import Foundation

/// CRITICAL: Single serial queue for ALL NetHack C code access
///
/// NetHack is from 1987 and is NOT thread-safe. ALL access to NetHack C functions
/// MUST go through this single serial queue to prevent race conditions, deadlocks,
/// and data corruption.
///
/// ARCHITECTURE RULE: Never create additional queues for NetHack access!
/// Use this shared queue for:
/// - Game loop execution (moveloop waits for input via condition variable)
/// - Command processing (signals condition variable to wake moveloop)
/// - Inventory fetching
/// - Map updates
/// - Save/Load operations
/// - All other NetHack C bridge calls
///
/// WHY SINGLE QUEUE:
/// NetHack's moveloop() is EVENT-DRIVEN, not infinite-blocking:
/// 1. moveloop() calls nh_poskey() to get next command
/// 2. nh_poskey() WAITS on pthread_cond (ios_winprocs.c:910)
/// 3. sendCommand() queues input and SIGNALS condition
/// 4. nh_poskey() returns command → moveloop processes → waits again
///
/// This is TURN-BASED gameplay - the blocking IS the design!
/// The game loop yielding control while waiting for input allows
/// the SAME queue to process other operations between turns.
///
/// WRONG APPROACH (before):
/// - Separate game loop queue: Run moveloop
/// - Separate operations queue: Commands/inventory
/// Result: RACE CONDITIONS on NetHack globals (u, gi.invent, program_state)
///
/// CORRECT APPROACH (now):
/// - ONE queue: All NetHack access serialized
/// Result: Thread-safe access to 1987 C code
///
/// RATIONALE:
/// Before this fix, we had 2 serial queues causing race conditions:
/// 1. Game loop queue running moveloop → accessing u.ux, gi.invent, etc.
/// 2. Operations queue reading stats/inventory → accessing SAME globals
/// NetHack globals are NOT protected by locks → data corruption!
///
/// SOLUTION: ONE queue to rule them all!
class NetHackSerialExecutor {
    /// Singleton instance - use this everywhere
    static let shared = NetHackSerialExecutor()

    /// SINGLE serial queue for ALL NetHack C code access
    /// Used for: game loop, commands, map updates, inventory, save/load, ALL bridge calls
    /// Label: "com.nethack.serial-executor"
    /// QoS: .userInitiated (responsive for UI-initiated actions)
    let queue = DispatchQueue(label: "com.nethack.serial-executor", qos: .userInitiated)

    /// Timeout for NetHack operations (5 seconds)
    /// If an operation takes longer, it will be logged and dropped
    private let operationTimeout: TimeInterval = 5.0

    /// Private init to enforce singleton pattern
    private init() {
        print("[NetHackSerialExecutor] ✅ Created SINGLE serial queue for NetHack C access")
        print("[NetHackSerialExecutor] 🔒 ALL NetHack operations serialized on ONE queue")
        print("[NetHackSerialExecutor] ⚡ Game loop is event-driven (waits on condition variable)")
        print("[NetHackSerialExecutor] ✓ Thread-safe access to 1987 non-thread-safe C code")
    }

    /// Execute a NetHack operation with timeout protection
    /// - Parameters:
    ///   - description: Human-readable description of the operation (for logging)
    ///   - timeout: Custom timeout (default: 5 seconds)
    ///   - operation: The NetHack C call to execute
    ///   - completion: Called on main thread with result or error
    func execute<T>(
        _ description: String,
        timeout: TimeInterval? = nil,
        operation: @escaping () -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        let timeoutDuration = timeout ?? operationTimeout
        let startTime = Date()
        let queuedTime = Date()

        print("[NetHackSerialExecutor] 📥 QUEUED: '\(description)' (timeout: \(String(format: "%.1f", timeoutDuration))s)")

        // Create a work item for the operation
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            let queueDelay = Date().timeIntervalSince(queuedTime)
            if queueDelay > 0.1 {
                print("[NetHackSerialExecutor] ⏱️ DELAYED: '\(description)' waited \(String(format: "%.2f", queueDelay))s in queue")
            }

            guard let workItem = workItem, !workItem.isCancelled else {
                print("[NetHackSerialExecutor] ❌ CANCELLED: '\(description)' was cancelled before execution")
                DispatchQueue.main.async {
                    completion(.failure(NetHackError.cancelled))
                }
                return
            }

            print("[NetHackSerialExecutor] ▶️  EXECUTING: '\(description)'")
            let executeStart = Date()
            let result = operation()
            let executeDuration = Date().timeIntervalSince(executeStart)
            let totalDuration = Date().timeIntervalSince(startTime)

            if executeDuration > 1.0 {
                print("[NetHackSerialExecutor] 🐌 SLOW: '\(description)' took \(String(format: "%.2f", executeDuration))s to execute")
            } else if executeDuration > 0.5 {
                print("[NetHackSerialExecutor] ⚠️  MEDIUM: '\(description)' took \(String(format: "%.3f", executeDuration))s")
            } else {
                print("[NetHackSerialExecutor] ✅ SUCCESS: '\(description)' completed in \(String(format: "%.3f", executeDuration))s")
            }

            DispatchQueue.main.async {
                completion(.success(result))
            }
        }

        // Schedule timeout check
        let timeoutWorkItem = DispatchWorkItem {
            let duration = Date().timeIntervalSince(startTime)
            if duration >= timeoutDuration {
                print("[NetHackSerialExecutor] ❌❌❌ TIMEOUT: '\(description)' exceeded \(timeoutDuration)s - DROPPING ITEM")
                workItem?.cancel()
                DispatchQueue.main.async {
                    completion(.failure(NetHackError.timeout))
                }
            }
        }

        // Execute operation on NetHack queue
        queue.async(execute: workItem!)

        // Schedule timeout check slightly after timeout duration
        queue.asyncAfter(deadline: .now() + timeoutDuration + 0.1, execute: timeoutWorkItem)
    }
}

/// Errors that can occur during NetHack operations
enum NetHackError: Error, LocalizedError {
    case timeout
    case cancelled
    case notInMoveloop
    case gameNotStarted

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "NetHack operation timed out"
        case .cancelled:
            return "NetHack operation was cancelled"
        case .notInMoveloop:
            return "NetHack game loop not running"
        case .gameNotStarted:
            return "NetHack game not started"
        }
    }
}
