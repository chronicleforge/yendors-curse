/*
 * ContextActionsButton.swift - Horizontal Expanding Context Actions FAB
 *
 * A floating action button that expands HORIZONTALLY to show context actions.
 * Game-aesthetic design, NOT native iOS sheet.
 *
 * SWIFTUI REFERENCES:
 * - SWIFTUI-L-001: Z-Index for layering overlay above game (zIndex 4)
 * - SWIFTUI-L-002: ZStack for independent overlay positioning
 * - SWIFTUI-A-001: Spring animations with bounce: 0.15-0.2
 * - SWIFTUI-A-003: Combined transitions (scale + opacity)
 * - SWIFTUI-A-009: Reduce Motion accessibility (MANDATORY)
 * - SWIFTUI-P-001: @State for component state management
 * - SWIFTUI-HIG-001: Animation durations 200-400ms
 * - SWIFTUI-HIG-002: Haptic feedback timing
 * - SWIFTUI-M-003: contentShape for hit testing
 *
 * Design:
 * - Collapsed: Circular button with badge count
 * - Expanded: Horizontal strip of action buttons (expands LEFT)
 * - Auto-collapse on action execution or tap elsewhere
 */

import SwiftUI

// MARK: - Context Action Item

/// Represents a quick context action for the expanding button
struct ContextQuickAction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let color: Color
    let command: String
    
    init(icon: String, title: String, color: Color = .nethackAccent, command: String) {
        self.icon = icon
        self.title = title
        self.color = color
        self.command = command
    }
}

// MARK: - Context Actions Button

struct ContextActionsButton: View {
    var gameManager: NetHackGameManager
    var overlayManager: GameOverlayManager

    // PUSH MODEL: Game state snapshot (instant read)
    @State private var snapshot: GameStateSnapshot = GameStateSnapshot()
    
    // UI State
    @State private var isExpanded = false
    @State private var isPressed = false
    
    // Device detection
    private let isPhone = ScalingEnvironment.isPhone
    
    // Accessibility - SWIFTUI-A-009 (MANDATORY)
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    // SWIFTUI-A-001: Professional spring animation
    private var buttonAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2)
    }
    
    // SWIFTUI-A-003: Expansion animation (slightly faster for snappy feel)
    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.15)
    }
    
    // Calculate available actions based on game state
    private var availableActions: [ContextQuickAction] {
        var actions: [ContextQuickAction] = []
        
        // Stairs actions
        if snapshot.isStairsDown {
            actions.append(ContextQuickAction(
                icon: "arrow.down.circle.fill",
                title: "Down",
                color: .nethackStairsDown,
                command: ">"
            ))
        }
        
        if snapshot.isStairsUp {
            actions.append(ContextQuickAction(
                icon: "arrow.up.circle.fill",
                title: "Up",
                color: .nethackStairsUp,
                command: "<"
            ))
        }
        
        // Door actions (from adjacent doors)
        if let door = snapshot.adjacentDoors.first {
            if door.isOpen {
                actions.append(ContextQuickAction(
                    icon: "door.left.hand.closed",
                    title: "Close",
                    color: .nethackDoor,
                    command: "c\(door.directionCommand)"
                ))
            } else {
                actions.append(ContextQuickAction(
                    icon: "door.left.hand.open",
                    title: "Open",
                    color: .nethackDoor,
                    command: "o\(door.directionCommand)"
                ))
            }
            
            // Kick option
            actions.append(ContextQuickAction(
                icon: "figure.martial.arts",
                title: "Kick",
                color: .nethackCombat,
                command: "\u{04}\(door.directionCommand)"  // Ctrl-D + direction
            ))
        }
        
        // Pick up action (if items present)
        if snapshot.itemCount > 0 {
            actions.append(ContextQuickAction(
                icon: "arrow.down.to.line",
                title: "Pickup",
                color: .nethackSuccess,
                command: ","
            ))
        }

        // Loot action (if any container on floor)
        // Note: showLootOptionsPicker filters locked containers automatically
        if snapshot.hasContainer {
            actions.append(ContextQuickAction(
                icon: "shippingbox",
                title: "Loot",
                color: .brown,
                command: "M-l"
            ))
        }

        // Force action (if locked container on floor)
        // Note: Kick doesn't work - NetHack rejects direction "." (self)
        if snapshot.hasLockedContainer {
            // Force Lock - break lock with weapon/tool (#force = M-f)
            // Sends M-f + auto-confirms 'y' to "force its lock?" prompt
            actions.append(ContextQuickAction(
                icon: "hammer.fill",
                title: "Force",
                color: .orange,
                command: "M-f"
            ))
        }

        // Search action (always available)
        actions.append(ContextQuickAction(
            icon: "magnifyingglass",
            title: "Search",
            color: .nethackInfo,
            command: "s"
        ))
        
        // Repeat action (always available) - C-a = Ctrl+A = 0x01
        actions.append(ContextQuickAction(
            icon: "arrow.clockwise.circle.fill",
            title: "Repeat",
            color: .nethackAccent,
            command: "\u{01}"
        ))
        
        return actions
    }
    
    // Badge count (context-aware actions only, excluding always-available)
    private var badgeCount: Int {
        var count = 0

        if snapshot.isStairsDown { count += 1 }
        if snapshot.isStairsUp { count += 1 }
        if !snapshot.adjacentDoors.isEmpty { count += 2 }  // Open/Close + Kick
        if snapshot.itemCount > 0 { count += 1 }
        if snapshot.hasContainer { count += 1 }  // Loot
        if snapshot.hasLockedContainer { count += 1 }  // Force

        return count
    }
    
    var body: some View {
        // SWIFTUI-L-002: ZStack for overlay layering
        // Alignment: .leading so button stays left, strip expands right
        ZStack(alignment: .leading) {
            // Main FAB button (always visible, stays in place)
            mainButton

            // Expanded action strip (expands to the RIGHT of button)
            if isExpanded {
                expandedStrip
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                        removal: .scale(scale: 0.9, anchor: .leading).combined(with: .opacity)
                    ))
            }
        }
        .onAppear {
            refreshSnapshot()
        }
        // PUSH MODEL: Refresh on map updates
        .onReceive(NotificationCenter.default.publisher(for: .nethackMapUpdated)) { _ in
            refreshSnapshot()
            // NOTE: Auto-collapse removed - user manually closes menu
        }
    }
    
    // MARK: - Main Button (Collapsed State)
    
    private var mainButton: some View {
        // CONSISTENCY FIX: Match MagnifyingGlassButton sizing for visual consistency
        // Both buttons use RoundedRectangle with cornerRadius 12 (standard button shape)
        let buttonSize = ScalingEnvironment.UIScale.magnifyingGlassSize(isPhone: isPhone)
        let iconSize: CGFloat = isPhone ? 20 : 24
        let badgeFontSize: CGFloat = isPhone ? 10 : 12

        return Button {
            withAnimation(expansionAnimation) {
                isExpanded.toggle()
            }
            HapticManager.shared.tap()
        } label: {
            ZStack {
                // Background - SQUARE with rounded corners (matches MagnifyingGlassButton)
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isExpanded ? Color.nethackAccent : Color.nethackGray700.opacity(0.4),
                                lineWidth: isExpanded ? 3 : 2
                            )
                    )
                    .shadow(
                        color: isExpanded ? Color.nethackAccent.opacity(0.4) : Color.black.opacity(0.3),
                        radius: isExpanded ? 8 : 4,
                        x: 0,
                        y: 2
                    )

                // Icon and label (matches MagnifyingGlassButton layout)
                VStack(spacing: 2) {
                    Image(systemName: isExpanded ? "xmark" : "sparkles.rectangle.stack")
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundColor(isExpanded ? .nethackAccent : .nethackGray700)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(buttonAnimation, value: isExpanded)

                    Text(isExpanded ? "Close" : "Actions")
                        .font(.system(size: isPhone ? 8 : 10, weight: .semibold))
                        .foregroundColor(.nethackGray900)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                // Badge (only when collapsed and has context actions)
                if !isExpanded && badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: badgeFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: isPhone ? 18 : 22, height: isPhone ? 18 : 22)
                        .background(
                            Circle()
                                .fill(Color.nethackAccent)
                                .shadow(color: .nethackAccent.opacity(0.5), radius: 3)
                        )
                        .offset(x: buttonSize / 2 - 6, y: -(buttonSize / 2 - 6))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 12))  // SWIFTUI-M-003 - match shape
        }
        .buttonStyle(.plain)
        .simultaneousGesture(  // SWIFTUI-G-003: Press state tracking
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(buttonAnimation) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(buttonAnimation) {
                        isPressed = false
                    }
                }
        )
        // Accessibility
        .accessibilityLabel(isExpanded ? "Close actions menu" : "Open actions menu, \(badgeCount) context actions available")
        .accessibilityHint("Tap to \(isExpanded ? "close" : "expand") quick actions")
    }
    
    // MARK: - Expanded Strip
    
    private var expandedStrip: some View {
        let buttonSize: CGFloat = isPhone ? 44 : 52
        let spacing: CGFloat = isPhone ? 6 : 8
        let horizontalPadding: CGFloat = isPhone ? 8 : 12
        let verticalPadding: CGFloat = isPhone ? 6 : 8

        // iPad: 8 actions (more space), iPhone: 5 actions
        let maxActions = isPhone ? 5 : 8
        let visibleActions = Array(availableActions.prefix(maxActions))
        
        return HStack(spacing: spacing) {
            ForEach(visibleActions) { action in
                ActionStripButton(
                    action: action,
                    size: buttonSize,
                    isPhone: isPhone
                ) {
                    // Check for escape warning on "<" command
                    if action.command == "<" && NetHackBridge.shared.checkEscapeWarning() {
                        overlayManager.showEscapeWarningSheet()
                        HapticManager.shared.warning()
                    } else if action.command == "M-l" {
                        // Loot - use native picker (matches CommandHandler behavior)
                        overlayManager.showLootOptionsPicker()
                        HapticManager.shared.buttonPress()
                    } else if action.command == "M-f" {
                        // Force - send command + auto-confirm "force its lock? [ynq]"
                        NetHackBridge.shared.sendRawByte(UInt8(0x80 | UInt8(ascii: "f")))
                        // Queue 'y' to confirm the prompt
                        ios_queue_input(Int8(Character("y").asciiValue!))
                        HapticManager.shared.buttonPress()
                    } else if action.command.hasPrefix("M-") {
                        // Other Meta commands - send as raw byte with high bit set
                        let cmd = String(action.command.dropFirst(2))
                        if let char = cmd.first, let ascii = char.asciiValue {
                            NetHackBridge.shared.sendRawByte(UInt8(ascii | 0x80))
                        }
                        HapticManager.shared.buttonPress()
                    } else {
                        // Execute action normally
                        gameManager.sendCommand(action.command)
                        HapticManager.shared.buttonPress()
                    }
                    // NOTE: No auto-collapse - user manually closes menu
                }
            }
            
            // "More" button if there are additional actions
            if availableActions.count > maxActions {
                ActionStripButton(
                    action: ContextQuickAction(
                        icon: "ellipsis",
                        title: "More",
                        color: .nethackGray600,
                        command: ""
                    ),
                    size: buttonSize,
                    isPhone: isPhone
                ) {
                    // Could open full action menu here
                    HapticManager.shared.tap()
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            // CONSISTENCY: Use RoundedRectangle to match button style (not Capsule)
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.nethackGray700.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, x: 4, y: 2)
        )
        // Offset to the RIGHT of the main button (expands right)
        // Use same size calculation as mainButton for proper alignment
        .offset(x: ScalingEnvironment.UIScale.magnifyingGlassSize(isPhone: isPhone) + 8)
    }
    
    // MARK: - Helpers
    
    private func refreshSnapshot() {
        snapshot = NetHackBridge.shared.getGameStateSnapshot()
    }
}

// MARK: - Action Strip Button

private struct ActionStripButton: View {
    let action: ContextQuickAction
    let size: CGFloat
    let isPhone: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    private var pressAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: isPhone ? 2 : 3) {
                Image(systemName: action.icon)
                    .font(.system(size: isPhone ? 16 : 20, weight: .semibold))
                    .foregroundColor(action.color)
                
                Text(action.title)
                    .font(.system(size: isPhone ? 8 : 10, weight: .medium))
                    .foregroundColor(.nethackGray900)
                    .lineLimit(1)
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
                    .fill(isPressed ? action.color.opacity(0.2) : Color.nethackGray300.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
                            .strokeBorder(
                                isPressed ? action.color.opacity(0.5) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .contentShape(Rectangle())  // SWIFTUI-M-003
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(pressAnimation) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(pressAnimation) {
                        isPressed = false
                    }
                }
        )
        // SWIFTUI-HIG: Minimum touch target 44pt (size param ensures this)
        .accessibilityLabel(action.title)
        .accessibilityHint("Tap to \(action.title.lowercased())")
    }
}

// MARK: - Preview

#if DEBUG
struct ContextActionsButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    // Simulated button stack (matches actual game layout)
                    // Both buttons now use SQUARE shape (RoundedRectangle) for consistency
                    VStack(alignment: .leading, spacing: 12) {
                        // MagnifyingGlassButton placeholder (square with rounded corners)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .frame(width: 70, height: 70)
                            .overlay(
                                VStack(spacing: 2) {
                                    Image(systemName: "magnifyingglass.circle")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.gray)
                                    Text("Inspect")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.gray)
                                }
                            )

                        // Our new button (also square with rounded corners)
                        ContextActionsButton(gameManager: NetHackGameManager(), overlayManager: GameOverlayManager())
                    }
                    .padding(.leading, 20)

                    Spacer()
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
