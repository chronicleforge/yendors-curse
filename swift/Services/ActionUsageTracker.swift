import Foundation
import Combine

// MARK: - Action Usage Statistics
struct ActionUsageStats: Codable {
    var usageCount: Int
    var lastUsedDate: Date

    init(usageCount: Int = 0, lastUsedDate: Date = Date()) {
        self.usageCount = usageCount
        self.lastUsedDate = lastUsedDate
    }
}

// MARK: - Action Usage Tracker
@MainActor
class ActionUsageTracker: ObservableObject {
    // MARK: - Published State
    @Published private(set) var recentActions: [NetHackAction] = []
    @Published private(set) var sortedCategories: [ActionCategory] = []

    // Computed property for recently used action IDs (for compatibility)
    var recentlyUsed: [String] {
        recentActions.map { $0.id }
    }

    // MARK: - Private State
    private var usageStats: [String: ActionUsageStats] = [:]
    private let maxRecentActions = 5

    // Preferences manager (iCloud + local storage)
    private let preferences = UserPreferencesManager.shared

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Singleton
    static let shared = ActionUsageTracker()

    // MARK: - Initialization
    private init() {
        loadStats()
        loadRecentActions()
        updateSortedCategories()
        observeCloudChanges()
    }

    // MARK: - Usage Tracking

    /// Track action usage
    func trackUsage(of action: NetHackAction) {
        // Update usage stats
        var stats = usageStats[action.id] ?? ActionUsageStats()
        stats.usageCount += 1
        stats.lastUsedDate = Date()
        usageStats[action.id] = stats

        // Update recent actions
        // Remove if already present
        recentActions.removeAll { $0.id == action.id }

        // Add to front
        recentActions.insert(action, at: 0)

        // Keep only maxRecentActions
        if recentActions.count > maxRecentActions {
            recentActions.removeLast()
        }

        // Update sorted categories
        updateSortedCategories()

        // Persist changes
        saveStats()
        saveRecentActions()
    }

    /// Get usage count for an action
    func usageCount(for action: NetHackAction) -> Int {
        usageStats[action.id]?.usageCount ?? 0
    }

    /// Get total usage count for a category
    func categoryUsageCount(for category: ActionCategory) -> Int {
        let actions = NetHackAction.actionsForCategory(category)
        return actions.reduce(0) { sum, action in
            sum + usageCount(for: action)
        }
    }

    /// Get sorted actions within a category (most used first)
    func sortedActions(for category: ActionCategory) -> [NetHackAction] {
        let actions = NetHackAction.actionsForCategory(category)
        return actions.sorted { first, second in
            let firstCount = usageCount(for: first)
            let secondCount = usageCount(for: second)

            guard firstCount != secondCount else {
                // Same usage count - sort by name
                return first.name < second.name
            }

            // Higher usage count first
            return firstCount > secondCount
        }
    }

    // MARK: - Category Ordering

    /// Update sorted category list based on total usage
    private func updateSortedCategories() {
        // Default priority order (used when no usage data)
        let defaultOrder: [ActionCategory] = [
            .combat,
            .movement,
            .equipment,
            .items,
            .magic,
            .world,
            .info,
            .system
        ]

        // Check if we have any usage data
        let hasUsageData = !usageStats.isEmpty

        guard hasUsageData else {
            sortedCategories = defaultOrder
            return
        }

        // Sort categories by total usage
        sortedCategories = ActionCategory.allCases.sorted { first, second in
            let firstCount = categoryUsageCount(for: first)
            let secondCount = categoryUsageCount(for: second)

            guard firstCount != secondCount else {
                // Same usage - use default order
                let firstIndex = defaultOrder.firstIndex(of: first) ?? 999
                let secondIndex = defaultOrder.firstIndex(of: second) ?? 999
                return firstIndex < secondIndex
            }

            // Higher usage count first
            return firstCount > secondCount
        }
    }

    // MARK: - Context-Aware Suggestions

    /// Get suggested actions based on game context
    /// - Note: This is a placeholder for Phase 2 implementation
    func contextSuggestions(gameState: GameState? = nil) -> [NetHackAction] {
        // Phase 2: Implement context-aware suggestions
        // For now, just return recent actions
        return Array(recentActions.prefix(3))
    }

    // MARK: - Reset

    /// Reset all usage statistics
    func resetStats() {
        usageStats.removeAll()
        recentActions.removeAll()
        updateSortedCategories()
        saveStats()
        saveRecentActions()
    }

    /// Reset statistics for a specific action
    func resetStats(for action: NetHackAction) {
        usageStats.removeValue(forKey: action.id)
        recentActions.removeAll { $0.id == action.id }
        updateSortedCategories()
        saveStats()
        saveRecentActions()
    }

    // MARK: - Persistence (via UserPreferencesManager)

    private func saveStats() {
        preferences.setUsageStats(usageStats)
        print("[ActionUsage] ✅ Saved \(usageStats.count) usage stats")
    }

    private func loadStats() {
        usageStats = preferences.getUsageStats()
        print("[ActionUsage] ✅ Loaded \(usageStats.count) usage stats")
    }

    private func saveRecentActions() {
        preferences.setRecentActions(recentActions)
        print("[ActionUsage] ✅ Saved \(recentActions.count) recent actions")
    }

    private func loadRecentActions() {
        recentActions = preferences.getRecentActions()
        print("[ActionUsage] ✅ Loaded \(recentActions.count) recent actions")
    }

    // MARK: - Cloud Sync Observer

    /// Observe cloud changes from other devices
    private func observeCloudChanges() {
        NotificationCenter.default.publisher(for: .userPreferencesDidChange)
            .sink { [weak self] notification in
                guard let self = self else { return }

                // Check if action usage data was changed
                if let changedKeys = notification.userInfo?["changedKeys"] as? [String] {
                    let usageStatsChanged = changedKeys.contains(UserPreferencesManager.Key.actionUsageStats)
                    let recentActionsChanged = changedKeys.contains(UserPreferencesManager.Key.recentActions)

                    if usageStatsChanged || recentActionsChanged {
                        print("[ActionUsage] ☁️ Cloud sync: Action usage data changed on another device")

                        // Reload from preferences (which already has the latest data from iCloud)
                        Task { @MainActor in
                            if usageStatsChanged {
                                self.loadStats()
                            }
                            if recentActionsChanged {
                                self.loadRecentActions()
                            }
                            self.updateSortedCategories()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Debug Info

    /// Get debug information about usage statistics
    func debugInfo() -> String {
        var info = "=== Action Usage Statistics ===\n\n"

        info += "Total tracked actions: \(usageStats.count)\n"
        info += "Recent actions: \(recentActions.count)\n\n"

        info += "Category Usage:\n"
        for category in sortedCategories {
            let count = categoryUsageCount(for: category)
            info += "  \(category.rawValue): \(count)\n"
        }

        info += "\nTop 10 Most Used Actions:\n"
        let topActions = NetHackAction.allActions
            .sorted { usageCount(for: $0) > usageCount(for: $1) }
            .prefix(10)

        for action in topActions {
            let count = usageCount(for: action)
            guard count > 0 else { break }
            info += "  \(action.name) (\(action.command)): \(count)\n"
        }

        info += "\nRecent Actions:\n"
        for action in recentActions {
            info += "  \(action.name) (\(action.command))\n"
        }

        return info
    }
}

// MARK: - Game State (Placeholder for Phase 2)
/// Placeholder for context-aware suggestions
struct GameState {
    var playerHP: Int?
    var hasItemsOnGround: Bool?
    var nearDoor: Bool?
    var inCombat: Bool?
}
