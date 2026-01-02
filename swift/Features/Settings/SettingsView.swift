import SwiftUI

/// Comprehensive Settings View for NetHack iOS
///
/// Provides:
/// - iCloud Sync toggle with clear explanation
/// - Sync status indicators
/// - Help/Info resources
/// - Future settings expansion
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var coordinator = SimplifiedSaveLoadCoordinator.shared
    @ObservedObject private var iCloudManager = iCloudStorageManager.shared
    @ObservedObject private var userPrefs = UserPreferencesManager.shared

    @State private var showCloudSyncInfo = false
    @State private var showDisableConfirmation = false

    // 7-tap hidden developer mode activation
    @State private var versionTapCount = 0
    @State private var lastTapTime = Date()
    @State private var showDeveloperSection = false

    // Autopickup settings (Progressive Disclosure - collapsed by default)
    @State private var showAutopickupDetails = false
    @State private var autopickupCategories: [AutopickupCategory] = UserPreferencesManager.defaultAutopickupCategories

    // MARK: - Responsive Layout (SWIFTUI-L-004)

    private var isSmallDevice: Bool {
        UIScreen.main.bounds.width < 400
    }

    private var horizontalPadding: CGFloat {
        isSmallDevice ? 16 : 20
    }

    private var contentTopPadding: CGFloat {
        isSmallDevice ? 8 : 20
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.nethackGray100
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // MARK: - iCloud Sync Section
                        settingsSection(title: "Cloud Sync") {
                            VStack(spacing: 16) {
                                // Toggle with status
                                HStack(spacing: 12) {
                                    Image(systemName: "icloud.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(coordinator.iCloudSyncEnabled ? .blue : .nethackGray500)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("iCloud Sync")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(.white)

                                        Text(coordinator.iCloudSyncEnabled ? "Enabled" : "Disabled")
                                            .font(.system(size: 14))
                                            .foregroundColor(.nethackGray600)
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { coordinator.iCloudSyncEnabled },
                                        set: { newValue in
                                            if newValue {
                                                // Enable sync
                                                coordinator.iCloudSyncEnabled = true
                                            } else {
                                                // Show confirmation before disabling
                                                showDisableConfirmation = true
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(.blue)
                                }

                                // Explanation
                                Text("Automatically backup your saves to iCloud. Continue your adventures on any device.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.nethackGray600)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                // Status indicator
                                if coordinator.iCloudSyncEnabled {
                                    HStack(spacing: 8) {
                                        Image(systemName: iCloudManager.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(iCloudManager.isAvailable ? .green : .orange)

                                        Text(iCloudManager.isAvailable ? "iCloud Available" : "iCloud Not Available")
                                            .font(.system(size: 13))
                                            .foregroundColor(.nethackGray600)

                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.nethackGray200.opacity(0.5))
                                    )
                                }

                                // Info button
                                Button(action: {
                                    showCloudSyncInfo = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 14))
                                        Text("Learn More About iCloud Sync")
                                            .font(.system(size: 14))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                    }
                                    .foregroundColor(.nethackAccent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                            }
                        }

                        // MARK: - Autopickup Section (Progressive Disclosure)
                        autopickupSection

                        // MARK: - Synced Characters Section
                        if coordinator.iCloudSyncEnabled {
                            settingsSection(title: "Synced Characters") {
                                VStack(spacing: 12) {
                                    let characters = coordinator.listSavedCharacters()

                                    if characters.isEmpty {
                                        Text("No characters yet. Your saves will sync automatically.")
                                            .font(.system(size: 14))
                                            .foregroundColor(.nethackGray600)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        ForEach(characters, id: \.self) { characterName in
                                            characterSyncRow(characterName: characterName)
                                        }
                                    }
                                }
                            }
                        }

                        // MARK: - About Section
                        settingsSection(title: "About") {
                            VStack(spacing: 12) {
                                // Version row with 7-tap activation
                                infoRow(icon: "gamecontroller.fill", title: "Yendor's Curse", value: "v1.0.0")
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        handleVersionTap()
                                    }

                                infoRow(icon: "hammer.fill", title: "Built on NetHack", value: "3.7.0")
                            }
                        }

                        // MARK: - Developer Section (Hidden until 7-tap)
                        if showDeveloperSection || userPrefs.isDebugModeEnabled() {
                            settingsSection(title: "Developer") {
                                VStack(spacing: 16) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "wand.and.stars")
                                            .font(.system(size: 24))
                                            .foregroundColor(userPrefs.isDebugModeEnabled() ? .purple : .nethackGray500)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Wizard Mode")
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundColor(.white)

                                            Text(userPrefs.isDebugModeEnabled() ? "All powers unlocked" : "Debug & testing")
                                                .font(.system(size: 14))
                                                .foregroundColor(.nethackGray600)
                                        }

                                        Spacer()

                                        Toggle("", isOn: Binding(
                                            get: { userPrefs.isDebugModeEnabled() },
                                            set: { userPrefs.setDebugModeEnabled($0) }
                                        ))
                                        .labelsHidden()
                                        .tint(.purple)
                                    }

                                    Text("Enables wizard mode for new games. Access #wizwish, #wizgenesis, and other debug commands. Synced via iCloud.")
                                        .font(.system(size: 14))
                                        .foregroundColor(.nethackGray600)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Divider()
                                        .background(Color.nethackGray400)
                                        .padding(.vertical, 8)

                                    // iCloud Debug Info
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("iCloud Debug")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.nethackGray600)

                                        Text(iCloudManager.getDebugInfo())
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.nethackGray500)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, contentTopPadding)
                }
            }
            .edgesIgnoringSafeArea(.bottom) // SWIFTUI-HIG-001: Respect SafeArea top, ignore bottom
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.nethackAccent)
                }
            }
        }
        .sheet(isPresented: $showCloudSyncInfo) {
            // Placeholder: CloudSyncInfoSheet removed in rebuild
            Text("Cloud Sync Info (Coming Soon)")
                .padding()
        }
        .alert("Disable iCloud Sync?", isPresented: $showDisableConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Disable", role: .destructive) {
                coordinator.iCloudSyncEnabled = false
            }
        } message: {
            Text("Your saves will remain on this device, but won't sync to other devices. Existing iCloud backups won't be deleted.")
        }
    }

    // MARK: - 7-Tap Developer Mode Activation

    private func handleVersionTap() {
        let now = Date()

        // Reset counter if more than 2 seconds since last tap
        if now.timeIntervalSince(lastTapTime) > 2.0 {
            versionTapCount = 0
        }

        lastTapTime = now
        versionTapCount += 1

        // Show feedback for progress
        if versionTapCount >= 5 && versionTapCount < 7 {
            let remaining = 7 - versionTapCount
            print("[Settings] \(remaining) more tap\(remaining == 1 ? "" : "s") to unlock developer mode")
        }

        // Activate on 7th tap
        if versionTapCount >= 7 {
            withAnimation(.spring(response: 0.3)) {
                showDeveloperSection = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            versionTapCount = 0
            print("[Settings] 🧙 Developer section unlocked!")
        }
    }

    // MARK: - Autopickup Section

    @ViewBuilder
    private var autopickupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with disclosure indicator
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    showAutopickupDetails.toggle()
                }
            }) {
                HStack {
                    Text("AUTOPICKUP")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.nethackGray600)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(showAutopickupDetails ? "Hide" : "Customize")
                            .font(.system(size: 13))
                            .foregroundColor(.nethackAccent)

                        Image(systemName: showAutopickupDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.nethackAccent)
                    }
                }
            }

            VStack(spacing: 0) {
                // Summary row (always visible)
                HStack(spacing: 12) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 24))
                        .foregroundColor(userPrefs.isAutopickupEnabled() ? .nethackSuccess : .nethackGray500)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-Pickup")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)

                        let enabledCount = autopickupCategories.filter { $0.enabled }.count
                        Text("\(enabledCount) categories enabled")
                            .font(.system(size: 14))
                            .foregroundColor(.nethackGray600)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { userPrefs.isAutopickupEnabled() },
                        set: { newValue in
                            userPrefs.setAutopickupEnabled(newValue)
                            // Apply to C engine immediately if game is running
                            AutopickupBridgeService.shared.applyUserPreferences()
                        }
                    ))
                    .labelsHidden()
                    .tint(.nethackSuccess)
                }

                // Explanation
                Text("Automatically collect scrolls, potions, wands, and other valuable items when walking over them.")
                    .font(.system(size: 14))
                    .foregroundColor(.nethackGray600)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)

                // Category toggles (collapsed by default)
                if showAutopickupDetails {
                    Divider()
                        .background(Color.nethackGray400)
                        .padding(.vertical, 12)

                    VStack(spacing: 8) {
                        ForEach(autopickupCategories.indices, id: \.self) { index in
                            autopickupCategoryRow(index: index)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.nethackGray200.opacity(0.7))
            )
        }
        .onAppear {
            autopickupCategories = userPrefs.getAutopickupCategories()
        }
    }

    @ViewBuilder
    private func autopickupCategoryRow(index: Int) -> some View {
        let category = autopickupCategories[index]

        HStack(spacing: 12) {
            // Category icon
            Image(systemName: category.icon)
                .font(.system(size: 18))
                .foregroundColor(category.enabled ? category.color : .nethackGray500)
                .frame(width: 28)

            // Category name
            Text(category.name)
                .font(.system(size: 15))
                .foregroundColor(.white)

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { autopickupCategories[index].enabled },
                set: { newValue in
                    autopickupCategories[index].enabled = newValue
                    userPrefs.setAutopickupCategories(autopickupCategories)
                    // Apply to C engine immediately if game is running
                    AutopickupBridgeService.shared.applyUserPreferences()
                }
            ))
            .labelsHidden()
            .tint(category.color)
        }
        .padding(.vertical, 4)
    }

    // MARK: - View Components

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.nethackGray600)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.nethackGray200.opacity(0.7))
            )
        }
    }

    @ViewBuilder
    private func characterSyncRow(characterName: String) -> some View {
        // Get sync status from CharacterMetadata (derived from timestamps)
        let metadata = CharacterMetadata.load(for: characterName)
        let status = metadata?.syncStatus ?? .localOnly

        HStack(spacing: 12) {
            // Character icon
            ZStack {
                Circle()
                    .fill(Color.nethackGray300)
                    .frame(width: 40, height: 40)

                Text(String(characterName.prefix(1).uppercased()))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }

            // Character name
            Text(characterName)
                .font(.system(size: 15))
                .foregroundColor(.white)

            Spacer()

            // Sync status
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.system(size: 12))
                    .foregroundColor(status.color)

                Text(status.label)
                    .font(.system(size: 13))
                    .foregroundColor(.nethackGray600)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.nethackGray600)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.white)

            Spacer()

            Text(value)
                .font(.system(size: 15))
                .foregroundColor(.nethackGray600)
        }
    }
}

// NOTE: CharacterSyncStatus extension removed - label, icon, color now in CharacterMetadata.swift

// MARK: - Preview

#Preview("Settings View") {
    SettingsView()
}
