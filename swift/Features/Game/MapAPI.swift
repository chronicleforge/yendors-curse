//
//  MapAPI.swift
//  nethack
//
//  Coordinate-aware wrappers for ObjectBridgeWrapper
//
//  DESIGN PRINCIPLE: All public APIs use Swift coordinates
//  Conversion to NetHack coordinates happens internally at FFI boundary
//

import Foundation

/// Coordinate-aware map query API
/// Wraps ObjectBridgeWrapper with type-safe coordinate conversion
enum MapAPI {

    // MARK: - Object Queries

    /// Get all objects at Swift coordinate
    /// - Parameter swift: Swift coordinate (0-based)
    /// - Returns: Array of objects at position (empty if none)
    static func getObjectsAt(swift coord: SwiftCoord) -> [GameObjectInfo] {
        // Convert to NetHack coordinate for bridge call
        let nh = CoordinateConverter.swiftToNetHack(coord)
        let (nhX, nhY) = nh.forCBridge()

        // Call existing ObjectBridgeWrapper with NetHack coordinates
        return ObjectBridgeWrapper.getObjectsAt(x: nhX, y: nhY)
    }

    // MARK: - Adjacency Helpers

    /// Get objects in all 8 adjacent tiles
    /// - Parameter swift: Center coordinate
    /// - Returns: Dictionary of adjacent coordinates to object arrays
    static func getAdjacentObjects(swift coord: SwiftCoord) -> [SwiftCoord: [GameObjectInfo]] {
        var result: [SwiftCoord: [GameObjectInfo]] = [:]

        for adjacent in coord.adjacent8 {
            let objects = getObjectsAt(swift: adjacent)
            if !objects.isEmpty {
                result[adjacent] = objects
            }
        }

        return result
    }

    /// Find nearest coordinate matching predicate
    /// - Parameters:
    ///   - swift: Starting coordinate
    ///   - maxDistance: Maximum manhattan distance to search
    ///   - predicate: Test function for each coordinate
    /// - Returns: Nearest matching coordinate, or nil if none found
    static func findNearest(from coord: SwiftCoord, maxDistance: Int, matching predicate: (SwiftCoord) -> Bool) -> SwiftCoord? {
        guard maxDistance > 0 else { return nil }

        // Check center first
        if predicate(coord) {
            return coord
        }

        // Search in expanding rings
        for distance in 1...maxDistance {
            for dy in -distance...distance {
                for dx in -distance...distance {
                    // Skip if not on ring perimeter
                    guard abs(dx) == distance || abs(dy) == distance else { continue }

                    if let candidate = coord.adjacent(dx: dx, dy: dy), predicate(candidate) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Async Wrappers (CONC-S-001, CONC-S-004)

    /// Get all objects at Swift coordinate (async, non-blocking)
    /// - Parameter swift: Swift coordinate (0-based)
    /// - Returns: Array of objects at position (empty if none)
    /// - Note: Dispatches to NetHackSerialExecutor for thread-safe C bridge access
    static func getObjectsAtAsync(swift coord: SwiftCoord) async -> [GameObjectInfo] {
        await withCheckedContinuation { continuation in
            NetHackSerialExecutor.shared.queue.async {
                let result = Self.getObjectsAt(swift: coord)
                continuation.resume(returning: result)
            }
        }
    }

    /// Get objects in all 8 adjacent tiles (async, batch query)
    /// - Parameter swift: Center coordinate
    /// - Returns: Dictionary of adjacent coordinates to object arrays
    /// - Note: More efficient than 8 separate async calls - single queue dispatch
    static func getAdjacentObjectsAsync(swift coord: SwiftCoord) async -> [SwiftCoord: [GameObjectInfo]] {
        await withCheckedContinuation { continuation in
            NetHackSerialExecutor.shared.queue.async {
                let result = Self.getAdjacentObjects(swift: coord)
                continuation.resume(returning: result)
            }
        }
    }
}
