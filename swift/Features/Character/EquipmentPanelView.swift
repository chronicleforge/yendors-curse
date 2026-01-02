//
//  EquipmentPanelView.swift
//  nethack
//
//  Premium Equipment Panel - Sliding side panel from RIGHT edge
//  Features:
//  - Glass-morphic design matching app style
//  - Swipe-to-dismiss gesture
//  - Touch blocking for game below
//  - Reduce Motion accessibility support (MANDATORY - SWIFTUI-A-009)
//  - Inline Item Selection (no external overlay needed)
//
//  References:
//  - SWIFTUI-L-001: zIndex only works within same container
//  - SWIFTUI-A-001: Spring animations for natural feel
//  - SWIFTUI-A-003: Combined transitions
//  - SWIFTUI-G-001: Gesture handling
//  - SWIFTUI-M-003: contentShape for tap areas
//

import SwiftUI

// MARK: - Inline Item Selection State

/// State for inline item selection within Equipment Panel
struct InlineItemSelectionState: Equatable {
    let slot: EquipmentSlot
    let context: ItemSelectionContext

    static func == (lhs: InlineItemSelectionState, rhs: InlineItemSelectionState) -> Bool {
        lhs.slot == rhs.slot && lhs.context.command == rhs.context.command
    }
}

// MARK: - Hero Panel Tab

/// Tabs for the hero panel (Equipment vs Abilities)
enum HeroPanelTab: String, CaseIterable {
    case equipment = "Equipment"
    case abilities = "Abilities"

    var icon: String {
        switch self {
        case .equipment: return "shield.checkerboard"
        case .abilities: return "sparkles"
        }
    }

    var color: Color {
        // Single accent philosophy: all tabs use nethack accent (orange)
        // Color = meaning, not decoration
        .orange  // nethackAccent from LCH system
    }
}

// MARK: - Equipment Category

/// Groups equipment slots for organized display
enum EquipmentCategory: String, CaseIterable {
    case weapons = "Weapons"
    case armor = "Armor"
    case accessories = "Accessories"

    var slots: [EquipmentSlot] {
        switch self {
        case .weapons:
            return [.weapon, .secondary, .quiver]
        case .armor:
            return [.bodyArmor, .cloak, .helmet, .shield, .gloves, .boots, .shirt]
        case .accessories:
            return [.amulet, .leftRing, .rightRing, .blindfold]
        }
    }

    var icon: String {
        switch self {
        case .weapons: return "sword"
        case .armor: return "shield.checkerboard"
        case .accessories: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .weapons: return .red
        case .armor: return .blue
        case .accessories: return .yellow
        }
    }
}

// MARK: - Equipment Panel View

/// Premium sliding equipment panel from right edge
/// Displays paper doll on left, equipment list OR item selection on right
struct EquipmentPanelView: View {
    @Binding var isPresented: Bool
    @ObservedObject var statusManager: CharacterStatusManager
    @ObservedObject var overlayManager: GameOverlayManager

    // Accessibility
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Drag gesture state
    @State private var dragOffset: CGFloat = 0
    @State private var hasAppeared = false

    // Inline Item Selection State (replaces external ItemSelectionSheet)
    @State private var inlineSelection: InlineItemSelectionState? = nil

    // Tab selection for Equipment vs Abilities
    @State private var selectedTab: HeroPanelTab = .equipment

    // Device detection
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        GeometryReader { geometry in
            let panelWidth = calculatePanelWidth(for: geometry)

            ZStack(alignment: .trailing) {
                // MARK: - Backdrop (CRITICAL: Touch blocking - SWIFTUI-M-003)
                Color.black.opacity(hasAppeared ? 0.5 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())  // Make entire area tappable
                    .allowsHitTesting(true)     // Block all touches
                    .onTapGesture {
                        HapticManager.shared.tap()
                        dismiss()
                    }
                    .animation(
                        reduceMotion ? nil : AnimationConstants.backdropFade,
                        value: hasAppeared
                    )

                // MARK: - Sliding Panel
                panelContent(panelWidth: panelWidth, geometry: geometry)
                    .frame(width: panelWidth)
                    .offset(x: dragOffset)
                    .gesture(swipeToDismissGesture)
                    .transition(
                        reduceMotion
                            ? .opacity  // SWIFTUI-A-009: Simple fade for Reduce Motion
                            : AnimationConstants.panelSlideFromRight
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            statusManager.refresh()
            withAnimation(reduceMotion ? nil : AnimationConstants.panelSlideIn) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Panel Width Calculation

    private func calculatePanelWidth(for geometry: GeometryProxy) -> CGFloat {
        // 55-60% on iPad, 75% on iPhone
        let percentage: CGFloat = isPhone ? 0.75 : 0.58
        let maxWidth: CGFloat = isPhone ? geometry.size.width * 0.85 : 700

        return min(geometry.size.width * percentage, maxWidth)
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(panelWidth: CGFloat, geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left side: Paper Doll
            VStack(spacing: 0) {
                // Header
                panelHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider()
                    .background(Color.white.opacity(0.15))

                // Paper Doll
                InteractivePaperDollView(
                    statusManager: statusManager,
                    overlayManager: overlayManager,
                    isCompact: isPhone
                )
                .padding(isPhone ? 12 : 16)

                Spacer()

                // Close button
                closeButton
                    .padding(.bottom, 16)
            }
            .frame(width: panelWidth * (isPhone ? 0.55 : 0.45))

            // Divider between sections
            Divider()
                .background(Color.white.opacity(0.15))

            // Right side: Tabbed content (Equipment OR Abilities) OR Inline Item Selection
            VStack(spacing: 0) {
                // Tab Bar (only when not in inline selection)
                if inlineSelection == nil {
                    tabBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }

                // Content area
                ZStack {
                    // Tab content (Equipment or Abilities) with smooth transition
                    Group {
                        switch selectedTab {
                        case .equipment:
                            equipmentListView
                        case .abilities:
                            IntrinsicsView(isCompact: isPhone)
                        }
                    }
                    .id(selectedTab)  // Forces view identity change for transition
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 8)),
                        removal: .opacity
                    ))
                    .animation(reduceMotion ? nil : AnimationConstants.categorySelection, value: selectedTab)
                    .opacity(inlineSelection == nil ? 1 : 0)
                    .offset(x: inlineSelection == nil ? 0 : -20)
                    .zIndex(0)  // SWIFTUI-L-001: Explicit z-order for animation stability

                    // Inline Item Selection (slides in from right)
                    if let selection = inlineSelection {
                        InlineItemSelectionView(
                            context: selection.context,
                            slot: selection.slot,
                            items: overlayManager.items,
                            onSelect: { invlet in
                                handleItemSelected(invlet, for: selection)
                            },
                            onCancel: {
                                cancelInlineSelection()
                            }
                        )
                        .transition(inlineSelectionTransition)
                        .zIndex(1)  // SWIFTUI-L-001: Always on top of tab content
                    }
                }
                .animation(reduceMotion ? nil : AnimationConstants.smoothNatural, value: inlineSelection != nil)
            }
            .frame(maxWidth: .infinity)
        }
        .background(
            // Glass-morphic background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 30, x: -10, y: 0)
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        VStack(spacing: 6) {
            if let status = statusManager.status {
                // Character name/role
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: isPhone ? 16 : 20))
                        .foregroundColor(.yellow)

                    Text(status.identity.roleName)
                        .font(.system(size: isPhone ? 18 : 22, weight: .bold))
                        .foregroundColor(.white)
                }

                // Race & level
                Text("\(status.identity.raceName.capitalized) Lv.\(status.identity.level)")
                    .font(.system(size: isPhone ? 12 : 14))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text("Loading...")
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: {
            HapticManager.shared.tap()
            dismiss()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                Text("Close")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
            )
        }
        .frame(minWidth: 44, minHeight: 44)  // Apple HIG: 44pt minimum touch target
    }

    // MARK: - Equipment List View (extracted for animation)

    private var equipmentListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Equipment")
                .font(.system(size: isPhone ? 14 : 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(EquipmentCategory.allCases, id: \.rawValue) { category in
                        equipmentCategorySection(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: isPhone ? 4 : 6) {
            ForEach(HeroPanelTab.allCases, id: \.rawValue) { tab in
                tabButton(for: tab)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }

    @ViewBuilder
    private func tabButton(for tab: HeroPanelTab) -> some View {
        let isSelected = selectedTab == tab

        TabButtonView(
            tab: tab,
            isSelected: isSelected,
            isPhone: isPhone,
            reduceMotion: reduceMotion
        ) {
            HapticManager.shared.tap()
            withAnimation(reduceMotion ? nil : AnimationConstants.categorySelection) {
                selectedTab = tab
            }
        }
    }

    // MARK: - Inline Selection Transition

    private var inlineSelectionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
    }

    // MARK: - Equipment Category Section

    @ViewBuilder
    private func equipmentCategorySection(_ category: EquipmentCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: isPhone ? 11 : 13))
                    .foregroundColor(category.color)

                Text(category.rawValue)
                    .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            // Items in category
            VStack(spacing: 6) {
                ForEach(category.slots, id: \.rawValue) { slot in
                    equipmentSlotRow(slot)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Equipment Slot Row

    @ViewBuilder
    private func equipmentSlotRow(_ slot: EquipmentSlot) -> some View {
        let item = statusManager.status?.item(for: slot)
        let hasItem = item != nil && !item!.isEmpty

        HStack(spacing: 10) {
            // Slot icon
            Image(systemName: hasItem ? slot.icon : slot.emptyIcon)
                .font(.system(size: isPhone ? 12 : 14))
                .foregroundColor(hasItem ? slot.color : .white.opacity(0.3))
                .frame(width: isPhone ? 20 : 24)

            // Item name or empty state
            VStack(alignment: .leading, spacing: 2) {
                if let item = item, !item.isEmpty {
                    Text(item.name)
                        .font(.system(size: isPhone ? 12 : 13))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Text(slot.shortName)
                        .font(.system(size: isPhone ? 11 : 12))
                        .foregroundColor(.white.opacity(0.4))
                        .italic()
                }
            }

            Spacer()

            // BUC indicator
            if let item = item, !item.isEmpty {
                bucIndicator(for: item)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            Group {
                if let item = item, item.isCursed {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                        .cursedItemGlow()
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())  // SWIFTUI-M-003: Ensure tap area covers full row
        .onTapGesture {
            handleSlotTap(slot: slot, item: item)
        }
        .frame(minHeight: 44)  // Apple HIG: 44pt minimum touch target
    }

    // MARK: - BUC Indicator

    @ViewBuilder
    private func bucIndicator(for item: EquippedItem) -> some View {
        if item.isCursed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.red)
        } else if item.isBlessed {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.green)
        }
    }

    // MARK: - Swipe to Dismiss Gesture

    private var swipeToDismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow dragging to the right (positive X)
                guard value.translation.width > 0 else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let threshold = AnimationConstants.panelDismissThreshold
                let velocity = value.predictedEndLocation.x - value.location.x

                // Dismiss if dragged past threshold or velocity is high enough
                guard dragOffset > threshold || velocity > AnimationConstants.panelDismissVelocity else {
                    // Spring back to original position
                    withAnimation(reduceMotion ? nil : AnimationConstants.panelSlideIn) {
                        dragOffset = 0
                    }
                    return
                }

                HapticManager.shared.tap()
                dismiss()
            }
    }

    // MARK: - Slot Tap Handler

    private func handleSlotTap(slot: EquipmentSlot, item: EquippedItem?) {
        HapticManager.shared.tap()

        guard let item = item, !item.isEmpty else {
            // Empty slot - trigger equip flow
            handleEmptySlotTap(slot: slot)
            return
        }

        // Has item - could show action sheet, but for now just log
        // The paper doll already handles this via InteractivePaperDollView
        print("[EQUIPMENT_PANEL] Tapped equipped slot: \(slot.displayName) - \(item.name)")
    }

    private func handleEmptySlotTap(slot: EquipmentSlot) {
        // Map slot to appropriate ItemSelectionContext
        let context: ItemSelectionContext
        switch slot {
        case .weapon, .secondary:
            context = .wield()
        case .leftRing, .rightRing, .amulet, .blindfold:
            context = .putOn()
        case .bodyArmor, .cloak, .helmet, .shield, .gloves, .boots, .shirt:
            context = .wear()
        case .quiver:
            context = .quiver()
        }

        // Refresh inventory before showing selection
        overlayManager.updateInventory()

        // Show inline selection (replaces external ItemSelectionSheet)
        withAnimation(reduceMotion ? nil : AnimationConstants.smoothNatural) {
            inlineSelection = InlineItemSelectionState(slot: slot, context: context)
        }
    }

    // MARK: - Inline Selection Handlers

    private func handleItemSelected(_ invlet: Character, for selection: InlineItemSelectionState) {
        guard let invletAscii = invlet.asciiValue,
              let commandChar = selection.context.command.first,
              let commandAscii = commandChar.asciiValue else { return }

        print("[EQUIPMENT_PANEL] Item selected: '\(invlet)' for slot \(selection.slot.displayName)")

        // Queue the atomic command: command + item
        ios_queue_input(Int8(commandAscii))
        ios_queue_input(Int8(invletAscii))

        // Close inline selection and dismiss panel
        withAnimation(reduceMotion ? nil : AnimationConstants.smoothNatural) {
            inlineSelection = nil
        }

        // Dismiss panel after short delay for smooth transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.dismiss()
        }
    }

    private func cancelInlineSelection() {
        HapticManager.shared.tap()
        withAnimation(reduceMotion ? nil : AnimationConstants.smoothNatural) {
            inlineSelection = nil
        }
    }

    // MARK: - Dismiss

    private func dismiss() {
        withAnimation(reduceMotion ? nil : AnimationConstants.panelSlideOut) {
            hasAppeared = false
            dragOffset = 0
        }

        // Delay actual dismissal to allow animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.1 : 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Tab Button View (extracted for @State press tracking)

private struct TabButtonView: View {
    let tab: HeroPanelTab
    let isSelected: Bool
    let isPhone: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: isPhone ? 4 : 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: isPhone ? 11 : 13, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: isPhone ? 11 : 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, isPhone ? 14 : 18)
            .padding(.vertical, isPhone ? 10 : 12)
            .background(
                Capsule()
                    .fill(isSelected ? tab.color.opacity(0.3) : Color.clear)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected ? tab.color.opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
            )
            .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
            .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isPressed)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 80, minHeight: 44)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Inline Item Selection View

/// Compact item picker for Equipment Panel inline selection
/// Designed for 300-400pt width, replaces equipment list when slot is tapped
struct InlineItemSelectionView: View {
    let context: ItemSelectionContext
    let slot: EquipmentSlot
    let items: [NetHackItem]
    let onSelect: (Character) -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private let isPhone = ScalingEnvironment.isPhone

    // Filtered items based on context
    private var filteredItems: [NetHackItem] {
        guard let filter = context.filter else { return items }
        return items.filter(filter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with back button
            selectionHeader

            Divider()
                .background(Color.white.opacity(0.15))

            // Content: Items grid or empty state
            if filteredItems.isEmpty {
                emptyStateView
            } else {
                itemsScrollView
            }
        }
    }

    // MARK: - Selection Header

    private var selectionHeader: some View {
        HStack(spacing: 8) {
            // Title with icon
            Image(systemName: context.icon)
                .font(.system(size: isPhone ? 12 : 14))
                .foregroundColor(context.color)

            Text(slot.displayName)
                .font(.system(size: isPhone ? 13 : 15, weight: .semibold))
                .foregroundColor(.white)

            if !filteredItems.isEmpty {
                Text("(\(filteredItems.count))")
                    .font(.system(size: isPhone ? 11 : 12))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            // Close button
            Button(action: {
                HapticManager.shared.tap()
                onCancel()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: isPhone ? 11 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Items Scroll View

    private var itemsScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                ForEach(filteredItems) { item in
                    InlineItemCard(
                        item: item,
                        accentColor: context.color,
                        onTap: {
                            HapticManager.shared.selection()
                            onSelect(item.invlet)
                        }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: isPhone ? 14 : 16))
                .foregroundColor(.white.opacity(0.3))

            Text("No items available")
                .font(.system(size: isPhone ? 12 : 13))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Inline Item Card

/// Compact item card for inline selection picker
/// Shows icon, name, BUC status (abbreviated), and quantity
struct InlineItemCard: View {
    let item: NetHackItem
    let accentColor: Color
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private let isPhone = ScalingEnvironment.isPhone

    private var pressAnimation: Animation? {
        reduceMotion ? nil : AnimationConstants.pressAnimation
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Left: Item icon with inventory letter badge
                ZStack(alignment: .bottomTrailing) {
                    // Item category icon
                    Image(systemName: item.category.icon)
                        .font(.system(size: isPhone ? 16 : 18))
                        .foregroundColor(item.category.color)
                        .frame(width: isPhone ? 32 : 36, height: isPhone ? 32 : 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(item.category.color.opacity(0.15))
                        )

                    // Inventory letter badge
                    Text(String(item.invlet))
                        .font(.system(size: isPhone ? 8 : 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: isPhone ? 14 : 16, height: isPhone ? 14 : 16)
                        .background(
                            Circle()
                                .fill(accentColor)
                        )
                        .offset(x: 3, y: 3)
                }

                // Center: Item name and details
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .font(.system(size: isPhone ? 12 : 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)

                    // Subtitle with BUC and quantity
                    HStack(spacing: 4) {
                        // BUC indicator (only if known)
                        if item.bucKnown {
                            bucBadge
                        }

                        // Quantity (if > 1)
                        if item.quantity > 1 {
                            Text("x\(item.quantity)")
                                .font(.system(size: isPhone ? 9 : 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }

                Spacer(minLength: 4)

                // Right: Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: isPhone ? 10 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 44)  // Apple HIG: 44pt minimum touch target
            .background(cardBackground)
            .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
            .animation(pressAnimation, value: isPressed)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(isPressed ? 0.12 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        bucBorderColor.opacity(isPressed ? 0.5 : 0.2),
                        lineWidth: item.bucKnown && item.bucStatus == .cursed ? 2 : 1
                    )
            )
    }

    // MARK: - BUC Badge

    @ViewBuilder
    private var bucBadge: some View {
        switch item.bucStatus {
        case .blessed:
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: isPhone ? 8 : 9))
                Text("B")
                    .font(.system(size: isPhone ? 8 : 9, weight: .semibold))
            }
            .foregroundColor(.green)

        case .cursed:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: isPhone ? 8 : 9))
                Text("C")
                    .font(.system(size: isPhone ? 8 : 9, weight: .semibold))
            }
            .foregroundColor(.red)

        case .uncursed:
            Text("U")
                .font(.system(size: isPhone ? 8 : 9, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

        case .unknown:
            EmptyView()
        }
    }

    // MARK: - BUC Border Color

    private var bucBorderColor: Color {
        guard item.bucKnown else { return .white }
        switch item.bucStatus {
        case .blessed: return .green
        case .cursed: return .red
        case .uncursed, .unknown: return .white
        }
    }
}

// MARK: - Preview

#if DEBUG
struct EquipmentPanelView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Game background simulation
            Color.black.ignoresSafeArea()

            EquipmentPanelView(
                isPresented: .constant(true),
                statusManager: CharacterStatusManager.shared,
                overlayManager: GameOverlayManager()
            )
        }
        .preferredColorScheme(.dark)
    }
}

struct InlineItemSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            InlineItemSelectionView(
                context: .wear(),
                slot: .bodyArmor,
                items: NetHackItem.sampleItems,
                onSelect: { _ in },
                onCancel: { }
            )
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .preferredColorScheme(.dark)
    }
}
#endif
