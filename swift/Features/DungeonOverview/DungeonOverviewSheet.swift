import SwiftUI

// MARK: - Dungeon Overview Sheet

struct DungeonOverviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = DungeonOverviewService.shared

    var body: some View {
        NavigationStack {
            Group {
                if service.groups.isEmpty {
                    emptyState
                } else {
                    dungeonList
                }
            }
            .navigationTitle("Dungeon Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                service.refreshOverview()
            }
        }
    }

    // MARK: - Dungeon List

    private var dungeonList: some View {
        List {
            ForEach(service.groups) { group in
                Section {
                    ForEach(group.levels) { level in
                        DungeonLevelRow(level: level)
                    }
                } header: {
                    dungeonHeader(group)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Dungeon Header

    private func dungeonHeader(_ group: DungeonGroup) -> some View {
        HStack {
            Text(group.name)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Text(group.depthRange)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Dungeon Data", systemImage: "map")
        } description: {
            Text("Dungeon information will appear here once you explore.")
        }
    }
}

// MARK: - Dungeon Level Row

struct DungeonLevelRow: View {
    let level: DungeonLevel

    var body: some View {
        HStack(spacing: 12) {
            // Level indicator
            levelIndicator

            // Level info
            VStack(alignment: .leading, spacing: 4) {
                levelTitle
                levelDetails
            }

            Spacer()

            // Features
            featureIcons
        }
        .padding(.vertical, 4)
    }

    // MARK: - Level Indicator

    private var levelIndicator: some View {
        ZStack {
            Circle()
                .fill(level.isCurrentLevel ? Color.blue : Color.secondary.opacity(0.2))
                .frame(width: 32, height: 32)

            Text("\(level.depth)")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(level.isCurrentLevel ? .white : .primary)
        }
    }

    // MARK: - Level Title

    private var levelTitle: some View {
        HStack(spacing: 6) {
            Text(level.displayName)
                .font(.subheadline)
                .fontWeight(level.isCurrentLevel ? .semibold : .regular)

            if level.isCurrentLevel {
                Image(systemName: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if level.hasBones {
                Image(systemName: "person.fill.questionmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Level Details

    @ViewBuilder
    private var levelDetails: some View {
        if let annotation = level.annotation, !annotation.isEmpty {
            Text("\"\(annotation)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        } else if let special = level.specialLocationName {
            Text(special)
                .font(.caption)
                .foregroundStyle(.purple)
        } else if let sokoban = level.sokobanStatus {
            Text(sokoban)
                .font(.caption)
                .foregroundStyle(sokoban == "Solved" ? .green : .orange)
        } else if level.branchType != .none, let branchTo = level.branchTo {
            HStack(spacing: 4) {
                Image(systemName: level.branchType.icon)
                    .font(.caption2)
                Text("to \(branchTo)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Feature Icons

    private var featureIcons: some View {
        HStack(spacing: 4) {
            ForEach(level.featureIcons.prefix(4), id: \.icon) { feature in
                featureIcon(feature.icon, count: feature.count)
            }
        }
    }

    private func featureIcon(_ icon: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            if count > 1 {
                Text("\(count)")
                    .font(.system(.caption2, design: .monospaced))
            }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Preview

#Preview {
    DungeonOverviewSheet()
}
