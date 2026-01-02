//
//  GlassOverlayComponents.swift
//  nethack
//
//  Glass-morphic UI overlay components for the 2.5D game view
//

import SwiftUI

// MARK: - Status Bar Overlay
struct StatusBarOverlay: View {
    var gameManager: NetHackGameManager

    // Device detection for iPhone-specific sizing
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        // SWIFTUI-L-003: GeometryReader in background to read safe area
        GeometryReader { geometry in
            let safeAreaLeft = geometry.safeAreaInsets.leading
            // LANDSCAPE ONLY: Dynamic Island is on LEFT side, not top
            // Left padding respects safe area, right padding aligns with CommandGroupBar
            let leftPadding = max(isPhone ? 16 : 24, safeAreaLeft + 8)
            // Fixed right padding to align with Quick button (54pt on iPhone)
            let rightPadding: CGFloat = isPhone ? 54 : 24
            // Top padding: minimal since Dynamic Island is on sides in landscape
            // iPad: extra padding to keep status bar away from screen edge
            let topPadding: CGFloat = isPhone ? 8 : 27

            HStack(spacing: isPhone ? 6 : 12) {
                // Left side: Empty (Inspect+Context buttons are separate overlay)
                Spacer()
                    .frame(width: isPhone ? 80 : 100) // Reserve space for Inspect+Context

                // CENTERED: All status badges
                HStack(spacing: isPhone ? 6 : 12) {
                    // Health
                    StatusBadge(
                        icon: "heart.fill",
                        value: "\(gameManager.playerStats?.hp ?? 0)/\(gameManager.playerStats?.hpmax ?? 0)",
                        color: healthColor(current: gameManager.playerStats?.hp ?? 0,
                                         max: gameManager.playerStats?.hpmax ?? 1)
                    )

                    // Mana/Power
                    StatusBadge(
                        icon: "sparkles",
                        value: "\(gameManager.playerStats?.pw ?? 0)/\(gameManager.playerStats?.pwmax ?? 0)",
                        color: .blue
                    )

                    // Level
                    StatusBadge(
                        icon: "arrow.up.circle.fill",
                        value: "Lv \(gameManager.playerStats?.level ?? 1)",
                        color: .green
                    )

                    // Gold
                    StatusBadge(
                        icon: "dollarsign.circle.fill",
                        value: "\(gameManager.playerStats?.gold ?? 0)",
                        color: .yellow
                    )

                    // AC
                    StatusBadge(
                        icon: "shield.fill",
                        value: "AC:\(gameManager.playerStats?.ac ?? 10)",
                        color: .cyan
                    )

                    // Dungeon Level
                    StatusBadge(
                        icon: "map.fill",
                        value: "D:\(gameManager.playerStats?.dungeonLevel ?? 1)",
                        color: .purple
                    )

                    // Hunger Status (only shown when not normal)
                    if let info = hungerStatusInfo {
                        StatusBadge(icon: info.icon, value: info.value, color: info.color)
                    }

                    // Condition Badges (Blind, Confused, Stunned, etc.)
                    if let conditions = gameManager.playerStats?.conditions, conditions != 0 {
                        // Divider between stats and conditions
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 1, height: isPhone ? 16 : 20)

                        ConditionBadgeRow(
                            conditions: conditions,
                            maxVisible: isPhone ? 5 : 8
                        )
                        .frame(maxWidth: isPhone ? 200 : 350)
                    }
                }

                Spacer()

                // Right side: Exit button + Turn counter (compact, same height as badges)
                HStack(spacing: isPhone ? 6 : 10) {
                    // Exit button - compact to match status badges
                    Button(action: {
                        gameManager.exitToMenu()
                    }) {
                        HStack(spacing: isPhone ? 3 : 4) {
                            Image(systemName: "escape")
                                .font(.system(size: isPhone ? 11 : 14, weight: .semibold))
                            Text("Exit")
                                .font(.system(size: isPhone ? 10 : 13, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, isPhone ? 8 : 12)
                        .padding(.vertical, isPhone ? 4 : 6)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.3))
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }

                    // Turn counter
                    StatusBadge(
                        icon: "clock.fill",
                        value: "T:\(gameManager.turnCount)",
                        color: .white.opacity(0.8)
                    )
                }
            }
            // SAFE AREA FIX: Left padding respects safe area, right padding aligns with CommandGroupBar
            .padding(.leading, leftPadding)
            .padding(.trailing, rightPadding)
            .padding(.top, topPadding)
            .padding(.bottom, isPhone ? 3 : 5)
            .frame(maxWidth: .infinity)
        }
        // FIX: GeometryReader expands to fill parent - constrain with fixedSize
        .fixedSize(horizontal: false, vertical: true)
        // No background - transparent status bar
        .ignoresSafeArea(edges: .top)
    }

    // Helper to color health based on percentage
    private func healthColor(current: Int, max: Int) -> Color {
        let percentage = max > 0 ? Double(current) / Double(max) : 1.0
        if percentage > 0.75 {
            return .green
        } else if percentage > 0.5 {
            return .yellow
        } else if percentage > 0.25 {
            return .orange
        } else {
            return .red
        }
    }

    // Helper to convert hunger value to status badge info (nil if normal)
    // Hunger values: 0=Satiated, 1=Normal(hidden), 2=Hungry, 3=Weak, 4=Fainting, 5=Fainted, 6=Starved
    private var hungerStatusInfo: (icon: String, value: String, color: Color)? {
        let hunger = gameManager.playerStats?.hunger ?? 1
        switch hunger {
        case 0:  // Satiated (overfed)
            return ("fork.knife", "Satiated", .green)
        case 2:  // Hungry
            return ("fork.knife", "Hungry", .yellow)
        case 3:  // Weak
            return ("fork.knife", "Weak", .orange)
        case 4, 5:  // Fainting/Fainted
            return ("exclamationmark.triangle.fill", "Fainting", .red)
        case 6:  // Starved
            return ("exclamationmark.triangle.fill", "Starving", .red)
        default:  // 1 = NOT_HUNGRY (normal, don't show)
            return nil
        }
    }
}

// MARK: - Top Bar Overlay (Exit + Turn - right aligned)
struct TopBarOverlay: View {
    var gameManager: NetHackGameManager

    private let isPhone = ScalingEnvironment.isPhone
    // Minimum 44pt touch targets for accessibility
    private let minTouchTarget: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let safeAreaLeft = geometry.safeAreaInsets.leading
            let safeAreaRight = geometry.safeAreaInsets.trailing
            // LANDSCAPE: Dynamic Island creates safe area on LEFT/RIGHT sides, not top
            let horizontalPadding = max(isPhone ? 16 : 24, max(safeAreaLeft, safeAreaRight) + 8)
            // Top padding: smaller since no Dynamic Island on top in landscape
            let topPadding: CGFloat = isPhone ? 12 : 16

            HStack(spacing: isPhone ? 8 : 12) {
                Spacer()

                // Right side: Exit button + Turn counter
                HStack(spacing: isPhone ? 6 : 10) {
                    // Exit button (44pt minimum touch target)
                    Button(action: {
                        gameManager.exitToMenu()
                    }) {
                        HStack(spacing: isPhone ? 4 : 6) {
                            Image(systemName: "escape")
                                .font(.system(size: isPhone ? 14 : 16, weight: .semibold))
                            Text("Exit")
                                .font(.system(size: isPhone ? 13 : 15, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(minWidth: minTouchTarget, minHeight: minTouchTarget)
                        .padding(.horizontal, isPhone ? 10 : 14)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.3))
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }

                    // Turn counter badge
                    StatusBadge(
                        icon: "clock.fill",
                        value: "T:\(gameManager.turnCount)",
                        color: .white.opacity(0.8)
                    )
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Bottom Status Bar (Health, Mana, Level, Gold, AC, Dungeon - centered)
struct BottomStatusBar: View {
    var gameManager: NetHackGameManager

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        HStack(spacing: isPhone ? 4 : 8) {
            // Health
            StatusBadge(
                icon: "heart.fill",
                value: "\(gameManager.playerStats?.hp ?? 0)/\(gameManager.playerStats?.hpmax ?? 0)",
                color: healthColor(current: gameManager.playerStats?.hp ?? 0,
                                 max: gameManager.playerStats?.hpmax ?? 1)
            )

            // Mana/Power
            StatusBadge(
                icon: "sparkles",
                value: "\(gameManager.playerStats?.pw ?? 0)/\(gameManager.playerStats?.pwmax ?? 0)",
                color: .blue
            )

            // Level
            StatusBadge(
                icon: "arrow.up.circle.fill",
                value: "Lv \(gameManager.playerStats?.level ?? 1)",
                color: .green
            )

            // Gold
            StatusBadge(
                icon: "dollarsign.circle.fill",
                value: "\(gameManager.playerStats?.gold ?? 0)",
                color: .yellow
            )

            // AC
            StatusBadge(
                icon: "shield.fill",
                value: "AC:\(gameManager.playerStats?.ac ?? 10)",
                color: .cyan
            )

            // Dungeon Level
            StatusBadge(
                icon: "map.fill",
                value: "D:\(gameManager.playerStats?.dungeonLevel ?? 1)",
                color: .purple
            )

            // Hunger Status (only shown when not normal)
            if let info = hungerStatusInfo {
                StatusBadge(icon: info.icon, value: info.value, color: info.color)
            }
        }
        .padding(.vertical, isPhone ? 6 : 8)
        .padding(.horizontal, isPhone ? 8 : 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // Helper to color health based on percentage
    private func healthColor(current: Int, max: Int) -> Color {
        let percentage = max > 0 ? Double(current) / Double(max) : 1.0
        if percentage > 0.75 {
            return .green
        }
        if percentage > 0.5 {
            return .yellow
        }
        if percentage > 0.25 {
            return .orange
        }
        return .red
    }

    // Helper to convert hunger value to status badge info (nil if normal)
    // Hunger values: 0=Satiated, 1=Normal(hidden), 2=Hungry, 3=Weak, 4=Fainting, 5=Fainted, 6=Starved
    private var hungerStatusInfo: (icon: String, value: String, color: Color)? {
        let hunger = gameManager.playerStats?.hunger ?? 1
        switch hunger {
        case 0:  // Satiated (overfed)
            return ("fork.knife", "Satiated", .green)
        case 2:  // Hungry
            return ("fork.knife", "Hungry", .yellow)
        case 3:  // Weak
            return ("fork.knife", "Weak", .orange)
        case 4, 5:  // Fainting/Fainted
            return ("exclamationmark.triangle.fill", "Fainting", .red)
        case 6:  // Starved
            return ("exclamationmark.triangle.fill", "Starving", .red)
        default:  // 1 = NOT_HUNGRY (normal, don't show)
            return nil
        }
    }
}

// MARK: - Individual Status Badge
struct StatusBadge: View {
    let icon: String
    let value: String
    let color: Color

    // Device detection for iPhone-specific sizing
    private let isPhone = ScalingEnvironment.isPhone
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let iconSize = ScalingEnvironment.UIScale.statusBadgeIconSize(isPhone: isPhone)
        let fontSize = ScalingEnvironment.UIScale.statusBadgeFontSize(isPhone: isPhone)

        HStack(spacing: isPhone ? 3 : 4) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, isPhone ? 6 : 10)
        .padding(.vertical, isPhone ? 4 : 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                )
        )
        .scaleEffect(pulseScale)
        .onChange(of: value) { _, _ in
            guard !reduceMotion else { return }
            // Pulse animation on value change
            withAnimation(AnimationConstants.statusUpdate) {
                pulseScale = 1.08
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(AnimationConstants.statusUpdate) {
                    pulseScale = 1.0
                }
            }
        }
    }
}

// MARK: - Condition Badge

/// A single condition badge (Blind, Confused, Stunned, etc.)
struct ConditionBadge: View {
    let condition: PlayerCondition
    let mode: ConditionBadgeDisplayMode

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: CGFloat = 0.3
    @State private var hueRotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    private var iconSize: CGFloat { isPhone ? 13 : 16 }
    private var fontSize: CGFloat { isPhone ? 10 : 12 }
    private var horizontalPadding: CGFloat { isPhone ? 5 : 8 }
    private var verticalPadding: CGFloat { isPhone ? 3 : 5 }

    var body: some View {
        HStack(spacing: isPhone ? 2 : 3) {
            Image(systemName: condition.icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(condition.iconColor)

            if mode != .iconOnly {
                Text(mode == .compact ? condition.shortLabel : condition.fullLabel)
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(badgeBackground)
        .scaleEffect(condition.tier == .critical ? (isPhone ? 1.08 : 1.10) : 1.0)
        .scaleEffect(pulseScale)
        .hueRotation(condition == .hallucinating ? Angle(degrees: hueRotation) : .zero)
        .shadow(
            color: condition.tier == .critical ? condition.color.opacity(glowOpacity) : .clear,
            radius: condition.tier == .critical ? 6 : 0
        )
        .onAppear {
            if !reduceMotion {
                startAnimations()
            }
        }
        .accessibilityLabel(condition.fullLabel)
        .accessibilityHint(condition.accessibilityDescription)
    }

    @ViewBuilder
    private var badgeBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(
                        condition.color.opacity(condition.tier == .critical ? 0.5 : 0.3),
                        lineWidth: condition.tier == .critical && !reduceMotion ? 2 : 0.5
                    )
            )
            .overlay(
                // Colored fill for better visibility
                Capsule()
                    .fill(condition.color.opacity(0.2))
            )
    }

    private func startAnimations() {
        // Critical pulse animation
        if condition.tier == .critical {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                glowOpacity = 0.6
            }
        }

        // Hallucination rainbow effect
        if condition == .hallucinating {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                hueRotation = 360
            }
        }
    }
}

/// Display mode for condition badges
enum ConditionBadgeDisplayMode {
    case iconOnly   // Just the icon
    case compact    // Icon + short label
    case full       // Icon + full label
}

// MARK: - Condition Badge Row

/// Container for displaying multiple condition badges
struct ConditionBadgeRow: View {
    let conditions: UInt
    let maxVisible: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isPhone = ScalingEnvironment.isPhone

    private var activeConditions: [PlayerCondition] {
        PlayerCondition.activeConditions(from: conditions)
    }

    var body: some View {
        if activeConditions.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geometry in
                let visibleConditions = Array(activeConditions.prefix(maxVisible))
                let overflowCount = activeConditions.count - visibleConditions.count
                let mode = calculateDisplayMode(
                    availableWidth: geometry.size.width,
                    badgeCount: visibleConditions.count + (overflowCount > 0 ? 1 : 0)
                )

                HStack(spacing: isPhone ? 4 : 6) {
                    ForEach(visibleConditions) { condition in
                        ConditionBadge(condition: condition, mode: mode)
                            .transition(badgeTransition)
                    }

                    if overflowCount > 0 {
                        overflowIndicator(count: overflowCount)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: activeConditions.map(\.rawValue))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var badgeTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(scale: 0.6).combined(with: .opacity),
            removal: .scale(scale: 0.8).combined(with: .opacity)
        )
    }

    private func overflowIndicator(count: Int) -> some View {
        Text("+\(count)")
            .font(.system(size: isPhone ? 10 : 12, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, isPhone ? 6 : 8)
            .padding(.vertical, isPhone ? 3 : 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }

    private func calculateDisplayMode(availableWidth: CGFloat, badgeCount: Int) -> ConditionBadgeDisplayMode {
        let minBadgeWidth: CGFloat = isPhone ? 28 : 36
        let compactBadgeWidth: CGFloat = isPhone ? 50 : 65
        let fullBadgeWidth: CGFloat = isPhone ? 70 : 90
        let spacing: CGFloat = isPhone ? 4 : 6

        let totalSpacing = CGFloat(badgeCount - 1) * spacing

        // Check if full labels fit
        let fullWidth = CGFloat(badgeCount) * fullBadgeWidth + totalSpacing
        if fullWidth <= availableWidth { return .full }

        // Check if compact labels fit
        let compactWidth = CGFloat(badgeCount) * compactBadgeWidth + totalSpacing
        if compactWidth <= availableWidth { return .compact }

        return .iconOnly
    }
}

// MARK: - Controls Overlay
struct ControlsOverlay: View {
    var gameManager: NetHackGameManager

    var body: some View {
        // Movement controls only - live save moved to top bar
        HStack {
            // D-Pad for movement - centered and larger for better touch
            GlassDirectionalPad(gameManager: gameManager)
                .frame(width: 200, height: 200)
                .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Glass Directional Pad
struct GlassDirectionalPad: View {
    let gameManager: NetHackGameManager
    @State private var activeDirection: String? = nil

    var body: some View {
        ZStack {
            // Removed large background circle - only buttons visible

            // Directional buttons
            VStack(spacing: 0) {
                // Top row
                HStack(spacing: 0) {
                    DPadButton(direction: "↖", action: gameManager.moveUpLeft, activeDirection: $activeDirection)
                    DPadButton(direction: "↑", action: gameManager.moveUp, activeDirection: $activeDirection)
                    DPadButton(direction: "↗", action: gameManager.moveUpRight, activeDirection: $activeDirection)
                }

                // Middle row
                HStack(spacing: 0) {
                    DPadButton(direction: "←", action: gameManager.moveLeft, activeDirection: $activeDirection)
                    DPadButton(direction: "•", action: gameManager.wait, activeDirection: $activeDirection)
                    DPadButton(direction: "→", action: gameManager.moveRight, activeDirection: $activeDirection)
                }

                // Bottom row
                HStack(spacing: 0) {
                    DPadButton(direction: "↙", action: gameManager.moveDownLeft, activeDirection: $activeDirection)
                    DPadButton(direction: "↓", action: gameManager.moveDown, activeDirection: $activeDirection)
                    DPadButton(direction: "↘", action: gameManager.moveDownRight, activeDirection: $activeDirection)
                }
            }
        }
    }
}

// MARK: - D-Pad Button (Enhanced for Touch)
struct DPadButton: View {
    let direction: String
    let action: () -> Void
    @Binding var activeDirection: String?
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pressAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.1)
    }

    var body: some View {
        Text(direction)
            .font(.system(size: 28, weight: .semibold))  // Larger icons
            .foregroundColor(isPressed ? .white : .white.opacity(0.8))
            .frame(width: 66, height: 66)  // Increased from 50x50 to 66x66
            .background(
                Circle()
                    .fill(isPressed ? Color.white.opacity(0.3) : Color.white.opacity(0.05))
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isPressed ? Color.white.opacity(0.5) : Color.white.opacity(0.2),
                                lineWidth: isPressed ? 2 : 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)  // Less dramatic scale for larger buttons
            .shadow(color: .black.opacity(isPressed ? 0.3 : 0.1), radius: 4, y: 2)
            .animation(reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.1), value: isPressed)
            .onTapGesture {
                // Haptic feedback for better touch response
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                withAnimation(pressAnimation) {
                    isPressed = true
                }
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(pressAnimation) {
                        isPressed = false
                    }
                }
            }
    }
}

// MARK: - Glass Action Button (Enhanced Touch)
struct GlassActionButton: View {
    let icon: String
    let action: () -> Void
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pressAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.1)
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 24, weight: .semibold))  // Larger icon
            .foregroundColor(.white.opacity(0.95))
            .frame(width: 54, height: 54)  // Increased from 44x44
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                Color.white.opacity(isPressed ? 0.4 : 0.2),
                                lineWidth: isPressed ? 1.5 : 0.5
                            )
                    )
            )
            .shadow(color: .black.opacity(isPressed ? 0.3 : 0.1), radius: 4, y: 2)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.1), value: isPressed)
            .onTapGesture {
                // Haptic feedback
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                withAnimation(pressAnimation) {
                    isPressed = true
                }
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(pressAnimation) {
                        isPressed = false
                    }
                }
            }
    }
}

// MARK: - Save Action Pill (Special styling for save button)
// Note: QuickActionPill and SaveActionPill removed - functionality moved to ActionBar

// MARK: - Glass Background
struct GlassBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
    }
}

// MARK: - Glass Divider
/// A glass-morphic divider with subtle gradient highlight
/// Replaces system Divider() for consistent visual styling
struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.2), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

// MARK: - Message Toast (REMOVED - Dead code from migration to messagesOverlay)

// MARK: - Helper for button press gestures
struct ButtonGestureModifier: ViewModifier {
    let onChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity) { } onPressingChanged: { pressing in
                onChanged(pressing)
            }
    }
}

extension View {
    func onButtonGesture(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(ButtonGestureModifier(onChanged: action))
    }
}