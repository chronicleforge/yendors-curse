//
//  CharacterStatusModel.swift
//  nethack
//
//  Character status model wrapping C bridge functions for equipment and identity.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Equipment Slot

/// NetHack equipment slot indices matching ios_character_status.h
enum EquipmentSlot: Int, CaseIterable, Identifiable {
    case bodyArmor = 0      // IOS_SLOT_BODY_ARMOR
    case cloak = 1          // IOS_SLOT_CLOAK
    case helmet = 2         // IOS_SLOT_HELMET
    case shield = 3         // IOS_SLOT_SHIELD
    case gloves = 4         // IOS_SLOT_GLOVES
    case boots = 5          // IOS_SLOT_BOOTS
    case shirt = 6          // IOS_SLOT_SHIRT
    case weapon = 7         // IOS_SLOT_WEAPON
    case secondary = 8      // IOS_SLOT_SECONDARY
    case quiver = 9         // IOS_SLOT_QUIVER
    case amulet = 10        // IOS_SLOT_AMULET
    case leftRing = 11      // IOS_SLOT_LEFT_RING
    case rightRing = 12     // IOS_SLOT_RIGHT_RING
    case blindfold = 13     // IOS_SLOT_BLINDFOLD

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .bodyArmor: return "Body Armor"
        case .cloak: return "Cloak"
        case .helmet: return "Helmet"
        case .shield: return "Shield"
        case .gloves: return "Gloves"
        case .boots: return "Boots"
        case .shirt: return "Shirt"
        case .weapon: return "Weapon"
        case .secondary: return "Off-hand"
        case .quiver: return "Quiver"
        case .amulet: return "Amulet"
        case .leftRing: return "Left Ring"
        case .rightRing: return "Right Ring"
        case .blindfold: return "Eyes"
        }
    }

    var shortName: String {
        switch self {
        case .bodyArmor: return "Body"
        case .cloak: return "Cloak"
        case .helmet: return "Head"
        case .shield: return "Shield"
        case .gloves: return "Hands"
        case .boots: return "Feet"
        case .shirt: return "Shirt"
        case .weapon: return "Main"
        case .secondary: return "Off"
        case .quiver: return "Ammo"
        case .amulet: return "Neck"
        case .leftRing: return "L.Ring"
        case .rightRing: return "R.Ring"
        case .blindfold: return "Eyes"
        }
    }

    var icon: String {
        switch self {
        case .bodyArmor: return "shield.checkerboard"
        case .cloak: return "wind"
        case .helmet: return "brain.head.profile"
        case .shield: return "shield.fill"
        case .gloves: return "hand.raised.fill"
        case .boots: return "shoe.2.fill"
        case .shirt: return "tshirt.fill"
        case .weapon: return "sword"
        case .secondary: return "shield.lefthalf.filled"
        case .quiver: return "arrow.up.and.down"
        case .amulet: return "hexagon.fill"
        case .leftRing: return "circle.dotted"
        case .rightRing: return "circle.dotted"
        case .blindfold: return "eyes"
        }
    }

    var emptyIcon: String {
        switch self {
        case .weapon: return "rectangle.slash"
        case .shield: return "shield"
        default: return "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .weapon, .secondary: return .red
        case .bodyArmor, .cloak, .helmet, .shirt: return .blue
        case .shield, .gloves, .boots: return .cyan
        case .amulet: return .green
        case .leftRing, .rightRing: return .yellow
        case .quiver: return .orange
        case .blindfold: return .purple
        }
    }
}

// MARK: - Equipment Item

/// Represents an equipped item with BUC status
struct EquippedItem: Identifiable {
    let slot: EquipmentSlot
    let name: String
    let isCursed: Bool
    let isBlessed: Bool

    var id: Int { slot.rawValue }

    var bucStatus: ItemBUCStatus {
        if isCursed { return .cursed }
        if isBlessed { return .blessed }
        return .uncursed
    }

    var isEmpty: Bool { name.isEmpty }
}

// MARK: - Character Identity

/// Character identity information
struct CharacterIdentity {
    let roleName: String
    let raceName: String
    let genderName: String
    let alignmentName: String
    let level: Int
    let experience: Int

    static var empty: CharacterIdentity {
        CharacterIdentity(
            roleName: "Unknown",
            raceName: "unknown",
            genderName: "unknown",
            alignmentName: "unknown",
            level: 0,
            experience: 0
        )
    }
}

// MARK: - Character Status

/// Complete character status snapshot
struct CharacterStatus {
    let identity: CharacterIdentity
    let equipment: [EquippedItem]
    let hungerState: Int
    let hungerName: String
    let encumbrance: Int
    let encumbranceName: String
    let conditions: UInt
    let isPolymorphed: Bool
    let polymorphForm: String?
    let polymorphTurnsLeft: Int
    let isWeaponWelded: Bool
    let leftRingAvailable: Bool
    let rightRingAvailable: Bool

    /// Active conditions as PlayerCondition array
    var activeConditions: [PlayerCondition] {
        PlayerCondition.activeConditions(from: conditions)
    }

    /// Equipment for a specific slot
    func item(for slot: EquipmentSlot) -> EquippedItem? {
        equipment.first { $0.slot == slot }
    }

    /// Whether a slot has an item
    func hasItem(in slot: EquipmentSlot) -> Bool {
        guard let item = item(for: slot) else { return false }
        return !item.isEmpty
    }

    /// Check if an equipped item can be removed
    /// Returns (canRemove, reason if cannot)
    func canRemove(slot: EquipmentSlot) -> (canRemove: Bool, reason: String?) {
        guard let equippedItem = item(for: slot), !equippedItem.isEmpty else {
            return (false, "Empty slot")
        }

        // Cursed items cannot be removed
        if equippedItem.isCursed {
            return (false, "This item is cursed!")
        }

        // Welded weapons cannot be dropped/switched
        if slot == .weapon && isWeaponWelded {
            return (false, "Your weapon is welded to your hand!")
        }

        // Cursed gloves block ring removal
        if (slot == .leftRing || slot == .rightRing) {
            if let gloves = item(for: .gloves), !gloves.isEmpty && gloves.isCursed {
                return (false, "Your cursed gloves prevent ring removal!")
            }
        }

        return (true, nil)
    }

    /// Get the appropriate remove command for a slot
    func removeCommand(for slot: EquipmentSlot) -> String {
        switch slot {
        case .leftRing, .rightRing, .amulet, .blindfold:
            return "R"  // Remove accessory
        case .weapon, .secondary:
            return "w-"  // Wield barehanded / switch
        case .quiver:
            return "Q-"  // Empty quiver
        default:
            return "T"  // Take off armor
        }
    }
}

// MARK: - Character Status Manager

/// ObservableObject that reads character status from C bridge
@MainActor
final class CharacterStatusManager: ObservableObject {
    static let shared = CharacterStatusManager()

    @Published private(set) var status: CharacterStatus?
    @Published private(set) var lastError: String?

    private init() {}

    /// Refresh status from C bridge
    func refresh() {
        status = fetchStatus()
    }

    /// Fetch current status from bridge
    private func fetchStatus() -> CharacterStatus? {
        // Identity
        let roleName = stringFromC(ios_get_current_role_name())
        let raceName = stringFromC(ios_get_current_race_name())
        let genderName = stringFromC(ios_get_current_gender_name())
        let alignmentName = stringFromC(ios_get_current_alignment_name())
        let level = Int(ios_get_player_level())
        let experience = Int(ios_get_player_experience())

        let identity = CharacterIdentity(
            roleName: roleName,
            raceName: raceName,
            genderName: genderName,
            alignmentName: alignmentName,
            level: level,
            experience: experience
        )

        // Equipment
        var equipment: [EquippedItem] = []
        for slot in EquipmentSlot.allCases {
            let name = stringFromC(ios_get_equipment_slot(Int32(slot.rawValue)))
            let isCursed = ios_is_slot_cursed(Int32(slot.rawValue)) != 0
            let isBlessed = ios_is_slot_blessed(Int32(slot.rawValue)) != 0

            let item = EquippedItem(
                slot: slot,
                name: name,
                isCursed: isCursed,
                isBlessed: isBlessed
            )
            equipment.append(item)
        }

        // Status
        let hungerState = Int(ios_get_hunger_state())
        let hungerName = stringFromC(ios_get_hunger_state_name())
        let encumbrance = Int(ios_get_encumbrance())
        let encumbranceName = stringFromC(ios_get_encumbrance_name())
        let conditions = UInt(ios_get_condition_mask())

        // Polymorph
        let isPolymorphed = ios_is_polymorphed() != 0
        let polymorphForm = isPolymorphed ? stringFromC(ios_get_polymorph_form()) : nil
        let polymorphTurnsLeft = isPolymorphed ? Int(ios_get_polymorph_turns_left()) : 0

        // Special states
        let isWeaponWelded = ios_is_weapon_welded() != 0
        let leftRingAvailable = ios_is_left_ring_available() != 0
        let rightRingAvailable = ios_is_right_ring_available() != 0

        return CharacterStatus(
            identity: identity,
            equipment: equipment,
            hungerState: hungerState,
            hungerName: hungerName,
            encumbrance: encumbrance,
            encumbranceName: encumbranceName,
            conditions: conditions,
            isPolymorphed: isPolymorphed,
            polymorphForm: polymorphForm,
            polymorphTurnsLeft: polymorphTurnsLeft,
            isWeaponWelded: isWeaponWelded,
            leftRingAvailable: leftRingAvailable,
            rightRingAvailable: rightRingAvailable
        )
    }

    /// Convert C string to Swift String (empty if nil)
    private func stringFromC(_ cString: UnsafePointer<CChar>?) -> String {
        guard let cString = cString else { return "" }
        return String(cString: cString)
    }
}
