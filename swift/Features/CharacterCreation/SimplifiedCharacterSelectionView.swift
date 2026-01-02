import SwiftUI
import os.log

private let logger = Logger(subsystem: "de.manyminds.nethack", category: "CharacterSelection")

/// CLEAN Character Selection View - Screen 2 of 3
///
/// Purpose: Choose existing character (continue) or create new character
///
/// Features:
/// - IF save exists: Screenshot + metadata overlay + [Continue]/[New Game]/[Delete]
/// - IF no save: Icon + "No save available" + [New Game]
/// - LEFT-ALIGNED stats (critical!)
/// - Dark overlay (0.7-0.85 opacity) on screenshot
/// - RESPONSIVE: Uses ResponsiveLayout for ALL devices (iPhone to iPad Pro)
struct SimplifiedCharacterSelectionView: View {
    let gameManager: NetHackGameManager

    @StateObject private var coordinator = SimplifiedSaveLoadCoordinator.shared
    @State private var hasExistingSave: Bool = false
    @State private var allCharacters: [CharacterMetadata] = []  // ALL saved characters
    @State private var characterToDelete: CharacterMetadata?  // Character pending deletion (triggers sheet)
    @State private var showCharacterCreation = false
    @State private var showSettings = false
    @State private var selectedBackground = "nethack-background-v1"

    // Cloud download state
    @State private var isDownloading = false
    @State private var downloadingCharacter: String?
    @State private var downloadError: String?
    @State private var downloadTask: Task<Void, Never>?

    // Phase 5: Conflict resolution state
    @State private var showConflictSheet = false
    @State private var currentConflict: ConflictInfo?

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject private var iCloudManager = iCloudStorageManager.shared

    private let backgroundImages = [
        "nethack-background-v1",
        "nethack-background-v2",
        "nethack-background-v3",
        "nethack-background-v4",
        "nethack-background-v5",
        "nethack-background-v6"
    ]

    var body: some View {
        GeometryReader { geometry in
            let device = DeviceCategory.detect(for: geometry)
            let screenPadding = ResponsiveLayout.screenPadding(for: geometry)
            let titleSize = ResponsiveLayout.fontSize(.title, for: geometry)
            let subtitleSize = ResponsiveLayout.fontSize(.body, for: geometry)
            let spacing = ResponsiveLayout.spacing(.large, for: geometry)
            // iPhone landscape has ~362-402pt height - hide title when compact
            let isCompactHeight = geometry.size.height < 500

            ZStack {
                // Background layer - FIRST in ZStack for proper layering
                backgroundLayer

                // Phase 4: Offline Banner at top
                VStack {
                    OfflineBanner()
                        .padding(.horizontal, 16)
                        .padding(.top, geometry.safeAreaInsets.top + 8)
                    Spacer()
                }
                .zIndex(6)

                // Settings button - top right corner (Glass-morphic)
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 44, height: 44)  // Apple HIG minimum
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                                        )
                                )
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                        .contentShape(Circle())
                        .accessibilityLabel("Settings")
                        .padding(.top, geometry.safeAreaInsets.top + (iCloudManager.isAvailable ? 8 : 60))
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .zIndex(5)

                // Main content - RESPONSIVE sizes
                VStack(spacing: isCompactHeight ? spacing * 0.5 : spacing) {
                    Spacer()

                    // Title section - HIDDEN on iPhone landscape to save space
                    if !isCompactHeight {
                        VStack(spacing: ResponsiveLayout.spacing(.small, for: geometry)) {
                            Text("Yendor's Curse")
                                .font(.custom("PirataOne-Regular", size: titleSize))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.9), radius: 4, x: 2, y: 2)

                            Text("Choose Your Hero")
                                .font(.system(size: subtitleSize, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.9), radius: 2)
                        }
                    }

                    // Main content: Character list OR No save prompt
                    if hasExistingSave {
                        characterListSection(geometry: geometry, isCompact: isCompactHeight)
                    } else {
                        noSaveSection(geometry: geometry, isCompact: isCompactHeight)
                    }

                    Spacer()
                }
                .padding(screenPadding)

                // Character creation overlay (fullscreen, above scaled content)
                if showCharacterCreation {
                    FullscreenCharacterCreationView(
                        gameManager: gameManager,
                        isPresented: $showCharacterCreation
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .zIndex(10)
                }
            }
            // Pass device category to child views
            .environment(\.deviceCategory, device)
        }
        .sheet(item: $characterToDelete) { character in
            // Use DeleteConfirmationSheet for iCloud-aware deletion
            DeleteConfirmationSheet(
                character: character,
                onDeleteLocal: {
                    deleteCharacterLocal()
                },
                onDeleteEverywhere: {
                    deleteCharacterEverywhere()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.nethackGray100)
        }
        .alert("Download Failed", isPresented: .init(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
        )) {
            Button("OK", role: .cancel) {
                downloadError = nil
            }
        } message: {
            Text(downloadError ?? "Unknown error")
        }
        .overlay(alignment: .bottom) {
            // Phase 3: Sync failure toasts at bottom
            SyncFailureToastContainer(failures: $coordinator.pendingFailures)
        }
        .overlay {
            // Phase 6: Enhanced download progress with cancel button
            if isDownloading, let characterName = downloadingCharacter {
                DownloadProgressView(
                    characterName: characterName,
                    iCloudManager: iCloudManager,
                    onCancel: {
                        downloadTask?.cancel()
                        downloadTask = nil
                        isDownloading = false
                        downloadingCharacter = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showConflictSheet) {
            // Phase 5: Conflict resolution sheet
            if let conflict = currentConflict {
                ConflictResolutionSheet(
                    characterName: conflict.characterName,
                    localMetadata: conflict.localMetadata,
                    cloudMetadata: conflict.cloudMetadata,
                    onKeepLocal: {
                        // Upload local version to overwrite cloud
                        let characterDir = CharacterSanitization.getCharacterDirectoryURL(conflict.characterName)
                        try? await iCloudManager.uploadCharacterSave(from: characterDir, characterName: conflict.characterName)
                        CharacterMetadata.updateSyncedAt(conflict.characterName)
                    },
                    onKeepCloud: {
                        // Download cloud version to overwrite local
                        try? await coordinator.downloadCharacter(conflict.characterName)
                    },
                    onKeepBoth: {
                        // Rename local version with " (Conflict)" suffix
                        // For now, just keep both by doing nothing (local stays, cloud stays)
                        // TODO: Implement actual rename logic
                    }
                )
            }
        }
        .onAppear {
            loadCharacterData()
            selectRandomBackground()
        }
        .task {
            // Sync cloud saves on appear (download any saves from other devices)
            await coordinator.performInitialCloudSync()
            // Reload data after cloud sync completes
            loadCharacterData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .characterSyncStatusChanged)) { notification in
            // Refresh character list when sync status changes (after upload completes)
            if let characterName = notification.object as? String {
                logger.info("[CharacterSelection] Sync status changed for '\(characterName)' - refreshing list")
            }
            loadCharacterData()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }


    // MARK: - View Components

    /// Background layer - random NetHack background with dark overlay
    private var backgroundLayer: some View {
        GeometryReader { geo in
            ZStack {
                Image(selectedBackground)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Color.black.opacity(0.6)  // Dark overlay for text readability
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)  // Remove from accessibility tree
    }

    /// Character list section - Hero card center, other saves left/right with overflow drawers
    private func characterListSection(geometry: GeometryProxy, isCompact: Bool) -> some View {
        CharacterListContent(
            allCharacters: allCharacters,
            cloudOnlyCharacters: Set(coordinator.getCloudOnlyCharacters()),
            geometry: geometry,
            isCompact: isCompact,
            onContinue: continueGame,
            onDelete: { metadata in
                characterToDelete = metadata  // Triggers sheet via .sheet(item:)
            },
            onNewGame: startNewGame
        )
    }
}

// MARK: - Character List Content (with drawer state)

/// Extracted to manage drawer state at this level for proper z-index
struct CharacterListContent: View {
    let allCharacters: [CharacterMetadata]
    let cloudOnlyCharacters: Set<String>
    let geometry: GeometryProxy
    let isCompact: Bool
    let onContinue: (String) -> Void
    let onDelete: (CharacterMetadata) -> Void
    let onNewGame: () -> Void

    @State private var leftDrawerExpanded = false
    @State private var rightDrawerExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardWidth: CGFloat {
        ResponsiveLayout.heroCardWidth(in: geometry)
    }

    private var spacing: CGFloat {
        isCompact ? ResponsiveLayout.spacing(.medium, for: geometry) : ResponsiveLayout.spacing(.large, for: geometry)
    }

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var otherSaves: [CharacterMetadata] {
        Array(allCharacters.dropFirst())
    }

    private var leftSaves: [CharacterMetadata] {
        let midpoint = (otherSaves.count + 1) / 2
        return Array(otherSaves.prefix(midpoint))
    }

    private var rightSaves: [CharacterMetadata] {
        let midpoint = (otherSaves.count + 1) / 2
        return Array(otherSaves.dropFirst(midpoint))
    }

    private var visiblePerColumn: Int {
        device.isPhone ? 2 : 3
    }

    private var anyDrawerOpen: Bool {
        leftDrawerExpanded || rightDrawerExpanded
    }

    var body: some View {
        ZStack {
            // Main content
            VStack(alignment: .center, spacing: spacing) {
                // Main row: [Stacked Left] [HERO] [Stacked Right]
                HStack(alignment: .center, spacing: device.isPhone ? 12 : 20) {
                    // Left column
                    if !leftSaves.isEmpty {
                        StackedSaveColumn(
                            saves: leftSaves,
                            cloudOnlyCharacters: cloudOnlyCharacters,
                            side: .leading,
                            geometry: geometry,
                            visibleCount: visiblePerColumn,
                            onContinue: onContinue,
                            onDelete: onDelete,
                            isExpanded: $leftDrawerExpanded
                        )
                    } else {
                        Color.clear.frame(width: device.isPhone ? 130 : 160)
                    }

                    // Hero Card
                    if let heroCharacter = allCharacters.first {
                        HeroCharacterCard(
                            metadata: heroCharacter,
                            isCloudOnly: cloudOnlyCharacters.contains(heroCharacter.characterName),
                            geometry: geometry,
                            onContinue: { onContinue(heroCharacter.characterName) },
                            onDelete: { onDelete(heroCharacter) }
                        )
                        .frame(maxWidth: min(cardWidth, 340))
                    }

                    // Right column
                    if !rightSaves.isEmpty {
                        StackedSaveColumn(
                            saves: rightSaves,
                            cloudOnlyCharacters: cloudOnlyCharacters,
                            side: .trailing,
                            geometry: geometry,
                            visibleCount: visiblePerColumn,
                            onContinue: onContinue,
                            onDelete: onDelete,
                            isExpanded: $rightDrawerExpanded
                        )
                    } else {
                        Color.clear.frame(width: device.isPhone ? 130 : 160)
                    }
                }

                // Separator + New Game button
                VStack(spacing: spacing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                        .frame(maxWidth: min(cardWidth, 300))

                    ResponsiveButton(
                        title: "New Game",
                        icon: "plus.circle.fill",
                        color: .nethackSuccess,
                        geometry: geometry,
                        action: onNewGame
                    )
                    .frame(maxWidth: min(cardWidth, 200))
                }
            }

            // Backdrop for dismissing drawers
            if anyDrawerOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.05)) {
                            leftDrawerExpanded = false
                            rightDrawerExpanded = false
                        }
                    }
                    .zIndex(50)
            }

            // Left drawer overlay
            if leftDrawerExpanded {
                ExpandedSaveDrawer(
                    saves: leftSaves,
                    cloudOnlyCharacters: cloudOnlyCharacters,
                    side: .leading,
                    geometry: geometry,
                    onContinue: { name in
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                            leftDrawerExpanded = false
                        }
                        onContinue(name)
                    },
                    onDelete: onDelete,
                    onClose: {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.05)) {
                            leftDrawerExpanded = false
                        }
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                .zIndex(100)
            }

            // Right drawer overlay
            if rightDrawerExpanded {
                ExpandedSaveDrawer(
                    saves: rightSaves,
                    cloudOnlyCharacters: cloudOnlyCharacters,
                    side: .trailing,
                    geometry: geometry,
                    onContinue: { name in
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                            rightDrawerExpanded = false
                        }
                        onContinue(name)
                    },
                    onDelete: onDelete,
                    onClose: {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.05)) {
                            rightDrawerExpanded = false
                        }
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                .zIndex(100)
            }
        }
    }
}

// MARK: - No Save Section Extension

extension SimplifiedCharacterSelectionView {
    /// No save section - Shows when no save exists (RESPONSIVE)
    /// Uses horizontal layout on iPhone landscape for space efficiency
    func noSaveSection(geometry: GeometryProxy, isCompact: Bool) -> some View {
        let device = DeviceCategory.detect(for: geometry)
        let iconSize: CGFloat = isCompact ? 40 : (device.isPhone ? 60 : 80)
        let spacing = isCompact ? ResponsiveLayout.spacing(.small, for: geometry) : ResponsiveLayout.spacing(.large, for: geometry)
        let bodySize = ResponsiveLayout.fontSize(.body, for: geometry)
        let headlineSize = ResponsiveLayout.fontSize(.headline, for: geometry)
        let maxButtonWidth = ResponsiveLayout.heroCardWidth(in: geometry)

        return Group {
            if isCompact {
                // Horizontal layout for iPhone landscape
                HStack(spacing: ResponsiveLayout.spacing(.large, for: geometry)) {
                    // Left: Icon + Text
                    HStack(spacing: ResponsiveLayout.spacing(.medium, for: geometry)) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: iconSize))
                            .foregroundColor(.white.opacity(0.4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Save Available")
                                .font(.system(size: headlineSize, weight: .semibold))
                                .foregroundColor(.white)

                            Text("Begin your adventure")
                                .font(.system(size: bodySize))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    // Right: Button
                    ResponsiveButton(
                        title: "New Game",
                        icon: "plus.circle.fill",
                        color: .nethackSuccess,
                        geometry: geometry,
                        action: startNewGame
                    )
                    .frame(width: 200)
                }
            } else {
                // Vertical layout for tablets and portrait
                VStack(spacing: spacing) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: iconSize))
                        .foregroundColor(.white.opacity(0.4))

                    VStack(spacing: ResponsiveLayout.spacing(.tiny, for: geometry)) {
                        Text("No Save Available")
                            .font(.system(size: headlineSize, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Begin your adventure")
                            .font(.system(size: bodySize))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    ResponsiveButton(
                        title: "New Game",
                        icon: "plus.circle.fill",
                        color: .nethackSuccess,
                        geometry: geometry,
                        action: startNewGame
                    )
                    .frame(maxWidth: maxButtonWidth)
                }
            }
        }
    }

    // MARK: - Actions

    /// Load ALL character data on appear (local + cloud-only placeholders)
    func loadCharacterData() {
        logger.info("[CharacterSelection] Loading all character data...")

        // Get ALL saved character names (local)
        let characterNames = coordinator.listSavedCharacters()

        // Load metadata for local characters
        var loadedCharacters: [CharacterMetadata] = []
        for name in characterNames {
            guard let metadata = CharacterMetadata.load(for: name) else {
                logger.warning("[CharacterSelection] Failed to load metadata for '\(name)'")
                continue
            }
            loadedCharacters.append(metadata)
        }

        // Add cloud-only characters as placeholders (not downloaded yet)
        let cloudOnlyNames = coordinator.getCloudOnlyCharacters()
        for name in cloudOnlyNames {
            let placeholder = CharacterMetadata.cloudPlaceholder(characterName: name)
            loadedCharacters.append(placeholder)
        }

        logger.info("[CharacterSelection] Found \(characterNames.count) local + \(cloudOnlyNames.count) cloud-only")

        // Sort: local characters by lastSaved (descending), cloud-only at the end
        loadedCharacters.sort { lhs, rhs in
            let lhsIsCloud = coordinator.isCloudOnly(lhs.characterName)
            let rhsIsCloud = coordinator.isCloudOnly(rhs.characterName)

            // Local characters come first
            if lhsIsCloud != rhsIsCloud {
                return !lhsIsCloud
            }

            // Within same category, sort by lastSaved (descending)
            return lhs.lastSaved > rhs.lastSaved
        }

        // Set state
        hasExistingSave = !loadedCharacters.isEmpty
        allCharacters = loadedCharacters

        logger.info("[CharacterSelection] ✅ Loaded \(loadedCharacters.count) character(s)")
    }

    /// Select random background on appear
    func selectRandomBackground() {
        guard let randomBackground = backgroundImages.randomElement() else { return }
        selectedBackground = randomBackground
        logger.info("[CharacterSelection] Selected background: \(randomBackground)")
    }

    /// Continue existing game for specific character
    /// For cloud-only characters, downloads first then continues
    func continueGame(characterName: String) {
        print("[CharacterSelection] >>> BUTTON TAPPED - continueGame called for '\(characterName)'")
        print("[CharacterSelection] >>> isCloudOnly check: \(coordinator.isCloudOnly(characterName))")
        logger.info("[CharacterSelection] Continuing game for '\(characterName)'...")

        // Check if this is a cloud-only character that needs downloading
        if coordinator.isCloudOnly(characterName) {
            print("[CharacterSelection] >>> Taking CLOUD-ONLY path")
            logger.info("[CharacterSelection] Cloud-only character - downloading first...")
            downloadingCharacter = characterName
            isDownloading = true
            downloadError = nil

            // Phase 6: Store task for cancellation support
            downloadTask = Task {
                do {
                    // Check for cancellation before starting
                    try Task.checkCancellation()

                    try await coordinator.downloadCharacter(characterName)

                    // Check for cancellation after download
                    try Task.checkCancellation()

                    logger.info("[CharacterSelection] ✅ Download complete, loading character...")

                    await MainActor.run {
                        isDownloading = false
                        downloadingCharacter = nil
                        downloadTask = nil

                        // Reload to get full metadata
                        loadCharacterData()

                        // Now continue with the downloaded character
                        loadAndStartGame(characterName: characterName)
                    }
                } catch is CancellationError {
                    logger.info("[CharacterSelection] Download cancelled by user")
                    // State already cleared by cancel handler
                } catch {
                    logger.error("[CharacterSelection] Failed to download: \(error.localizedDescription)")
                    await MainActor.run {
                        isDownloading = false
                        downloadingCharacter = nil
                        downloadTask = nil
                        downloadError = "Failed to download '\(characterName)' from iCloud. Please check your connection."
                    }
                }
            }
            return
        }

        // Local character - load directly
        print("[CharacterSelection] >>> Taking LOCAL path - calling loadAndStartGame")
        loadAndStartGame(characterName: characterName)
    }

    /// Actually load the game for a (local) character
    private func loadAndStartGame(characterName: String) {
        print("[CharacterSelection] >>> loadAndStartGame called for '\(characterName)'")
        print("[CharacterSelection] >>> State machine state: \(GameLifecycleStateMachine.shared.state)")
        guard coordinator.continueCharacter(characterName: characterName) else {
            print("[CharacterSelection] >>> continueCharacter returned FALSE")
            logger.error("[CharacterSelection] Failed to load character '\(characterName)'")
            return
        }

        print("[CharacterSelection] >>> continueCharacter returned TRUE - setting isGameRunning")
        logger.info("[CharacterSelection] ✅ Character loaded successfully")
        gameManager.isGameRunning = true
        print("[CharacterSelection] >>> isGameRunning set to: \(gameManager.isGameRunning)")
        gameManager.updateGameState()
        print("[CharacterSelection] >>> updateGameState called")
    }

    /// Start new game (opens character creation)
    func startNewGame() {
        logger.info("[CharacterSelection] Starting new game...")
        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.2)) {
            showCharacterCreation = true
        }
    }

    /// Delete selected character from local device only (keeps iCloud copy)
    private func deleteCharacterLocal() {
        logger.info("[CharacterSelection] Deleting character locally...")

        guard let character = characterToDelete else {
            logger.error("[CharacterSelection] No character selected for deletion")
            return
        }

        let characterName = character.characterName

        guard coordinator.deleteCharacterLocal(characterName) else {
            logger.error("[CharacterSelection] Failed to delete character '\(characterName)' locally")
            return
        }

        logger.info("[CharacterSelection] ✅ Character '\(characterName)' deleted locally (iCloud copy preserved)")
        characterToDelete = nil

        // Reload data
        loadCharacterData()
    }

    /// Delete selected character from both device and iCloud
    private func deleteCharacterEverywhere() {
        logger.info("[CharacterSelection] Deleting character everywhere...")

        guard let character = characterToDelete else {
            logger.error("[CharacterSelection] No character selected for deletion")
            return
        }

        let characterName = character.characterName

        // Use async delete for iCloud
        Task {
            let success = await coordinator.deleteCharacterEverywhere(characterName)
            if !success {
                logger.error("[CharacterSelection] Failed to delete character '\(characterName)' everywhere")
                return
            }

            logger.info("[CharacterSelection] ✅ Character '\(characterName)' deleted everywhere")
            await MainActor.run {
                characterToDelete = nil
                // Reload data
                loadCharacterData()
            }
        }
    }
}

// MARK: - Character Card Component

// MARK: - Hero Character Card (Last Played - Full Info)

/// Large prominent card for the last played character
/// Shows full info: screenshot, name, level, role, HP, dungeon level, turns
/// Displays SyncStatusBadge in top-right corner for iCloud sync state
struct HeroCharacterCard: View {
    let metadata: CharacterMetadata
    let isCloudOnly: Bool
    let geometry: GeometryProxy
    let onContinue: () -> Void
    let onDelete: () -> Void

    @State private var screenshot: UIImage?
    @State private var isContinuePressed = false
    @State private var isDeletePressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var screenshotHeight: CGFloat {
        device.isPhone ? 140 : 200
    }

    var body: some View {
        VStack(spacing: 0) {
            // Screenshot area with overlays
            ZStack(alignment: .topTrailing) {
                // Main content with bottom-leading info
                ZStack(alignment: .bottomLeading) {
                    // Screenshot or cloud placeholder
                    if isCloudOnly {
                    // Cloud-only: Show iCloud placeholder
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.nethackGray200],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: screenshotHeight)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "icloud.and.arrow.down.fill")
                                    .font(.system(size: device.isPhone ? 32 : 44))
                                    .foregroundColor(.blue.opacity(0.7))
                                Text("Tap to Download")
                                    .font(.system(size: device.isPhone ? 12 : 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                } else if let screenshot = screenshot {
                    Image(uiImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: screenshotHeight)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.nethackGray200)
                        .frame(height: screenshotHeight)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: device.isPhone ? 28 : 40))
                                    .foregroundColor(.white.opacity(0.2))
                                Text("No Screenshot")
                                    .font(.system(size: device.isPhone ? 11 : 13))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                }

                // Dark gradient for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)

                // Character info overlay - LEFT ALIGNED (critical for roguelike)
                VStack(alignment: .leading, spacing: 4) {
                    // Name + Cloud/Level badge
                    HStack(spacing: 8) {
                        Text(metadata.characterName)
                            .font(.system(size: device.isPhone ? 18 : 22, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if isCloudOnly {
                            // Cloud badge
                            HStack(spacing: 4) {
                                Image(systemName: "icloud.fill")
                                    .font(.system(size: device.isPhone ? 11 : 13))
                                Text("iCloud")
                                    .font(.system(size: device.isPhone ? 12 : 14, weight: .semibold))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.25))
                            )
                        } else {
                            Text("Lv \(metadata.level)")
                                .font(.system(size: device.isPhone ? 13 : 15, weight: .bold))
                                .foregroundColor(.nethackAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.nethackAccent.opacity(0.25))
                                )
                        }
                    }

                    if isCloudOnly {
                        // Cloud character: minimal info
                        Text("Stored in iCloud")
                            .font(.system(size: device.isPhone ? 13 : 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        // Local character: full info
                        // Race + Role
                        Text("\(metadata.race) \(metadata.role)")
                            .font(.system(size: device.isPhone ? 13 : 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))

                        // Stats row: HP + Dungeon Level + Turns
                        HStack(spacing: device.isPhone ? 12 : 16) {
                            // HP
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: device.isPhone ? 11 : 13))
                                    .foregroundColor(.red)
                                Text("\(metadata.hp)/\(metadata.hpmax)")
                                    .font(.system(size: device.isPhone ? 12 : 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }

                            // Dungeon Level
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: device.isPhone ? 11 : 13))
                                    .foregroundColor(.cyan)
                                Text("Dlvl:\(metadata.dungeonLevel)")
                                    .font(.system(size: device.isPhone ? 12 : 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }

                            // Turns
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: device.isPhone ? 11 : 13))
                                    .foregroundColor(.orange)
                                Text("\(metadata.turns)")
                                    .font(.system(size: device.isPhone ? 12 : 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(14)
                } // End inner ZStack (bottomLeading)

                // Sync status badge - top right
                SyncStatusBadge(status: metadata.syncStatus)
                    .padding(8)
            } // End outer ZStack (topTrailing)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.nethackAccent.opacity(0.3), lineWidth: 1)
            )

            // Action buttons - 44pt minimum touch targets (Apple HIG)
            HStack(spacing: 10) {
                // Continue/Download button - prominent
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Image(systemName: isCloudOnly ? "icloud.and.arrow.down.fill" : "play.fill")
                            .font(.system(size: device.isPhone ? 16 : 18))
                        Text(isCloudOnly ? "Download & Play" : "Continue Quest")
                            .font(.system(size: device.isPhone ? 15 : 17, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: isCloudOnly
                                        ? [Color.blue, Color.blue.opacity(0.7)]
                                        : [Color.nethackAccent, Color.nethackAccent.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .scaleEffect(isContinuePressed ? AnimationConstants.pressScale : 1.0)
                    .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isContinuePressed)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isContinuePressed = true }
                        .onEnded { _ in isContinuePressed = false }
                )
                .accessibilityLabel(isCloudOnly ? "Download \(metadata.characterName) from iCloud" : "Continue game as \(metadata.characterName)")

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: device.isPhone ? 16 : 18))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.15))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .scaleEffect(isDeletePressed ? AnimationConstants.pressScale : 1.0)
                        .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isDeletePressed)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isDeletePressed = true }
                        .onEnded { _ in isDeletePressed = false }
                )
                .accessibilityLabel("Delete \(metadata.characterName)")
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.nethackAccent.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: Color.nethackAccent.opacity(0.2), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metadata.characterName), Level \(metadata.level) \(metadata.role), \(metadata.hp) of \(metadata.hpmax) HP, Dungeon level \(metadata.dungeonLevel)")
        .onAppear {
            screenshot = ScreenshotService.shared.loadScreenshot(for: metadata.characterName)
        }
    }
}

// MARK: - Compact Character Card (Other Saves)

/// Compact card for secondary saves - shows only essential info
/// Name + Level badge + SyncStatusBadge, tap to continue
struct CompactCharacterCard: View {
    let metadata: CharacterMetadata
    let isCloudOnly: Bool
    let geometry: GeometryProxy
    let onContinue: () -> Void
    let onDelete: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    var body: some View {
        Button(action: onContinue) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    // Name
                    HStack(spacing: 4) {
                        if isCloudOnly {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: device.isPhone ? 12 : 14))
                                .foregroundColor(.blue.opacity(0.8))
                        }
                        Text(metadata.characterName)
                            .font(.system(size: device.isPhone ? 14 : 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    if isCloudOnly {
                        // Cloud character: show tap to download
                        Text("Tap to download")
                            .font(.system(size: device.isPhone ? 11 : 12))
                            .foregroundColor(.blue.opacity(0.7))
                    } else {
                        // Local character: show level + role
                        HStack(spacing: 6) {
                            Text("Lv \(metadata.level)")
                                .font(.system(size: device.isPhone ? 12 : 14, weight: .bold))
                                .foregroundColor(.nethackAccent)

                            Text(metadata.role)
                                .font(.system(size: device.isPhone ? 11 : 13))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }

                        // Dungeon level indicator
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: device.isPhone ? 10 : 11))
                                .foregroundColor(.cyan.opacity(0.8))
                            Text("Dlvl:\(metadata.dungeonLevel)")
                                .font(.system(size: device.isPhone ? 11 : 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                Spacer(minLength: 6)

                // Sync status badge - right side
                SyncStatusBadge(status: metadata.syncStatus)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isCloudOnly ? Color.blue.opacity(0.08) : Color.white.opacity(0.05))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isCloudOnly ? Color.blue.opacity(0.3) : Color.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
            .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(isCloudOnly ? "\(metadata.characterName), stored in iCloud" : "\(metadata.characterName), Level \(metadata.level) \(metadata.role)")
        .accessibilityHint(isCloudOnly ? "Double tap to download from iCloud" : "Double tap to continue, long press to delete")
    }
}

// MARK: - Stacked Save Column

/// Stacked save column with overflow indicator (drawer rendered at parent level)
struct StackedSaveColumn: View {
    let saves: [CharacterMetadata]
    let cloudOnlyCharacters: Set<String>
    let side: HorizontalEdge
    let geometry: GeometryProxy
    let visibleCount: Int
    let onContinue: (String) -> Void
    let onDelete: (CharacterMetadata) -> Void
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var visibleSaves: [CharacterMetadata] {
        Array(saves.prefix(visibleCount))
    }

    private var overflowCount: Int {
        max(0, saves.count - visibleCount)
    }

    private var cardWidth: CGFloat {
        device.isPhone ? 130 : 160
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(visibleSaves, id: \.characterName) { metadata in
                CompactCharacterCard(
                    metadata: metadata,
                    isCloudOnly: cloudOnlyCharacters.contains(metadata.characterName),
                    geometry: geometry,
                    onContinue: { onContinue(metadata.characterName) },
                    onDelete: { onDelete(metadata) }
                )
                .frame(width: cardWidth)
            }

            // Overflow indicator
            if overflowCount > 0 {
                OverflowIndicator(
                    count: overflowCount,
                    isExpanded: isExpanded,
                    isPhone: device.isPhone
                ) {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.12)) {
                        isExpanded.toggle()
                    }
                    HapticManager.shared.tap()
                }
            }
        }
    }
}

// MARK: - Overflow Indicator

/// Glass-morphic badge showing overflow count
struct OverflowIndicator: View {
    let count: Int
    let isExpanded: Bool
    let isPhone: Bool
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("+\(count)")
                    .font(.system(size: isPhone ? 12 : 13, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .contentShape(Capsule())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(reduceMotion ? nil : .spring(duration: 0.2), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("\(count) more saved games")
        .accessibilityHint("Double tap to show all saves")
    }
}

// MARK: - Expanded Save Drawer

/// Full list drawer that slides out from side
struct ExpandedSaveDrawer: View {
    let saves: [CharacterMetadata]
    let cloudOnlyCharacters: Set<String>
    let side: HorizontalEdge
    let geometry: GeometryProxy
    let onContinue: (String) -> Void
    let onDelete: (CharacterMetadata) -> Void
    let onClose: () -> Void

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var drawerWidth: CGFloat {
        device.isPhone ? 200 : 260
    }

    private var offsetX: CGFloat {
        side == .leading ? (device.isPhone ? 135 : 165) : -(device.isPhone ? 135 : 165)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("All Saves")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .contentShape(Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)

            // Scrollable save list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(saves, id: \.characterName) { metadata in
                        DrawerSaveRow(
                            metadata: metadata,
                            isCloudOnly: cloudOnlyCharacters.contains(metadata.characterName),
                            isPhone: device.isPhone,
                            onContinue: {
                                onContinue(metadata.characterName)
                                onClose()
                            },
                            onDelete: { onDelete(metadata) }
                        )
                    }
                }
                .padding(10)
            }
        }
        .frame(width: drawerWidth)
        .frame(maxHeight: min(geometry.size.height * 0.75, 350))
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 20, x: side == .leading ? 5 : -5, y: 0)
        .offset(x: offsetX)
    }
}

// MARK: - Drawer Save Row

/// Compact row for expanded drawer list
struct DrawerSaveRow: View {
    let metadata: CharacterMetadata
    let isCloudOnly: Bool
    let isPhone: Bool
    let onContinue: () -> Void
    let onDelete: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onContinue) {
            HStack(spacing: 10) {
                // Role icon or cloud icon
                if isCloudOnly {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: isPhone ? 16 : 18))
                        .foregroundColor(.blue.opacity(0.8))
                        .frame(width: 24)
                } else {
                    Image(systemName: roleIcon(for: metadata.role))
                        .font(.system(size: isPhone ? 16 : 18))
                        .foregroundColor(.nethackAccent)
                        .frame(width: 24)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.characterName)
                        .font(.system(size: isPhone ? 13 : 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if isCloudOnly {
                        Text("Tap to download")
                            .font(.system(size: isPhone ? 11 : 12))
                            .foregroundColor(.blue.opacity(0.7))
                    } else {
                        Text("Lv\(metadata.level) \(metadata.role)")
                            .font(.system(size: isPhone ? 11 : 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Dungeon level (only for local characters)
                if !isCloudOnly {
                    Text("D:\(metadata.dungeonLevel)")
                        .font(.system(size: isPhone ? 11 : 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCloudOnly ? Color.blue.opacity(0.08) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isCloudOnly ? Color.blue.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : .spring(duration: 0.15), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func roleIcon(for role: String) -> String {
        switch role.lowercased() {
        case "valkyrie": return "shield.fill"
        case "wizard": return "wand.and.stars"
        case "rogue": return "eye.slash"
        case "knight": return "chevron.up.circle.fill"
        case "monk": return "figure.martial.arts"
        case "priest", "priestess": return "cross.fill"
        case "ranger": return "scope"
        case "samurai": return "bolt.horizontal.fill"
        case "barbarian": return "flame.fill"
        case "healer": return "cross.case.fill"
        case "tourist": return "camera.fill"
        case "caveman", "cavewoman": return "mountain.2.fill"
        case "archeologist": return "magnifyingglass"
        default: return "person.fill"
        }
    }
}

// MARK: - Legacy Character Card (for compatibility)

/// A compact character card for horizontal scrolling list
/// Shows screenshot, name, level, role, and action buttons
struct CharacterCard: View {
    let metadata: CharacterMetadata
    let geometry: GeometryProxy
    let onContinue: () -> Void
    let onDelete: () -> Void

    @State private var screenshot: UIImage?
    @State private var isContinuePressed = false
    @State private var isDeletePressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Screenshot area with overlay
            ZStack(alignment: .bottomLeading) {
                // Screenshot or placeholder
                if let screenshot = screenshot {
                    Image(uiImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: device.isPhone ? 110 : 170)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.nethackGray200)
                        .frame(height: device.isPhone ? 110 : 170)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: device.isPhone ? 24 : 32))
                                    .foregroundColor(.white.opacity(0.2))
                                Text("No Screenshot")
                                    .font(.system(size: device.isPhone ? 10 : 12))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                }

                // Dark gradient for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)

                // Character info overlay - LEFT ALIGNED (critical for roguelike)
                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata.characterName)
                        .font(.system(size: device.isPhone ? 15 : 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.5), radius: 2)

                    HStack(spacing: 6) {
                        // Level badge
                        Text("Lv \(metadata.level)")
                            .font(.system(size: device.isPhone ? 11 : 13, weight: .semibold))
                            .foregroundColor(.nethackAccent)

                        // Role
                        Text(metadata.role)
                            .font(.system(size: device.isPhone ? 11 : 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )

            // Action buttons - 44pt minimum touch targets (Apple HIG)
            HStack(spacing: 8) {
                // Continue button
                Button(action: onContinue) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: device.isPhone ? 14 : 16))
                        Text("Continue")
                            .font(.system(size: device.isPhone ? 13 : 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)  // Apple HIG minimum
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.nethackAccent.opacity(0.2))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.nethackAccent.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                    .scaleEffect(isContinuePressed ? AnimationConstants.pressScale : 1.0)
                    .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isContinuePressed)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isContinuePressed = true }
                        .onEnded { _ in isContinuePressed = false }
                )
                .accessibilityLabel("Continue game as \(metadata.characterName)")

                // Delete button - 44pt minimum touch target
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: device.isPhone ? 14 : 16))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(width: 44, height: 44)  // Apple HIG minimum
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.red.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .contentShape(Rectangle())
                        .scaleEffect(isDeletePressed ? AnimationConstants.pressScale : 1.0)
                        .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isDeletePressed)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isDeletePressed = true }
                        .onEnded { _ in isDeletePressed = false }
                )
                .accessibilityLabel("Delete \(metadata.characterName)")
                .accessibilityHint("Double tap to delete this character permanently")
            }
            .padding(.top, 10)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    // Subtle top highlight for glass depth
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metadata.characterName), Level \(metadata.level) \(metadata.role)")
        .onAppear {
            screenshot = ScreenshotService.shared.loadScreenshot(for: metadata.characterName)
        }
    }
}

// MARK: - Responsive Button Component

/// A button that adapts to device size while maintaining 44pt minimum touch target
struct ResponsiveButton: View {
    let title: String
    let icon: String
    let color: Color
    let geometry: GeometryProxy
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var fontSize: CGFloat {
        ResponsiveLayout.fontSize(.body, for: geometry)
    }

    private var iconSize: CGFloat {
        switch device {
        case .phone: return 18
        case .tabletCompact: return 20
        case .tablet: return 22
        }
    }

    private var buttonHeight: CGFloat {
        ResponsiveLayout.buttonHeight(for: geometry)
    }

    private var cornerRadius: CGFloat {
        ResponsiveLayout.cornerRadius(for: geometry)
    }

    private var horizontalPadding: CGFloat {
        switch device {
        case .phone: return 12
        case .tabletCompact: return 14
        case .tablet: return 16
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(buttonHeight, 44))  // Apple HIG minimum
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(color.opacity(0.2))
                    )
                    .overlay(
                        // Top highlight for glass depth
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .contentShape(Rectangle())  // Ensure entire area is tappable (SWIFTUI-M-003)
            .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
            .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(title)
    }
}

// MARK: - SwiftUI Preview

#Preview("Character Selection") {
    SimplifiedCharacterSelectionView(gameManager: NetHackGameManager())
}
