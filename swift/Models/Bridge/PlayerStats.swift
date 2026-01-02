import Foundation

// MARK: - Player Stats Structure
// Extracted from NetHackBridge.swift for better organization

/// Player statistics from the game engine
struct PlayerStats: Codable {
    let hp: Int
    let hpmax: Int
    let pw: Int
    let pwmax: Int
    let level: Int
    let exp: Int
    let ac: Int
    let str: Int
    let dex: Int
    let con: Int
    let int: Int
    let wis: Int
    let cha: Int
    let gold: Int
    let moves: Int
    let dungeonLevel: Int
    let align: String
    let hunger: Int
    let conditions: UInt  // BL_CONDITION bitmask (30 flags)
}
