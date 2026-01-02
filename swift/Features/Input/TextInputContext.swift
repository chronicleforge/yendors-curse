import SwiftUI

// MARK: - Text Input Context

/// Context for text input prompts (engrave custom, name, genocide, polymorph)
/// Defines the prompt, suggestions, and behavior for each input type
struct TextInputContext {
    let prompt: String
    let icon: String
    let color: Color
    let placeholder: String
    let showSearch: Bool  // Show search field for 50+ suggestions
    let killedMonsters: [DiscoveredMonster]  // Section 1: Killed monsters
    let seenMonsters: [DiscoveredMonster]    // Section 2: Seen-only monsters
    let staticSuggestions: [String]          // Static suggestions (for engrave)
    let onSubmit: (String) -> Void

    // MARK: - Computed Properties

    var hasMonsterSuggestions: Bool {
        !killedMonsters.isEmpty || !seenMonsters.isEmpty
    }

    var hasSuggestions: Bool {
        hasMonsterSuggestions || !staticSuggestions.isEmpty
    }

    var totalSuggestionCount: Int {
        killedMonsters.count + seenMonsters.count + staticSuggestions.count
    }

    // MARK: - Factory Methods

    /// Engrave custom text
    static func engrave(onSubmit: @escaping (String) -> Void) -> TextInputContext {
        TextInputContext(
            prompt: "What do you want to write?",
            icon: "pencil.tip",
            color: .brown,
            placeholder: "Enter text to engrave...",
            showSearch: false,
            killedMonsters: [],
            seenMonsters: [],
            staticSuggestions: ["Elbereth", "X", "?"],  // Common engravings
            onSubmit: onSubmit
        )
    }

    /// Name a monster, item, or type
    static func name(prompt: String, onSubmit: @escaping (String) -> Void) -> TextInputContext {
        TextInputContext(
            prompt: prompt,
            icon: "tag.fill",
            color: .blue,
            placeholder: "Enter name...",
            showSearch: false,
            killedMonsters: [],
            seenMonsters: [],
            staticSuggestions: [],
            onSubmit: onSubmit
        )
    }

    /// Genocide scroll - suggest discovered monsters
    static func genocide(onSubmit: @escaping (String) -> Void) -> TextInputContext {
        let (killed, seen) = ObjectBridgeWrapper.getDiscoveredMonsters()
        return TextInputContext(
            prompt: "What monster do you want to genocide?",
            icon: "xmark.circle.fill",
            color: .red,
            placeholder: "Enter monster name...",
            showSearch: killed.count + seen.count > 30,
            killedMonsters: killed,
            seenMonsters: seen,
            staticSuggestions: [],
            onSubmit: onSubmit
        )
    }

    /// Polymorph - suggest discovered monsters
    static func polymorph(onSubmit: @escaping (String) -> Void) -> TextInputContext {
        let (killed, seen) = ObjectBridgeWrapper.getDiscoveredMonsters()
        return TextInputContext(
            prompt: "Become what kind of monster?",
            icon: "sparkles",
            color: .purple,
            placeholder: "Enter monster name...",
            showSearch: killed.count + seen.count > 30,
            killedMonsters: killed,
            seenMonsters: seen,
            staticSuggestions: [],
            onSubmit: onSubmit
        )
    }

    /// Wish - suggest common wish items with categories
    static func wish(onSubmit: @escaping (String) -> Void) -> TextInputContext {
        TextInputContext(
            prompt: "For what do you wish?",
            icon: "star.fill",
            color: .purple,
            placeholder: "e.g. blessed +3 silver dragon scale mail",
            showSearch: true,  // Many suggestions - enable search
            killedMonsters: [],
            seenMonsters: [],
            staticSuggestions: [],  // Use categorizedWishes instead
            onSubmit: onSubmit
        )
    }

    /// Annotate current level
    static func annotation(prompt: String, onSubmit: @escaping (String) -> Void) -> TextInputContext {
        TextInputContext(
            prompt: prompt,
            icon: "note.text",
            color: .orange,
            placeholder: "Enter level annotation...",
            showSearch: false,
            killedMonsters: [],
            seenMonsters: [],
            staticSuggestions: ["Shop", "Temple", "Stash", "Altar", "Dangerous"],
            onSubmit: onSubmit
        )
    }

    // MARK: - Categorized Wish Suggestions

    /// Categories for wish suggestions (used by UnifiedSelectionSheet)
    static var categorizedWishes: [(name: String, icon: String, color: Color, items: [String])] {
        [
            (
                name: "Priority Armor",
                icon: "shield.fill",
                color: .blue,
                items: [
                    "blessed +3 gray dragon scale mail",
                    "blessed +3 silver dragon scale mail",
                    "blessed greased +3 speed boots",
                    "blessed +3 gauntlets of power",
                ]
            ),
            (
                name: "Artifacts",
                icon: "sparkles",
                color: .yellow,
                items: [
                    "blessed rustproof +3 Grayswandir",
                    "blessed rustproof +3 Mjollnir",
                    "blessed Magicbane",
                    "blessed +3 Excalibur",
                ]
            ),
            (
                name: "More Armor",
                icon: "tshirt.fill",
                color: .blue,
                items: [
                    "blessed +3 helm of brilliance",
                    "blessed +3 cloak of magic resistance",
                    "blessed +3 cloak of displacement",
                    "blessed +3 levitation boots",
                ]
            ),
            (
                name: "Accessories",
                icon: "circle.fill",
                color: .purple,
                items: [
                    "blessed ring of conflict",
                    "blessed ring of free action",
                    "blessed amulet of life saving",
                    "blessed amulet of reflection",
                ]
            ),
            (
                name: "Wands",
                icon: "wand.and.stars",
                color: .orange,
                items: [
                    "blessed wand of wishing",
                    "blessed wand of death",
                    "blessed wand of teleportation",
                    "blessed wand of digging",
                ]
            ),
            (
                name: "Tools",
                icon: "wrench.and.screwdriver.fill",
                color: .green,
                items: [
                    "blessed magic marker",
                    "blessed bag of holding",
                    "blessed magic lamp",
                    "blessed +0 unicorn horn",
                ]
            ),
            (
                name: "Scrolls & Potions",
                icon: "scroll.fill",
                color: .mint,
                items: [
                    "2 blessed scrolls of genocide",
                    "3 blessed scrolls of charging",
                    "2 blessed potions of full healing",
                    "blessed potion of gain level",
                ]
            ),
        ]
    }
}
