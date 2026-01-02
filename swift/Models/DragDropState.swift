import SwiftUI
import Observation

/// State management for drag-and-drop operations with visual feedback
@Observable
class DragDropState {
    // MARK: - Drag State
    var draggedAction: NetHackAction?
    var dragSourceSlot: Int?
    var dragLocation: CGPoint = .zero
    var isDragging: Bool = false

    // MARK: - Drop Target State
    var dropTargetSlot: Int?
    var hoveredSlots: Set<Int> = []

    // MARK: - Visual State
    var ghostOpacity: Double = 0.3
    var dragScale: CGFloat = 1.05
    var dragRotation: Double = 2.0
    var shadowRadius: CGFloat = 20

    // MARK: - Animation State
    var isAnimatingDrop: Bool = false
    var isAnimatingCancel: Bool = false

    // MARK: - Drag Lifecycle

    func startDrag(action: NetHackAction, fromSlot: Int, at location: CGPoint) {
        guard !isDragging else { return }

        draggedAction = action
        dragSourceSlot = fromSlot
        dragLocation = location
        isDragging = true

        // Haptic feedback
        HapticManager.shared.dragStart()

        // Animate lift
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            dragScale = 1.05
            shadowRadius = 20
        }
    }

    func updateDrag(at location: CGPoint) {
        guard isDragging else { return }
        dragLocation = location
    }

    func enterDropZone(slot: Int) {
        guard isDragging else { return }
        guard !hoveredSlots.contains(slot) else { return }

        hoveredSlots.insert(slot)
        dropTargetSlot = slot

        // Haptic feedback
        HapticManager.shared.dropZoneEntered()
    }

    func exitDropZone(slot: Int) {
        guard isDragging else { return }

        hoveredSlots.remove(slot)

        if dropTargetSlot == slot {
            dropTargetSlot = hoveredSlots.first
        }

        // Haptic feedback
        HapticManager.shared.dropZoneExited()
    }

    func endDrag(success: Bool, completion: @escaping () -> Void) {
        guard isDragging else {
            completion()
            return
        }

        if success {
            animateDropSuccess(completion: completion)
        } else {
            animateDropCancel(completion: completion)
        }
    }

    // MARK: - Private Animation Helpers

    private func animateDropSuccess(completion: @escaping () -> Void) {
        isAnimatingDrop = true
        HapticManager.shared.dropSuccess()

        // Pop animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            dragScale = 1.2
        }

        // Return to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                self.dragScale = 1.0
                self.shadowRadius = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.resetDragState()
                self.isAnimatingDrop = false
                completion()
            }
        }
    }

    private func animateDropCancel(completion: @escaping () -> Void) {
        isAnimatingCancel = true
        HapticManager.shared.cancel()

        // Spring back animation
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 20)) {
            dragScale = 1.0
            shadowRadius = 0
            dragRotation = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.resetDragState()
            self.isAnimatingCancel = false
            completion()
        }
    }

    private func resetDragState() {
        isDragging = false
        draggedAction = nil
        dragSourceSlot = nil
        dropTargetSlot = nil
        hoveredSlots.removeAll()
        dragLocation = .zero
        dragScale = 1.0
        shadowRadius = 0
        dragRotation = 2.0
    }

    // MARK: - Validation

    func isValidDropTarget(slot: Int) -> Bool {
        // Can't drop on source slot (would do nothing)
        guard slot != dragSourceSlot else { return false }

        // All slots accept any action
        return true
    }

    func canAcceptDrop(slot: Int) -> Bool {
        guard let _ = draggedAction else { return false }
        return isValidDropTarget(slot: slot)
    }
}
