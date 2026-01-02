import SwiftUI

// MARK: - Item Detail View (Tooltip)
struct ItemDetailView: View {
    let item: NetHackItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Main Info Section
                    mainInfoSection

                    // Properties Section
                    if hasProperties {
                        propertiesSection
                    }

                    // Stats Section
                    if hasStats {
                        statsSection
                    }

                    // Description
                    if let description = item.description {
                        descriptionSection(description)
                    }

                    // Actions
                    actionsSection
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(item.rarity.color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            // Icon
            ZStack {
                Circle()
                    .fill(item.category.color.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: item.category.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(item.category.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Full name with all modifiers
                Text(item.displayName)
                    .font(.headline)
                    .foregroundColor(.white)

                // Category & Rarity
                HStack {
                    Label(item.category.rawValue, systemImage: item.category.icon)
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("•")
                        .foregroundColor(.gray)

                    Text(rarityText)
                        .font(.caption.bold())
                        .foregroundColor(item.rarity.color)
                }
            }

            Spacer()

            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Main Info Section
    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // BUC Status - only show if player knows it!
            if item.bucKnown && item.bucStatus != .unknown {
                HStack {
                    Text("Status:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    HStack(spacing: 4) {
                        Image(systemName: item.bucStatus.icon)
                        Text(item.bucStatus.rawValue.capitalized)
                    }
                    .font(.caption.bold())
                    .foregroundColor(item.bucStatus.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(item.bucStatus.color.opacity(0.2))
                            .overlay(
                                Capsule()
                                    .strokeBorder(item.bucStatus.color.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
            }

            // Identification Status
            HStack {
                Text("Identified:")
                    .font(.caption)
                    .foregroundColor(.gray)
                Image(systemName: item.isIdentified ? "checkmark.circle.fill" : "questionmark.circle")
                    .foregroundColor(item.isIdentified ? .green : .orange)
                Text(item.isIdentified ? "Yes" : "No")
                    .font(.caption.bold())
                    .foregroundColor(item.isIdentified ? .green : .orange)
            }

            // Quantity only
            if item.quantity > 1 {
                HStack {
                    Text("Quantity:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(item.quantity)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Properties Section
    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROPERTIES")
                .font(.caption.bold())
                .foregroundColor(.gray)

            FlowLayout(spacing: 8) {
                if item.properties.isWielded {
                    PropertyBadge(text: "Wielded", icon: "hand.raised.fill", color: .yellow)
                }
                if item.properties.isWorn {
                    PropertyBadge(text: "Worn", icon: "tshirt.fill", color: .blue)
                }
                if item.properties.isQuivered {
                    PropertyBadge(text: "Quivered", icon: "arrow.up.bin.fill", color: .orange)
                }
                if item.properties.isGreased {
                    PropertyBadge(text: "Greased", icon: "drop.fill", color: .brown)
                }
                if item.properties.isPoisoned {
                    PropertyBadge(text: "Poisoned", icon: "drop.triangle.fill", color: .purple)
                }
                if item.properties.isErodeproof {
                    PropertyBadge(text: "Erodeproof", icon: "shield.fill", color: .cyan)
                }
                if item.rustLevel != .none {
                    PropertyBadge(text: "Rusty (\(item.rustLevel.description))", icon: "exclamationmark.triangle", color: .orange)
                }
                if item.corrodeLevel != .none {
                    PropertyBadge(text: "Corroded (\(item.corrodeLevel.description))", icon: "exclamationmark.triangle", color: .green)
                }
            }
        }
    }

    // MARK: - Stats Section
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATS")
                .font(.caption.bold())
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 4) {
                if let enchantment = item.enchantment {
                    StatRow(label: "Enchantment", value: enchantment >= 0 ? "+\(enchantment)" : "\(enchantment)",
                           color: enchantment >= 0 ? .green : .red)
                }
                if let damage = item.damage {
                    StatRow(label: "Damage", value: damage, color: .red)
                }
                if let ac = item.armorClass {
                    StatRow(label: "Armor Class", value: "\(ac)", color: .blue)
                }
                if let charges = item.charges {
                    StatRow(label: "Charges", value: "\(charges)", color: .purple)
                }
                if let nutrition = item.nutrition {
                    StatRow(label: "Nutrition", value: "\(nutrition)", color: .green)
                }
                if let value = item.value {
                    StatRow(label: "Value", value: "\(value) gold", color: .yellow)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIPTION")
                .font(.caption.bold())
                .foregroundColor(.gray)

            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }

    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 8) {
            Text("ACTIONS")
                .font(.caption.bold())
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if item.category == .weapons && !item.properties.isWielded {
                    ActionButton(title: "Wield", icon: "hand.raised.fill", color: .yellow)
                }
                if item.category == .armor && !item.properties.isWorn {
                    ActionButton(title: "Wear", icon: "tshirt.fill", color: .blue)
                }
                if item.category == .food {
                    ActionButton(title: "Eat", icon: "fork.knife", color: .green)
                }
                ActionButton(title: "Drop", icon: "arrow.down.circle", color: .red)
            }
        }
    }

    // MARK: - Helper Properties
    private var hasProperties: Bool {
        item.properties.isWielded || item.properties.isWorn || item.properties.isQuivered ||
        item.properties.isGreased || item.properties.isPoisoned || item.properties.isErodeproof ||
        item.rustLevel != .none || item.corrodeLevel != .none
    }

    private var hasStats: Bool {
        item.enchantment != nil || item.damage != nil || item.armorClass != nil ||
        item.charges != nil || item.nutrition != nil || item.value != nil
    }

    private var rarityText: String {
        switch item.rarity {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .legendary: return "Legendary"
        case .cursed: return "Cursed"
        }
    }
}

// MARK: - Property Badge
struct PropertyBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.5), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Stat Row
struct StatRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(color)
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(color)
            .frame(width: 60, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(color.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }

                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))

                x += size.width + spacing
                maxHeight = max(maxHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: y + maxHeight)
        }
    }
}