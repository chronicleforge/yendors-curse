//
//  ShakeEffect.swift
//  nethack
//
//  Horizontal shake effect for damage feedback using GeometryEffect
//

import SwiftUI

/// Shake animation using GeometryEffect for smooth interpolation
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var shakesPerUnit: CGFloat
    var animatableData: CGFloat

    init(amount: CGFloat = 5, shakesPerUnit: CGFloat = 3, animatableData: CGFloat) {
        self.amount = amount
        self.shakesPerUnit = shakesPerUnit
        self.animatableData = animatableData
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = amount * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

// MARK: - View Extension

extension View {
    /// Apply shake effect triggered by incrementing the trigger value
    /// - Parameters:
    ///   - trigger: Increment this value to trigger a shake
    ///   - amount: Pixel displacement (default 5px)
    ///   - shakesPerUnit: Number of oscillations (default 3)
    func shake(trigger: Int, amount: CGFloat = 5, shakesPerUnit: CGFloat = 3) -> some View {
        modifier(ShakeEffect(
            amount: amount,
            shakesPerUnit: shakesPerUnit,
            animatableData: CGFloat(trigger)
        ))
    }

    /// Shake with intensity-based amount
    func shake(trigger: Int, intensity: FeedbackIntensity) -> some View {
        let amount: CGFloat = switch intensity {
        case .light: 3
        case .medium: 5
        case .heavy: 8
        case .critical: 8
        }
        return shake(trigger: trigger, amount: amount)
    }
}
