import Foundation
import SwiftUI

// MARK: - Sync Status

/// Sync status derived from timestamps - single source of truth
enum CharacterSyncStatus: String, Codable {
    case localOnly           // Never synced, created locally (syncedAt == nil, downloadedAt == nil)
    case pendingUpload       // Local changes not yet uploaded (updatedAt > syncedAt)
    case syncing             // Upload/download in progress (transient UI state)
    case synced              // syncedAt >= updatedAt
    case downloadedNotSynced // Downloaded but modified locally (downloadedAt != nil, syncedAt == nil)
    case cloudOnly           // Only exists in iCloud, not downloaded locally (= old "downloadable")
    case conflict            // Conflict detected (for future use)

    var icon: String {
        switch self {
        case .localOnly: return "iphone"
        case .pendingUpload: return "arrow.up.circle"
        case .syncing: return "icloud.and.arrow.up"
        case .synced: return "checkmark.icloud"
        case .downloadedNotSynced: return "arrow.up.circle.fill"
        case .cloudOnly: return "icloud.and.arrow.down"
        case .conflict: return "exclamationmark.icloud"
        }
    }

    var displayText: String {
        switch self {
        case .localOnly: return "Local"
        case .pendingUpload: return "Pending"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .downloadedNotSynced: return "Modified"
        case .cloudOnly: return "In iCloud"
        case .conflict: return "Conflict"
        }
    }

    var color: Color {
        switch self {
        case .localOnly: return .gray
        case .pendingUpload: return .orange
        case .syncing: return .blue
        case .synced: return .green
        case .downloadedNotSynced: return .orange
        case .cloudOnly: return .blue
        case .conflict: return .red
        }
    }

    // Alias for backwards compatibility with old enum
    var label: String { displayText }

    /// Short label for compact badge display
    var shortLabel: String {
        switch self {
        case .localOnly: return ""  // Icon only
        case .pendingUpload: return "Pending"
        case .syncing: return ""  // Animated icon
        case .synced: return ""  // Icon only
        case .downloadedNotSynced: return "Modified"
        case .cloudOnly: return ""  // Icon only - cloud download icon is self-explanatory
        case .conflict: return "Conflict"
        }
    }

    /// Whether this status requires user action (shows text label)
    var needsAction: Bool {
        switch self {
        case .pendingUpload, .downloadedNotSynced, .conflict:
            return true
        case .localOnly, .syncing, .synced, .cloudOnly:
            return false  // cloudOnly uses icon-only badge
        }
    }
}

// MARK: - Character Metadata

/// Character metadata loaded from metadata.json
///
/// This matches the structure created by generate_metadata() in ios_character_save.c
/// Supports both legacy (lastSaved only) and new format (with timestamps)
struct CharacterMetadata: Codable, Identifiable {
    var id: String { characterName }  // Use characterName as unique identifier

    let characterName: String
    let role: String
    let race: String
    let gender: String
    let alignment: String
    let level: Int
    let hp: Int
    let hpmax: Int
    let turns: Int
    let dungeonLevel: Int

    // Legacy field - kept for backward compatibility
    let lastSaved: String

    // NEW: Timestamp fields (ISO 8601) - optional for migration
    var createdAt: Date?       // First creation
    var updatedAt: Date?       // Last local save
    var syncedAt: Date?        // Last successful iCloud upload (nil = never synced)
    var downloadedAt: Date?    // When downloaded from cloud (nil = created locally)

    // MARK: - Computed Sync Status

    /// Derive sync status from timestamps - single source of truth
    var syncStatus: CharacterSyncStatus {
        // Cloud-only placeholder
        if role == "Unknown" && level == 0 {
            return .cloudOnly
        }

        // Never synced
        guard let syncedAt = syncedAt else {
            return downloadedAt != nil ? .downloadedNotSynced : .localOnly
        }

        // Compare timestamps
        let effectiveUpdatedAt = updatedAt ?? Self.parseISO8601(lastSaved) ?? Date.distantPast
        return syncedAt >= effectiveUpdatedAt ? .synced : .pendingUpload
    }

    /// Parse ISO 8601 date string (legacy lastSaved format)
    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case characterName = "character_name"
        case role
        case race
        case gender
        case alignment
        case level
        case hp
        case hpmax
        case turns
        case dungeonLevel = "dungeon_level"
        case lastSaved = "last_saved"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
        case downloadedAt = "downloaded_at"
    }

    /// Load metadata from JSON file for a character
    /// Returns: CharacterMetadata if successful, nil otherwise
    static func load(for characterName: String) -> CharacterMetadata? {
        // Get metadata path using SAME sanitization as C code
        let characterDir = CharacterSanitization.getCharacterDirectory(characterName)
        let metadataPath = "\(characterDir)/metadata.json"

        // Check if file exists
        guard FileManager.default.fileExists(atPath: metadataPath) else {
            print("[CharacterMetadata] No metadata found for '\(characterName)' at: \(metadataPath)")
            return nil
        }

        // Read file
        guard let jsonData = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)) else {
            print("[CharacterMetadata] Failed to read metadata file")
            return nil
        }

        // Parse JSON with ISO8601 date support
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode(CharacterMetadata.self, from: jsonData) else {
            print("[CharacterMetadata] Failed to parse metadata JSON")
            return nil
        }

        print("[CharacterMetadata] ✅ Loaded metadata for '\(characterName)': Level \(metadata.level) \(metadata.race) \(metadata.role), syncStatus=\(metadata.syncStatus)")
        return metadata
    }

    // MARK: - Timestamp Updates

    /// Update syncedAt timestamp after successful iCloud upload
    /// Swift-only - C bridge does NOT write this field
    static func updateSyncedAt(_ characterName: String, to date: Date = Date()) {
        guard var metadata = load(for: characterName) else {
            print("[CharacterMetadata] Cannot update syncedAt - failed to load metadata for '\(characterName)'")
            return
        }

        metadata.syncedAt = date
        save(metadata, for: characterName)
        print("[CharacterMetadata] ✅ Updated syncedAt for '\(characterName)' to \(date)")

        // Notify UI to refresh sync status badges
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .characterSyncStatusChanged, object: characterName)
        }
    }

    /// Update downloadedAt timestamp after downloading from iCloud
    static func updateDownloadedAt(_ characterName: String, to date: Date = Date()) {
        guard var metadata = load(for: characterName) else {
            print("[CharacterMetadata] Cannot update downloadedAt - failed to load metadata for '\(characterName)'")
            return
        }

        metadata.downloadedAt = date
        save(metadata, for: characterName)
        print("[CharacterMetadata] ✅ Updated downloadedAt for '\(characterName)' to \(date)")
    }

    /// Save metadata back to JSON file
    private static func save(_ metadata: CharacterMetadata, for characterName: String) {
        let characterDir = CharacterSanitization.getCharacterDirectory(characterName)
        let metadataPath = "\(characterDir)/metadata.json"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(metadata) else {
            print("[CharacterMetadata] Failed to encode metadata")
            return
        }

        do {
            try jsonData.write(to: URL(fileURLWithPath: metadataPath))
            print("[CharacterMetadata] Saved metadata to \(metadataPath)")
        } catch {
            print("[CharacterMetadata] Failed to write metadata: \(error)")
        }
    }

    /// Format for display: "Level 5 Human Valkyrie"
    var displayText: String {
        return "Level \(level) \(race) \(role)"
    }

    /// Short format for display: "Lvl 5 • HP 45/60"
    var shortDisplayText: String {
        return "Lvl \(level) • HP \(hp)/\(hpmax)"
    }

    /// Create placeholder metadata for cloud-only characters (not yet downloaded)
    /// Shows minimal info until user taps to download
    static func cloudPlaceholder(characterName: String) -> CharacterMetadata {
        return CharacterMetadata(
            characterName: characterName,
            role: "Unknown",
            race: "Unknown",
            gender: "Unknown",
            alignment: "Unknown",
            level: 0,
            hp: 0,
            hpmax: 0,
            turns: 0,
            dungeonLevel: 0,
            lastSaved: "In iCloud"
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a character's sync status changes (after upload/download completes)
    /// Object: character name (String)
    static let characterSyncStatusChanged = Notification.Name("characterSyncStatusChanged")
}
