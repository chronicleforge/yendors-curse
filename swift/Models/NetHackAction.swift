import SwiftUI

// MARK: - LCH Color System Extension

extension Color {
    /// Create a Color from LCH (Lightness, Chroma, Hue) color space for perceptually uniform colors
    ///
    /// WHY LCH? Perceptually uniform - L=60 always looks the same brightness regardless of hue.
    /// Unlike HSL/HSB which are RGB-based and perceptually non-uniform.
    ///
    /// - Parameters:
    ///   - l: Lightness (0-100, where 0=black, 100=white, 50=mid-tone)
    ///   - c: Chroma/saturation (0-150+, where 0=gray, higher=more saturated)
    ///   - h: Hue angle in degrees (0-360, where 0=red, 120=green, 240=blue)
    ///   - alpha: Opacity (0-1)
    static func lch(l: Double, c: Double, h: Double, alpha: Double = 1.0) -> Color {
        // LCH → LAB conversion
        let hRad = h * .pi / 180.0
        let labA = c * cos(hRad)
        let labB = c * sin(hRad)

        // LAB → XYZ conversion (D65 illuminant)
        let fy = (l + 16.0) / 116.0
        let fx = labA / 500.0 + fy
        let fz = fy - labB / 200.0

        let delta = 6.0 / 29.0
        let deltaSquared = delta * delta
        let deltaCubed = delta * delta * delta

        func labInverse(_ t: Double) -> Double {
            t > delta ? t * t * t : 3.0 * deltaSquared * (t - 4.0 / 29.0)
        }

        let xn = 95.047, yn = 100.000, zn = 108.883
        let x = xn * labInverse(fx)
        let y = yn * labInverse(fy)
        let z = zn * labInverse(fz)

        // XYZ → Linear RGB (sRGB color space, D65)
        let rLinear = ( 3.2404542 * x - 1.5371385 * y - 0.4985314 * z) / 100.0
        let gLinear = (-0.9692660 * x + 1.8760108 * y + 0.0415560 * z) / 100.0
        let bLinear = ( 0.0556434 * x - 0.2040259 * y + 1.0572252 * z) / 100.0

        // Linear RGB → sRGB (gamma correction)
        func sRGBCompand(_ linear: Double) -> Double {
            guard linear > 0.0031308 else { return 12.92 * linear }
            return 1.055 * pow(linear, 1.0 / 2.4) - 0.055
        }

        let r = max(0, min(1, sRGBCompand(rLinear)))
        let g = max(0, min(1, sRGBCompand(gLinear)))
        let b = max(0, min(1, sRGBCompand(bLinear)))

        return Color(red: r, green: g, blue: b, opacity: alpha)
    }

    // MARK: - NetHack Category Colors (Minimalist Monochrome + Orange Accent)

    /// PRIMARY ACCENT: Orange - used for highlights, selected states, important actions
    static let nethackAccent = Color.lch(l: 65, c: 75, h: 65)  // Warm orange

    /// Category colors - All monochrome grays with varying lightness for distinction
    /// No colored categories - professional, minimal, focused design

    /// Combat actions - Dark gray (L:45)
    static let nethackCombat = Color.lch(l: 45, c: 8, h: 0)

    /// Movement actions - Medium-dark gray (L:50)
    static let nethackMovement = Color.lch(l: 50, c: 8, h: 0)

    /// Equipment actions - Medium gray (L:55)
    static let nethackEquipment = Color.lch(l: 55, c: 8, h: 0)

    /// Item actions - Medium-light gray (L:60) with slight warm tint
    static let nethackItems = Color.lch(l: 60, c: 10, h: 65)

    /// Magic actions - Light gray (L:65)
    static let nethackMagic = Color.lch(l: 65, c: 8, h: 0)

    /// World interaction - Medium-light gray (L:62)
    static let nethackWorld = Color.lch(l: 62, c: 8, h: 0)

    /// Info/knowledge actions - Light gray (L:67)
    static let nethackInfo = Color.lch(l: 67, c: 8, h: 0)

    /// System actions - Lighter gray (L:70)
    static let nethackSystem = Color.lch(l: 70, c: 8, h: 0)

    // MARK: - Semantic Colors (Minimal - Only Essential)

    /// Success states - ONLY green when truly positive (blessed items)
    static let nethackSuccess = Color.lch(l: 60, c: 55, h: 140)

    /// Warning states - Orange accent (reuse accent color)
    static let nethackWarning = nethackAccent

    /// Error/danger states - ONLY red for real danger (cursed, death)
    static let nethackError = Color.lch(l: 50, c: 60, h: 12)

    /// Info states - gray, no color distraction
    static let nethackInfoSemantic = Color.lch(l: 65, c: 8, h: 0)

    /// BUC Status: Blessed (subtle green)
    static let nethackBlessed = Color.lch(l: 60, c: 55, h: 140)

    /// BUC Status: Uncursed (gray, neutral)
    static let nethackUncursed = Color.lch(l: 60, c: 8, h: 0)

    /// BUC Status: Cursed (red, danger)
    static let nethackCursed = Color.lch(l: 50, c: 60, h: 12)

    /// Enchantment color - orange accent (important info)
    static let nethackEnchantment = nethackAccent

    // MARK: - Context Action Colors

    /// Danger/urgent (red) - for critical HP, fatal conditions
    static let nethackDanger = nethackError

    /// Water/fountain (blue)
    static let nethackWater = Color.lch(l: 60, c: 45, h: 250)

    /// Gold/throne (yellow-gold)
    static let nethackGold = Color.lch(l: 70, c: 55, h: 85)

    // MARK: - Neutral Scale (Consistent Luminance Steps)

    /// Near-black background (L:10)
    static let nethackGray100 = Color.lch(l: 10, c: 3, h: 0)

    /// Very dark gray (L:20)
    static let nethackGray200 = Color.lch(l: 20, c: 3, h: 0)

    /// Dark gray (L:30)
    static let nethackGray300 = Color.lch(l: 30, c: 3, h: 0)

    /// Medium-dark gray (L:40)
    static let nethackGray400 = Color.lch(l: 40, c: 3, h: 0)

    /// Medium gray (L:50)
    static let nethackGray500 = Color.lch(l: 50, c: 3, h: 0)

    /// Medium-light gray (L:60)
    static let nethackGray600 = Color.lch(l: 60, c: 3, h: 0)

    /// Light gray (L:70)
    static let nethackGray700 = Color.lch(l: 70, c: 3, h: 0)

    /// Very light gray (L:80)
    static let nethackGray800 = Color.lch(l: 80, c: 3, h: 0)

    /// Near-white (L:90)
    static let nethackGray900 = Color.lch(l: 90, c: 3, h: 0)

    // MARK: - Terrain/Feature Colors (Minimal)

    /// Stairs up - orange accent (important navigation)
    static let nethackStairsUp = nethackAccent

    /// Stairs down - orange accent (important navigation)
    static let nethackStairsDown = nethackAccent

    /// Altar - orange accent (important feature)
    static let nethackAltar = nethackAccent

    /// Fountain - gray (not important enough for accent)
    static let nethackFountain = Color.lch(l: 60, c: 8, h: 0)

    /// Door - gray (neutral structure)
    static let nethackDoor = Color.lch(l: 55, c: 8, h: 0)
}

// MARK: - Action Categories (9 Balanced Categories)
enum ActionCategory: String, CaseIterable {
    case combat = "Combat"
    case movement = "Movement"
    case equipment = "Equipment"
    case items = "Items"
    case magic = "Magic"
    case world = "World"
    case info = "Info"
    case system = "System"

    var icon: String {
        switch self {
        case .combat: return "bolt.shield.fill"  // Fixed: "sword" doesn't exist in SF Symbols
        case .movement: return "figure.walk"
        case .equipment: return "tshirt.fill"
        case .items: return "backpack.fill"
        case .magic: return "sparkles"
        case .world: return "globe.americas.fill"
        case .info: return "info.circle.fill"
        case .system: return "gear"
        }
    }

    /// LCH-based perceptually uniform category colors
    /// All categories have L=55-65 (equal perceived brightness) with distinct hues
    var color: Color {
        switch self {
        case .combat:    return .nethackCombat      // L:55, C:70, H:12 (red)
        case .movement:  return .nethackMovement    // L:62, C:70, H:140 (green)
        case .equipment: return .nethackEquipment   // L:58, C:55, H:45 (brown)
        case .items:     return .nethackItems       // L:65, C:75, H:65 (orange)
        case .magic:     return .nethackMagic       // L:58, C:75, H:300 (purple)
        case .world:     return .nethackWorld       // L:60, C:65, H:260 (indigo)
        case .info:      return .nethackInfo        // L:62, C:60, H:250 (blue)
        case .system:    return .nethackSystem      // L:60, C:10, H:0 (gray)
        }
    }
}

// MARK: - NetHack Action Model
struct NetHackAction: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let command: String
    let icon: String
    let category: String // Store as String for Codable
    let description: String
    let requiresDirection: Bool
    let requiresTarget: Bool
    let supportsQuantity: Bool  // Whether this action supports quantity selection
    let isWizardOnly: Bool  // Whether this action requires wizard mode

    var categoryEnum: ActionCategory {
        ActionCategory(rawValue: category) ?? .system
    }

    init(id: String? = nil, name: String, command: String, icon: String, category: ActionCategory, description: String, requiresDirection: Bool = false, requiresTarget: Bool = false, supportsQuantity: Bool = false, isWizardOnly: Bool = false) {
        self.id = id ?? command
        self.name = name
        self.command = command
        self.icon = icon
        self.category = category.rawValue
        self.description = description
        self.requiresDirection = requiresDirection
        self.requiresTarget = requiresTarget
        self.supportsQuantity = supportsQuantity
        self.isWizardOnly = isWizardOnly
    }
}

// MARK: - All NetHack Actions (Reorganized into 9 Categories)
extension NetHackAction {
    static let allActions: [NetHackAction] = [
        // MARK: Combat Actions (7)
        NetHackAction(name: "Attack", command: "F", icon: "burst.fill", category: .combat,
                      description: "Force attack in a direction", requiresDirection: true),
        NetHackAction(name: "Fire", command: "f", icon: "arrow.right.circle.fill", category: .combat,
                      description: "Fire ammunition from quiver"),
        NetHackAction(name: "Throw", command: "t", icon: "paperplane.fill", category: .combat,
                      description: "Throw an item", requiresDirection: true, supportsQuantity: true),
        NetHackAction(name: "Kick", command: "C-d", icon: "figure.walk", category: .combat,
                      description: "Kick something", requiresDirection: true),
        NetHackAction(name: "Force", command: "M-f", icon: "hammer.fill", category: .combat,
                      description: "Force a lock"),
        NetHackAction(name: "Technique", command: "#technique", icon: "star.circle.fill", category: .combat,
                      description: "Use a combat technique"),
        NetHackAction(name: "Two Weapon", command: "#twoweapon", icon: "hand.raised.fingers.spread.fill", category: .combat,
                      description: "Toggle two-weapon combat"),

        // MARK: Movement Actions (10) - Including all autotravel
        NetHackAction(name: "Go Up", command: "<", icon: "arrow.up.square", category: .movement,
                      description: "Go up stairs"),
        NetHackAction(name: "Go Down", command: ">", icon: "arrow.down.square", category: .movement,
                      description: "Go down stairs"),
        NetHackAction(name: "Jump", command: "M-j", icon: "figure.jumprope", category: .movement,
                      description: "Jump to another location"),
        NetHackAction(name: "Travel", command: "_", icon: "map.fill", category: .movement,
                      description: "Travel to a specific location", requiresTarget: true),
        NetHackAction(name: "Wait", command: ".", icon: "hourglass", category: .movement,
                      description: "Wait/Rest for a turn"),
        NetHackAction(name: "Search", command: "s", icon: "magnifyingglass", category: .movement,
                      description: "Search for secret doors and traps"),
        NetHackAction(name: "Retravel", command: "C-_", icon: "arrow.uturn.backward.circle.fill", category: .movement,
                      description: "Travel to previous location"),
        // Autotravel Actions
        NetHackAction(id: "travel_stairs_up", name: "Go to Stairs Up", command: "", icon: "arrow.up.square.fill", category: .movement,
                      description: "Automatically travel to upward stairs"),
        NetHackAction(id: "travel_stairs_down", name: "Go to Stairs Down", command: "", icon: "arrow.down.square.fill", category: .movement,
                      description: "Automatically travel to downward stairs"),
        NetHackAction(id: "travel_altar", name: "Go to Altar", command: "", icon: "flame.fill", category: .movement,
                      description: "Automatically travel to nearest altar"),
        NetHackAction(id: "travel_fountain", name: "Go to Fountain", command: "", icon: "drop.triangle.fill", category: .movement,
                      description: "Automatically travel to nearest fountain"),

        // MARK: Equipment Actions (9) - Gear management
        NetHackAction(name: "Wield", command: "w", icon: "hand.raised.fill", category: .equipment,
                      description: "Wield a weapon"),
        NetHackAction(name: "Wear", command: "W", icon: "tshirt.fill", category: .equipment,
                      description: "Wear armor"),
        NetHackAction(name: "Take Off", command: "T", icon: "tshirt", category: .equipment,
                      description: "Take off armor"),
        NetHackAction(name: "Put On", command: "P", icon: "circle.hexagongrid.fill", category: .equipment,
                      description: "Put on accessories"),
        NetHackAction(name: "Remove", command: "R", icon: "circle.hexagongrid", category: .equipment,
                      description: "Remove accessories"),
        NetHackAction(name: "Quiver", command: "Q", icon: "arrow.up.bin.fill", category: .equipment,
                      description: "Ready ammunition"),
        NetHackAction(name: "Apply", command: "a", icon: "wrench.and.screwdriver.fill", category: .equipment,
                      description: "Use a tool"),
        NetHackAction(name: "Swap Weapons", command: "x", icon: "arrow.left.arrow.right", category: .equipment,
                      description: "Swap primary and secondary weapons"),
        NetHackAction(name: "Take Off All", command: "A", icon: "tshirt.slash.fill", category: .equipment,
                      description: "Remove all armor at once"),

        // MARK: Item Actions (7) - Consumables & inventory
        NetHackAction(name: "Inventory", command: "i", icon: "backpack.fill", category: .items,
                      description: "Show your inventory"),
        NetHackAction(name: "Pick Up", command: ",", icon: "arrow.down.square.fill", category: .items,
                      description: "Pick up items"),
        NetHackAction(name: "Drop", command: "d", icon: "arrow.up.square.fill", category: .items,
                      description: "Drop an item", supportsQuantity: true),
        NetHackAction(name: "Drop Type", command: "D", icon: "tray.and.arrow.up.fill", category: .items,
                      description: "Drop specific item types"),
        NetHackAction(name: "Eat", command: "e", icon: "fork.knife", category: .items,
                      description: "Eat something", supportsQuantity: true),
        NetHackAction(name: "Quaff", command: "q", icon: "drop.fill", category: .items,
                      description: "Drink a potion", supportsQuantity: true),
        NetHackAction(name: "Read", command: "r", icon: "book.fill", category: .items,
                      description: "Read a scroll or spellbook", supportsQuantity: true),
        NetHackAction(name: "Inventory Type", command: "I", icon: "list.bullet.rectangle.fill", category: .items,
                      description: "Show inventory of one item class"),
        NetHackAction(name: "Tip", command: "M-T", icon: "arrow.down.to.line.compact", category: .items,
                      description: "Empty a container"),

        // MARK: Magic Actions (6)
        NetHackAction(name: "Cast Spell", command: "Z", icon: "sparkles", category: .magic,
                      description: "Cast a spell from memory"),
        NetHackAction(name: "Zap Wand", command: "z", icon: "wand.and.stars", category: .magic,
                      description: "Zap a wand", requiresDirection: true),
        NetHackAction(name: "Invoke", command: "M-i", icon: "sparkles.rectangle.stack.fill", category: .magic,
                      description: "Invoke an object's special powers"),
        NetHackAction(name: "Pray", command: "#pray", icon: "hands.sparkles.fill", category: .magic,
                      description: "Pray to your deity"),
        NetHackAction(name: "Turn Undead", command: "#turn", icon: "moon.stars.fill", category: .magic,
                      description: "Turn undead creatures"),
        NetHackAction(name: "Monster Ability", command: "#monster", icon: "pawprint.fill", category: .magic,
                      description: "Use monster ability"),
        NetHackAction(name: "Teleport", command: "C-t", icon: "sparkle", category: .magic,
                      description: "Teleport around the level"),
        NetHackAction(name: "Show Spells", command: "+", icon: "text.book.closed.fill", category: .magic,
                      description: "List and reorder known spells"),

        // MARK: World Interaction Actions (12) - Environment & NPCs
        NetHackAction(name: "Open", command: "o", icon: "door.left.hand.open", category: .world,
                      description: "Open a door", requiresDirection: true),
        NetHackAction(name: "Close", command: "c", icon: "door.left.hand.closed", category: .world,
                      description: "Close a door", requiresDirection: true),
        NetHackAction(name: "Chat", command: "M-c", icon: "bubble.left.and.bubble.right.fill", category: .world,
                      description: "Talk to someone"),
        NetHackAction(name: "Pay", command: "p", icon: "creditcard.fill", category: .world,
                      description: "Pay your bill"),
        NetHackAction(name: "Loot", command: "M-l", icon: "shippingbox.fill", category: .world,
                      description: "Loot a container"),
        NetHackAction(name: "Untrap", command: "#untrap", icon: "xmark.shield.fill", category: .world,
                      description: "Disarm a trap"),
        NetHackAction(name: "Engrave", command: "E", icon: "pencil.tip", category: .world,
                      description: "Write on the floor (Elbereth!)"),
        NetHackAction(name: "Dip", command: "M-d", icon: "drop.triangle.fill", category: .world,
                      description: "Dip an object into something"),
        NetHackAction(name: "Rub", command: "#rub", icon: "hand.point.up.left.fill", category: .world,
                      description: "Rub a lamp or stone"),
        NetHackAction(name: "Sit", command: "#sit", icon: "chair.fill", category: .world,
                      description: "Sit down"),
        NetHackAction(name: "Offer", command: "#offer", icon: "gift.fill", category: .world,
                      description: "Sacrifice at an altar"),
        NetHackAction(name: "Ride", command: "#ride", icon: "figure.equestrian.sports", category: .world,
                      description: "Mount or dismount a steed"),
        NetHackAction(name: "Wipe Face", command: "M-w", icon: "face.dashed", category: .world,
                      description: "Wipe off your face"),

        // MARK: Info Actions (11)
        NetHackAction(name: "Look", command: ":", icon: "eye.fill", category: .info,
                      description: "Look at current location"),
        NetHackAction(name: "Look Around", command: ";", icon: "eye.circle.fill", category: .info,
                      description: "Look at map location", requiresTarget: true),
        NetHackAction(name: "Discoveries", command: "\\", icon: "lightbulb.fill", category: .info,
                      description: "Show discovered items"),
        NetHackAction(name: "Named Items", command: "#named", icon: "tag.fill", category: .info,
                      description: "Show named items"),
        NetHackAction(name: "Attributes", command: "C-x", icon: "person.text.rectangle.fill", category: .info,
                      description: "Show your attributes"),
        NetHackAction(name: "Conduct", command: "M-C", icon: "checkmark.shield.fill", category: .info,
                      description: "Show conduct and challenges"),
        NetHackAction(name: "Chronicle", command: "#chronicle", icon: "book.closed.fill", category: .info,
                      description: "Show game chronicle"),
        NetHackAction(name: "What Is", command: "/", icon: "questionmark.circle.fill", category: .info,
                      description: "Identify a symbol"),
        NetHackAction(name: "Help", command: "?", icon: "questionmark.circle", category: .info,
                      description: "Show help"),
        NetHackAction(name: "Overview", command: "C-o", icon: "map.circle.fill", category: .info,
                      description: "Show dungeon overview"),
        NetHackAction(name: "Genocided", command: "M-g", icon: "xmark.circle.fill", category: .info,
                      description: "List genocided monsters"),
        NetHackAction(name: "Previous Messages", command: "C-p", icon: "text.bubble.fill", category: .info,
                      description: "View recent game messages"),
        NetHackAction(name: "Known Class", command: "`", icon: "square.stack.3d.up.fill", category: .info,
                      description: "Show discovered types for one class"),
        NetHackAction(name: "Show Trap", command: "^", icon: "exclamationmark.triangle.fill", category: .info,
                      description: "Describe an adjacent trap"),
        NetHackAction(name: "Vanquished", command: "M-V", icon: "list.star", category: .info,
                      description: "List vanquished monsters"),
        NetHackAction(name: "What Does", command: "&", icon: "keyboard.fill", category: .info,
                      description: "Tell what a command does"),

        // MARK: System Actions - Game management
        // Note: Save/Quit removed - handled by dedicated exit button in UI
        NetHackAction(name: "Options", command: "O", icon: "gearshape.fill", category: .system,
                      description: "Set game options"),
        NetHackAction(name: "Enhance Skills", command: "#enhance", icon: "arrow.up.circle.fill", category: .system,
                      description: "Advance weapon and spell skills"),
        NetHackAction(name: "Autopickup", command: "@", icon: "arrow.down.to.line.circle.fill", category: .system,
                      description: "Toggle autopickup"),
        NetHackAction(name: "Name", command: "C", icon: "pencil.circle.fill", category: .system,
                      description: "Name a monster or object"),
        NetHackAction(name: "Annotate", command: "M-A", icon: "note.text", category: .system,
                      description: "Name current level"),
        NetHackAction(name: "Version", command: "V", icon: "info.square.fill", category: .system,
                      description: "Show version info"),
        NetHackAction(name: "Redraw", command: "C-r", icon: "arrow.clockwise", category: .system,
                      description: "Redraw the screen"),
        NetHackAction(name: "Shell", command: "!", icon: "terminal.fill", category: .system,
                      description: "Shell escape"),
        NetHackAction(name: "Repeat", command: "C-a", icon: "arrow.clockwise.circle.fill", category: .system,
                      description: "Repeat previous command"),

        // MARK: Wizard Mode Actions (only visible when wizard mode enabled)
        // Special iOS action - grants wizard powers at runtime (no NetHack command)
        NetHackAction(id: "ios_grant_wizard", name: "Grant Powers", command: "ios_grant_wizard", icon: "bolt.badge.checkmark.fill", category: .magic,
                      description: "Activate wizard mode for this session", isWizardOnly: true),
        NetHackAction(name: "Wish", command: "#wizwish", icon: "star.fill", category: .magic,
                      description: "Wish for any item", isWizardOnly: true),
        NetHackAction(name: "Identify All", command: "#wizidentify", icon: "eye.trianglebadge.exclamationmark.fill", category: .magic,
                      description: "Identify all items in inventory", isWizardOnly: true),
        NetHackAction(name: "Reveal Map", command: "#wizmap", icon: "map.fill", category: .magic,
                      description: "Reveal the entire level map", isWizardOnly: true),
        NetHackAction(name: "Create Monster", command: "#wizgenesis", icon: "ant.fill", category: .magic,
                      description: "Create any monster", isWizardOnly: true),
        NetHackAction(name: "Level Teleport", command: "#wizlevelport", icon: "arrow.up.arrow.down.square.fill", category: .magic,
                      description: "Teleport to any dungeon level", isWizardOnly: true),
        NetHackAction(name: "Detect Monsters", command: "#wizdetect", icon: "sensor.fill", category: .magic,
                      description: "Detect all monsters on level", isWizardOnly: true),
        NetHackAction(name: "Where Is", command: "#wizwhere", icon: "location.magnifyingglass", category: .magic,
                      description: "Find location of a monster type", isWizardOnly: true),
        NetHackAction(name: "Intrinsic", command: "#wizintrinsic", icon: "sparkle.magnifyingglass", category: .magic,
                      description: "Set or unset an intrinsic", isWizardOnly: true),

        // MARK: Environment Test Actions (for testing visual theming)
        NetHackAction(id: "ios_test_mines", name: "→ Mines", command: "ios_test_mines", icon: "pickaxe", category: .magic,
                      description: "Teleport to Gnomish Mines (cyan tint)", isWizardOnly: true),
        NetHackAction(id: "ios_test_sokoban", name: "→ Sokoban", command: "ios_test_sokoban", icon: "square.grid.3x3", category: .magic,
                      description: "Teleport to Sokoban (yellow tint)", isWizardOnly: true),
        NetHackAction(id: "ios_test_gehennom", name: "→ Gehennom", command: "ios_test_gehennom", icon: "flame", category: .magic,
                      description: "Teleport to Gehennom (orange tint)", isWizardOnly: true),
        NetHackAction(id: "ios_test_vlad", name: "→ Vlad's Tower", command: "ios_test_vlad", icon: "building.columns", category: .magic,
                      description: "Teleport to Vlad's Tower (magenta tint)", isWizardOnly: true),
        NetHackAction(id: "ios_test_astral", name: "→ Astral Plane", command: "ios_test_astral", icon: "sparkles", category: .magic,
                      description: "Teleport to Astral Plane (white tint)", isWizardOnly: true),
    ]

    // MARK: - Wizard Actions (filtered subset)
    static var wizardActions: [NetHackAction] {
        allActions.filter { $0.isWizardOnly }
    }

    // MARK: - Actions filtered by wizard mode
    static func availableActions(wizardModeEnabled: Bool) -> [NetHackAction] {
        if wizardModeEnabled {
            return allActions
        }
        return allActions.filter { !$0.isWizardOnly }
    }

    static func actionsForCategory(_ category: ActionCategory) -> [NetHackAction] {
        allActions.filter { $0.categoryEnum == category }
    }

    static func searchActions(query: String) -> [NetHackAction] {
        guard !query.isEmpty else { return allActions }
        let lowercased = query.lowercased()
        return allActions.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.description.lowercased().contains(lowercased) ||
            $0.command.lowercased().contains(lowercased)
        }
    }
}
