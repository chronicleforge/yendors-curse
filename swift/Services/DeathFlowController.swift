//
//  DeathFlowController.swift
//  nethack
//
//  Single orchestrator for the entire death flow.
//  Replaces complex flag management with simple state machine.
//
//  Created: 2025-12-18
//

import SwiftUI
import Combine

/// Death flow state machine - single source of truth
@MainActor
@Observable
final class DeathFlowController {

    // MARK: - State Machine

    /// Death flow phases - replaces 6+ flags with ONE property
    enum DeathPhase: Equatable {
        case alive           // Normal gameplay
        case animating       // Animation running, background tasks active
        case showing         // Death screen visible
    }

    // MARK: - Single Source of Truth

    /// Current phase - the ONLY state property needed
    private(set) var phase: DeathPhase = .alive

    /// Death info - populated when data arrives from C
    private(set) var deathInfo: DeathInfo?

    /// Animation progress (0.0 to 1.0)
    private(set) var animationProgress: CGFloat = 0

    /// Type of game end (died, escaped, ascended)
    private(set) var gameEndType: GameEndType = .died

    // MARK: - Internal State

    /// Track if death data has arrived
    private var deathDataReceived = false

    /// Track if animation minimum time has passed
    private var animationComplete = false

    /// Minimum animation duration (masks data collection)
    private let animationDuration: TimeInterval = 2.0

    /// Notification observers
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dependencies

    private let coordinator: SimplifiedSaveLoadCoordinator
    private let bridge: NetHackBridge

    // MARK: - Initialization

    init(coordinator: SimplifiedSaveLoadCoordinator = .shared,
         bridge: NetHackBridge = .shared) {
        self.coordinator = coordinator
        self.bridge = bridge
        setupNotificationObservers()
        print("[DeathFlow] Controller initialized")
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Early death animation trigger (from C callback)
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NetHackDeathAnimationStart"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[DeathFlow] 📬 Received NetHackDeathAnimationStart")
            self?.onDeathDetected()
        }

        // Death data ready (from game thread end)
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NetHackPlayerDied"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("[DeathFlow] 📬 Received NetHackPlayerDied")
            if let deathInfo = notification.object as? DeathInfo {
                self?.onDeathDataReceived(deathInfo)
            } else {
                print("[DeathFlow] ⚠️ No DeathInfo in notification")
                self?.onDeathDataReceived(DeathInfo())
            }
        }

        print("[DeathFlow] ✅ Notification observers setup")
    }

    // MARK: - Death Flow Entry Point

    /// Called IMMEDIATELY when death is detected
    /// Animation starts NOW, cleanup runs in background
    func onDeathDetected() {
        // Guard: prevent double-trigger
        guard phase == .alive else {
            print("[DeathFlow] ⚠️ Already in death flow (phase=\(phase)), ignoring")
            return
        }

        print("[DeathFlow] ========================================")
        print("[DeathFlow] ☠️ DEATH DETECTED - STARTING FLOW")
        print("[DeathFlow] ========================================")

        // IMMEDIATE: Transition to animating phase
        phase = .animating
        animationProgress = 0
        deathDataReceived = false
        animationComplete = false

        // IMMEDIATE: Start animation (UI will react to phase change)
        startAnimation()

        // BACKGROUND: Run cleanup tasks in parallel
        Task {
            await performBackgroundCleanup()
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        print("[DeathFlow] 🎬 Starting death animation")

        // Animate progress from 0 to 1 over duration
        withAnimation(.easeInOut(duration: animationDuration)) {
            animationProgress = 1.0
        }

        // Mark animation complete after duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(animationDuration * 1_000_000_000))
            await MainActor.run {
                self.animationComplete = true
                print("[DeathFlow] ✅ Animation complete")
                self.checkReadyToShow()
            }
        }
    }

    // MARK: - Background Cleanup

    private func performBackgroundCleanup() async {
        print("[DeathFlow] 🧹 Starting background cleanup...")

        // FIRST: Delete save file (no waiting!)
        await deleteSaveFile()

        // Note: Dylib unload happens AFTER we get death data
        // (can't unload while C code is still collecting data)

        print("[DeathFlow] ✅ Background cleanup started")
    }

    private func deleteSaveFile() async {
        guard let character = coordinator.activeCharacter else {
            print("[DeathFlow] ⚠️ No active character - skipping save deletion")
            return
        }

        print("[DeathFlow] 🗑️ Deleting save for '\(character)'...")

        // Delete LOCAL save first
        let localSuccess = coordinator.deleteCharacterSave(character)
        if localSuccess {
            print("[DeathFlow] ✅ Local save file deleted for '\(character)'")
        } else {
            print("[DeathFlow] ⚠️ Failed to delete local save (may not exist)")
        }

        // CRITICAL: Also delete from iCloud to prevent re-download
        let iCloudSuccess = await iCloudStorageManager.shared.deleteCharacterSave(characterName: character)
        if iCloudSuccess {
            print("[DeathFlow] ✅ iCloud save deleted for '\(character)'")
        } else {
            print("[DeathFlow] ⚠️ Failed to delete iCloud save")
        }
    }

    // MARK: - Death Data Received

    private func onDeathDataReceived(_ info: DeathInfo) {
        print("[DeathFlow] 📊 Death data received:")
        print("[DeathFlow]   Score: \(info.finalScore)")
        print("[DeathFlow]   Message: \(info.deathMessage)")
        print("[DeathFlow]   Reason: \(info.deathReason)")

        deathInfo = info
        deathDataReceived = true

        // Detect game end type from death reason
        let reason = info.deathReason.lowercased()
        if reason.hasPrefix("escaped") {
            gameEndType = .escaped
            print("[DeathFlow] 🏃 Game end type: ESCAPED")
        } else if reason.hasPrefix("ascended") {
            gameEndType = .ascended
            print("[DeathFlow] 👑 Game end type: ASCENDED")
        } else {
            gameEndType = .died
            print("[DeathFlow] ☠️ Game end type: DIED")
        }

        // Now safe to unload dylib (C done collecting data)
        print("[DeathFlow] 🔄 Unloading dylib (data captured)...")
        bridge.unloadDylib()
        print("[DeathFlow] ✅ Dylib unloaded")

        // Reset coordinator state (uses state machine internally)
        coordinator.reset()

        checkReadyToShow()
    }

    // MARK: - Ready Check

    private func checkReadyToShow() {
        // Both conditions must be met
        guard animationComplete && deathDataReceived else {
            print("[DeathFlow] Waiting... animation=\(animationComplete), data=\(deathDataReceived)")
            return
        }

        print("[DeathFlow] ========================================")
        print("[DeathFlow] ✅ SHOWING DEATH SCREEN")
        print("[DeathFlow] ========================================")

        phase = .showing
    }

    // MARK: - Actions

    /// User taps "Play Again" - start fresh game
    func playAgain() {
        print("[DeathFlow] 🎮 Play Again requested")
        reset()

        // Start new game will be triggered by caller
    }

    /// User taps "Return to Menu"
    func returnToMenu() {
        print("[DeathFlow] 🏠 Return to Menu requested")
        reset()
    }

    // MARK: - Reset

    /// Reset all state for fresh start
    func reset() {
        print("[DeathFlow] 🔄 Resetting state")
        phase = .alive
        deathInfo = nil
        animationProgress = 0
        deathDataReceived = false
        animationComplete = false
        gameEndType = .died
        coordinator.reset()
        print("[DeathFlow] ✅ State reset complete")
    }

    // MARK: - Computed Properties

    /// Whether death screen should be visible
    var isDeathScreenVisible: Bool {
        phase == .showing
    }

    /// Whether death animation should be visible
    var isAnimationVisible: Bool {
        phase == .animating
    }
}
