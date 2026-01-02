//
//  EscapeWarningSheet.swift
//  nethack
//
//  Dramatic warning sheet when player attempts to escape the dungeon
//  without the Amulet of Yendor. The game ends permanently if confirmed.
//
//  Design Pattern: LootOptionsPicker + SkillEnhanceSheet
//  - Glass-morphic background with .ultraThinMaterial
//  - Dramatic red/warning styling for destructive action
//  - Touch targets >= 44pt (Apple HIG)
//  - Reduce Motion support (SWIFTUI-A-009)
//

import SwiftUI

// MARK: - Escape Warning Sheet

/// Dramatic warning sheet displayed when player tries to escape without the Amulet
/// This is a point of no return - escaping ends the game permanently
struct EscapeWarningSheet: View {
    let onConfirm: (Bool) -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconPulse = false
    @State private var appearAnimation = false
    
    // Device detection (Ref: SWIFTUI-L-003 - avoid GeometryReader when possible)
    private let isPhone = ScalingEnvironment.isPhone
    
    // MARK: - Layout Constants
    
    private var containerWidth: CGFloat { isPhone ? 320 : 420 }
    private var iconSize: CGFloat { isPhone ? 56 : 72 }
    private var titleFontSize: CGFloat { isPhone ? 22 : 28 }
    private var bodyFontSize: CGFloat { isPhone ? 14 : 16 }
    private var buttonHeight: CGFloat { isPhone ? 50 : 56 }
    private var buttonFontSize: CGFloat { isPhone ? 16 : 18 }
    
    var body: some View {
        VStack(spacing: isPhone ? 20 : 28) {
            // Warning icon with dramatic glow
            warningIcon
            
            // Title
            Text("Escape the Dungeon?")
                .font(.system(size: titleFontSize, weight: .bold))
                .foregroundColor(.gruvboxForeground)
                .multilineTextAlignment(.center)
            
            // Warning message
            VStack(spacing: 8) {
                Text("You don't have the Amulet of Yendor.")
                    .font(.system(size: bodyFontSize, weight: .medium))
                    .foregroundColor(.gruvboxOrange)
                
                Text("Leaving now means abandoning your quest forever.")
                    .font(.system(size: bodyFontSize))
                    .foregroundColor(.gruvboxForeground.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, isPhone ? 12 : 20)
            
            // Consequence warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: isPhone ? 14 : 16))
                    .foregroundColor(.gruvboxRed)
                
                Text("This action cannot be undone!")
                    .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                    .foregroundColor(.gruvboxRed)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                Capsule()
                    .fill(Color.gruvboxRed.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.gruvboxRed.opacity(0.3), lineWidth: 1)
                    )
            )
            
            // Action buttons
            actionButtons
        }
        .padding(isPhone ? 24 : 32)
        .frame(width: containerWidth)
        .background(
            RoundedRectangle(cornerRadius: isPhone ? 20 : 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 20 : 24)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.gruvboxRed.opacity(0.4),
                                    Color.gruvboxOrange.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .scaleEffect(appearAnimation ? 1.0 : 0.85)
        .opacity(appearAnimation ? 1.0 : 0)
        .transition(
            reduceMotion
                ? .opacity
                : .scale(scale: 0.85).combined(with: .opacity)
        )
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.15)) {
                appearAnimation = true
            }
            
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                iconPulse = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Escape warning dialog")
    }
    
    // MARK: - Warning Icon
    
    private var warningIcon: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.gruvboxRed.opacity(iconPulse ? 0.4 : 0.2),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: iconSize * 1.2
                    )
                )
                .frame(width: iconSize * 2.4, height: iconSize * 2.4)
                .blur(radius: 20)
            
            // Icon background
            Circle()
                .fill(Color.gruvboxRed.opacity(0.2))
                .frame(width: iconSize * 1.4, height: iconSize * 1.4)
                .overlay(
                    Circle()
                        .strokeBorder(Color.gruvboxRed.opacity(0.4), lineWidth: 2)
                )
            
            // Door icon (escaping dungeon)
            Image(systemName: "door.left.hand.open")
                .font(.system(size: iconSize * 0.6, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.gruvboxOrange,
                            Color.gruvboxRed
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .gruvboxRed.opacity(0.5), radius: 8)
                .scaleEffect(iconPulse ? 1.05 : 1.0)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: isPhone ? 12 : 16) {
            // Stay button (primary, safe)
            Button {
                HapticManager.shared.tap()
                withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.1)) {
                    appearAnimation = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onConfirm(false)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: buttonFontSize))
                    Text("Stay")
                        .font(.system(size: buttonFontSize, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.nethackSuccess, Color.gruvboxGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .buttonStyle(EscapeButtonStyle())
            
            // Escape button (destructive)
            Button {
                HapticManager.shared.warning()
                withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.1)) {
                    appearAnimation = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onConfirm(true)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk.departure")
                        .font(.system(size: buttonFontSize))
                    Text("Escape")
                        .font(.system(size: buttonFontSize, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.gruvboxRed, Color.gruvboxRed.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.gruvboxRed.opacity(0.6), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(EscapeButtonStyle())
        }
        .padding(.top, 8)
    }
}

// MARK: - Button Style

private struct EscapeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AnimationConstants.pressScale : 1.0)
            .animation(
                reduceMotion ? nil : AnimationConstants.pressAnimation,
                value: configuration.isPressed
            )
    }
}

// MARK: - Preview

#if DEBUG
struct EscapeWarningSheet_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gruvboxBackground.ignoresSafeArea()
            
            EscapeWarningSheet { confirmed in
                print("Escape confirmed: \(confirmed)")
            }
        }
        .previewDisplayName("Escape Warning Sheet")
    }
}
#endif
