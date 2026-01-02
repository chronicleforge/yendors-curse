import SwiftUI

// MARK: - Command Groups (6 Main Categories)

/// The 6 command groups for the bottom action bar.
/// Common first (most-used actions), then categorized groups, More for everything else.
/// Each group supports ⭐ starred actions - user can star up to 4 actions per group.
enum CommandGroup: String, CaseIterable, Identifiable {
    case common = "Common"        // Tier 1: Most frequently used actions
    case combat = "Combat"
    case items = "Items"
    case equipment = "Equipment"
    case magic = "Magic"
    case wizard = "Wizard"        // Wizard mode only - debug commands
    case all = "All"              // All actions alphabetically

    var id: String { rawValue }

    /// Whether this group requires wizard mode to be visible
    var requiresWizardMode: Bool {
        self == .wizard
    }

    /// Get visible groups based on wizard mode status
    static func visibleGroups(wizardModeEnabled: Bool) -> [CommandGroup] {
        if wizardModeEnabled {
            return allCases
        }
        return allCases.filter { !$0.requiresWizardMode }
    }

    // MARK: - Visual Properties

    var icon: String {
        switch self {
        case .common: return "clock.fill"       // Frequent actions
        case .combat: return "bolt.fill"
        case .items: return "cube.box.fill"
        case .equipment: return "tshirt.fill"
        case .magic: return "sparkles"
        case .wizard: return "wand.and.stars"   // Wizard mode
        case .all: return "list.bullet"
        }
    }

    var shortLabel: String {
        switch self {
        case .common: return "Common"
        case .combat: return "Combat"
        case .items: return "Items"
        case .equipment: return "Gear"
        case .magic: return "Magic"
        case .wizard: return "Wizard"
        case .all: return "All"
        }
    }

    /// LCH-based colors for each group
    var color: Color {
        switch self {
        case .common: return Color.lch(l: 65, c: 75, h: 65)    // Gold (accent) - most visible
        case .combat: return Color.lch(l: 55, c: 65, h: 12)    // Red
        case .items: return Color.lch(l: 60, c: 70, h: 45)     // Orange
        case .equipment: return Color.lch(l: 58, c: 50, h: 200) // Cyan
        case .magic: return Color.lch(l: 55, c: 60, h: 290)    // Purple
        case .wizard: return Color.lch(l: 60, c: 70, h: 300)   // Magenta/Pink - debug power
        case .all: return Color.lch(l: 60, c: 40, h: 220)      // Neutral blue-gray
        }
    }

    // MARK: - Default Quick Actions (before user customization)

    /// Default quick actions shown when group is expanded (before user stars any)
    /// Based on frequency analysis from nethack_action_analysis.md
    var defaultQuickActionIDs: [String] {
        switch self {
        case .common:
            // Tier 1: Actions used every 1-5 turns
            return [",", ":", "o", "x"]  // Pickup, Look, Open, Swap Weapons
        case .combat:
            return ["F", "t", "f", "C-d"]  // Attack, Throw, Fire, Kick
        case .items:
            return ["e", "q", "r", "a"]    // Eat, Quaff, Read, Apply
        case .equipment:
            return ["w", "W", "T", "Q"]    // Wield, Wear, Take Off, Quiver
        case .magic:
            return ["Z", "z", "#pray", "#enhance"]  // Cast, Zap, Pray, Enhance
        case .wizard:
            return ["ios_grant_wizard", "#wizwish", "#wizidentify", "#wizmap"]  // Grant, Wish, ID, Map
        case .all:
            return ["s", ":", "\\", "C-x"]  // Search, Look, Discoveries, Attributes
        }
    }

    /// Whether this group supports user starring (all groups do now)
    var supportsStarring: Bool { true }

    // MARK: - Subcategories for Full List

    struct Subcategory: Identifiable {
        let id: String
        let name: String
        let actionIDs: [String]

        var actions: [NetHackAction] {
            actionIDs.compactMap { id in
                NetHackAction.allActions.first { $0.command == id || $0.id == id }
            }
        }
    }

    var subcategories: [Subcategory] {
        switch self {
        case .common:
            // Tier 1 + Tier 2 most frequent actions
            return [
                Subcategory(id: "frequent", name: "Frequent", actionIDs: [".", "s", ",", ":", "i"]),
                Subcategory(id: "navigation", name: "Navigation", actionIDs: ["<", ">", "_", "g", "G"]),
                Subcategory(id: "doors", name: "Doors", actionIDs: ["o", "c", "C-d", "#untrap"])
            ]
        case .combat:
            return [
                Subcategory(id: "melee", name: "Melee", actionIDs: ["F", "C-d", "#twoweapon"]),
                Subcategory(id: "ranged", name: "Ranged", actionIDs: ["t", "f", "Q"]),
                Subcategory(id: "special", name: "Special", actionIDs: ["z", "M-f", "#monster"])
            ]
        case .items:
            return [
                Subcategory(id: "consume", name: "Consumables", actionIDs: ["e", "q", "r"]),
                Subcategory(id: "manage", name: "Management", actionIDs: ["i", ",", "d", "D", "M-a"]),
                Subcategory(id: "use", name: "Use Objects", actionIDs: ["a", "M-d", "#rub"])
            ]
        case .equipment:
            return [
                Subcategory(id: "armor", name: "Armor", actionIDs: ["W", "T"]),
                Subcategory(id: "weapons", name: "Weapons", actionIDs: ["w", "Q", "x", "#twoweapon"]),
                Subcategory(id: "accessories", name: "Accessories", actionIDs: ["P", "R"])
            ]
        case .magic:
            return [
                Subcategory(id: "spells", name: "Spellcasting", actionIDs: ["Z", "z", "#enhance"]),
                Subcategory(id: "divine", name: "Divine", actionIDs: ["#pray", "#turn", "#offer"]),
                Subcategory(id: "powers", name: "Powers", actionIDs: ["M-i", "#monster"])
            ]
        case .wizard:
            return [
                Subcategory(id: "activate", name: "Activate", actionIDs: ["ios_grant_wizard"]),
                Subcategory(id: "creation", name: "Creation", actionIDs: ["#wizwish", "#wizgenesis"]),
                Subcategory(id: "knowledge", name: "Knowledge", actionIDs: ["#wizidentify", "#wizmap", "#wizdetect", "#wizwhere"]),
                Subcategory(id: "power", name: "Power", actionIDs: ["#wizlevelport", "#wizintrinsic"]),
                Subcategory(id: "test_env", name: "Test Environment", actionIDs: ["ios_test_mines", "ios_test_sokoban", "ios_test_gehennom", "ios_test_vlad", "ios_test_astral"])
            ]
        case .all:
            // All actions alphabetically sorted by name
            // Use .id (not .command) because some actions have empty commands
            let sortedIDs = NetHackAction.allActions
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
                .map { $0.id }
            return [Subcategory(id: "all", name: "", actionIDs: sortedIDs)]
        }
    }

    // MARK: - All Actions in Group

    /// All action IDs that belong to this group
    var allActionIDs: [String] {
        subcategories.flatMap { $0.actionIDs }
    }

    /// Get all NetHackAction objects for this group
    var allActions: [NetHackAction] {
        // For .all group, return all actions sorted alphabetically
        if self == .all {
            return NetHackAction.allActions.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
        return allActionIDs.compactMap { id in
            NetHackAction.allActions.first { $0.command == id || $0.id == id }
        }
    }
}

// MARK: - NetHackAction Extension for Group Mapping

extension NetHackAction {
    /// The CommandGroup this action belongs to (computed from category)
    var group: CommandGroup {
        // Wizard actions go to wizard group
        if isWizardOnly {
            return .wizard
        }
        switch categoryEnum {
        case .combat: return .combat
        case .items: return .items
        case .equipment: return .equipment
        case .magic: return .magic
        case .movement, .world, .info: return .all
        case .system: return .all  // System actions go in More
        }
    }

    /// Find action by command string or ID
    static func find(by identifier: String) -> NetHackAction? {
        allActions.first { $0.command == identifier || $0.id == identifier }
    }
}
