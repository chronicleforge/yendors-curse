import Foundation

// =============================================================================
// NetHackBridge+YNResponse - Yes/No Callback Management
// =============================================================================
//
// This extension handles yn (yes/no) callback configuration:
// - Automatic yes/no responses
// - UI confirmation mode
// - Single-response overrides
// - Lazy symbol resolution for YN C functions
//
// =============================================================================

extension NetHackBridge {

    // MARK: - Lazy Wrappers (C Function Calls)

    internal func nethack_set_yn_auto_yes_wrap() throws {
        try ensureDylibLoaded()
        if _nethack_set_yn_auto_yes == nil {
            _nethack_set_yn_auto_yes = try dylib.resolveFunction("nethack_set_yn_auto_yes")
        }
        _nethack_set_yn_auto_yes?()
    }

    internal func nethack_set_yn_auto_no_wrap() throws {
        try ensureDylibLoaded()
        if _nethack_set_yn_auto_no == nil {
            _nethack_set_yn_auto_no = try dylib.resolveFunction("nethack_set_yn_auto_no")
        }
        _nethack_set_yn_auto_no?()
    }

    internal func nethack_set_yn_ask_user_wrap() throws {
        try ensureDylibLoaded()
        if _nethack_set_yn_ask_user == nil {
            _nethack_set_yn_ask_user = try dylib.resolveFunction("nethack_set_yn_ask_user")
        }
        _nethack_set_yn_ask_user?()
    }

    internal func nethack_set_yn_default_wrap() throws {
        try ensureDylibLoaded()
        if _nethack_set_yn_default == nil {
            _nethack_set_yn_default = try dylib.resolveFunction("nethack_set_yn_default")
        }
        _nethack_set_yn_default?()
    }

    internal func nethack_set_next_yn_response_wrap(_ response: CChar) throws {
        try ensureDylibLoaded()
        if _nethack_set_next_yn_response == nil {
            _nethack_set_next_yn_response = try dylib.resolveFunction("nethack_set_next_yn_response")
        }
        _nethack_set_next_yn_response?(response)
    }

    // MARK: - High-Level YN Functions

    /// Execute a block with automatic yes responses
    func withAutoYes<T>(_ block: () async throws -> T) async rethrows -> T {
        try? nethack_set_yn_auto_yes_wrap()
        defer { try? nethack_set_yn_default_wrap() }
        return try await block()
    }

    /// Execute a block with automatic no responses
    func withAutoNo<T>(_ block: () async throws -> T) async rethrows -> T {
        try? nethack_set_yn_auto_no_wrap()
        defer { try? nethack_set_yn_default_wrap() }
        return try await block()
    }

    /// Execute a block with UI confirmation mode
    func withUIConfirmation<T>(_ block: () async throws -> T) async rethrows -> T {
        try? nethack_set_yn_ask_user_wrap()
        defer { try? nethack_set_yn_default_wrap() }
        return try await block()
    }

    /// Set a specific response for the next yn question
    func setNextYNResponse(_ response: Character) {
        let cChar = CChar(response.asciiValue ?? 0)
        try? nethack_set_next_yn_response_wrap(cChar)
    }

    /// Enable automatic yes for all yn questions
    func enableAutoYes() {
        try? nethack_set_yn_auto_yes_wrap()
    }

    /// Enable automatic no for all yn questions
    func enableAutoNo() {
        try? nethack_set_yn_auto_no_wrap()
    }

    /// Enable UI confirmation for yn questions
    func enableUIConfirmation() {
        try? nethack_set_yn_ask_user_wrap()
    }

    /// Reset to default yn behavior
    func resetYNBehavior() {
        try? nethack_set_yn_default_wrap()
    }
}
