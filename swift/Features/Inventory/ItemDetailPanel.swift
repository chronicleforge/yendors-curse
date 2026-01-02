import SwiftUI

// MARK: - Item Detail Panel
/// Displays comprehensive item information when an item is selected
/// Shows: properties, stats, condition, and context-aware actions
struct ItemDetailPanel: View {
    let item: NetHackItem
    @Environment(NetHackGameManager.self) var gameManager
    @EnvironmentObject var overlayManager: GameOverlayManager

    // Game-style sizing
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Header with item name and icon
                itemHeader

                Divider()

                // Properties Section
                propertiesSection

                // Type-specific Stats Section
                if item.category == .weapons || item.category == .armor || item.category == .food {
                    Divider()
                    statsSection
                }

                // Condition Section
                Divider()
                conditionSection

                // Actions Section
                Divider()
                actionsSection
            }
            .padding(8)
        }
        .background(Color.black.opacity(0.6))
    }

    // MARK: - Header
    private var itemHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            // Category icon with colored background (compact)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.category.color.opacity(0.2))
                    .frame(width: isPhone ? 36 : 44, height: isPhone ? 36 : 44)

                Image(systemName: item.category.icon)
                    .font(.system(size: isPhone ? 16 : 20))
                    .foregroundColor(item.category.color)
            }

            // Item name and category
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fullName)
                    .font(.system(size: isPhone ? 12 : 14, weight: .bold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.category.rawValue)
                    .font(.system(size: isPhone ? 9 : 11))
                    .foregroundColor(.secondary)

                // BUC status badge (only if player knows it!)
                if item.bucKnown && item.bucStatus != .unknown {
                    HStack(spacing: 2) {
                        Image(systemName: item.bucStatus.icon)
                            .font(.system(size: isPhone ? 8 : 9))
                        Text(item.bucStatus.rawValue.capitalized)
                            .font(.system(size: isPhone ? 8 : 9, weight: .bold))
                    }
                    .foregroundColor(item.bucStatus.color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(item.bucStatus.color.opacity(0.2))
                    .cornerRadius(4)
                }
            }

            Spacer()
        }
    }

    // MARK: - Properties Section
    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Properties")
                .font(.system(size: isPhone ? 10 : 12, weight: .bold))
                .foregroundColor(.primary)

            VStack(spacing: 3) {
                // Inventory letter
                PropertyRow(
                    label: "Letter",
                    value: String(item.invlet),
                    icon: "character"
                )

                // Weight
                if item.weight > 0 {
                    PropertyRow(
                        label: "Weight",
                        value: "\(item.weight) aum",
                        icon: "scalemass"
                    )
                }

                // Quantity
                if item.quantity > 1 {
                    PropertyRow(
                        label: "Quantity",
                        value: "\(item.quantity)",
                        icon: "square.stack"
                    )
                }

                // Material (TODO: needs bridge function)
                PropertyRow(
                    label: "Material",
                    value: "Unknown",
                    icon: "cube.fill",
                    isPlaceholder: true
                )

                // Value (if known)
                if let value = item.value {
                    PropertyRow(
                        label: "Value",
                        value: "\(value) zorkmids",
                        icon: "dollarsign.circle"
                    )
                }
            }
        }
    }

    // MARK: - Stats Section (Type-specific)
    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stats")
                .font(.system(size: isPhone ? 10 : 12, weight: .bold))
                .foregroundColor(.primary)

            VStack(spacing: 3) {
                switch item.category {
                case .weapons:
                    weaponStats

                case .armor:
                    armorStats

                case .food:
                    foodStats

                default:
                    EmptyView()
                }
            }
        }
    }

    private var weaponStats: some View {
        Group {
            // Enchantment
            if let enchantment = item.enchantment {
                PropertyRow(
                    label: "Enchantment",
                    value: enchantment >= 0 ? "+\(enchantment)" : "\(enchantment)",
                    icon: "sparkles"
                )
            }

            // Damage (TODO: needs bridge function for weapon damage dice)
            PropertyRow(
                label: "Damage",
                value: item.damage ?? "Unknown",
                icon: "bolt.fill",
                isPlaceholder: item.damage == nil
            )

            // Status
            if item.properties.isWielded {
                StatusBadge(icon: "hand.raised.fill", value: "Wielded", color: .yellow)
            }
            if item.properties.isQuivered {
                StatusBadge(icon: "arrow.up.circle.fill", value: "Quivered", color: .blue)
            }
        }
    }

    private var armorStats: some View {
        Group {
            // AC bonus (TODO: needs bridge function)
            if let ac = item.armorClass {
                PropertyRow(
                    label: "Armor Class",
                    value: "\(ac)",
                    icon: "shield.fill"
                )
            } else {
                PropertyRow(
                    label: "Armor Class",
                    value: "Unknown",
                    icon: "shield.fill",
                    isPlaceholder: true
                )
            }

            // Enchantment
            if let enchantment = item.enchantment {
                PropertyRow(
                    label: "Enchantment",
                    value: enchantment >= 0 ? "+\(enchantment)" : "\(enchantment)",
                    icon: "sparkles"
                )
            }

            // Status
            if item.properties.isWorn {
                StatusBadge(icon: "shield.checkered", value: "Worn", color: .blue)
            }
        }
    }

    private var foodStats: some View {
        Group {
            // Nutrition
            if let nutrition = item.nutrition {
                PropertyRow(
                    label: "Nutrition",
                    value: "\(nutrition)",
                    icon: "flame.fill"
                )
            } else {
                PropertyRow(
                    label: "Nutrition",
                    value: "Unknown",
                    icon: "flame.fill",
                    isPlaceholder: true
                )
            }
        }
    }

    // MARK: - Condition Section
    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Condition")
                .font(.system(size: isPhone ? 10 : 12, weight: .bold))
                .foregroundColor(.primary)

            VStack(spacing: 3) {
                // Erosion
                if item.rustLevel != .none {
                    ConditionRow(
                        label: "Rust",
                        level: item.rustLevel,
                        icon: "drop.fill",
                        color: .orange
                    )
                }

                if item.corrodeLevel != .none {
                    ConditionRow(
                        label: "Corrosion",
                        level: item.corrodeLevel,
                        icon: "flame.fill",
                        color: .green
                    )
                }

                if item.burnLevel != .none {
                    ConditionRow(
                        label: "Burn",
                        level: item.burnLevel,
                        icon: "flame.fill",
                        color: .red
                    )
                }

                if item.rotLevel != .none {
                    ConditionRow(
                        label: "Rot",
                        level: item.rotLevel,
                        icon: "leaf.fill",
                        color: .brown
                    )
                }

                // Special properties
                if item.properties.isGreased {
                    StatusBadge(icon: "drop.fill", value: "Greased", color: .blue)
                }

                if item.properties.isErodeproof {
                    StatusBadge(icon: "shield.fill", value: "Erodeproof", color: .green)
                }

                if item.properties.isPoisoned {
                    StatusBadge(icon: "cross.fill", value: "Poisoned", color: .purple)
                }

                if item.properties.isBroken {
                    StatusBadge(icon: "exclamationmark.triangle.fill", value: "Broken", color: .red)
                }

                // Container-specific
                if item.isContainer {
                    if item.properties.isLocked {
                        StatusBadge(icon: "lock.fill", value: "Locked", color: .red)
                    }
                    if item.properties.isTrapped {
                        StatusBadge(icon: "exclamationmark.triangle.fill", value: "Trapped", color: .orange)
                    }
                }

                // If no conditions, show pristine
                if item.rustLevel == .none &&
                   item.corrodeLevel == .none &&
                   item.burnLevel == .none &&
                   item.rotLevel == .none &&
                   !item.properties.isGreased &&
                   !item.properties.isPoisoned &&
                   !item.properties.isBroken {
                    Text("Pristine condition")
                        .font(.system(size: isPhone ? 9 : 11))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }

    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Actions")
                .font(.system(size: isPhone ? 10 : 12, weight: .bold))
                .foregroundColor(.primary)

            // Compact horizontal flow layout
            FlowLayout(spacing: 6) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        // PRIORITY: Check for containers by name (fallback for broken/misdetected containers)
        // This catches cases where oclass is wrong but item is clearly a container
        if item.effectivelyIsContainer {
            containerActionButtons
        } else {
            categoryActionButtons
        }
    }

    /// Actions for containers (detected by isContainer flag OR name)
    @ViewBuilder
    private var containerActionButtons: some View {
        if item.properties.isLocked {
            // Locked container: Use Apply - NetHack will prompt for key
            ItemActionButton(
                title: "Unlock",
                icon: "lock.open.fill",
                command: "a",
                item: item,
                color: .orange,
                isPrimary: true
            )
        } else {
            // Unlocked container: Loot with native ContainerTransfer UI
            ContainerOpenButton(item: item)
        }
        ItemActionButton(
            title: "Drop",
            icon: "arrow.down.circle.fill",
            command: "d",
            item: item,
            color: .gray
        )
        // Universal action: Name
        ItemActionButton(
            title: "Name",
            icon: "textformat",
            command: "C",
            item: item,
            color: .indigo
        )
    }

    /// Actions based on item category (non-containers)
    @ViewBuilder
    private var categoryActionButtons: some View {
        // Context-aware action buttons based on item category
        switch item.category {
        case .weapons:
            if !item.properties.isWielded {
                ItemActionButton(
                    title: "Wield",
                    icon: "hand.raised.fill",
                    command: "w",
                    item: item,
                    color: .red,
                    isPrimary: true
                )
            }
            ItemActionButton(
                title: "Throw",
                icon: "figure.disc.sports",
                command: "t",
                item: item,
                color: .orange
            )
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .armor:
            if !item.properties.isWorn {
                ItemActionButton(
                    title: "Wear",
                    icon: "shield.fill",
                    command: "W",
                    item: item,
                    color: .blue,
                    isPrimary: true
                )
            } else {
                ItemActionButton(
                    title: "Take Off",
                    icon: "shield.slash.fill",
                    command: "T",
                    item: item,
                    color: .orange,
                    isPrimary: true
                )
            }
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .food:
            ItemActionButton(
                title: "Eat",
                icon: "fork.knife",
                command: "e",
                item: item,
                color: .green,
                isPrimary: true
            )
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .potions:
            ItemActionButton(
                title: "Quaff",
                icon: "drop.fill",
                command: "q",
                item: item,
                color: .purple,
                isPrimary: true
            )
            ItemActionButton(
                title: "Throw",
                icon: "figure.disc.sports",
                command: "t",
                item: item,
                color: .orange
            )
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .scrolls:
            ItemActionButton(
                title: "Read",
                icon: "doc.text.fill",
                command: "r",
                item: item,
                color: .orange,
                isPrimary: true
            )
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .spellbooks:
            ItemActionButton(
                title: "Read",
                icon: "book.fill",
                command: "r",
                item: item,
                color: .orange,
                isPrimary: true
            )
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .wands:
            ItemActionButton(
                title: "Zap",
                icon: "bolt.fill",
                command: "z",
                item: item,
                color: .yellow,
                isPrimary: true
            )
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .tools:
            // Note: Containers are handled globally by effectivelyIsContainer check
            // This case only handles non-container tools (lamps, keys, etc.)
            ItemActionButton(
                title: "Apply",
                icon: "wrench.fill",
                command: "a",
                item: item,
                color: .brown,
                isPrimary: true
            )
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .rings, .amulets:
            if !item.properties.isWorn {
                ItemActionButton(
                    title: "Put On",
                    icon: "circle.fill",
                    command: "P",
                    item: item,
                    color: .yellow,
                    isPrimary: true
                )
            } else {
                ItemActionButton(
                    title: "Remove",
                    icon: "circle.slash.fill",
                    command: "R",
                    item: item,
                    color: .orange,
                    isPrimary: true
                )
            }
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        case .gems:
            ItemActionButton(
                title: "Throw",
                icon: "figure.disc.sports",
                command: "t",
                item: item,
                color: .orange,
                isPrimary: true
            )
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )

        default:
            ItemActionButton(
                title: "Drop",
                icon: "arrow.down.circle.fill",
                command: "d",
                item: item,
                color: .gray
            )
        }

        // Universal action: Name
        ItemActionButton(
            title: "Name",
            icon: "textformat",
            command: "C",
            item: item,
            color: .indigo
        )
    }
}

// MARK: - Supporting Views

struct PropertyRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    var isPlaceholder: Bool = false

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: isPhone ? 10 : 12))
                    .foregroundColor(.secondary)
                    .frame(width: isPhone ? 14 : 16)
            }
            Text(label)
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(isPlaceholder ? .secondary : .primary)
                .italic(isPlaceholder)
        }
    }
}

struct ConditionRow: View {
    let label: String
    let level: ItemErosion
    var icon: String? = nil
    var color: Color = .primary

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: isPhone ? 10 : 12))
                    .foregroundColor(color)
                    .frame(width: isPhone ? 14 : 16)
            }
            Text(label)
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(level.description)
                .font(.system(size: isPhone ? 10 : 12))
                .foregroundColor(color)
        }
    }
}

struct ItemActionButton: View {
    let title: String
    let icon: String
    let command: String
    let item: NetHackItem
    var color: Color = .blue
    var isPrimary: Bool = false

    @Environment(NetHackGameManager.self) var gameManager
    @EnvironmentObject var overlayManager: GameOverlayManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var isPressed: Bool = false

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        Button(action: executeAction) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isPhone ? 11 : 13))
                    .foregroundColor(.white)

                Text(title)
                    .font(.system(size: isPhone ? 11 : 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(isPrimary ? 0.9 : 0.7))
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

    func executeAction() {
        // Haptic feedback - SWIFTUI-HIG-002
        let generator = UIImpactFeedbackGenerator(style: isPrimary ? .medium : .light)
        generator.impactOccurred()

        // Visual feedback
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPressed = false
        }

        guard let commandAscii = command.first?.asciiValue else {
            return
        }

        // Close inventory FIRST to prevent dialogs appearing behind it
        overlayManager.closeOverlay()

        // Commands that trigger NetHack's own menu (different selectors than invlet)
        // For these, just queue the command - NetHack's menu will show via ios_winprocs
        let menuTriggerCommands = ["R", "T"]  // Remove, Take off - use NetHack's native menu

        if menuTriggerCommands.contains(command) {
            // Only queue command - let NetHack show its menu for item selection
            ios_queue_input(Int8(commandAscii))
            return
        }

        // Standard commands: queue command + invlet atomically
        guard let invletAscii = item.invlet.asciiValue else {
            return
        }

        ios_queue_input(Int8(commandAscii))
        ios_queue_input(Int8(invletAscii))

        // Commands that trigger "Do it? [yn]" confirmation - auto-confirm since
        // user already confirmed by tapping the action button in inventory
        let autoConfirmCommands = ["e", "q", "r"]  // eat, quaff, read
        if autoConfirmCommands.contains(command) {
            ios_queue_input(Int8(Character("y").asciiValue!))
        }
    }
}

/// Special button for looting containers with the transfer UI
struct ContainerOpenButton: View {
    let item: NetHackItem

    @EnvironmentObject var overlayManager: GameOverlayManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var isPressed: Bool = false

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        Button(action: openContainer) {
            HStack(spacing: 4) {
                Image(systemName: item.properties.isLocked ? "lock.fill" : "shippingbox.fill")
                    .font(.system(size: isPhone ? 11 : 13))
                    .foregroundColor(.white)

                Text(item.properties.isLocked ? "Locked" : "Loot")
                    .font(.system(size: isPhone ? 11 : 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(item.properties.isLocked ? Color.red.opacity(0.7) : Color.brown.opacity(0.9))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(item.properties.isLocked)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15),
            value: isPressed
        )
    }

    func openContainer() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Visual feedback
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPressed = false
        }

        // Open container transfer view
        overlayManager.openInventoryContainer(item)
    }
}

// MARK: - Preview
struct ItemDetailPanel_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailPanel(item: NetHackItem.sampleItems[0])
            .preferredColorScheme(.dark)
    }
}
