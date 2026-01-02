//
//  MapData.swift
//  nethack
//
//  Map data structures for tile rendering
//
//  COORDINATE CONVENTIONS:
//  - MapTile.x/y: Swift array indices (0-based) matching tiles[y][x]
//  - MapState.playerX/playerY: Swift array indices (0-based)
//  - Use CoordinateConverter to transform between NetHack/Swift/SceneKit spaces
//

import Foundation
import SwiftUI

// Tile visibility states matching NetHack's visibility system
enum TileVisibility: Int {
    case unexplored = 0  // Never seen (fog of war)
    case remembered = 1  // Previously seen, not currently visible
    case visible = 2     // Currently in line of sight
    case detected = 3    // Monster detected via telepathy
    case dark = 4        // In darkness but known (infravision)
}

// Represents a single tile on the map
struct MapTile: Identifiable, Equatable {
    let id = UUID()

    // IMPORTANT: These are Swift array indices (0-based), NOT NetHack coordinates!
    // NetHack coordinates are 1-based for X, 0-based for Y
    // Use CoordinateConverter to transform between spaces
    let x: Int              // Swift X index: 0 to (width-1)
    let y: Int              // Swift Y index: 0 to (height-1)

    let glyph: Int32        // NetHack glyph ID
    let character: Character // ASCII character
    let foreground: MapColor
    let background: MapColor
    let type: TileType

    // Glyph flags for special rendering
    let glyphflags: UInt32
    var isPet: Bool { (glyphflags & NetHackBridge.MG_PET) != 0 }
    var isRidden: Bool { (glyphflags & NetHackBridge.MG_RIDDEN) != 0 }
    var isDetected: Bool { (glyphflags & NetHackBridge.MG_DETECT) != 0 }

    static func == (lhs: MapTile, rhs: MapTile) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.glyph == rhs.glyph
    }
}

// Tile types for different rendering
enum TileType {
    case floor
    case wall
    case door
    case doorOpen
    case doorClosed
    case corridor
    case stairs
    case water
    case lava
    case altar
    case fountain
    case throne
    case sink
    case trap
    case monster
    case player
    case item
    case gold
    case food
    case weapon
    case armor
    case potion
    case scroll
    case wand
    case ring
    case amulet
    case tool
    case unknown

    /// True for terrain that can be "underneath" the player (floor, stairs, etc.)
    /// Used for underlyingTile tracking - we only cache terrain, never monsters/items
    var isTerrain: Bool {
        switch self {
        case .floor, .wall, .door, .doorOpen, .doorClosed, .corridor,
             .stairs, .water, .lava, .altar, .fountain, .throne, .sink, .trap:
            return true
        case .monster, .player, .item, .gold, .food, .weapon, .armor,
             .potion, .scroll, .wand, .ring, .amulet, .tool, .unknown:
            return false
        }
    }

    static func fromCharacter(_ ch: Character) -> TileType {
        switch ch {
        case ".": return .floor
        case "-", "|": return .wall
        case "+": return .doorClosed
        case "'": return .doorOpen
        case "#": return .corridor
        case "<", ">": return .stairs
        case "~": return .water
        case "}": return .water  // Pool
        case "{": return .fountain
        case "_": return .altar
        case "\\": return .throne
        case "^": return .trap
        case "@": return .player
        case "$": return .gold
        case "%": return .food
        case ")": return .weapon
        case "[": return .armor
        case "!": return .potion
        case "?": return .scroll
        // "/" already handled above for doors
        case "=": return .ring
        case "\"": return .amulet
        case "(": return .tool
        case "a"..."z", "A"..."Z": return .monster
        default: return .unknown
        }
    }
}

// Color representation
struct MapColor {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    static let black = MapColor(r: 0, g: 0, b: 0, a: 255)
    static let white = MapColor(r: 255, g: 255, b: 255, a: 255)
    static let gray = MapColor(r: 128, g: 128, b: 128, a: 255)
    static let red = MapColor(r: 255, g: 0, b: 0, a: 255)
    static let green = MapColor(r: 0, g: 255, b: 0, a: 255)
    static let blue = MapColor(r: 0, g: 0, b: 255, a: 255)
    static let yellow = MapColor(r: 255, g: 255, b: 0, a: 255)
    static let brown = MapColor(r: 139, g: 69, b: 19, a: 255)
    static let cyan = MapColor(r: 0, g: 255, b: 255, a: 255)
    static let magenta = MapColor(r: 255, g: 0, b: 255, a: 255)
}

// Complete map state
@Observable
class MapState {
    // COORDINATE CONVENTION: All X/Y values are Swift array indices (0-based)
    // tiles[y][x] stores the tile at Swift coordinate (x, y)
    // Use CoordinateConverter to transform to/from NetHack or SceneKit coordinates

    var tiles: [[MapTile?]] = []
    var width: Int = 0
    var height: Int = 0

    // Player position in Swift coordinates (0-based)
    var playerX: Int = 0
    var playerY: Int = 0

    var messages: [String] = []
    var statusLine: String = ""

    // Visibility tracking for NetHack's vision system
    var visibility: [[TileVisibility]] = []
    var remembered: [[MapTile?]] = []  // Memory of previously seen tiles
    var lightLevel: [[Float]] = []     // Light intensity per tile
    var sightRadius: Int = 5           // Default sight radius

    // Track what's underneath the player
    var underlyingTile: MapTile? = nil

    // FIX: Force @Observable to detect nested array mutations
    // @Observable doesn't detect tiles[y][x] = newTile (nested mutation through subscript)
    // This counter increments on each tile update, triggering SwiftUI re-render
    var tileUpdateCounter: Int = 0

    // Current dungeon environment for visual theming
    var currentEnvironment: DungeonEnvironment = .standard

    init() {
        // Initialize with empty map
        reset(width: 80, height: 25)
    }

    func reset(width: Int, height: Int) {
        self.width = width
        self.height = height
        tiles = Array(repeating: Array(repeating: nil, count: width), count: height)
        visibility = Array(repeating: Array(repeating: .unexplored, count: width), count: height)
        remembered = Array(repeating: Array(repeating: nil, count: width), count: height)
        lightLevel = Array(repeating: Array(repeating: 0.0, count: width), count: height)
        underlyingTile = nil
    }

    /// Update tile at Swift coordinates (0-based)
    /// - Parameters:
    ///   - x: Swift X coordinate (0 to width-1)
    ///   - y: Swift Y coordinate (0 to height-1)
    ///   - glyph: NetHack glyph ID
    ///   - character: ASCII character to display
    ///   - glyphflags: NetHack glyph flags (MG_PET, MG_RIDDEN etc.)
    func updateTile(x: Int, y: Int, glyph: Int32, character: Character, glyphflags: UInt32 = 0) {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            print("[MapData] ERROR: Tile coordinate [SW:\(x),\(y)] out of bounds (width:\(width), height:\(height))")
            return
        }

        let type = TileType.fromCharacter(character)
        let foreground = colorForTileType(type)
        let background = MapColor.black

        let newTile = MapTile(
            x: x,
            y: y,
            glyph: glyph,
            character: character,
            foreground: foreground,
            background: background,
            type: type,
            glyphflags: glyphflags
        )

        // Track player position for camera/visibility
        // NOTE: We do NOT track "underlyingTile" anymore!
        // NetHack sends correct tiles for all positions via render queue.
        // Manual tracking caused ghost tiles (duplicates) by overwriting queue data.
        if type == .player {
            playerX = x
            playerY = y
            updateVisibilityAroundPlayer()
        }

        if let coord = CoordinateConverter.makeSwift(x: x, y: y) {
            tiles[coord] = newTile

            // If tile is visible, update remembered state
            if visibility[coord] == .visible {
                remembered[coord] = newTile
            }

            // FIX: Force @Observable notification for nested array mutation
            // Without this, SwiftUI doesn't know tiles changed (subscript mutation not detected)
            tileUpdateCounter += 1
        }
    }

    // Update visibility based on player's line of sight
    func updateVisibilityAroundPlayer() {
        // Reset all tiles to remembered or unexplored
        for y in 0..<height {
            for x in 0..<width {
                if let coord = CoordinateConverter.makeSwift(x: x, y: y) {
                    if visibility[coord] == .visible {
                        visibility[coord] = .remembered
                    }
                }
            }
        }

        // Calculate visible tiles in radius around player
        let minX = max(0, playerX - sightRadius)
        let maxX = min(width - 1, playerX + sightRadius)
        let minY = max(0, playerY - sightRadius)
        let maxY = min(height - 1, playerY + sightRadius)

        for y in minY...maxY {
            for x in minX...maxX {
                let distance = abs(x - playerX) + abs(y - playerY)
                if distance <= sightRadius {
                    // Simple visibility check - can be enhanced with line of sight
                    if hasLineOfSight(fromX: playerX, fromY: playerY, toX: x, toY: y) {
                        if let coord = CoordinateConverter.makeSwift(x: x, y: y) {
                            visibility[coord] = .visible
                            lightLevel[coord] = Float(sightRadius - distance) / Float(sightRadius)
                        }
                    }
                }
            }
        }
    }

    // Simple line of sight check using Bresenham's algorithm
    private func hasLineOfSight(fromX: Int, fromY: Int, toX: Int, toY: Int) -> Bool {
        var x0 = fromX
        var y0 = fromY
        let x1 = toX
        let y1 = toY

        let dx = abs(x1 - x0)
        let dy = abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx - dy

        while true {
            // Check if current position blocks sight (walls block)
            if x0 != fromX || y0 != fromY {
                if let coord = CoordinateConverter.makeSwift(x: x0, y: y0),
                   let tile = tiles[coord] {
                    if tile.type == .wall || tile.type == .doorClosed {
                        return x0 == toX && y0 == toY  // Can see the wall itself
                    }
                }
            }

            if x0 == x1 && y0 == y1 {
                return true
            }

            let e2 = 2 * err
            if e2 > -dy {
                err -= dy
                x0 += sx
            }
            if e2 < dx {
                err += dx
                y0 += sy
            }
        }
    }

    // Update visibility for a specific tile (e.g., telepathy detection)
    func setTileVisibility(x: Int, y: Int, visibility: TileVisibility) {
        if let coord = CoordinateConverter.makeSwift(x: x, y: y) {
            self.visibility[coord] = visibility
        }
    }

    private func colorForTileType(_ type: TileType) -> MapColor {
        switch type {
        case .floor: return MapColor.gray
        case .wall: return MapColor.white
        case .door, .doorOpen, .doorClosed: return MapColor.brown
        case .corridor: return MapColor.gray
        case .stairs: return MapColor.yellow
        case .water: return MapColor.blue
        case .lava: return MapColor.red
        case .altar: return MapColor.white
        case .fountain: return MapColor.cyan
        case .throne: return MapColor.yellow
        case .sink: return MapColor.white
        case .trap: return MapColor.red
        case .monster: return MapColor.red
        case .player: return MapColor.white
        case .item: return MapColor.cyan
        case .gold: return MapColor.yellow
        case .food: return MapColor.brown
        case .weapon: return MapColor.gray
        case .armor: return MapColor.gray
        case .potion: return MapColor.magenta
        case .scroll: return MapColor.white
        case .wand: return MapColor.cyan
        case .ring: return MapColor.yellow
        case .amulet: return MapColor.yellow
        case .tool: return MapColor.gray
        case .unknown: return MapColor.gray
        }
    }

    // MARK: - Render Queue Consumer (Phase 2)

    /// Consume updates from the render queue and apply to map state
    /// This is called from the notification handler when ios_notify_map_changed() is triggered
    /// - Returns: Updated PlayerStats if status update was received, nil otherwise
    func consumeRenderQueue(from bridge: NetHackBridge) -> PlayerStats? {
        let updates = bridge.consumeRenderQueue()

        guard !updates.isEmpty else {
            return nil
        }

        print("[MapData] Processing \(updates.count) render queue updates")

        var updatedStats: PlayerStats? = nil

        for (type, data) in updates {
            switch type {
            case .updateGlyph:
                guard let update = data as? NetHackBridge.MapUpdateData else {
                    continue
                }

                // Convert NetHack coordinates from render queue to Swift coordinates
                // Uses single source of truth: CoordinateConverter
                guard let swiftCoord = CoordinateConverter.fromRenderUpdate(x: Int32(update.x), y: Int32(update.y)) else {
                    print("[MapData] ERROR: Queue update out of bounds - NH(\(update.x),\(update.y))")
                    continue
                }

                let (swiftX, swiftY) = swiftCoord.arrayIndices

                // Convert char to Character
                let character = Character(UnicodeScalar(UInt8(bitPattern: update.ch)))

                // Update tile with glyph flags (pet, ridden, detected etc.)
                updateTile(x: swiftX, y: swiftY, glyph: update.glyph, character: character, glyphflags: update.glyphflags)

            case .updateMessage:
                guard let messageData = data as? NetHackBridge.MessageUpdateData else {
                    continue
                }
                // Message text and category are strdup'd in C - we must free them after use
                let text = String(cString: messageData.text)
                let category = String(cString: messageData.category)

                // Add to message history
                messages.append(text)
                print("[MapData] Message [\(category)]: \(text)")

                // Free C strings
                free(messageData.text)
                free(messageData.category)

            case .updateStatus:
                guard let statusData = data as? NetHackBridge.StatusUpdateData else {
                    continue
                }

                // Convert align tuple to String
                let alignBytes = [statusData.align.0, statusData.align.1, statusData.align.2, statusData.align.3,
                                statusData.align.4, statusData.align.5, statusData.align.6, statusData.align.7,
                                statusData.align.8, statusData.align.9, statusData.align.10, statusData.align.11,
                                statusData.align.12, statusData.align.13, statusData.align.14, statusData.align.15]
                let alignString = String(cString: alignBytes.map { UInt8(bitPattern: $0) } + [0])

                // TODO: Get dungeon level from u.uz.dlevel (not in StatusUpdate struct yet)
                // For now, keep existing dungeonLevel from polling
                // This is OK because dungeon level changes less frequently than HP/stats
                let dungeonLevel = 0  // Placeholder - will be updated by polling fallback

                // CRITICAL FIX (Bug #4 & #8): Build PlayerStats from render queue
                updatedStats = PlayerStats(
                    hp: Int(statusData.hp),
                    hpmax: Int(statusData.hpmax),
                    pw: Int(statusData.pw),
                    pwmax: Int(statusData.pwmax),
                    level: Int(statusData.level),
                    exp: statusData.exp,
                    ac: Int(statusData.ac),
                    str: Int(statusData.str),
                    dex: Int(statusData.dex),
                    con: Int(statusData.con),
                    int: Int(statusData.intel),
                    wis: Int(statusData.wis),
                    cha: Int(statusData.cha),
                    gold: statusData.gold,
                    moves: statusData.moves,
                    dungeonLevel: dungeonLevel,
                    align: alignString,
                    hunger: Int(statusData.hunger),
                    conditions: statusData.conditions
                )
                print("[MapData] ✅ Status updated: HP=\(statusData.hp)/\(statusData.hpmax) Turn=\(statusData.moves)")

            case .cmdFlushMap:
                // @Observable handles updates automatically
                break

            case .cmdClearMap:
                // Clear ALL map data on level change - not just tiles!
                // This fixes ghost tile bug where stairs from previous level remained visible
                reset(width: width, height: height)

                // Update environment for visual theming on level change
                let envRaw = ios_get_current_environment()
                currentEnvironment = DungeonEnvironment(rawValue: Int32(envRaw.rawValue)) ?? .standard
                print("[MapData] Environment updated to \(currentEnvironment)")

                tileUpdateCounter += 1  // Force SwiftUI re-render
                print("[MapData] Map fully reset via queue (tiles, remembered, visibility)")

            case .cmdTurnComplete:
                if let turnNum = data as? Int {
                    print("[MapData] Turn \(turnNum) complete")
                }
                // Update visibility after turn completes
                updateVisibilityAroundPlayer()

            default:
                break
            }
        }

        print("[MapData] Render queue consumption complete")
        return updatedStats
    }

    // MARK: - Player Position Helpers

    /// Set player position directly from NetHack coordinates
    /// This is called after consumeRenderQueue() to correct the position based on NetHack's u.ux/u.uy
    /// - Parameters:
    ///   - nhX: NetHack X coordinate (1-based, same as print_glyph)
    ///   - nhY: NetHack Y coordinate (0-based, same as print_glyph)
    func setPlayerPositionFromNetHack(nhX: Int, nhY: Int) {
        // Convert NetHack coordinates to Swift using single source of truth
        guard let nhCoord = CoordinateConverter.makeNetHack(x: nhX, y: nhY) else {
            print("[MapData] ERROR: Invalid NetHack position (\(nhX),\(nhY))")
            return
        }

        let swiftCoord = CoordinateConverter.nethackToSwift(nhCoord)
        let (swiftX, swiftY) = swiftCoord.arrayIndices

        guard swiftX >= 0 && swiftX < width && swiftY >= 0 && swiftY < height else {
            let timestamp = String(format: "%.3f", CACurrentMediaTime())
            print("[\(timestamp)] [MapData] ERROR: Converted Swift position (\(swiftX),\(swiftY)) out of bounds")
            return
        }

        playerX = swiftX
        playerY = swiftY
        let timestamp = String(format: "%.3f", CACurrentMediaTime())
        print("[\(timestamp)] [MapData] Player position updated: NetHack(\(nhX),\(nhY)) -> Swift(\(swiftX),\(swiftY))")
    }

    /// Update the underlying tile based on real terrain from NetHack
    /// This is called after consumeRenderQueue() to set what's REALLY under the player,
    /// since the render queue only shows '@' when player is on a tile.
    /// - Parameter terrainChar: The real terrain character ('>', '<', '{', etc.)
    func updateUnderlyingTile(_ terrainChar: Character) {
        guard playerX >= 0 && playerX < width && playerY >= 0 && playerY < height else {
            print("[MapData] ERROR: Invalid player position (\(playerX),\(playerY))")
            return
        }

        let type = TileType.fromCharacter(terrainChar)
        let foreground = colorForTileType(type)
        let background = MapColor.black

        let tile = MapTile(
            x: playerX,
            y: playerY,
            glyph: 0,  // Glyph doesn't matter for underlying tile
            character: terrainChar,
            foreground: foreground,
            background: background,
            type: type,
            glyphflags: 0  // Terrain has no special flags
        )

        underlyingTile = tile
        print("[MapData] Updated underlying tile at (\(playerX),\(playerY)) to '\(terrainChar)' (type: \(type))")
    }

    /// Get the tile at the player's current position
    func getTileUnderPlayer() -> MapTile? {
        // Return the underlying tile (what the player is standing on)
        // This could be stairs, items, fountains, etc.
        return underlyingTile
    }

    /// Check if there's an actionable tile under the player
    var hasActionableTileUnderPlayer: Bool {
        guard let tile = getTileUnderPlayer() else { return false }

        // Check for actionable tile types
        switch tile.type {
        case .stairs, .item, .gold, .food, .weapon, .armor,
             .potion, .scroll, .wand, .ring, .amulet, .tool,
             .fountain, .sink, .altar, .throne:
            return true
        default:
            return false
        }
    }

    /// Get an appropriate icon for what's under the player
    func getIconForTileUnderPlayer() -> String? {
        guard let tile = getTileUnderPlayer() else { return nil }

        switch tile.type {
        case .stairs:
            // Check character to determine up or down
            if tile.character == ">" {
                return "chevron.down.circle.fill"
            } else if tile.character == "<" {
                return "chevron.up.circle.fill"
            }
            return "arrow.up.arrow.down.circle.fill"
        case .item, .tool:
            return "cube.box.fill"
        case .gold:
            return "bitcoinsign.circle.fill"
        case .food:
            return "fork.knife.circle.fill"
        case .weapon:
            return "shield.fill"
        case .armor:
            return "tshirt.fill"
        case .potion:
            return "drop.circle.fill"
        case .scroll:
            return "scroll.fill"
        case .wand:
            return "magic.wand.and.rays"
        case .ring:
            return "circle.circle.fill"
        case .amulet:
            return "diamond.circle.fill"
        case .fountain:
            return "drop.circle"
        case .sink:
            return "sink"
        case .altar:
            return "sparkles.circle.fill"
        case .throne:
            return "crown.fill"
        default:
            return nil
        }
    }

    /// Get the color for the indicator based on tile type
    func getColorForTileUnderPlayer() -> Color {
        guard let tile = getTileUnderPlayer() else { return .white }

        switch tile.type {
        case .stairs:
            return tile.character == ">" ? .orange : .yellow
        case .gold:
            return .yellow
        case .food:
            return .green
        case .potion:
            return .purple
        case .fountain, .sink:
            return .blue
        case .altar:
            return .cyan
        case .throne:
            return .yellow
        default:
            return .white
        }
    }
}
