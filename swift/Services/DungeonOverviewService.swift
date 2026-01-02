import Foundation
import SwiftUI
import Combine

// MARK: - Dungeon Overview Service
/// Manages dungeon level data from NetHack bridge
/// Provides cached dungeon overview and grouping functionality
@MainActor
final class DungeonOverviewService: ObservableObject {
    @Published private(set) var levels: [DungeonLevel] = []
    @Published private(set) var groups: [DungeonGroup] = []
    @Published private(set) var lastUpdate: Date?

    // Singleton for global access
    static let shared = DungeonOverviewService()

    private init() {}

    // MARK: - Public API

    /// Refresh dungeon overview from NetHack bridge
    /// Call this when opening dungeon overview or after level change
    func refreshOverview() {
        // First refresh the data in C
        ios_refresh_dungeon_overview()

        let count = Int(ios_get_visited_level_count())
        guard count > 0 else {
            levels = []
            groups = []
            lastUpdate = Date()
            return
        }

        // Fetch all levels
        var fetchedLevels: [DungeonLevel] = []
        for i in 0..<count {
            // Use the C struct type directly (DungeonLevelInfo from RealNetHackBridge.h)
            var cInfo = DungeonLevelInfo()
            guard ios_get_dungeon_level_info(Int32(i), &cInfo) else { continue }

            let level = convertToDungeonLevel(cInfo)
            fetchedLevels.append(level)
        }

        levels = fetchedLevels

        // Group by dungeon
        let grouped = Dictionary(grouping: fetchedLevels) { $0.dungeonNumber }
        groups = grouped.map { dnum, dungeonLevels in
            // Sort levels by depth within each dungeon
            let sortedLevels = dungeonLevels.sorted { $0.depth < $1.depth }
            let dungeonName = sortedLevels.first?.dungeonName ?? "Unknown"
            return DungeonGroup(id: dnum, name: dungeonName, levels: sortedLevels)
        }.sorted { $0.id < $1.id }

        lastUpdate = Date()
        print("[DungeonOverviewService] Refreshed \(levels.count) levels in \(groups.count) dungeons")
    }

    /// Get current level info
    var currentLevel: DungeonLevel? {
        levels.first { $0.isCurrentLevel }
    }

    /// Get levels for a specific dungeon
    func levels(inDungeon dnum: Int) -> [DungeonLevel] {
        levels.filter { $0.dungeonNumber == dnum }.sorted { $0.depth < $1.depth }
    }

    /// Check if any levels are loaded
    var hasLevels: Bool {
        !levels.isEmpty
    }

    /// Get total level count
    var levelCount: Int {
        levels.count
    }

    /// Get dungeon count
    var dungeonCount: Int {
        groups.count
    }

    // MARK: - Private Helpers

    /// Convert C struct to Swift model
    private func convertToDungeonLevel(_ cInfo: DungeonLevelInfo) -> DungeonLevel {
        // Extract strings from C char arrays (Swift imports with original names as tuples)
        let dungeonName = withUnsafePointer(to: cInfo.dungeon_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 64) { charPtr in
                String(cString: charPtr)
            }
        }

        let annotation: String? = withUnsafePointer(to: cInfo.annotation) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 128) { charPtr in
                let str = String(cString: charPtr)
                return str.isEmpty ? nil : str
            }
        }

        let branchTo: String? = withUnsafePointer(to: cInfo.branch_to) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 64) { charPtr in
                let str = String(cString: charPtr)
                return str.isEmpty ? nil : str
            }
        }

        return DungeonLevel(
            id: "\(cInfo.dnum)-\(cInfo.dlevel)",
            dungeonNumber: Int(cInfo.dnum),
            levelNumber: Int(cInfo.dlevel),
            dungeonName: dungeonName,
            depth: Int(cInfo.depth),
            shops: Int(cInfo.shops),
            temples: Int(cInfo.temples),
            altars: Int(cInfo.altars),
            fountains: Int(cInfo.fountains),
            thrones: Int(cInfo.thrones),
            graves: Int(cInfo.graves),
            sinks: Int(cInfo.sinks),
            trees: Int(cInfo.trees),
            shopType: Int(cInfo.shop_type),
            specialFlags: cInfo.special_flags,
            annotation: annotation,
            branchTo: branchTo,
            branchType: DungeonLevel.BranchType(rawValue: Int(cInfo.branch_type)) ?? .none,
            isCurrentLevel: cInfo.is_current_level != 0,
            isForgotten: cInfo.is_forgotten != 0,
            hasBones: cInfo.has_bones != 0
        )
    }
}
