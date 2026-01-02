import Foundation

// =============================================================================
// NetHackBridge+SaveLoad - Save/Load Game Functions
// =============================================================================
//
// This extension handles game persistence:
// - Save game state to disk
// - Load/restore saved games
// - Character file management
// - Save file queries
// - Lazy symbol resolution for save/load C functions
//
// =============================================================================

extension NetHackBridge {

    // MARK: - Lazy Wrappers (C Function Calls)

    internal func ios_quicksave() throws -> Int32 {
        try ensureDylibLoaded()
        if _ios_quicksave == nil {
            _ios_quicksave = try dylib.resolveFunction("ios_quicksave")
        }
        guard let fn = _ios_quicksave else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "ios_quicksave")
        }
        return fn()
    }

    internal func ios_quickrestore() throws -> Int32 {
        try ensureDylibLoaded()
        if _ios_quickrestore == nil {
            _ios_quickrestore = try dylib.resolveFunction("ios_quickrestore")
        }
        guard let fn = _ios_quickrestore else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "ios_quickrestore")
        }
        return fn()
    }

    internal func ios_save_character(_ filename: UnsafePointer<CChar>) throws -> Int32 {
        try ensureDylibLoaded()
        if _ios_save_character == nil {
            _ios_save_character = try dylib.resolveFunction("ios_save_character")
        }
        guard let fn = _ios_save_character else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "ios_save_character")
        }
        return fn(filename)
    }

    internal func ios_load_character(_ filename: UnsafePointer<CChar>) throws -> Int32 {
        try ensureDylibLoaded()
        if _ios_load_character == nil {
            _ios_load_character = try dylib.resolveFunction("ios_load_character")
        }
        guard let fn = _ios_load_character else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "ios_load_character")
        }
        return fn(filename)
    }

    // MARK: - Save Functions

    /// Save current game state
    /// - Returns: true if save successful
    func saveGame() -> Bool {
        guard gameStarted else {
            print("[Bridge] Cannot save - game not started")
            return false
        }

        print("[Bridge] Initiating complete save with memory state...")

        // Call our complete save function
        // NOTE: Snapshot creation is now handled by NetHackGameManager
        // which has access to the correct playerStats BEFORE game exits moveloop
        let result: Int32
        do {
            result = try ios_quicksave()
        } catch {
            print("[Bridge] ❌ Save failed: \(error)")
            return false
        }

        if result == 0 {
            print("[Bridge] ✅ Save successful - both memory and game state saved")
            return true
        } else {
            print("[Bridge] ❌ Save failed")
            return false
        }
    }

    /// Check if a saved game exists
    func hasSaveGame() -> Bool {
        return ios_save_exists() != 0
    }

    // MARK: - Load Functions

    /// Load saved game and prepare for resumption
    /// - Returns: true if load successful, call resumeGame() to start playing
    func loadGame() -> Bool {
        print("[Bridge] loadGame() called - checking gameStarted flag...")
        print("[Bridge] Current state: gameStarted=\(gameStarted), gameTask=\(gameTask != nil ? "exists" : "nil")")

        guard !gameStarted else {
            print("[Bridge] ❌ Cannot load - game already running (gameStarted=true)")
            print("[Bridge] This should NOT happen! stopGame() should have reset this flag.")
            return false
        }

        // Check if save exists
        if !hasSaveGame() {
            print("[Bridge] No save file exists")
            return false
        }

        print("[Bridge] ✅ Preconditions passed - gameStarted=false, save exists")

        // CRITICAL ARCHITECTURE FIX: Always reload dylib for FRESH STATE
        // This eliminates need for nh_restart() in ios_quickrestore()
        // Why: nh_restart() wipes Lua/file_prefixes that were just initialized
        //      in ios_full_dylib_init(), causing duplicate initialization!
        // With dylib reload, we get fresh state automatically with NO duplicates.
        let reloadStart = Date()
        if dylib.isLoaded {
            print("[Bridge] 🔄 Dylib already loaded - forcing reload for fresh state...")
            unloadDylib()
            print("[Bridge] ✓ Dylib unloaded")
        }

        do {
            print("[Bridge] ⏱️ Profiling dylib reload...")
            try ensureDylibLoaded()
            let reloadMs = Date().timeIntervalSince(reloadStart) * 1000
            print("[Bridge] ⏱️ Dylib reload took \(String(format: "%.1f", reloadMs))ms")

            // CRITICAL FIX: Re-register callbacks after dylib reload!
            // The old callback pointers are destroyed with the old dylib.
            // We MUST register new callbacks that point to the NEW dylib instance.
            // This ensures map updates and render queue notifications reach Swift.
            print("[Bridge] 🔄 Re-registering callbacks after dylib reload...")
            registerCallbacks()
            print("[Bridge] ✓ Callbacks re-registered with new dylib instance")

            print("[Bridge] ✓ Fresh dylib loaded with unified init complete")
        } catch {
            print("[Bridge] ❌ Failed to reload dylib: \(error)")
            return false
        }

        print("[Bridge] Initiating complete restore with memory state...")

        // Call our complete restore function
        let result: Int32
        do {
            result = try ios_quickrestore()
        } catch {
            print("[Bridge] ❌ Restore failed: \(error)")
            return false
        }

        if result == 0 {
            print("[Bridge] ✅ Restore successful - game ready to continue")

            // CRITICAL: Do NOT set gameStarted = true here!
            // We need resumeGame() to actually start the game thread.
            // If we set gameStarted=true, resumeGame() thinks the thread is already running
            // and skips starting it, leaving the game in a dead state!

            // Mark that we had a previous game (for cleanup on next restart)
            hadPreviousGame = true

            return true
        } else {
            print("[Bridge] ❌ Restore failed")
            return false
        }
    }

    /// Load a character's save (wrapper for ios_load_character that manages dylib state)
    func loadCharacter(_ characterName: String) -> Bool {
        print("[Bridge] 🔴🔴🔴 loadCharacter v2 FIX ACTIVE 🔴🔴🔴")
        print("[Bridge] loadCharacter('\(characterName)') called, dylib.isLoaded=\(dylib.isLoaded)")

        // FIX 2025-12-30 v2: FULL reinit like CLI does!
        // CLI ALWAYS calls: ios_reset_game_exit() → ios_full_dylib_init() → nethack_real_init()
        // Previous "light reset" was WRONG - it left corrupted state from level consolidation.
        // The corruption (timers, stairs, level files) causes load to fail after level changes.
        do {
            if !dylib.isLoaded {
                print("[Bridge] Dylib not loaded - loading fresh...")
                try ensureDylibLoaded()
                registerCallbacks()
                print("[Bridge] 🟡 Calling nethack_real_init() for fresh dylib...")
                try nethack_real_init()
            } else {
                print("[Bridge] Dylib already loaded - FULL reinit (matching CLI)...")
                // FULL REINIT: Shutdown clears corrupted state, init starts fresh
                // This matches CLI which calls ios_full_dylib_init() before EVERY load
                try ios_reset_game_exit()
                try ios_full_dylib_shutdown()  // Clears full_init_called, frees memory
                try ios_full_dylib_init()      // Reinitializes everything clean
                try nethack_real_init()        // Set up game options
                print("[Bridge] ✓ Full reinit complete (clean state)")
            }
            print("[Bridge] ✓ Dylib ready for character load")
        } catch {
            print("[Bridge] ❌ Failed to prepare dylib: \(error)")
            return false
        }

        // Now call the C function - dylib is loaded and Swift knows about it
        let result: Int32
        do {
            result = try ios_load_character(characterName)
        } catch {
            print("[Bridge] ❌ ios_load_character threw error: \(error)")
            return false
        }

        if result == 1 {
            print("[Bridge] ✅ Character loaded successfully")
            hadPreviousGame = true
            return true
        } else {
            print("[Bridge] ❌ Failed to load character")
            return false
        }
    }

    // MARK: - Save Management

    /// Delete the current save file
    func deleteSave() {
        ios_delete_save()
        print("[Bridge] Save deleted")
    }

    /// Get information about the current save
    func getSaveInfo() -> String {
        let info = ios_get_save_info()
        return info != nil ? String(cString: info!) : "No save info"
    }
}
