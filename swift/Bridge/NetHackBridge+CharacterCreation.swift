import Foundation

// =============================================================================
// NetHackBridge+CharacterCreation - Character Creation Functions
// =============================================================================
//
// This extension handles character creation:
// - Role/Race/Gender/Alignment queries and selection
// - Player name setting
// - Character validation and finalization
// - Lazy symbol resolution for character creation C functions
//
// =============================================================================

extension NetHackBridge {

    // MARK: - Lazy Wrappers (C Function Calls)

    internal func nethack_get_available_roles() throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_get_available_roles == nil {
            _nethack_get_available_roles = try dylib.resolveFunction("nethack_get_available_roles")
        }
        guard let fn = _nethack_get_available_roles else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_available_roles")
        }
        return fn()
    }

    internal func nethack_set_role(_ role: Int32) throws {
        try ensureDylibLoaded()
        if _nethack_set_role == nil {
            _nethack_set_role = try dylib.resolveFunction("nethack_set_role")
        }
        _nethack_set_role?(role)
    }

    internal func nethack_validate_character_selection() throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_validate_character_selection == nil {
            _nethack_validate_character_selection = try dylib.resolveFunction("nethack_validate_character_selection")
        }
        guard let fn = _nethack_validate_character_selection else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_validate_character_selection")
        }
        return fn()
    }

    internal func nethack_finalize_character() throws {
        try ensureDylibLoaded()
        if _nethack_finalize_character == nil {
            _nethack_finalize_character = try dylib.resolveFunction("nethack_finalize_character")
        }
        _nethack_finalize_character?()
    }

    internal func nethack_get_role_name(_ rolenum: Int32) throws -> UnsafePointer<CChar> {
        try ensureDylibLoaded()
        if _nethack_get_role_name == nil {
            _nethack_get_role_name = try dylib.resolveFunction("nethack_get_role_name")
        }
        guard let fn = _nethack_get_role_name else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_role_name")
        }
        return fn(rolenum)
    }

    internal func nethack_get_available_races_for_role(_ rolenum: Int32) throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_get_available_races_for_role == nil {
            _nethack_get_available_races_for_role = try dylib.resolveFunction("nethack_get_available_races_for_role")
        }
        guard let fn = _nethack_get_available_races_for_role else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_available_races_for_role")
        }
        return fn(rolenum)
    }

    internal func nethack_get_race_name(_ racenum: Int32) throws -> UnsafePointer<CChar> {
        try ensureDylibLoaded()
        if _nethack_get_race_name == nil {
            _nethack_get_race_name = try dylib.resolveFunction("nethack_get_race_name")
        }
        guard let fn = _nethack_get_race_name else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_race_name")
        }
        return fn(racenum)
    }

    internal func nethack_get_available_genders_for_role(_ rolenum: Int32) throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_get_available_genders_for_role == nil {
            _nethack_get_available_genders_for_role = try dylib.resolveFunction("nethack_get_available_genders_for_role")
        }
        guard let fn = _nethack_get_available_genders_for_role else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_available_genders_for_role")
        }
        return fn(rolenum)
    }

    internal func nethack_get_gender_name(_ gendnum: Int32) throws -> UnsafePointer<CChar> {
        try ensureDylibLoaded()
        if _nethack_get_gender_name == nil {
            _nethack_get_gender_name = try dylib.resolveFunction("nethack_get_gender_name")
        }
        guard let fn = _nethack_get_gender_name else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_gender_name")
        }
        return fn(gendnum)
    }

    internal func nethack_get_available_alignments_for_role(_ rolenum: Int32) throws -> Int32 {
        try ensureDylibLoaded()
        if _nethack_get_available_alignments_for_role == nil {
            _nethack_get_available_alignments_for_role = try dylib.resolveFunction("nethack_get_available_alignments_for_role")
        }
        guard let fn = _nethack_get_available_alignments_for_role else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_available_alignments_for_role")
        }
        return fn(rolenum)
    }

    internal func nethack_get_alignment_name(_ alignnum: Int32) throws -> UnsafePointer<CChar> {
        try ensureDylibLoaded()
        if _nethack_get_alignment_name == nil {
            _nethack_get_alignment_name = try dylib.resolveFunction("nethack_get_alignment_name")
        }
        guard let fn = _nethack_get_alignment_name else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "nethack_get_alignment_name")
        }
        return fn(alignnum)
    }

    internal func nethack_set_race(_ racenum: Int32) throws {
        try ensureDylibLoaded()
        if _nethack_set_race == nil {
            _nethack_set_race = try dylib.resolveFunction("nethack_set_race")
        }
        _nethack_set_race?(racenum)
    }

    internal func nethack_set_gender(_ gendnum: Int32) throws {
        try ensureDylibLoaded()
        if _nethack_set_gender == nil {
            _nethack_set_gender = try dylib.resolveFunction("nethack_set_gender")
        }
        _nethack_set_gender?(gendnum)
    }

    internal func nethack_set_alignment(_ alignnum: Int32) throws {
        try ensureDylibLoaded()
        if _nethack_set_alignment == nil {
            _nethack_set_alignment = try dylib.resolveFunction("nethack_set_alignment")
        }
        _nethack_set_alignment?(alignnum)
    }

    internal func nethack_set_player_name(_ name: UnsafePointer<CChar>) throws {
        try ensureDylibLoaded()
        if _nethack_set_player_name == nil {
            _nethack_set_player_name = try dylib.resolveFunction("nethack_set_player_name")
        }
        _nethack_set_player_name?(name)
    }

    // MARK: - Role Queries

    /// Get number of available roles
    func getAvailableRoles() -> Int {
        print("[Bridge] 🔵 getAvailableRoles() START")
        print("[Bridge] 🔵 isInitialized = \(isInitialized)")
        if !isInitialized {
            print("[Bridge] 🔵 NOT initialized - calling initializeGame()...")
            initializeGame()
            print("[Bridge] 🔵 initializeGame() completed, isInitialized = \(isInitialized)")
        } else {
            print("[Bridge] 🔵 Already initialized, skipping initializeGame()")
        }
        do {
            print("[Bridge] 🔵 Calling nethack_get_available_roles()...")
            let result = Int(try nethack_get_available_roles())
            print("[Bridge] 🔵 nethack_get_available_roles() returned: \(result)")
            return result
        } catch {
            print("[Bridge] ❌ Failed to get available roles: \(error)")
            return 0
        }
    }

    /// Get role name by index
    func getRoleName(_ roleIdx: Int) -> String {
        if !isInitialized {
            print("[Bridge] Initializing NetHack for character creation...")
            initializeGame()
        }
        do {
            return String(cString: try nethack_get_role_name(Int32(roleIdx)))
        } catch {
            return "Unknown"
        }
    }

    // MARK: - Race Queries

    /// Get number of available races for a role
    func getAvailableRacesForRole(_ roleIdx: Int) -> Int {
        if !isInitialized {
            print("[Bridge] Initializing NetHack for character creation...")
            initializeGame()
        }
        do {
            return Int(try nethack_get_available_races_for_role(Int32(roleIdx)))
        } catch {
            return 0
        }
    }

    /// Get race name by index
    func getRaceName(_ raceIdx: Int) -> String {
        if !isInitialized {
            print("[Bridge] Initializing NetHack for character creation...")
            initializeGame()
        }
        do {
            return String(cString: try nethack_get_race_name(Int32(raceIdx)))
        } catch {
            return "Unknown"
        }
    }

    // MARK: - Gender Queries

    /// Get number of available genders for a role
    func getAvailableGendersForRole(_ roleIdx: Int) -> Int {
        if !isInitialized {
            print("[Bridge] Initializing NetHack for character creation...")
            initializeGame()
        }
        do {
            return Int(try nethack_get_available_genders_for_role(Int32(roleIdx)))
        } catch {
            return 0
        }
    }

    /// Get gender name by index
    func getGenderName(_ genderIdx: Int) -> String {
        if !isInitialized {
            print("[Bridge] Initializing NetHack for character creation...")
            initializeGame()
        }
        do {
            return String(cString: try nethack_get_gender_name(Int32(genderIdx)))
        } catch {
            return "Unknown"
        }
    }

    // MARK: - Alignment Queries

    /// Get number of available alignments for a role
    func getAvailableAlignmentsForRole(_ roleIdx: Int) -> Int {
        if !isInitialized {
            print("[Bridge] Initializing NetHack for character creation...")
            initializeGame()
        }
        do {
            return Int(try nethack_get_available_alignments_for_role(Int32(roleIdx)))
        } catch {
            return 0
        }
    }

    /// Get alignment name by index
    func getAlignmentName(_ alignIdx: Int) -> String {
        if !isInitialized {
            print("[Bridge] Initializing NetHack for character creation...")
            initializeGame()
        }
        do {
            return String(cString: try nethack_get_alignment_name(Int32(alignIdx)))
        } catch {
            return "Unknown"
        }
    }

    // MARK: - Character Selection Setters

    /// Set player name (stored in Swift to survive dylib reload)
    func setPlayerName(_ name: String) {
        // CRITICAL: Store in Swift first (survives dylib reload)
        pendingPlayerName = name
        print("[Bridge] 🔧 setPlayerName('\(name)') - Stored in pending, calling C layer")

        if !isInitialized {
            print("[Bridge] Initializing NetHack for character creation...")
            initializeGame()
        }
        do {
            try name.withCString { cString in
                try nethack_set_player_name(cString)
            }
        } catch {
            print("[Bridge] Failed to set player name: \(error)")
        }
    }

    /// Set role (stored in Swift to survive dylib reload)
    func setRole(_ roleIdx: Int) {
        // CRITICAL: Store in Swift first (survives dylib reload)
        pendingRole = Int32(roleIdx)
        print("[Bridge] 🔧 setRole(\(roleIdx)) - Stored in pending, calling C layer")
        do {
            try nethack_set_role(Int32(roleIdx))
        } catch {
            print("[Bridge] ❌ Failed to set role: \(error)")
        }
    }

    /// Set race (stored in Swift to survive dylib reload)
    func setRace(_ raceIdx: Int) {
        // CRITICAL: Store in Swift first (survives dylib reload)
        pendingRace = Int32(raceIdx)
        print("[Bridge] 🔧 setRace(\(raceIdx)) - Stored in pending, calling C layer")
        do {
            try nethack_set_race(Int32(raceIdx))
        } catch {
            print("[Bridge] Failed to set race: \(error)")
        }
    }

    /// Set gender (stored in Swift to survive dylib reload)
    func setGender(_ genderIdx: Int) {
        // CRITICAL: Store in Swift first (survives dylib reload)
        pendingGender = Int32(genderIdx)
        print("[Bridge] 🔧 setGender(\(genderIdx)) - Stored in pending, calling C layer")
        do {
            try nethack_set_gender(Int32(genderIdx))
        } catch {
            print("[Bridge] Failed to set gender: \(error)")
        }
    }

    /// Set alignment (stored in Swift to survive dylib reload)
    func setAlignment(_ alignIdx: Int) {
        // CRITICAL: Store in Swift first (survives dylib reload)
        pendingAlignment = Int32(alignIdx)
        print("[Bridge] 🔧 setAlignment(\(alignIdx)) - Stored in pending, calling C layer")
        do {
            try nethack_set_alignment(Int32(alignIdx))
        } catch {
            print("[Bridge] ❌ Failed to set alignment: \(error)")
        }
    }

    // MARK: - Character Finalization

    /// Validate current character selection
    /// - Returns: 0 if valid, error code otherwise
    func validateCharacterSelection() -> Int {
        do {
            return Int(try nethack_validate_character_selection())
        } catch {
            print("[Bridge] ❌ Failed to validate character selection: \(error)")
            return -1
        }
    }

    /// Finalize character and prepare for game start
    func finalizeCharacter() {
        do {
            try nethack_finalize_character()
        } catch {
            print("[Bridge] ❌ Failed to finalize character: \(error)")
        }
    }
}
