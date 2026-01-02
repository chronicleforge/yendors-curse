import Foundation
import SwiftUI
import Combine

// NOTE: CharacterSyncStatus is now defined in CharacterMetadata.swift
// Sync status is derived from timestamps, not stored separately

/// SIMPLIFIED Save/Load Coordinator - ONE save per character, no slots
///
/// This coordinator ensures:
/// - Each character has EXACTLY ONE save file
/// - Global Continue button loads the most recent save from /save/savegame
/// - Character-specific Continue loads from /characters/{name}/savegame
/// - Clean separation between UI, Game Logic, and Filesystem
///
/// Flow:
///   User Action → View → SimplifiedSaveLoadCoordinator → C Bridge → Success/Failure
class SimplifiedSaveLoadCoordinator: ObservableObject {
    // MARK: - State Machine (Single Source of Truth)

    /// State machine controls all game lifecycle transitions
    private let stateMachine = GameLifecycleStateMachine.shared

    /// Currently active character name (nil if no game running)
    @Published var activeCharacter: String?  // Removed private(set) for death reset

    /// Whether a game is currently running - delegates to state machine
    var isGameRunning: Bool {
        stateMachine.isPlaying
    }

    /// Error message for UI display
    @Published var errorMessage: String?

    /// Sync status for UI display (exposed from iCloudManager)
    var syncStatusInfo: String {
        "\(iCloudManager.lastSyncAttempt) - \(iCloudManager.lastSyncResult)"
    }

    // NOTE: syncStatus dictionary REMOVED - status is now derived from CharacterMetadata.syncStatus
    // NOTE: cloudOnlyCharacters REMOVED - use getCloudOnlyCharacters() which derives from filesystem

    /// User preference for iCloud sync (stored in UserDefaults)
    @Published var iCloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled")
            print("[SimplifiedSaveLoad] iCloud sync preference changed: \(iCloudSyncEnabled)")
        }
    }

    // MARK: - Sync Failure Handling (Phase 3)

    /// Pending sync failures that can be retried
    @Published var pendingFailures: [SyncFailure] = []

    // MARK: - Conflict Detection (Phase 5)

    /// Detected sync conflicts awaiting resolution
    @Published var conflicts: [ConflictInfo] = []

    // MARK: - Upload Serialization (CRITICAL-1 Fix)

    /// Characters currently being uploaded - blocks delete until upload completes
    /// This prevents race condition where delete runs while upload reads files
    private var charactersUploading: Set<String> = []

    /// Check if a character is currently being uploaded
    func isUploading(_ characterName: String) -> Bool {
        return charactersUploading.contains(CharacterSanitization.sanitizeName(characterName))
    }

    // MARK: - Dependencies

    private let bridge: NetHackBridge
    private let iCloudManager = iCloudStorageManager.shared
    private var gameReadyCancellable: AnyCancellable?

    static let shared = SimplifiedSaveLoadCoordinator()

    private init() {
        self.bridge = NetHackBridge.shared

        // Load iCloud sync preference (default: enabled)
        self.iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true

        // CRITICAL: Reset game state on fresh app start
        // This ensures isGameRunning is false after app restart/crash
        resetForFreshStart()

        // Listen for game ready signal (logging only - transition happens in start/continue functions)
        gameReadyCancellable = NotificationCenter.default.publisher(for: .nethackGameReady)
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("[SimplifiedSaveLoad] 🎯 Game ready signal received (state: \(self.stateMachine.state))")
            }
    }

    /// Reset coordinator state for fresh app start
    /// Called on init and when dylib is freshly loaded
    func resetForFreshStart() {
        print("[SimplifiedSaveLoad] 🔄 Resetting state for fresh start")
        _ = stateMachine.request(.reset)
        activeCharacter = nil
        errorMessage = nil
        print("[SimplifiedSaveLoad] ✅ State reset complete (state: \(stateMachine.state))")
    }
    
    // MARK: - New Game
    
    /// Start a new game for a character
    /// Returns: true if successful, false otherwise
    func startNewGame(characterName: String) -> Bool {
        print("[SimplifiedSaveLoad] Starting new game for '\(characterName)'")

        let result = stateMachine.request(.newGame(characterName))
        switch result {
        case .proceed:
            activeCharacter = characterName
            // CRITICAL: For NEW games, gameReady notification never fires!
            // Transition to playing immediately (like old code did)
            _ = stateMachine.request(.gameStarted)
            print("[SimplifiedSaveLoad] ✅ New game started - Character: '\(characterName)' (state: \(stateMachine.state))")
            return true

        case .exitFirst:
            print("[SimplifiedSaveLoad] ⚠️ Game running, must exit first - pending action stored")
            // State machine already stored the pending action and transitioned to exiting
            // The pending action will execute automatically when exitToMenu() calls .gameExited
            // Caller should trigger exitToMenu() async
            return false

        case .failed, .invalid:
            print("[SimplifiedSaveLoad] ❌ Cannot start new game (state: \(stateMachine.state))")
            errorMessage = "Cannot start game in current state"
            return false
        }
    }
    
    // MARK: - Continue Game (Global)
    
    /// Continue the most recent game (loads from /save/savegame)
    /// This is used by the global "Continue" button
    /// Returns: true if successful, false otherwise
    func continueGame() -> Bool {
        print("[SimplifiedSaveLoad] ========================================")
        print("[SimplifiedSaveLoad] Continue game requested (state: \(stateMachine.state))")

        // Request transition via state machine
        let result = stateMachine.request(.continueGame(""))
        guard result == .proceed else {
            if result == .exitFirst {
                print("[SimplifiedSaveLoad] ⚠️ Game running, will exit first")
                errorMessage = "Exiting current game..."
            } else {
                print("[SimplifiedSaveLoad] ❌ Cannot continue (state: \(stateMachine.state))")
                errorMessage = "Cannot continue in current state"
            }
            return false
        }

        // Check if save exists
        guard bridge.hasSaveGame() else {
            print("[SimplifiedSaveLoad] ❌ No save file exists")
            _ = stateMachine.request(.loadFailed("No save file"))
            errorMessage = "No saved game found"
            return false
        }

        print("[SimplifiedSaveLoad] ✅ Save exists - calling bridge.loadGame()...")

        // Load the game
        guard bridge.loadGame() else {
            print("[SimplifiedSaveLoad] ❌ Failed to load game (bridge returned false)")
            _ = stateMachine.request(.loadFailed("Bridge load failed"))
            errorMessage = "Failed to load saved game"
            return false
        }

        print("[SimplifiedSaveLoad] ✅ bridge.loadGame() successful")
        print("[SimplifiedSaveLoad] Game loaded from /save/savegame")

        // Try to detect character from save file
        if let characterName = bridge.getPlayerName() {
            activeCharacter = characterName
            print("[SimplifiedSaveLoad] Detected character: '\(characterName)'")
        }

        // Resume game thread
        print("[SimplifiedSaveLoad] Calling bridge.resumeGame()...")
        do {
            try bridge.resumeGame()
        } catch {
            print("[SimplifiedSaveLoad] ❌ Failed to resume game: \(error)")
            _ = stateMachine.request(.loadFailed(error.localizedDescription))
            errorMessage = "Failed to resume game: \(error.localizedDescription)"
            return false
        }

        // IMPORTANT: Load preferences BEFORE transitioning to playing!
        // SwiftUI renders GameView immediately when isPlaying becomes true
        if let characterName = activeCharacter {
            let role = CharacterMetadata.load(for: characterName)?.role ?? "unknown"
            CommandGroupManager.shared.loadForCharacter(characterName, role: role)
            print("[SimplifiedSaveLoad] ✅ Loaded preferences for '\(characterName)' (role: \(role))")
        }

        // NOW transition to playing - this was done manually in old code too
        _ = stateMachine.request(.gameStarted)
        print("[SimplifiedSaveLoad] ✅ Continue successful (state: \(stateMachine.state))")
        print("[SimplifiedSaveLoad] ========================================")
        return true
    }

    // MARK: - Continue Character
    
    /// Continue a specific character (loads from /characters/{name}/savegame)
    /// Returns: true if successful, false otherwise
    func continueCharacter(characterName: String) -> Bool {
        print("[SimplifiedSaveLoad] Continue character '\(characterName)' (state: \(stateMachine.state))")

        // Request transition via state machine
        let result = stateMachine.request(.continueGame(characterName))
        guard result == .proceed else {
            if result == .exitFirst {
                print("[SimplifiedSaveLoad] ⚠️ Game running, will exit first")
                errorMessage = "Exiting current game..."
            } else {
                print("[SimplifiedSaveLoad] ❌ Cannot continue (state: \(stateMachine.state))")
                errorMessage = "Cannot continue in current state"
            }
            return false
        }

        // Check if character save exists
        guard ios_character_save_exists(characterName) == 1 else {
            print("[SimplifiedSaveLoad] ❌ No save exists for character '\(characterName)'")
            _ = stateMachine.request(.loadFailed("No save for \(characterName)"))
            errorMessage = "No saved game found for \(characterName)"
            return false
        }

        // Load character save via bridge
        guard bridge.loadCharacter(characterName) else {
            print("[SimplifiedSaveLoad] ❌ Failed to load character save")
            _ = stateMachine.request(.loadFailed("Bridge load failed"))
            errorMessage = "Failed to load character save"
            return false
        }

        print("[SimplifiedSaveLoad] ✅ Character save loaded from /characters/\(characterName)/savegame")
        activeCharacter = characterName

        // Resume game thread
        do {
            try bridge.resumeGame()
        } catch {
            print("[SimplifiedSaveLoad] ❌ Failed to resume character: \(error)")
            _ = stateMachine.request(.loadFailed(error.localizedDescription))
            errorMessage = "Failed to resume character: \(error.localizedDescription)"
            return false
        }

        // IMPORTANT: Load preferences BEFORE transitioning to playing!
        // SwiftUI renders GameView immediately when isPlaying becomes true
        let role = CharacterMetadata.load(for: characterName)?.role ?? "unknown"
        CommandGroupManager.shared.loadForCharacter(characterName, role: role)
        print("[SimplifiedSaveLoad] ✅ Loaded preferences for '\(characterName)' (role: \(role))")

        // NOW transition to playing - this was done manually in old code too
        _ = stateMachine.request(.gameStarted)
        print("[SimplifiedSaveLoad] ✅ Continue character successful (state: \(stateMachine.state))")
        return true
    }

    // MARK: - Exit to Menu
    
    /// Exit to menu - saves to character's directory
    /// This is called by the "Exit" button during gameplay
    /// Returns: true if successful, false otherwise
    @MainActor
    func exitToMenu() async -> Bool {
        print("[SimplifiedSaveLoad] Exit to menu requested")

        // Request exit transition
        let result = stateMachine.request(.exitGame)
        if result == .invalid {
            print("[SimplifiedSaveLoad] ❌ Invalid state for exit: \(stateMachine.state)")
            return false
        }

        guard let characterName = activeCharacter else {
            print("[SimplifiedSaveLoad] ❌ No active character")
            errorMessage = "No active character"
            return false
        }

        // NOTE: Screenshot is now captured BEFORE exitToMenu() is called
        // See NetHackGameManager.exitToMenu() for screenshot capture logic
        // This ensures the SceneKit view is still available when capturing

        // STEP 1: Save to character-specific path
        guard ios_save_character(characterName) == 1 else {
            print("[SimplifiedSaveLoad] ❌ Failed to save character")
            errorMessage = "Failed to save game"
            return false
        }

        print("[SimplifiedSaveLoad] ✅ Game saved to /characters/\(characterName)/savegame")

        // NOTE: No need to update cloudOnlyCharacters - C code preserves downloaded_at
        // Sync status is now derived from timestamps in CharacterMetadata

        // STEP 2: Stop game thread FIRST (ensures all file handles closed)
        // CRITICAL: Must complete before iCloud upload to prevent race conditions
        await bridge.stopGameAsync()
        print("[SimplifiedSaveLoad] ✅ Game thread stopped, all files closed")

        // STEP 3: Auto-upload to iCloud in background (if user opted in)
        // Now safe because all C file operations are complete
        print("[SimplifiedSaveLoad] 🔍 Checking iCloud availability...")
        print("[SimplifiedSaveLoad] 🔍 iCloudManager.isAvailable = \(iCloudManager.isAvailable)")
        print("[SimplifiedSaveLoad] 🔍 iCloudSyncEnabled = \(iCloudSyncEnabled)")

        if iCloudSyncEnabled && iCloudManager.isAvailable {
            print("[SimplifiedSaveLoad] 🌩️ iCloud IS available AND enabled - starting upload for '\(characterName)'")

            // Capture characterName for retry closure
            let uploadCharacterName = characterName
            let sanitizedName = CharacterSanitization.sanitizeName(uploadCharacterName)

            // CRITICAL-1 FIX: Mark character as uploading to prevent race with delete
            charactersUploading.insert(sanitizedName)
            print("[SimplifiedSaveLoad] 🔒 Marked '\(sanitizedName)' as uploading")

            Task {
                defer {
                    // Always remove from uploading set when done
                    Task { @MainActor in
                        self.charactersUploading.remove(sanitizedName)
                        print("[SimplifiedSaveLoad] 🔓 Unmarked '\(sanitizedName)' as uploading")
                    }
                }

                do {
                    let characterDir = CharacterSanitization.getCharacterDirectoryURL(uploadCharacterName)
                    print("[SimplifiedSaveLoad] 📁 Character dir: \(characterDir.path)")
                    try await iCloudManager.uploadCharacterSave(from: characterDir, characterName: uploadCharacterName)
                    print("[SimplifiedSaveLoad] ✅ iCloud upload successful")

                    // Update syncedAt timestamp - status will be derived as .synced
                    CharacterMetadata.updateSyncedAt(uploadCharacterName)
                    print("[SimplifiedSaveLoad] 🟢 Updated syncedAt timestamp")
                } catch {
                    print("[SimplifiedSaveLoad] ⚠️ iCloud upload failed: \(error)")

                    // Phase 3: Add to pendingFailures for UI retry
                    await MainActor.run {
                        let failure = SyncFailure(
                            type: .upload(characterName: uploadCharacterName),
                            retryAction: { [weak self] in
                                guard let self = self else { return }
                                let characterDir = CharacterSanitization.getCharacterDirectoryURL(uploadCharacterName)
                                try await self.iCloudManager.uploadCharacterSave(from: characterDir, characterName: uploadCharacterName)
                                CharacterMetadata.updateSyncedAt(uploadCharacterName)
                            }
                        )
                        self.pendingFailures.append(failure)
                        print("[SimplifiedSaveLoad] 📋 Added upload failure to pendingFailures")
                    }
                }
            }
        } else if !iCloudSyncEnabled {
            print("[SimplifiedSaveLoad] ⚠️ iCloud sync DISABLED by user - save is local only")
        } else if !iCloudManager.isAvailable {
            print("[SimplifiedSaveLoad] ⚠️ iCloud NOT available - save is local only")
        }

        // Clear active state
        // CRITICAL FIX: Must clear activeCharacter when exiting!
        // Otherwise new game for same character won't work properly
        activeCharacter = nil

        // Notify state machine that game has exited
        _ = stateMachine.request(.gameExited)

        print("[SimplifiedSaveLoad] ✅ Exit successful - Saved to character directory, state: \(stateMachine.state)")
        return true
    }
    
    // MARK: - State Queries

    /// Check if a saved game exists (global /save/savegame)
    func hasSavedGame() -> Bool {
        return bridge.hasSaveGame()
    }

    /// Get the most recently played character based on metadata timestamps
    /// Returns: Character name with most recent save, or nil if no saves exist
    func getMostRecentCharacter() -> String? {
        let characters = listSavedCharacters()

        guard !characters.isEmpty else {
            return nil
        }

        // Load all metadata and find the most recent
        var mostRecentCharacter: String?
        var mostRecentDate: Date?

        for characterName in characters {
            guard let metadata = CharacterMetadata.load(for: characterName) else {
                continue
            }

            // Parse ISO 8601 timestamp (format: "2025-10-21T14:32:45Z")
            let isoFormatter = ISO8601DateFormatter()
            guard let saveDate = isoFormatter.date(from: metadata.lastSaved) else {
                print("[SimplifiedSaveLoad] ⚠️  Failed to parse date for '\(characterName)': \(metadata.lastSaved)")
                continue
            }

            // Check if this is the most recent
            if mostRecentDate == nil || saveDate > mostRecentDate! {
                mostRecentDate = saveDate
                mostRecentCharacter = characterName
            }
        }

        if let character = mostRecentCharacter, let date = mostRecentDate {
            print("[SimplifiedSaveLoad] ✅ Most recent character: '\(character)' (saved: \(date))")
        } else {
            print("[SimplifiedSaveLoad] ⚠️  No valid metadata found for any character")
        }

        return mostRecentCharacter
    }
    
    /// Check if a character has a save
    func characterHasSave(_ characterName: String) -> Bool {
        return ios_character_save_exists(characterName) == 1
    }
    
    /// Get active character name
    func getActiveCharacter() -> String? {
        return activeCharacter
    }
    
    /// List all characters with saves
    func listSavedCharacters() -> [String] {
        var count: Int32 = 0
        guard let charArrayPtr = ios_list_saved_characters(&count) else {
            return []
        }
        
        var characters: [String] = []
        for i in 0..<Int(count) {
            if let charPtr = charArrayPtr[i] {
                let charName = String(cString: charPtr)
                characters.append(charName)
                free(charPtr) // Free individual string
            }
        }
        free(charArrayPtr) // Free array
        
        return characters
    }
    
    // MARK: - Delete

    /// Delete a character's save (legacy method, deletes everywhere)
    func deleteCharacterSave(_ characterName: String) -> Bool {
        print("[SimplifiedSaveLoad] Deleting save for '\(characterName)'")

        guard ios_delete_character_save(characterName) == 1 else {
            print("[SimplifiedSaveLoad] ❌ Failed to delete character save")
            return false
        }

        print("[SimplifiedSaveLoad] ✅ Character save deleted")
        return true
    }

    /// Delete a character from local device only (keeps iCloud copy)
    /// Use this when user wants to free space but keep cloud backup
    /// - Parameter characterName: Name of the character to delete locally
    /// - Returns: true if successful
    func deleteCharacterLocal(_ characterName: String) -> Bool {
        print("[SimplifiedSaveLoad] 🗑️ Deleting LOCAL save for '\(characterName)' (keeping iCloud)")

        guard ios_delete_character_save(characterName) == 1 else {
            print("[SimplifiedSaveLoad] ❌ Failed to delete local character save")
            return false
        }

        print("[SimplifiedSaveLoad] ✅ Local character save deleted (iCloud copy preserved)")
        return true
    }

    /// Delete a character from both device AND iCloud
    /// Use this for permanent deletion across all devices
    /// - Parameter characterName: Name of the character to delete
    /// - Returns: true if local delete succeeded (iCloud delete is best-effort)
    @MainActor
    func deleteCharacterEverywhere(_ characterName: String) async -> Bool {
        print("[SimplifiedSaveLoad] 🗑️ Deleting '\(characterName)' EVERYWHERE (local + iCloud)")

        let sanitizedName = CharacterSanitization.sanitizeName(characterName)

        // CRITICAL-1 FIX: Wait for any in-progress upload to complete
        // This prevents race condition where we delete files while upload reads them
        if charactersUploading.contains(sanitizedName) {
            print("[SimplifiedSaveLoad] ⏳ Waiting for upload to complete before delete...")
            // Poll until upload completes (max 30 seconds)
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                if !charactersUploading.contains(sanitizedName) {
                    print("[SimplifiedSaveLoad] ✅ Upload completed, proceeding with delete")
                    break
                }
            }
            // If still uploading after 30s, proceed anyway (upload will fail gracefully)
            if charactersUploading.contains(sanitizedName) {
                print("[SimplifiedSaveLoad] ⚠️ Upload timeout, proceeding with delete anyway")
            }
        }

        // Step 1: Delete from iCloud first (before local)
        // This ensures if local fails, we haven't lost cloud backup
        var iCloudSuccess = true
        if iCloudSyncEnabled && iCloudManager.isAvailable {
            iCloudSuccess = await iCloudManager.deleteCharacterSave(characterName: characterName)
            if !iCloudSuccess {
                print("[SimplifiedSaveLoad] ⚠️ iCloud delete failed - character may reappear on sync")
                // Continue with local delete anyway
            }
        }

        // Step 2: Delete local (primary operation)
        guard ios_delete_character_save(characterName) == 1 else {
            print("[SimplifiedSaveLoad] ❌ Failed to delete local character save")
            return false
        }

        // Step 3: Report status
        if iCloudSuccess {
            print("[SimplifiedSaveLoad] ✅ Character deleted from device and iCloud")
        } else {
            print("[SimplifiedSaveLoad] ⚠️ Character deleted locally, iCloud delete failed")
            // User should be warned that character may reappear
        }

        return true
    }
    
    // MARK: - Reset

    /// Reset coordinator state (for new game after death, etc.)
    func reset() {
        print("[SimplifiedSaveLoad] Resetting state")
        activeCharacter = nil
        _ = stateMachine.request(.reset)
        errorMessage = nil
        print("[SimplifiedSaveLoad] ✅ Reset complete, state: \(stateMachine.state)")
    }

    // MARK: - Cloud-Only Characters

    /// Get list of characters that exist only in iCloud (not downloaded locally)
    /// Derived from filesystem - no cached list to maintain
    /// Returns ACTUAL iCloud folder names (needed for download operations)
    func getCloudOnlyCharacters() -> [String] {
        guard iCloudSyncEnabled, iCloudManager.isAvailable else {
            print("[SimplifiedSaveLoad] getCloudOnlyCharacters: iCloud disabled or unavailable")
            return []
        }

        let cloudCharacters = iCloudManager.getCloudCharacters()
        let localCharacters = listSavedCharacters()

        // CRITICAL: Compare using SANITIZED names to handle legacy unsanitized iCloud folders
        // But return the ACTUAL iCloud folder names for download operations
        let localSanitized = Set(localCharacters.map { CharacterSanitization.sanitizeName($0) })

        // Filter: keep cloud characters whose sanitized name is NOT in local
        // This handles both "Wizard" (old) and "wizard" (new) correctly
        var cloudOnly: [String] = []
        var seenSanitized: Set<String> = []

        for cloudName in cloudCharacters {
            let sanitized = CharacterSanitization.sanitizeName(cloudName)

            // Skip if already exists locally (comparing sanitized names)
            if localSanitized.contains(sanitized) {
                continue
            }

            // Skip duplicates (e.g., both "Wizard" and "wizard" in cloud)
            if seenSanitized.contains(sanitized) {
                continue
            }

            seenSanitized.insert(sanitized)
            cloudOnly.append(cloudName)  // Keep original name for download!
        }

        print("[SimplifiedSaveLoad] getCloudOnlyCharacters:")
        print("  - cloud: \(cloudCharacters)")
        print("  - local: \(localCharacters)")
        print("  - cloudOnly: \(cloudOnly)")

        return cloudOnly
    }

    /// Check if a character is cloud-only (needs download before playing)
    /// Uses sanitized name comparison for legacy compatibility
    func isCloudOnly(_ characterName: String) -> Bool {
        guard iCloudSyncEnabled, iCloudManager.isAvailable else {
            print("[SimplifiedSaveLoad] isCloudOnly('\(characterName)'): false (iCloud unavailable)")
            return false
        }

        // Local check using SANITIZED comparison (handles "Wizard" vs "wizard")
        let sanitizedName = CharacterSanitization.sanitizeName(characterName)
        let localCharacters = listSavedCharacters()
        let localSanitized = localCharacters.map { CharacterSanitization.sanitizeName($0) }

        if localSanitized.contains(sanitizedName) {
            print("[SimplifiedSaveLoad] isCloudOnly('\(characterName)'): false (exists locally as '\(sanitizedName)')")
            return false
        }

        // Check if it exists in cloud
        let existsInCloud = iCloudManager.characterExistsInCloud(characterName)
        print("[SimplifiedSaveLoad] isCloudOnly('\(characterName)'): \(existsInCloud) (not local, cloud=\(existsInCloud))")
        return existsInCloud
    }

    // MARK: - Initial Cloud Sync

    /// Perform initial cloud sync - logs status, no cached lists to update
    /// Sync status is derived from CharacterMetadata timestamps
    @MainActor
    func performInitialCloudSync() async {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        iCloudManager.lastSyncAttempt = timestamp

        guard iCloudSyncEnabled else {
            print("[SimplifiedSaveLoad] ⏭️ Skipping cloud sync (disabled)")
            iCloudManager.lastSyncResult = "disabled"
            return
        }

        // Wait for iCloud availability check to complete (async init)
        let available = await iCloudManager.waitForAvailability()
        guard available else {
            print("[SimplifiedSaveLoad] ⏭️ Skipping cloud sync (iCloud unavailable)")
            iCloudManager.lastSyncResult = "unavailable"
            return
        }

        print("[SimplifiedSaveLoad] 🌩️ Checking cloud characters...")

        // Get counts for logging
        let cloudCharacters = iCloudManager.getCloudCharacters()
        let localCharacters = listSavedCharacters()
        let cloudOnlyCount = cloudCharacters.filter { !localCharacters.contains($0) }.count

        print("[SimplifiedSaveLoad] 📊 Found \(cloudCharacters.count) cloud, \(localCharacters.count) local, \(cloudOnlyCount) cloud-only")

        iCloudManager.lastSyncResult = "ready (local:\(localCharacters.count) cloud-only:\(cloudOnlyCount))"
        print("[SimplifiedSaveLoad] ✅ Cloud sync check complete")
    }

    // MARK: - On-Demand Download

    /// Download a single character from iCloud (called when user taps cloud character)
    /// - Parameter characterName: Name of the character to download
    /// - Throws: iCloudError if download fails
    @MainActor
    func downloadCharacter(_ characterName: String) async throws {
        print("[SimplifiedSaveLoad] 📥 On-demand download: '\(characterName)'")

        guard iCloudSyncEnabled, iCloudManager.isAvailable else {
            throw iCloudError.notAvailable
        }

        do {
            try await iCloudManager.downloadCharacterSave(characterName: characterName)

            // Update downloadedAt timestamp - sync status will be derived
            CharacterMetadata.updateDownloadedAt(characterName)

            print("[SimplifiedSaveLoad] ✅ Downloaded '\(characterName)' successfully")

            // Post notification for UI update
            NotificationCenter.default.post(
                name: Notification.Name("CharacterDownloaded"),
                object: nil,
                userInfo: ["characterName": characterName]
            )
        } catch {
            print("[SimplifiedSaveLoad] ❌ Download failed: \(error)")
            throw error
        }
    }

    /// Manually trigger a sync check (for pull-to-refresh)
    @MainActor
    func refreshCloudSync() async {
        print("[SimplifiedSaveLoad] 🔄 Manual cloud sync refresh requested")
        await performInitialCloudSync()
    }
}
