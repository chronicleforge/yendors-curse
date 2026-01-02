import SwiftUI
import UniformTypeIdentifiers

// MARK: - Fullscreen Inventory View
/// Comprehensive inventory management view with container support
/// Based on iPad RPG UI/UX research (40/60 split recommended)
struct FullscreenInventoryView: View {
    @Environment(NetHackGameManager.self) var gameManager
    @EnvironmentObject var overlayManager: GameOverlayManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedContainer: NetHackItem? = nil
    @State private var selectedItem: NetHackItem? = nil
    @State private var draggedItem: NetHackItem? = nil
    @State private var searchText: String = ""
    @State private var selectedCategory: ItemCategory? = nil

    var playerInventory: [NetHackItem] {
        let items = overlayManager.items

        // Filter by search
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        let _ = print("[FULLSCREEN-INVENTORY] Rendering FullscreenInventoryView - items count: \(overlayManager.items.count)")
        GeometryReader { geometry in
            let _ = print("[FULLSCREEN-INVENTORY] GeometryReader size: \(geometry.size)")
            HStack(spacing: 0) {
                // LEFT PANEL: Player Inventory (40%)
                PlayerInventoryPanel(
                    items: playerInventory,
                    searchText: $searchText,
                    selectedCategory: $selectedCategory,
                    selectedContainer: $selectedContainer,
                    selectedItem: $selectedItem,
                    draggedItem: $draggedItem
                )
                .frame(width: geometry.size.width * 0.4)

                Divider()

                // RIGHT PANEL: Priority order: Container > Selected Item > Empty State
                if let container = selectedContainer {
                    ContainerPanel(
                        container: container,
                        draggedItem: $draggedItem,
                        onClose: {
                            selectedContainer = nil
                            selectedItem = nil
                        }
                    )
                    .frame(width: geometry.size.width * 0.6)
                } else if let item = selectedItem {
                    ItemDetailPanel(item: item)
                        .frame(width: geometry.size.width * 0.6)
                } else {
                    EmptyContainerPanel()
                        .frame(width: geometry.size.width * 0.6)
                }
            }
        }
        .background(.ultraThickMaterial)
    }
}

// MARK: - NetHack Category Order (classic order)
enum NetHackCategoryOrder: Int, CaseIterable {
    case coins = 0
    case amulets = 1
    case weapons = 2
    case armor = 3
    case comestibles = 4
    case scrolls = 5
    case spellbooks = 6
    case potions = 7
    case rings = 8
    case wands = 9
    case tools = 10
    case gems = 11
    case other = 99

    var displayName: String {
        switch self {
        case .coins: return "Coins"
        case .amulets: return "Amulets"
        case .weapons: return "Weapons"
        case .armor: return "Armor"
        case .comestibles: return "Comestibles"
        case .scrolls: return "Scrolls"
        case .spellbooks: return "Spellbooks"
        case .potions: return "Potions"
        case .rings: return "Rings"
        case .wands: return "Wands"
        case .tools: return "Tools"
        case .gems: return "Gems"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .coins: return "$"
        case .amulets: return "\""
        case .weapons: return ")"
        case .armor: return "["
        case .comestibles: return "%"
        case .scrolls: return "?"
        case .spellbooks: return "+"
        case .potions: return "!"
        case .rings: return "="
        case .wands: return "/"
        case .tools: return "("
        case .gems: return "*"
        case .other: return "?"
        }
    }

    static func from(_ category: ItemCategory) -> NetHackCategoryOrder {
        switch category {
        case .coins: return .coins
        case .amulets: return .amulets
        case .weapons: return .weapons
        case .armor: return .armor
        case .food: return .comestibles
        case .scrolls: return .scrolls
        case .spellbooks: return .spellbooks
        case .potions: return .potions
        case .rings: return .rings
        case .wands: return .wands
        case .tools: return .tools
        case .gems: return .gems
        default: return .other
        }
    }
}

// MARK: - Player Inventory Panel (NetHack-style grouped)
struct PlayerInventoryPanel: View {
    let items: [NetHackItem]
    @Binding var searchText: String
    @Binding var selectedCategory: ItemCategory?
    @Binding var selectedContainer: NetHackItem?
    @Binding var selectedItem: NetHackItem?
    @Binding var draggedItem: NetHackItem?
    @EnvironmentObject var overlayManager: GameOverlayManager

    private let isPhone = ScalingEnvironment.isPhone

    // Group items by NetHack category order
    var groupedItems: [(NetHackCategoryOrder, [NetHackItem])] {
        let grouped = Dictionary(grouping: items) { NetHackCategoryOrder.from($0.category) }
        return grouped
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ($0.key, $0.value.sorted { $0.fullName < $1.fullName }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Minimal Header
            HStack {
                Text("Inventory")
                    .font(.system(size: isPhone ? 13 : 15, weight: .bold))
                    .foregroundColor(.nethackGray900)

                Spacer()

                Button(action: { overlayManager.closeOverlay() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.nethackGray500)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 36)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))

            // Grouped Item List
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(groupedItems, id: \.0) { category, categoryItems in
                        Section {
                            ForEach(categoryItems) { item in
                                CompactItemRow(
                                    item: item,
                                    onTap: {
                                        // ALL items show ItemDetailPanel (has Drop, Apply, Open, etc.)
                                        // ContainerPanel was buggy - removed for now
                                        selectedItem = item
                                        selectedContainer = nil
                                    }
                                )
                            }
                        } header: {
                            CategoryHeader(category: category, count: categoryItems.count)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Category Header (NetHack style)
struct CategoryHeader: View {
    let category: NetHackCategoryOrder
    let count: Int
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        HStack(spacing: 6) {
            Text(category.symbol)
                .font(.system(size: isPhone ? 11 : 13, weight: .bold, design: .monospaced))
                .foregroundColor(.nethackAccent)

            Text(category.displayName)
                .font(.system(size: isPhone ? 11 : 13, weight: .semibold))
                .foregroundColor(.nethackGray800)

            Spacer()

            Text("\(count)")
                .font(.system(size: isPhone ? 10 : 11))
                .foregroundColor(.nethackGray500)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
    }
}

// MARK: - Compact Item Row (single line, minimal)
struct CompactItemRow: View {
    let item: NetHackItem
    let onTap: () -> Void
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                // Inventory letter
                Text(String(item.invlet))
                    .font(.system(size: isPhone ? 11 : 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.nethackAccent)
                    .frame(width: 16)

                Text("-")
                    .font(.system(size: isPhone ? 10 : 11, design: .monospaced))
                    .foregroundColor(.nethackGray500)

                // Item name (BUC colored if known)
                Text(item.fullName)
                    .font(.system(size: isPhone ? 11 : 12))
                    .foregroundColor(bucColor)
                    .lineLimit(1)

                Spacer(minLength: 2)

                // Status badges
                if item.properties.isWielded {
                    InlineStatusBadge(text: "wield", color: .nethackWarning)
                } else if item.properties.isWorn {
                    InlineStatusBadge(text: "worn", color: .nethackInfo)
                } else if item.properties.isQuivered {
                    InlineStatusBadge(text: "quiver", color: .nethackAccent)
                }

                if item.isContainer {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.nethackGray500)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.02))
    }

    var bucColor: Color {
        guard item.bucKnown else { return .nethackGray800 }
        switch item.bucStatus {
        case .blessed: return .nethackSuccess
        case .cursed: return .nethackError
        case .uncursed: return .nethackGray800
        case .unknown: return .nethackGray600
        }
    }
}

// MARK: - Inline Status Badge (tiny for inventory rows)
struct InlineStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }
}

// MARK: - Container Panel (glass-morphic)
struct ContainerPanel: View {
    let container: NetHackItem
    @Binding var draggedItem: NetHackItem?
    let onClose: () -> Void
    @Environment(NetHackGameManager.self) var gameManager

    @State private var containerItems: [NetHackItem] = []
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        VStack(spacing: 0) {
            // Container Header - glass-morphic
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: isPhone ? 14 : 16, weight: .medium))
                        .foregroundColor(.nethackGray600)
                        .frame(width: 44, height: 44)  // Touch target
                }
                .buttonStyle(.plain)

                if let type = container.containerType {
                    Image(systemName: type.icon)
                        .font(.system(size: isPhone ? 18 : 20, weight: .bold))
                        .foregroundColor(type.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.fullName)
                        .font(.system(size: isPhone ? 14 : 16, weight: .bold))
                        .foregroundColor(.nethackGray900)
                        .lineLimit(nil) // No truncation!

                    HStack {
                        Text("\(containerItems.count) items")
                            .font(.system(size: isPhone ? 11 : 12))
                            .foregroundColor(.nethackGray500)

                        if let capacity = container.containerCapacity {
                            let totalWeight = containerItems.reduce(0) { $0 + $1.weight }
                            Text("• \(totalWeight)/\(capacity) aum")
                                .font(.system(size: isPhone ? 11 : 12))
                                .foregroundColor(totalWeight > capacity ? .nethackError : .nethackGray500)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                    )
            )

            // Container Contents
            if containerItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "shippingbox")
                        .font(.system(size: isPhone ? 40 : 56))
                        .foregroundColor(.nethackGray400)
                    Text("Empty Container")
                        .font(.system(size: isPhone ? 14 : 16, weight: .bold))
                        .foregroundColor(.nethackGray600)
                    Text("Drag items here to store them")
                        .font(.system(size: isPhone ? 12 : 13))
                        .foregroundColor(.nethackGray500)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(containerItems) { item in
                            InventoryItemRow(item: item, onTap: {})
                                .onDrag {
                                    draggedItem = item
                                    return NSItemProvider(object: item.id as NSString)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
        .alert("Cannot Insert Item", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadContainerContents()
        }
    }

    func loadContainerContents() {
        print("[ContainerPanel] Loading contents for: \(container.fullName)")

        // Check if container is locked
        guard !container.properties.isLocked else {
            errorMessage = "This container is locked. You need a key or lock pick."
            showError = true
            print("[ContainerPanel] Container is locked")
            return
        }

        // Check if container is trapped (traps should trigger)
        if container.properties.isTrapped {
            print("[ContainerPanel] WARNING: Container is trapped!")
            errorMessage = "This container might be trapped! Use '#loot' command carefully."
            showError = true
            // Still allow opening but warn user
        }

        containerItems = gameManager.getContainerContents(container)
        print("[ContainerPanel] Loaded \(containerItems.count) items")
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let item = draggedItem else { return false }

        print("[ContainerPanel] Drop: \(item.fullName) → \(container.fullName)")

        // ✅ CRITICAL: Validate before inserting (prevents BoH explosion!)
        let (canContain, errorMsg) = gameManager.canContain(container: container, item: item)

        guard canContain else {
            errorMessage = errorMsg ?? "Cannot put item in container"
            showError = true
            draggedItem = nil
            return false
        }

        // Send NetHack command to put item in container (atomic)
        // Format: #put then item letter then container letter
        let putCommand = "#put" + String(item.invlet) + String(container.invlet)
        gameManager.sendCommand(putCommand)

        // Reload container contents
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadContainerContents()
        }

        draggedItem = nil
        return true
    }
}

// MARK: - Empty Container Panel (glass-morphic)
struct EmptyContainerPanel: View {
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hand.point.left.fill")
                .font(.system(size: isPhone ? 40 : 56))
                .foregroundColor(.nethackGray400)

            Text("Select an Item")
                .font(.system(size: isPhone ? 16 : 18, weight: .bold))
                .foregroundColor(.nethackGray600)

            Text("Tap any item in your inventory to see available actions")
                .font(.system(size: isPhone ? 13 : 14))
                .foregroundColor(.nethackGray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.02))
                )
        )
    }
}

// MARK: - Inventory Item Row (compact glass-morphic)
struct InventoryItemRow: View {
    let item: NetHackItem
    let onTap: () -> Void
    @EnvironmentObject var overlayManager: GameOverlayManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var isPressed: Bool = false
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Item Icon - compact
                Image(systemName: item.category.icon)
                    .font(.system(size: isPhone ? 14 : 16))
                    .foregroundColor(item.category.color)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(item.category.color.opacity(0.15))
                    )

                // Item Info - single line preferred
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.fullName)
                        .font(.system(size: isPhone ? 12 : 13))
                        .foregroundColor(bucStatusColor(item.bucStatus))
                        .lineLimit(1)

                    // Compact secondary info
                    HStack(spacing: 4) {
                        if item.quantity > 1 {
                            Text("×\(item.quantity)")
                                .font(.system(size: isPhone ? 10 : 11))
                        }
                        if item.isContainer {
                            Text("[\(item.containerItemCount)]")
                                .font(.system(size: isPhone ? 10 : 11))
                                .foregroundColor(.nethackAccent)
                        }
                        if item.properties.isWielded {
                            Text("wielded")
                                .font(.system(size: isPhone ? 10 : 11))
                                .foregroundColor(.nethackWarning)
                        } else if item.properties.isWorn {
                            Text("worn")
                                .font(.system(size: isPhone ? 10 : 11))
                                .foregroundColor(.nethackInfo)
                        }
                    }
                    .foregroundColor(.nethackGray500)
                }

                Spacer(minLength: 4)

                // Compact action or chevron
                if item.isContainer {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.nethackGray500)
                } else if let action = getPrimaryAction(for: item) {
                    CompactActionBadge(action: action)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 40)  // Compact but tappable
            .contentShape(Rectangle())  // Full row is touch target
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.1),
            value: isPressed
        )
    }

    func bucStatusColor(_ status: ItemBUCStatus) -> Color {
        switch status {
        case .blessed: return .nethackSuccess
        case .cursed: return .nethackError
        case .uncursed: return .nethackGray900
        case .unknown: return .nethackGray600
        }
    }

    // Get primary action for item based on category
    func getPrimaryAction(for item: NetHackItem) -> ItemQuickAction? {
        guard !item.isContainer else { return nil }

        switch item.category {
        case .food:
            return ItemQuickAction(
                name: "Eat",
                command: "e",
                icon: "fork.knife",
                color: .green
            )
        case .potions:
            return ItemQuickAction(
                name: "Quaff",
                command: "q",
                icon: "drop.fill",
                color: .purple
            )
        case .armor:
            if item.properties.isWorn {
                return ItemQuickAction(
                    name: "Remove",
                    command: "T",
                    icon: "shield.slash.fill",
                    color: .orange
                )
            } else {
                return ItemQuickAction(
                    name: "Wear",
                    command: "W",
                    icon: "shield.fill",
                    color: .blue
                )
            }
        case .weapons:
            guard !item.properties.isWielded else { return nil }
            return ItemQuickAction(
                name: "Wield",
                command: "w",
                icon: "hand.raised.fill",
                color: .red
            )
        case .wands:
            return ItemQuickAction(
                name: "Zap",
                command: "z",
                icon: "bolt.fill",
                color: .yellow
            )
        case .tools:
            return ItemQuickAction(
                name: "Apply",
                command: "a",
                icon: "wrench.fill",
                color: .orange
            )
        case .scrolls, .spellbooks:
            return ItemQuickAction(
                name: "Read",
                command: "r",
                icon: "doc.text.fill",
                color: .orange
            )
        case .rings, .amulets:
            if item.properties.isWorn {
                return ItemQuickAction(
                    name: "Remove",
                    command: "R",
                    icon: "circle.slash.fill",
                    color: .orange
                )
            } else {
                return ItemQuickAction(
                    name: "Put On",
                    command: "P",
                    icon: "circle.fill",
                    color: .yellow
                )
            }
        default:
            return nil // No primary action for misc items
        }
    }
}

// MARK: - Item Quick Action Model
struct ItemQuickAction {
    let name: String
    let command: String
    let icon: String
    let color: Color
    let needsMenu: Bool // true for getobj-based commands (Drop, Throw, etc.), false for atomic commands (Eat, Quaff)
    let supportsQuantity: Bool // true for actions that can handle multiple items (Drop, Throw, Eat, Quaff, Read)

    init(name: String, command: String, icon: String, color: Color, needsMenu: Bool = false, supportsQuantity: Bool = false) {
        self.name = name
        self.command = command
        self.icon = icon
        self.color = color
        self.needsMenu = needsMenu
        self.supportsQuantity = supportsQuantity
    }
}

// MARK: - Compact Action Badge (for inline row display)
struct CompactActionBadge: View {
    let action: ItemQuickAction
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: action.icon)
                .font(.system(size: 10))
            Text(action.name)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(action.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(action.color.opacity(0.15))
        )
    }
}

// MARK: - Quick Action Button (for detail panel)
struct QuickActionButton: View {
    let action: ItemQuickAction
    let item: NetHackItem
    @Binding var isPressed: Bool

    @EnvironmentObject var overlayManager: GameOverlayManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        Button(action: executeAction) {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: isPhone ? 12 : 14))
                Text(action.name)
                    .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(action.color.opacity(0.85))
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

    func executeAction() {
        // Haptic feedback - SWIFTUI-HIG-002
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Visual feedback
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPressed = false
        }

        // Queue command atomically: command + item letter
        guard let commandAscii = action.command.first?.asciiValue,
              let invletAscii = item.invlet.asciiValue else {
            return
        }

        ios_queue_input(Int8(commandAscii))
        ios_queue_input(Int8(invletAscii))

        // Close inventory after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            overlayManager.closeOverlay()
        }
    }
}

// MARK: - Category Filter Chip (compact)
struct CategoryFilterChip: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    var count: Int? = nil
    let action: () -> Void

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: isPhone ? 10 : 12))
                Text(title)
                    .font(.system(size: isPhone ? 10 : 12, weight: .medium))
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: isPhone ? 9 : 10))
                        .foregroundColor(.nethackGray500)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.2) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? color.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: 0.5
                    )
            )
            .foregroundColor(isSelected ? color : .nethackGray700)
            .contentShape(Capsule())  // Touch target is the whole capsule
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Label (glass-morphic)
struct StatLabel: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let isPhone: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: isPhone ? 12 : 14))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: isPhone ? 12 : 14, weight: .bold))
                .foregroundColor(.nethackGray900)
            Text(label)
                .font(.system(size: isPhone ? 11 : 12))
                .foregroundColor(.nethackGray500)
        }
    }
}

// MARK: - Preview
struct FullscreenInventoryView_Previews: PreviewProvider {
    static var previews: some View {
        FullscreenInventoryView()
            .preferredColorScheme(.dark)
    }
}
