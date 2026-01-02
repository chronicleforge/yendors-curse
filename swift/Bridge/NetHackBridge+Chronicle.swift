import Foundation

// =============================================================================
// NetHackBridge+Chronicle - Hero's Chronicle Access
// =============================================================================
//
// Provides access to the gamelog (chronicle) from NetHack C engine.
// The chronicle logs major game events: wishes, artifacts, divine gifts, etc.
//
// Uses ios_gamelog_json() for efficient bulk transfer of all entries.
// =============================================================================

extension NetHackBridge {

    // MARK: - Function Pointer Storage

    private static var _ios_gamelog_json: (@convention(c) () -> UnsafePointer<CChar>?)?

    // MARK: - Chronicle Access

    /// Fetch all chronicle entries from the C engine as JSON
    /// Returns array of ChronicleEntry structs
    func getChronicleEntries() -> [ChronicleEntry] {
        do {
            try ensureDylibLoaded()

            if Self._ios_gamelog_json == nil {
                Self._ios_gamelog_json = try dylib.resolveFunction("ios_gamelog_json")
            }

            guard let jsonPtr = Self._ios_gamelog_json?() else {
                return []
            }

            let jsonString = String(cString: jsonPtr)

            guard let data = jsonString.data(using: .utf8) else {
                return []
            }

            let decoder = JSONDecoder()
            let rawEntries = try decoder.decode([RawChronicleEntry].self, from: data)

            return rawEntries.map { ChronicleEntry(from: $0) }

        } catch {
            print("[Chronicle] Failed to fetch entries: \(error)")
            return []
        }
    }
}

// MARK: - Raw JSON Entry (from C)

private struct RawChronicleEntry: Decodable {
    let turn: Int
    let flags: Int
    let text: String
}

// MARK: - Chronicle Entry Model

struct ChronicleEntry: Identifiable {
    let id: UUID
    let turn: Int
    let flags: Int
    let text: String
    let eventType: ChronicleEventType
    let rarity: ChronicleRarity

    fileprivate init(from raw: RawChronicleEntry) {
        self.id = UUID()
        self.turn = raw.turn
        self.flags = raw.flags
        self.text = raw.text
        self.eventType = ChronicleEventType.from(flags: raw.flags)
        self.rarity = ChronicleRarity.from(flags: raw.flags)
    }

    /// Convenience init for previews and testing
    init(turn: Int, flags: Int, text: String) {
        self.id = UUID()
        self.turn = turn
        self.flags = flags
        self.text = text
        self.eventType = ChronicleEventType.from(flags: flags)
        self.rarity = ChronicleRarity.from(flags: flags)
    }
}

// MARK: - Event Type Classification

enum ChronicleEventType: String, CaseIterable {
    case wish
    case artifact
    case divineGift
    case genocide
    case achievement
    case uniqueMonster
    case lifesave
    case alignment
    case conduct
    case killedPet
    case minorAchievement
    case other

    // LL_* flags from global.h
    private static let LL_WISH: Int       = 0x0001
    private static let LL_ACHIEVE: Int    = 0x0002
    private static let LL_UMONST: Int     = 0x0004
    private static let LL_DIVINEGIFT: Int = 0x0008
    private static let LL_LIFESAVE: Int   = 0x0010
    private static let LL_CONDUCT: Int    = 0x0020
    private static let LL_ARTIFACT: Int   = 0x0040
    private static let LL_GENOCIDE: Int   = 0x0080
    private static let LL_KILLEDPET: Int  = 0x0100
    private static let LL_ALIGNMENT: Int  = 0x0200
    private static let LL_MINORAC: Int    = 0x1000

    static func from(flags: Int) -> ChronicleEventType {
        // Priority order for mixed flags
        if flags & LL_WISH != 0 { return .wish }
        if flags & LL_ARTIFACT != 0 { return .artifact }
        if flags & LL_DIVINEGIFT != 0 { return .divineGift }
        if flags & LL_GENOCIDE != 0 { return .genocide }
        if flags & LL_LIFESAVE != 0 { return .lifesave }
        if flags & LL_UMONST != 0 { return .uniqueMonster }
        if flags & LL_ALIGNMENT != 0 { return .alignment }
        if flags & LL_KILLEDPET != 0 { return .killedPet }
        if flags & LL_CONDUCT != 0 { return .conduct }
        if flags & LL_ACHIEVE != 0 { return .achievement }
        if flags & LL_MINORAC != 0 { return .minorAchievement }
        return .other
    }

    var icon: String {
        switch self {
        case .wish: return "wand.and.stars"
        case .artifact: return "sparkles"
        case .divineGift: return "gift.fill"
        case .genocide: return "xmark.circle.fill"
        case .achievement: return "trophy.fill"
        case .uniqueMonster: return "person.crop.circle.badge.xmark"
        case .lifesave: return "heart.circle.fill"
        case .alignment: return "arrow.triangle.branch"
        case .conduct: return "book.closed.fill"
        case .killedPet: return "pawprint.fill"
        case .minorAchievement: return "star.fill"
        case .other: return "scroll.fill"
        }
    }

    var label: String {
        switch self {
        case .wish: return "Wish"
        case .artifact: return "Artifact"
        case .divineGift: return "Divine"
        case .genocide: return "Genocide"
        case .achievement: return "Achievement"
        case .uniqueMonster: return "Unique"
        case .lifesave: return "Lifesave"
        case .alignment: return "Alignment"
        case .conduct: return "Conduct"
        case .killedPet: return "Pet"
        case .minorAchievement: return "Minor"
        case .other: return "Event"
        }
    }
}

// MARK: - Rarity Classification

enum ChronicleRarity: Int, Comparable {
    case minor = 0
    case major = 1
    case epic = 2
    case legendary = 3

    static func < (lhs: ChronicleRarity, rhs: ChronicleRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static let LL_WISH: Int       = 0x0001
    private static let LL_ACHIEVE: Int    = 0x0002
    private static let LL_UMONST: Int     = 0x0004
    private static let LL_DIVINEGIFT: Int = 0x0008
    private static let LL_LIFESAVE: Int   = 0x0010
    private static let LL_ARTIFACT: Int   = 0x0040
    private static let LL_GENOCIDE: Int   = 0x0080
    private static let LL_MINORAC: Int    = 0x1000

    static func from(flags: Int) -> ChronicleRarity {
        // Legendary: Wishes, Divine Crowning
        if flags & LL_WISH != 0 { return .legendary }

        // Epic: Artifacts, Divine Gifts, Lifesaving
        if flags & LL_ARTIFACT != 0 { return .epic }
        if flags & LL_DIVINEGIFT != 0 { return .epic }
        if flags & LL_LIFESAVE != 0 { return .epic }

        // Major: Genocide, Major Achievements, Unique Monsters
        if flags & LL_GENOCIDE != 0 { return .major }
        if flags & LL_ACHIEVE != 0 { return .major }
        if flags & LL_UMONST != 0 { return .major }

        // Minor: Everything else
        return .minor
    }
}
