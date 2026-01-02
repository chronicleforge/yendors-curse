import SwiftUI

// MARK: - Container Item Row

/// Row for displaying an item with a transfer button
/// Used in both inventory panel (with [>] button) and container panel (with [<] button)
struct ContainerItemRow: View {
    let item: NetHackItem
    let direction: TransferDirection
    let onTransfer: () -> Void
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isPressed = false
    
    private let isPhone = ScalingEnvironment.isPhone
    
    enum TransferDirection {
        case toContainer    // [>] button - put item in container
        case toInventory    // [<] button - take item from container
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Item info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fullName)
                    .font(.system(size: isPhone ? 13 : 14))
                    .foregroundColor(bucColor)
                    .lineLimit(2)
                
                // Status badges
                HStack(spacing: 4) {
                    if item.properties.isWielded {
                        ContainerStatusBadge(text: "wielded", color: .nethackWarning)
                    } else if item.properties.isWorn {
                        ContainerStatusBadge(text: "worn", color: .nethackInfo)
                    } else if item.properties.isQuivered {
                        ContainerStatusBadge(text: "quivered", color: .nethackAccent)
                    }
                    
                    if item.weight > 0 {
                        Text("\(item.weight) aum")
                            .font(.system(size: isPhone ? 10 : 11))
                            .foregroundColor(.nethackGray500)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            // Transfer button
            Button(action: {
                // Haptic feedback - SWIFTUI-HIG-002
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                // Visual feedback
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                }
                
                onTransfer()
            }) {
                Image(systemName: direction == .toContainer ? "chevron.right" : "chevron.left")
                    .font(.system(size: isPhone ? 14 : 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)  // Minimum touch target - SWIFTUI-HIG-001
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(transferButtonColor.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15),  // SWIFTUI-A-001
                value: isPressed
            )
            .disabled(cannotTransfer)
            .opacity(cannotTransfer ? 0.4 : 1.0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .contentShape(Rectangle())  // SWIFTUI-M-003: clipped() doesn't affect hit testing
    }
    
    // MARK: - Computed Properties
    
    private var bucColor: Color {
        guard item.bucKnown else { return .nethackGray800 }
        switch item.bucStatus {
        case .blessed: return .nethackSuccess
        case .cursed: return .nethackError
        case .uncursed: return .nethackGray800
        case .unknown: return .nethackGray600
        }
    }
    
    private var transferButtonColor: Color {
        guard !cannotTransfer else { return .nethackGray500 }
        return direction == .toContainer ? .nethackAccent : .nethackSuccess
    }
    
    /// Check if item cannot be transferred (worn, wielded, cursed)
    private var cannotTransfer: Bool {
        guard direction == .toContainer else { return false }
        
        // Cannot put worn/wielded items in container
        if item.properties.isWorn { return true }
        if item.properties.isWielded { return true }
        
        return false
    }
}

// MARK: - Container Item Row (for ContainerItemInfo)

/// Row for displaying a container item with take button
struct ContainerContentRow: View {
    let item: ContainerItemInfo
    let onTake: () -> Void
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isPressed = false
    
    private let isPhone = ScalingEnvironment.isPhone
    
    var body: some View {
        HStack(spacing: 8) {
            // Item info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: isPhone ? 13 : 14))
                    .foregroundColor(bucColor)
                    .lineLimit(2)
                
                if item.isContainer {
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: isPhone ? 10 : 11))
                            .foregroundColor(.nethackAccent)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            // Take button [<]
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                }
                
                onTake()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: isPhone ? 14 : 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.nethackSuccess.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15),
                value: isPressed
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .contentShape(Rectangle())
    }
    
    private var bucColor: Color {
        switch item.bucStatus {
        case .blessed: return .nethackSuccess
        case .cursed: return .nethackError
        case .uncursed: return .nethackGray800
        case .unknown: return .nethackGray600
        }
    }
}

// MARK: - Container Status Badge

private struct ContainerStatusBadge: View {
    let text: String
    let color: Color
    
    private let isPhone = ScalingEnvironment.isPhone
    
    var body: some View {
        Text(text)
            .font(.system(size: isPhone ? 9 : 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        ContainerItemRow(
            item: NetHackItem(
                invlet: "a",
                name: "+1 long sword",
                fullName: "a +1 long sword (weapon in hand)",
                category: .weapons
            ).with { $0.properties.isWielded = true },
            direction: .toContainer,
            onTransfer: {}
        )
        
        ContainerItemRow(
            item: NetHackItem(
                invlet: "b",
                name: "food ration",
                fullName: "3 food rations",
                category: .food,
                quantity: 3
            ),
            direction: .toContainer,
            onTransfer: {}
        )
    }
    .padding()
    .background(Color.black)
}
