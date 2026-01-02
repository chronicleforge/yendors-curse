import SwiftUI

// MARK: - Engrave Tool Model

/// Represents a tool that can be used for engraving
struct EngraveTool: Identifiable, Equatable {
    let id: String
    let name: String
    let invlet: Character
    let icon: String
    let description: String
    let isPermanent: Bool
    let toolCategory: ToolType

    /// Tool categories for visual grouping and color coding
    enum ToolType: Equatable {
        case finger
        case wand
        case athame
        case weapon
        case gem
        case marker
        case ring
        case other
    }

    /// Finger - always available, makes dust engravings
    static let finger = EngraveTool(
        id: "finger",
        name: "Finger",
        invlet: "-",
        icon: "hand.point.up.fill",
        description: "Dust (fades)",
        isPermanent: false,
        toolCategory: .finger
    )

    /// Factory method for any inventory item
    static func fromItem(_ item: NetHackItem) -> EngraveTool {
        let toolType: ToolType
        let icon: String
        let description: String
        let isPermanent: Bool

        switch item.category {
        case .wands:
            toolType = .wand
            icon = "wand.and.stars"
            description = "Permanent burn"
            isPermanent = true

        case .weapons:
            let isAthame = item.cleanName.lowercased().contains("athame")
            toolType = isAthame ? .athame : .weapon
            icon = isAthame ? "moon.stars" : "scissors"
            description = isAthame ? "Carve (no wear)" : "Scratch (dulls)"
            isPermanent = true

        case .gems:
            toolType = .gem
            icon = "diamond"
            description = "Scratch (hard)"
            isPermanent = true

        case .rings:
            toolType = .ring
            icon = "circle.hexagongrid"
            description = "Scratch"
            isPermanent = true

        case .tools:
            let lowerName = item.cleanName.lowercased()
            if lowerName.contains("magic marker") {
                toolType = .marker
                icon = "pencil.tip"
                description = "Ink (uses charges)"
                isPermanent = true
            } else {
                // Towel - can wipe, not really engrave
                toolType = .other
                icon = "rectangle.portrait"
                description = "Wipe dust"
                isPermanent = false
            }

        default:
            toolType = .other
            icon = "questionmark"
            description = "Unknown"
            isPermanent = false
        }

        return EngraveTool(
            id: String(item.invlet),
            name: item.cleanName,
            invlet: item.invlet,
            icon: icon,
            description: description,
            isPermanent: isPermanent,
            toolCategory: toolType
        )
    }
}

/// EngraveFlowSheet - Multi-tier engraving system modal
///
/// Features:
/// - Context detection (low HP emergency, existing Elbereth)
/// - Quick phrases for combat speed (Elbereth < 1 sec)
/// - Tool selector for wands/athames
/// - Custom engraving text
///
/// Design Philosophy:
/// - **Combat First**: Emergency Elbereth must be reachable in < 1 second
/// - **Progressive Disclosure**: Quick phrases first, tools as optional
/// - **Context Awareness**: UI adapts based on player HP and floor state
struct EngraveFlowSheet: View {
    let gameManager: NetHackGameManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @EnvironmentObject private var overlayManager: GameOverlayManager

    // MARK: - State

    @State private var isDismissing = false
    @State private var selectedPhrase: String? = nil
    @State private var selectedTool: EngraveTool = .finger
    @State private var showToolSelector: Bool = false
    @State private var isToolsExpanded: Bool = false

    // MARK: - Quick Phrases

    private let quickPhrases: [(text: String, icon: String, description: String)] = [
        ("Elbereth", "shield.lefthalf.filled", "Scares monsters (1 turn)"),
        ("X", "xmark.circle.fill", "Test mark (1 turn)"),
        ("Test", "magnifyingglass.circle.fill", "Wand identification (1 turn)")
    ]

    // MARK: - Tool Categories (Hybrid Smart Defaults)

    /// Primary tools: Finger + Wands (always visible in Tier 1)
    private var primaryTools: [EngraveTool] {
        let wands = overlayManager.items
            .filter { $0.category == .wands }
            .map { EngraveTool.fromItem($0) }
        return [.finger] + wands
    }

    /// Secondary tools: Everything else (shown in Tier 2 expansion)
    private var secondaryTools: [EngraveTool] {
        overlayManager.items
            .filter { $0.canEngrave && !$0.isPrimaryEngraveTool }
            .map { EngraveTool.fromItem($0) }
    }

    /// Whether to show "More Tools..." button
    private var hasSecondaryTools: Bool {
        !secondaryTools.isEmpty
    }

    /// Count for badge on "More Tools..." button
    private var secondaryToolCount: Int {
        secondaryTools.count
    }

    /// Check if any tools besides finger are available
    private var hasWands: Bool {
        primaryTools.count > 1
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background dimmer
            backgroundDimmer

            // Main modal container
            modalContainer
                .frame(maxWidth: 600)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
                .padding(40)
                .opacity(isDismissing ? 0 : 1)
                .offset(y: isDismissing ? 100 : 0)
                .animation(
                    reduceMotion ? nil : AnimationConstants.modalTransition,
                    value: isDismissing
                )
        }
        .ignoresSafeArea()
    }

    // MARK: - Background Dimmer

    @ViewBuilder
    private var backgroundDimmer: some View {
        Color.black
            .opacity(isDismissing ? 0 : 0.8)
            .ignoresSafeArea()
            .onTapGesture {
                dismissView()
            }
            .animation(
                reduceMotion ? nil : AnimationConstants.modalTransition,
                value: isDismissing
            )
    }

    // MARK: - Modal Container

    @ViewBuilder
    private var modalContainer: some View {
        VStack(spacing: 0) {
            // Header
            modalHeader

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Emergency Elbereth (if low HP)
                    if isLowHP {
                        emergencyElberethButton
                    }

                    // Already on Elbereth?
                    if let existingText = getCurrentEngraving(), existingText.lowercased().contains("elbereth") {
                        refreshElberethButton
                    }

                    // Tool Selector (if wands available)
                    if hasWands {
                        toolSelectorSection
                    }

                    // Quick Phrases Section
                    quickPhrasesSection

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)

                        Text("OR")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 12)

                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 20)

                    // More Options (Phase 2: Tool selector)
                    moreOptionsButton
                }
                .padding(.vertical, 20)
            }
            .frame(maxHeight: 500)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var modalHeader: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "pencil.tip.crop.circle.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text("Engrave")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Write on the dungeon floor")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Close Button
            closeButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(height: 70)
        .background(Color.black.opacity(0.4))
    }

    @ViewBuilder
    private var closeButton: some View {
        Button(action: {
            dismissView()
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .frame(width: 54, height: 54)
        .accessibilityLabel("Close engraving menu")
    }

    // MARK: - Emergency Elbereth

    @ViewBuilder
    private var emergencyElberethButton: some View {
        Button(action: {
            engravePhrase("Elbereth")
        }) {
            HStack(spacing: 16) {
                // Icon with pulsing effect
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(Color.red, lineWidth: 2)
                        )
                        .modifier(PulsingModifier(isActive: !reduceMotion))

                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("EMERGENCY: Elbereth")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("You're low on health! Elbereth scares monsters")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.red, lineWidth: 2)
                    )
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 60)
        .accessibilityLabel("Emergency Elbereth - engrave protection, low health warning")
        .accessibilityHint("Tap to engrave Elbereth immediately, scares monsters")
    }

    // MARK: - Refresh Elbereth

    @ViewBuilder
    private var refreshElberethButton: some View {
        Button(action: {
            engravePhrase("Elbereth")
        }) {
            HStack(spacing: 16) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Re-engrave Elbereth")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Refresh fading protection")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.2))
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 50)
        .accessibilityLabel("Re-engrave Elbereth")
        .accessibilityHint("Refresh existing Elbereth to restore full protection")
    }

    // MARK: - Tool Selector Section

    @ViewBuilder
    private var toolSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundColor(.indigo)

                Text("Engrave With")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)

            // Primary Tools (Tier 1) - Always visible
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(primaryTools) { tool in
                        toolButton(tool)
                    }

                    // "More Tools..." button (if secondary tools exist)
                    if hasSecondaryTools {
                        moreToolsButton
                    }
                }
                .padding(.horizontal, 20)
            }

            // Secondary Tools (Tier 2) - Expanded section
            if isToolsExpanded && hasSecondaryTools {
                secondaryToolsSection
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }

    // MARK: - More Tools Button

    @ViewBuilder
    private var moreToolsButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isToolsExpanded.toggle()
            }
            HapticManager.shared.tap()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isToolsExpanded ? "chevron.up" : "tray.full")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.orange)

                Text(isToolsExpanded ? "Less" : "More...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                // Badge count when collapsed
                if !isToolsExpanded {
                    Text("(\(secondaryToolCount))")
                        .font(.system(size: 10))
                        .foregroundColor(.orange.opacity(0.8))
                }
            }
            .frame(width: 90, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isToolsExpanded
            ? "Hide additional tools"
            : "Show \(secondaryToolCount) more engraving tools like athames and gems")
    }

    // MARK: - Secondary Tools Section

    @ViewBuilder
    private var secondaryToolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundColor(.orange.opacity(0.8))

                Text("Additional Tools")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)

            // Horizontal scroll of secondary tools
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(secondaryTools) { tool in
                        toolButton(tool)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func toolButton(_ tool: EngraveTool) -> some View {
        let toolColor = toolCategoryColor(tool.toolCategory)
        let isSelected = selectedTool == tool

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTool = tool
            }
            HapticManager.shared.tap()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? .white : toolColor)

                Text(tool.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1)

                Text(tool.description)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(width: 90, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? toolColor.opacity(0.5) : toolColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? toolColor : toolColor.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Color based on tool category
    private func toolCategoryColor(_ category: EngraveTool.ToolType) -> Color {
        switch category {
        case .finger: return .cyan
        case .wand: return .indigo
        case .athame: return .purple
        case .weapon: return .red
        case .gem: return .yellow
        case .ring: return .orange
        case .marker: return .green
        case .other: return .gray
        }
    }

    // MARK: - Quick Phrases Section

    @ViewBuilder
    private var quickPhrasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header - shows selected tool
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)

                Text("Quick Phrases (with \(selectedTool.name.lowercased()))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)

            // Phrase buttons
            ForEach(quickPhrases, id: \.text) { phrase in
                // Skip Elbereth if already shown in emergency/refresh sections
                if phrase.text == "Elbereth" && (isLowHP || getCurrentEngraving()?.lowercased().contains("elbereth") == true) {
                    EmptyView()
                } else {
                    quickPhraseButton(phrase)
                }
            }
        }
    }

    @ViewBuilder
    private func quickPhraseButton(_ phrase: (text: String, icon: String, description: String)) -> some View {
        Button(action: {
            engravePhrase(phrase.text)
        }) {
            HStack(spacing: 16) {
                Image(systemName: phrase.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.cyan)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(phrase.text)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    Text(phrase.description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 50)
        .accessibilityLabel("Engrave \(phrase.text), \(phrase.description)")
    }

    // MARK: - Custom Text

    @ViewBuilder
    private var moreOptionsButton: some View {
        Button(action: {
            openCustomTextInput()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundColor(.brown)

                Text("Custom Text...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.brown.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.brown.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 50)
        .accessibilityLabel("Custom engraving text")
        .accessibilityHint("Enter your own text to engrave")
    }

    private func openCustomTextInput() {
        // Capture selected tool before dismissing
        let tool = selectedTool

        // Close engrave flow sheet first
        isDismissing = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            dismiss()

            // Open text input sheet with engrave context
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                overlayManager.requestTextInput(context: .engrave { text in
                    guard nethack_can_engrave() else {
                        print("[EngraveFlow] Cannot engrave at current location")
                        return
                    }

                    // Use captured tool for engraving
                    let success: Bool
                    if tool == .finger {
                        success = nethack_quick_engrave(text)
                        if success {
                            print("[EngraveFlow] Engraved custom text '\(text)' with finger")
                        }
                    } else {
                        let invlet = Int8(bitPattern: UInt8(tool.invlet.asciiValue ?? 0))
                        success = nethack_engrave_with_tool(text, invlet)
                        if success {
                            print("[EngraveFlow] Engraved custom text '\(text)' with \(tool.name)")
                        }
                    }

                    if !success {
                        print("[EngraveFlow] Failed to engrave custom text")
                    }
                })
            }
        }
    }

    // MARK: - Context Detection

    private var isLowHP: Bool {
        guard let stats = gameManager.playerStats else { return false }
        guard stats.hpmax > 0 else { return false }
        return Double(stats.hp) / Double(stats.hpmax) < 0.3
    }

    private func getCurrentEngraving() -> String? {
        // Call bridge function to check engraving at player position
        guard let cString = nethack_get_engraving_at_player() else {
            return nil
        }
        return String(cString: cString)
    }

    // MARK: - Actions

    private func engravePhrase(_ text: String) {
        // Check if can engrave
        guard nethack_can_engrave() else {
            print("[EngraveFlow] Cannot engrave at current location")
            dismissView()
            return
        }

        // Haptic feedback
        HapticManager.shared.buttonPress()

        // Use selected tool for engraving
        let success: Bool
        if selectedTool == .finger {
            // Finger: use quick engrave (sends E-text)
            success = nethack_quick_engrave(text)
            if success {
                print("[EngraveFlow] Engraved '\(text)' with finger")
            }
        } else {
            // Wand/tool: use engrave_with_tool (sends E[invlet]text)
            let invlet = Int8(bitPattern: UInt8(selectedTool.invlet.asciiValue ?? 0))
            success = nethack_engrave_with_tool(text, invlet)
            if success {
                print("[EngraveFlow] Engraved '\(text)' with \(selectedTool.name) (\(selectedTool.invlet))")
            }
        }

        if !success {
            print("[EngraveFlow] Failed to engrave '\(text)'")
        }

        dismissView()
    }

    private func dismissView() {
        HapticManager.shared.tap()

        isDismissing = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismiss()
        }
    }
}

// MARK: - Pulsing Modifier (for emergency Elbereth)

struct PulsingModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && isPulsing ? 1.1 : 1.0)
            .opacity(isActive && isPulsing ? 0.8 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil,
                value: isPulsing
            )
            .onAppear {
                if isActive {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Preview Provider

#Preview("EngraveFlowSheet - Normal") {
    ZStack {
        Color.gray.ignoresSafeArea()

        Text("Tap to open")
            .foregroundColor(.white)
    }
    .sheet(isPresented: .constant(true)) {
        EngraveFlowSheet(gameManager: NetHackGameManager())
            .environmentObject(GameOverlayManager())
    }
}

#Preview("EngraveFlowSheet - Low HP") {
    @Previewable @State var manager: NetHackGameManager = {
        let m = NetHackGameManager()
        m.playerStats = PlayerStats(
            hp: 5, hpmax: 20,
            pw: 10, pwmax: 10,
            level: 2, exp: 100,
            ac: 5,
            str: 18, dex: 12, con: 14, int: 10, wis: 8, cha: 6,
            gold: 50,
            moves: 10,
            dungeonLevel: 1,
            align: "Neutral",
            hunger: 0,
            conditions: 0
        )
        return m
    }()

    ZStack {
        Color.gray.ignoresSafeArea()
    }
    .sheet(isPresented: .constant(true)) {
        EngraveFlowSheet(gameManager: manager)
            .environmentObject(GameOverlayManager())
    }
}
