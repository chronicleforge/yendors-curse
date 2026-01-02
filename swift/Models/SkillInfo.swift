//
//  SkillInfo.swift
//  nethack
//
//  Data model for NetHack skill information
//  Used by the #enhance command UI
//

import SwiftUI

// MARK: - Skill Info Model

/// Represents a NetHack skill with its current training state
struct SkillInfo: Identifiable, Equatable {
    let id: Int                  // Skill index 0-37
    let name: String             // "dagger", "attack spells", etc.
    let currentLevel: SkillLevel // Current proficiency
    let maxLevel: SkillLevel     // Maximum achievable for this character
    let practicePoints: Int      // Current practice points
    let pointsNeeded: Int        // Points needed for next level
    let canAdvance: Bool         // Can advance right now (has slots + XP)
    let couldAdvance: Bool       // Could advance if more XP (show "*")
    let isMaxed: Bool            // At maximum level (show "#")
    
    /// Category this skill belongs to
    var category: SkillCategory {
        SkillCategory.from(skillId: id)
    }
    
    /// Progress towards next level (0.0 - 1.0)
    var progress: Double {
        guard pointsNeeded > 0 else { return 1.0 }
        return Double(practicePoints) / Double(pointsNeeded)
    }
    
    /// Status indicator character (for display)
    var statusIndicator: String? {
        if canAdvance { return nil }  // Highlighted instead
        if isMaxed { return "#" }
        if couldAdvance { return "*" }
        return nil
    }
}

// MARK: - Skill Level

/// NetHack skill proficiency levels
enum SkillLevel: Int, Comparable, CaseIterable {
    case restricted = 0   // Cannot train (hidden from UI)
    case unskilled = 1
    case basic = 2
    case skilled = 3
    case expert = 4
    case master = 5       // Martial arts only
    case grandMaster = 6  // Martial arts only
    
    static func < (lhs: SkillLevel, rhs: SkillLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    /// Display name for the skill level
    var displayName: String {
        switch self {
        case .restricted: return "Restricted"
        case .unskilled: return "Unskilled"
        case .basic: return "Basic"
        case .skilled: return "Skilled"
        case .expert: return "Expert"
        case .master: return "Master"
        case .grandMaster: return "Grand Master"
        }
    }
    
    /// Short display name for badges
    var shortName: String {
        switch self {
        case .restricted: return "-"
        case .unskilled: return "Un"
        case .basic: return "Ba"
        case .skilled: return "Sk"
        case .expert: return "Ex"
        case .master: return "Ma"
        case .grandMaster: return "GM"
        }
    }
    
    /// Color for the skill level badge
    var color: Color {
        switch self {
        case .restricted: return .nethackGray400
        case .unskilled: return .nethackGray500
        case .basic: return .nethackSuccess        // Green
        case .skilled: return .gruvboxBlue         // Blue
        case .expert: return .gruvboxMagenta       // Purple
        case .master: return .gruvboxOrange        // Orange
        case .grandMaster: return .gruvboxYellow   // Gold
        }
    }
}

// MARK: - Skill Category

/// Categories for grouping skills in the UI
enum SkillCategory: String, CaseIterable {
    case weapons = "Weapons"
    case spells = "Spells"
    case combat = "Combat"
    
    /// Icon for the category header
    var icon: String {
        switch self {
        case .weapons: return "hammer.fill"
        case .spells: return "sparkles"
        case .combat: return "figure.martial.arts"
        }
    }
    
    /// Color for the category
    var color: Color {
        switch self {
        case .weapons: return .nethackWarning
        case .spells: return .gruvboxMagenta
        case .combat: return .nethackError
        }
    }
    
    /// Determine category from skill ID
    static func from(skillId: Int) -> SkillCategory {
        switch skillId {
        case 0...26: return .weapons   // dagger through unicorn horn
        case 27...33: return .spells   // attack spells through matter spells
        case 34...36: return .combat   // bare hands, two weapon, riding
        default: return .weapons
        }
    }
}

// MARK: - Sample Data (for previews)

#if DEBUG
extension SkillInfo {
    static let sampleSkills: [SkillInfo] = [
        // Weapons
        SkillInfo(id: 0, name: "dagger", currentLevel: .skilled, maxLevel: .expert,
                  practicePoints: 80, pointsNeeded: 100, canAdvance: true, couldAdvance: false, isMaxed: false),
        SkillInfo(id: 1, name: "knife", currentLevel: .basic, maxLevel: .skilled,
                  practicePoints: 30, pointsNeeded: 100, canAdvance: false, couldAdvance: true, isMaxed: false),
        SkillInfo(id: 5, name: "long sword", currentLevel: .expert, maxLevel: .expert,
                  practicePoints: 100, pointsNeeded: 100, canAdvance: false, couldAdvance: false, isMaxed: true),
        SkillInfo(id: 12, name: "quarterstaff", currentLevel: .unskilled, maxLevel: .basic,
                  practicePoints: 10, pointsNeeded: 50, canAdvance: false, couldAdvance: false, isMaxed: false),
        
        // Spells
        SkillInfo(id: 27, name: "attack spells", currentLevel: .skilled, maxLevel: .expert,
                  practicePoints: 60, pointsNeeded: 100, canAdvance: true, couldAdvance: false, isMaxed: false),
        SkillInfo(id: 28, name: "healing spells", currentLevel: .basic, maxLevel: .skilled,
                  practicePoints: 45, pointsNeeded: 100, canAdvance: false, couldAdvance: true, isMaxed: false),
        SkillInfo(id: 29, name: "divination spells", currentLevel: .unskilled, maxLevel: .basic,
                  practicePoints: 5, pointsNeeded: 50, canAdvance: false, couldAdvance: false, isMaxed: false),
        
        // Combat
        SkillInfo(id: 34, name: "bare hands", currentLevel: .master, maxLevel: .grandMaster,
                  practicePoints: 150, pointsNeeded: 200, canAdvance: true, couldAdvance: false, isMaxed: false),
        SkillInfo(id: 35, name: "two weapon combat", currentLevel: .basic, maxLevel: .expert,
                  practicePoints: 20, pointsNeeded: 100, canAdvance: false, couldAdvance: false, isMaxed: false),
        SkillInfo(id: 36, name: "riding", currentLevel: .unskilled, maxLevel: .skilled,
                  practicePoints: 0, pointsNeeded: 50, canAdvance: false, couldAdvance: false, isMaxed: false),
    ]
    
    static var advanceableSkills: [SkillInfo] {
        sampleSkills.filter { $0.canAdvance }
    }
}
#endif
