import Foundation

// =============================================================================
// NetHackBridge+Discoveries - Discovered Items Access
// =============================================================================
//
// Provides access to discovered items using the disco[] array (vanilla behavior).
// Only returns items that have been encountered/discovered by the player.
//
// Uses ios_get_discoveries_json() for efficient bulk transfer.
// =============================================================================

extension NetHackBridge {

    // MARK: - Function Pointer Storage

    private static var _ios_get_discoveries_json: (@convention(c) () -> UnsafePointer<CChar>?)?

    // MARK: - Discoveries Access

    /// Fetch discovered items from the C engine using disco[] array
    /// Returns array of RawDiscoveryEntry structs (matches vanilla's dodiscovered() behavior)
    func getDiscoveredItems() -> [RawDiscoveryEntry] {
        do {
            try ensureDylibLoaded()

            if Self._ios_get_discoveries_json == nil {
                Self._ios_get_discoveries_json = try dylib.resolveFunction("ios_get_discoveries_json")
            }

            guard let jsonPtr = Self._ios_get_discoveries_json?() else {
                return []
            }

            let jsonString = String(cString: jsonPtr)

            guard let data = jsonString.data(using: .utf8) else {
                return []
            }

            let decoder = JSONDecoder()
            return try decoder.decode([RawDiscoveryEntry].self, from: data)

        } catch {
            print("[Discoveries] Failed to fetch entries: \(error)")
            return []
        }
    }
}

// MARK: - Raw JSON Entry (from C)

/// Raw discovery entry from C bridge
struct RawDiscoveryEntry: Decodable {
    let otyp: Int
    let oclass: Int
    let name: String
    let description: String?
    let is_known: Bool
    let is_encountered: Bool
    let is_unique: Bool

    // Map JSON keys
    enum CodingKeys: String, CodingKey {
        case otyp
        case oclass
        case name
        case description
        case is_known
        case is_encountered
        case is_unique
    }
}
