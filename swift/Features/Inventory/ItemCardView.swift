import SwiftUI

// MARK: - Item Card View
struct ItemCardView: View {
    let item: NetHackItem
    @State private var isHovered = false
    @State private var showDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            // Top Section: Icon & Enchantment
            ZStack {
                // Background based on rarity
                RoundedRectangle(cornerRadius: 8)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(borderColor, lineWidth: 2)
                    )
                    .frame(height: 60)

                VStack(spacing: 2) {
                    // Item Icon
                    Image(systemName: item.category.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(item.category.color)

                    // Quantity Badge
                    if item.quantity > 1 {
                        Text("\(item.quantity)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                }

                // Enchantment Badge (top right)
                if let enchantment = item.enchantment {
                    VStack {
                        HStack {
                            Spacer()
                            EnchantmentBadge(value: enchantment)
                                .offset(x: 5, y: -5)
                        }
                        Spacer()
                    }
                }

                // Status Indicators (top left)
                VStack {
                    HStack {
                        StatusIndicator(item: item)
                            .offset(x: -5, y: -5)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Item Name (NO TRUNCATION - UX Research requirement!)
            Text(item.fullName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(nil) // Allow unlimited wrapping
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28)

            // Bottom Status Bar
            HStack(spacing: 4) {
                // BUC Indicator - only show if player knows the status!
                if item.bucKnown && item.bucStatus != .unknown {
                    BUCIndicator(status: item.bucStatus)
                }

                Spacer()

                // Quantity indicator for stacks
                if item.quantity > 1 {
                    Label("x\(item.quantity)", systemImage: "square.stack")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
        }
        .padding(6)
        .frame(width: 100, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHovered ? item.rarity.color : Color.white.opacity(0.1), lineWidth: isHovered ? 2 : 1)
        )
        .shadow(color: item.rarity.glowEffect ? item.rarity.color.opacity(0.3) : .clear, radius: 8)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            showDetail.toggle()
        }
        .popover(isPresented: $showDetail) {
            ItemDetailView(item: item)
                .frame(width: 300, height: 400)
        }
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                item.rarity.color.opacity(0.2),
                item.rarity.color.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        if item.properties.isWielded || item.properties.isWorn {
            return .yellow.opacity(0.6)
        }
        return item.rarity.color.opacity(0.5)
    }
}

// MARK: - Enchantment Badge
struct EnchantmentBadge: View {
    let value: Int

    var body: some View {
        Text(value >= 0 ? "+\(value)" : "\(value)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(value >= 0 ? .green : .red)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        Capsule()
                            .strokeBorder(value >= 0 ? Color.green.opacity(0.5) : Color.red.opacity(0.5), lineWidth: 1)
                    )
            )
    }
}

// MARK: - BUC Indicator
struct BUCIndicator: View {
    let status: ItemBUCStatus

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: status.icon)
                .font(.system(size: 10, weight: .bold))
            Text(String(status.rawValue.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(status.color.opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder(status.color.opacity(0.5), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let item: NetHackItem

    var body: some View {
        HStack(spacing: 2) {
            if item.properties.isWielded {
                StatusIcon(icon: "hand.raised.fill", color: .yellow)
            }
            if item.properties.isWorn {
                StatusIcon(icon: "tshirt.fill", color: .blue)
            }
            if item.properties.isQuivered {
                StatusIcon(icon: "arrow.up.bin.fill", color: .orange)
            }
            if item.properties.isPoisoned {
                StatusIcon(icon: "drop.triangle.fill", color: .purple)
            }
            if item.properties.isGreased {
                StatusIcon(icon: "drop.fill", color: .brown)
            }
            if item.properties.isErodeproof {
                StatusIcon(icon: "shield.fill", color: .cyan)
            }
            // Container indicator
            if item.isContainer {
                StatusIcon(
                    icon: item.containerType?.icon ?? "shippingbox.fill",
                    color: item.containerType?.color ?? .orange
                )
            }
        }
    }
}

// MARK: - Status Icon
struct StatusIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(2)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        Circle()
                            .strokeBorder(color.opacity(0.5), lineWidth: 0.5)
                    )
            )
    }
}