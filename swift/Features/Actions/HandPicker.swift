//
//  HandPicker.swift
//  nethack
//
//  Hand selection picker for ring equipment
//  Allows user to choose left or right hand when putting on a ring
//

import SwiftUI

// MARK: - Hand Picker

/// Hand selection picker for ring equipment
/// Displays two large hand buttons showing current ring status
struct HandPicker: View {
    let onSelect: (Character) -> Void  // 'l' for left, 'r' for right
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var statusManager = CharacterStatusManager.shared

    // Device detection
    private let isPhone = ScalingEnvironment.isPhone

    // Layout constants
    private var containerWidth: CGFloat { isPhone ? 280 : 400 }
    private var containerHeight: CGFloat { isPhone ? 220 : 280 }
    private var handButtonSize: CGFloat { isPhone ? 100 : 140 }
    private var iconSize: CGFloat { isPhone ? 32 : 44 }
    private var titleFontSize: CGFloat { isPhone ? 16 : 20 }
    private var labelFontSize: CGFloat { isPhone ? 14 : 17 }
    private var statusFontSize: CGFloat { isPhone ? 11 : 13 }
    private var cancelButtonHeight: CGFloat { isPhone ? 36 : 44 }

    var body: some View {
        VStack(spacing: isPhone ? 16 : 24) {
            // Title
            Text("Which hand?")
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundColor(.gruvboxForeground)

            // Hand buttons row
            HStack(spacing: isPhone ? 20 : 32) {
                // Left hand
                HandButton(
                    hand: .left,
                    currentRing: currentLeftRing,
                    isAvailable: isLeftAvailable,
                    size: handButtonSize,
                    iconSize: iconSize,
                    labelFontSize: labelFontSize,
                    statusFontSize: statusFontSize
                ) {
                    HapticManager.shared.selection()
                    onSelect("l")
                }

                // Right hand
                HandButton(
                    hand: .right,
                    currentRing: currentRightRing,
                    isAvailable: isRightAvailable,
                    size: handButtonSize,
                    iconSize: iconSize,
                    labelFontSize: labelFontSize,
                    statusFontSize: statusFontSize
                ) {
                    HapticManager.shared.selection()
                    onSelect("r")
                }
            }

            // Cancel button
            Button {
                HapticManager.shared.tap()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: isPhone ? 14 : 16, weight: .medium))
                    .foregroundColor(.gruvboxForeground.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: cancelButtonHeight)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(HandPickerButtonStyle())
            .padding(.horizontal, isPhone ? 20 : 40)
        }
        .padding(isPhone ? 20 : 28)
        .frame(width: containerWidth)
        .background(
            RoundedRectangle(cornerRadius: isPhone ? 16 : 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 16 : 20)
                        .strokeBorder(Color.gruvboxYellow.opacity(0.3), lineWidth: 1)
                )
        )
        .scaleEffect(reduceMotion ? 1.0 : 1.0)  // Initial scale
        .transition(
            reduceMotion
                ? .opacity
                : .scale(scale: 0.8).combined(with: .opacity)
        )
    }

    // MARK: - Computed Properties

    private var currentLeftRing: String? {
        guard let status = statusManager.status else { return nil }
        guard let item = status.item(for: .leftRing), !item.isEmpty else { return nil }
        return item.name
    }

    private var currentRightRing: String? {
        guard let status = statusManager.status else { return nil }
        guard let item = status.item(for: .rightRing), !item.isEmpty else { return nil }
        return item.name
    }

    private var isLeftAvailable: Bool {
        statusManager.status?.leftRingAvailable ?? true
    }

    private var isRightAvailable: Bool {
        statusManager.status?.rightRingAvailable ?? true
    }
}

// MARK: - Hand Type

private enum HandType {
    case left
    case right

    var label: String {
        switch self {
        case .left: return "Left Hand"
        case .right: return "Right Hand"
        }
    }

    var icon: String {
        // Using hand.raised.fill - mirrored appearance handled by scaleEffect
        return "hand.raised.fill"
    }

    var isMirrored: Bool {
        // Left hand should be mirrored horizontally
        self == .left
    }
}

// MARK: - Hand Button

private struct HandButton: View {
    let hand: HandType
    let currentRing: String?
    let isAvailable: Bool
    let size: CGFloat
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let statusFontSize: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    private var statusText: String {
        guard let ring = currentRing else { return "empty" }
        return ring
    }

    private var buttonOpacity: Double {
        isAvailable ? 1.0 : 0.4
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: size * 0.06) {
                // Hand icon
                Image(systemName: hand.icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(isAvailable ? .gruvboxYellow : .gruvboxGray)
                    .scaleEffect(x: hand.isMirrored ? -1 : 1, y: 1)  // Mirror left hand

                // Hand label
                Text(hand.label)
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .foregroundColor(.gruvboxForeground)

                // Divider
                Rectangle()
                    .fill(Color.gruvboxGray.opacity(0.3))
                    .frame(width: size * 0.6, height: 1)

                // Current ring status
                Text(statusText)
                    .font(.system(size: statusFontSize, weight: .regular))
                    .foregroundColor(currentRing != nil ? .gruvboxCyan : .gruvboxGray)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(width: size * 0.8)
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.15)
                    .fill(Color.gruvboxBlack.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.15)
                            .strokeBorder(
                                isAvailable ? Color.gruvboxYellow.opacity(0.4) : Color.gruvboxGray.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            )
            .opacity(buttonOpacity)
            .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
            .animation(AnimationConstants.pressAnimation, value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isAvailable else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("\(hand.label), \(currentRing ?? "empty")")
        .accessibilityHint(isAvailable ? "Double tap to select" : "Not available")
    }
}

// MARK: - Button Style

private struct HandPickerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AnimationConstants.pressScale : 1.0)
            .animation(AnimationConstants.pressAnimation, value: configuration.isPressed)
    }
}

// MARK: - Preview

#if DEBUG
struct HandPicker_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gruvboxBackground.ignoresSafeArea()

            HandPicker(
                onSelect: { hand in
                    print("Selected: \(hand)")
                },
                onCancel: {
                    print("Cancelled")
                }
            )
        }
        .previewDisplayName("Hand Picker")
    }
}
#endif
