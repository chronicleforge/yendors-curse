import Foundation

// =============================================================================
// NetHackBridge - Main Swift/C Bridge for NetHack iOS
// =============================================================================
//
// TABLE OF CONTENTS:
// ------------------
// Line ~30:   Class Definition & Properties
// Line ~150:  Dylib Management (load/unload/clear)
// Line ~350:  Lazy Symbol Resolution (Batch 1-5 wrappers)
// Line ~850:  Game Lifecycle (startNewGame, stopGame, resumeGame)
// Line ~1050: Save/Load Functions
// Line ~1250: Autotravel Functions
// Line ~1400: Render Queue Consumer
// Line ~1650: YN Callback Management
// Line ~1700: Game State Metadata
// Line ~1750: Message Readiness & Callbacks
// Line ~1850: Game State Snapshot (Push Model)
//
// RELATED FILES:
// - BridgeFileHelpers.swift: @_cdecl file loading functions (Lua, data files)
// - Models/Bridge/PlayerStats.swift: PlayerStats struct
// - Models/Bridge/GameStateSnapshot.swift: Snapshot structs
// - DylibLoader.swift: Dynamic library loading
// - NetHackSerialExecutor.swift: Thread-safe execution
//
// =============================================================================

// Bridge class that connects Swift to the real NetHack C engine

// Thread-safe via NetHackSerialExecutor - NO @MainActor needed
// @MainActor was causing deadlock with nonisolated movement functions
final class NetHackBridge: @unchecked Sendable {
    // CRITICAL: nonisolated(unsafe) suppresses false MainActor inference
    // Swift 6 incorrectly infers MainActor due to gameTask property
    // but this singleton is designed for cross-thread access via serial queue + locks
    nonisolated(unsafe) static let shared = NetHackBridge()

    // MARK: - Runtime Dylib Loading

    /// Runtime dylib loader - automatically resets ALL static state via dlclose/dlopen
    /// Eliminates need for manual pointer tracking (gt.timer_base, gs.stairs, gg.gamelog, etc.)
    /// NOTE: internal for extension access
    internal let dylib = DylibLoader()

    // MARK: - Function Pointers (Runtime Resolution)
    // NOTE: All internal for extension access

    // Lifecycle functions (5)
    internal var _nethack_real_init: (@convention(c) () -> Void)?
    internal var _nethack_start_new_game: (@convention(c) () -> Void)?
    internal var _nethack_run_game_threaded: (@convention(c) () -> Void)?
    internal var _ios_request_game_exit: (@convention(c) () -> Void)?
    internal var _ios_reset_game_exit: (@convention(c) () -> Void)?

    // Input/Output functions (3)
    internal var _nethack_send_input_threaded: (@convention(c) (UnsafePointer<CChar>) -> Void)?
    internal var _nethack_get_output_buffer: (@convention(c) () -> UnsafePointer<CChar>?)?
    internal var _nethack_process_command: (@convention(c) () -> Int32)?

    // Game state functions (4)
    internal var _nethack_get_turn_count: (@convention(c) () -> Int)?
    internal var _nethack_get_player_stats_json: (@convention(c) () -> UnsafePointer<CChar>?)?
    internal var _nethack_get_map_data: (@convention(c) () -> UnsafePointer<CChar>?)?
    internal var _ios_get_player_position: (@convention(c) (UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Void)?

    // Character creation functions (4)
    internal var _nethack_get_available_roles: (@convention(c) () -> Int32)?
    internal var _nethack_set_role: (@convention(c) (Int32) -> Void)?
    internal var _nethack_validate_character_selection: (@convention(c) () -> Int32)?
    internal var _nethack_finalize_character: (@convention(c) () -> Void)?

    // Save/Load functions (4)
    internal var _ios_quicksave: (@convention(c) () -> Int32)?
    internal var _ios_quickrestore: (@convention(c) () -> Int32)?
    internal var _ios_save_character: (@convention(c) (UnsafePointer<CChar>) -> Int32)?
    internal var _ios_load_character: (@convention(c) (UnsafePointer<CChar>) -> Int32)?

    // Batch 1: Core lifecycle functions (12) - UNIFIED LIFECYCLE
    internal var _ios_early_init: (@convention(c) () -> Void)?
    internal var _ios_full_dylib_init: (@convention(c) () -> Void)?
    internal var _ios_full_dylib_shutdown: (@convention(c) () -> Void)?
    internal var _ios_wipe_memory: (@convention(c) () -> Void)?
    internal var _nethack_real_newgame: (@convention(c) () -> Void)?
    internal var _nethack_real_get_output: (@convention(c) () -> UnsafePointer<CChar>)?
    internal var _nethack_real_clear_output: (@convention(c) () -> Void)?
    internal var _nethack_real_send_input: (@convention(c) (UnsafePointer<CChar>) -> Void)?
    internal var _nethack_real_is_initialized: (@convention(c) () -> Int32)?
    internal var _nethack_real_is_started: (@convention(c) () -> Int32)?
    internal var _nethack_enable_threaded_mode: (@convention(c) () -> Void)?
    internal var _nethack_start_game_thread: (@convention(c) () -> Void)?
    internal var _ios_was_exit_requested: (@convention(c) () -> Int32)?

    // Callback registration functions (2)
    internal var _ios_register_map_update_callback: (@convention(c) (@convention(c) () -> Void) -> Void)?
    internal var _ios_register_game_ready_callback: (@convention(c) (@convention(c) () -> Void) -> Void)?

    // Message readiness signals
    internal var _ios_swift_ready_for_messages: (@convention(c) () -> Void)?
    internal var _ios_swift_ready_for_new_game: (@convention(c) () -> Void)?

    // Wizard mode (debug mode)
    internal var _ios_enable_wizard_mode: (@convention(c) () -> Void)?

    // Batch 2: Character creation functions (10)
    internal var _nethack_get_role_name: (@convention(c) (Int32) -> UnsafePointer<CChar>)?
    internal var _nethack_get_available_races_for_role: (@convention(c) (Int32) -> Int32)?
    internal var _nethack_get_race_name: (@convention(c) (Int32) -> UnsafePointer<CChar>)?
    internal var _nethack_get_available_genders_for_role: (@convention(c) (Int32) -> Int32)?
    internal var _nethack_get_gender_name: (@convention(c) (Int32) -> UnsafePointer<CChar>)?
    internal var _nethack_get_available_alignments_for_role: (@convention(c) (Int32) -> Int32)?
    internal var _nethack_get_alignment_name: (@convention(c) (Int32) -> UnsafePointer<CChar>)?
    internal var _nethack_set_race: (@convention(c) (Int32) -> Void)?
    internal var _nethack_set_gender: (@convention(c) (Int32) -> Void)?
    internal var _nethack_set_player_name: (@convention(c) (UnsafePointer<CChar>) -> Void)?

    // Batch 3: Remaining character/map/command functions (10)
    internal var _nethack_set_alignment: (@convention(c) (Int32) -> Void)?
    internal var _nethack_get_map_data_fn: (@convention(c) () -> UnsafePointer<CChar>)?
    internal var _nethack_is_map_dirty: (@convention(c) () -> Int32)?
    internal var _nethack_clear_map_dirty: (@convention(c) () -> Void)?
    internal var _nethack_start_new_game_fn: (@convention(c) () -> Void)?
    internal var _nethack_process_command_fn: (@convention(c) () -> Int32)?
    internal var _nethack_set_yn_auto_yes: (@convention(c) () -> Void)?
    internal var _nethack_set_yn_auto_no: (@convention(c) () -> Void)?
    internal var _nethack_set_yn_ask_user: (@convention(c) () -> Void)?
    internal var _nethack_set_yn_default: (@convention(c) () -> Void)?

    // Batch 4: Player metadata and object functions (10)
    internal var _nethack_set_next_yn_response: (@convention(c) (CChar) -> Void)?
    internal var _nethack_get_player_name: (@convention(c) () -> UnsafePointer<CChar>?)?
    internal var _nethack_get_player_class_name: (@convention(c) () -> UnsafePointer<CChar>?)?
    internal var _nethack_get_player_race_name: (@convention(c) () -> UnsafePointer<CChar>?)?
    internal var _nethack_zone_get_metadata: (@convention(c) (UnsafeMutablePointer<CChar>, Int) -> Void)?
    internal var _ios_get_terrain_under_player: (@convention(c) () -> CChar)?
    internal var _ios_get_player_position_fn: (@convention(c) (UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Void)?
    internal var _ios_check_escape_warning: (@convention(c) () -> Int32)?
    internal var _ios_setup_default_symbols: (@convention(c) () -> Void)?
    internal var _ios_get_objects_at: (@convention(c) (Int32, Int32, UnsafeMutablePointer<IOSObjectInfo>, Int32) -> Int32)?
    internal var _ios_get_render_queue: (@convention(c) () -> UnsafeMutablePointer<RenderQueue>?)?

    // Batch 5: Render queue functions (2)
    internal var _render_queue_dequeue: (@convention(c) (UnsafeMutablePointer<RenderQueue>, UnsafeMutablePointer<RenderQueueElement>) -> Bool)?
    internal var _render_queue_is_empty: (@convention(c) (UnsafePointer<RenderQueue>) -> Bool)?

    // MARK: - Legacy Properties
    // NOTE: internal for extension access

    // CRITICAL: Thread-safe access to state flags via NSLock
    // Protects against data races from concurrent access (MainActor + background queue)
    internal let stateLock = NSLock()

    nonisolated(unsafe) internal var _isInitialized = false
    internal var isInitialized: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isInitialized
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _isInitialized = newValue
        }
    }

    // CRITICAL: Thread-safe atomic access to gameStarted flag
    // REVERT: C-layer query caused hang around turn 295-300
    // Root cause TBD - for now use NSLock-based stored property
    internal let gameStartedLock = NSLock()
    nonisolated(unsafe) internal var _gameStarted = false
    internal var gameStarted: Bool {
        get {
            gameStartedLock.lock()
            defer { gameStartedLock.unlock() }
            return _gameStarted
        }
        set {
            gameStartedLock.lock()
            defer { gameStartedLock.unlock() }
            _gameStarted = newValue
        }
    }

    // CRITICAL: Thread-safe access to sendInput function pointer
    // FIX: Rapid command sending (10x Search) caused SIGSEGV due to
    // concurrent access to _nethack_send_input_threaded during lazy resolution
    internal let sendInputLock = NSLock()

    nonisolated(unsafe) internal var _hadPreviousGame = false
    internal var hadPreviousGame: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _hadPreviousGame
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _hadPreviousGame = newValue
        }
    }

    // CRITICAL: Pending character selection - survives dylib reload!
    // These are set by setRole/setRace/etc and re-applied after dylib reload in startGame()
    internal var pendingRole: Int32 = -1
    internal var pendingRace: Int32 = -1
    internal var pendingGender: Int32 = -1
    internal var pendingAlignment: Int32 = -1
    internal var pendingPlayerName: String = ""

    internal var gameTask: Task<Void, Error>?
    internal let requiredAPIVersion: Int32 = 1

    // CRITICAL: Use SHARED serial queue for thread-safe NetHack C code access
    // NetHack is NOT thread-safe (from 1987!) and ALL access MUST go through ONE queue
    internal var nethackQueue: DispatchQueue {
        NetHackSerialExecutor.shared.queue
    }

    private init() {
        // Dylib will be loaded on first use (lazy loading)
        print("[Bridge] NetHackBridge initialized (dylib will load on demand)")
    }

    // MARK: - Dylib Management

    /// Load dylib and resolve all function pointers
    /// UNIFIED INITIALIZATION: Same for NEW GAME and CONTINUE CHARACTER
    internal func ensureDylibLoaded() throws {
        guard !dylib.isLoaded else {
            return
        }

        print("[Bridge] 🟢 Loading NetHack dylib...")
        try dylib.load()
        print("[Bridge] ✅ Dylib loaded successfully")

        // CRITICAL: Full dylib initialization - SINGLE SOURCE OF TRUTH
        // This function does ALL dylib-level initialization in correct order:
        // 1. ios_early_init() - gs.subrooms, early_init(), ios_init_savedir()
        // 2. ios_init_file_prefixes() - Set iOS paths BEFORE dlb_init()
        // 3. dlb_init() - Data file system
        // 4. l_nhcore_init() - Lua scripting
        // 5. REMOVED: status_initialize() - Moved to game initialization (requires window system!)
        // 6. ios_reset_all_static_state() - Bridge state
        // 7. Boulder symbol override
        //
        // This is the UNIFIED path for BOTH NEW GAME and CONTINUE CHARACTER!
        // NOTE: status_initialize() is called later during game start (ios_newgame.c or ios_save_integration.c)
        try ios_full_dylib_init()
        print("[Bridge] ✅ Full dylib initialization complete")

        // Register callbacks with C code (now that dylib is loaded)
        registerCallbacks()
        print("[Bridge] ✅ Callbacks registered with C code")
    }

    /// Unload dylib to reset ALL static state
    func unloadDylib() {
        print("[Bridge] Unloading dylib to reset static state...")

        // CRITICAL FIX: MUST call shutdown BEFORE unload!
        // This resets full_init_called = 0 in ios_dylib_lifecycle.c
        // Without this, panic("ios_full_dylib_init() called twice") on reload!
        if dylib.isLoaded {
            print("[Bridge] Calling ios_full_dylib_shutdown() to reset static flags...")
            do {
                try ios_full_dylib_shutdown()
                print("[Bridge] ✓ Shutdown complete - static flags reset")
            } catch {
                print("[Bridge] ⚠️ Shutdown failed: \(error) - continuing with unload")
            }
        }

        dylib.unload()

        // Clear all function pointers (will be re-resolved on next load)
        clearFunctionPointers()

        // CRITICAL FIX: Reset initialization flag so next operation will reload dylib
        // This allows "New Character" to work after exiting a game
        isInitialized = false

        print("[Bridge] ✅ Dylib unloaded - ALL static state cleared, isInitialized reset to false")
    }

    /// Clear all function pointer caches
    internal func clearFunctionPointers() {
        // Lifecycle
        _nethack_real_init = nil
        _nethack_start_new_game = nil
        _nethack_run_game_threaded = nil
        _ios_request_game_exit = nil
        _ios_reset_game_exit = nil

        // Input/Output
        _nethack_send_input_threaded = nil
        _nethack_get_output_buffer = nil
        _nethack_process_command = nil

        // Game state
        _nethack_get_turn_count = nil
        _nethack_get_player_stats_json = nil
        _nethack_get_map_data = nil
        _ios_get_player_position = nil

        // Character creation
        _nethack_get_available_roles = nil
        _nethack_set_role = nil
        _nethack_validate_character_selection = nil
        _nethack_finalize_character = nil

        // Save/Load
        _ios_quicksave = nil
        _ios_quickrestore = nil
        _ios_save_character = nil
        _ios_load_character = nil

        // Unified Lifecycle
        _ios_early_init = nil
        _ios_full_dylib_init = nil
        _ios_full_dylib_shutdown = nil
        _ios_wipe_memory = nil

        // Batch 1: Core lifecycle
        _ios_early_init = nil
        _nethack_real_newgame = nil
        _nethack_real_get_output = nil
        _nethack_real_clear_output = nil
        _nethack_real_send_input = nil
        _nethack_real_is_initialized = nil
        _nethack_real_is_started = nil
        _nethack_enable_threaded_mode = nil
        _nethack_start_game_thread = nil
        _ios_was_exit_requested = nil

        // Batch 2: Character creation
        _nethack_get_role_name = nil
        _nethack_get_available_races_for_role = nil
        _nethack_get_race_name = nil
        _nethack_get_available_genders_for_role = nil
        _nethack_get_gender_name = nil
        _nethack_get_available_alignments_for_role = nil
        _nethack_get_alignment_name = nil
        _nethack_set_race = nil
        _nethack_set_gender = nil
        _nethack_set_player_name = nil

        // Batch 3: Remaining character/map/command
        _nethack_set_alignment = nil
        _nethack_get_map_data_fn = nil
        _nethack_is_map_dirty = nil
        _nethack_clear_map_dirty = nil
        _nethack_start_new_game_fn = nil
        _nethack_process_command_fn = nil
        _nethack_set_yn_auto_yes = nil
        _nethack_set_yn_auto_no = nil
        _nethack_set_yn_ask_user = nil
        _nethack_set_yn_default = nil

        // Batch 4: Player metadata and object functions
        _nethack_set_next_yn_response = nil
        _nethack_get_player_name = nil
        _nethack_get_player_class_name = nil
        _nethack_get_player_race_name = nil
        _nethack_zone_get_metadata = nil
        _ios_get_terrain_under_player = nil
        _ios_get_player_position_fn = nil
        _ios_check_escape_warning = nil
        _ios_setup_default_symbols = nil
        _ios_get_objects_at = nil
        _ios_get_render_queue = nil

        // Batch 5: Render queue functions
        _render_queue_dequeue = nil
        _render_queue_is_empty = nil
    }

    // MARK: - Lazy Symbol Resolution
    // NOTE: All internal for extension access

    /// Lazy-resolve nethack_real_init
    internal func nethack_real_init() throws {
        try ensureDylibLoaded()
        if _nethack_real_init == nil {
            _nethack_real_init = try dylib.resolveFunction("nethack_real_init")
        }
        _nethack_real_init?()
    }

    /// Lazy-resolve nethack_start_new_game
    internal func nethack_start_new_game() throws {
        try ensureDylibLoaded()
        if _nethack_start_new_game == nil {
            _nethack_start_new_game = try dylib.resolveFunction("nethack_start_new_game")
        }
        _nethack_start_new_game?()
    }

    // NOTE: nethack_send_input_threaded moved to NetHackBridge+Commands.swift

    /// Lazy-resolve ios_request_game_exit
    internal func ios_request_game_exit() throws {
        try ensureDylibLoaded()
        if _ios_request_game_exit == nil {
            _ios_request_game_exit = try dylib.resolveFunction("ios_request_game_exit")
        }
        _ios_request_game_exit?()
    }

    // MARK: - Lazy Symbol Resolution (continued - 16 remaining)

    // Game State Functions
    internal func nethack_get_turn_count() throws -> Int {
        try ensureDylibLoaded()
        if _nethack_get_turn_count == nil {
            _nethack_get_turn_count = try dylib.resolveFunction("nethack_get_turn_count")
        }
        guard let fn = _nethack_get_turn_count else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_turn_count")
        }
        return fn()
    }

    internal func nethack_get_map_data() throws -> UnsafePointer<CChar>? {
        try ensureDylibLoaded()
        if _nethack_get_map_data == nil {
            _nethack_get_map_data = try dylib.resolveFunction("nethack_get_map_data")
        }
        return _nethack_get_map_data?()
    }

    // NOTE: State wrappers moved to NetHackBridge+State.swift
    // NOTE: Character creation wrappers moved to NetHackBridge+CharacterCreation.swift

    // NOTE: Save/Load wrappers moved to NetHackBridge+SaveLoad.swift

    // Lifecycle Functions (remaining)
    internal func nethack_run_game_threaded() throws {
        try ensureDylibLoaded()
        if _nethack_run_game_threaded == nil {
            _nethack_run_game_threaded = try dylib.resolveFunction("nethack_run_game_threaded")
        }
        _nethack_run_game_threaded?()
    }

    internal func ios_reset_game_exit() throws {
        try ensureDylibLoaded()
        if _ios_reset_game_exit == nil {
            _ios_reset_game_exit = try dylib.resolveFunction("ios_reset_game_exit")
        }
        _ios_reset_game_exit?()
    }

    // Input/Output Functions (remaining)
    internal func nethack_get_output_buffer() throws -> UnsafePointer<CChar>? {
        try ensureDylibLoaded()
        if _nethack_get_output_buffer == nil {
            _nethack_get_output_buffer = try dylib.resolveFunction("nethack_get_output_buffer")
        }
        return _nethack_get_output_buffer?()
    }

    internal func nethack_process_command() throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_process_command == nil {
            _nethack_process_command = try dylib.resolveFunction("nethack_process_command")
        }
        guard let fn = _nethack_process_command else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_process_command")
        }
        return fn()
    }

    // MARK: - Batch 1 Lazy Wrappers (Core Lifecycle - 12 functions) - UNIFIED LIFECYCLE

    internal func ios_full_dylib_init() throws {
        if _ios_full_dylib_init == nil {
            _ios_full_dylib_init = try dylib.resolveFunction("ios_full_dylib_init")
        }
        _ios_full_dylib_init?()
    }

    internal func ios_full_dylib_shutdown() throws {
        if _ios_full_dylib_shutdown == nil {
            _ios_full_dylib_shutdown = try dylib.resolveFunction("ios_full_dylib_shutdown")
        }
        _ios_full_dylib_shutdown?()
    }

    internal func ios_wipe_memory() throws {
        if _ios_wipe_memory == nil {
            _ios_wipe_memory = try dylib.resolveFunction("ios_wipe_memory")
        }
        _ios_wipe_memory?()
    }

    internal func ios_early_init() throws {
        try ensureDylibLoaded()  // CRITICAL FIX: Load dylib before resolving symbol
        if _ios_early_init == nil {
            _ios_early_init = try dylib.resolveFunction("ios_early_init")
        }
        _ios_early_init?()
    }

    internal func nethack_real_newgame() throws {
        try ensureDylibLoaded()
        if _nethack_real_newgame == nil {
            _nethack_real_newgame = try dylib.resolveFunction("nethack_real_newgame")
        }
        _nethack_real_newgame?()
    }

    internal func nethack_real_get_output() throws -> UnsafePointer<CChar> {
        try ensureDylibLoaded()
        if _nethack_real_get_output == nil {
            _nethack_real_get_output = try dylib.resolveFunction("nethack_real_get_output")
        }
        guard let fn = _nethack_real_get_output else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_real_get_output")
        }
        return fn()
    }

    internal func nethack_real_clear_output() throws {
        try ensureDylibLoaded()
        if _nethack_real_clear_output == nil {
            _nethack_real_clear_output = try dylib.resolveFunction("nethack_real_clear_output")
        }
        _nethack_real_clear_output?()
    }

    internal func nethack_real_send_input(_ cmd: UnsafePointer<CChar>) throws {
        try ensureDylibLoaded()
        if _nethack_real_send_input == nil {
            _nethack_real_send_input = try dylib.resolveFunction("nethack_real_send_input")
        }
        _nethack_real_send_input?(cmd)
    }

    internal func nethack_real_is_initialized() throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_real_is_initialized == nil {
            _nethack_real_is_initialized = try dylib.resolveFunction("nethack_real_is_initialized")
        }
        guard let fn = _nethack_real_is_initialized else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_real_is_initialized")
        }
        return fn()
    }

    internal func nethack_real_is_started() throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_real_is_started == nil {
            _nethack_real_is_started = try dylib.resolveFunction("nethack_real_is_started")
        }
        guard let fn = _nethack_real_is_started else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_real_is_started")
        }
        return fn()
    }

    internal func nethack_enable_threaded_mode() throws {
        try ensureDylibLoaded()
        if _nethack_enable_threaded_mode == nil {
            _nethack_enable_threaded_mode = try dylib.resolveFunction("nethack_enable_threaded_mode")
        }
        _nethack_enable_threaded_mode?()
    }

    internal func nethack_start_game_thread() throws {
        try ensureDylibLoaded()
        if _nethack_start_game_thread == nil {
            _nethack_start_game_thread = try dylib.resolveFunction("nethack_start_game_thread")
        }
        _nethack_start_game_thread?()
    }

    internal func ios_was_exit_requested() throws -> Int32 {
        try ensureDylibLoaded()
        if _ios_was_exit_requested == nil {
            _ios_was_exit_requested = try dylib.resolveFunction("ios_was_exit_requested")
        }
        guard let fn = _ios_was_exit_requested else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "ios_was_exit_requested")
        }
        return fn()
    }

    // NOTE: Batch 2 (Character Creation wrappers) moved to NetHackBridge+CharacterCreation.swift

    // MARK: - Batch 3 Lazy Wrappers (Map/Command functions)

    internal func nethack_get_map_data_wrap() throws -> UnsafePointer<CChar> {
        try ensureDylibLoaded()
        if _nethack_get_map_data_fn == nil {
            _nethack_get_map_data_fn = try dylib.resolveFunction("nethack_get_map_data")
        }
        guard let fn = _nethack_get_map_data_fn else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_map_data")
        }
        return fn()
    }

    internal func nethack_is_map_dirty_wrap() throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_is_map_dirty == nil {
            _nethack_is_map_dirty = try dylib.resolveFunction("nethack_is_map_dirty")
        }
        guard let fn = _nethack_is_map_dirty else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_is_map_dirty")
        }
        return fn()
    }

    internal func nethack_clear_map_dirty_wrap() throws {
        try ensureDylibLoaded()
        if _nethack_clear_map_dirty == nil {
            _nethack_clear_map_dirty = try dylib.resolveFunction("nethack_clear_map_dirty")
        }
        _nethack_clear_map_dirty?()
    }

    internal func nethack_start_new_game_wrap() throws {
        try ensureDylibLoaded()
        if _nethack_start_new_game_fn == nil {
            _nethack_start_new_game_fn = try dylib.resolveFunction("nethack_start_new_game")
        }
        _nethack_start_new_game_fn?()
    }

    internal func nethack_process_command_wrap() throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_process_command_fn == nil {
            _nethack_process_command_fn = try dylib.resolveFunction("nethack_process_command")
        }
        guard let fn = _nethack_process_command_fn else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_process_command")
        }
        return fn()
    }

    // NOTE: YN response wrappers moved to NetHackBridge+YNResponse.swift

    // NOTE: Player metadata wrappers moved to NetHackBridge+State.swift

    // MARK: - Batch 4 Lazy Wrappers (Zone and object functions)

    internal func nethack_zone_get_metadata_wrap(_ buffer: UnsafeMutablePointer<CChar>, _ bufsize: Int) throws {
        try ensureDylibLoaded()
        if _nethack_zone_get_metadata == nil {
            _nethack_zone_get_metadata = try dylib.resolveFunction("nethack_zone_get_metadata")
        }
        _nethack_zone_get_metadata?(buffer, bufsize)
    }

    // NOTE: ios_get_terrain_under_player_wrap, ios_get_player_position_wrap moved to +State.swift

    internal func ios_setup_default_symbols_wrap() throws {
        try ensureDylibLoaded()
        if _ios_setup_default_symbols == nil {
            _ios_setup_default_symbols = try dylib.resolveFunction("ios_setup_default_symbols")
        }
        _ios_setup_default_symbols?()
    }

    internal func ios_get_objects_at_wrap(_ x: Int32, _ y: Int32, _ buffer: UnsafeMutablePointer<IOSObjectInfo>, _ max_objects: Int32) throws -> Int32 {
        try ensureDylibLoaded()
        if _ios_get_objects_at == nil {
            _ios_get_objects_at = try dylib.resolveFunction("ios_get_objects_at")
        }
        guard let fn = _ios_get_objects_at else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "ios_get_objects_at")
        }
        return fn(x, y, buffer, max_objects)
    }

    // NOTE: RenderQueue wrappers moved to NetHackBridge+RenderQueue.swift

    func checkLibraryVersion() -> Bool {
        // Get version info from C library
        let apiVersion = nethack_get_api_version()
        let libVersion = String(cString: nethack_get_lib_version())
        let buildInfo = String(cString: nethack_get_build_info())

        // Log version information
        print("═══════════════════════════════════════════")
        print("NetHack Library Information:")
        print("  Version: \(libVersion)")
        print("  API Version: \(apiVersion)")
        print("  Build Info: \(buildInfo)")
        print("═══════════════════════════════════════════")

        // Check API compatibility
        let isCompatible = nethack_check_compatibility(requiredAPIVersion)
        if isCompatible == 0 {
            print("❌ API Version Mismatch!")
            print("   Required: \(requiredAPIVersion)")
            print("   Library:  \(apiVersion)")
            print("   Please rebuild the library with: ./build_nethack_dylib.sh")
            return false
        }

        print("✅ Library version check passed")
        return true
    }

    func getLibraryVersion() -> String {
        return String(cString: nethack_get_lib_version())
    }

    // Lua debug logging functions
    func getLuaLogs() -> String {
        return String(cString: nethack_get_lua_logs())
    }

    func dumpLuaLogs() {
        print("=== LUA DEBUG LOGS ===")
        print(getLuaLogs())
        print("======================")
    }

    func clearLuaLogs() {
        nethack_clear_lua_logs()
    }

    func getBuildInfo() -> String {
        return String(cString: nethack_get_build_info())
    }

    func initializeGame() {
        print("[Bridge] 🟡 initializeGame() START")
        print("[Bridge] 🟡 isInitialized = \(isInitialized)")
        guard !isInitialized else {
            print("[Bridge] 🟡 Already initialized - RETURNING EARLY")
            return
        }

        print("[Bridge] 🟡 Clearing Lua logs...")
        clearLuaLogs()

        do {
            print("[Bridge] 🟡 Calling ios_early_init()...")
            try ios_early_init()
            print("[Bridge] 🟡 ios_early_init() completed")

            print("[Bridge] 🟡 Calling nethack_real_init()...")
            try nethack_real_init()
            print("[Bridge] 🟡 nethack_real_init() completed")
        } catch {
            print("[Bridge] ❌ Failed to initialize NetHack: \(error)")
            return
        }

        // Check if initialization was successful by looking for errors
        let logs = getLuaLogs()
        if logs.contains("ERROR") || logs.contains("panic") {
            print("⚠️ Errors detected during initialization!")
            dumpLuaLogs()
        }

        print("[Bridge] 🟡 Setting isInitialized = true")
        isInitialized = true
        print("[Bridge] 🟡 initializeGame() END - Success!")
    }

    func randomizeCharacter() {
        guard isInitialized else {
            initializeGame()
            return
        }

        // Call the C function to randomize character
        nethack_real_randomize()
    }

    func startGame() {
        // Ensure NetHack is initialized before starting game
        if !isInitialized {
            print("[Bridge] Initializing NetHack before starting game...")
            initializeGame()
        }

        // CRITICAL FIX: ALWAYS wait for game thread to fully exit before dylib operations!
        // BUG: Checking gameTask != nil is WRONG - it gets set to nil at end of stopGameAsync,
        // but game thread might STILL be running on nethackQueue!
        // FIX: Check gameStarted flag instead, and ALWAYS use queue barrier to ensure thread exit
        if gameStarted || gameTask != nil {
            print("[Bridge] WARNING: Previous game is running (gameStarted=\(gameStarted), gameTask=\(gameTask != nil)), cleaning up...")

            // CRITICAL: Use queue barrier to wait for game thread to FULLY exit
            // stopGameAsync() sets gameStarted=false at the END, so we wait for that
            print("[Bridge] 🔄 Waiting for game thread to fully exit (queue barrier)...")
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await self.stopGameAsync()
                semaphore.signal()
            }
            semaphore.wait()
            print("[Bridge] ✓ Game thread CONFIRMED exited - safe for dylib reload")
        } else {
            // Even if no game running, ensure dylib is in clean state
            // This handles case where previous game exited cleanly but dylib still loaded
            print("[Bridge] No game running (gameStarted=false, gameTask=nil)")
            print("[Bridge] Checking if dylib cleanup needed...")
            if dylib.isLoaded {
                print("[Bridge] ⚠️ Dylib still loaded from previous session - forcing cleanup...")
                let semaphore = DispatchSemaphore(value: 0)
                nethackQueue.async {
                    // Queue barrier: Ensures no game thread is running
                    semaphore.signal()
                }
                semaphore.wait()
                print("[Bridge] ✓ Queue barrier passed - no active game thread")
            }
        }

        // CRITICAL ARCHITECTURE FIX: Always reload dylib for FRESH STATE (same as loadGame)
        // This is the PROVEN pattern from loadGame() that works 100% consistently!
        // Why: dylib reload gives us fresh state automatically - no need for complex cleanup
        // With dylib reload, we get: fresh Lua, fresh DLB, fresh iOS bridge, fresh memory
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
            print("[Bridge] 🔄 Re-registering callbacks after dylib reload...")
            registerCallbacks()
            print("[Bridge] ✓ Callbacks re-registered with new dylib instance")

            print("[Bridge] ✓ Fresh dylib loaded - ready for new game")
        } catch {
            print("[Bridge] ❌ Failed to reload dylib: \(error)")
            return
        }

        // CRITICAL FIX: Check if this is a RESTORE (snapshot load) vs NEW game
        // When loading snapshot, memory.dat is already restored by iosRestoreComplete()
        // We MUST NOT reset memory or call nethack_start_new_game()!
        let isRestore = nethack_is_snapshot_loaded()

        if isRestore {
            print("[Bridge] ⚠️ Snapshot loaded - SKIPPING cleanup/reset/newgame!")
        }

        // NOTE: No need for manual ios_reinit_subsystems() - dylib reload does this!
        // The dylib reload above calls ios_full_dylib_init() which reinitializes everything:
        // - Lua (l_nhcore_init)
        // - DLB (dlb_init)
        // - iOS bridge state (ios_reset_all_static_state)
        // - File prefixes (ios_init_file_prefixes)
        // This is the SAME pattern that makes loadGame() work 100% consistently!

        // CRITICAL: Reset exit flag BEFORE starting new game!
        // If we reset it AFTER, the game starts with game_should_exit=1 and exits immediately
        do {
            try ios_reset_game_exit()
        } catch {
            print("[Bridge] ❌ Failed to reset game exit flag: \(error)")
            return
        }

        // CRITICAL FIX: Re-apply pending character selection AFTER dylib reload!
        // The dylib reload above cleared all C state including flags.initrole etc.
        // We stored the values in Swift before the reload, now we restore them.
        if pendingRole >= 0 || pendingRace >= 0 || pendingGender >= 0 || pendingAlignment >= 0 {
            print("[Bridge] 🔄 Re-applying pending character selection after dylib reload:")
            print("[Bridge]   pendingRole=\(pendingRole), pendingRace=\(pendingRace), pendingGender=\(pendingGender), pendingAlignment=\(pendingAlignment)")
            print("[Bridge]   pendingPlayerName='\(pendingPlayerName)'")

            if pendingRole >= 0 {
                do { try nethack_set_role(pendingRole) }
                catch { print("[Bridge] ❌ Failed to re-apply role: \(error)") }
            }
            if pendingRace >= 0 {
                do { try nethack_set_race(pendingRace) }
                catch { print("[Bridge] ❌ Failed to re-apply race: \(error)") }
            }
            if pendingGender >= 0 {
                do { try nethack_set_gender(pendingGender) }
                catch { print("[Bridge] ❌ Failed to re-apply gender: \(error)") }
            }
            if pendingAlignment >= 0 {
                do { try nethack_set_alignment(pendingAlignment) }
                catch { print("[Bridge] ❌ Failed to re-apply alignment: \(error)") }
            }
            if !pendingPlayerName.isEmpty {
                do {
                    try pendingPlayerName.withCString { cString in
                        try nethack_set_player_name(cString)
                    }
                } catch { print("[Bridge] ❌ Failed to re-apply player name: \(error)") }
            }

            print("[Bridge] ✅ Character selection re-applied to fresh dylib")
        }

        // Initialize game first (this sets up all the structures)
        // CRITICAL: Only call for NEW games, NOT for restores!
        // For restores, game state is already loaded by iosRestoreComplete()
        if !isRestore {
            // Check if wizard mode (debug mode) is enabled in user preferences
            // Read directly from UserDefaults to avoid MainActor requirement
            let debugModeKey = "com.nethack.debug.wizardMode"
            if let debugData = UserDefaults.standard.data(forKey: debugModeKey),
               let debugEnabled = try? JSONDecoder().decode(Bool.self, from: debugData),
               debugEnabled {
                print("[Bridge] 🧙 Debug mode enabled - activating wizard mode")
                enableWizardMode()
            }

            do {
                try nethack_start_new_game()
            } catch {
                print("[Bridge] ❌ Failed to start new game: \(error)")
                return
            }

            // NOTE: ios_setup_default_symbols() is called from ios_newgame.c
            // MUST be called IMMEDIATELY after init_symbols() which wipes overrides
            // DO NOT call here - symbols would already be cached!
            print("[Bridge] iOS symbol customizations applied (inside ios_newgame.c)")
        } else {
            print("[Bridge] Snapshot restore - game state already loaded, skipping nethack_start_new_game()")

            // NOTE: Symbol overrides are applied inside ios_restore_complete()
            // RIGHT after window system initialization, before map rendering
            print("[Bridge] iOS symbol customizations applied (inside ios_restore_complete())")
        }

        // CRITICAL: Start game loop on SINGLE serial queue
        // Game loop is EVENT-DRIVEN (not infinite blocking):
        //   - moveloop() calls nh_poskey() which WAITS on pthread_cond
        //   - sendCommand() signals condition → moveloop wakes → processes turn
        //   - Single queue is safe because moveloop YIELDS during wait
        // This ensures ALL NetHack access is serialized (thread-safe for 1987 C code)
        NetHackSerialExecutor.shared.queue.async { [weak self] in
            print("[Bridge] Game thread started on SINGLE serial queue (event-driven)")

            // This runs forever until game ends
            do {
                try self?.nethack_run_game_threaded()
            } catch {
                print("[Bridge] ❌ Game thread failed: \(error)")
                return
            }

            print("[Bridge] ========================================")
            print("[Bridge] GAME THREAD ENDED - DEATH DETECTION")
            print("[Bridge] ========================================")

            // Check if game ended due to exit request
            guard let self = self else {
                print("[Bridge] ❌ ERROR: self is nil in completion handler!")
                return
            }
            let wasExitRequested = ((try? self.ios_was_exit_requested()) ?? 0) != 0
            print("[Bridge] Exit requested: \(wasExitRequested)")

            // Check if player died
            let isPlayerDead = nethack_is_player_dead()
            print("[Bridge] nethack_is_player_dead() returned: \(isPlayerDead)")

            // CRITICAL FIX: If exit was requested, do NOT treat as death!
            // The isPlayerDead flag can be stale from previous game session.
            // Only show death screen if player ACTUALLY died (not exit request).
            if isPlayerDead != 0 && !wasExitRequested {
                print("[Bridge] ☠️ PLAYER DEATH DETECTED - PROCESSING...")

                // Get death info from C BEFORE clearing it
                let deathInfo = DeathInfo.fromCDeathInfo()
                print("[Bridge] Death info: score=\(deathInfo.finalScore), message=\(deathInfo.deathMessage)")

                // Post player died notification with death info
                // GameManager will show death screen and handle cleanup
                print("[Bridge] Posting NetHackPlayerDied notification to main thread...")
                DispatchQueue.main.async {
                    print("[Bridge] ON MAIN THREAD - Posting NetHackPlayerDied notification NOW")
                    NotificationCenter.default.post(
                        name: Notification.Name("NetHackPlayerDied"),
                        object: deathInfo
                    )
                    print("[Bridge] NetHackPlayerDied notification POSTED")
                }

                // Clear death info AFTER posting notification
                // (The DeathInfo struct already has copies of all data)
                print("[Bridge] Clearing death info...")
                nethack_clear_death_info()
                print("[Bridge] Death info cleared")
            }

            // Update gameStarted flag synchronously
            DispatchQueue.main.async { [weak self] in
                self?.gameStarted = false
            }

            // CRITICAL FIX: Only post game ended notification for EXPLICIT EXIT
            // NOT for death - death screen handles its own lifecycle via NetHackPlayerDied notification
            // RCA: Race condition between NetHackPlayerDied and NetHackGameEnded notifications
            // If both are posted, handleGameEnded() might run before handlePlayerDeath() sets showDeathScreen=true
            if wasExitRequested {
                print("[Bridge] Game ended due to EXIT REQUEST - posting NetHackGameEnded notification")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("NetHackGameEnded"),
                        object: nil
                    )
                }
                return
            }

            if isPlayerDead == 0 {
                print("[Bridge] ⚠️ Game thread exited but neither death nor exit (startup issue?) - NOT posting any notification")
                return
            }

            print("[Bridge] Game ended due to DEATH - NetHackPlayerDied notification already posted, NOT posting NetHackGameEnded")
        }
        gameStarted = true
        print("[Bridge] Game started in threaded mode on SINGLE serial queue")
    }

    func stopGame() {
        print("[Bridge] === STOP GAME REQUEST (SYNC - DEPRECATED) ===")
        print("[Bridge] ⚠️ WARNING: Synchronous stopGame() is deprecated. Use stopGameAsync() instead!")

        // Legacy synchronous implementation - kept for compatibility
        // New code should use stopGameAsync() for proper async/await patterns
        Task {
            await self.stopGameAsync()
        }
    }

    func stopGameAsync() async {
        // NOTE: Removed guard against double-call - it caused hangs when unloadDylib()
        // was called before stopGameAsync() (which sets gameStarted=false early)
        // The timeout below handles stuck threads gracefully instead.

        print("[Bridge] === STOP GAME REQUEST (ASYNC) ===")
        print("[Bridge] Current state: gameStarted=\(gameStarted), gameTask=\(gameTask != nil)")

        // Phase 1: Request game exit
        print("[Bridge] Phase 1: Requesting game exit...")
        do {
            try ios_request_game_exit()
        } catch {
            print("[Bridge] ❌ Failed to request game exit: \(error)")
        }

        // Phase 2: CRITICAL - Wait for game thread to FULLY exit using queue barrier
        // This uses serial queue semantics to GUARANTEE thread completion
        // TIMEOUT: Max 3 seconds to prevent UI hang if game thread is stuck
        print("[Bridge] Phase 2: Waiting for game thread to exit (queue barrier, 3s timeout)...")

        let gameThreadExited = await withTaskGroup(of: Bool.self) { group in
            // Task 1: Wait for queue barrier
            group.addTask {
                await withCheckedContinuation { continuation in
                    self.nethackQueue.async {
                        print("[Bridge] ✅ Game thread CONFIRMED exited (queue barrier passed)")
                        continuation.resume(returning: true)
                    }
                }
            }

            // Task 2: Timeout after 3 seconds
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return false
            }

            // Return first result (either barrier passed or timeout)
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        if !gameThreadExited {
            print("[Bridge] ⚠️ TIMEOUT: Game thread did NOT exit after 3s")
            print("[Bridge] ⚠️ SKIPPING CLEANUP - unsafe while thread running!")
            print("[Bridge] ⚠️ User may need to force-quit app to recover")
            // NOTE: We do NOT unload dylib or wipe memory - game thread still running!
            // gameStarted queries C layer - it will return true until thread actually exits
            await MainActor.run {
                self.gameTask = nil
                print("[Bridge] ⚠️ STOP GAME INCOMPLETE (timeout) - gameStarted=\(self.gameStarted)")
            }
            return
        }

        print("[Bridge] ✓ Game thread confirmed exited via barrier")

        // Phase 3: Run cleanup DIRECTLY (not in detached task)
        // This ensures cleanup completes BEFORE function returns
        print("[Bridge] === CLEANUP (game thread confirmed dead) ===")

        // Phase 3a: Full dylib shutdown - UNIFIED SHUTDOWN
        // This function does ALL shutdown in correct order:
        // 1. status_finish() - Free status buffers
        // 2. freedynamicdata() - Free NetHack dynamic memory
        // 3. l_nhcore_done() - Shutdown Lua
        // 4. dlb_cleanup() - Clean up data files
        print("[Bridge] Phase 3a: Full dylib shutdown...")
        do {
            try ios_full_dylib_shutdown()
            print("[Bridge] ✓ Full dylib shutdown complete")
        } catch {
            print("[Bridge] ⚠️ Shutdown failed: \(error) - continuing cleanup anyway")
        }

        // Phase 3b: Wipe memory (AFTER shutdown, so all structures are freed)
        print("[Bridge] Phase 3b: Wiping memory...")
        do {
            try ios_wipe_memory()
            print("[Bridge] ✓ Memory wiped")
        } catch {
            print("[Bridge] ⚠️ Memory wipe failed: \(error) - continuing cleanup anyway")
        }

        // Phase 3c: Clear output buffer
        print("[Bridge] Phase 3c: Clearing output...")
        try? nethack_real_clear_output()

        // Phase 4: NOW SAFE to unload dylib (thread confirmed dead, cleanup done)
        print("[Bridge] Phase 4: Unloading dylib (SAFE - thread exited)...")
        unloadDylib()
        print("[Bridge] ✅ Dylib unloaded - ALL static state cleared automatically!")

        // Final state reset on MainActor
        // This runs AFTER cleanup, ensuring gameStarted = false happens LAST
        await MainActor.run {
            self.gameStarted = false
            self.gameTask = nil
            print("[Bridge] ✅ STOP GAME COMPLETE! (gameStarted=\(self.gameStarted))")
        }
        // Now caller KNOWS cleanup is done when await returns
    }

    // NOTE: Save/Load functions moved to NetHackBridge+SaveLoad.swift
    //       (saveGame, hasSaveGame, loadGame, loadCharacter, deleteSave, getSaveInfo)

    // NOTE: Command functions moved to NetHackBridge+Commands.swift
    //       (getGameDisplay, sendCommand, moveInDirection, wait, travelTo,
    //        examineTileAsync, examineTile, kickDoor, openDoor, closeDoor,
    //        fireQuiver, throwItem, unlockDoor, lockDoor, travelToStairsUp,
    //        travelToStairsDown, travelToAltar, travelToFountain)

    // NOTE: State query functions moved to NetHackBridge+State.swift
    //       (getPlayerStats, isGameInitialized, isGameStarted, getGameStateSnapshot,
    //        getTerrainUnderPlayer, getPlayerPosition)

    // NOTE: Character creation functions moved to NetHackBridge+CharacterCreation.swift
    //       (getAvailableRoles, getRoleName, getAvailableRacesForRole, getRaceName,
    //        getAvailableGendersForRole, getGenderName, getAvailableAlignmentsForRole,
    //        getAlignmentName, setPlayerName, setRole, setRace, setGender, setAlignment,
    //        validateCharacterSelection, finalizeCharacter)

    func startNewGame() {
        // For NEW games, Swift view is already visible and ready
        signalSwiftReadyForNewGame()
        startGame()
    }

    func resumeGame() throws {
        print("[Bridge] resumeGame() called - current gameStarted=\(gameStarted)")

        // CRITICAL FIX: Reset exit flag FIRST (was set in stopGame())
        try ios_reset_game_exit()
        print("[Bridge] ✅ Exit flag reset for new session")

        gameStarted = true
        print("[Bridge] ✅ resumeGame() - setting gameStarted=true (enables command sending)")

        // Ensure game thread is running
        if !isGameThreadRunning() {
            print("[Bridge] Starting game thread (was not running)")

            // CRITICAL: Start game loop on SINGLE serial queue
            // Game loop is EVENT-DRIVEN (moveloop waits on condition variable)
            // Single queue is safe - moveloop YIELDS control while waiting for input
            NetHackSerialExecutor.shared.queue.async { [weak self] in
                print("[Bridge] Game thread resumed on SINGLE serial queue (event-driven)")

                // This runs until game ends (yields during nh_poskey wait)
                do {
                    try self?.nethack_run_game_threaded()
                } catch {
                    print("[Bridge] ❌ Game thread failed: \(error)")
                    return
                }

                print("[Bridge] ========================================")
                print("[Bridge] GAME THREAD ENDED (resumeGame) - DEATH DETECTION")
                print("[Bridge] ========================================")

                // Check if game ended due to exit request
                guard let self = self else {
                    print("[Bridge] ❌ ERROR: self is nil in completion handler!")
                    return
                }
                let wasExitRequested = ((try? self.ios_was_exit_requested()) ?? 0) != 0
                print("[Bridge] Exit requested: \(wasExitRequested)")

                // Check if player died
                let isPlayerDead = nethack_is_player_dead()
                print("[Bridge] nethack_is_player_dead() returned: \(isPlayerDead)")

                // CRITICAL: Death detection for resumed games
                if isPlayerDead != 0 && !wasExitRequested {
                    print("[Bridge] ☠️ PLAYER DEATH DETECTED (resumed game) - PROCESSING...")

                    // Get death info from C BEFORE clearing it
                    let deathInfo = DeathInfo.fromCDeathInfo()
                    print("[Bridge] Death info: score=\(deathInfo.finalScore), message=\(deathInfo.deathMessage)")

                    // Post player died notification with death info
                    DispatchQueue.main.async {
                        print("[Bridge] ON MAIN THREAD - Posting NetHackPlayerDied notification NOW")
                        NotificationCenter.default.post(
                            name: Notification.Name("NetHackPlayerDied"),
                            object: deathInfo
                        )
                        print("[Bridge] NetHackPlayerDied notification POSTED")
                    }

                    // Clear death info AFTER posting notification
                    print("[Bridge] Clearing death info...")
                    nethack_clear_death_info()
                    print("[Bridge] Death info cleared")
                }

                // CRITICAL: Set gameStarted = false IMMEDIATELY (not async!)
                // This must happen BEFORE we process death/exit handling
                // so that any state checks see the correct value
                self.gameStarted = false
                print("[Bridge] Game thread ended - gameStarted=\(self.gameStarted)")

                // Post appropriate notification
                if wasExitRequested {
                    print("[Bridge] Game ended due to EXIT REQUEST - posting NetHackGameEnded notification")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("NetHackGameEnded"),
                            object: nil
                        )
                    }
                    return
                }

                if isPlayerDead != 0 {
                    print("[Bridge] Game ended due to DEATH - NetHackPlayerDied already posted")
                    return
                }

                print("[Bridge] ⚠️ Game thread exited but neither death nor exit - NOT posting any notification")
            }
            print("[Bridge] ✅ Game thread started on SINGLE serial queue")
        } else {
            print("[Bridge] Game thread already running")
        }
        print("[Bridge] resumeGame() complete - gameStarted=\(gameStarted)")
    }

    // Helper to check if game thread is running
    internal func isGameThreadRunning() -> Bool {
        return gameTask != nil && !gameTask!.isCancelled
    }

    // NOTE: YN Callback Management functions moved to NetHackBridge+YNResponse.swift

    // MARK: - Game State Metadata Functions

    /// Get the current location name
    func getLocationName() -> String {
        guard let cString = nethack_get_location_name() else {
            return "Unknown"
        }
        return String(cString: cString)
    }

    /// Get the total play time (in game turns)
    func getPlayTime() -> Int {
        return Int(nethack_get_play_time())
    }

    // NOTE: getPlayerName(), getPlayerClassName(), getPlayerRaceName() moved to +State.swift

    // MARK: - Message Readiness

    /// Signal that Swift UI is ready to receive messages
    /// This will flush any queued messages from NEW game startup
    func signalSwiftReadyForMessages() {
        guard dylib.isLoaded else { return }

        // Resolve the function if not already done
        if _ios_swift_ready_for_messages == nil {
            _ios_swift_ready_for_messages = try? dylib.resolveFunction("ios_swift_ready_for_messages")
        }

        guard let signalReady = _ios_swift_ready_for_messages else {
            print("[Bridge] ❌ Failed to resolve ios_swift_ready_for_messages")
            return
        }

        print("[Bridge] 📬 Signaling Swift is ready for messages (will flush queue)")
        signalReady()
    }

    /// Signal that Swift UI is ready for NEW game messages
    /// (View is already visible when NEW game starts)
    func signalSwiftReadyForNewGame() {
        guard dylib.isLoaded else { return }

        // Resolve the function if not already done
        if _ios_swift_ready_for_new_game == nil {
            _ios_swift_ready_for_new_game = try? dylib.resolveFunction("ios_swift_ready_for_new_game")
        }

        guard let signalReady = _ios_swift_ready_for_new_game else {
            print("[Bridge] ❌ Failed to resolve ios_swift_ready_for_new_game")
            return
        }

        print("[Bridge] 📬 NEW game - signaling Swift is already ready")
        signalReady()
    }

    /// Enable wizard mode (must be called before nethack_start_new_game)
    func enableWizardMode() {
        guard dylib.isLoaded else {
            print("[Bridge] ❌ Cannot enable wizard mode - dylib not loaded")
            return
        }

        // Resolve the function if not already done
        if _ios_enable_wizard_mode == nil {
            _ios_enable_wizard_mode = try? dylib.resolveFunction("ios_enable_wizard_mode")
        }

        guard let enableWizard = _ios_enable_wizard_mode else {
            print("[Bridge] ❌ Failed to resolve ios_enable_wizard_mode")
            return
        }

        print("[Bridge] 🧙 Enabling wizard mode")
        enableWizard()
    }

    // MARK: - Callback Registration

    /// Register callbacks with C code (replaces weak symbols which don't work with dylib)
    internal func registerCallbacks() {
        // Resolve registration functions
        _ios_register_map_update_callback = try? dylib.resolveFunction("ios_register_map_update_callback")
        _ios_register_game_ready_callback = try? dylib.resolveFunction("ios_register_game_ready_callback")

        guard let registerMapCallback = _ios_register_map_update_callback,
              let registerGameReadyCallback = _ios_register_game_ready_callback else {
            print("[SWIFT] ❌ Failed to resolve callback registration functions!")
            return
        }

        // Map update callback
        let mapCallback: @convention(c) () -> Void = {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .nethackMapUpdated, object: nil)
            }
        }

        // Game ready callback
        let gameReadyCallback: @convention(c) () -> Void = {
            print("[SWIFT GAME READY] 🎯 Game ready signal received from C")
            DispatchQueue.main.async {
                print("[SWIFT GAME READY] Posting notification to main thread")
                NotificationCenter.default.post(name: .nethackGameReady, object: nil)
            }
        }

        // Register with C code
        registerMapCallback(mapCallback)
        registerGameReadyCallback(gameReadyCallback)
        print("[SWIFT] ✅ Map and game-ready callbacks registered")

        // Register death animation callback
        // This is called from C when death is detected (BEFORE data collection)
        // to trigger visual animation IN PARALLEL with the ~10s death disclosure
        registerDeathAnimationCallback()
        print("[SWIFT] ✅ Death animation callback registered")
    }

    // MARK: - Game State Snapshot (Push Model - Lock-Free)
    // NOTE: getGameStateSnapshot() moved to NetHackBridge+State.swift

    // Lazy function pointer for snapshot (raw pointer-based API for C compatibility)
    internal var _ios_get_game_state_snapshot: (@convention(c) (UnsafeMutableRawPointer) -> Void)?

}

@_cdecl("ios_swift_yn_callback")
public func ios_swift_yn_callback(query: UnsafePointer<CChar>?, resp: UnsafePointer<CChar>?, def: CChar) -> CChar {
    guard let query = query else { return 0 }
    let queryString = String(cString: query)

    print("[Swift YN Callback] Received query: \(queryString)")

    // CRITICAL: Skip tutorial to reach main game loop
    // Tutorial prompt blocks moveloop before it can process input commands
    if queryString.lowercased().contains("tutorial") {
        print("[Swift YN Callback] Detected tutorial prompt, returning 'n' to skip")
        return CChar("n".utf8.first!)
    }

    if queryString.contains("Overwrite") {
        print("[Swift YN Callback] Detected 'Overwrite', returning 'y'")
        return CChar("y".utf8.first!)
    }

    // For other queries, return 0 to let the C code use its default logic
    return 0
}

extension Notification.Name {
    static let nethackMapUpdated = Notification.Name("nethackMapUpdated")
    static let nethackGameReady = Notification.Name("nethackGameReady")
    static let nethackGameLoading = Notification.Name("nethackGameLoading")
}

// MARK: - Game State Snapshot Structs
// Extracted to Models/Bridge/GameStateSnapshot.swift

// C bridge function declarations
// These connect to our RealNetHackBridge.c functions

// Early initialization function - MUST be called before nethack_real_init()
// Batch 1 functions migrated to runtime dylib loading (see lazy wrappers above)

// ALL BATCHES MIGRATED TO RUNTIME DYLIB LOADING:
// - Batch 1: Core lifecycle functions (10 migrated)
// - Batch 2: Character creation functions (10 migrated)
// - Batch 3: Remaining character/map/command functions (10 migrated)
// - Batch 4: Player metadata and object functions (10 migrated)
// - Batch 5: Render queue functions (2 migrated)
//
// TOTAL: 42 functions migrated from @_silgen_name to lazy dylib loading
//
// NO MORE @_silgen_name DECLARATIONS - ALL USE RUNTIME SYMBOL RESOLUTION!

// MARK: - iOS Documents Directory Helper
// Returns the REAL iOS app sandbox Documents/NetHack path
@_cdecl("ios_swift_get_documents_path")
public func ios_swift_get_documents_path(_ buffer: UnsafeMutablePointer<CChar>?, _ bufsize: Int) -> Int {
    guard let buffer = buffer, bufsize > 0 else {
        return 0
    }
    
    // Get the proper iOS Documents directory
    guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        return 0
    }
    
    // Append NetHack subdirectory
    let nethackURL = documentsURL.appendingPathComponent("NetHack")
    let path = nethackURL.path
    
    // Ensure it fits in buffer
    guard path.utf8.count < bufsize else {
        return 0
    }
    
    // Copy to C buffer
    path.withCString { cString in
        strncpy(buffer, cString, bufsize - 1)
        buffer[bufsize - 1] = 0  // Null terminate
    }
    
    return 1  // Success
}
