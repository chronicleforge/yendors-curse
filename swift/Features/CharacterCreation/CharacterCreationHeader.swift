//
//  CharacterCreationHeader.swift
//  nethack
//
//  Header bar for character creation screen with Back button, Name input, and Start button.
//  Layout: [< Back]     [Name Input][Dice]    [Start >]
//
//  RESPONSIVE DESIGN: Works on ALL devices using ResponsiveLayout
//

import SwiftUI

/// Header bar for character creation screen
/// Contains Back button (left), Name input with random button (center), Start button (right)
struct CharacterCreationHeader: View {
    @Binding var characterName: String
    let onBack: () -> Void
    let onRandomName: () -> Void
    let onStart: () -> Void
    let canStart: Bool
    let geometry: GeometryProxy

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @FocusState private var isNameFieldFocused: Bool

    // MARK: - Computed Properties

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var bodyFontSize: CGFloat {
        ResponsiveLayout.fontSize(.body, for: geometry)
    }

    private var captionFontSize: CGFloat {
        ResponsiveLayout.fontSize(.caption, for: geometry)
    }

    private var spacing: CGFloat {
        ResponsiveLayout.spacing(.small, for: geometry)
    }

    private var buttonHeight: CGFloat {
        ResponsiveLayout.buttonHeight(for: geometry)
    }

    private var cornerRadius: CGFloat {
        ResponsiveLayout.cornerRadius(for: geometry)
    }

    private var screenPadding: CGFloat {
        ResponsiveLayout.screenPadding(for: geometry)
    }

    // MARK: - Animation

    private var buttonAnimation: Animation? {
        reduceMotion ? nil : AnimationConstants.fastSnappy
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: spacing) {
            // Back Button (left)
            backButton

            Spacer(minLength: 0)

            // Name Input (center) - constrained width
            nameInputField
                .layoutPriority(-1)  // Lower priority than buttons

            Spacer(minLength: 0)

            // Start Button (right)
            startButton
        }
        .padding(.vertical, spacing)
        .background(headerBackground)
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: bodyFontSize, weight: .semibold))
                Text("Back")
                    .font(.system(size: bodyFontSize, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, spacing)
            .padding(.vertical, spacing)
            .frame(minHeight: ResponsiveLayout.minimumTouchTarget) // Apple HIG: 44pt minimum
            .contentShape(Rectangle())
        }
        .buttonStyle(HeaderButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Back")
        .accessibilityHint("Returns to previous screen")
    }

    // MARK: - Name Input Field

    private var nameInputField: some View {
        HStack(spacing: spacing) {
            TextField("Enter name...", text: $characterName)
                .font(.system(size: bodyFontSize))
                .foregroundColor(.white)
                .textFieldStyle(.plain)
                .focused($isNameFieldFocused)
                .frame(minWidth: 80, maxWidth: device.isPhone ? 120 : 180)
                .padding(.horizontal, spacing)
                .padding(.vertical, spacing)
                .accessibilityLabel("Character name")
                .accessibilityHint("Enter your character's name")

            // Random name button
            Button(action: onRandomName) {
                Text("🎲")
                    .font(.system(size: bodyFontSize + 2))
                    .frame(minWidth: ResponsiveLayout.minimumTouchTarget,
                           minHeight: ResponsiveLayout.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DiceButtonStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Generate random name")
            .accessibilityHint("Generates a random fantasy name for your character")
        }
        .fixedSize()  // Prevent expansion
        .background(
            RoundedRectangle(cornerRadius: cornerRadius - 4)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius - 4)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 4) {
                Text(device.isPhone ? "Start" : "Begin Adventure")
                    .font(.system(size: bodyFontSize, weight: .semibold))
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: bodyFontSize + 2))
            }
            .foregroundColor(canStart ? .black : .white.opacity(0.5))
            .padding(.horizontal, spacing * 1.5)
            .padding(.vertical, spacing)
            .frame(minHeight: ResponsiveLayout.minimumTouchTarget)
            .background(startButtonBackground)
            .contentShape(Rectangle())
        }
        .disabled(!canStart)
        .buttonStyle(StartButtonStyle(canStart: canStart, reduceMotion: reduceMotion))
        .accessibilityLabel(canStart ? "Start game" : "Start game, disabled")
        .accessibilityHint(canStart ? "Begins your adventure" : "Enter a name to enable")
    }

    // MARK: - Background Views

    @ViewBuilder
    private var startButtonBackground: some View {
        if canStart {
            RoundedRectangle(cornerRadius: cornerRadius - 4)
                .fill(
                    LinearGradient(
                        colors: [.green, Color(red: 0.2, green: 0.8, blue: 0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius - 4)
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius - 4)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
        }
    }

    private var headerBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 50/255, green: 48/255, blue: 47/255).opacity(0.95),
                Color(red: 40/255, green: 38/255, blue: 37/255).opacity(0.9)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Custom Button Styles

/// Button style for header navigation buttons (Back)
private struct HeaderButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(
                reduceMotion ? nil : AnimationConstants.fastSnappy,
                value: configuration.isPressed
            )
    }
}

/// Button style for the dice/random name button
private struct DiceButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .rotationEffect(configuration.isPressed ? .degrees(15) : .zero)
            .animation(
                reduceMotion ? nil : AnimationConstants.bouncyFeedback,
                value: configuration.isPressed
            )
    }
}

/// Button style for the Start button
private struct StartButtonStyle: ButtonStyle {
    let canStart: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && canStart ? 0.95 : 1.0)
            .brightness(configuration.isPressed && canStart ? 0.1 : 0)
            .animation(
                reduceMotion ? nil : AnimationConstants.fastSnappy,
                value: configuration.isPressed
            )
    }
}

// MARK: - Preview

#Preview("Character Creation Header - iPhone") {
    GeometryReader { geometry in
        VStack {
            CharacterCreationHeader(
                characterName: .constant("Aragorn"),
                onBack: { print("Back tapped") },
                onRandomName: { print("Random name tapped") },
                onStart: { print("Start tapped") },
                canStart: true,
                geometry: geometry
            )
            Spacer()
        }
    }
    .frame(width: 390, height: 100) // iPhone 14 Pro width
    .background(Color.gruvboxBackground)
    .preferredColorScheme(.dark)
}

#Preview("Character Creation Header - iPad") {
    GeometryReader { geometry in
        VStack {
            CharacterCreationHeader(
                characterName: .constant(""),
                onBack: { print("Back tapped") },
                onRandomName: { print("Random name tapped") },
                onStart: { print("Start tapped") },
                canStart: false,
                geometry: geometry
            )
            Spacer()
        }
    }
    .frame(width: 1024, height: 100) // iPad width
    .background(Color.gruvboxBackground)
    .preferredColorScheme(.dark)
}

#Preview("Character Creation Header - Empty Name") {
    GeometryReader { geometry in
        VStack {
            CharacterCreationHeader(
                characterName: .constant(""),
                onBack: { print("Back tapped") },
                onRandomName: { print("Random name tapped") },
                onStart: { print("Start tapped") },
                canStart: false,
                geometry: geometry
            )
            Spacer()
        }
    }
    .frame(width: 390, height: 100)
    .background(Color.gruvboxBackground)
    .preferredColorScheme(.dark)
}
