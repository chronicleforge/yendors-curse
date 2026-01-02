import SwiftUI

// MARK: - Spell Direction Type
enum SpellDirectionType: Int, CaseIterable {
    case unknown = 0
    case nodir = 1      // Self-cast, no direction needed (healing, buffs)
    case immediate = 2  // Directional, hits first target (force bolt, cure)
    case ray = 3        // Directional, bounces off walls (magic missile, fire)

    var requiresDirection: Bool {
        self == .immediate || self == .ray
    }

    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .nodir: return "Self"
        case .immediate: return "Touch"
        case .ray: return "Beam"
        }
    }

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .nodir: return "person.fill"
        case .immediate: return "hand.point.right.fill"
        case .ray: return "bolt.horizontal.fill"
        }
    }
}

// MARK: - Spell Skill Type
enum SpellSkillType: String, CaseIterable {
    case attack = "attack"
    case healing = "healing"
    case divination = "divination"
    case enchantment = "enchantment"
    case clerical = "clerical"
    case escape = "escape"
    case matter = "matter"
    case unknown = "unknown"

    var color: Color {
        switch self {
        case .attack: return .red
        case .healing: return .green
        case .divination: return .cyan
        case .enchantment: return .purple
        case .clerical: return .yellow
        case .escape: return .blue
        case .matter: return .orange
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch self {
        case .attack: return "flame.fill"
        case .healing: return "heart.fill"
        case .divination: return "eye.fill"
        case .enchantment: return "sparkles"
        case .clerical: return "sun.max.fill"
        case .escape: return "figure.walk"
        case .matter: return "atom"
        case .unknown: return "questionmark"
        }
    }

    static func from(_ string: String) -> SpellSkillType {
        SpellSkillType(rawValue: string.lowercased()) ?? .unknown
    }
}

// MARK: - Spell Retention Level
enum SpellRetentionLevel {
    case fresh       // 80-100%
    case good        // 50-79%
    case fading      // 20-49%
    case critical    // 1-19%
    case forgotten   // 0%

    var color: Color {
        switch self {
        case .fresh: return .green
        case .good: return .blue
        case .fading: return .yellow
        case .critical: return .orange
        case .forgotten: return .red
        }
    }

    static func from(_ retention: Int) -> SpellRetentionLevel {
        switch retention {
        case 80...100: return .fresh
        case 50..<80: return .good
        case 20..<50: return .fading
        case 1..<20: return .critical
        default: return .forgotten
        }
    }
}

// MARK: - NetHack Spell Model
struct NetHackSpell: Identifiable, Hashable {
    let id: String
    let index: Int           // spl_book index (0-51)
    let letter: Character    // Menu letter (a-z, A-Z)
    let name: String         // Spell name
    let level: Int           // Spell level (1-7)
    let powerCost: Int       // Power cost (level * 5)
    let successRate: Int     // Success rate 0-100%
    let retention: Int       // Retention 0-100%
    let directionType: SpellDirectionType
    let skillType: SpellSkillType

    // Computed Properties

    var retentionLevel: SpellRetentionLevel {
        SpellRetentionLevel.from(retention)
    }

    var requiresDirection: Bool {
        directionType.requiresDirection
    }

    var isCastable: Bool {
        retention > 0
    }

    var isLowRetention: Bool {
        retention < 20
    }

    var successDescription: String {
        switch successRate {
        case 90...100: return "Very High"
        case 70..<90: return "High"
        case 50..<70: return "Medium"
        case 30..<50: return "Low"
        default: return "Very Low"
        }
    }

    var successColor: Color {
        switch successRate {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .yellow
        case 20..<40: return .orange
        default: return .red
        }
    }

    // Retention bar segments (5 total)
    var retentionSegments: Int {
        max(0, min(5, retention / 20))
    }

    // Display string for UI
    var displayName: String {
        name.capitalized
    }

    var shortDescription: String {
        "Lv.\(level) \(powerCost)Pw"
    }

    // Hash and equality based on index
    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
    }

    static func == (lhs: NetHackSpell, rhs: NetHackSpell) -> Bool {
        lhs.index == rhs.index
    }

    // Initializer from C bridge data
    init(index: Int, letter: Character, name: String, level: Int, powerCost: Int,
         successRate: Int, retention: Int, directionType: Int, skillType: String) {
        self.id = "spell_\(index)"
        self.index = index
        self.letter = letter
        self.name = name
        self.level = level
        self.powerCost = powerCost
        self.successRate = max(0, min(100, successRate))
        self.retention = max(0, min(100, retention))
        self.directionType = SpellDirectionType(rawValue: directionType) ?? .unknown
        self.skillType = SpellSkillType.from(skillType)
    }
}

// MARK: - Sample Spells for Testing
extension NetHackSpell {
    static let sampleSpells: [NetHackSpell] = [
        NetHackSpell(
            index: 0,
            letter: "a",
            name: "force bolt",
            level: 1,
            powerCost: 5,
            successRate: 100,
            retention: 100,
            directionType: 2,
            skillType: "attack"
        ),
        NetHackSpell(
            index: 1,
            letter: "b",
            name: "identify",
            level: 3,
            powerCost: 15,
            successRate: 13,
            retention: 100,
            directionType: 1,
            skillType: "divination"
        ),
        NetHackSpell(
            index: 2,
            letter: "c",
            name: "healing",
            level: 1,
            powerCost: 5,
            successRate: 95,
            retention: 80,
            directionType: 2,
            skillType: "healing"
        ),
        NetHackSpell(
            index: 3,
            letter: "d",
            name: "magic missile",
            level: 2,
            powerCost: 10,
            successRate: 85,
            retention: 45,
            directionType: 3,
            skillType: "attack"
        ),
        NetHackSpell(
            index: 4,
            letter: "e",
            name: "light",
            level: 1,
            powerCost: 5,
            successRate: 100,
            retention: 15,
            directionType: 1,
            skillType: "divination"
        )
    ]
}
