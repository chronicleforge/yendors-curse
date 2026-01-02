//
//  ZIndexRegistry.swift
//  nethack
//
//  Central z-index management for all UI layers.
//  All overlay elements MUST get their z-index from here.
//
//  Usage:
//    .zIndex(ZIndex.messages)
//    .zIndex(ZIndex.above(.messages))
//    .zIndex(ZIndex.below(.equipmentPanel))
//

import SwiftUI

// MARK: - Z-Index Layer Definition

/// All UI layers in the app, ordered from bottom to top
enum ZIndexLayer: Int, CaseIterable, Comparable {
    // Base game layers (0-10)
    case gameMap = 0
    case mapOverlays = 1          // Grid, coordinates
    case statusBar = 3

    // Action UI layers (50-80)
    case actionBar = 50
    case contextMenu = 74
    case actionWheel = 75
    case directionPicker = 76
    case inspectTooltip = 77
    case targetPicker = 79
    case confirmationDialog = 81

    // Overlay layers (85-99)
    case messages = 85            // Game messages toast - stays visible
    case equipmentPanel = 87      // Hero Panel (Equipment/Abilities) - can be open during selection
    case fullscreenInventory = 89

    // Modal layers (95-99) - ABOVE all persistent overlays
    case itemSelection = 95       // Item selection sheet (eat, quaff, etc.) - MODAL
    case quantityPicker = 96      // Quantity picker - appears after item selection
    case escapeWarning = 98       // Escape warning - critical game-ending decision

    // Critical/Modal layers (100+)
    case deathScreen = 100
    case exitOverlay = 101
    case systemAlert = 110

    // Comparison
    static func < (lhs: ZIndexLayer, rhs: ZIndexLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Z-Index Registry

/// Central registry for z-index values
/// Use ZIndex.layer or ZIndex.above/below for all overlay z-indices
enum ZIndex {
    /// Get the z-index for a specific layer
    static func layer(_ layer: ZIndexLayer) -> Double {
        Double(layer.rawValue)
    }

    /// Get a z-index value above the specified layer
    /// Returns midpoint between this layer and next layer
    static func above(_ layer: ZIndexLayer) -> Double {
        let current = layer.rawValue
        let allLayers = ZIndexLayer.allCases.sorted()

        // Find next layer
        guard let currentIndex = allLayers.firstIndex(of: layer),
              currentIndex + 1 < allLayers.count else {
            return Double(current + 5)  // No next layer, just add 5
        }

        let nextLayer = allLayers[currentIndex + 1]
        // Return midpoint
        return Double(current + nextLayer.rawValue) / 2.0
    }

    /// Get a z-index value below the specified layer
    /// Returns midpoint between this layer and previous layer
    static func below(_ layer: ZIndexLayer) -> Double {
        let current = layer.rawValue
        let allLayers = ZIndexLayer.allCases.sorted()

        // Find previous layer
        guard let currentIndex = allLayers.firstIndex(of: layer),
              currentIndex > 0 else {
            return Double(current - 1)  // No previous layer, just subtract 1
        }

        let prevLayer = allLayers[currentIndex - 1]
        // Return midpoint
        return Double(prevLayer.rawValue + current) / 2.0
    }

    // MARK: - Convenience Accessors

    static var gameMap: Double { layer(.gameMap) }
    static var statusBar: Double { layer(.statusBar) }
    static var actionBar: Double { layer(.actionBar) }
    static var contextMenu: Double { layer(.contextMenu) }
    static var actionWheel: Double { layer(.actionWheel) }
    static var directionPicker: Double { layer(.directionPicker) }
    static var inspectTooltip: Double { layer(.inspectTooltip) }
    static var quantityPicker: Double { layer(.quantityPicker) }
    static var targetPicker: Double { layer(.targetPicker) }
    static var itemSelection: Double { layer(.itemSelection) }
    static var confirmationDialog: Double { layer(.confirmationDialog) }
    static var messages: Double { layer(.messages) }
    static var equipmentPanel: Double { layer(.equipmentPanel) }
    static var fullscreenInventory: Double { layer(.fullscreenInventory) }
    static var escapeWarning: Double { layer(.escapeWarning) }
    static var deathScreen: Double { layer(.deathScreen) }
    static var exitOverlay: Double { layer(.exitOverlay) }
    static var systemAlert: Double { layer(.systemAlert) }
}

// MARK: - Debug Helper

#if DEBUG
extension ZIndex {
    /// Print all layers in order for debugging
    static func printHierarchy() {
        print("=== Z-Index Hierarchy ===")
        for layer in ZIndexLayer.allCases.sorted() {
            print("  \(layer.rawValue): \(layer)")
        }
        print("========================")
    }
}
#endif
