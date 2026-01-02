import SwiftUI

// MARK: - Menu Row
/// Compact pill-shaped row component for NetHack menus
/// Redesigned to match ItemPill from ItemSelectionSheet
struct MenuRow: View {
    let item: NHMenuItem
    let pickMode: NHPickMode
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var isConfirming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone
    private let accentColor = Color.nethackAccent

    // Minimum height for touch target (44pt)
    private var pillHeight: CGFloat { isPhone ? 44 : 48 }

    // MARK: - Body

    var body: some View {
        Button {
            guard item.isSelectable, !isConfirming else { return }

            if pickMode == .one {
                isConfirming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    handleTap()
                }
            } else {
                handleTap()
            }
        } label: {
            HStack(spacing: isPhone ? 6 : 8) {
                // Checkbox (PICK_ANY only)
                if pickMode == .any && item.isSelectable {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: isPhone ? 16 : 18))
                        .foregroundColor(isSelected ? accentColor : .white.opacity(0.4))
                        .frame(width: isPhone ? 24 : 28)
                        .animation(reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.1), value: isSelected)
                }

                // Selector badge (if present)
                if let selector = item.selector {
                    Text(String(selector))
                        .font(.system(size: isPhone ? 12 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(item.isSelectable ? accentColor : Color.white.opacity(0.2))
                        )
                }

                // Item text
                Text(item.text)
                    .font(.system(size: isPhone ? 11 : 13, weight: item.isBold ? .semibold : .medium))
                    .foregroundColor(item.isSelectable ? .white.opacity(0.9) : .white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 4)

                // Count badge (if > 1)
                if item.count > 1 {
                    Text("\u{00D7}\(item.count)")
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, isPhone ? 5 : 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                }

                // Selection indicator (PICK_ONE)
                if pickMode == .one && item.isSelectable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
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
        }
        .buttonStyle(.plain)
        .disabled(!item.isSelectable && pickMode != .none)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard item.isSelectable, !isConfirming else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.itemCardPress, value: isPressed)
        .animation(reduceMotion ? nil : AnimationConstants.selectionConfirmation, value: isConfirming)
        .sensoryFeedback(.impact(weight: .medium), trigger: isConfirming)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(accessibilityTraits)
    }

    // MARK: - Pill Background

    private var pillBackground: some View {
        let fillOpacity: Double = {
            if isConfirming { return 0.2 }
            if isPressed { return 0.12 }
            if isSelected && pickMode == .any { return 0.15 }
            return 0.05
        }()

        let borderColor: Color = {
            if isConfirming { return accentColor.opacity(0.6) }
            if isSelected && pickMode == .any { return accentColor.opacity(0.4) }
            return .white.opacity(0.1)
        }()

        return RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
                    .strokeBorder(borderColor, lineWidth: isConfirming ? 2 : 0.5)
            )
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var label = item.text
        if let sel = item.selector {
            label = "\(sel), \(label)"
        }
        if item.count > 1 {
            label += ", quantity \(item.count)"
        }
        return label
    }

    private var accessibilityHint: String {
        guard item.isSelectable else { return "" }

        switch pickMode {
        case .none: return ""
        case .one: return "Double tap to select"
        case .any: return isSelected ? "Selected, double tap to deselect" : "Double tap to select"
        }
    }

    private var accessibilityTraits: AccessibilityTraits {
        guard item.isSelectable else { return [] }

        switch pickMode {
        case .none: return []
        case .one: return .isButton
        case .any: return isSelected ? [.isButton, .isSelected] : .isButton
        }
    }

    // MARK: - Actions

    private func handleTap() {
        guard item.isSelectable || pickMode == .none else { return }

        switch pickMode {
        case .one:
            HapticManager.shared.selection()
        case .any:
            HapticManager.shared.tap()
        case .none:
            break
        }

        onTap()
    }
}

// MARK: - Preview

#Preview("PICK_NONE") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 4) {
            MenuRow(
                item: .item("a long sword (+2)", selector: "a"),
                pickMode: .none,
                isSelected: false,
                onTap: {}
            )
            MenuRow(
                item: .info("(nothing else)"),
                pickMode: .none,
                isSelected: false,
                onTap: {}
            )
        }
        .padding(12)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("PICK_ONE") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 4) {
            MenuRow(
                item: .item("force bolt (1)", selector: "a"),
                pickMode: .one,
                isSelected: false,
                onTap: {}
            )
            MenuRow(
                item: .item("magic missile (2)", selector: "b"),
                pickMode: .one,
                isSelected: false,
                onTap: {}
            )
        }
        .padding(12)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("PICK_ANY") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 4) {
            MenuRow(
                item: NHMenuItem(selector: "a", text: "5 gold pieces", count: 5),
                pickMode: .any,
                isSelected: true,
                onTap: {}
            )
            MenuRow(
                item: NHMenuItem(selector: "b", text: "a rusty dagger"),
                pickMode: .any,
                isSelected: false,
                onTap: {}
            )
        }
        .padding(12)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}
