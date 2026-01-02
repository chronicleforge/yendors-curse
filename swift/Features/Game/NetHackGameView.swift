import SwiftUI
import SceneKit
import Combine

struct NetHackGameView: View {
    var gameManager: NetHackGameManager
    @Environment(DeathFlowController.self) private var deathFlow
    @StateObject private var overlayManager = GameOverlayManager()
    @StateObject private var feedbackEngine = FeedbackEngine.shared
    private var commandGroupManager = CommandGroupManager.shared
    @ObservedObject private var menuRouter = MenuRouter.shared
    @State private var messages: [GameMessage] = []  // Changed from [String] for turn-based fading
    @State private var lastTurnCount: Int = 0
    @State private var selectedTile: (x: Int, y: Int)? = nil  // For SceneKitMapView
    // inspectModeActive moved to NetHackGameManager (fixes stale closure capture)
    @State private var inspectionResult: (tile: (x: Int, y: Int), messages: [String], screenPos: CGPoint)? = nil
    @State private var lastInspectionTime: TimeInterval = 0  // PERF: Debouncing for tile inspection
    @State private var lastTileTapTime: TimeInterval = 0  // PERF: Debouncing for tile taps (prevent queue overflow)

    // NEW: Tap Handler Chain (Strategy Pattern)
    @State private var tapHandlerChain = TileTapHandlerChain()

    // Character Status Sheet
    @State private var showCharacterStatus = false

    // Message Log Sheet (tap on notifications to open)
    @State private var showMessageLog = false

    init(gameManager: NetHackGameManager) {
        self.gameManager = gameManager
    }

    // PERF: Connect overlay manager to game manager for auto-inventory updates
    private func connectOverlayManager() {
        gameManager.overlayManager = overlayManager
    }

    // Helper property to access SceneKit view
    private var sceneKitMapView: some View {
        SceneKitMapView(
            mapState: gameManager.mapState,
            selectedTile: $selectedTile,
            onTileTap: handleTileTap,
            onSceneViewCreated: { scnView in
                ScreenshotService.shared.registerSceneView(scnView)
            }
        )
        .ignoresSafeArea()
    }

    var body: some View {
        // CLEAN LAYOUT ARCHITECTURE (SWIFTUI-L-002)
        // - Base: SceneKitMapView (fullscreen, z-index 0)
        // - Overlays: .overlay() with explicit alignment + zIndex
        // - No nested ZStack/GeometryReader (avoids layout pollution)

        SceneKitMapView(
            mapState: gameManager.mapState,
            selectedTile: $selectedTile,
            onTileTap: handleTileTap,
            onSceneViewCreated: { scnView in
                ScreenshotService.shared.registerSceneView(scnView)
            }
        )
        .ignoresSafeArea()  // ONLY place for ignoresSafeArea - keeps map fullscreen
        // FEEDBACK: Shake effect on damage
        .shake(trigger: feedbackEngine.shakeCount, intensity: feedbackEngine.shakeIntensity)
        .animation(.linear(duration: 0.25), value: feedbackEngine.shakeCount)

        // FEEDBACK: Damage flash overlay (red tint)
        .overlay {
            if feedbackEngine.damageFlashActive {
                Color.red.opacity(0.12)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: feedbackEngine.damageFlashActive)

        // ENVIRONMENT: Subtle color tint based on dungeon branch
        .overlay {
            let env = gameManager.mapState.currentEnvironment
            if env != .standard && env != .tutorial {
                Color(env.accentUIColor)
                    .opacity(env.accentOpacity * 1.5)  // Slightly stronger for full overlay
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .blendMode(.overlay)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: gameManager.mapState.currentEnvironment)

        // OVERLAY LAYER 1: Status Bar (status center, Exit+Turn right)
        .overlay(alignment: .top) {
            StatusBarOverlay(gameManager: gameManager)
                .zIndex(1)
        }

        // OVERLAY LAYER 2: Context Card (z-index 2)
        // IPHONE LANDSCAPE FIX: Position context card with proper safe area insets
        // NOTE: Old ContextOverlayCard removed - replaced by ContextActionsButton (horizontal FAB)

        // OVERLAY LAYER 3: Controls (z-index 3)
        // iPhone landscape: Dynamic Island is on LEFT side
        // Layout: Actions ABOVE Dynamic Island, Inspect BELOW it
        .overlay(alignment: .topLeading) {
            // Minimal left padding - as close to edge as possible
            let leftPadding: CGFloat = ScalingEnvironment.isPhone ? 8 : 24

            // Actions button - at top, left of Dynamic Island
            // iPhone: above Dynamic Island (50pt), iPad: lower (20pt, no notch)
            ContextActionsButton(gameManager: gameManager, overlayManager: overlayManager)
                .padding(.leading, leftPadding)
                .padding(.top, ScalingEnvironment.isPhone ? 50 : 20)
                .zIndex(3)
        }
        // Character Status + Inspect buttons removed from here - now in bottomControls
        .overlay(alignment: .bottom) {
            bottomControls
                .zIndex(3)
        }

        // OVERLAY LAYER 50: Inspection Result (z-index 50)
        .overlay(alignment: .center) {
            if let result = inspectionResult {
                InspectionOverlayCard(
                    tile: result.tile,
                    messages: result.messages,
                    screenPos: result.screenPos,
                    onDismiss: {
                        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                            inspectionResult = nil
                        }
                    }
                )
                .zIndex(50)
            }
        }

        // NOTE: Item Selection + Quantity Picker overlays moved AFTER EquipmentPanel for correct stacking

        // OVERLAY LAYER 78-79: Spell Selection
        .overlay(alignment: .center) {
            if overlayManager.showSpellSelection {
                ZStack {
                    // Dimming background
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            overlayManager.cancelSpellSelection()
                        }
                        .zIndex(78)

                    // Spell selection sheet
                    GeometryReader { geometry in
                        VStack {
                            Spacer()
                            SpellSelectionSheet(
                                spells: overlayManager.spells,
                                onSelect: { spell in overlayManager.handleSpellSelected(spell) },
                                onCancel: { overlayManager.cancelSpellSelection() }
                            )
                            .frame(maxHeight: 500)
                            .padding(.horizontal)
                            Spacer()
                        }
                    }
                    .zIndex(79)
                }
            }
        }

        // OVERLAY LAYER 80-81: Direction Picker (for directional spells)
        // Positioned bottom-left to overlay navigation control
        // Uses GeometryReader for proper Dynamic Island safe area handling
        .overlay(alignment: .bottomLeading) {
            if overlayManager.showDirectionPicker, let spell = overlayManager.selectedSpellForDirection {
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        // Dimming background (full screen)
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture {
                                overlayManager.cancelSpellSelection()
                            }
                            .zIndex(80)

                        // Direction picker - positioned over navigation control
                        // Use actual safe area insets (respects Dynamic Island in landscape)
                        DirectionPicker(
                            spell: spell,
                            onSelect: { direction in overlayManager.handleDirectionSelected(direction) },
                            onCancel: { overlayManager.cancelSpellSelection() }
                        )
                        .padding(.leading, max(geometry.safeAreaInsets.leading, padding))
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, padding))
                        .zIndex(81)
                    }
                }
                .ignoresSafeArea()
            }
        }

        // OVERLAY LAYER 80-81b: Action Direction Picker (for directional actions like Kick, Open, etc.)
        // Uses GeometryReader for proper Dynamic Island safe area handling
        .overlay(alignment: .bottomLeading) {
            if overlayManager.showActionDirectionPicker, let action = overlayManager.selectedActionForDirection {
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        // Dimming background (full screen)
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture {
                                overlayManager.cancelActionDirection()
                            }
                            .zIndex(80)

                        // Direction picker - positioned over navigation control
                        // Use actual safe area insets (respects Dynamic Island in landscape)
                        ActionDirectionPicker(
                            action: action,
                            onSelect: { direction in overlayManager.handleActionDirectionSelected(direction) },
                            onCancel: { overlayManager.cancelActionDirection() }
                        )
                        .padding(.leading, max(geometry.safeAreaInsets.leading, padding))
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, padding))
                        .zIndex(81)
                    }
                }
                .ignoresSafeArea()
            }
        }

        // OVERLAY LAYER 80-81c: Hand Picker (for ring equipping - left/right hand selection)
        .overlay(alignment: .center) {
            if overlayManager.showHandPicker {
                ZStack {
                    // Dimming background (full screen)
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            overlayManager.cancelHandSelection()
                        }
                        .zIndex(80)

                    // Hand picker - centered on screen
                    HandPicker(
                        onSelect: { hand in overlayManager.handleHandSelected(hand) },
                        onCancel: { overlayManager.cancelHandSelection() }
                    )
                    .zIndex(81)
                }
            }
        }

        // OVERLAY LAYER 86-87: Generic Menu (MenuRouter)
        .overlay(alignment: .center) {
            if menuRouter.isShowingMenu, let context = menuRouter.activeContext {
                ZStack {
                    // Dimming background
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // UX Spec: PICK_NONE and PICK_ONE allow tap-outside dismiss
                            // PICK_ANY requires explicit Cancel button (data loss risk)
                            switch context.pickMode {
                            case .none:
                                menuRouter.dismissMenu()
                            case .one:
                                // Tap outside = cancel (send empty selection)
                                menuRouter.completeMenu(with: [])
                            case .any:
                                // Require explicit Cancel button - ignore tap
                                break
                            }
                        }
                        .zIndex(ZIndex.layer(.itemSelection) - 1)

                    // Generic menu sheet - centered (ABOVE messages!)
                    GeometryReader { geometry in
                        menuRouter.view(for: context) { selections in
                            menuRouter.completeMenu(with: selections)
                        }
                        .frame(maxHeight: min(600, geometry.size.height * 0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity) // Center in container
                    }
                    .zIndex(ZIndex.layer(.itemSelection))
                }
            }
        }

        // OVERLAY LAYER 88-89: Skill Enhance Sheet (for #enhance command)
        .overlay(alignment: .center) { skillEnhanceOverlay }

        // OVERLAY LAYER 88-89: Chronicle Sheet (for #chronicle command)
        .overlay(alignment: .center) { chronicleOverlay }

        // OVERLAY LAYER 88-89: Conduct Sheet (for M-C command)
        .overlay(alignment: .center) { conductOverlay }

        // OVERLAY LAYER 98: Escape Warning Sheet (when trying to escape without amulet)
        .overlay(alignment: .center) { escapeWarningOverlay }

        // OVERLAY LAYER 99-100: Text Input Sheet (for genocide, polymorph, name, engrave custom)
        .overlay(alignment: .center) { textInputOverlay }

        // OVERLAY LAYER 85: Messages (ZIndex.messages)
        // Messages positioned TOP-RIGHT, aligned with Command Bar and status bar
        .overlay(alignment: .topTrailing) {
            if !messages.isEmpty {
                // Use same right padding as CommandGroupBar (54pt on iPhone)
                let rightPadding: CGFloat = ScalingEnvironment.isPhone ? 54 : padding

                messagesOverlay
                    .padding(.top, topPadding)
                    // Align right edge with Quick button and T:XX
                    .padding(.trailing, rightPadding)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(ZIndex.messages)
            }
        }

        // MODAL LAYER 5: 4-Quadrant Inventory (full-screen modal)
        .overlay(alignment: .center) {
            if overlayManager.activeOverlay == .inventory {
                FourQuadrantInventoryView(
                    gameManager: gameManager,
                    overlayManager: overlayManager,
                    sceneKitView: { sceneKitMapView }
                )
                .ignoresSafeArea()
                .zIndex(5)
            }
        }

        // MODAL LAYER: Equipment Panel (sliding side panel from right)
        // Premium equipment UI with swipe-to-dismiss and touch blocking
        .overlay {
            if showCharacterStatus {
                EquipmentPanelView(
                    isPresented: $showCharacterStatus,
                    statusManager: CharacterStatusManager.shared,
                    overlayManager: overlayManager
                )
            }
        }

        // MODAL LAYER: Item Selection (appears AFTER EquipmentPanel in code = renders ON TOP)
        .overlay(alignment: .center) {
            if overlayManager.showItemSelection, let context = overlayManager.itemSelectionContext {
                // Fetch ground items at player position (from live game state snapshot)
                let snapshot = NetHackBridge.shared.getGameStateSnapshot()
                let groundItems = ObjectBridgeWrapper.getObjectsAt(
                    x: Int32(snapshot.playerX),
                    y: Int32(snapshot.playerY)
                )

                // UnifiedSelectionSheet has built-in dimmer and tap-to-dismiss
                UnifiedSelectionSheet(
                    config: .fromItemContext(
                        context,
                        items: overlayManager.items,
                        groundItems: groundItems,
                        onSelect: { invlet in overlayManager.selectItem(invlet) },
                        onSelectGround: { objectID in overlayManager.selectGroundItem(objectID) }
                    ),
                    onDismiss: { overlayManager.cancelItemSelection() }
                )
            }
        }

        // MODAL LAYER: Quantity Picker (appears AFTER ItemSelection = renders ON TOP)
        .overlay(alignment: .center) {
            if overlayManager.showQuantityPicker,
               let item = overlayManager.quantityPickerItem,
               let action = overlayManager.quantityPickerAction {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { overlayManager.hideQuantityPicker() }

                    QuantityPickerView(
                        item: item,
                        action: action,
                        maxQuantity: Int(overlayManager.quantityPickerMaxQuantity)
                    ) { selectedQuantity in
                        overlayManager.quantityPickerCompletion?(selectedQuantity)
                        overlayManager.hideQuantityPicker()
                    }
                    .frame(maxWidth: QuantityPickerTheme.popoverMaxWidth)
                }
            }
        }

        // Death transition animation (soul particles rising - plays DURING .animating phase)
        // DeathFlowController manages the phase, ContentView shows DeathScreenView in .showing phase
        .overlay {
            if deathFlow.isAnimationVisible {
                SelfContainedDeathTransition()
                    .ignoresSafeArea()
            }
        }

        // NOTE: Death screen is now shown by ContentView when deathFlow.phase == .showing
        // This keeps NetHackGameView focused on gameplay, ContentView handles top-level routing
        .overlay(alignment: .center) {
            if gameManager.exitingToMenu {
                ExitOverlayView(message: gameManager.exitMessage)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(ZIndex.exitOverlay)
            }
        }

        // Debug overlay (disabled by default)
        .overlay(alignment: .topLeading) {
            if false {  // Set to true for debug output
                debugOverlay
            }
        }

        // MODIFIERS: Global view configuration
        .preferredColorScheme(.dark)
        .onChange(of: gameManager.turnCount) { _, newTurn in
            guard newTurn != lastTurnCount else { return }
            overlayManager.closeOverlay()
            // Dismiss inspection overlay when turn changes (player took action)
            withAnimation(.spring(duration: 0.2, bounce: 0.15)) {
                inspectionResult = nil
            }
            lastTurnCount = newTurn
        }
        // NOTE: Removed auto-dismiss on inspectModeActive change
        // Overlay now stays visible until: turn changes, user taps X, or taps elsewhere
        // This enables one-time inspect: mode deactivates but result stays visible
        .onAppear {
            connectOverlayManager()
            setupTapHandlers()
            NetHackBridge.shared.signalSwiftReadyForMessages()
        }
        .onDisappear {
            ScreenshotService.shared.unregisterSceneView()
            Task { await gameManager.stopGame() }
        }
        .onKeyPress { press in
            guard press.key == .escape else { return handleKeyPress(press) }
            guard overlayManager.activeOverlay != .none else { return handleKeyPress(press) }
            overlayManager.closeOverlay()
            return .handled
        }
        // Character Status overlay (replaces old .sheet() modal)
        .sheet(isPresented: $overlayManager.showEngraveFlow) {
            EngraveFlowSheet(gameManager: gameManager)
                .environmentObject(overlayManager)
        }
        .sheet(isPresented: $overlayManager.showDiscoveries) {
            DiscoveriesView(gameManager: gameManager)
        }
        .sheet(isPresented: $overlayManager.showDungeonOverview) {
            DungeonOverviewSheet()
        }
        .sheet(isPresented: $overlayManager.showContainerPicker) {
            FloorContainerPicker(
                containers: overlayManager.floorContainers,
                onSelect: { overlayManager.selectFloorContainer($0) }
            )
        }
        .sheet(isPresented: $overlayManager.showContainerTransfer) {
            if let container = overlayManager.selectedFloorContainer {
                ContainerTransferView(container: container)
                    .environmentObject(overlayManager)
            }
        }
        .sheet(isPresented: $showMessageLog) {
            MessageLogView()
        }
        // NOTE: Generic Menu System uses overlay at lines 230-260 (not .sheet)
        // This allows custom animation, tap-outside behavior, and haptic feedback
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NetHackMessage"))) { notification in
            var messageText: String? = nil

            if let messageDict = notification.object as? [String: Any],
               let text = messageDict["message"] as? String {
                messageText = text
            } else if let text = notification.object as? String {
                messageText = text
            }

            guard let text = messageText else { return }

            guard let messageDict = notification.object as? [String: Any],
                  let category = messageDict["category"] as? String,
                  let attr = messageDict["attr"] as? Int else { return }

            // PERF: Don't use withAnimation for append - triggers expensive SwiftUI diff calculation
            // The message transition animation is handled by the .transition() modifier in messagesOverlay
            let attributes = GameMessage.MessageAttributes(fromBitmask: attr)
            let newMessage = GameMessage(
                text: text,
                turnNumber: gameManager.turnCount,
                timestamp: Date(),
                count: 1,
                attributes: attributes,
                category: category
            )
            messages.append(newMessage)

            // Pickup haptic feedback (distinct from movement tap)
            // Detect autopickup messages: "a - item name", "$: gold", or "pick up" in text
            if UserPreferencesManager.shared.isAutopickupEnabled() {
                let lowercased = text.lowercased()
                let isPickupMessage = category == "ITEM" ||
                    lowercased.contains("pick up") ||
                    lowercased.contains("gold piece") ||
                    (text.count > 3 && text.dropFirst().hasPrefix(" - "))  // "a - item" pattern
                if isPickupMessage {
                    HapticManager.shared.pickup()
                }
            }

            // Store in history manager for fullscreen message log
            MessageHistoryManager.shared.addMessage(newMessage)

            // Trim old messages without animation (just data cleanup)
            if messages.count > 10 {
                messages.removeFirst()
            }
        }
    }

    // MARK: - Bottom Controls (D-Pad + Action Bar)

    private var bottomControls: some View {
        // LAYOUT: D-Pad (left) | Spacer | Character+Inspect | Commands (right)
        // LANDSCAPE: Dynamic Island is on LEFT side, need extra leading padding on iPhone
        // iPad: D-pad positioned further right for better thumb reach
        let leftPadding: CGFloat = ScalingEnvironment.isPhone ? 64 : 60
        // Reduced right padding to align with status bar T:XX element
        let rightPadding: CGFloat = ScalingEnvironment.isPhone ? 54 : padding

        return HStack(alignment: .bottom, spacing: 0) {
            // Left: Movement D-Pad
            let navSize = ScalingEnvironment.UIScale.navigationWheelSize(isPhone: ScalingEnvironment.isPhone)
            GestureNavigationControl(gameManager: gameManager)
                .frame(width: navSize, height: navSize)
                .padding(.leading, leftPadding)

            Spacer()

            // Center-right: Tool buttons (Inspect, Equip, Inventory) - left of command bar
            // Match CommandGroupBar spacing: 4pt (phone) / 8pt (iPad)
            HStack(spacing: ScalingEnvironment.isPhone ? 4 : 8) {
                // Inspect button - toggle inspect mode
                MagnifyingGlassButton(
                    isActive: Binding(
                        get: { gameManager.inspectModeActive },
                        set: { gameManager.inspectModeActive = $0 }
                    ),
                    onToggle: { HapticManager.shared.tap() }
                )

                // Equip button - opens Equipment overlay
                EquipButton {
                    showCharacterStatus = true
                }

                // Inventory button - opens Inventory overlay
                InventoryButton {
                    overlayManager.showInventory()
                }
            }
            .padding(.vertical, 6)
            .padding(.trailing, ScalingEnvironment.isPhone ? 16 : 24)  // Gap before command bar

            // Right: Command Group Bar (6 categories)
            CommandGroupBar(
                manager: commandGroupManager,
                gameManager: gameManager,
                overlayManager: overlayManager
            )
            .padding(.trailing, rightPadding)
        }
        // Bottom padding - command bar moved higher
        .padding(.bottom, ScalingEnvironment.isPhone ? 30 : padding)
    }

    // MARK: - Layout Helpers

    private var padding: CGFloat {
        ScalingEnvironment.UIScale.screenPadding(isPhone: ScalingEnvironment.isPhone)
    }

    private var topPadding: CGFloat {
        // Messages must appear BELOW status bar (which uses 59pt+ for Dynamic Island)
        ScalingEnvironment.isPhone ? 90 : 80
    }

    // MARK: - Skill Enhance Overlay
    @ViewBuilder
    private var skillEnhanceOverlay: some View {
        if overlayManager.showSkillEnhance {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { overlayManager.cancelSkillEnhance() }
                    .zIndex(88)

                SkillEnhanceSheet(
                    skills: overlayManager.skillEnhanceData.skills,
                    availableSlots: overlayManager.skillEnhanceData.slots,
                    onAdvance: { skill in overlayManager.handleSkillAdvance(skill) },
                    onCancel: { overlayManager.cancelSkillEnhance() }
                )
                .zIndex(89)
            }
        }
    }

    // MARK: - Chronicle Overlay
    @ViewBuilder
    private var chronicleOverlay: some View {
        if overlayManager.showChronicle {
            ChronicleView(
                entries: overlayManager.chronicleEntries,
                onDismiss: {
                    overlayManager.showChronicle = false
                }
            )
            .zIndex(89)
        }
    }

    // MARK: - Conduct Overlay
    @ViewBuilder
    private var conductOverlay: some View {
        if overlayManager.showConduct, let conductData = overlayManager.conductData {
            ConductView(
                conductData: conductData,
                onDismiss: {
                    overlayManager.showConduct = false
                }
            )
            .zIndex(89)
        }
    }

    // MARK: - Escape Warning Overlay
    @ViewBuilder
    private var escapeWarningOverlay: some View {
        if overlayManager.showEscapeWarning {
            ZStack {
                // Dimming background - darker for dramatic effect (game-ending decision)
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    // No tap-to-dismiss - this is a critical decision
                    .zIndex(ZIndex.below(.escapeWarning))

                EscapeWarningSheet { confirmed in
                    overlayManager.confirmEscape(confirmed)
                }
                .zIndex(ZIndex.escapeWarning)
            }
        }
    }

    // MARK: - Text Input Overlay (for genocide, polymorph, wish, name, engrave custom)
    @ViewBuilder
    private var textInputOverlay: some View {
        if overlayManager.showTextInput, let context = overlayManager.textInputContext {
            // UnifiedSelectionSheet: Shows suggestions + keyboard fallback for custom input
            UnifiedSelectionSheet(
                config: .fromTextContext(context) { text in
                    context.onSubmit(text)
                },
                onDismiss: {
                    overlayManager.cancelTextInput()
                }
            )
            .zIndex(100)  // Above all other overlays
        }
    }

    private var messagesOverlay: some View {
        let fontSize = ScalingEnvironment.UIScale.messageFontSize(isPhone: ScalingEnvironment.isPhone)
        let maxWidth = ScalingEnvironment.UIScale.messageMaxWidth(isPhone: ScalingEnvironment.isPhone)
        let hPadding: CGFloat = ScalingEnvironment.isPhone ? 10 : 16
        let vPadding: CGFloat = ScalingEnvironment.isPhone ? 6 : 8

        return Button {
            showMessageLog = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Show last 3 messages with turn-based opacity fading and attribute styling
                ForEach(messages.suffix(3)) { message in
                    Text(message.text)
                        .font(.system(size: fontSize))
                        .fontWeight(message.fontWeight)
                        .italic(message.attributes.isItalic)
                        .underline(message.attributes.isUnderline)
                        .foregroundColor(message.textColor())
                        .frame(maxWidth: maxWidth, alignment: .leading)  // Max width with left alignment
                        .padding(.horizontal, hPadding)
                        .padding(.vertical, vPadding)
                        .background(message.backgroundColor ?? Color.black.opacity(0.75))
                        .cornerRadius(8)
                        .opacity(message.opacity(currentTurn: gameManager.turnCount))
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .frame(alignment: .topLeading)  // Top-right corner, left-aligned text
        }
        .buttonStyle(.plain)
        // PERF: Use .animation() on view instead of withAnimation{} on state change
        // This animates transitions asynchronously without blocking state updates
        .animation(.spring(duration: 0.3, bounce: 0.15), value: messages.count)
    }

    private var debugOverlay: some View {
        VStack {
            HStack {
                ScrollView {
                    Text(gameManager.gameOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(8)
                }
                .frame(width: 250, height: 150)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding()
                Spacer()
            }
            Spacer()
        }
    }

    // determineMessageType removed - GameMessage now has its own type property

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Handle arrow keys for movement
        switch press.key {
        case .upArrow:
            gameManager.moveUp()
            return .handled
        case .downArrow:
            gameManager.moveDown()
            return .handled
        case .leftArrow:
            gameManager.moveLeft()
            return .handled
        case .rightArrow:
            gameManager.moveRight()
            return .handled
        default:
            // Handle character keys
            if let char = press.characters.first {
                switch char {
                case ".":
                    // Period for wait/skip turn
                    gameManager.wait()
                    return .handled
                default:
                    // Let other keys pass through
                    return .ignored
                }
            }
            return .ignored
        }
    }

    // MARK: - Touch Handlers

    private func handleTileTap(x: Int, y: Int) {
        // PERF FIX: Debounce tile taps to prevent queue overflow
        // RCA: Multiple taps in quick succession caused async queue bottleneck
        // Solution: Enforce 300ms minimum between tile taps
        let now = CACurrentMediaTime()
        guard now - lastTileTapTime >= 0.3 else {
            return  // Debounced - ignore duplicate tap
        }
        lastTileTapTime = now

        // Get tile from map state
        let tile = gameManager.mapState.tiles[safe: y]?[safe: x] ?? nil

        // Dispatch to handler chain (Strategy Pattern)
        tapHandlerChain.handleTap(x: x, y: y, tile: tile, gameManager: gameManager)
    }

    private func setupTapHandlers() {
        // CRITICAL FIX: Reset chain to prevent duplicate handlers on re-appear
        tapHandlerChain = TileTapHandlerChain()

        // Configure TravelQueueManager with game manager reference
        // This enables queued travel destinations during active travel
        TravelQueueManager.shared.configure(gameManager: gameManager)

        // Register handlers in priority order
        // CRITICAL FIX: InspectHandler accesses gameManager.inspectModeActive directly (no stale closure!)
        let inspectHandler = InspectTapHandler(
            inspectTile: { [self] x, y in await self.inspectTile(x: x, y: y) }
        )
        tapHandlerChain.register(inspectHandler)

        tapHandlerChain.register(AutoTravelTapHandler())
    }

    private func inspectTile(x: Int, y: Int) async {
        // INSTANT VISUAL FEEDBACK - Show loading state immediately (no wait!)
        // This makes the tap feel responsive even if C call takes time
        let screenPos = tileToScreenPosition(x: x, y: y)

        // CRITICAL UX: Haptic FIRST - before any debounce or async work
        // User needs instant confirmation that tap was registered
        HapticManager.shared.selection()

        // Show "Loading..." placeholder instantly (no animation delay)
        // MUST dispatch to Main Thread for UI updates (we're on background thread now!)
        DispatchQueue.main.async {
            self.inspectionResult = (tile: (x: x, y: y), messages: ["Inspecting..."], screenPos: screenPos)
        }

        // DEBOUNCE: Only prevent expensive C calls, not visual feedback
        // Reduced from 300ms to 50ms - 300ms blocked intentional follow-up taps!
        // 50ms is minimum to prevent accidental double-taps (human finger can't tap faster)
        let now = CACurrentMediaTime()
        guard now - lastInspectionTime >= 0.05 else {
            return  // Debounced
        }
        lastInspectionTime = now

        // Get actual description from NetHack (async, thread-safe call)
        // Call async version - properly serialized through NetHackSerialExecutor
        let description = await gameManager.examineTileAsync(x: x, y: y)

        guard let description = description else {
            // Update placeholder with "nothing here" message - MUST use Main Thread for UI
            DispatchQueue.main.async {
                self.inspectionResult = (tile: (x: x, y: y), messages: ["Nothing to see here."], screenPos: screenPos)
                // One-time use: deactivate inspect mode after inspection
                self.gameManager.inspectModeActive = false
            }
            return
        }

        // Clean up description (remove trailing newlines, split into lines if multiline)
        let cleanDescription = description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let messages = cleanDescription.split(separator: "\n").map { String($0) }

        // Update with actual description - MUST use Main Thread for UI updates
        DispatchQueue.main.async {
            self.inspectionResult = (tile: (x: x, y: y), messages: messages, screenPos: screenPos)
            // One-time use: deactivate inspect mode after inspection
            self.gameManager.inspectModeActive = false
        }
    }

    private func tileToScreenPosition(x: Int, y: Int) -> CGPoint {
        // Use same coordinate conversion as TileActionOverlay
        // Get screen dimensions from UIScreen for now
        let screenSize = UIScreen.main.bounds.size
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2

        let sceneKitTileSize: CGFloat = CGFloat(kSceneKitTileSize)
        let orthographicScale: CGFloat = 25
        let verticalUnitsVisible = orthographicScale * 2
        let pixelsPerUnit = screenSize.height / verticalUnitsVisible
        let tileSize = sceneKitTileSize * pixelsPerUnit

        let offsetX = CGFloat(x - gameManager.mapState.playerX) * tileSize
        let offsetY = CGFloat(y - gameManager.mapState.playerY) * tileSize

        return CGPoint(x: centerX + offsetX, y: centerY + offsetY)
    }

}

// MARK: - InspectModeDelegate Implementation
// Note: Cannot use protocol conformance because NetHackGameView is a struct, not a class
// InspectModeDelegate uses weak references which require AnyObject
// Solution: InspectTapHandler directly captures @State var inspectModeActive and calls inspectTile via closure

// MARK: - DEPRECATED - Tile Action Overlay removed, replaced by TileTapHandler chain
// Old yellow rectangle + travel button overlay - now uses Strategy Pattern in TileTapHandler.swift

// MARK: - Command Menu View
struct CommandMenuView: View {
    let gameManager: NetHackGameManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List(GameCommand.allCases, id: \.self) { command in
                Button(action: {
                    gameManager.sendCommand(command.rawValue)
                    dismiss()
                }) {
                    HStack {
                        Text(command.description)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(command.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Commands")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .presentationBackground(.ultraThinMaterial)
        }
    }
}

// MARK: - Exit Overlay View

struct ExitOverlayView: View {
    let message: String

    var body: some View {
        UnifiedLoadingView(state: .exiting(message))
    }
}

// MARK: - 4-Quadrant Inventory Layout
/// Responsive 4-quadrant layout when inventory opens
///
/// SWIFTUI REFERENCES:
/// - SWIFTUI-L-002: ZStack for independent overlays
/// - SWIFTUI-A-001: Spring animations (bounce 0.15-0.2)
/// - SWIFTUI-A-003: Combined transitions (scale + opacity)
/// - SWIFTUI-A-009: Reduce Motion accessibility (MANDATORY)
/// - SWIFTUI-HIG-001: Animation duration 300-400ms
///
/// Layout:
/// ┌─────────┬─────────┐
/// │  Game   │         │
/// │ (scaled)│ Inven-  │
/// ├─────────┤ tory    │
/// │ Status/ │ (full   │
/// │ Actions │ height) │
/// └─────────┴─────────┘

struct FourQuadrantInventoryView<GameView: View>: View {
    let gameManager: NetHackGameManager
    let overlayManager: GameOverlayManager
    let sceneKitView: () -> GameView

    // Accessibility - SWIFTUI-A-009 (MANDATORY)
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Device detection for adaptive layout
    private let isPhone = ScalingEnvironment.isPhone

    // Item selection state (shared between inventory and actions panel)
    @State private var selectedItem: NetHackItem? = nil
    @State private var searchText: String = ""
    @State private var selectedCategory: ItemCategory? = nil

    // Animation - SWIFTUI-A-001 (PERF: Reduced duration for snappier close)
    // RCA: 0.4s duration caused menu close lag
    // Solution: 0.15s is fast enough to feel instant, smooth enough to not jar
    private var quadrantAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.1)
    }

    @State private var isPresented = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent backdrop
                Color.black.opacity(isPresented ? 0.3 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeWithAnimation()
                    }

                // Unified layout: 4-Quadrant Grid for both iPhone and iPad
                // Zoom + fade for smooth transition
                iPadQuadrantLayout(geometry: geometry)
                    .scaleEffect(isPresented ? 1.0 : 1.8, anchor: .topLeading)
                    .opacity(isPresented ? 1.0 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.4, bounce: 0.12)) {
                isPresented = true
            }
        }
    }

    private func closeWithAnimation() {
        withAnimation(.spring(duration: 0.3, bounce: 0.08)) {
            isPresented = false
        }
        // Delay actual close until animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            overlayManager.closeOverlay()
        }
    }

    // MARK: - Inventory Layout (4-Quadrant for all devices)
    @ViewBuilder
    private func iPadQuadrantLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // LEFT COLUMN (50% width)
            VStack(spacing: 0) {
                // TOP-LEFT: Live Game Preview (50% height)
                // PERF: Render at target size to avoid expensive scale compositing
                ZStack {
                    // Background
                    Color.black

                    // PERF: Render at target size (avoids full render + scale)
                    sceneKitView()
                        .frame(
                            width: geometry.size.width * 0.5,
                            height: geometry.size.height * 0.5
                        )
                        .allowsHitTesting(false)
                }
                .frame(height: geometry.size.height * 0.5)
                .clipShape(Rectangle())
                .contentShape(Rectangle())  // Make entire area tappable
                .onTapGesture {
                    closeWithAnimation()
                }

                // BOTTOM-LEFT: Item Actions Panel (50% height)
                ItemActionsPanel(
                    gameManager: gameManager,
                    selectedItem: $selectedItem,
                    overlayManager: overlayManager
                )
                    .frame(height: geometry.size.height * 0.5)
                    // SWIFTUI-A-003: Combined transition for "pop" effect
                    .transition(AnyTransition.scale(scale: 0.85).combined(with: .opacity))
            }
            .frame(width: geometry.size.width * 0.5)

            // RIGHT COLUMN: Inventory List only (100% height)
            PlayerInventoryPanel(
                items: overlayManager.items,
                searchText: $searchText,
                selectedCategory: $selectedCategory,
                selectedContainer: .constant(nil),  // No container support in 4-quadrant
                selectedItem: $selectedItem,
                draggedItem: .constant(nil)  // No drag-drop in 4-quadrant
            )
            .environmentObject(overlayManager)
            .background(Color.black)  // Solid background (no transparency)
            .frame(width: geometry.size.width * 0.5)
            // SWIFTUI-A-003: Combined transition for "pop" effect
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}

// MARK: - Item Actions Panel
/// Bottom-left panel showing actions for selected item
struct ItemActionsPanel: View {
    let gameManager: NetHackGameManager
    @Binding var selectedItem: NetHackItem?
    @ObservedObject var overlayManager: GameOverlayManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.verticalSizeClass) var verticalSizeClass

    // Portrait detection
    private var isPortrait: Bool {
        verticalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (compact)
            HStack {
                Text(selectedItem != nil ? "Item Actions" : "Select Item")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gruvboxForeground)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gruvboxBackground.opacity(0.95))

            Divider()
                .background(Color.gruvboxGray.opacity(0.3))

            // Content
            ScrollView {
                if let item = selectedItem {
                    // Item-specific actions (grid layout)
                    itemActionsGrid(for: item)
                        .padding()
                } else {
                    // Empty state
                    emptyStateSection
                        .padding()
                }
            }
            .background(Color.black.opacity(0.9))
        }
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.point.right.fill")
                .font(.system(size: 32))
                .foregroundColor(.gray.opacity(0.5))
                .padding(.top, 20)

            Text("Select an item")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Tap any item in your inventory to see available actions")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Item Actions Grid

    private func itemActionsGrid(for item: NetHackItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Item info (compact)
            HStack(spacing: 8) {
                Image(systemName: item.category.icon)
                    .font(.callout)
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(item.category.color.opacity(0.2))
                            .overlay(
                                Circle()
                                    .strokeBorder(item.category.color.opacity(0.4), lineWidth: 1)
                            )
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.fullName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gruvboxForeground)
                        .lineLimit(1)

                    Text(item.category.rawValue.capitalized)
                        .font(.system(size: 9))
                        .foregroundColor(.gruvboxGray)
                }

                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gruvboxBackground.opacity(0.5))
            )

            // Actions - compact inline capsules with FlowLayout
            let actions = getAllActions(for: item)

            FlowLayout(spacing: 6) {
                ForEach(actions, id: \.name) { action in
                    CompactActionCapsule(
                        action: action,
                        item: item,
                        gameManager: gameManager,
                        overlayManager: overlayManager
                    )
                }
            }
        }
    }

    // MARK: - Get All Actions

    private func getAllActions(for item: NetHackItem) -> [ItemQuickAction] {
        var actions: [ItemQuickAction] = []

        // Primary action
        if let primaryAction = getPrimaryAction(for: item) {
            actions.append(primaryAction)
        }

        // Universal actions
        actions.append(ItemQuickAction(
            name: "Drop",
            command: "d",
            icon: "arrow.down.circle.fill",
            color: .gruvboxOrange,
            needsMenu: true,  // Uses getobj() - menu-based
            supportsQuantity: true  // Supports quantity selection
        ))

        actions.append(ItemQuickAction(
            name: "Throw",
            command: "t",
            icon: "arrow.up.forward.circle.fill",
            color: .gruvboxYellow,
            needsMenu: true,  // Uses getobj() - menu-based
            supportsQuantity: true  // Supports quantity selection
        ))

        return actions
    }

    // MARK: - Get Primary Action

    private func getPrimaryAction(for item: NetHackItem) -> ItemQuickAction? {
        guard !item.isContainer else { return nil }

        switch item.category {
        case .food:
            return ItemQuickAction(
                name: "Eat",
                command: "e",
                icon: "fork.knife",
                color: .gruvboxGreen,
                needsMenu: false,  // Uses floorfood→yn_function (atomic works)
                supportsQuantity: false  // NetHack eats one item at a time (no count allowed)
            )
        case .potions:
            return ItemQuickAction(
                name: "Quaff",
                command: "q",
                icon: "drop.fill",
                color: .gruvboxMagenta,
                needsMenu: false,  // Uses yn_function (atomic works)
                supportsQuantity: false  // NetHack drinks one potion at a time (no count allowed)
            )
        case .armor:
            if item.properties.isWorn {
                return ItemQuickAction(
                    name: "Remove",
                    command: "T",
                    icon: "shield.slash.fill",
                    color: .gruvboxOrange,
                    needsMenu: true,  // Uses getobj() - menu-based
                    supportsQuantity: false  // Armor is worn/removed one at a time
                )
            } else {
                return ItemQuickAction(
                    name: "Wear",
                    command: "W",
                    icon: "shield.fill",
                    color: .gruvboxBlue,
                    needsMenu: true,  // Uses getobj() - menu-based
                    supportsQuantity: false  // Armor is worn one at a time
                )
            }
        case .weapons:
            guard !item.properties.isWielded else { return nil }
            return ItemQuickAction(
                name: "Wield",
                command: "w",
                icon: "hand.raised.fill",
                color: .gruvboxRed,
                needsMenu: true,  // Uses getobj() - menu-based
                supportsQuantity: false  // Weapons are wielded one at a time
            )
        case .wands:
            return ItemQuickAction(
                name: "Zap",
                command: "z",
                icon: "bolt.fill",
                color: .gruvboxYellow,
                needsMenu: true,  // Uses getobj() - menu-based
                supportsQuantity: false  // Wands are zapped individually
            )
        case .tools:
            return ItemQuickAction(
                name: "Apply",
                command: "a",
                icon: "wrench.fill",
                color: .gruvboxOrange,
                needsMenu: true,  // Uses getobj() - menu-based
                supportsQuantity: false  // Tools are applied individually
            )
        case .scrolls, .spellbooks:
            return ItemQuickAction(
                name: "Read",
                command: "r",
                icon: "doc.text.fill",
                color: .gruvboxYellow,
                needsMenu: true,  // Uses getobj() - menu-based
                supportsQuantity: false  // NetHack reads one scroll at a time (no count allowed)
            )
        case .rings, .amulets:
            if item.properties.isWorn {
                return ItemQuickAction(
                    name: "Remove",
                    command: "R",
                    icon: "circle.slash.fill",
                    color: .gruvboxOrange,
                    needsMenu: true,  // Uses getobj() - menu-based
                    supportsQuantity: false  // Accessories are removed one at a time
                )
            } else {
                return ItemQuickAction(
                    name: "Put On",
                    command: "P",
                    icon: "circle.fill",
                    color: .gruvboxCyan,
                    needsMenu: true,  // Uses getobj() - menu-based
                    supportsQuantity: false  // Accessories are put on one at a time
                )
            }
        default:
            return nil
        }
    }
}

// MARK: - Item Grid Action Card (Grid-optimized)

struct ItemGridActionCard: View {
    let action: ItemQuickAction
    let item: NetHackItem
    let gameManager: NetHackGameManager
    let overlayManager: GameOverlayManager

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: executeAction) {
            VStack(spacing: 5) {
                // Icon with subtle accent circle (compact)
                ZStack {
                    Circle()
                        .fill(action.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(action.color.opacity(0.4), lineWidth: 1)
                        )

                    Image(systemName: action.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }

                // Action name
                Text(action.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gruvboxForeground)
                    .lineLimit(1)

                // Command hint (subtle)
                Text(action.command)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(action.color.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(action.color.opacity(0.15))
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gruvboxBackground.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(action.color.opacity(0.2), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.2),
            value: isPressed
        )
    }

    private func executeAction() {
        isPressed = true

        // Haptic feedback
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        #endif

        // INVENTORY ACTION FIX: Avoid double-selection when acting on items from inventory
        //
        // Problem: User selects item from inventory → chooses action (e.g., Drop) → gets asked to select item again
        // Root Cause: NetHack's getobj() expects either a command queue or user input, not both
        //
        // Solution: When item is pre-selected from inventory, send both command and item letter directly.
        // This mimics NetHack's internal command queue behavior where itemactions_pushkeys()
        // queues both the command ('d') and item letter ('a') together.
        //
        // For stacked items (quantity > 1), we show a modern touch-optimized quantity picker
        // instead of NetHack's text-based "How many?" prompt.
        //
        // See claude-files/NETHACK_INVENTORY_DROP_RESEARCH.md for detailed NetHack source analysis

        // Debug: Log action details
        print("[QUANTITY_PICKER] executeAction called:")
        print("  - Action: \(action.name) (command: \(action.command))")
        print("  - Item: \(item.name) (invlet: \(item.invlet), quantity: \(item.quantity))")
        print("  - supportsQuantity: \(action.supportsQuantity)")

        // Guard: Single item or action doesn't support quantity - send command directly
        guard action.supportsQuantity && item.quantity > 1 else {
            print("[QUANTITY_PICKER] Single item or no quantity support - sending direct command")
            let command = "\(action.command)\(item.invlet)"
            gameManager.sendCommand(command)

            // Close inventory after action - INSTANT for better UX
            // RCA: 0.2s delay made UI feel sluggish
            overlayManager.closeOverlay()

            // Reset pressed state after a frame
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isPressed = false
            }
            return
        }

        // Action supports quantity and item has quantity > 1 - show quantity picker
        // Create a simple InventoryItem wrapper for the quantity picker
        var inventoryItem = InventoryItem()
        inventoryItem.invlet = Int8(item.invlet.asciiValue ?? 0)
        inventoryItem.quantity = Int32(item.quantity)

        // Allocate and copy name string
        let nameStr = item.name
        nameStr.withCString { cStr in
            let length = strlen(cStr) + 1
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(length))
            strcpy(buffer, cStr)
            inventoryItem.name = buffer  // Keep as UnsafeMutablePointer
        }

        // Convert ItemQuickAction to NetHackAction
        let nethackAction = NetHackAction(
            name: action.name,
            command: action.command,
            icon: action.icon,
            category: .items,  // Default category for item actions
            description: "Perform \(action.name) on \(item.name)",
            requiresDirection: false,
            requiresTarget: false,
            supportsQuantity: action.supportsQuantity
        )

        // Show quantity picker
        print("[QUANTITY_PICKER] Showing quantity picker for stacked item")
        print("  - inventoryItem.quantity: \(inventoryItem.quantity)")
        print("  - maxQuantity: \(item.quantity)")

        overlayManager.showQuantityPicker(
            for: inventoryItem,
            action: nethackAction,
            maxQuantity: item.quantity
        ) { selectedQuantity in
            print("[QUANTITY_PICKER] Completion called with quantity: \(selectedQuantity ?? -1)")
            // Free the allocated name buffer
            if let namePtr = inventoryItem.name {
                namePtr.deallocate()
            }

            guard let quantity = selectedQuantity else {
                // User cancelled - do nothing
                return
            }

            // Send command with selected quantity
            // NetHack format: command + quantity + invlet (e.g., "d2d" to drop 2 of item 'd')
            let command = "\(action.command)\(quantity)\(item.invlet)"
            print("[QUANTITY_PICKER] Sending NetHack command: '\(command)'")
            gameManager.sendCommand(command)

            // Close inventory after action
            overlayManager.closeOverlay()
        }

        // Reset pressed state after a frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isPressed = false
        }
    }
}

// MARK: - Compact Action Capsule (inline, horizontal)
struct CompactActionCapsule: View {
    let action: ItemQuickAction
    let item: NetHackItem
    let gameManager: NetHackGameManager
    let overlayManager: GameOverlayManager

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: executeAction) {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white)

                Text(action.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(action.color.opacity(0.85))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15),
            value: isPressed
        )
    }

    private func executeAction() {
        isPressed = true

        // Haptic feedback
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        #endif

        // Guard: Single item or action doesn't support quantity - send command directly
        guard action.supportsQuantity && item.quantity > 1 else {
            let command = "\(action.command)\(item.invlet)"
            gameManager.sendCommand(command)
            overlayManager.closeOverlay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isPressed = false
            }
            return
        }

        // Action supports quantity and item has quantity > 1 - show quantity picker
        var inventoryItem = InventoryItem()
        inventoryItem.invlet = Int8(item.invlet.asciiValue ?? 0)
        inventoryItem.quantity = Int32(item.quantity)

        // Copy item name
        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: item.name.count + 1)
        _ = item.name.withCString { source in
            strcpy(nameBuffer, source)
        }
        inventoryItem.name = nameBuffer

        // Create NetHack action wrapper
        let nethackAction = NetHackAction(
            id: UUID().uuidString,
            name: action.name,
            command: action.command,
            icon: action.icon,
            category: .items,
            description: "Quantity action for \(item.name)"
        )

        overlayManager.showQuantityPicker(
            for: inventoryItem,
            action: nethackAction,
            maxQuantity: item.quantity
        ) { selectedQuantity in
            if let namePtr = inventoryItem.name {
                namePtr.deallocate()
            }

            guard let quantity = selectedQuantity else { return }

            let command = "\(action.command)\(quantity)\(item.invlet)"
            gameManager.sendCommand(command)
            overlayManager.closeOverlay()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isPressed = false
        }
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
                )
        )
        // SWIFTUI-HIG: Minimum touch target
        .frame(minHeight: 44)
    }
}

// MARK: - Quick Action Row Component

struct QuickActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Button(action: {
            HapticManager.shared.buttonPress()
            action()
        }) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(color.opacity(0.15))
                    )

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .contentShape(Rectangle())  // SWIFTUI-M-003
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)  // SWIFTUI-A-001
        .animation(
            reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15),
            value: isPressed
        )  // SWIFTUI-A-009
        .simultaneousGesture(  // SWIFTUI-G-003
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        // SWIFTUI-HIG: Minimum touch target
        .frame(minHeight: 44)
    }
}

struct NetHackGameView_Previews: PreviewProvider {
    static var previews: some View {
        NetHackGameView(gameManager: NetHackGameManager())
    }
}