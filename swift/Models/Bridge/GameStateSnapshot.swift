import Foundation

// MARK: - Game State Snapshot Structs (Push Model)
// Extracted from NetHackBridge.swift for better organization

/// C struct mirror for SnapshotDoorInfo
struct CSnapshotDoorInfo {
    var x: Int32
    var y: Int32
    var dx: Int32
    var dy: Int32
    var is_open: Bool
    var is_closed: Bool
    var is_locked: Bool
    var direction_cmd: CChar
}

/// C struct mirror for SnapshotEnemyInfo
struct CSnapshotEnemyInfo {
    var name: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)  // 64 bytes
    var x: Int32
    var y: Int32
    var distance: Int32
    var hp: Int32
    var max_hp: Int32
    var glyph_char: CChar
    var is_hostile: Bool
    var is_peaceful: Bool
}

/// C struct mirror for GameStateSnapshot
struct CGameStateSnapshot {
    var turn_number: Int32

    // Player stats
    var player_hp: Int32
    var player_max_hp: Int32
    var player_ac: Int32
    var player_level: Int32
    var player_xp: Int32
    var player_gold: Int64  // Gold count (safe from game thread)
    var player_x: Int32
    var player_y: Int32
    var has_container: Bool  // Container at player position
    var has_locked_container: Bool  // Locked container at player position

    // Current tile
    var terrain_type: Int32
    var is_stairs_up: Bool
    var is_stairs_down: Bool
    var is_ladder: Bool
    var is_altar: Bool
    var is_fountain: Bool
    var is_sink: Bool
    var is_throne: Bool
    var terrain_char: CChar
    var terrain_name: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                      CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                      CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                      CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                      CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                      CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                      CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                      CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)  // 64 bytes

    // Level features (for autotravel)
    var stairs_up_x: Int32
    var stairs_up_y: Int32
    var stairs_down_x: Int32
    var stairs_down_y: Int32
    var altar_x: Int32
    var altar_y: Int32
    var fountain_x: Int32
    var fountain_y: Int32

    // Adjacent doors (max 8)
    var adjacent_door_count: Int32
    var adjacent_doors: (CSnapshotDoorInfo, CSnapshotDoorInfo, CSnapshotDoorInfo, CSnapshotDoorInfo,
                        CSnapshotDoorInfo, CSnapshotDoorInfo, CSnapshotDoorInfo, CSnapshotDoorInfo)

    // Nearby enemies (max 10)
    var nearby_enemy_count: Int32
    var nearby_enemies: (CSnapshotEnemyInfo, CSnapshotEnemyInfo, CSnapshotEnemyInfo, CSnapshotEnemyInfo, CSnapshotEnemyInfo,
                        CSnapshotEnemyInfo, CSnapshotEnemyInfo, CSnapshotEnemyInfo, CSnapshotEnemyInfo, CSnapshotEnemyInfo)

    // Items count (for PoC, actual items still fetched via async for now)
    var item_count: Int32
}

/// Swift-friendly door info
struct SwiftDoorInfo {
    let x: Int
    let y: Int
    let dx: Int
    let dy: Int
    let isOpen: Bool
    let isClosed: Bool
    let isLocked: Bool
    let directionCommand: String

    init(from c: CSnapshotDoorInfo) {
        x = Int(c.x)
        y = Int(c.y)
        dx = Int(c.dx)
        dy = Int(c.dy)
        isOpen = c.is_open
        isClosed = c.is_closed
        isLocked = c.is_locked
        directionCommand = String(UnicodeScalar(UInt8(c.direction_cmd)))
    }
}

/// Swift-friendly enemy info
struct SwiftEnemyInfo {
    let name: String
    let x: Int
    let y: Int
    let distance: Int
    let hp: Int
    let maxHp: Int
    let glyphChar: Character
    let isHostile: Bool
    let isPeaceful: Bool

    init(from c: CSnapshotEnemyInfo) {
        // Convert tuple to String
        name = withUnsafePointer(to: c.name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 64) { charPtr in
                String(cString: charPtr)
            }
        }
        x = Int(c.x)
        y = Int(c.y)
        distance = Int(c.distance)
        hp = Int(c.hp)
        maxHp = Int(c.max_hp)
        glyphChar = Character(UnicodeScalar(UInt8(c.glyph_char)))
        isHostile = c.is_hostile
        isPeaceful = c.is_peaceful
    }
}

/// Swift-friendly game state snapshot
struct GameStateSnapshot {
    let turnNumber: Int

    // Player stats
    let playerHp: Int
    let playerMaxHp: Int
    let playerAc: Int
    let playerLevel: Int
    let playerXp: Int
    let playerGold: Int  // Gold count (safe from game thread)
    let playerX: Int
    let playerY: Int
    let hasContainer: Bool  // Container at player position
    let hasLockedContainer: Bool  // Locked container at player position

    // Current tile
    let terrainType: Int
    let isStairsUp: Bool
    let isStairsDown: Bool
    let isLadder: Bool
    let isAltar: Bool
    let isFountain: Bool
    let isSink: Bool
    let isThrone: Bool
    let terrainChar: Character
    let terrainName: String

    // Level features (for autotravel)
    let stairsUpX: Int
    let stairsUpY: Int
    let stairsDownX: Int
    let stairsDownY: Int
    let altarX: Int
    let altarY: Int
    let fountainX: Int
    let fountainY: Int

    // Adjacent doors
    let adjacentDoors: [SwiftDoorInfo]

    // Nearby enemies
    let nearbyEnemies: [SwiftEnemyInfo]

    // Items count
    let itemCount: Int

    // Default initializer for empty snapshot
    init() {
        turnNumber = 0
        playerHp = 0
        playerMaxHp = 0
        playerAc = 0
        playerLevel = 0
        playerXp = 0
        playerGold = 0
        playerX = 0
        playerY = 0
        hasContainer = false
        hasLockedContainer = false
        terrainType = 0
        isStairsUp = false
        isStairsDown = false
        isLadder = false
        isAltar = false
        isFountain = false
        isSink = false
        isThrone = false
        terrainChar = " "
        terrainName = ""
        stairsUpX = -1
        stairsUpY = -1
        stairsDownX = -1
        stairsDownY = -1
        altarX = -1
        altarY = -1
        fountainX = -1
        fountainY = -1
        adjacentDoors = []
        nearbyEnemies = []
        itemCount = 0
    }

    // Initializer from C struct
    init(from c: CGameStateSnapshot) {
        turnNumber = Int(c.turn_number)

        // Player stats
        playerHp = Int(c.player_hp)
        playerMaxHp = Int(c.player_max_hp)
        playerAc = Int(c.player_ac)
        playerLevel = Int(c.player_level)
        playerXp = Int(c.player_xp)
        playerGold = Int(c.player_gold)
        playerX = Int(c.player_x)
        playerY = Int(c.player_y)
        hasContainer = c.has_container
        hasLockedContainer = c.has_locked_container

        // Current tile
        terrainType = Int(c.terrain_type)
        isStairsUp = c.is_stairs_up
        isStairsDown = c.is_stairs_down
        isLadder = c.is_ladder
        isAltar = c.is_altar
        isFountain = c.is_fountain
        isSink = c.is_sink
        isThrone = c.is_throne
        terrainChar = Character(UnicodeScalar(UInt8(c.terrain_char)))

        // Convert terrain name tuple to String
        terrainName = withUnsafePointer(to: c.terrain_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 64) { charPtr in
                String(cString: charPtr)
            }
        }

        // Level features (for autotravel)
        stairsUpX = Int(c.stairs_up_x)
        stairsUpY = Int(c.stairs_up_y)
        stairsDownX = Int(c.stairs_down_x)
        stairsDownY = Int(c.stairs_down_y)
        altarX = Int(c.altar_x)
        altarY = Int(c.altar_y)
        fountainX = Int(c.fountain_x)
        fountainY = Int(c.fountain_y)

        // Convert adjacent doors
        let doorTuple = c.adjacent_doors
        let doorMirror = Mirror(reflecting: doorTuple)
        var doors: [SwiftDoorInfo] = []
        for i in 0..<Int(c.adjacent_door_count) {
            if let child = doorMirror.children.dropFirst(i).first {
                if let cDoor = child.value as? CSnapshotDoorInfo {
                    doors.append(SwiftDoorInfo(from: cDoor))
                }
            }
        }
        adjacentDoors = doors

        // Convert nearby enemies
        let enemyTuple = c.nearby_enemies
        let enemyMirror = Mirror(reflecting: enemyTuple)
        var enemies: [SwiftEnemyInfo] = []
        for i in 0..<Int(c.nearby_enemy_count) {
            if let child = enemyMirror.children.dropFirst(i).first {
                if let cEnemy = child.value as? CSnapshotEnemyInfo {
                    enemies.append(SwiftEnemyInfo(from: cEnemy))
                }
            }
        }
        nearbyEnemies = enemies

        // Items count
        itemCount = Int(c.item_count)
    }

}
