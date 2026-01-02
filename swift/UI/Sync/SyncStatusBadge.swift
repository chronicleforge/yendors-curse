import SwiftUI

/// Compact sync status badge for character cards
/// Shows icon + optional text label for actionable states (Ref: SWIFTUI-A-009)
///
/// Design follows dark roguelike aesthetic:
/// - Capsule with colored background (20% opacity)
/// - Thin border (40% opacity)
/// - Animated rotation for syncing state (respects Reduce Motion)
///
/// Usage:
///   SyncStatusBadge(status: metadata.syncStatus)
struct SyncStatusBadge: View {
    let status: CharacterSyncStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotationDegrees: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            // Icon with rotation for syncing state
            iconView

            // Show text only for actionable states
            if status.needsAction {
                Text(status.shortLabel)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(status.color.opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder(status.color.opacity(0.4), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Icon View

    @ViewBuilder
    private var iconView: some View {
        if status == .syncing {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(rotationDegrees))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotationDegrees = 360
                    }
                }
        } else {
            Image(systemName: status.icon)
                .font(.system(size: 10, weight: .semibold))
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch status {
        case .localOnly:
            return "Stored locally only"
        case .pendingUpload:
            return "Pending upload to iCloud"
        case .syncing:
            return "Syncing with iCloud"
        case .synced:
            return "Synced with iCloud"
        case .downloadedNotSynced:
            return "Modified locally, needs sync"
        case .cloudOnly:
            return "Available in iCloud, tap to download"
        case .conflict:
            return "Sync conflict, tap to resolve"
        }
    }
}

// MARK: - Preview

#Preview("All Sync States") {
    VStack(spacing: 16) {
        ForEach([
            CharacterSyncStatus.localOnly,
            .pendingUpload,
            .syncing,
            .synced,
            .downloadedNotSynced,
            .cloudOnly,
            .conflict
        ], id: \.rawValue) { status in
            HStack {
                Text(status.displayText)
                    .frame(width: 120, alignment: .leading)
                SyncStatusBadge(status: status)
            }
        }
    }
    .padding()
    .background(Color.nethackGray100)
}
