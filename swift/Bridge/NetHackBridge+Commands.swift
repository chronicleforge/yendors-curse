import Foundation
import QuartzCore  // For CACurrentMediaTime

// =============================================================================
// NetHackBridge+Commands - Input and Command Functions
// =============================================================================
//
// This extension handles player input and commands:
// - Movement in all 8 directions
// - Wait/rest command
// - Travel commands (to coordinates and features)
// - Tile interaction (kick, open, close, lock, unlock doors)
// - Throw and fire commands
// - Tile examination
// - Lazy symbol resolution for command C functions
//
// =============================================================================

extension NetHackBridge {

    // MARK: - Lazy Wrappers (C Function Calls)

    /// Thread-safe send input - uses lock to protect function pointer access
    /// CRITICAL: This is called from nonisolated sendCommand() on any thread
    internal func nethack_send_input_threaded(_ cmd: UnsafePointer<CChar>) throws {
        try ensureDylibLoaded()

        // CRITICAL: Lock protects both lazy resolution AND the call itself
        // Without this, rapid commands (10x Search) cause SIGSEGV from
        // concurrent access to _nethack_send_input_threaded
        sendInputLock.lock()
        defer { sendInputLock.unlock() }

        if _nethack_send_input_threaded == nil {
            _nethack_send_input_threaded = try dylib.resolveFunction("nethack_send_input_threaded")
        }
        _nethack_send_input_threaded?(cmd)
    }

    // MARK: - Display

    /// Get current game display output
    func getGameDisplay() -> String {
        guard isInitialized else { return "Game not initialized" }

        // Get output from NetHack (will show TODOs until real integration)
        do {
            return String(cString: try nethack_real_get_output())
        } catch {
            return "Error getting display: \(error)"
        }
    }

    // MARK: - Core Input

    /// Send a command string to NetHack
    /// Thread-safe, can be called from any thread
    nonisolated func sendCommand(_ command: String) {
        // CRITICAL: sendCommand() MUST NOT be dispatched to queue!
        // Game loop (moveloop) runs on NetHackSerialExecutor queue and WAITS for input.
        // If we dispatch sendCommand to same queue → DEADLOCK!
        //
        // nethack_send_input_threaded() is ALREADY thread-safe:
        // - It only does: pthread_mutex_lock + enqueue + pthread_cond_signal + unlock
        // - No NetHack globals accessed, just signaling the waiting game loop
        // - This is the CORRECT pattern for event-driven architecture

        // gameStarted uses NSLock for thread-safe atomic access
        guard gameStarted else {
            #if DEBUG
            print("[Bridge] ❌ sendCommand BLOCKED - gameStarted=false, command='\(command)'")
            #endif
            return
        }

        do {
            try command.withCString { cString in
                try nethack_send_input_threaded(cString)
            }
        } catch {
            print("[Bridge] ❌ Failed to send command '\(command)': \(error)")
        }
    }

    /// Send a raw byte value to NetHack (bypasses UTF-8 encoding)
    /// Used for meta commands (M-x) where high bit (0x80) must be preserved as single byte
    /// Thread-safe, can be called from any thread
    nonisolated func sendRawByte(_ byte: UInt8) {
        // gameStarted uses NSLock for thread-safe atomic access
        guard gameStarted else {
            #if DEBUG
            print("[Bridge] ❌ sendRawByte BLOCKED - gameStarted=false, byte=\(byte)")
            #endif
            return
        }

        // Create a null-terminated C string with the raw byte
        // This bypasses Swift's UTF-8 encoding which would turn 0xC1 into 0xC3 0x81
        var bytes: [CChar] = [CChar(bitPattern: byte), 0]
        do {
            try nethack_send_input_threaded(&bytes)
        } catch {
            print("[Bridge] ❌ Failed to send raw byte \(byte): \(error)")
        }
    }

    // MARK: - Movement

    /// Move player in a direction
    /// - Parameter direction: "up", "down", "left", "right", "upleft", "upright", "downleft", "downright"
    nonisolated func moveInDirection(_ direction: String) {
        // Convert direction to NetHack numpad commands (1-9)
        // Numpad layout: 7 8 9
        //                4 5 6
        //                1 2 3
        let command: String
        switch direction.lowercased() {
        case "up": command = "8"        // North
        case "down": command = "2"      // South
        case "left": command = "4"      // West
        case "right": command = "6"     // East
        case "upleft": command = "7"    // Northwest
        case "upright": command = "9"   // Northeast
        case "downleft": command = "1"  // Southwest
        case "downright": command = "3" // Southeast
        default: return
        }
        sendCommand(command)
    }

    /// Wait/Rest - pass a turn without moving
    nonisolated func wait() {
        sendCommand(".")
    }

    // MARK: - Travel

    /// Travel to a specific tile using NetHack's travel command
    func travelTo(x: Int, y: Int) {
        nethack_travel_to(Int32(x), Int32(y))
    }

    /// Check if travel is currently in progress
    /// Returns true if character is traveling to a destination
    nonisolated func isTraveling() -> Bool {
        return nethack_is_traveling() != 0
    }

    // MARK: - Tile Examination

    /// Examine/look at a specific tile (ASYNC - Thread-safe)
    /// Uses separate thread because examine is READ-ONLY and game loop blocks on serial queue
    func examineTileAsync(x: Int, y: Int) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cString = nethack_examine_tile(Int32(x), Int32(y)) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(cString: cString))
            }
        }
    }

    /// DEPRECATED: Use examineTileAsync instead
    @available(*, deprecated, message: "Use examineTileAsync instead - this blocks the calling thread!")
    func examineTile(x: Int, y: Int) -> String? {
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            result = await examineTileAsync(x: x, y: y)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // MARK: - Door Interactions

    func kickDoor(x: Int, y: Int) {
        nethack_kick_door(Int32(x), Int32(y))
    }

    func openDoor(x: Int, y: Int) {
        nethack_open_door(Int32(x), Int32(y))
    }

    func closeDoor(x: Int, y: Int) {
        nethack_close_door(Int32(x), Int32(y))
    }

    func unlockDoor(x: Int, y: Int) {
        nethack_unlock_door(Int32(x), Int32(y))
    }

    func lockDoor(x: Int, y: Int) {
        nethack_lock_door(Int32(x), Int32(y))
    }

    // MARK: - Ranged Combat

    func fireQuiver(x: Int, y: Int) {
        nethack_fire_quiver(Int32(x), Int32(y))
    }

    func throwItem(x: Int, y: Int) {
        nethack_throw_item(Int32(x), Int32(y))
    }

    // MARK: - Autotravel

    /// Travel to upstairs
    func travelToStairsUp() -> Bool {
        return nethack_travel_to_stairs_up() != 0
    }

    /// Travel to downstairs
    func travelToStairsDown() -> Bool {
        return nethack_travel_to_stairs_down() != 0
    }

    /// Travel to altar
    func travelToAltar() -> Bool {
        return nethack_travel_to_altar() != 0
    }

    /// Travel to fountain
    func travelToFountain() -> Bool {
        return nethack_travel_to_fountain() != 0
    }
}
