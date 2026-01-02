import SwiftUI

// MARK: - Command Group Bar

/// The main bottom bar with 6 command group buttons.
/// Tap a button to expand and show quick actions.
/// Shows Wizard group only when wizard mode is enabled.
struct CommandGroupBar: View {
    let manager: CommandGroupManager
    let gameManager: NetHackGameManager
    let overlayManager: GameOverlayManager?

    @ObservedObject private var userPrefs = UserPreferencesManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    /// Visible command groups based on wizard mode status
    private var visibleGroups: [CommandGroup] {
        CommandGroup.visibleGroups(wizardModeEnabled: userPrefs.isDebugModeEnabled())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Expanded panel (above buttons)
            if let expanded = manager.expandedGroup {
                CommandGroupPanel(
                    group: expanded,
                    manager: manager,
                    gameManager: gameManager,
                    overlayManager: overlayManager
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // Command group buttons (wizard group only visible when enabled)
            HStack(spacing: isPhone ? 4 : 8) {
                ForEach(visibleGroups) { group in
                    CommandGroupButton(
                        group: group,
                        isExpanded: manager.expandedGroup == group,
                        onTap: {
                            HapticManager.shared.tap()
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2)) {
                                manager.toggleExpanded(group)
                            }
                        },
                        onLongPress: {
                            HapticManager.shared.buttonPress()
                            manager.showFullList(for: group)
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            // No container background - individual buttons have their own material
        }
        .sheet(isPresented: Binding(
            get: { manager.showFullList },
            set: { if !$0 { manager.hideFullList() } }
        )) {
            if let group = manager.fullListGroup {
                CommandFullListSheet(
                    group: group,
                    manager: manager,
                    gameManager: gameManager,
                    overlayManager: overlayManager
                )
            }
        }
    }
}

// MARK: - Command Group Button

/// A single group button in the bar
struct CommandGroupButton: View {
    let group: CommandGroup
    let isExpanded: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    private var buttonWidth: CGFloat {
        isPhone ? 54 : 66
    }

    private var buttonHeight: CGFloat {
        isPhone ? 52 : 60
    }

    private var iconSize: CGFloat {
        isPhone ? 20 : 24
    }

    private var labelSize: CGFloat {
        isPhone ? 9 : 10
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: group.icon)
                    .font(.system(size: iconSize, weight: .bold))
                    .frame(width: iconSize + 6, height: iconSize + 6)
                    .foregroundColor(isExpanded ? group.color : .nethackGray700)

                Text(group.shortLabel)
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundColor(isExpanded ? group.color : .nethackGray900)
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isExpanded ? group.color : Color.nethackGray700.opacity(0.4),
                        lineWidth: isExpanded ? 3 : 2
                    )
            )
            .shadow(
                color: isExpanded ? group.color.opacity(0.4) : Color.black.opacity(0.3),
                radius: isExpanded ? 8 : 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(CommandButtonStyle(reduceMotion: reduceMotion))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress() }
        )
        .accessibilityLabel("\(group.rawValue) commands")
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand, long press for all commands")
    }
}

// MARK: - Button Style

struct CommandButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.2),
                value: configuration.isPressed
            )
    }
}
