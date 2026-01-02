/*
 * ObjectBridgeWrapper.swift - Swift Wrapper for ios_object_bridge.h
 *
 * IMPORTANT: This file provides Swift-friendly access to the NetHack object
 * detection bridge. NO game logic - only bridging to C functions.
 *
 * References (SWIFTUI-P-001):
 * - claude-files/nethack_object_detection_research.md
 * - nethack/ios_object_bridge.h
 * - claude-files/context_sensitive_actions_research.md
 */

import Foundation

// MARK: - C Function Import for Container Detection
@_silgen_name("ios_has_container_at")
private func _ios_has_container_at(_ x: Int32, _ y: Int32) -> Int32

// MARK: - Swift-friendly Terrain Info Struct

struct TerrainInfo {
    let name: String
    let type: Int32
    let icon: String
    let isStairsUp: Bool
    let isStairsDown: Bool
    let isLadder: Bool
    let doorState: Int32
    let character: Character
}

// MARK: - Swift-friendly Object Info Struct

struct GameObjectInfo: Identifiable {
    let id: UUID = UUID()
    let name: String
    let type: Int32
    let objectClass: Int32  // NetHack object class (FOOD_CLASS=7, POTION_CLASS=8, etc.)
    let quantity: Int
    let enchantment: Int32
    let blessed: Bool
    let cursed: Bool
    let bucKnown: Bool
    let chargesKnown: Bool
    let descriptionKnown: Bool
    let objectID: UInt32

    // MARK: - NetHack Object Class Constants
    // From origin/NetHack/include/objclass.h
    static let RANDOM_CLASS: Int32 = 0
    static let ILLOBJ_CLASS: Int32 = 1
    static let WEAPON_CLASS: Int32 = 2
    static let ARMOR_CLASS: Int32 = 3
    static let RING_CLASS: Int32 = 4
    static let AMULET_CLASS: Int32 = 5
    static let TOOL_CLASS: Int32 = 6
    static let FOOD_CLASS: Int32 = 7
    static let POTION_CLASS: Int32 = 8
    static let SCROLL_CLASS: Int32 = 9
    static let SPBOOK_CLASS: Int32 = 10
    static let WAND_CLASS: Int32 = 11
    static let COIN_CLASS: Int32 = 12
    static let GEM_CLASS: Int32 = 13
    static let ROCK_CLASS: Int32 = 14
    static let BALL_CLASS: Int32 = 15
    static let CHAIN_CLASS: Int32 = 16
    static let VENOM_CLASS: Int32 = 17

    /// Check if this object is food (class == FOOD_CLASS)
    var isFood: Bool { objectClass == Self.FOOD_CLASS }

    /// Check if this object is a potion (class == POTION_CLASS)
    var isPotion: Bool { objectClass == Self.POTION_CLASS }

    // MARK: - Computed Properties for UI

    /// BUC status only for items where it matters (not gold/gems)
    var bucStatus: String {
        guard bucKnown else { return "" }

        // FILTER: Don't show BUC for items where it doesn't matter
        let lowercaseName = name.lowercased()

        // Gold and gems don't have BUC
        if lowercaseName.contains("gold") || lowercaseName.contains("coin") {
            return ""
        }
        if lowercaseName.contains("gem") || lowercaseName.contains("stone") {
            return ""
        }

        // Show BUC for everything else
        if blessed { return "blessed" }
        if cursed { return "cursed" }
        return "uncursed"
    }

    /// Name stripped of BUC prefix and quantity - for compact display
    /// "uncursed +1 ring mail" → "+1 ring mail"
    var cleanName: String {
        var result = name

        // Remove quantity prefix
        if quantity > 1 {
            let quantityPrefix = "\(quantity) "
            if result.hasPrefix(quantityPrefix) {
                result = String(result.dropFirst(quantityPrefix.count))
            }
        }

        // Remove a/an article
        if result.hasPrefix("a ") {
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("an ") {
            result = String(result.dropFirst(3))
        }

        // Remove BUC prefix (blessed, uncursed, cursed)
        let bucPrefixes = ["blessed ", "uncursed ", "cursed "]
        for prefix in bucPrefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }

        return result.isEmpty ? name : result
    }

    var displayName: String {
        guard quantity > 0 else { return cleanName }
        if quantity == 1 { return cleanName }
        // NetHack format: "5 daggers" not "dagger (5)"
        return "\(quantity) \(cleanName)"
    }

    var enchantmentDisplay: String? {
        guard chargesKnown, enchantment != 0 else { return nil }
        return enchantment > 0 ? "+\(enchantment)" : "\(enchantment)"
    }

    // MARK: - Priority Scoring (for sorting)

    var priority: Int {
        var score = 0

        // CRITICAL: Healing items (highest priority)
        if name.contains("potion of healing") || name.contains("potion of full healing") {
            score += 100
        }

        // HIGH: Food if player might be hungry
        if name.contains("food ration") || name.contains("corpse") {
            score += 50
        }

        // MEDIUM: Beneficial items
        if blessed { score += 30 }
        if cursed { score -= 30 } // Cursed items lower priority

        // MEDIUM: Enchanted items
        if enchantment > 0 { score += Int(enchantment) * 10 }
        if enchantment < 0 { score -= Int(abs(enchantment)) * 10 }

        // LOW: Quantity matters for stackable items
        if quantity > 1 { score += min(5, quantity / 10) }

        return score
    }

    // MARK: - Icon Mapping (emoji-based)

    var icon: String {
        let lowercaseName = name.lowercased()

        // Potions
        if lowercaseName.contains("potion") { return "🧪" }

        // Scrolls
        if lowercaseName.contains("scroll") { return "📜" }

        // Wands
        if lowercaseName.contains("wand") { return "🪄" }

        // Jewelry
        if lowercaseName.contains("ring") { return "💍" }
        if lowercaseName.contains("amulet") { return "📿" }

        // Food
        if lowercaseName.contains("food") || lowercaseName.contains("corpse")
            || lowercaseName.contains("ration") || lowercaseName.contains("fruit") {
            return "🍖"
        }

        // Armor
        if lowercaseName.contains("armor") || lowercaseName.contains("helmet")
            || lowercaseName.contains("cloak") || lowercaseName.contains("boots")
            || lowercaseName.contains("shield") || lowercaseName.contains("gauntlet") {
            return "👕"
        }

        // Weapons
        if lowercaseName.contains("sword") || lowercaseName.contains("dagger")
            || lowercaseName.contains("axe") || lowercaseName.contains("spear")
            || lowercaseName.contains("bow") || lowercaseName.contains("arrow") {
            return "⚔️"
        }

        // Gems & Stones
        if lowercaseName.contains("gem") || lowercaseName.contains("stone")
            || lowercaseName.contains("diamond") || lowercaseName.contains("ruby") {
            return "💎"
        }

        // Keys & Tools
        if lowercaseName.contains("key") || lowercaseName.contains("lock pick") {
            return "🔑"
        }

        // Gold
        if lowercaseName.contains("gold") || lowercaseName.contains("coin") {
            return "💰"
        }

        // Spellbooks
        if lowercaseName.contains("book") || lowercaseName.contains("spellbook") {
            return "📖"
        }

        return "📦" // Default for unknown items
    }
}

// MARK: - Bridge Wrapper

class ObjectBridgeWrapper {

    // Maximum objects per tile (safety buffer)
    // Research shows typical: 1-10, large hoards: 50+, practical limit: ~200
    private static let maxObjects = 100

    /// Get all objects at a specific map position
    /// - Parameters:
    ///   - x: Map X coordinate
    ///   - y: Map Y coordinate
    /// - Returns: Array of GameObjectInfo sorted by priority (highest first)
    static func getObjectsAt(x: Int32, y: Int32) -> [GameObjectInfo] {
        // Guard: Validate coordinates
        guard x >= 0, y >= 0 else {
            return []
        }

        // Allocate buffer for C bridge (SWIFTUI-P-002: avoid expensive calculations)
        var buffer = [IOSObjectInfo](repeating: IOSObjectInfo(), count: maxObjects)

        // Call C bridge function
        let count = buffer.withUnsafeMutableBufferPointer { bufferPtr -> Int32 in
            guard let baseAddress = bufferPtr.baseAddress else { return 0 }
            return ios_get_objects_at(x, y, baseAddress, Int32(maxObjects))
        }

        guard count > 0 else {
            return []
        }

        // Convert to Swift-friendly structs
        let objects = (0..<Int(count)).compactMap { i -> GameObjectInfo? in
            let info = buffer[i]

            // Convert C string to Swift String (CRITICAL: xname() circular buffer!)
            let name = withUnsafePointer(to: info.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { charPtr in
                    String(cString: charPtr)
                }
            }

            guard !name.isEmpty else { return nil }

            return GameObjectInfo(
                name: name,
                type: info.otyp,
                objectClass: info.oclass,
                quantity: Int(info.quantity),
                enchantment: info.enchantment,
                blessed: info.blessed,
                cursed: info.cursed,
                bucKnown: info.bknown,
                chargesKnown: info.known,
                descriptionKnown: info.dknown,
                objectID: info.o_id
            )
        }

        // Sort by priority (highest first) - healing potions, food, blessed items, enchanted
        return objects.sorted { $0.priority > $1.priority }
    }

    /// Get terrain/furniture information at a specific map position
    /// - Parameters:
    ///   - x: Map X coordinate
    ///   - y: Map Y coordinate
    /// - Returns: TerrainInfo if special terrain found, nil if ordinary floor/corridor
    static func getTerrainAt(x: Int32, y: Int32) -> TerrainInfo? {
        // Guard: Validate coordinates
        guard x >= 0, y >= 0 else {
            return nil
        }

        // Create C struct for terrain info
        var info = IOSTerrainInfo()

        // Call C bridge function
        let result = ios_get_terrain_at(x, y, &info)

        guard result != 0 else {
            return nil  // No special terrain (ordinary floor/corridor)
        }

        // Convert C string to Swift String
        let name = withUnsafePointer(to: info.terrain_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 64) { charPtr in
                String(cString: charPtr)
            }
        }

        // Determine emoji icon based on terrain type
        let icon: String
        if info.is_stairs_up {
            icon = "⬆️"
        } else if info.is_stairs_down {
            icon = "⬇️"
        } else if name.contains("door") {
            if info.door_state & 0x08 != 0 {  // D_LOCKED
                icon = "🔒"
            } else if info.door_state & 0x04 != 0 {  // D_CLOSED
                icon = "🚪"
            } else {
                icon = "🚶"  // Open door/doorway
            }
        } else if name.contains("fountain") {
            icon = "⛲"
        } else if name.contains("altar") {
            icon = "🛐"
        } else if name.contains("throne") {
            icon = "👑"
        } else if name.contains("sink") {
            icon = "🚰"
        } else if name.contains("grave") {
            icon = "🪦"
        } else {
            icon = "📍"  // Default for unknown terrain
        }

        // Convert terrain_char (CChar) to Swift Character
        let character = Character(UnicodeScalar(UInt8(info.terrain_char)))

        return TerrainInfo(
            name: name,
            type: info.terrain_type,
            icon: icon,
            isStairsUp: info.is_stairs_up,
            isStairsDown: info.is_stairs_down,
            isLadder: info.is_ladder,
            doorState: info.door_state,
            character: character
        )
    }

    // MARK: - Monster Discovery Functions

    /// Maximum monsters to query from bridge
    private static let maxMonsters = 500

    /// Get all monsters the player has discovered (seen up close)
    /// Returns two arrays: killed monsters and seen-only monsters
    static func getDiscoveredMonsters() -> (killed: [DiscoveredMonster], seenOnly: [DiscoveredMonster]) {
        var buffer = [IOSMonsterInfo](repeating: IOSMonsterInfo(), count: maxMonsters)

        let count = buffer.withUnsafeMutableBufferPointer { bufferPtr -> Int32 in
            guard let baseAddress = bufferPtr.baseAddress else { return 0 }
            return ios_get_discovered_monsters(baseAddress, Int32(maxMonsters))
        }

        guard count > 0 else {
            return (killed: [], seenOnly: [])
        }

        var killed: [DiscoveredMonster] = []
        var seenOnly: [DiscoveredMonster] = []

        for i in 0..<Int(count) {
            let info = buffer[i]

            // Convert C string to Swift String
            let name = withUnsafePointer(to: info.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 64) { charPtr in
                    String(cString: charPtr)
                }
            }

            guard !name.isEmpty else { continue }

            let monster = DiscoveredMonster(
                id: Int(info.monster_index),
                name: name,
                killedCount: Int(info.killed_count)
            )

            if info.killed {
                killed.append(monster)
            } else {
                seenOnly.append(monster)
            }
        }

        // Sort killed by kill count (descending), seen by name (alphabetical)
        killed.sort { $0.killedCount > $1.killedCount }
        seenOnly.sort { $0.name.lowercased() < $1.name.lowercased() }

        return (killed: killed, seenOnly: seenOnly)
    }

    // MARK: - Container Detection

    /// Check if there's a container (bag, box, chest) at the given map position
    /// - Parameters:
    ///   - x: Map X coordinate (NetHack coordinates)
    ///   - y: Map Y coordinate (NetHack coordinates)
    /// - Returns: true if a container is found at the position
    static func hasContainerAt(x: Int32, y: Int32) -> Bool {
        guard x >= 0, y >= 0 else { return false }
        return _ios_has_container_at(x, y) != 0
    }
}

// MARK: - Swift-friendly Monster Discovery Struct

struct DiscoveredMonster: Identifiable, Hashable {
    let id: Int  // monster_index from NetHack
    let name: String
    let killedCount: Int

    /// Display name with first letter capitalized
    var displayName: String {
        name.prefix(1).capitalized + name.dropFirst()
    }

    /// Short description for UI
    var subtitle: String {
        if killedCount > 0 {
            return killedCount == 1 ? "Killed 1" : "Killed \(killedCount)"
        }
        return "Seen"
    }
}
