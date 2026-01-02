import Foundation
import Combine
import SwiftUI  // For Color in AutopickupCategory

/// Manages user preferences with iCloud sync support
/// Uses NSUbiquitousKeyValueStore for automatic cloud sync + UserDefaults as local fallback
@MainActor
class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()

    // MARK: - Storage Backends

    /// iCloud Key-Value Store (auto-syncs across devices)
    private let cloudStore = NSUbiquitousKeyValueStore.default

    /// Local UserDefaults (fallback + cache)
    private let localStore = UserDefaults.standard

    // MARK: - Published State

    @Published private(set) var iCloudAvailable: Bool = false
    @Published private(set) var syncStatus: SyncStatus = .idle

    // MARK: - Sync Status

    enum SyncStatus {
        case idle
        case syncing
        case synced
        case offline
    }

    // MARK: - Preference Keys

    enum Key {
        // Action Bar Preferences
        static let pinnedActionIDs = "com.nethack.actions.pinned"
        static let actionUsageStats = "com.nethack.actions.usage"
        static let recentActions = "com.nethack.actions.recent"

        // Debug Mode
        static let debugModeEnabled = "com.nethack.debug.wizardMode"

        // Autopickup Preferences
        static let autopickupEnabled = "com.nethack.autopickup.enabled"
        static let autopickupCategories = "com.nethack.autopickup.categories"

        // Migration Flags
        static let migrationCompleted = "com.nethack.migration.v1.completed"
        static let migrationV2ToolsDisabled = "com.nethack.migration.v2.toolsDisabled"

        // Legacy Keys (for migration)
        static let legacyPinnedIDs = "pinnedActionIDs"
        static let legacyUsageStats = "NetHackActionUsageStats"
        static let legacyRecentActions = "NetHackRecentActions"
    }

    // MARK: - Initialization

    private init() {
        checkCloudAvailability()
        setupCloudSync()
        migrateExistingDataIfNeeded()
    }

    // MARK: - Cloud Availability

    private func checkCloudAvailability() {
        // Check if user is logged into iCloud
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil

        guard iCloudAvailable else {
            print("[UserPrefs] ⚠️ iCloud not available - using local storage only")
            syncStatus = .offline
            return
        }

        print("[UserPrefs] ✅ iCloud available")
    }

    // MARK: - Generic Get/Set (Codable)

    /// Get value from storage (iCloud first, then local fallback)
    func get<T: Codable>(_ key: String, type: T.Type) -> T? {
        // Try iCloud first
        if iCloudAvailable, let data = cloudStore.data(forKey: key) {
            guard let value = try? JSONDecoder().decode(T.self, from: data) else {
                print("[UserPrefs] ⚠️ Failed to decode iCloud value for key: \(key)")
                return nil
            }
            return value
        }

        // Fallback to local
        guard let data = localStore.data(forKey: key) else {
            return nil
        }

        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            print("[UserPrefs] ⚠️ Failed to decode local value for key: \(key)")
            return nil
        }

        return value
    }

    /// Set value in storage (dual-write: local + iCloud)
    func set<T: Codable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            print("[UserPrefs] ❌ Failed to encode value for key: \(key)")
            return
        }

        // Write to local (always)
        localStore.set(data, forKey: key)

        // Write to iCloud (if available)
        if iCloudAvailable {
            cloudStore.set(data, forKey: key)
            syncStatus = .syncing

            // Trigger sync
            let synced = cloudStore.synchronize()
            syncStatus = synced ? .synced : .offline

            if synced {
                print("[UserPrefs] ☁️ Synced to iCloud: \(key)")
            } else {
                print("[UserPrefs] ⚠️ iCloud sync failed for key: \(key)")
            }
        }
    }

    /// Remove value from storage
    func remove(forKey key: String) {
        localStore.removeObject(forKey: key)

        if iCloudAvailable {
            cloudStore.removeObject(forKey: key)
            cloudStore.synchronize()
        }
    }

    // MARK: - Pinned Actions

    func getPinnedActionIDs() -> Set<String> {
        guard let ids = get(Key.pinnedActionIDs, type: [String].self) else {
            return []
        }
        return Set(ids)
    }

    func setPinnedActionIDs(_ ids: Set<String>) {
        set(Array(ids), forKey: Key.pinnedActionIDs)
    }

    // MARK: - Usage Stats

    func getUsageStats() -> [String: ActionUsageStats] {
        return get(Key.actionUsageStats, type: [String: ActionUsageStats].self) ?? [:]
    }

    func setUsageStats(_ stats: [String: ActionUsageStats]) {
        set(stats, forKey: Key.actionUsageStats)
    }

    // MARK: - Recent Actions

    func getRecentActions() -> [NetHackAction] {
        return get(Key.recentActions, type: [NetHackAction].self) ?? []
    }

    func setRecentActions(_ actions: [NetHackAction]) {
        set(actions, forKey: Key.recentActions)
    }

    // MARK: - Debug Mode (Wizard Mode)

    func isDebugModeEnabled() -> Bool {
        return get(Key.debugModeEnabled, type: Bool.self) ?? false
    }

    func setDebugModeEnabled(_ enabled: Bool) {
        set(enabled, forKey: Key.debugModeEnabled)
        print("[UserPrefs] 🧙 Debug mode: \(enabled ? "ENABLED" : "disabled")")
    }

    // MARK: - Autopickup Preferences

    /// Default autopickup categories: Gold, Amulets, Scrolls, Potions, Wands, Rings, Tools, Spellbooks
    /// Symbols: $ " ? ! / = ( +
    static let defaultAutopickupCategories: [AutopickupCategory] = [
        AutopickupCategory(symbol: "$", name: "Gold", enabled: true),
        AutopickupCategory(symbol: "\"", name: "Amulets", enabled: true),
        AutopickupCategory(symbol: "?", name: "Scrolls", enabled: true),
        AutopickupCategory(symbol: "!", name: "Potions", enabled: true),
        AutopickupCategory(symbol: "/", name: "Wands", enabled: true),
        AutopickupCategory(symbol: "=", name: "Rings", enabled: true),
        AutopickupCategory(symbol: "(", name: "Tools", enabled: false),  // Off: includes chests
        AutopickupCategory(symbol: "+", name: "Spellbooks", enabled: true),
        AutopickupCategory(symbol: ")", name: "Weapons", enabled: false),
        AutopickupCategory(symbol: "[", name: "Armor", enabled: false),
        AutopickupCategory(symbol: "%", name: "Food", enabled: false),
        AutopickupCategory(symbol: "*", name: "Gems", enabled: false),
    ]

    func isAutopickupEnabled() -> Bool {
        // Default to TRUE (unlike NetHack's default of OFF)
        return get(Key.autopickupEnabled, type: Bool.self) ?? true
    }

    func setAutopickupEnabled(_ enabled: Bool) {
        set(enabled, forKey: Key.autopickupEnabled)
        print("[UserPrefs] 📦 Autopickup: \(enabled ? "ENABLED" : "disabled")")
    }

    func getAutopickupCategories() -> [AutopickupCategory] {
        return get(Key.autopickupCategories, type: [AutopickupCategory].self)
            ?? Self.defaultAutopickupCategories
    }

    func setAutopickupCategories(_ categories: [AutopickupCategory]) {
        set(categories, forKey: Key.autopickupCategories)
        let enabled = categories.filter { $0.enabled }.map { $0.symbol }.joined()
        print("[UserPrefs] 📦 Autopickup categories: \(enabled)")
    }

    /// Get pickup_types string for C bridge (e.g., "$\"?!/=(+")
    func getAutopickupTypesString() -> String {
        let categories = getAutopickupCategories()
        return categories.filter { $0.enabled }.map { $0.symbol }.joined()
    }

    // MARK: - Cloud Sync Setup

    private func setupCloudSync() {
        guard iCloudAvailable else { return }

        // Listen for external iCloud changes (from other devices)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudDataDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )

        // Trigger initial sync
        cloudStore.synchronize()
    }

    @objc private func cloudDataDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        // Determine change reason
        let reason: String
        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange:
            reason = "Server Change (from other device)"
        case NSUbiquitousKeyValueStoreInitialSyncChange:
            reason = "Initial Sync"
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            reason = "Quota Violation"
            print("[UserPrefs] ⚠️ iCloud quota exceeded!")
        case NSUbiquitousKeyValueStoreAccountChange:
            reason = "Account Change"
            checkCloudAvailability() // Re-check availability
        default:
            reason = "Unknown (\(changeReason))"
        }

        print("[UserPrefs] ☁️ iCloud data changed: \(reason)")

        // Get changed keys
        if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            print("[UserPrefs] 📝 Changed keys: \(changedKeys.joined(separator: ", "))")

            // Notify observers (triggers @Published updates)
            // This will cause ActionUsageTracker to reload
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .userPreferencesDidChange,
                    object: self,
                    userInfo: ["changedKeys": changedKeys]
                )
            }
        }
    }

    // MARK: - Migration

    private func migrateExistingDataIfNeeded() {
        // Check if migration already completed
        guard !localStore.bool(forKey: Key.migrationCompleted) else {
            print("[UserPrefs] ℹ️ Migration already completed, skipping")
            return
        }

        print("[UserPrefs] 🔄 Starting migration of legacy data...")

        var migrated = false

        // Migrate Pinned Actions
        if let legacyData = localStore.data(forKey: Key.legacyPinnedIDs),
           let legacyIDs = try? JSONDecoder().decode([String].self, from: legacyData) {
            print("[UserPrefs] 📦 Migrating \(legacyIDs.count) pinned actions")
            setPinnedActionIDs(Set(legacyIDs))
            migrated = true
        }

        // Migrate Usage Stats
        if let legacyData = localStore.data(forKey: Key.legacyUsageStats),
           let legacyStats = try? JSONDecoder().decode([String: ActionUsageStats].self, from: legacyData) {
            print("[UserPrefs] 📦 Migrating \(legacyStats.count) usage stats")
            setUsageStats(legacyStats)
            migrated = true
        }

        // Migrate Recent Actions
        if let legacyData = localStore.data(forKey: Key.legacyRecentActions),
           let legacyRecent = try? JSONDecoder().decode([NetHackAction].self, from: legacyData) {
            print("[UserPrefs] 📦 Migrating \(legacyRecent.count) recent actions")
            setRecentActions(legacyRecent)
            migrated = true
        }

        // Mark migration complete
        localStore.set(true, forKey: Key.migrationCompleted)

        if migrated {
            print("[UserPrefs] ✅ Migration completed successfully")
        } else {
            print("[UserPrefs] ℹ️ No legacy data found to migrate")
        }

        // V2 Migration: Disable Tools autopickup
        migrateV2DisableToolsAutopickup()
    }

    /// V2 Migration: Disable Tools in autopickup (chests shouldn't be auto-picked)
    /// Now runs EVERY time to ensure Tools stays disabled (previous migration might have failed)
    private func migrateV2DisableToolsAutopickup() {
        var categories = getAutopickupCategories()
        if let idx = categories.firstIndex(where: { $0.symbol == "(" }) {
            if categories[idx].enabled {
                categories[idx].enabled = false
                setAutopickupCategories(categories)
                print("[UserPrefs] 🔄 V2: Disabled Tools autopickup")
            } else {
                print("[UserPrefs] ✅ Tools autopickup already disabled")
            }
        } else {
            print("[UserPrefs] ⚠️ Tools category not found in autopickup categories!")
        }
    }

    // MARK: - Debug

    /// Reset all preferences (for debugging)
    func resetAll() {
        print("[UserPrefs] ⚠️ Resetting all preferences")

        // Remove from local
        localStore.removeObject(forKey: Key.pinnedActionIDs)
        localStore.removeObject(forKey: Key.actionUsageStats)
        localStore.removeObject(forKey: Key.recentActions)
        localStore.removeObject(forKey: Key.migrationCompleted)

        // Remove from iCloud
        if iCloudAvailable {
            cloudStore.removeObject(forKey: Key.pinnedActionIDs)
            cloudStore.removeObject(forKey: Key.actionUsageStats)
            cloudStore.removeObject(forKey: Key.recentActions)
            cloudStore.synchronize()
        }
    }

    /// Get debug info
    func debugInfo() -> String {
        var info = "=== UserPreferencesManager ===\n\n"
        info += "iCloud Available: \(iCloudAvailable)\n"
        info += "Sync Status: \(syncStatus)\n\n"

        info += "Pinned Actions: \(getPinnedActionIDs().count)\n"
        info += "Usage Stats: \(getUsageStats().count)\n"
        info += "Recent Actions: \(getRecentActions().count)\n"

        return info
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let userPreferencesDidChange = Notification.Name("userPreferencesDidChange")
}

// MARK: - Autopickup Category Model

/// Represents an item category for autopickup settings
struct AutopickupCategory: Codable, Identifiable, Equatable {
    let symbol: String      // NetHack object class symbol (e.g., "$", "?", "!")
    let name: String        // Human-readable name (e.g., "Gold", "Scrolls")
    var enabled: Bool       // Whether to autopickup this category

    var id: String { symbol }

    /// Icon for this category (SF Symbol)
    var icon: String {
        switch symbol {
        case "$": return "dollarsign.circle.fill"
        case "\"": return "lanyardcard.fill"
        case "?": return "scroll.fill"
        case "!": return "flask.fill"
        case "/": return "wand.and.stars"
        case "=": return "circle.circle.fill"
        case "(": return "wrench.and.screwdriver.fill"
        case "+": return "book.closed.fill"
        case ")": return "shield.lefthalf.filled"
        case "[": return "tshirt.fill"
        case "%": return "carrot.fill"
        case "*": return "diamond.fill"
        default: return "questionmark.circle"
        }
    }

    /// Color for this category
    var color: Color {
        switch symbol {
        case "$": return .yellow
        case "\"": return .orange
        case "?": return .cyan
        case "!": return .pink
        case "/": return .purple
        case "=": return .blue
        case "(": return .brown
        case "+": return .indigo
        case ")": return .gray
        case "[": return .gray
        case "%": return .green
        case "*": return .mint
        default: return .gray
        }
    }
}
