//
//  SceneKitMapView.swift
//  nethack
//
//  SceneKit-based 2.5D map renderer with visibility layers
//

import SwiftUI
import SceneKit

// Gruvbox Dark color scheme
struct GruvboxColors {
    static let background = UIColor(red: 0x32/255.0, green: 0x30/255.0, blue: 0x2f/255.0, alpha: 1.0)
    static let foreground = UIColor(red: 0xeb/255.0, green: 0xdb/255.0, blue: 0xb2/255.0, alpha: 1.0)

    // Normal colors
    static let black = UIColor(red: 0x28/255.0, green: 0x28/255.0, blue: 0x28/255.0, alpha: 1.0)
    static let red = UIColor(red: 0xcc/255.0, green: 0x24/255.0, blue: 0x1d/255.0, alpha: 1.0)
    static let green = UIColor(red: 0x98/255.0, green: 0x97/255.0, blue: 0x1a/255.0, alpha: 1.0)
    static let yellow = UIColor(red: 0xd7/255.0, green: 0x99/255.0, blue: 0x21/255.0, alpha: 1.0)
    static let blue = UIColor(red: 0x45/255.0, green: 0x85/255.0, blue: 0x88/255.0, alpha: 1.0)
    static let magenta = UIColor(red: 0xb1/255.0, green: 0x62/255.0, blue: 0x86/255.0, alpha: 1.0)
    static let cyan = UIColor(red: 0x68/255.0, green: 0x9d/255.0, blue: 0x6a/255.0, alpha: 1.0)
    static let white = UIColor(red: 0xa8/255.0, green: 0x99/255.0, blue: 0x84/255.0, alpha: 1.0)
}

// SceneKit-based map view for 2.5D rendering with hit-testing
struct SceneKitMapView: UIViewRepresentable {
    var mapState: MapState
    @Binding var selectedTile: (x: Int, y: Int)?
    var onTileTap: ((Int, Int) -> Void)?
    var onSceneViewCreated: ((SCNView) -> Void)?  // Callback for screenshot service
    let tileSize: Float = kSceneKitTileSize  // Use global constant

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        // Gruvbox Dark background
        scnView.backgroundColor = GruvboxColors.background
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false  // No rotation - fixed 2D view
        scnView.antialiasingMode = .multisampling2X
        scnView.showsStatistics = false  // Hide stats for cleaner view

        // Create scene
        let scene = SCNScene()
        scnView.scene = scene

        // Setup gesture recognizers through coordinator
        context.coordinator.setupGestures(for: scnView)

        // Notify callback with created view (for screenshot service)
        onSceneViewCreated?(scnView)

        // Setup camera
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 25  // Zoom level - adjusted for larger tiles
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode.camera = camera
        // Start camera at origin, will be updated to follow player
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 30)
        cameraNode.look(at: SCNVector3(x: 0, y: 0, z: 0),
                       up: SCNVector3(x: 0, y: 1, z: 0),
                       localFront: SCNVector3(x: 0, y: 0, z: -1))
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        // Setup lighting
        setupLighting(scene: scene)

        // Setup fog for unexplored areas
        setupFog(scene: scene)

        // Store coordinator and initialize map updater
        context.coordinator.scnView = scnView
        context.coordinator.mapUpdater = MapUpdateCoordinator()
        context.coordinator.mapUpdater?.scene = scene
        context.coordinator.mapUpdater?.scnView = scnView

        // Hook up SCNSceneRendererDelegate for frame-based full refresh
        scnView.delegate = context.coordinator.mapUpdater

        // CRITICAL FIX #7: Initial map render for RESTORE case
        // When a game is RESTORED, the sequence is:
        //   1. ios_restore_complete() → docrt() → tiles rendered to queue
        //   2. ios_notify_map_changed() → Swift notification
        //   3. SceneKitMapView.makeUIView() ← WE ARE HERE
        // The tiles are already in the render queue, but scene didn't exist yet!
        // Solution: Immediately consume render queue after scene creation
        let timestamp = String(format: "%.3f", CACurrentMediaTime())
        print("[\(timestamp)] [SceneKitMapView] makeUIView: Scene created - checking for pending tiles...")
        context.coordinator.mapUpdater?.updateMap(mapState: mapState)
        print("[\(timestamp)] [SceneKitMapView] makeUIView: Initial render complete")

        return scnView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        // Store SCNView reference for gesture handling
        context.coordinator.scnView = scnView

        // FIX: Explicitly read tileUpdateCounter to trigger SwiftUI observation
        // @Observable doesn't detect tiles[y][x] mutations, so we use this counter
        // Reading it here tells SwiftUI to call updateUIView when it changes
        let _ = mapState.tileUpdateCounter

        // Create map update coordinator for map rendering if needed
        Log.verbose(.sceneKit, "updateUIView called at \(CACurrentMediaTime() * 1000)ms (tileUpdates: \(mapState.tileUpdateCounter))")

        if context.coordinator.mapUpdater == nil {
            context.coordinator.mapUpdater = MapUpdateCoordinator()
        }
        context.coordinator.mapUpdater?.scnView = scnView
        context.coordinator.mapUpdater?.scene = scnView.scene
        context.coordinator.mapUpdater?.updateMap(mapState: mapState)
    }

    private func setupLighting(scene: SCNScene) {
        // For 2D roguelike: minimal lighting, tiles are self-illuminated
        // Only add subtle ambient for any 3D effects we might add later
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 100  // Very subtle
        ambientLight.light?.color = GruvboxColors.foreground
        ambientLight.name = "ambientLight"
        scene.rootNode.addChildNode(ambientLight)

        // No player light needed - tiles emit their own light
    }

    private func setupFog(scene: SCNScene) {
        // Disable fog completely - it might be hiding tiles
        // scene.fogColor = UIColor.black
        // scene.fogStartDistance = 15
        // scene.fogEndDistance = 25
        // scene.fogDensityExponent = 2
    }

    // MapUpdateCoordinator to manage SceneKit updates
    class MapUpdateCoordinator: NSObject, SCNSceneRendererDelegate {
        weak var scnView: SCNView?
        weak var scene: SCNScene?
        var tileNodes: [[SCNNode?]] = []
        var lastPlayerX: Int = -1
        var lastPlayerY: Int = -1
        let tileSize: Float = kSceneKitTileSize  // Use global constant

        // SMART THROTTLE: Track tile changes to avoid skipping real updates
        var lastUpdateTime: TimeInterval = 0
        var lastTileUpdateCounter: Int = -1

        // PERF: Full refresh removed - was rebuilding 2000 tiles every second
        // Incremental updates via tileUpdateCounter are sufficient

        func updateMap(mapState: MapState) {
            // CRITICAL: Don't access game state after death - memory may be freed
            guard NetHackBridge.shared.gameStarted else {
                Log.verbose(.mapUpdate, "Game not running - skipping update")
                return
            }

            guard let scene = scene else {
                Log.verbose(.mapUpdate, "No scene - returning")
                return
            }

            // SMART THROTTLE: Only throttle REDUNDANT calls, never skip REAL updates
            // - If tileUpdateCounter changed → tiles actually changed → MUST render
            // - If tileUpdateCounter same + within 30ms → redundant SwiftUI call → skip
            let now = CACurrentMediaTime()
            let timeSinceLastUpdate = now - lastUpdateTime
            let tilesActuallyChanged = mapState.tileUpdateCounter != lastTileUpdateCounter

            Log.verbose(.mapUpdate, "updateMap - changed:\(tilesActuallyChanged) dt:\(Int(timeSinceLastUpdate * 1000))ms")

            if !tilesActuallyChanged && timeSinceLastUpdate < 0.03 {
                // Redundant call - no tile changes AND within throttle window
                Log.verbose(.mapUpdate, "THROTTLED - No changes")
                return
            }

            // Real update OR enough time passed - render!
            Log.verbose(.mapUpdate, "RENDERING")
            lastUpdateTime = now
            lastTileUpdateCounter = mapState.tileUpdateCounter

            // Map dimensions and player position available

            // Initialize tile nodes array if needed
            if tileNodes.count != mapState.height || (tileNodes.first?.count ?? 0) != mapState.width {
                clearTiles()
                tileNodes = Array(repeating: Array(repeating: nil, count: mapState.width), count: mapState.height)
            }

            // FIX: Invalidate nodes where tile content changed
            // Node name format: "tile_x_y_CHAR" - compare CHAR with current tile
            for y in 0..<tileNodes.count {
                for x in 0..<(tileNodes[y].count) {
                    guard let node = tileNodes[y][x] else { continue }
                    let tile = mapState.tiles[safe: y]?[safe: x] ?? nil
                    let currentChar: Character = tile?.character ?? " "

                    // Extract cached character from node name (last component after _)
                    let cachedChar: Character = {
                        guard let name = node.name,
                              let lastPart = name.split(separator: "_").last,
                              let char = lastPart.first else { return "\0" }
                        return char
                    }()

                    // If character changed, invalidate node
                    if cachedChar != currentChar {
                        node.removeFromParentNode()
                        tileNodes[y][x] = nil
                    }
                }
            }

            // Update tiles
            var tilesCreated = 0
            var firstTilePos: SCNVector3?
            for y in 0..<mapState.height {
                for x in 0..<mapState.width {
                    updateTile(x: x, y: y, mapState: mapState, scene: scene)
                    if let node = tileNodes[y][x] {
                        tilesCreated += 1
                        if firstTilePos == nil {
                            firstTilePos = node.position
                        }
                    }
                }
            }
            // Tile nodes created and positioned

            // Update camera to follow player
            updateCameraPosition(mapState: mapState)

            // Update player light position
            updatePlayerLight(mapState: mapState)
        }

        private func updateTile(x: Int, y: Int, mapState: MapState, scene: SCNScene) {
            let tile = mapState.tiles[safe: y]?[safe: x] ?? nil

            // PERF FIX: Only recreate if node was invalidated (set to nil in first pass)
            // Valid nodes already exist and don't need recreation
            if tileNodes[y][x] != nil {
                return  // Node still valid from cache, skip recreation
            }

            // For now, just render any tile that exists (ignore visibility system)
            guard let tileToRender = tile else { return }

            // Skip empty spaces for now
            if tileToRender.character == " " {
                return
            }

            // Create tile node (use visible for now)
            let node = createTileNode(tile: tileToRender, visibility: .visible, x: x, y: y)

            // Position tile - validate coordinate first
            guard CoordinateConverter.makeSwift(x: x, y: y) != nil else {
                let timestamp = String(format: "%.3f", CACurrentMediaTime())
                print("[\(timestamp)] [COORD] ERROR: Invalid coordinate [SW:\(x),\(y)]")
                return
            }
            // Convert to SceneKit 3D position
            let sceneKitPos = SCNVector3(
                x: Float(x) * tileSize - Float(mapState.width) * tileSize / 2,
                y: -Float(y) * tileSize + Float(mapState.height) * tileSize / 2,
                z: 0
            )
            node.position = sceneKitPos
            scene.rootNode.addChildNode(node)
            tileNodes[y][x] = node
        }

        private func createTileNode(tile: MapTile, visibility: TileVisibility, x: Int, y: Int) -> SCNNode {
            let node = SCNNode()
            // Set node name for hit-testing AND cache invalidation
            // Format: tile_x_y_CHAR - allows checking if tile content changed
            node.name = "tile_\(x)_\(y)_\(tile.character)"
            
            // PERFORMANCE: CategoryBitMask = 1 for hitTest filtering
            // This allows hitTest to ONLY check tile nodes (ignores UI, lights, etc.)
            node.categoryBitMask = 1

            // Create plane geometry for tile
            let plane = SCNPlane(width: CGFloat(tileSize), height: CGFloat(tileSize))

            // Create material with unlit/emissive rendering for 2D look
            let material = SCNMaterial()
            material.lightingModel = .constant  // No lighting calculations
            material.isDoubleSided = true  // Visible from both sides

            // Gruvbox color based on tile type
            let tileColor: UIColor
            switch tile.type {
            case .wall:
                tileColor = GruvboxColors.white  // Light walls
            case .floor:
                tileColor = GruvboxColors.black  // Dark floors
            case .corridor:
                tileColor = UIColor(white: 0.3, alpha: 1.0)  // Lighter corridors/tunnels
            case .player:
                tileColor = GruvboxColors.foreground  // Player in foreground color
            case .door, .doorOpen, .doorClosed:
                tileColor = GruvboxColors.yellow  // Doors in yellow/brown
            case .stairs:
                tileColor = GruvboxColors.yellow  // Stairs also yellow
            case .water:
                tileColor = GruvboxColors.blue  // Water in blue
            case .monster:
                tileColor = tile.isPet ? GruvboxColors.green : GruvboxColors.red  // Pets green, monsters red
            default:
                // Use the original foreground color
                tileColor = UIColor(
                    red: CGFloat(tile.foreground.r) / 255.0,
                    green: CGFloat(tile.foreground.g) / 255.0,
                    blue: CGFloat(tile.foreground.b) / 255.0,
                    alpha: 1.0
                )
            }

            // Render NetHack glyphs (ASCII characters)
            if tile.character != " " {
                let glyphImage = createTextImage(
                    text: String(tile.character),
                    color: tileColor,
                    size: CGSize(width: 64, height: 64),
                    isPet: tile.isPet
                )
                material.emission.contents = glyphImage
                material.diffuse.contents = UIColor.black
            } else {
                // Empty space - just use background color
                material.emission.contents = GruvboxColors.background
                material.diffuse.contents = UIColor.black
            }

            plane.materials = [material]
            node.geometry = plane

            // Add subtle animation for living creatures
            if tile.type == .player || tile.type == .monster {
                if visibility == .visible {
                    addPulseAnimation(to: node)
                }
            }

            return node
        }

        private func createTextImage(text: String, color: UIColor, size: CGSize, isPet: Bool = false) -> UIImage? {
            // For now, keep ASCII but we can switch to tile images
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                // Clear background
                GruvboxColors.background.setFill()
                context.fill(CGRect(origin: .zero, size: size))

                // Draw text centered
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: size.height * 0.7, weight: .medium),
                    .foregroundColor: color
                ]

                let textSize = text.size(withAttributes: attributes)
                let rect = CGRect(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )

                text.draw(in: rect, withAttributes: attributes)

                // Pet indicator: Heart badge in corner
                if isPet {
                    // Small heart in bottom-right corner
                    let heartSize: CGFloat = 14
                    let heartX = size.width - heartSize - 4
                    let heartY = size.height - heartSize - 4

                    let heartAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: heartSize, weight: .bold),
                        .foregroundColor: GruvboxColors.green
                    ]
                    "♥".draw(at: CGPoint(x: heartX, y: heartY), withAttributes: heartAttrs)
                }
            }
        }

        /// Draws a filled star at specified position
        private func drawStar(in context: CGContext, at center: CGPoint, size: CGFloat, color: UIColor) {
            let points = 5
            let radius = size / 2
            let innerRadius = radius * 0.4

            context.saveGState()
            context.setFillColor(color.cgColor)

            let path = UIBezierPath()
            for i in 0..<points * 2 {
                let angle = CGFloat(i) * .pi / CGFloat(points)
                let currentRadius = i % 2 == 0 ? radius : innerRadius
                let x = center.x + currentRadius * sin(angle)
                let y = center.y - currentRadius * cos(angle)

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.close()

            // Draw the star path in the CGContext
            context.addPath(path.cgPath)
            context.fillPath()
            context.restoreGState()
        }

        private func createTileImage(for tileType: TileType, color: UIColor, size: CGSize) -> UIImage? {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let ctx = context.cgContext
                let rect = CGRect(origin: .zero, size: size)

                // Background
                ctx.setFillColor(GruvboxColors.background.cgColor)
                ctx.fill(rect)

                // Draw based on tile type
                switch tileType {
                case .wall:
                    drawWallTile(ctx: ctx, rect: rect, color: color)
                case .floor:
                    drawFloorTile(ctx: ctx, rect: rect, color: color)
                case .door, .doorClosed:
                    drawDoorTile(ctx: ctx, rect: rect, color: color, isOpen: false)
                case .doorOpen:
                    drawDoorTile(ctx: ctx, rect: rect, color: color, isOpen: true)
                case .corridor:
                    drawCorridorTile(ctx: ctx, rect: rect, color: color)
                case .stairs:
                    drawStairsTile(ctx: ctx, rect: rect, color: color)
                case .water:
                    drawWaterTile(ctx: ctx, rect: rect, color: color)
                case .player:
                    drawPlayerTile(ctx: ctx, rect: rect, color: color)
                case .monster:
                    drawMonsterTile(ctx: ctx, rect: rect, color: color)
                default:
                    drawGenericTile(ctx: ctx, rect: rect, color: color)
                }
            }
        }

        private func drawWallTile(ctx: CGContext, rect: CGRect, color: UIColor) {
            // Stone wall pattern
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)

            // Add brick pattern
            ctx.setStrokeColor(GruvboxColors.black.cgColor)
            ctx.setLineWidth(1)

            let rows = 4
            let brickHeight = rect.height / CGFloat(rows)
            for row in 0..<rows {
                let y = CGFloat(row) * brickHeight
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: rect.width, y: y))

                // Offset bricks
                let offset = row % 2 == 0 ? 0 : rect.width / 4
                for col in 0..<3 {
                    let x = CGFloat(col) * rect.width / 2 + offset
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x, y: y + brickHeight))
                }
            }
            ctx.strokePath()
        }

        private func drawFloorTile(ctx: CGContext, rect: CGRect, color: UIColor) {
            // Simple floor with subtle pattern
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)

            // Add dots for texture
            ctx.setFillColor(color.withAlphaComponent(0.3).cgColor)
            let dotSize: CGFloat = 2
            let spacing: CGFloat = rect.width / 4
            for x in stride(from: spacing, to: rect.width, by: spacing) {
                for y in stride(from: spacing, to: rect.height, by: spacing) {
                    ctx.fillEllipse(in: CGRect(x: x - dotSize/2, y: y - dotSize/2,
                                               width: dotSize, height: dotSize))
                }
            }
        }

        private func drawDoorTile(ctx: CGContext, rect: CGRect, color: UIColor, isOpen: Bool) {
            if isOpen {
                // Open door - show opening
                ctx.setFillColor(GruvboxColors.black.cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(3)
                ctx.stroke(rect.insetBy(dx: 2, dy: 2))
            } else {
                // Closed door
                ctx.setFillColor(color.cgColor)
                ctx.fill(rect)
                // Door handle
                ctx.setFillColor(GruvboxColors.yellow.cgColor)
                ctx.fillEllipse(in: CGRect(x: rect.width * 0.7, y: rect.height * 0.5 - 3,
                                          width: 6, height: 6))
            }
        }

        private func drawCorridorTile(ctx: CGContext, rect: CGRect, color: UIColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        }

        private func drawStairsTile(ctx: CGContext, rect: CGRect, color: UIColor) {
            ctx.setFillColor(GruvboxColors.black.cgColor)
            ctx.fill(rect)

            // Draw steps
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(2)
            let steps = 5
            for i in 0..<steps {
                let y = rect.height * CGFloat(i) / CGFloat(steps)
                ctx.move(to: CGPoint(x: rect.width * 0.2, y: y))
                ctx.addLine(to: CGPoint(x: rect.width * 0.8, y: y))
            }
            ctx.strokePath()
        }

        private func drawWaterTile(ctx: CGContext, rect: CGRect, color: UIColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)

            // Wave pattern
            ctx.setStrokeColor(color.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(1.5)
            for y in stride(from: rect.height * 0.3, to: rect.height * 0.7, by: 8) {
                ctx.move(to: CGPoint(x: 0, y: y))
                // Simple wave
                ctx.addCurve(to: CGPoint(x: rect.width, y: y),
                           control1: CGPoint(x: rect.width * 0.3, y: y - 3),
                           control2: CGPoint(x: rect.width * 0.7, y: y + 3))
            }
            ctx.strokePath()
        }

        private func drawPlayerTile(ctx: CGContext, rect: CGRect, color: UIColor) {
            // Hero figure
            ctx.setFillColor(color.cgColor)
            // Head
            ctx.fillEllipse(in: CGRect(x: rect.width * 0.35, y: rect.height * 0.2,
                                       width: rect.width * 0.3, height: rect.height * 0.25))
            // Body
            ctx.fill(CGRect(x: rect.width * 0.4, y: rect.height * 0.45,
                           width: rect.width * 0.2, height: rect.height * 0.3))
            // Arms and legs simplified
            ctx.setLineWidth(3)
            ctx.setStrokeColor(color.cgColor)
            ctx.strokePath()
        }

        private func drawMonsterTile(ctx: CGContext, rect: CGRect, color: UIColor) {
            // Simple monster shape
            ctx.setFillColor(color.cgColor)
            // Body circle
            ctx.fillEllipse(in: CGRect(x: rect.width * 0.2, y: rect.height * 0.3,
                                       width: rect.width * 0.6, height: rect.height * 0.4))
            // Eyes (angry)
            ctx.setFillColor(GruvboxColors.red.cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.width * 0.3, y: rect.height * 0.4,
                                       width: 6, height: 6))
            ctx.fillEllipse(in: CGRect(x: rect.width * 0.6, y: rect.height * 0.4,
                                       width: 6, height: 6))
        }

        private func drawGenericTile(ctx: CGContext, rect: CGRect, color: UIColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect.insetBy(dx: 4, dy: 4))
        }

        private func createTextImage(text: String, color: UIColor) -> UIImage {
            let size = CGSize(width: 64, height: 64)
            let renderer = UIGraphicsImageRenderer(size: size)

            return renderer.image { context in
                // Background
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: size))

                // Text
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                    .foregroundColor: color
                ]

                let textSize = text.size(withAttributes: attributes)
                let textRect = CGRect(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )

                text.draw(in: textRect, withAttributes: attributes)
            }
        }

        private func addPulseAnimation(to node: SCNNode) {
            let pulseAnimation = CABasicAnimation(keyPath: "scale")
            pulseAnimation.fromValue = SCNVector3(1.0, 1.0, 1.0)
            pulseAnimation.toValue = SCNVector3(1.05, 1.05, 1.0)
            pulseAnimation.duration = 2.0
            pulseAnimation.autoreverses = true
            pulseAnimation.repeatCount = .infinity
            node.addAnimation(pulseAnimation, forKey: "pulse")
        }

        private func createPetRingNode(size: Float) -> SCNNode {
            // Corner brackets indicator - transparent background, clean look
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false  // Enable transparency
            let indicatorImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
                // Background is already transparent with opaque=false

                let cornerLength: CGFloat = 14
                let cornerOffset: CGFloat = 4
                let lineWidth: CGFloat = 3.0

                ctx.cgContext.setStrokeColor(GruvboxColors.green.cgColor)
                ctx.cgContext.setLineWidth(lineWidth)
                ctx.cgContext.setLineCap(.round)

                // Top-left corner
                ctx.cgContext.move(to: CGPoint(x: cornerOffset, y: cornerOffset + cornerLength))
                ctx.cgContext.addLine(to: CGPoint(x: cornerOffset, y: cornerOffset))
                ctx.cgContext.addLine(to: CGPoint(x: cornerOffset + cornerLength, y: cornerOffset))

                // Top-right corner
                ctx.cgContext.move(to: CGPoint(x: 64 - cornerOffset - cornerLength, y: cornerOffset))
                ctx.cgContext.addLine(to: CGPoint(x: 64 - cornerOffset, y: cornerOffset))
                ctx.cgContext.addLine(to: CGPoint(x: 64 - cornerOffset, y: cornerOffset + cornerLength))

                // Bottom-left corner
                ctx.cgContext.move(to: CGPoint(x: cornerOffset, y: 64 - cornerOffset - cornerLength))
                ctx.cgContext.addLine(to: CGPoint(x: cornerOffset, y: 64 - cornerOffset))
                ctx.cgContext.addLine(to: CGPoint(x: cornerOffset + cornerLength, y: 64 - cornerOffset))

                // Bottom-right corner
                ctx.cgContext.move(to: CGPoint(x: 64 - cornerOffset - cornerLength, y: 64 - cornerOffset))
                ctx.cgContext.addLine(to: CGPoint(x: 64 - cornerOffset, y: 64 - cornerOffset))
                ctx.cgContext.addLine(to: CGPoint(x: 64 - cornerOffset, y: 64 - cornerOffset - cornerLength))

                ctx.cgContext.strokePath()
            }

            let plane = SCNPlane(width: CGFloat(size * 1.05), height: CGFloat(size * 1.05))
            let material = SCNMaterial()
            material.emission.contents = indicatorImage
            material.diffuse.contents = UIColor.clear
            material.isDoubleSided = true
            material.lightingModel = .constant
            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            node.name = "petIndicator"
            return node
        }

        private func updateCameraPosition(mapState: MapState) {
            guard let camera = scene?.rootNode.childNode(withName: "camera", recursively: false) else { return }

            // Convert player position to SceneKit 3D position
            let targetPos = SCNVector3(
                x: Float(mapState.playerX) * tileSize - Float(mapState.width) * tileSize / 2,
                y: -Float(mapState.playerY) * tileSize + Float(mapState.height) * tileSize / 2,
                z: camera.position.z  // Keep current Z
            )

            if lastPlayerX == -1 {
                // First update - snap to position
                camera.position.x = targetPos.x
                camera.position.y = targetPos.y
            } else {
                // Linear interpolation - each step takes exactly the same time
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.15  // Faster, snappier movement
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
                camera.position.x = targetPos.x
                camera.position.y = targetPos.y
                SCNTransaction.commit()
            }

            lastPlayerX = mapState.playerX
            lastPlayerY = mapState.playerY
        }

        private func updatePlayerLight(mapState: MapState) {
            guard let playerLight = scene?.rootNode.childNode(withName: "playerLight", recursively: false) else { return }

            // Convert player position to SceneKit 3D position
            let targetPos = SCNVector3(
                x: Float(mapState.playerX) * tileSize - Float(mapState.width) * tileSize / 2,
                y: -Float(mapState.playerY) * tileSize + Float(mapState.height) * tileSize / 2,
                z: playerLight.position.z  // Keep current Z
            )

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.15  // Match camera movement
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
            playerLight.position.x = targetPos.x
            playerLight.position.y = targetPos.y
            SCNTransaction.commit()
        }

        private func clearTiles() {
            for row in tileNodes {
                for node in row {
                    node?.removeFromParentNode()
                }
            }
            tileNodes.removeAll()

            // CRITICAL FIX: Reset player tracking state for new games
            // RCA: MapUpdateCoordinator persists across game sessions in SwiftUI
            // Without reset, second new game has lastPlayerX != -1, causing camera
            // to animate instead of snap, making player appear stuck
            lastPlayerX = -1
            lastPlayerY = -1
        }
    }

    // MARK: - Coordinator for Hit Testing

    class Coordinator: NSObject {
        var parent: SceneKitMapView
        weak var scnView: SCNView?
        var mapUpdater: MapUpdateCoordinator?

        init(_ parent: SceneKitMapView) {
            self.parent = parent
            super.init()
        }

        func setupGestures(for scnView: SCNView) {
            self.scnView = scnView

            // Single tap only - no more double tap delay!
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            scnView.addGestureRecognizer(tapGesture)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            // FIRST LINE - measure gesture recognition delay
            let gestureTimestamp = String(format: "%.3f", CACurrentMediaTime())
            print("[\(gestureTimestamp)] [TAP] 👆 UITapGestureRecognizer FIRED")

            guard let scnView = scnView else { return }

            let tapStart = CFAbsoluteTimeGetCurrent()
            Log.verbose(.perf, "Tap started at \(tapStart)")

            let location = gesture.location(in: scnView)
            let hitTestStart = CFAbsoluteTimeGetCurrent()
            
            // PERFORMANCE FIX: Optimize hitTest with targeted options
            // CRITICAL: Use NSNumber for SceneKit compatibility (not raw Swift types!)
            // - searchMode: .closest stops after first hit (was checking ALL nodes)
            // - boundingBoxOnly: faster collision detection (was using full geometry)
            // - categoryBitMask: only check tiles layer (ignore UI elements)
            let options: [SCNHitTestOption: Any] = [
                .searchMode: NSNumber(value: SCNHitTestSearchMode.closest.rawValue),  // NSNumber, not enum!
                .boundingBoxOnly: NSNumber(value: true),  // NSNumber(bool), not Bool!
                .categoryBitMask: NSNumber(value: 1),  // NSNumber(int), not Int!
                .ignoreHiddenNodes: NSNumber(value: true)  // NSNumber(bool), not Bool!
            ]
            let hitResults = scnView.hitTest(location, options: options)
            let hitTestEnd = CFAbsoluteTimeGetCurrent()
            Log.verbose(.perf, "HitTest took: \((hitTestEnd - hitTestStart) * 1000)ms")

            // Debug output (commented out for performance)
            // print("========== TAP DEBUG ==========")
            // print("Screen tap location: \(location)")
            // print("View size: \(scnView.bounds.size)")

            if let hit = hitResults.first {
                let node = hit.node
                // print("Hit node: \(node.name ?? "unnamed")")
                // Commented out debug logging for performance

                let extractStart = CFAbsoluteTimeGetCurrent()
                if let coords = extractTileCoordinates(from: node) {
                    let extractEnd = CFAbsoluteTimeGetCurrent()
                    let timestamp = String(format: "%.3f", CACurrentMediaTime())
                    print("[\(timestamp)] [PERF] Extract coords took: \((extractEnd - extractStart) * 1000)ms")

                    print("[\(timestamp)] [PERF] Calling onTileTap for (\(coords.x), \(coords.y))")
                    parent.selectedTile = coords
                    parent.onTileTap?(coords.x, coords.y)

                    let tapEnd = CFAbsoluteTimeGetCurrent()
                    print("[\(timestamp)] [PERF] Total tap time: \((tapEnd - tapStart) * 1000)ms")
                } else {
                    let timestamp = String(format: "%.3f", CACurrentMediaTime())
                    print("[\(timestamp)] Failed to extract tile coordinates")
                }
            } else {
                let timestamp = String(format: "%.3f", CACurrentMediaTime())
                print("[\(timestamp)] No hit detected")
            }
        }


        private func extractTileCoordinates(from node: SCNNode) -> (x: Int, y: Int)? {
            // PRIMARY: Extract from node name (format: "tile_x_y") - most reliable
            if let name = node.name {
                let parts = name.split(separator: "_")
                if parts.count == 3,
                   parts[0] == "tile",
                   let x = Int(parts[1]),
                   let y = Int(parts[2]) {
                    return (x: x, y: y)
                }
            }

            // FALLBACK: Calculate from position (less reliable due to floating point)
            guard let mapUpdater = mapUpdater else {
                let timestamp = String(format: "%.3f", CACurrentMediaTime())
                print("[\(timestamp)] [COORD] ERROR: No mapUpdater available for fallback")
                return nil
            }

            // Inverse of SceneKit position calculation
            let mapWidth = mapUpdater.tileNodes.first?.count ?? 0
            let mapHeight = mapUpdater.tileNodes.count
            guard mapWidth > 0 && mapHeight > 0 else { return nil }

            let x = Int(round((node.position.x + Float(mapWidth) * kSceneKitTileSize / 2) / kSceneKitTileSize))
            let y = Int(round((-node.position.y + Float(mapHeight) * kSceneKitTileSize / 2) / kSceneKitTileSize))

            // Validate bounds
            guard x >= 0 && x < mapWidth && y >= 0 && y < mapHeight else {
                let timestamp = String(format: "%.3f", CACurrentMediaTime())
                print("[\(timestamp)] [COORD] WARN: Converted coordinate (\(x),\(y)) out of bounds")
                return nil
            }

            return (x: x, y: y)
        }
    }
}

