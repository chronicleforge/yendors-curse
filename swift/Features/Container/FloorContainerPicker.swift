import SwiftUI

// MARK: - Floor Container Picker

/// Sheet for selecting a container from the floor when multiple are present
/// Shows before opening ContainerTransferView
struct FloorContainerPicker: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    let containers: [FloorContainerInfo]
    let onSelect: (FloorContainerInfo) -> Void
    
    private let isPhone = ScalingEnvironment.isPhone
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Container List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(containers) { container in
                        ContainerPickerRow(container: container) {
                            onSelect(container)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            
            // Cancel Button
            cancelButton
                .padding(16)
        }
        .background(.ultraThickMaterial)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Components
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.2.fill")
                .font(.system(size: isPhone ? 20 : 24, weight: .bold))
                .foregroundColor(.nethackAccent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Select Container")
                    .font(.system(size: isPhone ? 17 : 19, weight: .bold))
                    .foregroundColor(.nethackGray900)
                
                Text("\(containers.count) containers here")
                    .font(.system(size: isPhone ? 12 : 13))
                    .foregroundColor(.nethackGray500)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.3))
    }
    
    private var cancelButton: some View {
        Button(action: { dismiss() }) {
            Text("Cancel")
                .font(.system(size: isPhone ? 15 : 16, weight: .semibold))
                .foregroundColor(.nethackGray700)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.nethackGray500.opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Container Picker Row

private struct ContainerPickerRow: View {
    let container: FloorContainerInfo
    let onTap: () -> Void
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isPressed = false
    
    private let isPhone = ScalingEnvironment.isPhone
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            // Visual feedback
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
            
            onTap()
        }) {
            HStack(spacing: 14) {
                // Container icon
                Image(systemName: container.icon)
                    .font(.system(size: isPhone ? 24 : 28, weight: .bold))
                    .foregroundColor(container.iconColor)
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(container.iconColor.opacity(0.15))
                    )
                
                // Container info
                VStack(alignment: .leading, spacing: 4) {
                    Text(container.name)
                        .font(.system(size: isPhone ? 15 : 16, weight: .semibold))
                        .foregroundColor(.nethackGray900)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        // Item count
                        Label("\(container.itemCount) items", systemImage: "cube.fill")
                            .font(.system(size: isPhone ? 11 : 12))
                            .foregroundColor(.nethackGray500)
                        
                        // Status badges
                        if container.isLocked {
                            statusBadge(text: "LOCKED", color: .nethackError)
                        }
                        
                        if container.isTrapped {
                            statusBadge(text: "TRAPPED", color: .nethackWarning)
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.nethackGray500)
            }
            .padding(14)
            .frame(minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        container.isLocked ? Color.nethackError.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15),
            value: isPressed
        )
        .disabled(container.isLocked)
        .opacity(container.isLocked ? 0.6 : 1.0)
    }
    
    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: isPhone ? 9 : 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.2))
            )
    }
}

// MARK: - Preview

#Preview {
    FloorContainerPicker(
        containers: [
            FloorContainerInfo(id: 1, name: "large box", itemCount: 5, isLocked: false, isBroken: false, isTrapped: false),
            FloorContainerInfo(id: 2, name: "chest", itemCount: 0, isLocked: true, isBroken: false, isTrapped: false),
            FloorContainerInfo(id: 3, name: "bag of holding", itemCount: 12, isLocked: false, isBroken: false, isTrapped: false)
        ],
        onSelect: { _ in }
    )
}
