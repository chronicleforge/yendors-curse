import Foundation

// MARK: - Menu Item Attributes
// Matches NetHack's wintype.h ATR_* constants
struct MenuItemAttributes: OptionSet {
    let rawValue: UInt32

    static let none      = MenuItemAttributes([])
    static let bold      = MenuItemAttributes(rawValue: 1 << 0)  // ATR_BOLD
    static let dim       = MenuItemAttributes(rawValue: 1 << 1)  // ATR_DIM
    static let italic    = MenuItemAttributes(rawValue: 1 << 2)  // ATR_ULINE (repurposed)
    static let inverse   = MenuItemAttributes(rawValue: 1 << 3)  // ATR_INVERSE
    static let heading   = MenuItemAttributes(rawValue: 1 << 4)  // Section header
}

// MARK: - Menu Item
/// Generic menu item for NetHack menus
/// Used by NHMenuSheet for PICK_NONE, PICK_ONE, PICK_ANY display
struct NHMenuItem: Identifiable, Equatable {
    let id: String
    let selector: Character?     // 'a'-'z', 'A'-'Z', or nil for unselectable
    let glyph: Int?              // Tile/symbol ID for colored display
    let text: String             // Display text
    let attributes: MenuItemAttributes
    var isSelected: Bool = false // For PICK_ANY multi-select
    var count: Int = 0           // For quantity selection

    // MARK: - Computed Properties

    var isBold: Bool { attributes.contains(.bold) }
    var isDim: Bool { attributes.contains(.dim) }
    var isHeading: Bool { attributes.contains(.heading) }
    var isSelectable: Bool { selector != nil && !isDim }

    /// Display string for selector badge (e.g., "a", "B", "-")
    var selectorDisplay: String {
        guard let sel = selector else { return "-" }
        return String(sel)
    }

    // MARK: - Initializers

    init(
        id: String = UUID().uuidString,
        selector: Character? = nil,
        glyph: Int? = nil,
        text: String,
        attributes: MenuItemAttributes = .none,
        isSelected: Bool = false,
        count: Int = 0
    ) {
        self.id = id
        self.selector = selector
        self.glyph = glyph
        self.text = text
        self.attributes = attributes
        self.isSelected = isSelected
        self.count = count
    }

    /// Create from C bridge data
    init(fromBridge selector: Int8, glyph: Int32, text: UnsafePointer<CChar>?, attributes: UInt32) {
        self.id = UUID().uuidString
        self.selector = selector != 0 ? Character(UnicodeScalar(UInt8(bitPattern: selector))) : nil
        self.glyph = glyph != 0 ? Int(glyph) : nil
        self.text = text.map { String(cString: $0) } ?? ""
        self.attributes = MenuItemAttributes(rawValue: attributes)
        self.isSelected = false
        self.count = 0
    }

    // MARK: - Factory Methods

    /// Create a heading/section item
    static func heading(_ text: String) -> NHMenuItem {
        NHMenuItem(text: text, attributes: [.bold, .heading])
    }

    /// Create a selectable item
    static func item(_ text: String, selector: Character, glyph: Int? = nil) -> NHMenuItem {
        NHMenuItem(selector: selector, glyph: glyph, text: text)
    }

    /// Create an unselectable info line
    static func info(_ text: String) -> NHMenuItem {
        NHMenuItem(text: text, attributes: .dim)
    }
}

// MARK: - Menu Selection Result
/// Result returned from menu selection
struct NHMenuSelection {
    let item: NHMenuItem
    let count: Int  // 0 = cancelled, -1 = all, >0 = specific count

    var isCancelled: Bool { count == 0 }
    var isAll: Bool { count == -1 }
}
