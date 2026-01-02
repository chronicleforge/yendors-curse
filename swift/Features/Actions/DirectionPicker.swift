import SwiftUI

// MARK: - Circular Direction Picker
/// Circular 9-direction picker for targeting spells
/// Overlays the navigation control in bottom-left
struct DirectionPicker: View {
    let spell: NetHackSpell
    let onSelect: (Character) -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Device detection
    private let isPhone = ScalingEnvironment.isPhone

    // Direction data: (char, angle in degrees, name, icon)
    // Angles: 0° = right, 90° = down, 180° = left, 270° = up
    private let directions: [(char: Character, angle: Double, name: String, icon: String)] = [
        ("8", 270, "N", "arrow.up"),
        ("9", 315, "NE", "arrow.up.right"),
        ("6", 0, "E", "arrow.right"),
        ("3", 45, "SE", "arrow.down.right"),
        ("2", 90, "S", "arrow.down"),
        ("1", 135, "SW", "arrow.down.left"),
        ("4", 180, "W", "arrow.left"),
        ("7", 225, "NW", "arrow.up.left"),
    ]

    // Layout constants - device-aware to match navigation control
    // Nav control: 150px (iPhone) / 240px (iPad)
    // Picker slightly larger to accommodate direction buttons
    private var wheelSize: CGFloat {
        isPhone ? 180 : 260
    }
    private var centerButtonSize: CGFloat {
        isPhone ? 50 : 70
    }
    private var directionButtonSize: CGFloat {
        isPhone ? 40 : 54
    }
    private var orbitRadius: CGFloat {
        isPhone ? 60 : 90
    }

    var body: some View {
        ZStack {
            // Dark circular background
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: wheelSize, height: wheelSize)

            // Outer ring
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                .frame(width: wheelSize - 10, height: wheelSize - 10)

            // Direction buttons in circle
            ForEach(directions, id: \.char) { dir in
                DirectionWheelButton(
                    icon: dir.icon,
                    label: dir.name,
                    size: directionButtonSize
                ) {
                    hapticFeedback(.medium)
                    onSelect(dir.char)
                }
                .offset(
                    x: orbitRadius * cos(dir.angle * .pi / 180),
                    y: orbitRadius * sin(dir.angle * .pi / 180)
                )
            }

            // Center "Self" button
            Button {
                hapticFeedback(.medium)
                onSelect(".")
            } label: {
                VStack(spacing: isPhone ? 2 : 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: isPhone ? 18 : 24, weight: .semibold))
                    Text("Self")
                        .font(.system(size: isPhone ? 9 : 11, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(width: centerButtonSize, height: centerButtonSize)
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.8))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.red, lineWidth: 2)
                )
            }
            .buttonStyle(ScaleButtonStyle())

            // Spell name badge at top
            VStack {
                HStack(spacing: 6) {
                    Image(systemName: spell.skillType.icon)
                        .foregroundColor(spell.skillType.color)
                    Text(spell.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(spell.powerCost) Pw")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(spell.skillType.color)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.9))
                        .overlay(
                            Capsule()
                                .strokeBorder(spell.skillType.color.opacity(0.5), lineWidth: 1)
                        )
                )
                .offset(y: -wheelSize / 2 - 25)

                Spacer()

                // Cancel hint at bottom
                Text("Tap outside to cancel")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .offset(y: wheelSize / 2 + 15)
            }
        }
        .frame(width: wheelSize, height: wheelSize)
        .transition(
            reduceMotion
                ? .opacity
                : .scale.combined(with: .opacity)
        )
    }

    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Direction Wheel Button

private struct DirectionWheelButton: View {
    let icon: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    // Proportional font sizes based on button size
    private var iconSize: CGFloat { size * 0.4 }
    private var labelSize: CGFloat { size * 0.2 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                Text(label)
                    .font(.system(size: labelSize, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.9))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(Color.gray.opacity(0.3))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
            .animation(AnimationConstants.pressAnimation, value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Action Direction Picker
/// Direction picker for generic actions (not spells)
/// Shows action name/icon instead of spell info
struct ActionDirectionPicker: View {
    let action: NetHackAction
    let onSelect: (Character) -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    private let directions: [(char: Character, angle: Double, name: String, icon: String)] = [
        ("8", 270, "N", "arrow.up"),
        ("9", 315, "NE", "arrow.up.right"),
        ("6", 0, "E", "arrow.right"),
        ("3", 45, "SE", "arrow.down.right"),
        ("2", 90, "S", "arrow.down"),
        ("1", 135, "SW", "arrow.down.left"),
        ("4", 180, "W", "arrow.left"),
        ("7", 225, "NW", "arrow.up.left"),
    ]

    private var wheelSize: CGFloat { isPhone ? 180 : 260 }
    private var centerButtonSize: CGFloat { isPhone ? 50 : 70 }
    private var directionButtonSize: CGFloat { isPhone ? 40 : 54 }
    private var orbitRadius: CGFloat { isPhone ? 60 : 90 }

    // Action category color
    private var accentColor: Color {
        action.categoryEnum.color
    }

    var body: some View {
        ZStack {
            // Dark circular background
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: wheelSize, height: wheelSize)

            // Outer ring with accent color
            Circle()
                .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                .frame(width: wheelSize - 10, height: wheelSize - 10)

            // Direction buttons in circle
            ForEach(directions, id: \.char) { dir in
                DirectionWheelButton(
                    icon: dir.icon,
                    label: dir.name,
                    size: directionButtonSize
                ) {
                    hapticFeedback(.medium)
                    onSelect(dir.char)
                }
                .offset(
                    x: orbitRadius * cos(dir.angle * .pi / 180),
                    y: orbitRadius * sin(dir.angle * .pi / 180)
                )
            }

            // Center "Self" button
            Button {
                hapticFeedback(.medium)
                onSelect(".")
            } label: {
                VStack(spacing: isPhone ? 2 : 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: isPhone ? 18 : 24, weight: .semibold))
                    Text("Self")
                        .font(.system(size: isPhone ? 9 : 11, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(width: centerButtonSize, height: centerButtonSize)
                .background(
                    Circle()
                        .fill(accentColor.opacity(0.8))
                )
                .overlay(
                    Circle()
                        .strokeBorder(accentColor, lineWidth: 2)
                )
            }
            .buttonStyle(ScaleButtonStyle())

            // Action name badge at top
            VStack {
                HStack(spacing: 6) {
                    Image(systemName: action.icon)
                        .foregroundColor(accentColor)
                    Text(action.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.9))
                        .overlay(
                            Capsule()
                                .strokeBorder(accentColor.opacity(0.5), lineWidth: 1)
                        )
                )
                .offset(y: -wheelSize / 2 - 25)

                Spacer()

                // Cancel hint at bottom
                Text("Tap outside to cancel")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .offset(y: wheelSize / 2 + 15)
            }
        }
        .frame(width: wheelSize, height: wheelSize)
        .transition(
            reduceMotion
                ? .opacity
                : .scale.combined(with: .opacity)
        )
    }

    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Compact Direction Picker (for inline use)
/// Smaller direction picker that can be embedded in other views
struct CompactDirectionPicker: View {
    let onSelect: (Character) -> Void
    let accentColor: Color

    private let directions: [(char: Character, icon: String)] = [
        ("7", "arrow.up.left"),
        ("8", "arrow.up"),
        ("9", "arrow.up.right"),
        ("4", "arrow.left"),
        (".", "circle.fill"),
        ("6", "arrow.right"),
        ("1", "arrow.down.left"),
        ("2", "arrow.down"),
        ("3", "arrow.down.right")
    ]

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(36)), count: 3),
            spacing: 4
        ) {
            ForEach(0..<9, id: \.self) { index in
                let dir = directions[index]
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onSelect(dir.char)
                } label: {
                    Image(systemName: dir.icon)
                        .font(.system(size: 14))
                        .foregroundColor(index == 4 ? accentColor : .primary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index == 4 ? accentColor.opacity(0.2) : Color(.systemGray6))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DirectionPicker_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)

            DirectionPicker(
                spell: NetHackSpell.sampleSpells[0],
                onSelect: { dir in
                    print("Direction: \(dir)")
                },
                onCancel: {
                    print("Cancelled")
                }
            )
        }
    }
}
#endif
