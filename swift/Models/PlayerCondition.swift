//
//  PlayerCondition.swift
//  nethack
//
//  Status condition badges for NetHack iOS.
//  Bitmask values from origin/NetHack/include/botl.h
//

import SwiftUI

// MARK: - Condition Tier

/// Priority tier for condition display ordering
enum ConditionTier: Int, Comparable {
    case critical = 1       // Fatal conditions - always show first
    case debilitating = 2   // Sense impairment - show when active
    case incapacitation = 3 // Cannot act - show when active
    case movement = 4       // Movement mode - show when active
    case hazard = 5         // Environmental - show when active
    case optional = 6       // Minor - user preference

    static func < (lhs: ConditionTier, rhs: ConditionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Player Condition

/// All 30 NetHack status conditions with their bitmasks
enum PlayerCondition: UInt, CaseIterable, Identifiable {
    // CRITICAL (Tier 1) - Fatal conditions
    case stoned       = 0x00100000  // BL_MASK_STONE
    case slimed       = 0x00040000  // BL_MASK_SLIME
    case strangled    = 0x00200000  // BL_MASK_STRNGL
    case foodPoisoned = 0x00000080  // BL_MASK_FOODPOIS
    case terminallyIll = 0x01000000 // BL_MASK_TERMILL

    // DEBILITATING (Tier 2) - Sense impairment
    case blind        = 0x00000002  // BL_MASK_BLIND
    case deaf         = 0x00000010  // BL_MASK_DEAF
    case confused     = 0x00000008  // BL_MASK_CONF
    case stunned      = 0x00400000  // BL_MASK_STUN
    case hallucinating = 0x00000400 // BL_MASK_HALLU

    // INCAPACITATION (Tier 3) - Cannot act
    case paralyzed    = 0x00008000  // BL_MASK_PARLYZ
    case sleeping     = 0x00020000  // BL_MASK_SLEEPING
    case unconscious  = 0x08000000  // BL_MASK_UNCONSC

    // MOVEMENT (Tier 4) - Movement mode
    case levitating   = 0x00004000  // BL_MASK_LEV
    case flying       = 0x00000040  // BL_MASK_FLY
    case riding       = 0x00010000  // BL_MASK_RIDE

    // HAZARDS (Tier 5) - Environmental dangers
    case trapped      = 0x04000000  // BL_MASK_TRAPPED
    case inLava       = 0x00002000  // BL_MASK_INLAVA
    case held         = 0x00000800  // BL_MASK_HELD
    case grabbed      = 0x00000200  // BL_MASK_GRAB
    case submerged    = 0x00800000  // BL_MASK_SUBMERGED
    case onIce        = 0x00001000  // BL_MASK_ICY
    case tethered     = 0x02000000  // BL_MASK_TETHERED

    // OPTIONAL (Tier 6) - Minor conditions
    case woundedLegs  = 0x10000000  // BL_MASK_WOUNDEDL
    case slippery     = 0x00080000  // BL_MASK_SLIPPERY
    case bareHanded   = 0x00000001  // BL_MASK_BAREH
    case glowingHands = 0x00000100  // BL_MASK_GLOWHANDS
    case elfIron      = 0x00000020  // BL_MASK_ELF_IRON
    case busy         = 0x00000004  // BL_MASK_BUSY
    case holding      = 0x20000000  // BL_MASK_HOLDING

    var id: UInt { rawValue }

    // MARK: - Tier

    var tier: ConditionTier {
        switch self {
        case .stoned, .slimed, .strangled, .foodPoisoned, .terminallyIll:
            return .critical
        case .blind, .deaf, .confused, .stunned, .hallucinating:
            return .debilitating
        case .paralyzed, .sleeping, .unconscious:
            return .incapacitation
        case .levitating, .flying, .riding:
            return .movement
        case .trapped, .inLava, .held, .grabbed, .submerged, .onIce, .tethered:
            return .hazard
        case .woundedLegs, .slippery, .bareHanded, .glowingHands, .elfIron, .busy, .holding:
            return .optional
        }
    }

    // MARK: - Priority (lower = more important)

    var priority: Int {
        switch self {
        // Critical
        case .stoned: return 1
        case .slimed: return 2
        case .strangled: return 3
        case .foodPoisoned: return 4
        case .terminallyIll: return 5
        // Debilitating
        case .blind: return 6
        case .deaf: return 7
        case .confused: return 8
        case .stunned: return 9
        case .hallucinating: return 10
        // Incapacitation
        case .paralyzed: return 11
        case .sleeping: return 12
        case .unconscious: return 13
        // Movement
        case .levitating: return 14
        case .flying: return 15
        case .riding: return 16
        // Hazards
        case .trapped: return 17
        case .inLava: return 18
        case .held: return 19
        case .grabbed: return 20
        case .submerged: return 21
        case .onIce: return 22
        case .tethered: return 23
        // Optional
        case .woundedLegs: return 24
        case .slippery: return 25
        case .bareHanded: return 26
        case .glowingHands: return 27
        case .elfIron: return 28
        case .busy: return 29
        case .holding: return 30
        }
    }

    // MARK: - SF Symbol Icon

    var icon: String {
        switch self {
        // Critical
        case .stoned: return "fossil.shell.fill"
        case .slimed: return "drop.circle.fill"
        case .strangled: return "wind"
        case .foodPoisoned: return "allergens.fill"
        case .terminallyIll: return "cross.vial.fill"
        // Debilitating
        case .blind: return "eye.slash.fill"
        case .deaf: return "ear.trianglebadge.exclamationmark"
        case .confused: return "tornado"
        case .stunned: return "staroflife.fill"
        case .hallucinating: return "eye.trianglebadge.exclamationmark.fill"
        // Incapacitation
        case .paralyzed: return "figure.stand"
        case .sleeping: return "zzz"
        case .unconscious: return "moon.zzz.fill"
        // Movement
        case .levitating: return "arrow.up.forward.circle.fill"
        case .flying: return "bird.fill"
        case .riding: return "figure.equestrian.sports"
        // Hazards
        case .trapped: return "exclamationmark.triangle.fill"
        case .inLava: return "flame.fill"
        case .held: return "hand.raised.fingers.spread.fill"
        case .grabbed: return "hand.point.up.braille.fill"
        case .submerged: return "water.waves"
        case .onIce: return "snowflake"
        case .tethered: return "link"
        // Optional
        case .woundedLegs: return "figure.walk"
        case .slippery: return "drop.fill"
        case .bareHanded: return "hand.raised.fill"
        case .glowingHands: return "sparkle"
        case .elfIron: return "bolt.horizontal.fill"
        case .busy: return "clock.badge.checkmark.fill"
        case .holding: return "figure.stand.line.dotted.figure.stand"
        }
    }

    // MARK: - Short Label (for compact display)

    var shortLabel: String {
        switch self {
        case .stoned: return "Stone"
        case .slimed: return "Slime"
        case .strangled: return "Strgl"
        case .foodPoisoned: return "FPois"
        case .terminallyIll: return "TermI"
        case .blind: return "Blind"
        case .deaf: return "Deaf"
        case .confused: return "Conf"
        case .stunned: return "Stun"
        case .hallucinating: return "Hallu"
        case .paralyzed: return "Parlz"
        case .sleeping: return "Sleep"
        case .unconscious: return "Out"
        case .levitating: return "Lev"
        case .flying: return "Fly"
        case .riding: return "Ride"
        case .trapped: return "Trap"
        case .inLava: return "Lava"
        case .held: return "Held"
        case .grabbed: return "Grab"
        case .submerged: return "Sub"
        case .onIce: return "Icy"
        case .tethered: return "Teth"
        case .woundedLegs: return "Legs"
        case .slippery: return "Slip"
        case .bareHanded: return "Bare"
        case .glowingHands: return "Glow"
        case .elfIron: return "Iron"
        case .busy: return "Busy"
        case .holding: return "Hold"
        }
    }

    // MARK: - Full Label (for accessibility)

    var fullLabel: String {
        switch self {
        case .stoned: return "Petrifying"
        case .slimed: return "Turning to Slime"
        case .strangled: return "Strangled"
        case .foodPoisoned: return "Food Poisoned"
        case .terminallyIll: return "Terminally Ill"
        case .blind: return "Blinded"
        case .deaf: return "Deafened"
        case .confused: return "Confused"
        case .stunned: return "Stunned"
        case .hallucinating: return "Hallucinating"
        case .paralyzed: return "Paralyzed"
        case .sleeping: return "Sleeping"
        case .unconscious: return "Unconscious"
        case .levitating: return "Levitating"
        case .flying: return "Flying"
        case .riding: return "Riding"
        case .trapped: return "Trapped"
        case .inLava: return "In Lava"
        case .held: return "Held"
        case .grabbed: return "Grabbed"
        case .submerged: return "Submerged"
        case .onIce: return "On Ice"
        case .tethered: return "Tethered"
        case .woundedLegs: return "Wounded Legs"
        case .slippery: return "Slippery Hands"
        case .bareHanded: return "Bare Handed"
        case .glowingHands: return "Glowing Hands"
        case .elfIron: return "Iron Sickness"
        case .busy: return "Busy"
        case .holding: return "Holding"
        }
    }

    // MARK: - Color

    var color: Color {
        switch tier {
        case .critical:
            // Different shades for different critical conditions
            switch self {
            case .slimed, .foodPoisoned: return Color(hex: "#7CFC00") // Toxic green
            default: return Color(hex: "#FF2D55") // iOS System Pink/Red
            }
        case .debilitating:
            if self == .blind || self == .deaf {
                return Color(hex: "#48484A") // Dark gray for sense loss
            }
            return Color(hex: "#FF9500") // iOS System Orange
        case .incapacitation:
            return Color(hex: "#BF5AF2") // iOS System Purple
        case .movement:
            if self == .flying {
                return Color(hex: "#64D2FF") // Cyan for flying
            }
            return Color(hex: "#30D158") // iOS System Green
        case .hazard:
            if self == .inLava {
                return Color(hex: "#FF4500") // Lava orange-red
            }
            if self == .submerged {
                return Color(hex: "#0A84FF") // Deep blue
            }
            if self == .onIce {
                return Color(hex: "#ADD8E6") // Ice blue
            }
            return Color(hex: "#FFD60A") // iOS System Yellow
        case .optional:
            return Color(hex: "#8E8E93") // iOS System Gray
        }
    }

    // MARK: - Icon Color (foreground)

    var iconColor: Color {
        switch self {
        case .onIce:
            return Color(hex: "#000080") // Navy for contrast on light ice blue
        case .foodPoisoned, .slimed:
            return .black // Black on toxic green
        case .trapped:
            return .black // Black on yellow
        default:
            return .white
        }
    }

    // MARK: - Accessibility Description

    var accessibilityDescription: String {
        switch self {
        case .stoned: return "You are turning to stone. Eat a lizard or acidic corpse immediately."
        case .slimed: return "You are being covered in slime. Burn it off with fire or eat acidic food."
        case .strangled: return "You are being strangled and cannot breathe."
        case .foodPoisoned: return "You have food poisoning. Seek healing."
        case .terminallyIll: return "You have a terminal illness. Find a cure immediately."
        case .blind: return "You cannot see. Use other senses to navigate."
        case .deaf: return "You cannot hear. You will not notice some events."
        case .confused: return "You are confused. Movement may be erratic."
        case .stunned: return "You are stunned. Actions may fail."
        case .hallucinating: return "You are hallucinating. What you see is not real."
        case .paralyzed: return "You cannot move or act."
        case .sleeping: return "You are asleep."
        case .unconscious: return "You are unconscious and cannot act."
        case .levitating: return "You are levitating off the ground."
        case .flying: return "You are flying."
        case .riding: return "You are riding a mount."
        case .trapped: return "You are trapped and cannot move freely."
        case .inLava: return "You are in lava! Get out immediately!"
        case .held: return "Something is holding you."
        case .grabbed: return "You have been grabbed by a monster."
        case .submerged: return "You are underwater."
        case .onIce: return "You are standing on ice. Movement is slippery."
        case .tethered: return "You are tethered to something."
        case .woundedLegs: return "Your legs are wounded. Movement is impaired."
        case .slippery: return "Your hands are slippery. You may drop items."
        case .bareHanded: return "You have no weapon equipped."
        case .glowingHands: return "Your hands are glowing with magical energy."
        case .elfIron: return "You are suffering from iron sickness."
        case .busy: return "You are busy with a multi-turn action."
        case .holding: return "You are holding something."
        }
    }

    // MARK: - Active Conditions from Bitmask

    /// Extract all active conditions from a bitmask
    static func activeConditions(from mask: UInt) -> [PlayerCondition] {
        PlayerCondition.allCases
            .filter { (mask & $0.rawValue) != 0 }
            .sorted { $0.priority < $1.priority }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
