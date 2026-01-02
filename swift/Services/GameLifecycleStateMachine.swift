import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when state machine watchdog times out (object: GameLifecycleState that timed out)
    static let gameStateTimeout = Notification.Name("GameStateTimeout")
}

// MARK: - Game Lifecycle State

/// Possible states of the game lifecycle
enum GameLifecycleState: String, Sendable {
    case idle       // Home screen, no game running
    case loading    // Game is being loaded/created
    case playing    // Game is running
    case exiting    // Game is being shut down
    case error      // Error occurred
}

// MARK: - Game Action

/// Actions that can trigger state transitions
enum GameAction: Sendable {
    case continueGame(String)   // Continue saved character
    case newGame(String)        // Start new game with name
    case gameStarted            // Game successfully started
    case exitGame               // User requested exit
    case gameExited             // Game successfully exited
    case loadFailed(String)     // Load failed with error
    case reset                  // Force reset to idle
}

// MARK: - Transition Result

/// Result of a state transition request
enum TransitionResult: Sendable {
    case proceed        // Continue with action
    case exitFirst      // Must exit current game first
    case failed         // Action failed
    case invalid        // Invalid transition for current state
}

// MARK: - State Machine

/// Single source of truth for game lifecycle state
///
/// Usage:
/// ```
/// let result = stateMachine.request(.continueGame("Tethran"))
/// switch result {
/// case .proceed: // Start loading
/// case .exitFirst: // Exit current game, then retry
/// case .failed, .invalid: // Handle error
/// }
/// ```
@Observable
final class GameLifecycleStateMachine: @unchecked Sendable {

    // MARK: - State

    private(set) var state: GameLifecycleState = .idle
    private var pendingAction: GameAction?
    private let lock = NSLock()

    // MARK: - Watchdog Timer

    /// Task that monitors for stuck states
    private var watchdogTask: Task<Void, Never>?

    /// Timeout for loading state (dylib init, save load)
    private let loadingTimeout: TimeInterval = 30

    /// Timeout for exiting state (save, cleanup)
    private let exitingTimeout: TimeInterval = 10

    // MARK: - Convenience Properties

    var canStartGame: Bool { state == .idle }
    var isPlaying: Bool { state == .playing }
    var isLoading: Bool { state == .loading }
    var hasError: Bool { state == .error }

    // MARK: - Singleton

    static let shared = GameLifecycleStateMachine()

    private init() {
        print("[StateMachine] Initialized in state: \(state)")
    }

    deinit {
        watchdogTask?.cancel()
    }

    // MARK: - State Transitions

    /// Request a state transition
    /// - Parameter action: The action to perform
    /// - Returns: Result indicating how to proceed
    func request(_ action: GameAction) -> TransitionResult {
        lock.lock()
        defer { lock.unlock() }

        let oldState = state
        let result: TransitionResult

        switch (state, action) {
        // IDLE → LOADING (new game or continue)
        case (.idle, .continueGame), (.idle, .newGame):
            state = .loading
            result = .proceed

        // PLAYING → EXITING (must exit first before new game)
        case (.playing, .continueGame), (.playing, .newGame):
            pendingAction = action
            state = .exiting
            result = .exitFirst

        // LOADING → PLAYING (game started successfully)
        case (.loading, .gameStarted):
            state = .playing
            result = .proceed

        // LOADING → ERROR (load failed)
        case (.loading, .loadFailed):
            state = .error
            result = .failed

        // PLAYING → EXITING (user requested exit)
        case (.playing, .exitGame):
            state = .exiting
            result = .proceed

        // EXITING → IDLE (game exited, check for pending action)
        case (.exiting, .gameExited):
            state = .idle
            if let pending = pendingAction {
                pendingAction = nil
                print("[StateMachine] Executing pending action after exit")
                return request(pending)  // Recursive retry
            }
            result = .proceed

        // ANY → IDLE (force reset)
        case (_, .reset):
            state = .idle
            pendingAction = nil
            result = .proceed

        // ERROR → LOADING (retry from error)
        case (.error, .continueGame), (.error, .newGame):
            state = .loading
            result = .proceed

        // LOADING → LOADING (retry/restart while loading)
        // This handles edge case where load fails silently
        case (.loading, .continueGame), (.loading, .newGame):
            print("[StateMachine] Restarting from loading state")
            result = .proceed

        default:
            print("[StateMachine] Invalid transition: \(state) + \(action)")
            result = .invalid
        }

        if oldState != state {
            print("[StateMachine] \(oldState) → \(state) (action: \(action))")
            // Update watchdog for new state (start for loading/exiting, cancel for others)
            updateWatchdog(for: state)
        }

        return result
    }

    /// Force reset to idle state (use sparingly)
    func forceReset() {
        lock.lock()
        defer { lock.unlock() }

        print("[StateMachine] Force reset from \(state) to idle")
        state = .idle
        pendingAction = nil
        cancelWatchdog()
    }

    // MARK: - Watchdog Timer

    /// Start watchdog timer for time-limited states (loading, exiting)
    /// If state doesn't transition within timeout, forces reset to prevent stuck UI
    private func startWatchdog() {
        // Cancel any existing watchdog
        watchdogTask?.cancel()

        let timeout = state == .loading ? loadingTimeout : exitingTimeout
        let currentState = state

        print("[StateMachine] ⏱️ Watchdog started for \(currentState) (timeout: \(Int(timeout))s)")

        watchdogTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                guard let self = self else { return }
                guard !Task.isCancelled else { return }

                // Check if still in the same state
                self.lock.lock()
                let stillStuck = self.state == currentState
                self.lock.unlock()

                if stillStuck {
                    print("[StateMachine] ⚠️ WATCHDOG TIMEOUT: \(currentState) after \(Int(timeout))s - forcing reset")

                    // Force reset
                    _ = self.request(.reset)

                    // Notify observers
                    NotificationCenter.default.post(
                        name: .gameStateTimeout,
                        object: currentState
                    )
                }
            } catch {
                // Task was cancelled - this is normal
            }
        }
    }

    /// Cancel the watchdog timer (called when state transitions successfully)
    private func cancelWatchdog() {
        if watchdogTask != nil {
            print("[StateMachine] ⏱️ Watchdog cancelled")
            watchdogTask?.cancel()
            watchdogTask = nil
        }
    }

    /// Manage watchdog based on new state
    private func updateWatchdog(for newState: GameLifecycleState) {
        switch newState {
        case .loading, .exiting:
            startWatchdog()
        case .idle, .playing, .error:
            cancelWatchdog()
        }
    }
}
