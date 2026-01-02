import Foundation
import SwiftUI

// MARK: - Pick Mode
/// Menu selection mode - matches NetHack's PICK_* constants
enum NHPickMode: Int {
    case none = 0  // PICK_NONE - Display only, no selection
    case one = 1   // PICK_ONE - Select exactly one item
    case any = 2   // PICK_ANY - Multi-select with checkboxes

    var allowsSelection: Bool {
        self != .none
    }

    var isMultiSelect: Bool {
        self == .any
    }

    var needsConfirmButton: Bool {
        self == .any
    }

    var dismissOnSelect: Bool {
        self == .one
    }
}

// MARK: - Menu Context
/// Context for displaying a NetHack menu
/// Passed to MenuRouter to determine which view to show
struct NHMenuContext {
    let windowID: Int
    let prompt: String
    let pickMode: NHPickMode
    let menuID: String?          // For routing to specialized views
    var items: [NHMenuItem]
    let subtitle: String?        // Optional context (e.g., "12 MP available")
    let icon: String?            // SF Symbol name

    // MARK: - Computed Properties

    var hasItems: Bool { !items.isEmpty }
    var itemCount: Int { items.count }
    var selectableItems: [NHMenuItem] { items.filter { $0.isSelectable } }
    var headings: [NHMenuItem] { items.filter { $0.isHeading } }

    // MARK: - Initializers

    init(
        windowID: Int = 0,
        prompt: String,
        pickMode: NHPickMode,
        menuID: String? = nil,
        items: [NHMenuItem] = [],
        subtitle: String? = nil,
        icon: String? = nil
    ) {
        self.windowID = windowID
        self.prompt = prompt
        self.pickMode = pickMode
        self.menuID = menuID
        self.items = items
        self.subtitle = subtitle
        self.icon = icon
    }

    // MARK: - Factory Methods

    /// Create context for inventory display
    static func inventory(items: [NHMenuItem]) -> NHMenuContext {
        NHMenuContext(
            prompt: "Inventory",
            pickMode: .none,
            menuID: "inventory",
            items: items,
            icon: "bag.fill"
        )
    }

    /// Create context for item pickup
    static func pickup(items: [NHMenuItem], weight: String? = nil) -> NHMenuContext {
        NHMenuContext(
            prompt: "Pick up what?",
            pickMode: .any,
            menuID: "pickup",
            items: items,
            subtitle: weight,
            icon: "arrow.down.circle.fill"
        )
    }

    /// Create context for item drop
    static func drop(items: [NHMenuItem]) -> NHMenuContext {
        NHMenuContext(
            prompt: "Drop what?",
            pickMode: .any,
            menuID: "drop",
            items: items,
            icon: "arrow.down.to.line.circle.fill"
        )
    }

    /// Create context for spell casting
    static func spells(items: [NHMenuItem], mp: Int) -> NHMenuContext {
        NHMenuContext(
            prompt: "Cast which spell?",
            pickMode: .one,
            menuID: "spell_menu",
            items: items,
            subtitle: "\(mp) MP available",
            icon: "sparkles"
        )
    }

    /// Create context for help/text display
    static func help(title: String, items: [NHMenuItem]) -> NHMenuContext {
        NHMenuContext(
            prompt: title,
            pickMode: .none,
            menuID: "help",
            items: items,
            icon: "questionmark.circle.fill"
        )
    }

    /// Create context for generic single selection
    static func selectOne(prompt: String, items: [NHMenuItem], icon: String? = nil) -> NHMenuContext {
        NHMenuContext(
            prompt: prompt,
            pickMode: .one,
            items: items,
            icon: icon
        )
    }

    /// Create context for generic multi-selection
    static func selectAny(prompt: String, items: [NHMenuItem], icon: String? = nil) -> NHMenuContext {
        NHMenuContext(
            prompt: prompt,
            pickMode: .any,
            items: items,
            icon: icon
        )
    }

    // MARK: - Mutating Methods

    /// Update selection state for an item
    mutating func toggleSelection(for itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].isSelected.toggle()
    }

    /// Select all items
    mutating func selectAll() {
        for index in items.indices where items[index].isSelectable {
            items[index].isSelected = true
        }
    }

    /// Deselect all items
    mutating func deselectAll() {
        for index in items.indices {
            items[index].isSelected = false
        }
    }

    /// Get currently selected items
    var selectedItems: [NHMenuItem] {
        items.filter { $0.isSelected }
    }

    var selectedCount: Int {
        selectedItems.count
    }
}
