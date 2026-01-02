//
//  GameEndType.swift
//  nethack
//
//  Game end type enum for distinguishing death, escape, and ascension.
//  Used by DeathFlowController and DeathScreenView for conditional messaging.
//
//  Created: 2025-12-21
//

import SwiftUI

/// Types of game endings in NetHack
enum GameEndType: Int, CaseIterable {
    case died = 0
    case escaped = 14
    case ascended = 15

    /// Whether this is a victory condition (escaped or ascended)
    var isVictory: Bool { self == .escaped || self == .ascended }

    /// Main title for the game end screen
    var title: String {
        switch self {
        case .died: return "Game Over"
        case .escaped: return "Escaped!"
        case .ascended: return "Victory!"
        }
    }

    /// Subtitle shown under the icon
    var subtitle: String {
        switch self {
        case .died: return "Goodbye"
        case .escaped: return "You Made It!"
        case .ascended: return "Demigod!"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .died: return "person.crop.circle.badge.xmark"
        case .escaped: return "figure.walk.departure"
        case .ascended: return "crown.fill"
        }
    }

    /// Primary accent color for the game end screen
    var accentColor: Color {
        switch self {
        case .died: return .red
        case .escaped: return .green
        case .ascended: return .yellow
        }
    }

    /// Background gradient colors
    var backgroundGradient: [Color] {
        switch self {
        case .died:
            return [Color.black, Color(red: 0.1, green: 0.05, blue: 0.15)]
        case .escaped:
            return [Color.black, Color(red: 0.05, green: 0.12, blue: 0.08)]
        case .ascended:
            return [Color.black, Color(red: 0.15, green: 0.12, blue: 0.05)]
        }
    }
}
