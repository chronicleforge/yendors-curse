//
//  HapticManager.swift
//  nethack
//
//  Centralized haptic feedback management for premium touch interactions
//  Optimized for 120fps gesture performance with predictive preparation
//

import SwiftUI
import Combine
import UIKit

// MARK: - Feedback Intensity

/// Intensity levels for game-state feedback (damage, healing, etc.)
enum FeedbackIntensity: Int, Comparable {
    case light = 1      // <10% HP lost
    case medium = 2     // 10-25% HP lost
    case heavy = 3      // >25% HP lost
    case critical = 4   // <10% HP remaining

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Centralized haptic feedback system for the NetHack iOS app
/// Supports 120fps gesture tracking with zero-latency haptic feedback
final class HapticManager: ObservableObject {
    static let shared = HapticManager()

    // Feedback generators (pre-initialized for zero latency)
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()

    // Settings
    @Published var isEnabled: Bool = true

    private init() {
        prepareAll()
    }

    // MARK: - Preparation

    /// Prepare all generators for instant response (call before anticipated interactions)
    func prepareAll() {
        guard isEnabled else { return }
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        impactRigid.prepare()
        impactSoft.prepare()
        selectionFeedback.prepare()
        notificationFeedback.prepare()
    }

    // MARK: - Drag & Drop Haptics

    /// Haptic when drag starts (item lifts) - Medium intensity
    func dragStart() {
        guard isEnabled else { return }
        impactMedium.impactOccurred(intensity: 0.7)
        impactMedium.prepare()
    }

    /// Subtle feedback during drag movement (use sparingly to avoid overwhelming)
    func dragMove() {
        guard isEnabled else { return }
        impactLight.impactOccurred(intensity: 0.3)
    }

    /// Haptic when entering a valid drop zone - Rigid feedback
    func dropZoneEntered() {
        guard isEnabled else { return }
        impactRigid.impactOccurred(intensity: 0.6)
        impactRigid.prepare()
    }

    /// Haptic when leaving a drop zone - Light feedback
    func dropZoneExited() {
        guard isEnabled else { return }
        impactLight.impactOccurred(intensity: 0.4)
        impactLight.prepare()
    }

    /// Haptic for successful drop - Heavy impact + success notification
    func dropSuccess() {
        guard isEnabled else { return }
        impactHeavy.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.notificationFeedback.notificationOccurred(.success)
            self?.prepareAll()
        }
    }

    /// Haptic for cancelled/invalid drop - Light cancel feedback
    func cancel() {
        guard isEnabled else { return }
        impactLight.impactOccurred(intensity: 0.3)
        impactLight.prepare()
    }

    // MARK: - General UI Haptics

    /// Light tap feedback for buttons and category headers
    func tap() {
        guard isEnabled else { return }
        impactLight.impactOccurred(intensity: 0.5)
        impactLight.prepare()
    }

    /// Soft feedback when expanding categories
    func categoryExpand() {
        guard isEnabled else { return }
        impactSoft.impactOccurred(intensity: 0.8)
        impactSoft.prepare()
    }

    /// Heavy feedback for important button presses
    func buttonPress() {
        guard isEnabled else { return }
        impactHeavy.impactOccurred(intensity: 1.0)
        impactHeavy.prepare()
    }

    /// Selection changed feedback
    func selection() {
        guard isEnabled else { return }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    /// Error notification
    func error() {
        guard isEnabled else { return }
        notificationFeedback.notificationOccurred(.error)
        notificationFeedback.prepare()
    }

    /// Success notification
    func success() {
        guard isEnabled else { return }
        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()
    }

    /// Warning notification
    func warning() {
        guard isEnabled else { return }
        notificationFeedback.notificationOccurred(.warning)
        notificationFeedback.prepare()
    }

    // MARK: - Pattern-Based Haptics

    /// Play a double-tap pattern (for deletion/removal)
    func doubleTapPattern() {
        guard isEnabled else { return }
        impactLight.impactOccurred(intensity: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.impactLight.impactOccurred(intensity: 0.5)
        }
    }

    /// Play a success pattern (light → heavy for satisfying feedback)
    func successPattern() {
        guard isEnabled else { return }
        impactLight.impactOccurred(intensity: 0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.impactHeavy.impactOccurred(intensity: 1.0)
        }
    }

    /// Play a failure pattern (heavy → light → light for error indication)
    func failurePattern() {
        guard isEnabled else { return }
        impactHeavy.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.impactLight.impactOccurred(intensity: 0.4)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.impactLight.impactOccurred(intensity: 0.4)
            }
        }
    }

    // MARK: - Pickup Haptics

    /// Soft double-pulse for item pickup (distinct from movement tap)
    /// Feels like something landing in your inventory
    func pickup() {
        guard isEnabled else { return }
        // Soft initial pulse + slightly stronger follow-up = "catch" feeling
        impactSoft.impactOccurred(intensity: 0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.impactSoft.impactOccurred(intensity: 0.6)
            self?.impactSoft.prepare()
        }
    }

    // MARK: - Game State Feedback

    /// Damage feedback with intensity-based haptic pattern
    /// - Parameter intensity: Damage severity level
    func damage(intensity: FeedbackIntensity) {
        guard isEnabled else { return }

        switch intensity {
        case .light:
            impactLight.impactOccurred(intensity: 0.5)
            impactLight.prepare()

        case .medium:
            impactMedium.impactOccurred(intensity: 0.7)
            impactMedium.prepare()

        case .heavy:
            impactHeavy.impactOccurred(intensity: 1.0)
            impactHeavy.prepare()

        case .critical:
            // Double-tap pattern - unique feel for critical danger
            impactHeavy.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.impactHeavy.impactOccurred(intensity: 0.7)
                self?.impactHeavy.prepare()
            }
        }
    }

    /// Positive event feedback (healing, level up, etc.)
    /// - Parameter major: True for significant events (level up), false for minor (small heal)
    func positive(major: Bool = false) {
        guard isEnabled else { return }

        if major {
            notificationFeedback.notificationOccurred(.success)
            notificationFeedback.prepare()
        } else {
            impactSoft.impactOccurred(intensity: 0.6)
            impactSoft.prepare()
        }
    }
}

// MARK: - SwiftUI Environment Key
struct HapticManagerKey: EnvironmentKey {
    static let defaultValue = HapticManager.shared
}

extension EnvironmentValues {
    var hapticManager: HapticManager {
        get { self[HapticManagerKey.self] }
        set { self[HapticManagerKey.self] = newValue }
    }
}
