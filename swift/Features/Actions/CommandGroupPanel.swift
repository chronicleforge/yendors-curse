import SwiftUI

// MARK: - Command Group Panel

/// The expanded panel showing 4 quick actions + "More" button.
/// Appears above the group button when expanded.
struct CommandGroupPanel: View {
    let group: CommandGroup
    let manager: CommandGroupManager
    let gameManager: NetHackGameManager
    let overlayManager: GameOverlayManager?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        HStack(spacing: isPhone ? 6 : 10) {
            // Quick actions (up to 4)
            let actions = manager.actions(for: group)
            ForEach(actions.prefix(4)) { action in
                CommandQuickActionButton(
                    action: action,
                    groupColor: group.color,
                    isLastExecuted: manager.lastExecutedAction?.id == action.id,
                    onTap: {
                        HapticManager.shared.tap()
                        manager.executeAction(
                            action,
                            gameManager: gameManager,
                            overlayManager: overlayManager
                        )
                    }
                )
            }

            // "More" button
            MoreButton(groupColor: group.color) {
                HapticManager.shared.tap()
                manager.showFullList(for: group)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(group.color.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Command Quick Action Button

struct CommandQuickActionButton: View {
    let action: NetHackAction
    let groupColor: Color
    let isLastExecuted: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    private var buttonSize: CGFloat {
        isPhone ? 56 : 68
    }

    private var iconSize: CGFloat {
        isPhone ? 20 : 24
    }

    private var labelSize: CGFloat {
        isPhone ? 9 : 10
    }

    /// Short label (max 5 chars)
    private var shortLabel: String {
        let name = action.name
        guard name.count > 5 else { return name }
        return String(name.prefix(5))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Icon in fixed box for consistent alignment
                Image(systemName: action.icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: iconSize + 6, height: iconSize + 6)
                    .foregroundColor(isLastExecuted ? .white : groupColor)

                // Label
                Text(shortLabel)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(width: buttonSize, height: buttonSize)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isLastExecuted ? groupColor : .white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(groupColor.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(CommandButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(action.name)
        .accessibilityHint(action.description)
    }
}

// MARK: - More Button

struct MoreButton: View {
    let groupColor: Color
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    private var buttonHeight: CGFloat {
        isPhone ? 56 : 68
    }

    private var buttonWidth: CGFloat {
        isPhone ? 44 : 52
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(groupColor)

                Text("More")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(groupColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(CommandButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("More actions")
        .accessibilityHint("Opens full list of commands in this category")
    }
}
