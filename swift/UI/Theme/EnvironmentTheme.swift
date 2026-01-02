//
//  EnvironmentTheme.swift
//  nethack
//
//  Dungeon environment-based visual theming.
//  Provides subtle color accents based on the current dungeon branch.
//

import UIKit

/// Dungeon environment types for visual theming.
/// Must match DungeonEnvironmentType in RealNetHackBridge.h
enum DungeonEnvironment: Int32 {
    case standard = 0   // Dungeons of Doom (default)
    case mines = 1      // Gnomish Mines
    case gehennom = 2   // Gehennom/Hell
    case sokoban = 3    // Sokoban
    case quest = 4      // The Quest
    case tower = 5      // Vlad's Tower
    case air = 6        // Plane of Air
    case fire = 7       // Plane of Fire
    case water = 8      // Plane of Water
    case earth = 9      // Plane of Earth
    case astral = 10    // Astral Plane
    case ludios = 11    // Fort Ludios
    case tutorial = 12  // Tutorial

    /// Accent color for this environment (Gruvbox-based)
    var accentUIColor: UIColor {
        switch self {
        case .standard, .tutorial:
            return .clear
        case .mines:
            return GruvboxColors.cyan
        case .gehennom:
            return GruvboxColors.red.blend(with: GruvboxColors.yellow, ratio: 0.4)
        case .sokoban:
            return GruvboxColors.yellow
        case .quest:
            return GruvboxColors.white
        case .tower:
            return GruvboxColors.magenta
        case .fire:
            return GruvboxColors.red
        case .water:
            return GruvboxColors.blue
        case .air:
            return GruvboxColors.cyan.blend(with: GruvboxColors.foreground, ratio: 0.3)
        case .earth:
            return GruvboxColors.green
        case .astral:
            return GruvboxColors.foreground
        case .ludios:
            return GruvboxColors.yellow
        }
    }

    /// Accent opacity (very subtle: 0-3%)
    var accentOpacity: CGFloat {
        switch self {
        case .standard, .tutorial:
            return 0.0
        case .quest, .ludios:
            return 0.01
        case .mines, .gehennom, .sokoban, .tower, .air, .earth, .astral:
            return 0.02
        case .fire, .water:
            return 0.03
        }
    }

    /// Tinted background color for this environment
    var tintedBackground: UIColor {
        let base = GruvboxColors.background
        guard accentOpacity > 0 else { return base }
        return base.blend(with: accentUIColor, ratio: accentOpacity)
    }
}

// MARK: - UIColor Blending Extension

extension UIColor {
    /// Blend this color with another color at the given ratio.
    /// - Parameters:
    ///   - color: The color to blend with
    ///   - ratio: Blend ratio (0.0 = self, 1.0 = other color)
    /// - Returns: Blended color
    func blend(with color: UIColor, ratio: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return UIColor(
            red: r1 + (r2 - r1) * ratio,
            green: g1 + (g2 - g1) * ratio,
            blue: b1 + (b2 - b1) * ratio,
            alpha: 1.0
        )
    }
}
