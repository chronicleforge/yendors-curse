import Foundation

/// Per-character preferences stored in preferences.json alongside savegame
///
/// Lives in: /Documents/NetHack/characters/{sanitizedName}/preferences.json
/// Auto-syncs via iCloud with the character directory
struct CharacterPreferences: Codable {
    /// Starred action IDs per group (up to 4 per group)
    /// Key: CommandGroup.rawValue (e.g., "Common", "Combat", "Equipment")
    /// Value: Array of action IDs that are starred (shown first in that group)
    var starredActionIDsByGroup: [String: [String]]

    /// Schema version for future migrations
    var version: Int

    /// Last modification timestamp
    var lastModified: Date

    // MARK: - Initialization

    init(starredActionIDsByGroup: [String: [String]] = [:], version: Int = 3, lastModified: Date = Date()) {
        self.starredActionIDsByGroup = starredActionIDsByGroup
        self.version = version
        self.lastModified = lastModified
    }

    // MARK: - Starred Actions API

    /// Get starred action IDs for a specific group
    func starredActions(for groupID: String) -> [String] {
        starredActionIDsByGroup[groupID] ?? []
    }

    /// Check if an action is starred in a group
    func isStarred(actionID: String, in groupID: String) -> Bool {
        starredActionIDsByGroup[groupID]?.contains(actionID) ?? false
    }

    /// Add a starred action to a group (max 4)
    mutating func addStar(actionID: String, to groupID: String) {
        var stars = starredActionIDsByGroup[groupID] ?? []
        guard !stars.contains(actionID) else { return }
        guard stars.count < 4 else {
            // Replace oldest star
            stars.removeFirst()
            stars.append(actionID)
            starredActionIDsByGroup[groupID] = stars
            return
        }
        stars.append(actionID)
        starredActionIDsByGroup[groupID] = stars
    }

    /// Remove a starred action from a group
    mutating func removeStar(actionID: String, from groupID: String) {
        starredActionIDsByGroup[groupID]?.removeAll { $0 == actionID }
    }

    // MARK: - Role-based Defaults

    /// Create default starred actions based on character role
    static func defaultsForRole(_ role: String) -> [String: [String]] {
        var defaults: [String: [String]] = [:]

        // Common group: Same for all roles (most frequent actions)
        defaults["Common"] = [",", ":", "o", "x"]  // Pickup, Look, Open, Swap Weapons

        // Role-specific starred actions
        switch role.lowercased() {
        case "wizard":
            defaults["Magic"] = ["Z", "z", "r", "#enhance"]  // Cast, Zap, Read, Enhance
            defaults["Items"] = ["r", "q", "e", "a"]         // Read, Quaff, Eat, Apply
        case "healer", "monk", "priest", "priestess":
            defaults["Magic"] = ["Z", "#pray", "z", "#turn"] // Cast, Pray, Zap, Turn
        case "samurai", "knight", "valkyrie", "barbarian":
            defaults["Equipment"] = ["x", "w", "W", "Q"]     // Swap, Wield, Wear, Quiver
            defaults["Combat"] = ["F", "t", "f", "C-d"]      // Attack, Throw, Fire, Kick
        case "ranger", "rogue":
            defaults["Combat"] = ["f", "t", "F", "C-d"]      // Fire, Throw, Attack, Kick
            defaults["More"] = ["#untrap", "s", "o", "c"]    // Untrap, Search, Open, Close
        case "archeologist":
            defaults["Items"] = ["a", "r", "e", "q"]         // Apply, Read, Eat, Quaff
            defaults["More"] = ["#untrap", "s", "o", "c"]    // Untrap, Search, Open, Close
        case "tourist":
            defaults["Items"] = [",", "i", "e", "q"]         // Pickup, Inventory, Eat, Quaff
        default:
            break
        }

        return defaults
    }

    // MARK: - File Operations

    /// Load preferences for a character
    /// Returns nil if file doesn't exist or can't be parsed
    static func load(for characterName: String) -> CharacterPreferences? {
        let prefsPath = Self.preferencesPath(for: characterName)

        guard FileManager.default.fileExists(atPath: prefsPath.path) else {
            print("[CharacterPreferences] No preferences found for '\(characterName)'")
            return nil
        }

        guard let jsonData = try? Data(contentsOf: prefsPath) else {
            print("[CharacterPreferences] Failed to read preferences file")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let preferences = try? decoder.decode(CharacterPreferences.self, from: jsonData) else {
            print("[CharacterPreferences] Failed to parse preferences JSON")
            return nil
        }

        print("[CharacterPreferences] Loaded preferences for '\(characterName)' (\(preferences.starredActionIDsByGroup.count) groups with stars)")
        return preferences
    }

    /// Save preferences for a character
    func save(for characterName: String) -> Bool {
        let prefsPath = Self.preferencesPath(for: characterName)

        // Ensure the character directory exists
        let characterDir = prefsPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: characterDir, withIntermediateDirectories: true)
        } catch {
            print("[CharacterPreferences] Failed to create directory: \(error)")
            return false
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(self) else {
            print("[CharacterPreferences] Failed to encode preferences")
            return false
        }

        do {
            try jsonData.write(to: prefsPath)
            print("[CharacterPreferences] Saved preferences for '\(characterName)' (\(starredActionIDsByGroup.count) groups with stars)")
            return true
        } catch {
            print("[CharacterPreferences] Failed to write preferences: \(error)")
            return false
        }
    }

    /// Get the preferences file path for a character
    private static func preferencesPath(for characterName: String) -> URL {
        let characterDir = CharacterSanitization.getCharacterDirectoryURL(characterName)
        return characterDir.appendingPathComponent("preferences.json")
    }
}
