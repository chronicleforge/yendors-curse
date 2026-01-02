//
//  TileTapHandler.swift
//  nethack
//
//  Chain-of-Responsibility Pattern for Tile Tap Handling
//  Similar to JavaScript event bubbling with stopPropagation
//
//  Priority Order:
//  0. Inspect Mode (highest) - when active, examine tile
//  1. Auto Travel - travel to walkable tiles
//  n. Future: Context actions, other handlers
//

import SwiftUI

// MARK: - Travel Queue Manager

/// Manages queued travel destinations for responsive travel.
/// When user taps during travel, the new destination is queued and
/// executed immediately when current travel completes.
final class TravelQueueManager {
    static let shared = TravelQueueManager()

    /// Next queued destination (only one - newer taps replace older ones)
    private var queuedDestination: (x: Int, y: Int)?

    /// Reference to game manager for travel execution
    private weak var gameManager: NetHackGameManager?

    /// Timer to poll travel completion
    private var pollTimer: Timer?

    /// Track if we're currently polling
    private var isPolling = false

    private init() {}

    /// Configure with game manager reference
    func configure(gameManager: NetHackGameManager) {
        self.gameManager = gameManager
    }

    /// Queue a new travel destination
    /// Always executes immediately - the C bridge handles interrupt/queue internally
    func queueTravel(x: Int, y: Int) {
        guard let gameManager = gameManager else { return }
        gameManager.travelTo(x: x, y: y)
    }

    /// Clear any queued destination (e.g., when game ends)
    func clearQueue() {
        queuedDestination = nil
        stopPolling()
    }

    private func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkTravelCompletion()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    private func checkTravelCompletion() {
        guard let gameManager = gameManager else {
            stopPolling()
            return
        }
        if !gameManager.isTraveling() {
            if let dest = queuedDestination {
                queuedDestination = nil
                gameManager.travelTo(x: dest.x, y: dest.y)
            } else {
                stopPolling()
            }
        }
    }
}

// MARK: - Strategy Protocol

/// Strategy Protocol for Tile Tap Handling
protocol TileTapHandler {
    /// Priority: Lower = higher priority (0 = first)
    var priority: Int { get }

    /// Returns true if handler consumed the tap, false to continue chain
    func handleTap(x: Int, y: Int, tile: MapTile?, gameManager: NetHackGameManager) -> Bool
}

// MARK: - Handler 1: Inspect Mode

/// Inspect Mode Handler - Priority 0 (highest)
/// Examines tile when inspect mode is active
class InspectTapHandler: TileTapHandler {
    var priority: Int { 0 }

    // Closure for inspectTile function (async for thread-safe C bridge access)
    var inspectTile: (Int, Int) async -> Void

    init(inspectTile: @escaping (Int, Int) async -> Void) {
        self.inspectTile = inspectTile
    }

    func handleTap(x: Int, y: Int, tile: MapTile?, gameManager: NetHackGameManager) -> Bool {
        guard gameManager.inspectModeActive else {
            return false
        }

        Task {
            await inspectTile(x, y)
        }

        return true
    }
}

// MARK: - Handler 2: Auto Travel

/// Auto Travel Handler - Priority 1
/// Travels to walkable tiles when tapped
/// Uses TravelQueueManager to queue destinations during active travel
class AutoTravelTapHandler: TileTapHandler {
    var priority: Int { 1 }

    func handleTap(x: Int, y: Int, tile: MapTile?, gameManager: NetHackGameManager) -> Bool {
        // Ignore if player is already on this tile
        guard x != gameManager.mapState.playerX || y != gameManager.mapState.playerY else {
            return false
        }

        // Check if tile is walkable
        guard let tile = tile, isWalkable(tile) else {
            return false
        }

        showTravelIndicator(at: (x, y))
        HapticManager.shared.tap()
        TravelQueueManager.shared.queueTravel(x: x, y: y)

        return true
    }

    /// Check if tile is walkable
    private func isWalkable(_ tile: MapTile) -> Bool {
        // Walkable types: floor, corridor, open door, stairs, items, gold, monsters
        switch tile.type {
        case .floor, .corridor, .doorOpen, .stairs:
            return true
        case .item, .gold, .food, .weapon, .armor, .potion, .scroll, .wand, .ring, .amulet, .tool:
            return true  // Can walk on items
        case .fountain, .altar, .throne, .sink:
            return true  // Special terrain you can stand on
        case .monster:
            return true  // Can attack/displace
        case .wall, .doorClosed, .water, .lava, .trap:
            return false  // Blocked or dangerous
        default:
            return false  // Unknown, be conservative
        }
    }

    /// Show visual feedback for travel target
    private func showTravelIndicator(at coords: (Int, Int)) {
        // TODO: Implement visual pulse effect on target tile
        // Could use NotificationCenter or a shared state manager
    }
}

// MARK: - Handler Chain Manager

/// Chain of Responsibility Manager
/// Processes tap through registered handlers in priority order
class TileTapHandlerChain {
    private var handlers: [TileTapHandler] = []

    /// Register a new handler in the chain
    func register(_ handler: TileTapHandler) {
        handlers.append(handler)
        handlers.sort { $0.priority < $1.priority }
    }

    /// Process tap through handler chain
    func handleTap(x: Int, y: Int, tile: MapTile?, gameManager: NetHackGameManager) {
        for handler in handlers {
            if handler.handleTap(x: x, y: y, tile: tile, gameManager: gameManager) {
                return
            }
        }
    }
}

// MARK: - Inspect Mode Delegate Protocol (DEPRECATED)
// Replaced with closure-based delegation to work with SwiftUI structs
// See InspectTapHandler init(isInspectModeActive:inspectTile:)
