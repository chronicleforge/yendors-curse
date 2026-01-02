import Foundation

// =============================================================================
// NetHackBridge+Conduct - Voluntary Challenges Tracking
// =============================================================================
//
// Provides access to conduct data from NetHack C engine.
// Conducts are voluntary challenges - 0 means conduct maintained.
// =============================================================================

extension NetHackBridge {

    // MARK: - Function Pointer Storage

    private static var _ios_get_conduct_json: (@convention(c) () -> UnsafePointer<CChar>?)?

    // MARK: - Conduct Access

    /// Fetch conduct data from the C engine
    func getConductData() -> ConductData? {
        do {
            try ensureDylibLoaded()

            if Self._ios_get_conduct_json == nil {
                Self._ios_get_conduct_json = try dylib.resolveFunction("ios_get_conduct_json")
            }

            guard let jsonPtr = Self._ios_get_conduct_json?() else {
                return nil
            }

            let jsonString = String(cString: jsonPtr)

            guard let data = jsonString.data(using: .utf8) else {
                return nil
            }

            let decoder = JSONDecoder()
            return try decoder.decode(ConductData.self, from: data)

        } catch {
            print("[Conduct] Failed to fetch data: \(error)")
            return nil
        }
    }
}

// MARK: - Raw Conduct Data

struct ConductData: Decodable {
    // Conduct violations (0 = maintained)
    let unvegetarian: Int
    let unvegan: Int
    let food: Int
    let gnostic: Int
    let weaphit: Int
    let killer: Int
    let literate: Int
    let polypiles: Int
    let polyselfs: Int
    let wishes: Int
    let wisharti: Int
    let sokocheat: Int
    let pets: Int

    // Roleplay flags (permanent challenges)
    let blind: Int
    let deaf: Int
    let nudist: Int
    let pauper: Int

    // Context
    let sokoban_entered: Int
    let genocides: Int
    let turns: Int

    /// Get list of conduct entries for display
    func getConductEntries() -> [ConductEntry] {
        var entries: [ConductEntry] = []

        // Permanent roleplay challenges (always show if active)
        if blind == 1 {
            entries.append(ConductEntry(
                name: "Blind",
                description: "Blind from birth",
                status: .permanent,
                icon: "eye.slash.fill"
            ))
        }
        if deaf == 1 {
            entries.append(ConductEntry(
                name: "Deaf",
                description: "Deaf from birth",
                status: .permanent,
                icon: "ear.trianglebadge.exclamationmark"
            ))
        }
        if nudist == 1 {
            entries.append(ConductEntry(
                name: "Nudist",
                description: "Never worn armor",
                status: .maintained,
                icon: "figure.stand"
            ))
        }
        if pauper == 1 {
            entries.append(ConductEntry(
                name: "Pauper",
                description: "Started without possessions",
                status: .permanent,
                icon: "banknote"
            ))
        }

        // Food conducts (hierarchical: foodless > vegan > vegetarian)
        if food == 0 {
            entries.append(ConductEntry(
                name: "Foodless",
                description: "Gone without food",
                status: .maintained,
                icon: "fork.knife.circle"
            ))
        } else if unvegan == 0 {
            entries.append(ConductEntry(
                name: "Vegan",
                description: "Strict vegan diet",
                status: .maintained,
                icon: "leaf.fill"
            ))
        } else if unvegetarian == 0 {
            entries.append(ConductEntry(
                name: "Vegetarian",
                description: "No meat consumed",
                status: .maintained,
                icon: "carrot.fill"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Vegetarian",
                description: "Eaten meat \(unvegetarian)x",
                status: .broken,
                icon: "carrot"
            ))
        }

        // Atheist
        if gnostic == 0 {
            entries.append(ConductEntry(
                name: "Atheist",
                description: "No prayer or altars",
                status: .maintained,
                icon: "sparkle"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Atheist",
                description: "Used religion \(gnostic)x",
                status: .broken,
                icon: "sparkle"
            ))
        }

        // Weaponless
        if weaphit == 0 {
            entries.append(ConductEntry(
                name: "Weaponless",
                description: "Never hit with weapon",
                status: .maintained,
                icon: "hand.raised.slash.fill"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Weaponless",
                description: "Hit with weapon \(weaphit)x",
                status: .broken,
                icon: "hand.raised.slash"
            ))
        }

        // Pacifist
        if killer == 0 {
            entries.append(ConductEntry(
                name: "Pacifist",
                description: "Killed no monsters",
                status: .maintained,
                icon: "peacesign"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Pacifist",
                description: "Killed \(killer) monsters",
                status: .broken,
                icon: "peacesign"
            ))
        }

        // Illiterate
        if literate == 0 {
            entries.append(ConductEntry(
                name: "Illiterate",
                description: "Never read anything",
                status: .maintained,
                icon: "text.book.closed.fill"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Illiterate",
                description: "Read \(literate)x",
                status: .broken,
                icon: "text.book.closed"
            ))
        }

        // Petless
        if pets == 0 {
            entries.append(ConductEntry(
                name: "Petless",
                description: "Never had a pet",
                status: .maintained,
                icon: "pawprint.fill"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Petless",
                description: "Had \(pets) pet(s)",
                status: .broken,
                icon: "pawprint"
            ))
        }

        // Genocide-free
        if genocides == 0 {
            entries.append(ConductEntry(
                name: "Genocide-free",
                description: "Never genocided",
                status: .maintained,
                icon: "xmark.circle.fill"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Genocide-free",
                description: "Genocided \(genocides) type(s)",
                status: .broken,
                icon: "xmark.circle"
            ))
        }

        // Polymorph-free (objects)
        if polypiles == 0 {
            entries.append(ConductEntry(
                name: "Polypileless",
                description: "Never polymorphed items",
                status: .maintained,
                icon: "wand.and.rays"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Polypileless",
                description: "Polymorphed \(polypiles) items",
                status: .broken,
                icon: "wand.and.rays"
            ))
        }

        // Polymorph-free (self)
        if polyselfs == 0 {
            entries.append(ConductEntry(
                name: "Polyselfless",
                description: "Never changed form",
                status: .maintained,
                icon: "person.and.arrow.left.and.arrow.right"
            ))
        } else {
            entries.append(ConductEntry(
                name: "Polyselfless",
                description: "Changed form \(polyselfs)x",
                status: .broken,
                icon: "person.and.arrow.left.and.arrow.right"
            ))
        }

        // Wishless
        if wishes == 0 {
            entries.append(ConductEntry(
                name: "Wishless",
                description: "Used no wishes",
                status: .maintained,
                icon: "wand.and.stars"
            ))
        } else {
            let artifactNote = wisharti > 0 ? " (\(wisharti) artifact)" : ""
            entries.append(ConductEntry(
                name: "Wishless",
                description: "Used \(wishes) wish(es)\(artifactNote)",
                status: .broken,
                icon: "wand.and.stars"
            ))
        }

        // Sokoban (only show if entered)
        if sokoban_entered == 1 {
            if sokocheat == 0 {
                entries.append(ConductEntry(
                    name: "Sokoban",
                    description: "No rule violations",
                    status: .maintained,
                    icon: "square.grid.3x3.fill"
                ))
            } else {
                entries.append(ConductEntry(
                    name: "Sokoban",
                    description: "Violated rules \(sokocheat)x",
                    status: .broken,
                    icon: "square.grid.3x3"
                ))
            }
        }

        return entries
    }
}

// MARK: - Conduct Entry for Display

struct ConductEntry: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let status: ConductStatus
    let icon: String
}

enum ConductStatus {
    case maintained  // Conduct kept (green)
    case broken      // Conduct violated (gray)
    case permanent   // Permanent roleplay (blue)

    var color: String {
        switch self {
        case .maintained: return "green"
        case .broken: return "gray"
        case .permanent: return "blue"
        }
    }
}
