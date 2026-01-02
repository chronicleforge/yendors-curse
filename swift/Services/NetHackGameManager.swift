import Foundation
import SwiftUI
import Observation

// THREAD SAFETY: NetHack C code is NOT thread-safe and requires serialized access.
// We use a SHARED serial DispatchQueue to ensure all bridge calls happen sequentially
// on a background thread, preventing main thread blocking while maintaining safety.
// PERFORMANCE: @Observable macro provides 3-5x fewer view updates compared to ObservableObject
// by tracking per-property access instead of triggering all views on any property change.
@MainActor
@Observable
final class NetHackGameManager {

    // CRITICAL: Use SHARED serial queue for thread-safe NetHack C bridge access
    // All NetHack access (game loop, commands, state updates) MUST use the same queue!
    private var nethackQueue: DispatchQueue {
        NetHackSerialExecutor.shared.queue
    }
    var gameOutput: String = ""

    /// Game running state - delegates to state machine (Single Source of Truth)
    var isGameRunning: Bool {
        get { GameLifecycleStateMachine.shared.isPlaying }
        set { } // No-op setter for compatibility - state machine controls this
    }

    var mapData: String = ""  // Keep for compatibility
    var playerPosition: (x: Int, y: Int) = (0, 0)

    // MapState is now @Observable - no manual bridging needed!
    var mapState = MapState()

    // currentCharacterMetadata removed - not needed in simplified system
    var turnCount: Int = 0
    var loadError: String? = nil  // For displaying load errors to user
    var playerStats: PlayerStats?  // Real-time player statistics

    // Exit animation state
    var exitingToMenu: Bool = false
    var exitMessage: String = ""

    // UI State - Inspect Mode
    var inspectModeActive: Bool = false

    // PERF: Overlay manager for auto-updating inventory cache
    // Set by NetHackGameView during initialization
    weak var overlayManager: GameOverlayManager?

    private let bridge = NetHackBridge.shared  // ✅ USE SINGLETON!
    private let memoryManager = NetHackMemoryManager.shared
    private let saveLoadCoordinator = SimplifiedSaveLoadCoordinator.shared
    private var mapUpdateObserver: NSObjectProtocol?
    private var gameEndedObserver: NSObjectProtocol?
    private var gameLoadingObserver: NSObjectProtocol?

    // PERF: Coalesce rapid notifications - multiple can fire per action
    private var lastStateUpdate: CFTimeInterval = 0
    private let stateUpdateDebounceInterval: CFTimeInterval = 0.016  // ~60fps cap

    init() {
        setupGame()
        setupNotifications()
    }

    deinit {
        // @Observable with @MainActor: deinit is nonisolated,
        // but NotificationCenter is thread-safe so this is fine
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        // Listen for map updates from the NetHack game loop
        // FIX: Notification already comes from main thread (ios_swift_map_update_callback)
        // No need for double-dispatch - directly update on MainActor
        print("[GameManager] 🔔 Setting up map update observer...")
        mapUpdateObserver = NotificationCenter.default.addObserver(
            forName: .nethackMapUpdated,
            object: nil,
            queue: .main  // Ensure delivery on main thread
        ) { [weak self] _ in
            // PERF FIX: Remove Task wrapper - already on main thread!
            guard let self = self else { return }

            // PERF: Coalesce rapid notifications (multiple can fire per action)
            // Skip if last update was less than 16ms ago (~60fps cap)
            let now = CACurrentMediaTime()
            guard now - self.lastStateUpdate >= self.stateUpdateDebounceInterval else {
                return  // Skip - coalesce with previous update
            }
            self.lastStateUpdate = now

            self.updateGameState()
        }

        // NOTE: Death handling moved to DeathFlowController
        // DeathFlowController observes both "NetHackDeathAnimationStart" and "NetHackPlayerDied"

        // Listen for game ended
        // PERF FIX: Direct call, no Task wrapper (queue: .main = already main thread)
        gameEndedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NetHackGameEnded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.handleGameEnded()  // Direct call
        }

        // Listen for game ready - the map is already populated by C callbacks during load
        // Just trigger a state update to sync Swift-side stats
        gameLoadingObserver = NotificationCenter.default.addObserver(
            forName: .nethackGameReady,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            print("[GameManager] 🎮 Game ready - syncing state")
            // Don't reset! Map is already populated. Just update stats.
            self.playerStats = self.bridge.getPlayerStats()
            self.turnCount = self.playerStats?.moves ?? 0
        }
    }

    private func setupGame() {
        // DO NOTHING during initialization
        // NetHack will be initialized lazily when user starts/loads a game
        // This prevents early initialization crashes during SwiftUI setup
        print("[GameManager] setupGame() - deferred initialization (lazy init when needed)")
    }

    private func autoStartGame() {
        // Automatically set up a character like the user would
        // Do this synchronously so the name is set before the game starts
        print("[AUTO-START] Setting player name...")
        self.setPlayerName("TestHero")

        print("[AUTO-START] Finalizing character...")
        self.finalizeCharacter()

        // Now start the game with a small delay to let the UI update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("[AUTO-START] Starting new game...")
            self.startNewGame()
            print("[AUTO-START] Game started!")
        }
    }

    private func updateDisplay() {
        updateGameState()  // Use combined update
    }
    
    func startGame() {
        bridge.startGame()
        DispatchQueue.main.async {
            self.isGameRunning = true
            self.updateDisplay()
        }
    }

    // MARK: - Save/Load Delegation to SaveLoadCoordinator

    /// Load saved game - DELEGATES to SaveLoadCoordinator
    func loadGame() -> Bool {
        print("[GameManager] Delegating to SaveLoadCoordinator.continueGame()")

        guard saveLoadCoordinator.continueGame() else {
            loadError = saveLoadCoordinator.errorMessage ?? "Failed to load saved game"
            return false
        }

        // Update UI state
        isGameRunning = true
        updateGameState()

        // Apply user's autopickup preferences to C engine (after load)
        AutopickupBridgeService.shared.applyUserPreferences()

        // PERF: Initial inventory load (first cache population)
        overlayManager?.updateInventory()

        // Activate menu bridge for Swift UI menu display
        MenuBridge.shared.activate()

        return true
    }

    /// Check if there's a saved game to continue - DELEGATES to SaveLoadCoordinator
    func hasSavedGame() -> Bool {
        return saveLoadCoordinator.hasSavedGame()
    }

    func stopGame() async {
        // CRITICAL FIX: Proper async/await pattern
        // Previous Task.detached was fire-and-forget with race conditions
        // New pattern: await completion and update state synchronously
        await bridge.stopGameAsync()
        isGameRunning = false
    }

    // No timers needed - we're turn-based!
    // Updates happen after each command

    // Combined update function - Called on MainActor from notification
    // FIX: Removed DispatchQueue.main.async - already on main thread!
    @MainActor
    func updateGameState() {
        // CRITICAL: Don't access C game state after death - memory may be freed
        guard bridge.gameStarted, isGameRunning else {
            print("[GameManager] ⚠️ Game not running - skipping state update")
            return
        }

        // PERF: Frame budget enforcement (60fps = 16.66ms)
        let perfStart = CACurrentMediaTime()
        let timestamp = String(format: "%.3f", CACurrentMediaTime())
        print("[\(timestamp)] [GameManager] updateGameState called!")

        // Fetch player stats
        let newPlayerStats = bridge.getPlayerStats()

        // Debug: Log stats to verify they're being read correctly
        if let stats = newPlayerStats {
            if stats.hp > 0 || stats.hpmax > 0 {
                let ts1 = String(format: "%.3f", CACurrentMediaTime())
                print("[\(ts1)] [GameManager] Player Stats: HP=\(stats.hp)/\(stats.hpmax), PW=\(stats.pw)/\(stats.pwmax), AC=\(stats.ac), Level=\(stats.level)")
            }
        }

        // Get player position and terrain (for legacy compatibility)
        let playerPos = bridge.getPlayerPosition()
        let terrainChar = bridge.getTerrainUnderPlayer()

        // FIX: Direct update - we're already on MainActor!
        // PHASE 2 MIGRATION: Consume render queue instead of parsing ASCII map
        // Bug #4/#8 Fix: Consume callback for status updates
        let oldStats = self.playerStats  // Store for feedback detection
        if let updatedStats = self.mapState.consumeRenderQueue(from: self.bridge) {
            self.playerStats = updatedStats
            // Trigger feedback based on state change
            FeedbackEngine.shared.processStateChange(old: oldStats, new: updatedStats)
        } else {
            // Fallback: Use polling if no status update in queue
            self.playerStats = newPlayerStats
            // Trigger feedback for fallback path too
            if let stats = newPlayerStats {
                FeedbackEngine.shared.processStateChange(old: oldStats, new: stats)
            }
        }

        // CRITICAL: Update player position from NetHack (queue doesn't track player separately)
        if let playerPos = playerPos {
            let ts2 = String(format: "%.3f", CACurrentMediaTime())
            print("[\(ts2)] [GameManager] Real player position from NetHack: (\(playerPos.x),\(playerPos.y))")
            self.mapState.setPlayerPositionFromNetHack(nhX: playerPos.x, nhY: playerPos.y)
        }

        // CRITICAL: Update terrain under player
        if let terrainChar = terrainChar {
            let ts3 = String(format: "%.3f", CACurrentMediaTime())
            print("[\(ts3)] [GameManager] Real terrain under player: '\(terrainChar)'")
            self.mapState.updateUnderlyingTile(terrainChar)
        }

        // turnCount now comes from playerStats.moves
        self.turnCount = newPlayerStats?.moves ?? 0

        // PERF: Auto-update inventory cache (makes inventory open instant)
        // RCA: On-demand parsing blocks UI thread for 50-100ms
        // Solution: Update inventory every turn (5-10ms overhead, unnoticeable)
        overlayManager?.updateInventory()

        // PERF: Measure frame budget (Target: <16.66ms for 60fps)
        let perfEnd = CACurrentMediaTime()
        let duration = (perfEnd - perfStart) * 1000  // Convert to ms
        let ts4 = String(format: "%.3f", CACurrentMediaTime())
        print("[\(ts4)] [GameManager] Game state updated - Turn: \(self.turnCount), Duration: \(String(format: "%.2f", duration))ms")

        #if DEBUG
        if duration > 16.66 {
            print("[PERF WARNING] ⚠️ Frame budget exceeded! \(String(format: "%.2f", duration))ms > 16.66ms (60fps target)")
        }
        #endif
    }
    
    // CRITICAL FIX: Make nonisolated like movement functions to avoid @MainActor weak self issue
    // RCA: @MainActor + [weak self] in async block = self becomes nil immediately
    // Solution: Use direct call pattern like movement functions (which work correctly)
    nonisolated func sendCommand(_ command: String) {
        print("[GameManager] Sending command: '\(command)'")
        // Direct call to bridge - same pattern as working movement functions
        NetHackBridge.shared.sendCommand(command)
    }

    // Movement functions - delegate to bridge
    // CRITICAL: Changed to SYNC execution - async blocks were not executing!
    // BUILD VERSION: BOULDER-SYM-B0LD (Boulder symbol changed from ` to 0)
    nonisolated func moveUp() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD Move UP pressed")
        NetHackBridge.shared.moveInDirection("up")
    }

    nonisolated func moveDown() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD Move DOWN pressed")
        NetHackBridge.shared.moveInDirection("down")
    }

    nonisolated func moveLeft() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD Move LEFT pressed")
        NetHackBridge.shared.moveInDirection("left")
    }

    nonisolated func moveRight() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD Move RIGHT pressed")
        NetHackBridge.shared.moveInDirection("right")
    }

    nonisolated func moveUpLeft() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD Move UP-LEFT pressed")
        NetHackBridge.shared.moveInDirection("upleft")
    }

    nonisolated func moveUpRight() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD Move UP-RIGHT pressed")
        NetHackBridge.shared.moveInDirection("upright")
    }

    nonisolated func moveDownLeft() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD Move DOWN-LEFT pressed")
        NetHackBridge.shared.moveInDirection("downleft")
    }

    nonisolated func moveDownRight() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD Move DOWN-RIGHT pressed")
        NetHackBridge.shared.moveInDirection("downright")
    }

    nonisolated func wait() {
        print("[GameManager] 🔨 BUILD:BOULDER-SYM-B0LD WAIT/REST pressed")
        NetHackBridge.shared.wait()
    }

    // Travel to specific coordinates using NetHack's travel command
    // CRITICAL FIX: Use nonisolated + direct call pattern (consistent with movement functions)
    // RCA: async queue + weak self caused lag and nil failures
    nonisolated func travelTo(x: Int, y: Int) {
        print("[GameManager] 🚀 Travel to \(x), \(y) requested")
        NetHackBridge.shared.travelTo(x: x, y: y)
    }

    /// Check if travel is currently in progress
    nonisolated func isTraveling() -> Bool {
        return NetHackBridge.shared.isTraveling()
    }

    // Examine a specific tile
    // CRITICAL FIX: Use nonisolated + direct call pattern (consistent with movement functions)
    nonisolated func examineTile(x: Int, y: Int) -> String? {
        print("[GameManager] Examine tile at \(x), \(y)")
        return NetHackBridge.shared.examineTile(x: x, y: y)
    }

    // Async version for thread-safe C bridge access
    nonisolated func examineTileAsync(x: Int, y: Int) async -> String? {
        print("[GameManager] Examine tile async at \(x), \(y)")
        return await NetHackBridge.shared.examineTileAsync(x: x, y: y)
    }

    // CRITICAL FIX: All tile action functions now use nonisolated + direct call pattern
    // RCA: async queue + weak self caused lag and nil failures
    nonisolated func kickDoor(x: Int, y: Int) {
        print("[GameManager] Kick door at \(x), \(y)")
        NetHackBridge.shared.kickDoor(x: x, y: y)
    }

    nonisolated func openDoor(x: Int, y: Int) {
        print("[GameManager] Open door at \(x), \(y)")
        NetHackBridge.shared.openDoor(x: x, y: y)
    }

    nonisolated func closeDoor(x: Int, y: Int) {
        print("[GameManager] Close door at \(x), \(y)")
        NetHackBridge.shared.closeDoor(x: x, y: y)
    }

    nonisolated func fireQuiver(x: Int, y: Int) {
        print("[GameManager] Fire quiver at \(x), \(y)")
        NetHackBridge.shared.fireQuiver(x: x, y: y)
    }

    nonisolated func throwItem(x: Int, y: Int) {
        print("[GameManager] Throw item at \(x), \(y)")
        NetHackBridge.shared.throwItem(x: x, y: y)
    }

    nonisolated func unlockDoor(x: Int, y: Int) {
        print("[GameManager] Unlock door at \(x), \(y)")
        NetHackBridge.shared.unlockDoor(x: x, y: y)
    }

    nonisolated func lockDoor(x: Int, y: Int) {
        print("[GameManager] Lock door at \(x), \(y)")
        NetHackBridge.shared.lockDoor(x: x, y: y)
    }

    // MARK: - Autotravel Functions
    // CRITICAL FIX: All autotravel functions now use nonisolated + direct call pattern

    nonisolated func travelToStairsUp() {
        print("[GameManager] Travel to stairs up requested")
        guard NetHackBridge.shared.travelToStairsUp() else {
            print("[GameManager] No upward stairs found on this level")
            return
        }
        print("[GameManager] Traveling to upward stairs...")
    }

    nonisolated func travelToStairsDown() {
        print("[GameManager] Travel to stairs down requested")
        guard NetHackBridge.shared.travelToStairsDown() else {
            print("[GameManager] No downward stairs found on this level")
            return
        }
        print("[GameManager] Traveling to downward stairs...")
    }

    nonisolated func travelToAltar() {
        print("[GameManager] Travel to altar requested")
        guard NetHackBridge.shared.travelToAltar() else {
            print("[GameManager] No visible altar found")
            return
        }
        print("[GameManager] Traveling to altar...")
    }

    nonisolated func travelToFountain() {
        print("[GameManager] Travel to fountain requested")
        guard NetHackBridge.shared.travelToFountain() else {
            print("[GameManager] No visible fountain found")
            return
        }
        print("[GameManager] Traveling to fountain...")
    }

    // Move in a specific direction (for adjacent tiles)
    // CRITICAL FIX: Use nonisolated + direct call pattern (consistent with other movement functions)
    nonisolated func moveInDirection(dx: Int, dy: Int) {
        let direction: String
        if dx == 0 && dy == -1 {
            direction = "up"
        } else if dx == 0 && dy == 1 {
            direction = "down"
        } else if dx == -1 && dy == 0 {
            direction = "left"
        } else if dx == 1 && dy == 0 {
            direction = "right"
        } else if dx == -1 && dy == -1 {
            direction = "upleft"
        } else if dx == 1 && dy == -1 {
            direction = "upright"
        } else if dx == -1 && dy == 1 {
            direction = "downleft"
        } else if dx == 1 && dy == 1 {
            direction = "downright"
        } else {
            direction = "wait"
        }
        NetHackBridge.shared.moveInDirection(direction)
    }

    /// Exit to menu - DELEGATES to SaveLoadCoordinator
    func exitToMenu() {
        guard isGameRunning else { return }

        print("[GameManager] Exit to menu requested - delegating to SaveLoadCoordinator...")

        // Use async task for animation timing
        Task { @MainActor in
            // CRITICAL FIX: Capture screenshot FIRST, while view is still visible
            // The screenshot needs the SceneKit view which gets unregistered when view disappears
            if let characterName = saveLoadCoordinator.getActiveCharacter() {
                print("[GameManager] 📸 Capturing screenshot BEFORE exit animation...")
                let screenshotSuccess = ScreenshotService.shared.captureAndSaveScreenshot(for: characterName)
                if screenshotSuccess {
                    print("[GameManager] ✅ Screenshot captured successfully")
                } else {
                    print("[GameManager] ⚠️ Screenshot capture failed")
                }
            }

            // Show exit animation AFTER screenshot
            exitingToMenu = true
            exitMessage = "Verlasse das Labyrinth..."

            // Phase 1: Show exit message (min 1s)
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s

            // Phase 2: Save and exit via coordinator (screenshot already taken)
            exitMessage = "Speichere deinen Fortschritt..."
            print("[GameManager] Calling SaveLoadCoordinator.exitToMenu()...")

            let saveSuccess = await saveLoadCoordinator.exitToMenu()

            if saveSuccess {
                print("[GameManager] ✅ Save and exit successful")
            } else {
                print("[GameManager] ⚠️ Save failed: \(saveLoadCoordinator.errorMessage ?? "unknown error")")
            }

            // Phase 3: Memory stats
            #if DEBUG
            memoryManager.printMemoryStats()
            #endif

            // Show save complete message (min 1s)
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s

            // Done - hide overlay and return to menu
            isGameRunning = false
            exitingToMenu = false
            exitMessage = ""
            print("[GameManager] Game ended - ready to continue or start new game")
        }
    }

    // Character creation functions
    func getAvailableRoles() -> Int {
        print("[GameManager] 🟣 getAvailableRoles() START")
        print("[GameManager] 🟣 Calling bridge.getAvailableRoles()...")
        let roles = bridge.getAvailableRoles()
        print("[GameManager] 🟣 bridge.getAvailableRoles() returned: \(roles)")
        return roles
    }

    func getRoleName(_ roleIdx: Int) -> String {
        return bridge.getRoleName(roleIdx)
    }

    func getAvailableRacesForRole(_ roleIdx: Int) -> Int {
        return bridge.getAvailableRacesForRole(roleIdx)
    }

    func getRaceName(_ raceIdx: Int) -> String {
        return bridge.getRaceName(raceIdx)
    }

    func getAvailableGendersForRole(_ roleIdx: Int) -> Int {
        return bridge.getAvailableGendersForRole(roleIdx)
    }

    func getGenderName(_ genderIdx: Int) -> String {
        return bridge.getGenderName(genderIdx)
    }

    func getAvailableAlignmentsForRole(_ roleIdx: Int) -> Int {
        return bridge.getAvailableAlignmentsForRole(roleIdx)
    }

    func getAlignmentName(_ alignIdx: Int) -> String {
        return bridge.getAlignmentName(alignIdx)
    }

    func setPlayerName(_ name: String) {
        bridge.setPlayerName(name)
    }

    func setRole(_ roleIdx: Int) {
        bridge.setRole(roleIdx)
    }

    func setRace(_ raceIdx: Int) {
        bridge.setRace(raceIdx)
    }

    func setGender(_ genderIdx: Int) {
        bridge.setGender(genderIdx)
    }

    func setAlignment(_ alignIdx: Int) {
        bridge.setAlignment(alignIdx)
    }

    func validateCharacterSelection() -> Int {
        return bridge.validateCharacterSelection()
    }

    func finalizeCharacter() {
        bridge.finalizeCharacter()
    }

    /// Start new game - coordinates with SimplifiedSaveLoadCoordinator
    func startNewGame() {
        print("[GameManager] startNewGame called")

        #if DEBUG
        // Show memory stats before starting
        memoryManager.printMemoryStats()
        #endif

        print("[GameManager] Calling bridge.startNewGame()")
        bridge.startNewGame()

        // Apply user's autopickup preferences to C engine
        AutopickupBridgeService.shared.applyUserPreferences()

        #if DEBUG
        // Show memory stats after starting
        memoryManager.printMemoryStats()
        #endif

        print("[GameManager] Setting isGameRunning = true")
        self.isGameRunning = true

        // PERF: Initial inventory load (first cache population)
        overlayManager?.updateInventory()

        // Activate menu bridge for Swift UI menu display
        MenuBridge.shared.activate()

        print("[GameManager] isGameRunning is now: \(self.isGameRunning)")
        self.updateDisplay()

        print("[GameManager] startNewGame completed")

        // NOTE: SaveLoadCoordinator.startNewGame() is called by FullscreenCharacterCreationView
        // to set activeCharacter and create initial slot
    }





    // MARK: - Container Operations

    /// Get container contents from NetHack
    func getContainerContents(_ item: NetHackItem) -> [NetHackItem] {
        guard item.isContainer else { return [] }
        guard let itemPtr = ios_get_inventory_item_by_invlet(Int8(item.invlet.asciiValue ?? 0)) else {
            print("[GameManager] Item '\(item.invlet)' not found in inventory")
            return []
        }

        var itemsPtr: UnsafeMutablePointer<ios_item_info>?
        let count = ios_get_container_contents(itemPtr, &itemsPtr)

        guard count > 0, let items = itemsPtr else {
            if count == -1 {
                print("[GameManager] ERROR: Failed to load container contents")
            }
            return []
        }

        // Convert C array to Swift array
        let result = (0..<Int(count)).compactMap { i -> NetHackItem? in
            var info = items[i]
            let name = String(cString: tuple_to_ptr(&info.name.0))
            let fullname = String(cString: tuple_to_ptr(&info.fullname.0))

            return NetHackItem(
                invlet: Character(UnicodeScalar(UInt8(bitPattern: info.invlet))),
                name: name,
                fullName: fullname,
                category: .misc, // TODO: Parse from name
                quantity: Int(info.quantity)
            )
        }

        ios_free_container_contents(items, count)
        return result
    }

    /// Check if item can be put in container (prevents BoH explosion!)
    func canContain(container: NetHackItem, item: NetHackItem) -> (Bool, String?) {
        guard let containerPtr = ios_get_inventory_item_by_invlet(Int8(container.invlet.asciiValue ?? 0)) else {
            return (false, "Container not found")
        }
        guard let itemPtr = ios_get_inventory_item_by_invlet(Int8(item.invlet.asciiValue ?? 0)) else {
            return (false, "Item not found")
        }

        if ios_can_contain(containerPtr, itemPtr) {
            return (true, nil)
        } else {
            // Check specific failure reasons
            if container.containerType == .bagOfHolding {
                return (false, "Bag of Holding would EXPLODE! 💥")
            }
            return (false, "Cannot put item in container")
        }
    }

    /// Helper to convert tuple to pointer (for String(cString:))
    private func tuple_to_ptr<T>(_ tuple: UnsafePointer<T>) -> UnsafePointer<CChar> {
        return UnsafeRawPointer(tuple).assumingMemoryBound(to: CChar.self)
    }

    // MARK: - Discoveries

    /// Get discovered items from NetHack using disco[] array (vanilla behavior)
    /// Only returns items the player has actually encountered/discovered
    func getDiscoveries() -> [DiscoveryItem] {
        guard isGameRunning else { return [] }

        // Use new disco[]-based bridge function (matches vanilla's dodiscovered())
        let rawEntries = NetHackBridge.shared.getDiscoveredItems()

        return rawEntries.map { raw in
            let category = ItemCategory.fromOclass(Int8(raw.oclass))

            return DiscoveryItem(
                id: Int32(raw.otyp),
                name: raw.name,
                appearance: raw.description ?? "",
                category: category,
                isDiscovered: raw.is_known,
                isEncountered: raw.is_encountered,
                isUnique: raw.is_unique
            )
        }
    }

    // MARK: - Save/Load Delegation (OLD FUNCTIONS REMOVED)
    // All save/load operations now go through SaveLoadCoordinator
    // See: SaveLoadCoordinator.swift for the single source of truth
}

enum GameCommand: String, CaseIterable {
    case search = "s"
    case open = "o"
    case close = "c"
    case kick = "K"
    case look = ":"
    case inventory = "i"
    case pickup = ","
    case drop = "d"
    case eat = "e"
    case quaff = "q"
    case read = "r"
    case zap = "z"
    case wear = "W"
    case wield = "w"
    case putOn = "P"
    case remove = "R"
    case takeOff = "T"
    case pray = "#pray"
    case help = "?"
    case quit = "#quit"
    // Removed .save - we use snapshot system now

    var description: String {
        switch self {
        case .search: return "Search"
        case .open: return "Open"
        case .close: return "Close"
        case .kick: return "Kick"
        case .look: return "Look"
        case .inventory: return "Inventory"
        case .pickup: return "Pickup"
        case .drop: return "Drop"
        case .eat: return "Eat"
        case .quaff: return "Quaff"
        case .read: return "Read"
        case .zap: return "Zap"
        case .wear: return "Wear"
        case .wield: return "Wield"
        case .putOn: return "Put On"
        case .remove: return "Remove"
        case .takeOff: return "Take Off"
        case .pray: return "Pray"
        case .help: return "Help"
        case .quit: return "Quit"
        }
    }
}

// MARK: - Game Lifecycle Extension

extension NetHackGameManager {

    /// Called when game ends (not death - that's handled by DeathFlowController)
    private func handleGameEnded() {
        print("[GameManager] Game ended")
        self.isGameRunning = false
    }

    /// Reset for new game (used when NOT going through death flow)
    func resetForNewGame() {
        print("[GameManager] ========================================")
        print("[GameManager] PROPER GAME LIFECYCLE RESET")
        print("[GameManager] Following NetHack's shutdown → wipe → reinit pattern")
        print("[GameManager] ========================================")

        // Step 1: Orderly NetHack shutdown (like really_done() before exit)
        print("[GameManager] Step 1: ios_shutdown_game() - Orderly shutdown...")
        ios_shutdown_game()
        print("[GameManager]   ✓ freedynamicdata, dlb_cleanup, l_nhcore_done complete")

        // Step 2: Memory wipe (NOW safe - all structures freed)
        print("[GameManager] Step 2: ios_wipe_memory() - Zone allocator reset...")
        ios_wipe_memory()
        print("[GameManager]   ✓ Static heap wiped to zero")

        // Step 3: Re-initialize subsystems (dlb, Lua, iOS state)
        print("[GameManager] Step 3: ios_reinit_subsystems() - Reinitializing...")
        ios_reinit_subsystems()
        print("[GameManager]   ✓ dlb_init, l_nhcore_init, ios_reset_all_static_state complete")

        // Step 4: Reset Swift state
        print("[GameManager] Step 4: Resetting Swift state...")
        isGameRunning = false
        exitingToMenu = false
        exitMessage = ""
        nethack_clear_death_info()
        SimplifiedSaveLoadCoordinator.shared.reset()
        // NOTE: bridge.gameStarted is read-only - queries C layer directly
        bridge.gameTask = nil
        print("[GameManager]   ✓ Swift state reset (including coordinator and bridge)")

        print("[GameManager] ========================================")
        print("[GameManager] ✓ LIFECYCLE RESET COMPLETE - Ready for new game")
        print("[GameManager] ========================================")
    }

    /// Reset UI state for fresh game start
    func resetUIState() {
        print("[GameManager] Resetting UI state for new game...")
        gameOutput = ""
        mapData = ""
        playerPosition = (0, 0)
        turnCount = 0
        playerStats = nil
        inspectModeActive = false
        mapState = MapState()
        overlayManager?.resetForNewGame()
        TravelQueueManager.shared.clearQueue()  // Clear any queued travel destinations
        print("[GameManager] ✓ UI state reset complete")
    }
}
