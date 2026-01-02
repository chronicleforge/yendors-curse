import SwiftUI

// MARK: - Command Full List Sheet

/// Full list of commands for a group, organized by subcategory.
/// Optimized 2-column grid layout for landscape mode.
/// Users can ⭐ star actions to make them appear as quick actions for that group.
struct CommandFullListSheet: View {
    let group: CommandGroup
    let manager: CommandGroupManager
    let gameManager: NetHackGameManager
    let overlayManager: GameOverlayManager?

    @Environment(\.dismiss) private var dismiss

    // Check wizard mode to filter actions
    private var isWizardModeEnabled: Bool {
        UserPreferencesManager.shared.isDebugModeEnabled()
    }

    // 2-column adaptive grid for landscape optimization
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                    // Starred actions section (if any starred)
                    starredSection

                    // Subcategories with all actions in grid (filtered by wizard mode)
                    ForEach(group.subcategories) { subcategory in
                        let filteredActions = filterActions(subcategory.actions)
                        if !filteredActions.isEmpty {
                            Section {
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(filteredActions) { action in
                                        CommandTile(
                                            action: action,
                                            groupColor: group.color,
                                            isStarred: manager.isStarred(action, in: group),
                                            onTap: {
                                                executeAndDismiss(action)
                                            },
                                            onToggleStar: {
                                                manager.toggleStar(action, in: group)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 12)
                            } header: {
                                SectionHeader(title: subcategory.name, color: group.color)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color.black.opacity(0.95))
            .navigationTitle(group.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Starred Actions Section

    @ViewBuilder
    private var starredSection: some View {
        let starredActions = filterActions(manager.actions(for: group))
        let hasCustomStars = starredActions.contains { manager.isStarred($0, in: group) }

        if hasCustomStars {
            Section {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(starredActions) { action in
                        CommandTile(
                            action: action,
                            groupColor: group.color,
                            isStarred: true,
                            onTap: {
                                executeAndDismiss(action)
                            },
                            onToggleStar: {
                                manager.toggleStar(action, in: group)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
            } header: {
                SectionHeader(title: "⭐ Quick Actions", color: group.color)
            }
        }
    }

    // MARK: - Helpers

    private func executeAndDismiss(_ action: NetHackAction) {
        HapticManager.shared.tap()
        dismiss()
        // Execute after sheet dismisses
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            manager.executeAction(
                action,
                gameManager: gameManager,
                overlayManager: overlayManager
            )
        }
    }

    /// Filter actions based on wizard mode - hide wizard-only actions unless in debug mode
    private func filterActions(_ actions: [NetHackAction]) -> [NetHackAction] {
        guard !isWizardModeEnabled else { return actions }
        return actions.filter { !$0.isWizardOnly }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let color: Color

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Command Tile (Compact Grid Item)

struct CommandTile: View {
    let action: NetHackAction
    let groupColor: Color
    let isStarred: Bool
    let onTap: () -> Void
    let onToggleStar: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                // Top row: Icon + Name + Star
                HStack(spacing: 6) {
                    // Icon
                    Image(systemName: action.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(groupColor)
                        .frame(width: 22, height: 22)

                    // Name
                    Text(action.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    // Star toggle (smaller)
                    Button(action: {
                        HapticManager.shared.tap()
                        onToggleStar()
                    }) {
                        Image(systemName: isStarred ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(isStarred ? Color.lch(l: 65, c: 75, h: 65) : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }

                // Bottom row: Key badge + Description
                HStack(spacing: 6) {
                    // Compact key badge
                    KeyBadgeCompact(command: action.command, color: groupColor)

                    // Description
                    Text(action.description)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isStarred ? groupColor.opacity(0.12) : .white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isStarred ? groupColor.opacity(0.3) : .white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(CommandTileButtonStyle(reduceMotion: reduceMotion))
    }
}

// MARK: - Compact Key Badge (for tiles)

struct KeyBadgeCompact: View {
    let command: String
    let color: Color

    private var displayKey: String {
        guard !command.isEmpty else { return "-" }

        if command.hasPrefix("#") { return "#" }
        if command.hasPrefix("M-") { return "M" }
        if command.hasPrefix("C-") { return "^" }
        return String(command.prefix(1))
    }

    var body: some View {
        Text(displayKey)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .frame(width: 18, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.2))
            )
    }
}

// MARK: - Tile Button Style

struct CommandTileButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

