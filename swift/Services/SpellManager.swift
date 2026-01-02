import Foundation
import SwiftUI
import Combine

// MARK: - Spell Manager
/// Manages spell data from NetHack bridge
/// Provides cached spell list and spell casting functionality
@MainActor
final class SpellManager: ObservableObject {
    @Published private(set) var spells: [NetHackSpell] = []
    @Published private(set) var lastUpdate: Date?

    // Singleton for global access
    static let shared = SpellManager()

    private init() {}

    // MARK: - Public API

    /// Refresh spell list from NetHack bridge
    /// Call this when opening spell menu or after learning new spell
    func refreshSpells() {
        let count = Int(ios_get_spell_count())
        guard count > 0 else {
            spells = []
            lastUpdate = Date()
            return
        }

        // Allocate array for C spell info
        var cSpells = Array(repeating: SpellInfo(), count: count)
        let actualCount = Int(ios_get_spells(&cSpells, Int32(count)))

        // Convert C spells to Swift NetHackSpell
        // CRITICAL: String conversion must happen INSIDE the withUnsafePointer closure
        spells = (0..<actualCount).map { i in
            let cSpell = cSpells[i]

            // Safe C string conversion - must be inside closure scope
            let name = withUnsafePointer(to: cSpell.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 64) { charPtr in
                    String(cString: charPtr)
                }
            }

            let skillType = withUnsafePointer(to: cSpell.skill_type) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 32) { charPtr in
                    String(cString: charPtr)
                }
            }

            return NetHackSpell(
                index: Int(cSpell.index),
                letter: Character(UnicodeScalar(UInt8(cSpell.letter))),
                name: name,
                level: Int(cSpell.level),
                powerCost: Int(cSpell.power_cost),
                successRate: Int(cSpell.success_rate),
                retention: Int(cSpell.retention),
                directionType: Int(cSpell.direction_type),
                skillType: skillType
            )
        }

        lastUpdate = Date()
        print("[SpellManager] Refreshed \(spells.count) spells")
    }

    /// Get spell by letter
    func spell(forLetter letter: Character) -> NetHackSpell? {
        spells.first { $0.letter == letter }
    }

    /// Get spell by index
    func spell(atIndex index: Int) -> NetHackSpell? {
        spells.first { $0.index == index }
    }

    /// Filter spells by skill type
    func spells(ofType skillType: SpellSkillType) -> [NetHackSpell] {
        spells.filter { $0.skillType == skillType }
    }

    /// Get castable spells (retention > 0)
    var castableSpells: [NetHackSpell] {
        spells.filter { $0.isCastable }
    }

    /// Get spells that need re-reading (low retention)
    var lowRetentionSpells: [NetHackSpell] {
        spells.filter { $0.isLowRetention }
    }

    /// Check if player knows any spells
    var hasSpells: Bool {
        !spells.isEmpty
    }

    /// Get spell count
    var spellCount: Int {
        spells.count
    }

    // MARK: - Spell Casting

    /// Cast a spell by sending input to NetHack
    /// Returns true if cast command was sent
    func castSpell(_ spell: NetHackSpell, direction: Character? = nil) -> Bool {
        guard spell.isCastable else {
            print("[SpellManager] Cannot cast \(spell.name) - forgotten")
            return false
        }

        // Build complete command string: Z + spell letter + optional direction
        // FIX: Use sendCommand like movement does (sendCommand goes through
        // nethack_send_input_threaded which properly queues all characters atomically)
        var command = "Z\(spell.letter)"

        // If spell needs direction and one was provided
        if spell.requiresDirection, let dir = direction {
            command += String(dir)
        }

        print("[SpellManager] Cast command: '\(command)'")

        // Use Bridge's sendCommand - same path as movement which works correctly
        NetHackBridge.shared.sendCommand(command)
        return true
    }

    /// Cast spell at self (for NODIR spells or self-targeted IMMEDIATE)
    func castSpellAtSelf(_ spell: NetHackSpell) -> Bool {
        guard spell.isCastable else { return false }

        // Build complete command string
        var command = "Z\(spell.letter)"

        // For IMMEDIATE spells targeting self, send '.' (wait/self)
        if spell.directionType == .immediate {
            command += "."
        }

        print("[SpellManager] Cast at self: '\(command)'")
        NetHackBridge.shared.sendCommand(command)
        return true
    }

    // MARK: - Direction Helpers

    /// Direction characters for numpad
    static let directionChars: [(char: Character, dx: Int, dy: Int, name: String)] = [
        ("7", -1, -1, "Northwest"),
        ("8", 0, -1, "North"),
        ("9", 1, -1, "Northeast"),
        ("4", -1, 0, "West"),
        (".", 0, 0, "Self"),
        ("6", 1, 0, "East"),
        ("1", -1, 1, "Southwest"),
        ("2", 0, 1, "South"),
        ("3", 1, 1, "Southeast")
    ]

    /// Get direction character from dx/dy
    static func directionChar(dx: Int, dy: Int) -> Character? {
        directionChars.first { $0.dx == dx && $0.dy == dy }?.char
    }
}

// MARK: - Character Extension
private extension Character {
    var asciiValue: UInt8? {
        guard let scalar = unicodeScalars.first, scalar.isASCII else { return nil }
        return UInt8(scalar.value)
    }
}
