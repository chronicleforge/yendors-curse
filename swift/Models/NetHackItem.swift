import SwiftUI

// MARK: - Item BUC Status
enum ItemBUCStatus: String, CaseIterable {
    case blessed = "blessed"
    case uncursed = "uncursed"
    case cursed = "cursed"
    case unknown = "unknown"

    var color: Color {
        switch self {
        case .blessed: return .green
        case .uncursed: return .yellow
        case .cursed: return .red
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch self {
        case .blessed: return "sparkles"
        case .uncursed: return "minus.circle"
        case .cursed: return "exclamationmark.triangle"
        case .unknown: return "questionmark"
        }
    }
}

// MARK: - Item Category
enum ItemCategory: String, CaseIterable {
    case weapons = "Weapons"
    case armor = "Armor"
    case potions = "Potions"
    case scrolls = "Scrolls"
    case wands = "Wands"
    case rings = "Rings"
    case amulets = "Amulets"
    case tools = "Tools"
    case food = "Food"
    case spellbooks = "Spellbooks"
    case gems = "Gems"
    case coins = "Coins"
    case misc = "Miscellaneous"

    var icon: String {
        switch self {
        case .weapons: return "sword"
        case .armor: return "shield.fill"
        case .potions: return "drop.fill"
        case .scrolls: return "scroll.fill"
        case .wands: return "wand.and.stars"
        case .rings: return "circle.hexagongrid.fill"
        case .amulets: return "hexagon.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .food: return "fork.knife"
        case .spellbooks: return "book.fill"
        case .gems: return "diamond.fill"
        case .coins: return "dollarsign.circle.fill"
        case .misc: return "cube.fill"
        }
    }

    var color: Color {
        switch self {
        case .weapons: return .red
        case .armor: return .blue
        case .potions: return .purple
        case .scrolls: return .orange
        case .wands: return .indigo
        case .rings: return .yellow
        case .amulets: return .green
        case .tools: return .brown
        case .food: return .mint
        case .spellbooks: return .pink
        case .gems: return .cyan
        case .coins: return .yellow
        case .misc: return .gray
        }
    }

    // Convert NetHack oclass to ItemCategory
    // Uses numeric class IDs from NetHack's objclass.h (NOT ASCII symbols!)
    static func fromOclass(_ oclass: Int8) -> ItemCategory {
        switch oclass {
        case 2:  return .weapons     // WEAPON_CLASS
        case 3:  return .armor       // ARMOR_CLASS
        case 4:  return .rings       // RING_CLASS
        case 5:  return .amulets     // AMULET_CLASS
        case 6:  return .tools       // TOOL_CLASS
        case 7:  return .food        // FOOD_CLASS
        case 8:  return .potions     // POTION_CLASS
        case 9:  return .scrolls     // SCROLL_CLASS
        case 10: return .spellbooks  // SPBOOK_CLASS
        case 11: return .wands       // WAND_CLASS
        case 12: return .coins       // COIN_CLASS
        case 13: return .gems        // GEM_CLASS
        default: return .misc        // RANDOM_CLASS, ILLOBJ_CLASS, ROCK_CLASS, BALL_CLASS, CHAIN_CLASS, VENOM_CLASS
        }
    }

    // Discoveries display name (uses plural for discoveries view)
    var pluralName: String {
        switch self {
        case .weapons: return "Weapons"
        case .armor: return "Armor"
        case .potions: return "Potions"
        case .scrolls: return "Scrolls"
        case .wands: return "Wands"
        case .rings: return "Rings"
        case .amulets: return "Amulets"
        case .tools: return "Tools"
        case .food: return "Food"
        case .spellbooks: return "Spellbooks"
        case .gems: return "Gems"
        case .coins: return "Coins"
        case .misc: return "Miscellaneous"
        }
    }
}

// MARK: - Item Erosion
enum ItemErosion: Int {
    case none = 0
    case slightly = 1
    case moderately = 2
    case heavily = 3

    var description: String {
        switch self {
        case .none: return ""
        case .slightly: return "slightly damaged"
        case .moderately: return "damaged"
        case .heavily: return "heavily damaged"
        }
    }
}

// MARK: - Item Properties
struct ItemProperties {
    var isGreased: Bool = false
    var isPoisoned: Bool = false
    var isErodeproof: Bool = false
    var isLocked: Bool = false
    var isTrapped: Bool = false
    var isBroken: Bool = false
    var isLit: Bool = false
    var isWielded: Bool = false
    var isWorn: Bool = false
    var isQuivered: Bool = false
}

// MARK: - NetHack Item Model
struct NetHackItem: Identifiable {
    let id: String
    let invlet: Character // Inventory letter (a-z, A-Z)
    var name: String
    var fullName: String // Complete name with all modifiers
    var category: ItemCategory
    var quantity: Int = 1

    // Status
    var bucStatus: ItemBUCStatus = .unknown
    var bucKnown: Bool = false  // NetHack tracks if player knows BUC status
    var isIdentified: Bool = false

    // Enchantment & Quality
    var enchantment: Int? // +0, +1, +2, etc.
    var charges: Int? // For wands, tools

    // Erosion & Damage
    var rustLevel: ItemErosion = .none
    var corrodeLevel: ItemErosion = .none
    var burnLevel: ItemErosion = .none
    var rotLevel: ItemErosion = .none

    // Special Properties
    var properties: ItemProperties = ItemProperties()

    // Additional info
    var description: String?
    var value: Int? // Gold value when known
    var nutrition: Int? // For food items
    var armorClass: Int? // For armor
    var damage: String? // For weapons (e.g., "1d6")
    var weight: Int = 0 // Weight in aum

    // Container support (NEW)
    var isContainer: Bool = false
    var containerType: ContainerType? = nil
    var containerItemCount: Int = 0
    var containerCapacity: Int? = nil
    var contentsKnown: Bool = false

    /// Detects containers by name - fallback when isContainer flag fails
    /// Checks for: chest, box, bag, sack (including broken variants)
    var looksLikeContainer: Bool {
        let lowercaseName = name.lowercased()
        let containerKeywords = ["chest", "large box", "bag of", "sack", "ice box"]
        return containerKeywords.contains { lowercaseName.contains($0) }
    }

    /// Effective container check: uses isContainer flag OR name-based detection
    var effectivelyIsContainer: Bool {
        return isContainer || looksLikeContainer
    }

    // Computed Properties

    /// Name stripped of BUC prefix and quantity - for compact display
    /// "uncursed +1 ring mail" → "+1 ring mail"
    /// "3 blessed scrolls of identify" → "scrolls of identify"
    var cleanName: String {
        var result = name

        // Remove quantity prefix (e.g., "3 blessed scrolls" → "blessed scrolls")
        if quantity > 1 {
            let quantityPrefix = "\(quantity) "
            if result.hasPrefix(quantityPrefix) {
                result = String(result.dropFirst(quantityPrefix.count))
            }
        }

        // Remove a/an article
        if result.hasPrefix("a ") {
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("an ") {
            result = String(result.dropFirst(3))
        }

        // Remove BUC prefix (blessed, uncursed, cursed)
        let bucPrefixes = ["blessed ", "uncursed ", "cursed "]
        for prefix in bucPrefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }

        // Remove enchantment prefix if already tracked separately
        // "+1 ring mail" - keep this, it's useful
        // But if we have the enchantment property, could skip

        return result.isEmpty ? name : result
    }

    var displayName: String {
        var result = ""

        // BUC status
        if bucStatus != .unknown && bucStatus != .uncursed {
            result += bucStatus.rawValue + " "
        }

        // Erosion status
        if rustLevel != .none {
            result += "rusty "
        }
        if corrodeLevel != .none {
            result += "corroded "
        }
        if burnLevel != .none {
            result += "burnt "
        }
        if rotLevel != .none {
            result += "rotten "
        }

        // Enchantment
        if let enchantment = enchantment {
            result += enchantment >= 0 ? "+\(enchantment) " : "\(enchantment) "
        }

        // Name
        result += name

        // Quantity
        if quantity > 1 {
            result = "\(quantity) " + result
        }

        // Status indicators
        if properties.isWielded {
            result += " (wielded)"
        } else if properties.isWorn {
            result += " (worn)"
        } else if properties.isQuivered {
            result += " (quivered)"
        }

        return result
    }

    var rarity: ItemRarity {
        // Determine rarity based on various factors
        if bucStatus == .blessed && (enchantment ?? 0) >= 3 {
            return .legendary
        }
        if bucStatus == .blessed || (enchantment ?? 0) >= 2 {
            return .rare
        }
        if (enchantment ?? 0) >= 1 {
            return .uncommon
        }
        if bucStatus == .cursed {
            return .cursed
        }
        return .common
    }

    // MARK: - Engrave Capability

    /// Whether this item can be used for engraving (matches NetHack's stylus_ok())
    var canEngrave: Bool {
        switch category {
        case .weapons, .wands, .gems, .rings:
            return true
        case .tools:
            // Only magic markers and towels from tools
            let lowerName = cleanName.lowercased()
            return lowerName.contains("magic marker") || lowerName.contains("towel")
        default:
            return false
        }
    }

    /// Whether this is a "primary" engrave tool (shown in Tier 1)
    var isPrimaryEngraveTool: Bool {
        category == .wands
    }

    init(id: String = UUID().uuidString,
         invlet: Character,
         name: String,
         fullName: String? = nil,
         category: ItemCategory,
         quantity: Int = 1) {
        self.id = id
        self.invlet = invlet
        self.name = name
        self.fullName = fullName ?? name
        self.category = category
        self.quantity = quantity
    }
}

// MARK: - Container Type
enum ContainerType: String, CaseIterable, Codable {
    case largeBox = "large box"
    case chest = "chest"
    case iceBox = "ice box"
    case sack = "sack"
    case oilskinSack = "oilskin sack"
    case bagOfHolding = "bag of holding"
    case bagOfTricks = "bag of tricks"

    var icon: String {
        switch self {
        case .largeBox: return "shippingbox"
        case .chest: return "archivebox.fill"
        case .iceBox: return "snowflake"
        case .sack: return "bag"
        case .oilskinSack: return "bag.fill"
        case .bagOfHolding: return "sparkles.rectangle.stack"
        case .bagOfTricks: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .largeBox: return .brown
        case .chest: return .orange
        case .iceBox: return .cyan
        case .sack: return .gray
        case .oilskinSack: return .blue
        case .bagOfHolding: return .purple
        case .bagOfTricks: return .pink
        }
    }
}

// MARK: - Item Rarity
enum ItemRarity {
    case common
    case uncommon
    case rare
    case legendary
    case cursed

    var color: Color {
        switch self {
        case .common: return .gray
        case .uncommon: return .green
        case .rare: return .blue
        case .legendary: return .orange
        case .cursed: return .red
        }
    }

    var glowEffect: Bool {
        switch self {
        case .legendary, .rare: return true
        default: return false
        }
    }
}

// MARK: - Sample Items for Testing
extension NetHackItem {
    static let sampleItems: [NetHackItem] = [
        NetHackItem(
            invlet: "a",
            name: "orcish dagger",
            category: .weapons,
            quantity: 1
        ).with { item in
            item.bucStatus = .uncursed
            item.enchantment = 1
            item.properties.isWielded = true
        },

        NetHackItem(
            invlet: "b",
            name: "orcish bow",
            category: .weapons
        ).with { item in
            item.bucStatus = .uncursed
            item.enchantment = 1
        },

        NetHackItem(
            invlet: "c",
            name: "orcish arrows",
            category: .weapons,
            quantity: 58
        ).with { item in
            item.bucStatus = .uncursed
            item.enchantment = 2
            item.properties.isQuivered = true
        },

        NetHackItem(
            invlet: "e",
            name: "cloak of displacement",
            category: .armor
        ).with { item in
            item.bucStatus = .uncursed
            item.enchantment = 2
            item.properties.isWorn = true
        },

        NetHackItem(
            invlet: "f",
            name: "tripe rations",
            category: .food,
            quantity: 4
        ).with { item in
            item.bucStatus = .uncursed
            item.nutrition = 200
        },

        NetHackItem(
            invlet: "$",
            name: "gold pieces",
            category: .coins,
            quantity: 5
        )
    ]

    func with(_ modifier: (inout NetHackItem) -> Void) -> NetHackItem {
        var copy = self
        modifier(&copy)
        return copy
    }
}