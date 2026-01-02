//
//  NetHackCoordinate.swift
//  nethack
//
//  Type-safe coordinate system for NetHack iOS Port
//
//  ROOT CAUSE FIX: Coordinate space confusion between NetHack (1-based X) and Swift (0-based)
//  See: claude-files/coordinate-bug-rca.md for full analysis
//
//  DESIGN PRINCIPLE: Make wrong coordinate usage a COMPILE ERROR
//

import Foundation

// MARK: - Global Constants

/// SINGLE SOURCE OF TRUTH for SceneKit tile size
/// All coordinate transformations MUST use this constant
public let kSceneKitTileSize: Float = 2.5

// MARK: - NetHack Coordinates (1-based X, 0-based Y)

/// NetHack coordinate system (used in NetHack C engine)
/// - X: 1-79 (1-based, column 0 unused)
/// - Y: 0-20 (0-based)
/// - Used for: levl[x][y], u.ux/u.uy, NetHack API calls
struct NetHackCoord: Equatable, Hashable {
    // Private storage prevents direct access to raw values
    private let _x: Int  // 1-79
    private let _y: Int  // 0-20

    // PRIVATE initializer - use CoordinateConverter or factory methods
    fileprivate init(_x: Int, _y: Int) {
        self._x = _x
        self._y = _y
    }
    
    // MARK: - FFI Boundary (Only for C bridge calls)
    
    /// Convert to C bridge parameters
    /// - Returns: Tuple with Int32 values for C FFI
    func forCBridge() -> (x: Int32, y: Int32) {
        return (Int32(_x), Int32(_y))
    }
    
    // MARK: - Coordinate-Space-Aware Arithmetic
    
    /// Get adjacent coordinate with delta
    /// - Parameters:
    ///   - dx: X offset
    ///   - dy: Y offset
    /// - Returns: Adjacent coordinate if within bounds, nil otherwise
    func adjacent(dx: Int, dy: Int) -> NetHackCoord? {
        let newX = _x + dx
        let newY = _y + dy
        
        // NetHack bounds: X=1-79, Y=0-20
        guard newX >= 1 && newX < 80 && newY >= 0 && newY < 21 else {
            return nil
        }
        
        return NetHackCoord(_x: newX, _y: newY)
    }
    
    /// Get all 8 adjacent coordinates (cardinal + diagonal)
    var adjacent8: [NetHackCoord] {
        let deltas = [(-1,-1), (0,-1), (1,-1), (-1,0), (1,0), (-1,1), (0,1), (1,1)]
        return deltas.compactMap { adjacent(dx: $0.0, dy: $0.1) }
    }
    
    /// Get 4 cardinal adjacent coordinates (no diagonals)
    var adjacent4: [NetHackCoord] {
        let deltas = [(0,-1), (-1,0), (1,0), (0,1)]
        return deltas.compactMap { adjacent(dx: $0.0, dy: $0.1) }
    }
    
    // MARK: - Debug Only
    
    #if DEBUG
    /// Debug description (DO NOT use for logic!)
    var debugDescription: String {
        return "NH(\(_x),\(_y))"
    }
    #endif
}

// MARK: - Swift Coordinates (0-based X and Y)

/// Swift coordinate system (used in Swift array indices)
/// - X: 0-78 (0-based)
/// - Y: 0-20 (0-based)
/// - Used for: tiles[y][x], Swift UI geometry
struct SwiftCoord: Equatable, Hashable {
    // Private storage prevents direct access to raw values
    private let _x: Int  // 0-78
    private let _y: Int  // 0-20

    // PRIVATE initializer - use CoordinateConverter or factory methods
    fileprivate init(_x: Int, _y: Int) {
        self._x = _x
        self._y = _y
    }
    
    // MARK: - Array Access (Only for Swift array subscripts)
    
    /// Get array indices for tiles[y][x] access
    /// - Returns: Tuple (x, y) for array subscripting
    var arrayIndices: (x: Int, y: Int) {
        return (_x, _y)
    }
    
    // MARK: - Coordinate-Space-Aware Arithmetic
    
    /// Get adjacent coordinate with delta
    /// - Parameters:
    ///   - dx: X offset
    ///   - dy: Y offset
    /// - Returns: Adjacent coordinate if within bounds, nil otherwise
    func adjacent(dx: Int, dy: Int) -> SwiftCoord? {
        let newX = _x + dx
        let newY = _y + dy
        
        // Swift bounds: X=0-78, Y=0-20
        guard newX >= 0 && newX < 79 && newY >= 0 && newY < 21 else {
            return nil
        }
        
        return SwiftCoord(_x: newX, _y: newY)
    }
    
    /// Get all 8 adjacent coordinates (cardinal + diagonal)
    var adjacent8: [SwiftCoord] {
        let deltas = [(-1,-1), (0,-1), (1,-1), (-1,0), (1,0), (-1,1), (0,1), (1,1)]
        return deltas.compactMap { adjacent(dx: $0.0, dy: $0.1) }
    }
    
    /// Get 4 cardinal adjacent coordinates (no diagonals)
    var adjacent4: [SwiftCoord] {
        let deltas = [(0,-1), (-1,0), (1,0), (0,1)]
        return deltas.compactMap { adjacent(dx: $0.0, dy: $0.1) }
    }
    
    // MARK: - Debug Only
    
    #if DEBUG
    /// Debug description (DO NOT use for logic!)
    var debugDescription: String {
        return "SW(\(_x),\(_y))"
    }
    #endif
}

// MARK: - Coordinate Conversion (Single Source of Truth)

/// Single source of truth for coordinate conversions
/// DO NOT duplicate conversion logic elsewhere!
enum CoordinateConverter {
    
    // MARK: - Primary Conversions
    
    /// Convert NetHack coordinate to Swift coordinate
    /// - Parameter nh: NetHack coordinate (X=1-79, Y=0-20)
    /// - Returns: Swift coordinate (X=0-78, Y=0-20)
    static func nethackToSwift(_ nh: NetHackCoord) -> SwiftCoord {
        let (nhX, nhY) = nh.forCBridge()
        // NetHack X is 1-based → subtract 1 for Swift 0-based
        // NetHack Y is already 0-based → use directly
        return SwiftCoord(_x: Int(nhX) - 1, _y: Int(nhY))
    }

    /// Convert Swift coordinate to NetHack coordinate
    /// - Parameter sw: Swift coordinate (X=0-78, Y=0-20)
    /// - Returns: NetHack coordinate (X=1-79, Y=0-20)
    static func swiftToNetHack(_ sw: SwiftCoord) -> NetHackCoord {
        let (swX, swY) = sw.arrayIndices
        // Swift X is 0-based → add 1 for NetHack 1-based
        // Swift Y is already 0-based → use directly
        return NetHackCoord(_x: swX + 1, _y: swY)
    }
    
    // MARK: - Render Queue Boundary (From C)
    
    /// Create Swift coordinate from render queue update
    /// - Parameters:
    ///   - x: NetHack X from ios_print_glyph (1-based)
    ///   - y: NetHack Y from ios_print_glyph (0-based)
    /// - Returns: Swift coordinate if valid, nil if out of bounds
    static func fromRenderUpdate(x: Int32, y: Int32) -> SwiftCoord? {
        // Render queue sends NetHack coordinates
        let swiftX = Int(x) - 1  // Convert 1-based to 0-based
        let swiftY = Int(y)       // Already 0-based
        
        // Validate bounds
        guard swiftX >= 0 && swiftX < 79 && swiftY >= 0 && swiftY < 21 else {
            return nil
        }
        
        return SwiftCoord(_x: swiftX, _y: swiftY)
    }
    
    // MARK: - Validation Factories
    
    /// Create validated Swift coordinate from raw values
    /// - Parameters:
    ///   - x: Raw X value (must be 0-78)
    ///   - y: Raw Y value (must be 0-20)
    /// - Returns: Swift coordinate if valid, nil if out of bounds
    static func makeSwift(x: Int, y: Int) -> SwiftCoord? {
        guard x >= 0 && x < 79 && y >= 0 && y < 21 else {
            return nil
        }
        return SwiftCoord(_x: x, _y: y)
    }

    /// Create validated NetHack coordinate from raw values
    /// - Parameters:
    ///   - x: Raw X value (must be 1-79)
    ///   - y: Raw Y value (must be 0-20)
    /// - Returns: NetHack coordinate if valid, nil if out of bounds
    static func makeNetHack(x: Int, y: Int) -> NetHackCoord? {
        guard x >= 1 && x < 80 && y >= 0 && y < 21 else {
            return nil
        }
        return NetHackCoord(_x: x, _y: y)
    }
}

// MARK: - Array Extensions (Type-Safe Subscripts)

extension Array where Element == [MapTile?] {
    /// Type-safe subscript for tile grid access
    /// - Parameter coord: Swift coordinate (automatically enforces correct space)
    /// - Returns: Tile at coordinate
    subscript(coord: SwiftCoord) -> MapTile? {
        get {
            let (x, y) = coord.arrayIndices
            return self[y][x]
        }
        set {
            let (x, y) = coord.arrayIndices
            self[y][x] = newValue
        }
    }
}

extension Array where Element == [TileVisibility] {
    /// Type-safe subscript for visibility grid access
    /// - Parameter coord: Swift coordinate
    /// - Returns: Visibility state at coordinate
    subscript(coord: SwiftCoord) -> TileVisibility {
        get {
            let (x, y) = coord.arrayIndices
            return self[y][x]
        }
        set {
            let (x, y) = coord.arrayIndices
            self[y][x] = newValue
        }
    }
}

extension Array where Element == [Float] {
    /// Type-safe subscript for light level grid access
    /// - Parameter coord: Swift coordinate
    /// - Returns: Light level at coordinate
    subscript(coord: SwiftCoord) -> Float {
        get {
            let (x, y) = coord.arrayIndices
            return self[y][x]
        }
        set {
            let (x, y) = coord.arrayIndices
            self[y][x] = newValue
        }
    }
}

// MARK: - Compile-Time Safety Verification
// These tests verify that wrong patterns don't compile
#if DEBUG && false  // Set to true to verify compile errors
private func _verifyCompileTimeSafety() {
    // ❌ Test 1: Can't access raw coordinates
    let coord = CoordinateConverter.makeSwift(x: 5, y: 10)!
    let x = coord.x  // ERROR: 'x' is inaccessible due to 'private' protection level

    // ❌ Test 2: Can't mix coordinate types
    let nh = CoordinateConverter.makeNetHack(x: 5, y: 10)!
    MapAPI.getTerrainAt(swift: nh)  // ERROR: Cannot convert value of type 'NetHackCoord' to expected argument type 'SwiftCoord'

    // ❌ Test 3: Can't bypass converter
    let coord2 = SwiftCoord(_x: 5, _y: 10)  // ERROR: 'SwiftCoord' initializer is inaccessible due to 'fileprivate' protection level

    // ❌ Test 4: Can't do raw arithmetic
    let bad = coord.x + 1  // ERROR: 'x' is inaccessible due to 'private' protection level

    // ❌ Test 5: Can't create coords without validation
    let invalidCoord = SwiftCoord(x: 100, y: 100)  // ERROR: Argument labels '(x:, y:)' do not match any available overloads
}
#endif
