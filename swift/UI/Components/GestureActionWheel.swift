//
//  GestureActionWheel.swift
//  nethack
//
//  Vertical tile menu for NetHack actions
//  - Touch & hold category button → tiles appear above
//  - Swipe upward over tiles → highlighted
//  - Release → execute
//

import SwiftUI

struct GestureActionWheel: View {
    let category: ActionCategory
    let actions: [NetHackAction]
    let gameManager: NetHackGameManager
    let overlayManager: GameOverlayManager
    let touchPoint: CGPoint  // Global coordinates of button
    let onDismiss: () -> Void

    @State private var selectedAction: NetHackAction?
    @State private var continuousGestureActive = false  // Track if user dragged immediately

    // Visual constants
    private let tileHeight: CGFloat = 60
    private let tileWidth: CGFloat = 280
    private let tileSpacing: CGFloat = 8
    private let offsetAboveButton: CGFloat = 25  // Reduced from 80 for tighter connection (SWIFTUI-L-005)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent backdrop
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }

                // Vertical tile stack - positioned absolutely at touchPoint
                VStack(spacing: tileSpacing) {
                    ForEach(actions) { action in
                        ActionTile(
                            action: action,
                            isSelected: selectedAction?.id == action.id,
                            category: category
                        )
                        .frame(width: tileWidth, height: tileHeight)
                        .contentShape(Rectangle())  // Ensure tap targets work (SWIFTUI-M-003)
                        .onTapGesture {
                            // Tap mode: tap tile to select and execute
                            guard !continuousGestureActive else { return }
                            selectedAction = action
                            HapticManager.shared.selection()

                            // Brief delay for visual feedback (CONC-S-001: Modern async/await)
                            Task {
                                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                                handleDragEnd()
                            }
                        }
                    }
                }
                .frame(width: tileWidth)
                .position(
                    x: touchPoint.x,
                    y: max(totalHeight / 2 + 20, touchPoint.y - offsetAboveButton - totalHeight / 2)
                )
                .simultaneousGesture(  // SWIFTUI-G-003: Allow coexistence with CategoryButton gesture
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)  // SWIFTUI-G-001, L-004: Global coords match button
                        .onChanged { value in
                            // Activate continuous mode on first drag movement
                            if !continuousGestureActive {
                                continuousGestureActive = true
                            }
                            handleDrag(value, geometry: geometry)
                        }
                        .onEnded { _ in
                            handleDragEnd()
                            continuousGestureActive = false  // Reset for next interaction
                        }
                )
            }
        }
        .ignoresSafeArea()
    }

    private var totalHeight: CGFloat {
        CGFloat(actions.count) * (tileHeight + tileSpacing)
    }

    private func handleDrag(_ value: DragGesture.Value, geometry: GeometryProxy) {
        // Drag location in global coordinates
        let dragY = value.location.y

        // Calculate stack position (center Y is at touchPoint.y - offsetAboveButton - totalHeight/2)
        let stackCenterY = max(totalHeight / 2 + 20, touchPoint.y - offsetAboveButton - totalHeight / 2)
        let stackTop = stackCenterY - totalHeight / 2
        let stackBottom = stackCenterY + totalHeight / 2

        // Check if drag is within tile area
        guard dragY >= stackTop && dragY <= stackBottom else {
            selectedAction = nil
            return
        }

        // Find which tile we're over
        let relativeY = dragY - stackTop

        // Calculate tile index accounting for spacing
        var currentY: CGFloat = 0
        for (index, action) in actions.enumerated() {
            let tileTop = currentY
            let tileBottom = currentY + tileHeight

            if relativeY >= tileTop && relativeY <= tileBottom {
                if selectedAction?.id != action.id {
                    selectedAction = action
                    HapticManager.shared.selection()
                }
                return
            }

            currentY += tileHeight + tileSpacing
        }

        selectedAction = nil
    }

    private func handleDragEnd() {
        guard let selected = selectedAction else {
            onDismiss()
            return
        }

        // Execute selected action
        executeAction(selected)

        // Haptic feedback
        HapticManager.shared.buttonPress()

        // Dismiss wheel
        onDismiss()
    }

    private func executeAction(_ action: NetHackAction) {
        print("[ACTION_TRIGGERED] GestureWheel - Action: '\(action.name)' Command: '\(action.command)'")

        // Track usage
        ActionUsageTracker.shared.trackUsage(of: action)

        // Delegate to centralized CommandHandler
        _ = CommandHandler.execute(action: action, gameManager: gameManager, overlayManager: overlayManager)
    }
}

// MARK: - Action Tile (Vertical Card)

struct ActionTile: View {
    let action: NetHackAction
    let isSelected: Bool
    let category: ActionCategory

    @Environment(\.accessibilityReduceMotion) var reduceMotion  // SWIFTUI-A-009: Mandatory accessibility

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: action.icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(isSelected ? category.color : .nethackGray700)  // LCH: L:70 - unselected icon
                .frame(width: 40)

            // Name and command
            VStack(alignment: .leading, spacing: 2) {
                Text(action.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .nethackGray900 : .nethackGray800)  // LCH: L:90/L:80 - primary text

                if !action.command.isEmpty {
                    Text(action.command)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.nethackGray600)  // LCH: L:60 - secondary text
                }
            }

            Spacer()

            // Selected indicator
            if isSelected {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(category.color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)  // Match ActionBarView material
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? category.color : Color.nethackGray400.opacity(0.6), lineWidth: 2)  // LCH: L:40 with opacity
        )
        .shadow(color: isSelected ? category.color.opacity(0.4) : Color.black.opacity(0.4), radius: 8, x: 0, y: 4)  // 40% opacity shadow (SWIFTUI-L-002)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15),  // SWIFTUI-A-009: Reduce Motion support
            value: isSelected
        )
    }
}

// MARK: - Preview

struct GestureActionWheel_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GestureActionWheel(
                category: .movement,
                actions: NetHackAction.actionsForCategory(.movement),
                gameManager: NetHackGameManager(),
                overlayManager: GameOverlayManager(),
                touchPoint: CGPoint(x: 200, y: 400),
                onDismiss: {}
            )
        }
        .preferredColorScheme(.dark)
    }
}
