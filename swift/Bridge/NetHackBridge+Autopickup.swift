//
//  NetHackBridge+Autopickup.swift
//  nethack
//
//  Swift bridge for NetHack autopickup system.
//  Wraps C functions from RealNetHackBridge.h and applies
//  user preferences from UserPreferencesManager.
//

import Foundation

// MARK: - Autopickup Bridge Service

/// Service for managing autopickup settings
/// Bridges Swift preferences to NetHack C engine flags
@MainActor
class AutopickupBridgeService {

    static let shared = AutopickupBridgeService()

    private init() {}

    // MARK: - Public API

    /// Apply user's autopickup preferences to the C engine
    /// Call this after game start and after settings changes
    func applyUserPreferences() {
        let userPrefs = UserPreferencesManager.shared

        // Check if Tools is enabled in stored prefs - FIX IT PERMANENTLY
        var categories = userPrefs.getAutopickupCategories()
        if let toolsIndex = categories.firstIndex(where: { $0.symbol == "(" && $0.enabled }) {
            print("[AutopickupBridge] ⚠️ Tools was ENABLED in stored prefs! Fixing permanently...")
            categories[toolsIndex].enabled = false
            userPrefs.setAutopickupCategories(categories)
        }

        // Get enabled state
        let enabled = userPrefs.isAutopickupEnabled()
        ios_set_autopickup_enabled(enabled ? 1 : 0)

        // Get category types string (should NOT contain "(" now)
        var types = userPrefs.getAutopickupTypesString()

        // SAFETY: Double-check Tools is stripped
        if types.contains("(") {
            print("[AutopickupBridge] ⚠️ SAFETY: Stripping Tools '(' from types")
            types = types.replacingOccurrences(of: "(", with: "")
        }

        // Apply to C engine
        types.withCString { cTypes in
            ios_set_autopickup_types(cTypes)
        }
        print("[AutopickupBridge] ✅ Applied: enabled=\(enabled), types=\"\(types)\"")
    }

    /// Set autopickup enabled state directly
    /// - Parameter enabled: true to enable, false to disable
    func setEnabled(_ enabled: Bool) {
        ios_set_autopickup_enabled(enabled ? 1 : 0)
    }

    /// Set autopickup types directly
    /// - Parameter types: Object class symbols (e.g., "$\"?!/=(+")
    func setTypes(_ types: String) {
        types.withCString { cTypes in
            ios_set_autopickup_types(cTypes)
        }
    }

    /// Get current autopickup types from C engine
    /// - Returns: Current pickup_types string
    func getTypes() -> String {
        guard let cTypes = ios_get_autopickup_types() else {
            return ""
        }
        return String(cString: cTypes)
    }

    /// Check if autopickup is currently enabled in C engine
    /// - Returns: true if autopickup is enabled
    func isEnabled() -> Bool {
        return ios_is_autopickup_enabled() == 1
    }
}
