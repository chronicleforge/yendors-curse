import Foundation

// MARK: - Dungeon Level Model

/// Represents information about a visited dungeon level
/// Swift model that wraps data from the C struct DungeonLevelInfo
/// Named differently to avoid conflict with the C typedef
struct DungeonLevel: Identifiable, Hashable {
    let id: String  // Unique identifier "dnum-dlevel"
    let dungeonNumber: Int
    let levelNumber: Int
    let dungeonName: String
    let depth: Int

    // Features
    let shops: Int
    let temples: Int
    let altars: Int
    let fountains: Int
    let thrones: Int
    let graves: Int
    let sinks: Int
    let trees: Int
    let shopType: Int

    // Special flags
    let specialFlags: UInt32
    let annotation: String?

    // Branch info
    let branchTo: String?
    let branchType: BranchType

    // State
    let isCurrentLevel: Bool
    let isForgotten: Bool
    let hasBones: Bool

    // MARK: - Branch Type

    enum BranchType: Int {
        case none = 0
        case stairsUp = 1
        case stairsDown = 2
        case portal = 3

        var icon: String {
            switch self {
            case .none: return ""
            case .stairsUp: return "arrow.up"
            case .stairsDown: return "arrow.down"
            case .portal: return "sparkle"
            }
        }

        var description: String {
            switch self {
            case .none: return ""
            case .stairsUp: return "Stairs up"
            case .stairsDown: return "Stairs down"
            case .portal: return "Portal"
            }
        }
    }

    // MARK: - Special Location Flags

    struct SpecialFlags: OptionSet {
        let rawValue: UInt32

        static let oracle = SpecialFlags(rawValue: 1 << 0)
        static let sokobanSolved = SpecialFlags(rawValue: 1 << 1)
        static let bigroom = SpecialFlags(rawValue: 1 << 2)
        static let castle = SpecialFlags(rawValue: 1 << 3)
        static let valley = SpecialFlags(rawValue: 1 << 4)
        static let sanctum = SpecialFlags(rawValue: 1 << 5)
        static let ludios = SpecialFlags(rawValue: 1 << 6)
        static let rogue = SpecialFlags(rawValue: 1 << 7)
        static let vibratingSquare = SpecialFlags(rawValue: 1 << 8)
        static let questHome = SpecialFlags(rawValue: 1 << 9)
        static let questSummons = SpecialFlags(rawValue: 1 << 10)
        static let minetown = SpecialFlags(rawValue: 1 << 11)
    }

    var flags: SpecialFlags {
        SpecialFlags(rawValue: specialFlags)
    }

    // MARK: - Computed Properties

    /// Special location name based on flags
    var specialLocationName: String? {
        if flags.contains(.oracle) { return "Oracle of Delphi" }
        if flags.contains(.castle) { return "The Castle" }
        if flags.contains(.valley) { return "Valley of the Dead" }
        if flags.contains(.sanctum) { return "Moloch's Sanctum" }
        if flags.contains(.ludios) { return "Fort Ludios" }
        if flags.contains(.vibratingSquare) { return "Gateway to Sanctum" }
        if flags.contains(.questHome) { return "Quest Home" }
        if flags.contains(.bigroom) { return "A very big room" }
        if flags.contains(.rogue) { return "A primitive area" }
        return nil
    }

    /// Whether this level has any notable features
    var hasFeatures: Bool {
        shops > 0 || temples > 0 || altars > 0 || fountains > 0 ||
        thrones > 0 || graves > 0 || sinks > 0
    }

    /// Feature icons as array of (icon, count) tuples
    var featureIcons: [(icon: String, count: Int, name: String)] {
        var result: [(String, Int, String)] = []
        if shops > 0 { result.append(("cart.fill", shops, "shop")) }
        if temples > 0 { result.append(("building.columns.fill", temples, "temple")) }
        if altars > 0 { result.append(("star.fill", altars, "altar")) }
        if fountains > 0 { result.append(("drop.fill", fountains, "fountain")) }
        if thrones > 0 { result.append(("crown.fill", thrones, "throne")) }
        if graves > 0 { result.append(("cross.fill", graves, "grave")) }
        if sinks > 0 { result.append(("sink.fill", sinks, "sink")) }
        return result
    }

    /// Display name for the level
    var displayName: String {
        if let special = specialLocationName {
            return special
        }
        return "Level \(depth)"
    }

    /// Sokoban status if applicable
    var sokobanStatus: String? {
        guard dungeonName.contains("Sokoban") else { return nil }
        return flags.contains(.sokobanSolved) ? "Solved" : "Unsolved"
    }
}

// MARK: - Dungeon Group

/// Groups dungeon levels by dungeon for display
struct DungeonGroup: Identifiable {
    let id: Int  // dnum
    let name: String
    let levels: [DungeonLevel]

    var depthRange: String {
        guard let minDepth = levels.map(\.depth).min(),
              let maxDepth = levels.map(\.depth).max() else {
            return ""
        }
        if minDepth == maxDepth {
            return "Level \(minDepth)"
        }
        return "Levels \(minDepth)-\(maxDepth)"
    }

    var containsCurrentLevel: Bool {
        levels.contains { $0.isCurrentLevel }
    }
}
