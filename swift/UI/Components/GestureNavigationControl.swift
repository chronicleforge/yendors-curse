//
//  GestureNavigationControl.swift
//  nethack
//
//  Modern circular gesture-based navigation for NetHack iOS
//  - Tap = single step move
//  - Drag = "move until" (like numpad 5 + direction)
//

import SwiftUI

enum NavigationDirection: String, CaseIterable {
    case north = "N"
    case northeast = "NE"
    case east = "E"
    case southeast = "SE"
    case south = "S"
    case southwest = "SW"
    case west = "W"
    case northwest = "NW"

    var angle: Double {
        switch self {
        case .north: return 0
        case .northeast: return 45
        case .east: return 90
        case .southeast: return 135
        case .south: return 180
        case .southwest: return 225
        case .west: return 270
        case .northwest: return 315
        }
    }

    var arrowSymbol: String {
        switch self {
        case .north: return "↑"
        case .northeast: return "↗"
        case .east: return "→"
        case .southeast: return "↘"
        case .south: return "↓"
        case .southwest: return "↙"
        case .west: return "←"
        case .northwest: return "↖"
        }
    }

    // Calculate direction from angle (0 = North, clockwise)
    static func from(angle: Double) -> NavigationDirection {
        // Normalize angle to 0-360
        let normalizedAngle = (angle + 360).truncatingRemainder(dividingBy: 360)

        // Map to 8 directions (45° segments)
        switch normalizedAngle {
        case 337.5...360, 0..<22.5:
            return .north
        case 22.5..<67.5:
            return .northeast
        case 67.5..<112.5:
            return .east
        case 112.5..<157.5:
            return .southeast
        case 157.5..<202.5:
            return .south
        case 202.5..<247.5:
            return .southwest
        case 247.5..<292.5:
            return .west
        case 292.5..<337.5:
            return .northwest
        default:
            return .north
        }
    }
}

struct GestureNavigationControl: View {
    var gameManager: NetHackGameManager
    @State private var activeDirection: NavigationDirection?
    @State private var isDragging = false
    @State private var dragStartTime: Date?
    @State private var touchLocation: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Device detection for iPhone-specific sizing
    private let isPhone = ScalingEnvironment.isPhone

    // Visual constants - device-aware sizing (+10% larger)
    private var outerRadius: CGFloat {
        isPhone ? 82 : 132  // ~10% larger
    }

    private var innerRadius: CGFloat {
        isPhone ? 35 : 55  // ~10% larger
    }

    private var dragThreshold: CGFloat {
        isPhone ? 28 : 38  // Proportionally larger
    }

    private let tapTimeout: TimeInterval = 0.15  // Max time for tap (reduced for faster response)

    // Color scheme - high contrast black/white
    private let inactiveColor = Color.white.opacity(0.3)
    private let activeColor = Color.white
    private let backgroundColor = Color.black.opacity(0.05)
    private let tapHighlightColor = Color.white.opacity(0.4)
    private let dragHighlightColor = Color.cyan.opacity(0.6)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background circle - high contrast black/white
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                backgroundColor,
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: outerRadius
                        )
                    )
                    .frame(width: outerRadius * 2, height: outerRadius * 2)

                // Direction indicators
                ForEach(NavigationDirection.allCases, id: \.self) { direction in
                    DirectionIndicator(
                        direction: direction,
                        radius: outerRadius - 20,
                        isActive: activeDirection == direction,
                        isDragging: isDragging
                    )
                }

                // Center circle - high contrast
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: innerRadius
                            )
                        )
                        .frame(width: innerRadius * 2, height: innerRadius * 2)

                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                        .frame(width: innerRadius * 2, height: innerRadius * 2)

                    // Center icon - shows wait/skip when tapped
                    VStack(spacing: 2) {
                        Image(systemName: isDragging ? "arrow.forward.circle.fill" : "circle.dotted")
                            .font(.system(size: isPhone ? 18 : 24))
                            .foregroundColor(.white.opacity(0.7))

                        if !isDragging {
                            Text("wait")
                                .font(.system(size: isPhone ? 6 : 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .scaleEffect(isDragging ? 1.1 : 1.0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: isDragging)
                }

                // Active direction highlight - REMOVED: Was causing ugly gray wedge overlay
                // The DirectionIndicator already scales up when active, no need for extra highlight
            }
            .frame(width: outerRadius * 2, height: outerRadius * 2)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 10)  // 10px lower
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleGestureChange(value, in: geometry)
                    }
                    .onEnded { value in
                        handleGestureEnd(value, in: geometry)
                    }
            )
        }
    }

    private func handleGestureChange(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        let t0 = Date().timeIntervalSince1970

        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let location = value.location
        touchLocation = location

        // Calculate distance from center
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        // Start drag timer on first touch
        if dragStartTime == nil {
            dragStartTime = Date()
            print("[NavControl] [T=\(String(format: "%.3f", t0))] 👆 Navigation gesture started")
        }

        // Check if we're in center circle - will be wait/skip command
        guard distance > innerRadius else {
            activeDirection = nil
            isDragging = false
            return
        }

        // Calculate direction
        let angle = atan2(dy, dx) * 180 / .pi + 90  // Convert to compass bearing
        let direction = NavigationDirection.from(angle: angle)

        // Determine if this is a drag gesture
        // BOTH conditions must be true to trigger drag mode (less sensitive)
        let elapsed = Date().timeIntervalSince(dragStartTime ?? Date())
        let startLocation = value.startLocation
        let totalDrag = sqrt(pow(location.x - startLocation.x, 2) + pow(location.y - startLocation.y, 2))

        if totalDrag > dragThreshold && elapsed > tapTimeout {
            if !isDragging {
                print("[NavControl] [T=\(String(format: "%.3f", Date().timeIntervalSince1970))] 🔄 Drag mode activated (distance: \(String(format: "%.1f", totalDrag))pt, elapsed: \(String(format: "%.0f", elapsed*1000))ms)")
                isDragging = true
            }
        }

        activeDirection = direction
    }

    private func handleGestureEnd(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        let t0 = Date().timeIntervalSince1970
        print("[NavControl] [T=\(String(format: "%.3f", t0))] 👆 Navigation gesture ended - isDragging: \(isDragging)")

        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let location = value.location
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        // Check if tap was in center circle = wait/skip turn
        if distance <= innerRadius {
            let t1 = Date().timeIntervalSince1970
            print("[NavControl] [T=\(String(format: "%.3f", t1))] ⏸️ WAIT command (center tap)")
            gameManager.wait()  // Send "." command
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            reset()
            let t2 = Date().timeIntervalSince1970
            print("[NavControl] [T=\(String(format: "%.3f", t2))] ✅ Wait complete - took \(String(format: "%.1f", (t2-t1)*1000))ms")
            return
        }

        // Must have a direction for movement
        guard let direction = activeDirection else {
            reset()
            return
        }

        // Execute movement command
        let t3 = Date().timeIntervalSince1970
        print("[NavControl] [T=\(String(format: "%.3f", t3))] 🚶 Executing \(isDragging ? "MOVE-UNTIL" : "STEP") \(direction.rawValue)")
        executeMovement(direction: direction, isDrag: isDragging)

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: isDragging ? .medium : .light)
        generator.impactOccurred()

        reset()

        let t4 = Date().timeIntervalSince1970
        print("[NavControl] [T=\(String(format: "%.3f", t4))] ✅ Movement complete - took \(String(format: "%.1f", (t4-t3)*1000))ms")
    }

    private func executeMovement(direction: NavigationDirection, isDrag: Bool) {
        guard isDrag else {
            // Tap = single step
            performSingleStep(direction)
            return
        }

        // Drag = "move until" mode (sends 'g' prefix + direction in NetHack)
        performMoveUntil(direction)
    }

    private func performSingleStep(_ direction: NavigationDirection) {
        switch direction {
        case .north:
            gameManager.moveUp()
        case .northeast:
            gameManager.moveUpRight()
        case .east:
            gameManager.moveRight()
        case .southeast:
            gameManager.moveDownRight()
        case .south:
            gameManager.moveDown()
        case .southwest:
            gameManager.moveDownLeft()
        case .west:
            gameManager.moveLeft()
        case .northwest:
            gameManager.moveUpLeft()
        }
    }

    private func performMoveUntil(_ direction: NavigationDirection) {
        // "Move until" in NetHack is 'g' + direction
        // iOS uses NUMPAD MODE (iflags.num_pad = TRUE), so we must use numpad keys (1-9)
        // NOT vi keys (h,j,k,l,y,u,b,n) which are rebound to other commands in numpad mode!
        let directionKey: String
        switch direction {
        case .north:
            directionKey = "8"  // Numpad north
        case .northeast:
            directionKey = "9"  // Numpad NE
        case .east:
            directionKey = "6"  // Numpad east
        case .southeast:
            directionKey = "3"  // Numpad SE
        case .south:
            directionKey = "2"  // Numpad south
        case .southwest:
            directionKey = "1"  // Numpad SW
        case .west:
            directionKey = "4"  // Numpad west
        case .northwest:
            directionKey = "7"  // Numpad NW
        }

        // Send "g" followed by numpad direction key
        gameManager.sendCommand("g\(directionKey)")
    }

    private func reset() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            activeDirection = nil
            isDragging = false
        }
        dragStartTime = nil
    }
}

struct DirectionIndicator: View {
    let direction: NavigationDirection
    let radius: CGFloat
    let isActive: Bool
    let isDragging: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Device detection for iPhone-specific sizing
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        let angle = direction.angle
        let radians = angle * .pi / 180

        let x = radius * sin(radians)
        let y = -radius * cos(radians)

        VStack(spacing: isPhone ? 2 : 4) {
            Text(direction.arrowSymbol)
                .font(.system(size: isPhone ? 20 : 28, weight: .light))
                .foregroundColor(isActive ? .white : .white.opacity(0.3))

            Text(direction.rawValue)
                .font(.system(size: isPhone ? 8 : 10, weight: .medium, design: .monospaced))
                .foregroundColor(isActive ? .white : .white.opacity(0.2))
        }
        .offset(x: x, y: y)
        .scaleEffect(isActive ? 1.2 : 1.0)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: isActive)
    }
}

struct DirectionHighlight: View {
    let direction: NavigationDirection
    let radius: CGFloat
    let isDragging: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let angle = direction.angle

        // Create a wedge shape for the active direction - high contrast
        Circle()
            .trim(from: 0, to: 1/8)  // 45° wedge (1/8 of circle)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        isDragging ? Color.cyan.opacity(0.6) : Color.white.opacity(0.5),
                        isDragging ? Color.cyan.opacity(0.2) : Color.white.opacity(0.1)
                    ]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 40, lineCap: .round)
            )
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(angle - 22.5))  // Center the wedge on the direction
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: direction)
    }
}

// MARK: - Preview

struct GestureNavigationControl_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GestureNavigationControl(gameManager: NetHackGameManager())
                .frame(height: 300)
        }
        .preferredColorScheme(.dark)
    }
}
