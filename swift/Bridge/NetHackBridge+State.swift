import Foundation

// =============================================================================
// NetHackBridge+State - Game State Query Extension
// =============================================================================
//
// This extension provides methods for querying current game state:
// - Player stats and position
// - Game state snapshots
// - Terrain information
//
// All methods use lazy symbol resolution from the main NetHackBridge class.
// =============================================================================

extension NetHackBridge {

    // MARK: - Lazy Wrappers (C Function Calls)

    internal func nethack_get_player_stats_json() throws -> UnsafePointer<CChar>? {
        try ensureDylibLoaded()
        if _nethack_get_player_stats_json == nil {
            _nethack_get_player_stats_json = try dylib.resolveFunction("nethack_get_player_stats_json")
        }
        return _nethack_get_player_stats_json?()
    }

    internal func ios_get_player_position(_ x: UnsafeMutablePointer<Int32>, _ y: UnsafeMutablePointer<Int32>) throws {
        try ensureDylibLoaded()
        if _ios_get_player_position == nil {
            _ios_get_player_position = try dylib.resolveFunction("ios_get_player_position")
        }
        _ios_get_player_position?(x, y)
    }

    internal func ios_get_terrain_under_player_wrap() throws -> CChar {
        try ensureDylibLoaded()
        if _ios_get_terrain_under_player == nil {
            _ios_get_terrain_under_player = try dylib.resolveFunction("ios_get_terrain_under_player")
        }
        guard let fn = _ios_get_terrain_under_player else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "ios_get_terrain_under_player")
        }
        return fn()
    }

    internal func ios_get_player_position_wrap(_ x: UnsafeMutablePointer<Int32>, _ y: UnsafeMutablePointer<Int32>) throws {
        try ensureDylibLoaded()
        if _ios_get_player_position_fn == nil {
            _ios_get_player_position_fn = try dylib.resolveFunction("ios_get_player_position")
        }
        _ios_get_player_position_fn?(x, y)
    }

    /// Check if player would escape the dungeon (needs escape warning)
    /// Returns true if: player is on level 1, on upstairs, without the Amulet
    /// Logic mirrors doup() in origin/NetHack/src/do.c lines 1330-1335
    func checkEscapeWarning() -> Bool {
        print("[Swift] checkEscapeWarning() called")
        do {
            try ensureDylibLoaded()
            if _ios_check_escape_warning == nil {
                print("[Swift] Resolving ios_check_escape_warning...")
                _ios_check_escape_warning = try dylib.resolveFunction("ios_check_escape_warning")
            }
            guard let fn = _ios_check_escape_warning else {
                print("[Swift] checkEscapeWarning - function pointer is nil!")
                return false
            }
            let result = fn()
            print("[Swift] checkEscapeWarning() returned \(result)")
            return result != 0
        } catch {
            print("[Swift] checkEscapeWarning error: \(error)")
            return false
        }
    }

    // MARK: - Game State Snapshot

    /// Get current game state snapshot (instant, no async!)
    /// - Returns: Complete game state snapshot (stairs, doors, enemies, etc.)
    /// - Performance: ~1μs (just memcpy from double buffer, NO locks!)
    /// - Thread-Safe: Lock-free double buffering
    func getGameStateSnapshot() -> GameStateSnapshot {
        // Lazy resolve on first use
        if _ios_get_game_state_snapshot == nil {
            _ios_get_game_state_snapshot = try? dylib.resolveFunction("ios_get_game_state_snapshot")
        }

        guard let getSnapshot = _ios_get_game_state_snapshot else {
            print("[Bridge] ❌ Failed to resolve ios_get_game_state_snapshot")
            return GameStateSnapshot()  // Empty snapshot as fallback
        }

        // Allocate and zero-initialize memory for the C struct
        let size = MemoryLayout<CGameStateSnapshot>.size
        let alignment = MemoryLayout<CGameStateSnapshot>.alignment
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: alignment)
        defer { ptr.deallocate() }

        // Zero-initialize
        ptr.initializeMemory(as: UInt8.self, repeating: 0, count: size)

        // Call C function to fill the struct
        getSnapshot(ptr)

        // Load the filled struct
        let cSnapshot = ptr.load(as: CGameStateSnapshot.self)

        // Convert C struct to Swift
        return GameStateSnapshot(from: cSnapshot)
    }

    // MARK: - Player Stats

    /// Get player stats as structured data
    /// SINGLE SOURCE OF TRUTH: Only use JSON from nethack_get_player_stats_json()
    func getPlayerStats() -> PlayerStats? {
        let jsonString: UnsafePointer<CChar>?
        do {
            jsonString = try nethack_get_player_stats_json()
        } catch {
            print("[Bridge] ❌ Failed to get player stats JSON: \(error)")
            return nil
        }

        guard let jsonString = jsonString else {
            print("[Bridge] ❌ No player stats JSON available")
            return nil
        }

        let jsonStr = String(cString: jsonString)
        guard let data = jsonStr.data(using: .utf8) else {
            print("[Bridge] ❌ Failed to convert JSON string to data")
            return nil
        }

        do {
            return try JSONDecoder().decode(PlayerStats.self, from: data)
        } catch {
            print("[Bridge] ❌ Failed to decode player stats JSON: \(error)")
            print("[Bridge] JSON: \(jsonStr)")
            return nil
        }
    }

    // MARK: - Terrain Information

    /// Get terrain character at player position from NetHack's levl[][] array
    /// Returns '>' for down stairs, '<' for up stairs, '{' for fountain, etc.
    /// Returns nil if no special terrain or error
    func getTerrainUnderPlayer() -> Character? {
        guard let terrainChar = try? ios_get_terrain_under_player_wrap() else { return nil }
        guard terrainChar != 0 else { return nil }
        return Character(UnicodeScalar(UInt8(terrainChar)))
    }

    /// Get player position directly from NetHack's u.ux/u.uy
    /// Returns (x, y) in NetHack coordinates (0-based)
    func getPlayerPosition() -> (x: Int, y: Int)? {
        var x: Int32 = -1
        var y: Int32 = -1
        do {
            try ios_get_player_position_wrap(&x, &y)
        } catch {
            print("[Bridge] ❌ Failed to get player position: \(error)")
            return nil
        }
        guard x >= 0 && y >= 0 else { return nil }
        return (x: Int(x), y: Int(y))
    }

    // MARK: - Game Initialization State

    /// Check if the NetHack engine is initialized
    func isGameInitialized() -> Bool {
        do {
            return try nethack_real_is_initialized() != 0
        } catch {
            return false
        }
    }

    /// Check if the game is currently running (thread-safe)
    /// CRITICAL FIX: Public accessor for gameStarted flag
    /// GameOverlayManager needs to check if game is running WITHOUT relying on
    /// SimplifiedSaveLoadCoordinator.isGameRunning (race condition with notifications)
    /// Uses NSLock for thread-safe atomic access
    nonisolated func isGameStarted() -> Bool {
        return gameStarted
    }

    // MARK: - Player Metadata Wrappers

    internal func nethack_get_player_name_wrap() throws -> UnsafePointer<CChar>? {
        try ensureDylibLoaded()
        if _nethack_get_player_name == nil {
            _nethack_get_player_name = try dylib.resolveFunction("nethack_get_player_name")
        }
        return _nethack_get_player_name?()
    }

    internal func nethack_get_player_class_name_wrap() throws -> UnsafePointer<CChar>? {
        try ensureDylibLoaded()
        if _nethack_get_player_class_name == nil {
            _nethack_get_player_class_name = try dylib.resolveFunction("nethack_get_player_class_name")
        }
        return _nethack_get_player_class_name?()
    }

    internal func nethack_get_player_race_name_wrap() throws -> UnsafePointer<CChar>? {
        try ensureDylibLoaded()
        if _nethack_get_player_race_name == nil {
            _nethack_get_player_race_name = try dylib.resolveFunction("nethack_get_player_race_name")
        }
        return _nethack_get_player_race_name?()
    }

    // MARK: - Player Metadata Functions

    /// Get the player's character name
    func getPlayerName() -> String? {
        guard let cString = (try? nethack_get_player_name_wrap()) ?? nil else {
            return nil
        }
        let name = String(cString: cString)
        return name.isEmpty ? nil : name
    }

    /// Get the player's class name
    func getPlayerClassName() -> String? {
        guard let cString = (try? nethack_get_player_class_name_wrap()) ?? nil else {
            return nil
        }
        let name = String(cString: cString)
        return name.isEmpty ? nil : name
    }

    /// Get the player's race name
    func getPlayerRaceName() -> String? {
        guard let cString = (try? nethack_get_player_race_name_wrap()) ?? nil else {
            return nil
        }
        let name = String(cString: cString)
        return name.isEmpty ? nil : name
    }
}
