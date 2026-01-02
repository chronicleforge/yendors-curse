//
//  FeedbackEngine.swift
//  nethack
//
//  Central feedback system for game-state driven visual and haptic feedback
//  Detects HP changes, status effects, and positive events
//

import SwiftUI
import Combine

/// Central coordinator for game-state feedback (damage, healing, status changes)
@MainActor
final class FeedbackEngine: ObservableObject {
    static let shared = FeedbackEngine()

    // MARK: - Published State (for view binding)

    /// Increment to trigger shake animation
    @Published private(set) var shakeCount: Int = 0

    /// Current shake intensity for the animation
    @Published private(set) var shakeIntensity: FeedbackIntensity = .light

    /// Brief red flash on damage
    @Published private(set) var damageFlashActive: Bool = false

    // MARK: - Private State

    private var isFirstUpdate: Bool = true

    // MARK: - Critical Condition Masks

    /// Bitmask for life-threatening conditions (stoned, slimed, strangled, food poisoned, terminally ill)
    private let criticalConditionMask: UInt = 0x01340080

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Interface

    /// Process a game state change and trigger appropriate feedback
    /// - Parameters:
    ///   - old: Previous player stats (nil on first update)
    ///   - new: Current player stats
    func processStateChange(old: PlayerStats?, new: PlayerStats) {
        // First update - just initialize, no feedback
        guard !isFirstUpdate else {
            isFirstUpdate = false
            return
        }

        guard let old = old else { return }

        // Damage detection
        if new.hp < old.hp {
            handleDamage(old: old, new: new)
        }

        // Healing detection (only if was hurt)
        if new.hp > old.hp && old.hp < old.hpmax {
            handleHealing(old: old, new: new)
        }

        // Level up
        if new.level > old.level {
            handleLevelUp()
        }

        // New critical conditions
        let newCritical = (new.conditions & criticalConditionMask) & ~(old.conditions & criticalConditionMask)
        if newCritical != 0 {
            handleCriticalCondition()
        }
    }

    // MARK: - Damage Handling

    private func handleDamage(old: PlayerStats, new: PlayerStats) {
        let damage = old.hp - new.hp
        let percentLost = Double(damage) / Double(max(old.hpmax, 1))
        let percentRemaining = Double(new.hp) / Double(max(new.hpmax, 1))

        // Determine intensity based on damage and remaining HP
        let intensity: FeedbackIntensity
        if percentRemaining < 0.10 {
            intensity = .critical
        } else if percentLost > 0.25 {
            intensity = .heavy
        } else if percentLost > 0.10 {
            intensity = .medium
        } else {
            intensity = .light
        }

        triggerDamageFeedback(intensity)
    }

    private func triggerDamageFeedback(_ intensity: FeedbackIntensity) {
        // Haptic feedback
        HapticManager.shared.damage(intensity: intensity)

        // Visual: shake
        shakeIntensity = intensity
        shakeCount += 1

        // Visual: flash for medium+ damage
        guard intensity >= .medium else { return }

        damageFlashActive = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            damageFlashActive = false
        }
    }

    // MARK: - Healing Handling

    private func handleHealing(old: PlayerStats, new: PlayerStats) {
        let healed = new.hp - old.hp
        let percentHealed = Double(healed) / Double(max(new.hpmax, 1))

        // Major healing (>25% HP restored)
        let isMajor = percentHealed > 0.25

        HapticManager.shared.positive(major: isMajor)

        // Future: Green pulse visual feedback
    }

    // MARK: - Level Up Handling

    private func handleLevelUp() {
        HapticManager.shared.positive(major: true)

        // Future: Gold glow visual feedback
    }

    // MARK: - Critical Condition Handling

    private func handleCriticalCondition() {
        // New life-threatening condition started
        HapticManager.shared.damage(intensity: .heavy)
        shakeIntensity = .medium
        shakeCount += 1

        // The condition badge system already handles visual display
    }
}
