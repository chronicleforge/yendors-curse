import SwiftUI

// MARK: - Item Selection Context

/// Context for item selection commands (eat, quaff, wear, etc.)
/// Defines the prompt, filter, and empty state for each command type
struct ItemSelectionContext {
    let command: String // NetHack command letter (e, q, W, etc.)
    let prompt: String // "What do you want to eat?"
    let icon: String // SF Symbol
    let color: Color
    let emptyMessage: String
    let categoryName: String
    let filter: ((NetHackItem) -> Bool)? // Filter function for items
    let supportsQuantity: Bool // Whether this action supports quantity selection for stacked items
    let needsDirectionAfter: Bool // Whether to show direction picker after item selection (throw, zap)
    let supportsFallback: Bool // Whether to show "Try Anything?" when filter returns empty
    let fallbackPrompt: String // Prompt when in fallback mode (e.g., "Eat what? (anything)")

    // Default initializer with optional fallback fields
    init(
        command: String,
        prompt: String,
        icon: String,
        color: Color,
        emptyMessage: String,
        categoryName: String,
        filter: ((NetHackItem) -> Bool)?,
        supportsQuantity: Bool,
        needsDirectionAfter: Bool,
        supportsFallback: Bool = false,
        fallbackPrompt: String? = nil
    ) {
        self.command = command
        self.prompt = prompt
        self.icon = icon
        self.color = color
        self.emptyMessage = emptyMessage
        self.categoryName = categoryName
        self.filter = filter
        self.supportsQuantity = supportsQuantity
        self.needsDirectionAfter = needsDirectionAfter
        self.supportsFallback = supportsFallback
        self.fallbackPrompt = fallbackPrompt ?? prompt
    }

    // MARK: - Factory Methods

    static func eat() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "e",
            prompt: "What do you want to eat?",
            icon: "fork.knife",
            color: .orange,
            emptyMessage: "You have nothing to eat.",
            categoryName: "food",
            filter: { $0.category == .food },
            supportsQuantity: false, // NetHack: "no count allowed" for eat
            needsDirectionAfter: false,
            supportsFallback: true,
            fallbackPrompt: "Eat what? (anything)"
        )
    }

    static func quaff() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "q",
            prompt: "What do you want to drink?",
            icon: "drop.fill",
            color: .blue,
            emptyMessage: "You have no potions.",
            categoryName: "potion",
            filter: { $0.category == .potions },
            supportsQuantity: false, // NetHack: drink one potion at a time
            needsDirectionAfter: false,
            supportsFallback: true,
            fallbackPrompt: "Drink what? (anything)"
        )
    }

    static func read() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "r",
            prompt: "What do you want to read?",
            icon: "book.fill",
            color: .yellow,
            emptyMessage: "You have nothing to read.",
            categoryName: "scroll or book",
            filter: { $0.category == .scrolls || $0.category == .spellbooks },
            supportsQuantity: false, // NetHack: read one scroll at a time
            needsDirectionAfter: false
        )
    }

    static func wear() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "W",
            prompt: "What do you want to wear?",
            icon: "shield.fill",
            color: .green,
            emptyMessage: "You have no armor to wear.",
            categoryName: "armor",
            filter: { $0.category == .armor && !$0.properties.isWorn },
            supportsQuantity: false,
            needsDirectionAfter: false
        )
    }

    static func wield() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "w",
            prompt: "What do you want to wield?",
            icon: "hand.raised.fill",
            color: .red,
            emptyMessage: "You have no weapons.",
            categoryName: "weapon",
            filter: { $0.category == .weapons && !$0.properties.isWielded },
            supportsQuantity: false,
            needsDirectionAfter: false
        )
    }

    static func zap() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "z",
            prompt: "What do you want to zap?",
            icon: "wand.and.stars",
            color: .purple,
            emptyMessage: "You have no wands.",
            categoryName: "wand",
            filter: { $0.category == .wands },
            supportsQuantity: false,
            needsDirectionAfter: true // Wands need direction after selection
        )
    }

    static func apply() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "a",
            prompt: "What do you want to apply?",
            icon: "wrench.and.screwdriver.fill",
            color: .gray,
            emptyMessage: "You have no tools.",
            categoryName: "tool",
            filter: { $0.category == .tools },
            supportsQuantity: false,
            needsDirectionAfter: false
        )
    }

    static func rub() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "#rub",
            prompt: "What do you want to rub?",
            icon: "hand.point.up.left.fill",
            color: .yellow,
            emptyMessage: "You have nothing to rub.",
            categoryName: "lamp or stone",
            filter: { $0.category == .tools || $0.category == .gems },
            supportsQuantity: false,
            needsDirectionAfter: false
        )
    }

    static func drop() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "d",
            prompt: "What do you want to drop?",
            icon: "arrow.down.circle.fill",
            color: .gray,
            emptyMessage: "You have nothing to drop.",
            categoryName: "item",
            filter: nil, // No filter - allow all items
            supportsQuantity: true,
            needsDirectionAfter: false
        )
    }

    static func throwItem() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "t",
            prompt: "What do you want to throw?",
            icon: "arrow.up.forward.circle.fill",
            color: .yellow,
            emptyMessage: "You have nothing to throw.",
            categoryName: "item",
            filter: nil, // No filter - can throw anything
            supportsQuantity: true,
            needsDirectionAfter: true // Throw needs direction after item selection
        )
    }

    static func putOn() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "P",
            prompt: "What do you want to put on?",
            icon: "circle.fill",
            color: .cyan,
            emptyMessage: "You have no rings or amulets.",
            categoryName: "ring or amulet",
            filter: { ($0.category == .rings || $0.category == .amulets) && !$0.properties.isWorn },
            supportsQuantity: false,
            needsDirectionAfter: false
        )
    }

    static func remove() -> ItemSelectionContext {
        // NetHack 'R' command accepts W_ARMOR | W_ACCESSORY, NOT wielded weapons
        ItemSelectionContext(
            command: "R",
            prompt: "What do you want to remove?",
            icon: "minus.circle.fill",
            color: .orange,
            emptyMessage: "You're not wearing anything removable.",
            categoryName: "armor or accessory",
            filter: { $0.properties.isWorn && !$0.properties.isWielded },
            supportsQuantity: false,
            needsDirectionAfter: false
        )
    }

    static func takeOff() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "T",
            prompt: "What do you want to take off?",
            icon: "tshirt",
            color: .blue,
            emptyMessage: "You're not wearing any armor.",
            categoryName: "armor",
            filter: { $0.category == .armor && $0.properties.isWorn },
            supportsQuantity: false,
            needsDirectionAfter: false
        )
    }

    static func quiver() -> ItemSelectionContext {
        ItemSelectionContext(
            command: "Q",
            prompt: "What do you want to ready?",
            icon: "arrow.up.bin.fill",
            color: .purple,
            emptyMessage: "You have nothing to quiver.",
            categoryName: "projectile or weapon",
            filter: { item in
                // Quiver accepts: weapons (for throwing), gems (rocks), tools (cream pies, etc.)
                item.category == .weapons ||
                item.category == .gems ||
                item.category == .tools
            },
            supportsQuantity: false,
            needsDirectionAfter: false
        )
    }
}

// MARK: - Item Selection Sheet

/// Premium glass-morphic sheet for selecting inventory items
/// Used for: eat, quaff, read, throw, zap, wear, wield, etc.
///
/// Design Philosophy (Roguelike Quick-Select Pattern):
/// - **Compact Vertical Grid**: 2-column layout for efficient scanning
/// - **Letter-First**: Inventory letter prominently displayed (roguelike convention)
/// - **Touch-First**: 44pt minimum touch targets, thumb-reachable
/// - **Glass-morphic**: Consistent with app design system
/// - **Safe Area Aware**: Handles Dynamic Island on LEFT/RIGHT in landscape
///
/// Layout: Vertical 2-column grid with ItemPill components
/// Each pill shows: [Letter] [Icon] [Name] [BUC/Qty]
struct ItemSelectionSheet: View {
    let context: ItemSelectionContext
    let items: [NetHackItem]
    let groundItems: [GameObjectInfo]  // Items at player's feet (from ObjectBridgeWrapper)
    let onSelect: (Character) -> Void
    let onSelectGround: ((UInt32) -> Void)?  // Select ground item by object ID
    let onCancel: () -> Void

    // Backwards-compatible initializer (no ground items)
    init(
        context: ItemSelectionContext,
        items: [NetHackItem],
        onSelect: @escaping (Character) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.items = items
        self.groundItems = []
        self.onSelect = onSelect
        self.onSelectGround = nil
        self.onCancel = onCancel
    }

    // Full initializer with ground items
    init(
        context: ItemSelectionContext,
        items: [NetHackItem],
        groundItems: [GameObjectInfo],
        onSelect: @escaping (Character) -> Void,
        onSelectGround: ((UInt32) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.items = items
        self.groundItems = groundItems
        self.onSelect = onSelect
        self.onSelectGround = onSelectGround
        self.onCancel = onCancel
    }

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var hasAppeared = false

    private let isPhone = ScalingEnvironment.isPhone

    // MARK: - Computed Item Groups

    /// Items matching the filter (e.g., food for Eat)
    private var matchingItems: [NetHackItem] {
        guard let filter = context.filter else { return items }
        return items.filter(filter)
    }

    /// Items NOT matching the filter (for "Other items" section)
    private var otherItems: [NetHackItem] {
        guard context.supportsFallback, let filter = context.filter else { return [] }
        return items.filter { !filter($0) }
    }

    /// Ground items matching the filter (e.g., food on ground)
    /// Uses NetHack's objectClass for reliable filtering (no string heuristics!)
    private var matchingGroundItems: [GameObjectInfo] {
        guard context.filter != nil else { return groundItems }

        // Use objectClass from C bridge - reliable, matches NetHack's internal logic
        return groundItems.filter { obj in
            switch context.categoryName {
            case "food":
                return obj.isFood  // objectClass == FOOD_CLASS (7)
            case "potion":
                return obj.isPotion  // objectClass == POTION_CLASS (8)
            case "scroll or book":
                return obj.objectClass == GameObjectInfo.SCROLL_CLASS ||
                       obj.objectClass == GameObjectInfo.SPBOOK_CLASS
            case "wand":
                return obj.objectClass == GameObjectInfo.WAND_CLASS
            case "armor":
                return obj.objectClass == GameObjectInfo.ARMOR_CLASS
            case "weapon":
                return obj.objectClass == GameObjectInfo.WEAPON_CLASS
            case "ring or amulet":
                return obj.objectClass == GameObjectInfo.RING_CLASS ||
                       obj.objectClass == GameObjectInfo.AMULET_CLASS
            case "tool":
                return obj.objectClass == GameObjectInfo.TOOL_CLASS
            default:
                return true  // No filter - show all ground items
            }
        }
    }

    /// Check if we have anything to show
    private var hasAnyItems: Bool {
        !matchingItems.isEmpty || !otherItems.isEmpty || !matchingGroundItems.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact inline header
            compactHeader

            // Thin separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)

            // Content - grouped sections
            if hasAnyItems {
                groupedItemsContent
            } else {
                compactEmptyState
            }
        }
        .frame(maxWidth: isPhone ? 340 : 420)  // Constrain width
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: isPhone ? 12 : 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: -4)
        .transition(sheetTransition)
        .animation(reduceMotion ? nil : AnimationConstants.sheetAppear, value: hasAppeared)
        .onAppear {
            withAnimation(reduceMotion ? nil : AnimationConstants.sheetAppear) {
                hasAppeared = true
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hasAppeared)
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        HStack(spacing: isPhone ? 6 : 10) {
            // Context icon
            Image(systemName: context.icon)
                .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                .foregroundColor(context.color)
                .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                .background(
                    Circle()
                        .fill(context.color.opacity(0.2))
                )

            // Prompt
            Text(context.prompt)
                .font(.system(size: isPhone ? 13 : 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Total item count pill (matching + ground)
            let totalCount = matchingItems.count + matchingGroundItems.count
            Text("\(totalCount)")
                .font(.system(size: isPhone ? 10 : 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .contentTransition(.numericText())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(context.color.opacity(0.3))
                )
                .animation(reduceMotion ? nil : AnimationConstants.statusUpdate, value: totalCount)

            // Close button (44pt touch target)
            CloseButton(reduceMotion: reduceMotion) {
                HapticManager.shared.tap()
                onCancel()
            }
        }
        .padding(.horizontal, isPhone ? 12 : 16)
        .padding(.vertical, isPhone ? 6 : 8)
    }

    // MARK: - Grouped Items Content

    private var groupedItemsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: isPhone ? 8 : 12) {
                // Section 1: Ground items (if any match)
                if !matchingGroundItems.isEmpty {
                    itemSection(
                        header: "Here",
                        icon: "arrow.down.circle",
                        headerColor: .green
                    ) {
                        ForEach(Array(matchingGroundItems.enumerated()), id: \.element.id) { index, obj in
                            GroundItemPill(
                                item: obj,
                                accentColor: .green,
                                index: index,
                                reduceMotion: reduceMotion,
                                onTap: {
                                    HapticManager.shared.selection()
                                    onSelectGround?(obj.objectID)
                                }
                            )
                        }
                    }
                }

                // Section 2: Matching inventory items (primary)
                if !matchingItems.isEmpty {
                    let showHeader = !matchingGroundItems.isEmpty || !otherItems.isEmpty
                    itemSection(
                        header: showHeader ? context.categoryName.capitalized : nil,
                        icon: showHeader ? context.icon : nil,
                        headerColor: context.color
                    ) {
                        ForEach(Array(matchingItems.enumerated()), id: \.element.id) { index, item in
                            ItemPill(
                                item: item,
                                accentColor: context.color,
                                index: index,
                                reduceMotion: reduceMotion,
                                onTap: {
                                    HapticManager.shared.selection()
                                    onSelect(item.invlet)
                                }
                            )
                        }
                    }
                }

                // Section 3: Other items (fallback)
                if !otherItems.isEmpty {
                    itemSection(
                        header: "Other",
                        icon: "questionmark.circle",
                        headerColor: .orange
                    ) {
                        ForEach(Array(otherItems.enumerated()), id: \.element.id) { index, item in
                            ItemPill(
                                item: item,
                                accentColor: .orange,
                                index: index + matchingItems.count, // Continue index for animation
                                reduceMotion: reduceMotion,
                                onTap: {
                                    HapticManager.shared.selection()
                                    onSelect(item.invlet)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .padding(.vertical, isPhone ? 6 : 10)
        }
        .frame(maxHeight: isPhone ? 180 : 240)  // Slightly taller for sections
    }

    // MARK: - Item Section Helper

    @ViewBuilder
    private func itemSection<Content: View>(
        header: String?,
        icon: String?,
        headerColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: isPhone ? 4 : 6) {
            // Section header (if provided)
            if let header = header {
                HStack(spacing: 4) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: isPhone ? 10 : 12, weight: .medium))
                            .foregroundColor(headerColor.opacity(0.7))
                    }
                    Text(header)
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .textCase(.uppercase)
                }
                .padding(.leading, 4)
                .padding(.bottom, 2)
            }

            // Items list (single column for full item name visibility)
            LazyVGrid(
                columns: [GridItem(.flexible())],
                spacing: isPhone ? 4 : 6
            ) {
                content()
            }
        }
    }

    // MARK: - Compact Empty State

    private var compactEmptyState: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: isPhone ? 18 : 22))
                    .foregroundColor(.white.opacity(0.25))
                    .emptyStateIconAnimation()

                Text(context.emptyMessage)
                    .font(.system(size: isPhone ? 12 : 14))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isPhone ? 16 : 24)
        .emptyStateEntrance(isVisible: hasAppeared, reduceMotion: reduceMotion)
    }

    // MARK: - Sheet Background (Glass-morphic)

    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: isPhone ? 12 : 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 12 : 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                context.color.opacity(0.25),
                                Color.white.opacity(0.08),
                                context.color.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }

    // MARK: - Sheet Transition

    private var sheetTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : AnimationConstants.sheetAppearTransition
    }
}

// MARK: - Item Pill (Compact Selection Row)

/// Compact pill-shaped item row for quick selection in 2-column grid
/// Design: [Letter Badge] [Category Icon] [Name...] [Qty] [BUC]
/// Optimized for landscape roguelike quick-select pattern
private struct ItemPill: View {
    let item: NetHackItem
    let accentColor: Color
    let index: Int
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var isConfirming = false
    @State private var hasAppeared = false
    @State private var showDetails = false

    private let isPhone = ScalingEnvironment.isPhone

    // Minimum height for touch target (44pt)
    private var pillHeight: CGFloat { isPhone ? 44 : 48 }

    private var entranceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        guard AnimationConstants.shouldStaggerItem(at: index) else {
            return AnimationConstants.itemCardBaseEntrance
        }
        return AnimationConstants.itemCardStaggeredEntrance(index: index, reduceMotion: reduceMotion)
    }

    var body: some View {
        Button {
            guard !isConfirming else { return }
            isConfirming = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                onTap()
            }
        } label: {
            HStack(spacing: isPhone ? 6 : 8) {
                // Inventory letter badge (prominent, roguelike style)
                Text(String(item.invlet))
                    .font(.system(size: isPhone ? 12 : 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(accentColor)
                    )

                // Category icon (small, tinted)
                Image(systemName: item.category.icon)
                    .font(.system(size: isPhone ? 12 : 14))
                    .foregroundColor(item.category.color.opacity(0.8))
                    .frame(width: isPhone ? 16 : 20)

                // BUC indicator (always visible when known - before name)
                if item.bucKnown {
                    pillBUCIndicator
                }

                // Item name (stripped of BUC prefix for cleaner display)
                Text(item.cleanName)
                    .font(.system(size: isPhone ? 11 : 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                // Right side: Quantity badge only
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, isPhone ? 5 : 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, isPhone ? 8 : 10)
            .frame(height: pillHeight)
            .background(pillBackground)
            .scaleEffect(
                isConfirming
                    ? AnimationConstants.selectionConfirmationScale
                    : (isPressed ? AnimationConstants.itemCardPressScale : 1.0)
            )
            .opacity(hasAppeared ? 1.0 : 0.0)
            .offset(y: hasAppeared ? 0 : 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isConfirming else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.itemCardPress, value: isPressed)
        .animation(reduceMotion ? nil : AnimationConstants.selectionConfirmation, value: isConfirming)
        .onAppear {
            withAnimation(entranceAnimation) {
                hasAppeared = true
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isConfirming)
        .onLongPressGesture(minimumDuration: 0.4) {
            HapticManager.shared.tap()
            showDetails = true
        }
        .popover(isPresented: $showDetails, arrowEdge: .leading) {
            ItemDetailPopover(item: item)
        }
    }

    // MARK: - Pill Background

    private var pillBackground: some View {
        let fillOpacity: Double = {
            if isConfirming { return 0.2 }
            if isPressed { return 0.12 }
            return 0.05
        }()

        let borderColor: Color = isConfirming ? accentColor.opacity(0.6) : pillBorderColor

        return RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
                    .strokeBorder(borderColor, lineWidth: isConfirming ? 2 : (item.bucKnown && item.bucStatus == .cursed ? 1.5 : 0.5))
            )
    }

    private var pillBorderColor: Color {
        guard item.bucKnown else { return .white.opacity(0.1) }
        switch item.bucStatus {
        case .blessed: return .green.opacity(0.4)
        case .cursed: return .red.opacity(0.5)
        case .uncursed, .unknown: return .white.opacity(0.1)
        }
    }

    @ViewBuilder
    private var pillBUCIndicator: some View {
        switch item.bucStatus {
        case .blessed:
            Image(systemName: "sparkles")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.green)
        case .cursed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.red)
        case .uncursed:
            // Show subtle indicator for known uncursed (so users know it's been identified)
            Image(systemName: "checkmark.circle")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.yellow.opacity(0.7))
        case .unknown:
            EmptyView()
        }
    }
}

// MARK: - Item Detail Popover

/// Popover showing full item details on long press
private struct ItemDetailPopover: View {
    let item: NetHackItem

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item icon and full name
            HStack(spacing: 10) {
                Image(systemName: item.category.icon)
                    .font(.system(size: 20))
                    .foregroundColor(item.category.color)

                Text(item.cleanName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // BUC status
            if item.bucKnown {
                detailRow(
                    icon: item.bucStatus.icon,
                    iconColor: item.bucStatus.color,
                    label: bucStatusLabel
                )
            }

            // Enchantment
            if let enchantment = item.enchantment {
                detailRow(
                    icon: "plus.forwardslash.minus",
                    iconColor: enchantment >= 0 ? .green : .red,
                    label: "Enchantment: \(enchantment >= 0 ? "+" : "")\(enchantment)"
                )
            }

            // Quantity
            if item.quantity > 1 {
                detailRow(
                    icon: "square.stack.fill",
                    iconColor: .blue,
                    label: "Quantity: \(item.quantity)"
                )
            }

            // Category
            detailRow(
                icon: item.category.icon,
                iconColor: item.category.color,
                label: item.category.rawValue
            )

            Divider()

            // Hint
            Text("Tap to select")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .frame(minWidth: 200, maxWidth: 280)
        .background(Color(UIColor.systemBackground))
    }

    private var bucStatusLabel: String {
        switch item.bucStatus {
        case .blessed: return "Blessed"
        case .cursed: return "Cursed"
        case .uncursed: return "Uncursed"
        case .unknown: return "Unknown"
        }
    }

    @ViewBuilder
    private func detailRow(icon: String, iconColor: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Ground Item Detail Popover

/// Popover showing full details for ground items
private struct GroundItemDetailPopover: View {
    let item: GameObjectInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item icon and full name
            HStack(spacing: 10) {
                Text(item.icon)
                    .font(.system(size: 20))

                Text(item.cleanName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // BUC status
            if item.bucKnown {
                detailRow(
                    icon: bucIcon,
                    iconColor: bucColor,
                    label: bucStatusLabel
                )
            }

            // Enchantment
            if item.chargesKnown && item.enchantment != 0 {
                detailRow(
                    icon: "plus.forwardslash.minus",
                    iconColor: item.enchantment > 0 ? .green : .red,
                    label: "Enchantment: \(item.enchantment > 0 ? "+" : "")\(item.enchantment)"
                )
            }

            // Quantity
            if item.quantity > 1 {
                detailRow(
                    icon: "square.stack.fill",
                    iconColor: .blue,
                    label: "Quantity: \(item.quantity)"
                )
            }

            // Category
            let category = ItemCategory.fromOclass(Int8(item.objectClass))
            detailRow(
                icon: category.icon,
                iconColor: category.color,
                label: category.rawValue
            )

            Divider()

            // Hint
            Text("Tap to select")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .frame(minWidth: 200, maxWidth: 280)
        .background(Color(UIColor.systemBackground))
    }

    private var bucStatusLabel: String {
        guard item.bucKnown else { return "Unknown" }
        if item.blessed { return "Blessed" }
        if item.cursed { return "Cursed" }
        return "Uncursed"
    }

    private var bucIcon: String {
        if item.blessed { return "sparkles" }
        if item.cursed { return "exclamationmark.triangle" }
        return "checkmark.circle"
    }

    private var bucColor: Color {
        if item.blessed { return .green }
        if item.cursed { return .red }
        return .yellow
    }

    @ViewBuilder
    private func detailRow(icon: String, iconColor: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Ground Item Pill

/// Pill for ground items (uses GameObjectInfo instead of NetHackItem)
private struct GroundItemPill: View {
    let item: GameObjectInfo
    let accentColor: Color
    let index: Int
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var isConfirming = false
    @State private var hasAppeared = false
    @State private var showDetails = false

    private let isPhone = ScalingEnvironment.isPhone
    private var pillHeight: CGFloat { isPhone ? 44 : 48 }

    private var entranceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        guard AnimationConstants.shouldStaggerItem(at: index) else {
            return AnimationConstants.itemCardBaseEntrance
        }
        return AnimationConstants.itemCardStaggeredEntrance(index: index, reduceMotion: reduceMotion)
    }

    var body: some View {
        Button {
            guard !isConfirming else { return }
            isConfirming = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                onTap()
            }
        } label: {
            HStack(spacing: isPhone ? 6 : 8) {
                // Ground indicator (instead of inventory letter)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: isPhone ? 14 : 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(accentColor)
                    )

                // Item icon (emoji-based from GameObjectInfo)
                Text(item.icon)
                    .font(.system(size: isPhone ? 14 : 16))
                    .frame(width: isPhone ? 16 : 20)

                // BUC indicator (before name for consistency)
                if item.bucKnown {
                    groundBUCIndicator
                }

                // Item name (stripped of BUC prefix for cleaner display)
                Text(item.cleanName)
                    .font(.system(size: isPhone ? 11 : 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                // Right side: Quantity badge only
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, isPhone ? 5 : 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, isPhone ? 8 : 10)
            .frame(height: pillHeight)
            .background(pillBackground)
            .scaleEffect(
                isConfirming
                    ? AnimationConstants.selectionConfirmationScale
                    : (isPressed ? AnimationConstants.itemCardPressScale : 1.0)
            )
            .opacity(hasAppeared ? 1.0 : 0.0)
            .offset(y: hasAppeared ? 0 : 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isConfirming else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.itemCardPress, value: isPressed)
        .animation(reduceMotion ? nil : AnimationConstants.selectionConfirmation, value: isConfirming)
        .onAppear {
            withAnimation(entranceAnimation) {
                hasAppeared = true
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isConfirming)
        .onLongPressGesture(minimumDuration: 0.4) {
            HapticManager.shared.tap()
            showDetails = true
        }
        .popover(isPresented: $showDetails, arrowEdge: .leading) {
            GroundItemDetailPopover(item: item)
        }
    }

    private var pillBackground: some View {
        let fillOpacity: Double = {
            if isConfirming { return 0.2 }
            if isPressed { return 0.12 }
            return 0.05
        }()

        let borderColor: Color = isConfirming ? accentColor.opacity(0.6) : pillBorderColor

        return RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
                    .strokeBorder(borderColor, lineWidth: isConfirming ? 2 : 0.5)
            )
    }

    private var pillBorderColor: Color {
        guard item.bucKnown else { return .white.opacity(0.1) }
        if item.blessed { return .green.opacity(0.4) }
        if item.cursed { return .red.opacity(0.5) }
        return .white.opacity(0.1)
    }

    @ViewBuilder
    private var groundBUCIndicator: some View {
        if item.blessed {
            Image(systemName: "sparkles")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.green)
        } else if item.cursed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.red)
        } else {
            // Show subtle indicator for known uncursed (so users know it's been identified)
            Image(systemName: "checkmark.circle")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.yellow.opacity(0.7))
        }
    }
}

// MARK: - Close Button (with press feedback)

/// Animated close button with consistent press feedback
/// Ref: SWIFTUI-A-006 Press Animation Pattern
private struct CloseButton: View {
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "xmark")
                .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isPressed ? 0.2 : 0.1))
                )
                .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isPressed)
    }
}

// MARK: - Premium Item Card

/// Premium glass-morphic card for item selection
/// Features: Icon, inventory letter badge, name, quantity, BUC status, press animation
struct PremiumItemCard: View {
    let item: NetHackItem
    let accentColor: Color
    let index: Int
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var isConfirming = false  // Selection confirmation "pop"
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    // Card dimensions (landscape optimized)
    private var cardWidth: CGFloat { isPhone ? 110 : 140 }
    private var cardHeight: CGFloat { isPhone ? 130 : 160 }

    /// Staggered entrance - use faster itemCardStaggeredEntrance for snappy game feel
    private var entranceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        guard AnimationConstants.shouldStaggerItem(at: index) else {
            return AnimationConstants.itemCardBaseEntrance
        }
        return AnimationConstants.itemCardStaggeredEntrance(index: index, reduceMotion: reduceMotion)
    }

    var body: some View {
        Button {
            // Selection confirmation animation
            guard !isConfirming else { return }
            isConfirming = true

            // Delay callback to let confirmation animation play
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onTap()
            }
        } label: {
            VStack(spacing: isPhone ? 6 : 10) {
                // Item Icon with category-colored background
                ZStack {
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .fill(item.category.color.opacity(0.15))
                        .frame(width: isPhone ? 50 : 64, height: isPhone ? 50 : 64)

                    Image(systemName: item.category.icon)
                        .font(.system(size: isPhone ? 24 : 30))
                        .foregroundColor(item.category.color)

                    // Inventory letter badge (top-right)
                    Text(String(item.invlet))
                        .font(.system(size: isPhone ? 10 : 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: isPhone ? 18 : 22, height: isPhone ? 18 : 22)
                        .background(
                            Circle()
                                .fill(accentColor)
                                .shadow(color: accentColor.opacity(0.5), radius: 4)
                        )
                        .offset(x: isPhone ? 20 : 26, y: isPhone ? -20 : -26)
                }

                // Item name
                Text(item.name)
                    .font(.system(size: isPhone ? 11 : 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                // Bottom row: BUC + Quantity
                HStack(spacing: 6) {
                    // BUC indicator (if known)
                    if item.bucKnown && item.bucStatus != .unknown {
                        bucBadge
                    }

                    // Quantity (if > 1)
                    if item.quantity > 1 {
                        Text("x\(item.quantity)")
                            .font(.system(size: isPhone ? 10 : 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(cardBackground)
            // Press scale (standard) or confirmation scale (larger pop)
            .scaleEffect(
                isConfirming
                    ? AnimationConstants.selectionConfirmationScale
                    : (isPressed ? AnimationConstants.itemCardPressScale : 1.0)
            )
            // Staggered entrance opacity + offset
            .opacity(hasAppeared ? 1.0 : 0.0)
            .offset(y: hasAppeared ? 0 : 16)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isConfirming else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.itemCardPress, value: isPressed)
        .animation(reduceMotion ? nil : AnimationConstants.selectionConfirmation, value: isConfirming)
        .onAppear {
            withAnimation(entranceAnimation) {
                hasAppeared = true
            }
        }
        // Selection haptic feedback
        .sensoryFeedback(.impact(weight: .medium), trigger: isConfirming)
    }

    // MARK: - Card Background

    /// Background with visual states: normal -> pressed -> confirming (success highlight)
    private var cardBackground: some View {
        let fillOpacity: Double = {
            if isConfirming { return 0.2 }  // Success highlight
            if isPressed { return 0.12 }     // Press feedback
            return 0.06                       // Normal state
        }()

        // Override border on confirmation with accent color glow
        let confirmingBorderGradient = LinearGradient(
            colors: [accentColor.opacity(0.6), accentColor.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return RoundedRectangle(cornerRadius: isPhone ? 12 : 16)
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 12 : 16)
                    .strokeBorder(
                        isConfirming ? confirmingBorderGradient : bucBorderGradient,
                        lineWidth: isConfirming ? 2.5 : (item.bucKnown && item.bucStatus == .cursed ? 2 : 1)
                    )
            )
            .shadow(
                color: isConfirming
                    ? accentColor.opacity(0.4)
                    : (item.bucKnown && item.bucStatus == .cursed
                        ? Color.red.opacity(0.3)
                        : Color.black.opacity(0.2)),
                radius: isConfirming ? 10 : (item.bucKnown && item.bucStatus == .cursed ? 8 : 4),
                y: 2
            )
    }

    // MARK: - BUC Border Gradient

    private var bucBorderGradient: LinearGradient {
        let borderColor: Color = {
            guard item.bucKnown else { return .white.opacity(0.2) }
            switch item.bucStatus {
            case .blessed: return .green.opacity(0.5)
            case .cursed: return .red.opacity(0.6)
            case .uncursed: return .white.opacity(0.25)
            case .unknown: return .white.opacity(0.2)
            }
        }()

        return LinearGradient(
            colors: [borderColor, borderColor.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - BUC Badge

    @ViewBuilder
    private var bucBadge: some View {
        switch item.bucStatus {
        case .blessed:
            HStack(spacing: 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: isPhone ? 8 : 10))
                Text("B")
                    .font(.system(size: isPhone ? 9 : 11, weight: .bold))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.2))
            )

        case .cursed:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: isPhone ? 8 : 10))
                Text("C")
                    .font(.system(size: isPhone ? 9 : 11, weight: .bold))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.2))
            )

        case .uncursed:
            Text("UC")
                .font(.system(size: isPhone ? 9 : 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

        case .unknown:
            EmptyView()
        }
    }
}

// MARK: - Compact Item Card

/// Compact horizontal card for quick item selection
/// Single row: [Letter Badge] [Icon] [Name] [Quantity/BUC]
struct CompactItemCard: View {
    let item: NetHackItem
    let accentColor: Color
    let index: Int
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var isConfirming = false  // Selection confirmation "pop"
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    /// Staggered entrance - use faster itemCardStaggeredEntrance for snappy game feel
    private var entranceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        guard AnimationConstants.shouldStaggerItem(at: index) else {
            return AnimationConstants.itemCardBaseEntrance
        }
        return AnimationConstants.itemCardStaggeredEntrance(index: index, reduceMotion: reduceMotion)
    }

    var body: some View {
        Button {
            // Selection confirmation animation
            guard !isConfirming else { return }
            isConfirming = true

            // Haptic + visual pop, then callback
            withAnimation(reduceMotion ? nil : AnimationConstants.selectionConfirmation) {
                // Animation drives the scale effect
            }

            // Delay callback to let confirmation animation play
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onTap()
            }
        } label: {
            HStack(spacing: isPhone ? 6 : 8) {
                // Inventory letter badge
                Text(String(item.invlet))
                    .font(.system(size: isPhone ? 11 : 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: isPhone ? 22 : 26, height: isPhone ? 22 : 26)
                    .background(
                        Circle()
                            .fill(accentColor)
                    )

                // Category icon
                Image(systemName: item.category.icon)
                    .font(.system(size: isPhone ? 14 : 16))
                    .foregroundColor(item.category.color)
                    .frame(width: isPhone ? 20 : 24)

                // Item name
                Text(item.name)
                    .font(.system(size: isPhone ? 12 : 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)

                // Quantity badge (if > 1) - with numeric transition
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .contentTransition(.numericText())
                }

                // BUC indicator
                if item.bucKnown {
                    compactBUCIndicator
                }
            }
            .padding(.horizontal, isPhone ? 10 : 12)
            .padding(.vertical, isPhone ? 8 : 10)
            .background(cardBackground)
            // Press scale (standard) or confirmation scale (larger pop)
            .scaleEffect(
                isConfirming
                    ? AnimationConstants.selectionConfirmationScale
                    : (isPressed ? AnimationConstants.itemCardPressScale : 1.0)
            )
            // Staggered entrance opacity + offset
            .opacity(hasAppeared ? 1.0 : 0.0)
            .offset(y: hasAppeared ? 0 : 12)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isConfirming else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.itemCardPress, value: isPressed)
        .animation(reduceMotion ? nil : AnimationConstants.selectionConfirmation, value: isConfirming)
        .onAppear {
            withAnimation(entranceAnimation) {
                hasAppeared = true
            }
        }
        // Selection haptic feedback
        .sensoryFeedback(.impact(weight: .medium), trigger: isConfirming)
    }

    /// Background with visual states: normal -> pressed -> confirming (success highlight)
    private var cardBackground: some View {
        let fillOpacity: Double = {
            if isConfirming { return 0.2 }  // Success highlight
            if isPressed { return 0.12 }     // Press feedback
            return 0.06                       // Normal state
        }()

        let borderColor: Color = isConfirming ? accentColor.opacity(0.6) : bucBorderColor

        return RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
                    .strokeBorder(borderColor, lineWidth: isConfirming ? 2 : (item.bucKnown && item.bucStatus == .cursed ? 1.5 : 1))
            )
    }

    private var bucBorderColor: Color {
        guard item.bucKnown else { return .white.opacity(0.15) }
        switch item.bucStatus {
        case .blessed: return .green.opacity(0.4)
        case .cursed: return .red.opacity(0.5)
        case .uncursed, .unknown: return .white.opacity(0.15)
        }
    }

    @ViewBuilder
    private var compactBUCIndicator: some View {
        switch item.bucStatus {
        case .blessed:
            Image(systemName: "sparkles")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.green)
        case .cursed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.red)
        case .uncursed, .unknown:
            EmptyView()
        }
    }
}

// MARK: - Press Events Helper

/// Helper extension for detecting press/release events on any View
/// Used for spring animations that respond to touch (SWIFTUI-A-006)
extension View {
    func pressEvents(onPress: @escaping (Bool) -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress(true) }
                .onEnded { _ in onPress(false) }
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ItemSelectionSheet_Previews: PreviewProvider {
    static var previews: some View {
        // Landscape preview - Compact 2-column grid (primary use case)
        ZStack {
            // Dark game background simulation
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                ItemSelectionSheet(
                    context: .quaff(),
                    items: NetHackItem.sampleItems,
                    onSelect: { letter in
                        print("Selected: \(letter)")
                    },
                    onCancel: {
                        print("Cancelled")
                    }
                )
                .padding(.horizontal, 16)
            }
        }
        .previewDisplayName("Quaff - 2-Column Grid")
        .previewInterfaceOrientation(.landscapeLeft)
        .preferredColorScheme(.dark)

        // Empty state preview
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                ItemSelectionSheet(
                    context: .zap(),
                    items: [],
                    onSelect: { _ in },
                    onCancel: { }
                )
                .padding(.horizontal, 16)
            }
        }
        .previewDisplayName("Zap - Empty State")
        .previewInterfaceOrientation(.landscapeLeft)
        .preferredColorScheme(.dark)

        // Multi-category preview (drop all items)
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                ItemSelectionSheet(
                    context: .drop(),
                    items: NetHackItem.sampleItems,
                    onSelect: { _ in },
                    onCancel: { }
                )
                .padding(.horizontal, 16)
            }
        }
        .previewDisplayName("Drop - All Items")
        .previewInterfaceOrientation(.landscapeLeft)
        .preferredColorScheme(.dark)
    }
}
#endif
