import SwiftUI

// MARK: - Command Group Manager

/// Manages the state of the command group bar:
/// - Which group is expanded
/// - Starred actions per group (persisted per-character)
/// - Action execution
@MainActor
@Observable
final class CommandGroupManager {
    // MARK: - Singleton

    static let shared = CommandGroupManager()

    // MARK: - UI State

    /// Currently expanded group (nil = all collapsed)
    var expandedGroup: CommandGroup?

    /// Last executed action for visual feedback
    var lastExecutedAction: NetHackAction?

    /// Whether full list sheet is shown
    var showFullList: Bool = false

    /// Group for which full list is shown
    var fullListGroup: CommandGroup?

    // MARK: - Starred Actions (Per-Character, Persisted)

    /// Starred action IDs per group - DIRECTLY OBSERVED by @Observable
    /// Key: CommandGroup.rawValue, Value: Array of action IDs
    var starredByGroup: [String: [String]] = [:]

    /// Currently loaded character name
    private var activeCharacterName: String?

    // MARK: - Initialization

    private init() {}

    // MARK: - Character Loading

    /// Load starred actions for a character
    func loadForCharacter(_ characterName: String, role: String) {
        activeCharacterName = characterName

        // Try to load existing preferences
        if let prefs = CharacterPreferences.load(for: characterName) {
            // Migration: v1/v2 had role defaults as stars - clear them
            if prefs.version < 3 {
                print("[CommandGroupManager] Migrating v\(prefs.version) → v3: clearing role defaults")
                starredByGroup = [:]
                persistPreferences()
            } else {
                starredByGroup = prefs.starredActionIDsByGroup
                print("[CommandGroupManager] Loaded stars for '\(characterName)': \(starredByGroup.count) groups")
            }
            return
        }

        // New character - empty stars
        starredByGroup = [:]
        persistPreferences()
        print("[CommandGroupManager] Created empty stars for '\(characterName)'")
    }

    /// Clear character context (returning to menu)
    func clearCharacter() {
        persistPreferences()
        activeCharacterName = nil
        starredByGroup = [:]
        print("[CommandGroupManager] Cleared character")
    }

    // MARK: - Expansion Control

    func toggleExpanded(_ group: CommandGroup) {
        if expandedGroup == group {
            expandedGroup = nil
        } else {
            expandedGroup = group
        }
    }

    func collapse() {
        expandedGroup = nil
    }

    // MARK: - Full List

    func showFullList(for group: CommandGroup) {
        fullListGroup = group
        showFullList = true
        expandedGroup = nil
    }

    func hideFullList() {
        showFullList = false
        fullListGroup = nil
    }

    // MARK: - Starred Actions API

    /// Check if an action is starred in a group
    func isStarred(_ action: NetHackAction, in group: CommandGroup) -> Bool {
        starredByGroup[group.rawValue]?.contains(action.id) ?? false
    }

    /// Toggle star status - directly mutates @Observable state
    func toggleStar(_ action: NetHackAction, in group: CommandGroup) {
        var groupStars = starredByGroup[group.rawValue] ?? []

        if let index = groupStars.firstIndex(of: action.id) {
            // Remove star
            groupStars.remove(at: index)
            print("[CommandGroupManager] ☆ Removed star: '\(action.id)' from \(group.rawValue)")
        } else {
            // Add star (max 4 - replace oldest if full)
            if groupStars.count >= 4 {
                let removed = groupStars.removeFirst()
                print("[CommandGroupManager] ⭐ Replaced '\(removed)' with '\(action.id)' in \(group.rawValue)")
            } else {
                print("[CommandGroupManager] ⭐ Added star: '\(action.id)' in \(group.rawValue)")
            }
            groupStars.append(action.id)
        }

        // Direct mutation triggers @Observable
        starredByGroup[group.rawValue] = groupStars
        persistPreferences()
    }

    /// Get quick actions for a group (starred first, then defaults)
    func actions(for group: CommandGroup) -> [NetHackAction] {
        let starred = starredByGroup[group.rawValue] ?? []

        // Build result: starred first, then fill with defaults
        var result = starred
        for defaultID in group.defaultQuickActionIDs {
            guard result.count < 4 else { break }
            guard !result.contains(defaultID) else { continue }
            result.append(defaultID)
        }

        return result.prefix(4).compactMap { NetHackAction.find(by: $0) }
    }

    // MARK: - Persistence

    private func persistPreferences() {
        guard let name = activeCharacterName else { return }
        let prefs = CharacterPreferences(starredActionIDsByGroup: starredByGroup)
        _ = prefs.save(for: name)
    }

    // MARK: - Action Execution

    /// Execute an action (called from UI)
    func executeAction(
        _ action: NetHackAction,
        gameManager: NetHackGameManager,
        overlayManager: GameOverlayManager?
    ) {
        lastExecutedAction = action

        // Collapse after execution
        expandedGroup = nil

        // Use CommandHandler for execution
        guard let overlay = overlayManager else {
            sendCommandWithPrefixHandling(action.command, gameManager: gameManager)
            return
        }

        let result = CommandHandler.execute(
            action: action,
            gameManager: gameManager,
            overlayManager: overlay
        )

        // Handle special result types
        switch result {
        case .requiresDirection:
            print("[CommandGroupManager] Showing direction picker for '\(action.name)'")
            overlay.showActionDirectionPickerFor(action)
        case .requiresTarget:
            print("[CommandGroupManager] Target mode requested for '\(action.name)'")
        case .handled, .sendToGame:
            break
        }

        // Clear last executed after delay
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            if lastExecutedAction?.id == action.id {
                lastExecutedAction = nil
            }
        }
    }

    // MARK: - Command Prefix Handling

    private func sendCommandWithPrefixHandling(_ command: String, gameManager: NetHackGameManager) {
        // Extended command (#command)
        if command.hasPrefix("#") {
            let extCmd = String(command.dropFirst())
            gameManager.sendCommand("#")
            gameManager.sendCommand(extCmd + "\n")
            return
        }

        // Meta command (M-x -> high bit set: 0x80 | x)
        // NetHack defines M(c) as (0x80 | c), NOT ESC + c
        // CRITICAL: Must use sendRawByte - high-bit chars become UTF-8 multi-byte in String!
        if command.hasPrefix("M-") {
            let cmd = String(command.dropFirst(2))
            guard let char = cmd.first,
                  let asciiValue = char.asciiValue else { return }
            let metaByte = UInt8(asciiValue | 0x80)
            NetHackBridge.shared.sendRawByte(metaByte)
            return
        }

        // Control command (C-x -> control character)
        // CRITICAL: Must use sendRawByte - control chars don't survive String conversion!
        if command.hasPrefix("C-") {
            let cmd = String(command.dropFirst(2))
            guard let char = cmd.first,
                  let asciiValue = char.asciiValue else { return }
            let controlByte = UInt8(Int(asciiValue) - 96)  // 'x' (120) - 96 = 24 = Ctrl-X
            NetHackBridge.shared.sendRawByte(controlByte)
            return
        }

        // Regular command
        gameManager.sendCommand(command)
    }
}
