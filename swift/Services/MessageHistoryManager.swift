import Foundation
import Combine

// MARK: - Message History Manager

/// Singleton manager for storing game message history.
/// Persists messages across view updates for fullscreen log display.
@MainActor
final class MessageHistoryManager: ObservableObject {
    static let shared = MessageHistoryManager()

    @Published private(set) var messages: [GameMessage] = []

    private let maxMessages = 500

    private init() {}

    // MARK: - Public API

    func addMessage(_ message: GameMessage) {
        messages.append(message)

        // Trim oldest messages if over limit
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    func clearHistory() {
        messages.removeAll()
    }

    /// Get messages for a specific turn range
    func messages(from startTurn: Int, to endTurn: Int) -> [GameMessage] {
        messages.filter { $0.turnNumber >= startTurn && $0.turnNumber <= endTurn }
    }

    /// Get last N messages
    func lastMessages(_ count: Int) -> [GameMessage] {
        Array(messages.suffix(count))
    }
}
