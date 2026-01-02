import Foundation
import Combine

/// Manages iCloud Document Storage for NetHack saves
/// Handles automatic sync, conflict resolution, and offline capability
class iCloudStorageManager: ObservableObject {
    static let shared = iCloudStorageManager()

    // MARK: - Published Properties

    @Published var isAvailable: Bool = false
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0.0
    @Published var lastError: String?

    // MARK: - Private Properties

    // NOTE: NSFileCoordinator instances are created per-operation for thread-safety
    // Not stored as instance variable
    private var metadataQuery: NSMetadataQuery?
    private var ubiquityContainer: URL?
    private let operationQueue = OperationQueue()

    /// Directory names
    private let charactersDirectoryName = "characters"

    // MARK: - Initialization

    private init() {
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInitiated

        checkiCloudAvailability()
        // NOTE: setupMetadataQuery() is now called from checkiCloudAvailability()
        // after isAvailable is confirmed (fixes race condition)
    }

    // MARK: - iCloud Availability

    /// The iCloud container identifier from entitlements
    private let containerIdentifier = "iCloud.de.manyminds.nethack"

    private func checkiCloudAvailability() {
        // Check if iCloud is available
        guard FileManager.default.ubiquityIdentityToken != nil else {
            isAvailable = false
            print("[iCloud] iCloud not available - user not signed in")
            return
        }

        print("[iCloud] Checking availability for container: \(containerIdentifier)")

        // Get ubiquity container - use explicit identifier!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Try explicit identifier first
            var container = FileManager.default.url(forUbiquityContainerIdentifier: self.containerIdentifier)

            // Fallback to default if explicit fails
            if container == nil {
                print("[iCloud] ⚠️ Explicit container failed, trying nil...")
                container = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            }

            DispatchQueue.main.async {
                self.ubiquityContainer = container
                self.isAvailable = container != nil

                if let path = container?.path {
                    print("[iCloud] ✅ Container available: \(path)")
                    self.ensureDirectoryStructure()
                    self.setupMetadataQuery()  // Start after availability confirmed
                } else {
                    print("[iCloud] ❌ Failed to get container URL for \(self.containerIdentifier)")
                }
            }
        }
    }

    /// Waits for iCloud availability check to complete (max 5 seconds)
    /// Returns true if iCloud became available, false if timed out or unavailable
    func waitForAvailability() async -> Bool {
        // If already determined, return immediately
        if isAvailable { return true }
        if FileManager.default.ubiquityIdentityToken == nil { return false }

        // Wait for async availability check to complete
        for _ in 0..<50 {  // 50 * 100ms = 5 seconds max
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            if isAvailable { return true }
        }

        print("[iCloud] ⏰ Timed out waiting for availability")
        return false
    }

    private func ensureDirectoryStructure() {
        guard let container = ubiquityContainer else { return }

        let charactersURL = container.appendingPathComponent("Documents")
            .appendingPathComponent(charactersDirectoryName)

        do {
            try FileManager.default.createDirectory(at: charactersURL,
                                                   withIntermediateDirectories: true)
            print("[iCloud] ✅ Character directory structure created")
        } catch {
            print("[iCloud] ❌ Failed to create character directories: \(error)")
            lastError = "Failed to setup iCloud: \(error.localizedDescription)"
        }
    }

    // MARK: - Metadata Query (Auto-Discovery)

    private func setupMetadataQuery() {
        guard isAvailable else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        // Search for our snapshot metadata files
        query.predicate = NSPredicate(format: "%K LIKE %@",
                                      NSMetadataItemFSNameKey,
                                      "*.json")

        // Observe query notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.start()
        metadataQuery = query

        print("[iCloud] ✅ Metadata query started")
    }

    @objc private func metadataQueryDidFinishGathering(_ notification: Notification) {
        print("[iCloud] Metadata query finished gathering")
        processQueryResults()
    }

    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        print("[iCloud] Metadata query updated")
        processQueryResults()
    }

    private func processQueryResults() {
        guard let query = metadataQuery else { return }

        query.disableUpdates()
        defer { query.enableUpdates() }

        // Process discovered character saves
        var discoveredCount = 0
        var downloadedCount = 0
        var queuedDownloads: [String] = []

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                continue
            }

            // Extract character name from path
            // Path format: .../Documents/characters/{characterName}/metadata.json
            let pathComponents = url.pathComponents
            guard pathComponents.count >= 3,
                  pathComponents[pathComponents.count - 3] == "characters",
                  url.lastPathComponent == "metadata.json" else {
                continue
            }

            let characterName = pathComponents[pathComponents.count - 2]
            discoveredCount += 1

            // Check download status
            let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String

            if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                // File is downloaded to iCloud local cache
                downloadedCount += 1

                // Check if we have a local copy
                if !characterExistsLocally(characterName) {
                    print("[iCloud] Cloud character '\(characterName)' not found locally - queuing for download")
                    queuedDownloads.append(characterName)
                } else {
                    print("[iCloud] Character '\(characterName)' already exists locally")
                }
            } else {
                // File not downloaded from iCloud yet
                print("[iCloud] Character '\(characterName)' not cached locally - triggering cloud download")

                // Trigger download from iCloud
                do {
                    try startDownload(for: url.deletingLastPathComponent())
                    queuedDownloads.append(characterName)
                } catch {
                    print("[iCloud] Failed to trigger download for '\(characterName)': \(error)")
                }
            }
        }

        print("[iCloud] ✅ Discovered \(discoveredCount) character saves (\(downloadedCount) cached)")

        // Download queued characters to local storage
        if !queuedDownloads.isEmpty {
            Task { @MainActor in
                self.isSyncing = true
            }

            Task {
                for characterName in queuedDownloads {
                    do {
                        try await self.downloadCharacterSave(characterName: characterName)
                        print("[iCloud] ✅ Downloaded character '\(characterName)' to local storage")

                        // Post notification for UI update
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: Notification.Name("iCloudCharacterDownloaded"),
                                object: nil,
                                userInfo: ["characterName": characterName]
                            )
                        }
                    } catch {
                        print("[iCloud] ❌ Failed to download character '\(characterName)': \(error)")
                        await MainActor.run {
                            self.lastError = "Failed to download '\(characterName)': \(error.localizedDescription)"
                        }
                    }
                }

                await MainActor.run {
                    self.isSyncing = false
                }
            }
        }
    }


    // MARK: - Upload Character Save

    /// Upload a character save from local storage to iCloud
    /// - Parameters:
    ///   - localURL: Local directory containing the character save
    ///   - characterName: Name of the character
    func uploadCharacterSave(from localURL: URL, characterName: String) async throws {
        guard isAvailable, let container = ubiquityContainer else {
            throw iCloudError.notAvailable
        }

        // CRITICAL: Use sanitized name to match local directory naming
        let sanitizedName = CharacterSanitization.sanitizeName(characterName)
        let iCloudURL = container.appendingPathComponent("Documents")
            .appendingPathComponent("characters")
            .appendingPathComponent(sanitizedName)

        print("[iCloud] Uploading character save '\(characterName)'")

        await MainActor.run {
            isSyncing = true
            syncProgress = 0.0
        }

        defer {
            Task { @MainActor in
                isSyncing = false
                syncProgress = 0.0
            }
        }

        // CRITICAL: Must use setUbiquitous() to trigger iCloud sync!
        // copyItem() does NOT register files with iCloud sync daemon.
        // setUbiquitous() MOVES the file, so we copy to temp first.

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(sanitizedName)

        do {
            // Step 1: Copy local save to temp location
            try FileManager.default.createDirectory(
                at: tempURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: localURL, to: tempURL)
            print("[iCloud] 📁 Copied to temp: \(tempURL.path)")

            // Step 2: Remove existing iCloud version if present
            // NOTE: setUbiquitous() throws if destination exists, so we must remove first
            // Risk: If setUbiquitous fails after remove, old version is lost
            // Mitigation: We still have local copy, can re-upload on next save
            if FileManager.default.fileExists(atPath: iCloudURL.path) {
                try FileManager.default.removeItem(at: iCloudURL)
                print("[iCloud] 🗑️ Removed existing iCloud version")
            }

            // Step 3: Move temp to iCloud using setUbiquitous (triggers sync!)
            // MUST be called from background thread (we're already async)
            try FileManager.default.setUbiquitous(true, itemAt: tempURL, destinationURL: iCloudURL)

            print("[iCloud] ✅ Character save uploaded successfully via setUbiquitous")

            // Cleanup temp parent directory
            try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())

        } catch {
            print("[iCloud] ❌ Upload failed: \(error)")
            // Cleanup temp on failure
            try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
            throw error
        }
    }


    // MARK: - Helper: Copy from Cloud to Local

    /// Copy a directory from iCloud to local storage using NSFileCoordinator
    private func copyFromCloud(from cloudURL: URL, to localURL: URL) async throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var capturedError: NSError?

        coordinator.coordinate(
            readingItemAt: cloudURL,
            options: [],
            writingItemAt: localURL,
            options: .forReplacing,
            error: &coordinationError
        ) { readURL, writeURL in
            do {
                // CRITICAL: Create parent directory if it doesn't exist!
                let parentDir = writeURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parentDir.path) {
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    print("[iCloud] Created parent directory: \(parentDir.path)")
                }

                // Remove existing local copy if present
                if FileManager.default.fileExists(atPath: writeURL.path) {
                    try FileManager.default.removeItem(at: writeURL)
                }

                // Copy entire directory from iCloud to local
                try FileManager.default.copyItem(at: readURL, to: writeURL)
                print("[iCloud] ✅ Copied from \(readURL.lastPathComponent) to local")
            } catch {
                print("[iCloud] ❌ Copy to local failed: \(error)")
                capturedError = error as NSError
            }
        }

        if let error = coordinationError ?? capturedError {
            throw error
        }
    }

    // MARK: - Download Character Save

    /// Download a character save from iCloud to local storage
    /// - Parameter characterName: Name of the character to download (use ACTUAL iCloud folder name)
    func downloadCharacterSave(characterName: String) async throws {
        guard isAvailable, let container = ubiquityContainer else {
            throw iCloudError.notAvailable
        }

        // Use the ACTUAL folder name passed in (from getCloudCharacters)
        // Local directory will use sanitized name via CharacterSanitization
        let iCloudURL = container.appendingPathComponent("Documents")
            .appendingPathComponent("characters")
            .appendingPathComponent(characterName)

        // Get local directory URL using CharacterSanitization
        let localURL = CharacterSanitization.getCharacterDirectoryURL(characterName)

        print("[iCloud] Downloading character save '\(characterName)'")
        print("[iCloud]   From: \(iCloudURL.path)")
        print("[iCloud]   To: \(localURL.path)")

        await MainActor.run {
            isSyncing = true
            syncProgress = 0.0
        }

        defer {
            Task { @MainActor in
                isSyncing = false
                syncProgress = 0.0
            }
        }

        // List what's actually in the characters directory
        let charactersDir = iCloudURL.deletingLastPathComponent()
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: charactersDir.path) {
            let matching = contents.filter { $0.contains(characterName) || $0.contains(characterName.lowercased()) }
            print("[iCloud]   Dir contents matching '\(characterName)': \(matching)")
        }

        // Check for either the actual file OR the .icloud placeholder
        let placeholderURL = iCloudURL.deletingLastPathComponent()
            .appendingPathComponent(".\(characterName).icloud")

        let actualExists = FileManager.default.fileExists(atPath: iCloudURL.path)
        let placeholderExists = FileManager.default.fileExists(atPath: placeholderURL.path)

        print("[iCloud]   actual exists: \(actualExists) at \(iCloudURL.lastPathComponent)")
        print("[iCloud]   placeholder exists: \(placeholderExists) at \(placeholderURL.lastPathComponent)")

        // If neither exists, the name might be case-different - try to find it
        if !actualExists && !placeholderExists {
            // Try to find a matching entry (case-insensitive)
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: charactersDir.path) {
                for item in contents {
                    let cleanName = item.hasPrefix(".") && item.hasSuffix(".icloud")
                        ? String(item.dropFirst().dropLast(7))
                        : item
                    if cleanName.lowercased() == characterName.lowercased() {
                        print("[iCloud]   Found case-different match: \(item)")
                        // Use this match instead
                        let correctedURL = charactersDir.appendingPathComponent(cleanName)
                        let correctedPlaceholder = charactersDir.appendingPathComponent(".\(cleanName).icloud")

                        if FileManager.default.fileExists(atPath: correctedURL.path) {
                            print("[iCloud]   Using corrected path (directory)")
                            // Copy from corrected path
                            try await copyFromCloud(from: correctedURL, to: localURL)
                            return
                        } else if FileManager.default.fileExists(atPath: correctedPlaceholder.path) {
                            print("[iCloud]   Using corrected path (placeholder)")
                            try FileManager.default.startDownloadingUbiquitousItem(at: correctedPlaceholder)
                            // Continue with download wait below using corrected URL
                        }
                    }
                }
            }

            print("[iCloud] ❌ Character save not found in iCloud: \(characterName)")
            throw iCloudError.snapshotNotFound
        }

        // If actual directory exists, copy it directly
        if actualExists {
            print("[iCloud]   Directory exists, copying directly...")
            try await copyFromCloud(from: iCloudURL, to: localURL)
            return
        }

        // If placeholder exists, we need to trigger download
        if placeholderExists {
            print("[iCloud] Found placeholder, triggering download...")
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: placeholderURL)
            } catch {
                print("[iCloud] startDownloadingUbiquitousItem failed: \(error)")
                throw iCloudError.downloadFailed
            }

            // Wait for download to complete
            let maxAttempts = 120 // 60 seconds timeout (longer for slow connections)
            var attempts = 0

            while attempts < maxAttempts {
                if FileManager.default.fileExists(atPath: iCloudURL.path) {
                    print("[iCloud] ✅ Download complete! File now exists.")
                    break
                }

                await MainActor.run {
                    syncProgress = Double(attempts) / Double(maxAttempts)
                }

                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                attempts += 1
            }

            if !FileManager.default.fileExists(atPath: iCloudURL.path) {
                print("[iCloud] ❌ Download timeout after \(maxAttempts/2)s - file still doesn't exist")
                throw iCloudError.downloadFailed
            }

            // Now copy the downloaded file
            try await copyFromCloud(from: iCloudURL, to: localURL)
        }
    }

    /// Check if a character exists locally
    func characterExistsLocally(_ characterName: String) -> Bool {
        let localURL = CharacterSanitization.getCharacterDirectoryURL(characterName)
        return FileManager.default.fileExists(atPath: localURL.path)
    }

    /// Check if a character exists in iCloud
    /// Checks both exact name AND sanitized name for legacy compatibility
    func characterExistsInCloud(_ characterName: String) -> Bool {
        guard isAvailable, let container = ubiquityContainer else {
            print("[iCloud] characterExistsInCloud: NOT available or no container")
            return false
        }

        let sanitizedName = CharacterSanitization.sanitizeName(characterName)
        let charactersDir = container.appendingPathComponent("Documents")
            .appendingPathComponent("characters")

        // Check both original AND sanitized names for compatibility
        let iCloudURL = charactersDir.appendingPathComponent(characterName)
        let iCloudURLSanitized = charactersDir.appendingPathComponent(sanitizedName)

        // Check for actual directory OR .icloud placeholder (both versions)
        let iCloudPlaceholder = charactersDir.appendingPathComponent(".\(characterName).icloud")
        let iCloudPlaceholderSanitized = charactersDir.appendingPathComponent(".\(sanitizedName).icloud")

        let dirExists = FileManager.default.fileExists(atPath: charactersDir.path)

        // Check all possible paths (original and sanitized)
        let exists = FileManager.default.fileExists(atPath: iCloudURL.path)
        let existsSanitized = FileManager.default.fileExists(atPath: iCloudURLSanitized.path)
        let placeholderExists = FileManager.default.fileExists(atPath: iCloudPlaceholder.path)
        let placeholderSanitizedExists = FileManager.default.fileExists(atPath: iCloudPlaceholderSanitized.path)

        let found = exists || existsSanitized || placeholderExists || placeholderSanitizedExists

        print("[iCloud] characterExistsInCloud(\(characterName)):")
        print("[iCloud]   sanitized: \(sanitizedName)")
        print("[iCloud]   found: \(found) (dir=\(exists || existsSanitized), placeholder=\(placeholderExists || placeholderSanitizedExists))")

        return found
    }

    /// Track last sync attempt for debugging
    var lastSyncAttempt: String = "never"
    var lastSyncResult: String = "none"

    /// Get debug info for troubleshooting
    func getDebugInfo() -> String {
        var info = ""
        info += "available: \(isAvailable)\n"
        info += "lastSync: \(lastSyncAttempt)\n"
        info += "syncResult: \(lastSyncResult)\n"

        // Test getCloudCharacters() function
        let cloudChars = getCloudCharacters()
        info += "cloudChars: \(cloudChars.count)\n"

        // Check local characters
        let localPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let localCharsPath = "\(localPath)/NetHack/characters"
        if FileManager.default.fileExists(atPath: localCharsPath) {
            do {
                let localChars = try FileManager.default.contentsOfDirectory(atPath: localCharsPath)
                info += "localChars: \(localChars.count)\n"
            } catch {
                info += "localChars: error\n"
            }
        } else {
            info += "localChars: dir missing\n"
        }

        if let container = ubiquityContainer {
            // Show shortened path
            let path = container.path
            let shortPath = path.replacingOccurrences(of: "/private/var/mobile/Library/Mobile Documents/", with: "~/")
            info += "path: \(shortPath)\n"

            let charactersDir = container.appendingPathComponent("Documents")
                .appendingPathComponent("characters")
            let dirExists = FileManager.default.fileExists(atPath: charactersDir.path)
            info += "charDir: \(dirExists)\n"

            if dirExists {
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: charactersDir.path)
                    if contents.isEmpty {
                        info += "contents: (empty)\n"
                    } else {
                        info += "contents:\n"
                        for item in contents.prefix(10) {
                            info += "  - \(item)\n"
                        }
                        if contents.count > 10 {
                            info += "  ... +\(contents.count - 10) more\n"
                        }
                    }
                } catch {
                    info += "error: \(error.localizedDescription)\n"
                }
            } else {
                // Check if Documents exists
                let docsDir = container.appendingPathComponent("Documents")
                let docsExists = FileManager.default.fileExists(atPath: docsDir.path)
                info += "Documents: \(docsExists)\n"

                if docsExists {
                    do {
                        let docsContents = try FileManager.default.contentsOfDirectory(atPath: docsDir.path)
                        info += "docsContents: \(docsContents)\n"
                    } catch {
                        info += "docsError: \(error.localizedDescription)\n"
                    }
                }
            }
        } else {
            info += "container: nil\n"
        }

        return info
    }

    /// Get list of all available cloud characters
    /// Handles both downloaded directories AND .icloud placeholder files
    /// Returns ACTUAL folder names (needed for download operations)
    /// Use getCloudCharactersSanitized() for comparison with local characters
    func getCloudCharacters() -> [String] {
        guard isAvailable, let container = ubiquityContainer else {
            print("[iCloud] getCloudCharacters: not available or no container")
            return []
        }

        let charactersURL = container.appendingPathComponent("Documents")
            .appendingPathComponent("characters")

        print("[iCloud] getCloudCharacters checking: \(charactersURL.path)")

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: charactersURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isUbiquitousItemKey],
                options: []
            )

            print("[iCloud] getCloudCharacters found \(contents.count) items")

            var characters: [String] = []

            for url in contents {
                let name = url.lastPathComponent

                // Case 1: Downloaded directory (e.g., "Wizard/" or "wizard/")
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    print("[iCloud]   Found directory: \(name)")
                    characters.append(name)
                    continue
                }

                // Case 2: iCloud placeholder file (e.g., ".Wizard.icloud")
                // These are files that exist in iCloud but haven't been downloaded yet
                if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                    // Extract character name: ".Wizard.icloud" -> "Wizard"
                    let characterName = String(name.dropFirst().dropLast(7))
                    print("[iCloud]   Found placeholder: \(name) -> \(characterName)")
                    characters.append(characterName)

                    // Trigger download of this item
                    do {
                        try FileManager.default.startDownloadingUbiquitousItem(at: url)
                        print("[iCloud]   Started downloading: \(characterName)")
                    } catch {
                        print("[iCloud]   Failed to start download: \(error)")
                    }
                }
            }

            print("[iCloud] getCloudCharacters returning: \(characters)")
            return characters
        } catch {
            print("[iCloud] Failed to list cloud characters: \(error)")
            return []
        }
    }

    // MARK: - Delete Character Save

    /// Delete a character save from iCloud
    /// - Parameter characterName: Name of the character to delete
    /// - Returns: true if deleted successfully or didn't exist
    func deleteCharacterSave(characterName: String) async -> Bool {
        guard isAvailable, let container = ubiquityContainer else {
            print("[iCloud] Delete skipped - iCloud not available")
            return true // Not an error if iCloud isn't enabled
        }

        // CRITICAL: Use sanitized name to match upload path
        let sanitizedName = CharacterSanitization.sanitizeName(characterName)
        let iCloudURL = container.appendingPathComponent("Documents")
            .appendingPathComponent("characters")
            .appendingPathComponent(sanitizedName)

        print("[iCloud] 🗑️ Deleting character save '\(characterName)' from iCloud...")
        print("[iCloud]   Path: \(iCloudURL.path)")

        // Check if exists
        guard FileManager.default.fileExists(atPath: iCloudURL.path) else {
            print("[iCloud] ✅ Character save doesn't exist in iCloud (already deleted or never uploaded)")
            return true
        }

        // Use NSFileCoordinator for safe deletion
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var deleteSuccess = false

        coordinator.coordinate(
            writingItemAt: iCloudURL,
            options: .forDeleting,
            error: &coordinationError
        ) { deleteURL in
            do {
                try FileManager.default.removeItem(at: deleteURL)
                print("[iCloud] ✅ Character save deleted from iCloud")
                deleteSuccess = true
            } catch {
                print("[iCloud] ❌ Failed to delete from iCloud: \(error)")
            }
        }

        if let error = coordinationError {
            print("[iCloud] ❌ Coordination error during delete: \(error)")
            return false
        }

        return deleteSuccess
    }

    // MARK: - Conflict Detection

    /// Check if there are unresolved conflicts for a snapshot
    func detectConflicts(for snapshotID: UUID) -> [NSFileVersion] {
        guard isAvailable, let container = ubiquityContainer else {
            return []
        }

        let iCloudURL = container.appendingPathComponent("Documents")
            .appendingPathComponent(charactersDirectoryName)
            .appendingPathComponent(snapshotID.uuidString)

        // Check for conflicts
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: iCloudURL)

        if let conflicts = versions, !conflicts.isEmpty {
            print("[iCloud] ⚠️ Found \(conflicts.count) conflicts for snapshot \(snapshotID)")
            return conflicts
        }

        return []
    }

    /// Resolve conflict by choosing a specific version
    func resolveConflict(keepVersion version: NSFileVersion, discardOthers others: [NSFileVersion]) throws {
        // Mark chosen version as current
        try version.replaceItem(at: version.url, options: [])

        // Remove other versions
        for other in others {
            try NSFileVersion.removeOtherVersionsOfItem(at: other.url)
            other.isResolved = true
        }

        print("[iCloud] ✅ Conflict resolved")
    }

    // MARK: - Status Checking

    /// Check download status of a file
    func downloadStatus(for url: URL) -> String? {
        var status: AnyObject?
        do {
            try (url as NSURL).getResourceValue(&status,
                                               forKey: .ubiquitousItemDownloadingStatusKey)
            return status as? String
        } catch {
            print("[iCloud] Failed to get download status: \(error)")
            return nil
        }
    }

    /// Start downloading a file from iCloud
    func startDownload(for url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        print("[iCloud] Started download for: \(url.lastPathComponent)")
    }
}

// MARK: - Error Types

enum iCloudError: LocalizedError {
    case notAvailable
    case uploadFailed
    case downloadFailed
    case snapshotNotFound

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "iCloud is not available. Please sign in to iCloud in Settings."
        case .uploadFailed:
            return "Failed to upload snapshot to iCloud."
        case .downloadFailed:
            return "Failed to download snapshot from iCloud."
        case .snapshotNotFound:
            return "Snapshot not found in iCloud."
        }
    }
}
