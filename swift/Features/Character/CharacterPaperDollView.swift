//
//  CharacterPaperDollView.swift
//  nethack
//
//  Paper Doll equipment display view for NetHack iOS.
//

import SwiftUI

// MARK: - Equipment Slot View

/// Individual equipment slot with item or empty state
struct EquipmentSlotView: View {
    let slot: EquipmentSlot
    let item: EquippedItem?
    let isCompact: Bool

    private let isPhone = ScalingEnvironment.isPhone
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Animation states
    @State private var pulseScale: CGFloat = 1.0
    @State private var cursedGlow: CGFloat = 0.3

    private var slotSize: CGFloat {
        isCompact ? 44 : (isPhone ? 50 : 60)
    }

    var body: some View {
        VStack(spacing: isCompact ? 2 : 4) {
            ZStack {
                // Background - iOS HIG: 44pt minimum touch target
                RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                    .fill(backgroundColor)
                    .frame(width: slotSize, height: slotSize)

                // Cursed item glow effect
                if let item = item, item.isCursed {
                    RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                        .strokeBorder(Color.red.opacity(cursedGlow), lineWidth: 2)
                        .frame(width: slotSize, height: slotSize)
                }

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(iconColor)

                // BUC indicator (small dot in corner)
                if let item = item, !item.isEmpty {
                    bucIndicator(for: item)
                }
            }
            .scaleEffect(hasItem ? pulseScale : 1.0)

            // Label (not in ultra-compact mode)
            if !isCompact {
                Text(slot.shortName)
                    .font(.system(size: isPhone ? 9 : 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        guard !reduceMotion else { return }

        // Equipped item pulse (subtle scale animation)
        if hasItem {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.03
            }
        }

        // Cursed item glow pulse
        if let item = item, item.isCursed {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                cursedGlow = 0.7
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        guard let item = item, !item.isEmpty else {
            return "\(slot.displayName): Empty"
        }
        return "\(slot.displayName): \(item.name)"
    }

    private var accessibilityHint: String {
        guard let item = item, !item.isEmpty else {
            return "No item equipped in this slot"
        }

        var hints: [String] = []
        if item.isCursed { hints.append("Cursed") }
        if item.isBlessed { hints.append("Blessed") }
        return hints.isEmpty ? "Equipped" : hints.joined(separator: ", ")
    }

    private var hasItem: Bool {
        guard let item = item else { return false }
        return !item.isEmpty
    }

    private var backgroundColor: Color {
        guard hasItem else {
            return Color.white.opacity(0.1)
        }
        return slot.color.opacity(0.3)
    }

    private var iconName: String {
        guard hasItem else {
            return slot.emptyIcon
        }
        return slot.icon
    }

    private var iconSize: CGFloat {
        if isCompact { return isPhone ? 16 : 18 }
        return isPhone ? 20 : 24
    }

    private var iconColor: Color {
        guard hasItem else {
            return .white.opacity(0.3)
        }
        return slot.color
    }

    @ViewBuilder
    private func bucIndicator(for item: EquippedItem) -> some View {
        let indicatorSize: CGFloat = isCompact ? 8 : 10
        // Position at top-right corner: (slotSize/2) - (indicatorSize/2) - padding
        let offset: CGFloat = (slotSize / 2) - (indicatorSize / 2) - 2

        Circle()
            .fill(item.bucStatus.color)
            .frame(width: indicatorSize, height: indicatorSize)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
            )
            .offset(x: offset, y: -offset)
    }
}

// MARK: - Paper Doll View

/// Visual equipment layout showing character equipment slots
struct CharacterPaperDollView: View {
    @ObservedObject var statusManager: CharacterStatusManager
    let isCompact: Bool
    var isInteractive: Bool = true  // Enable tap interactions

    // Optional callbacks for handling interactions
    var onSlotTap: ((EquipmentSlot, EquippedItem?) -> Void)? = nil

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            // Head row: Helmet, Amulet, Blindfold
            HStack(spacing: isCompact ? 4 : 8) {
                slotView(for: .helmet)
                slotView(for: .amulet)
                slotView(for: .blindfold)
            }

            // Arms row: Weapon, Body, Shield
            HStack(spacing: isCompact ? 4 : 8) {
                slotView(for: .weapon)

                // Body stack (shirt under armor)
                ZStack {
                    slotView(for: .shirt)
                        .opacity(0.5)
                        .offset(x: 4, y: 4)
                    slotView(for: .bodyArmor)
                }

                slotView(for: .shield)
            }

            // Hands row: Gloves, Cloak, Rings
            HStack(spacing: isCompact ? 4 : 8) {
                slotView(for: .gloves)

                // Cloak (between gloves and rings)
                slotView(for: .cloak)

                // Ring stack
                VStack(spacing: 2) {
                    slotView(for: .leftRing)
                    slotView(for: .rightRing)
                }
            }

            // Feet row: Boots, Secondary, Quiver
            HStack(spacing: isCompact ? 4 : 8) {
                slotView(for: .boots)
                slotView(for: .secondary)
                slotView(for: .quiver)
            }
        }
        .padding(isCompact ? 6 : 10)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 10 : 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 10 : 14)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func slotView(for slot: EquipmentSlot) -> some View {
        let item = statusManager.status?.item(for: slot)

        if isInteractive {
            EquipmentSlotView(slot: slot, item: item, isCompact: isCompact)
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticManager.shared.tap()
                    onSlotTap?(slot, item)
                }
        } else {
            EquipmentSlotView(slot: slot, item: item, isCompact: isCompact)
        }
    }
}

// MARK: - Interactive Paper Doll Container

/// A container that provides full interaction handling for the paper doll
/// Handles both empty slot taps (opens item selection) and equipped slot taps (shows action sheet)
struct InteractivePaperDollView: View {
    @ObservedObject var statusManager: CharacterStatusManager
    @ObservedObject var overlayManager: GameOverlayManager
    let isCompact: Bool

    // Action sheet state
    @State private var selectedSlot: EquipmentSlot?
    @State private var selectedItem: EquippedItem?
    @State private var showActionSheet = false

    var body: some View {
        ZStack {
            CharacterPaperDollView(
                statusManager: statusManager,
                isCompact: isCompact,
                isInteractive: true,
                onSlotTap: handleSlotTap
            )

            // Action sheet overlay
            if showActionSheet, let slot = selectedSlot, let item = selectedItem, let status = statusManager.status {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { dismissActionSheet() }

                EquipmentActionSheet(
                    slot: slot,
                    item: item,
                    status: status,
                    onRemove: { handleRemove(slot: slot) },
                    onInfo: { handleInfo(item: item) },
                    onDismiss: { dismissActionSheet() }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.15), value: showActionSheet)
    }

    private func handleSlotTap(slot: EquipmentSlot, item: EquippedItem?) {
        if let item = item, !item.isEmpty {
            // Slot has item → show action sheet
            selectedSlot = slot
            selectedItem = item
            showActionSheet = true
        } else {
            // Empty slot → open item selection for this slot type
            handleEmptySlotTap(slot: slot)
        }
    }

    private func handleEmptySlotTap(slot: EquipmentSlot) {
        // Map slot to appropriate NetHack command
        switch slot {
        case .weapon:
            overlayManager.requestItemSelection(context: .wield())
        case .secondary:
            // Secondary weapon - use wield, user picks weapon
            overlayManager.requestItemSelection(context: .wield())
        case .leftRing, .rightRing:
            overlayManager.requestItemSelection(context: .putOn())
        case .amulet:
            overlayManager.requestItemSelection(context: .putOn())
        case .bodyArmor, .cloak, .helmet, .shield, .gloves, .boots, .shirt:
            overlayManager.requestItemSelection(context: .wear())
        case .quiver:
            overlayManager.requestItemSelection(context: .quiver())
        case .blindfold:
            overlayManager.requestItemSelection(context: .putOn())
        }
    }

    private func handleRemove(slot: EquipmentSlot) {
        guard let status = statusManager.status else { return }

        dismissActionSheet()

        // Get the appropriate remove command
        let command = status.removeCommand(for: slot)

        // Queue the command
        for char in command {
            if let ascii = char.asciiValue {
                ios_queue_input(Int8(ascii))
            }
        }

        print("[EQUIPMENT] Removing item from \(slot.displayName) with command '\(command)'")
    }

    private func handleInfo(item: EquippedItem) {
        dismissActionSheet()
        // TODO: Show item detail panel
        print("[EQUIPMENT] Info requested for: \(item.name)")
    }

    private func dismissActionSheet() {
        showActionSheet = false
        selectedSlot = nil
        selectedItem = nil
    }
}

// MARK: - Character Status Sheet

/// Full character status sheet with identity, equipment, and conditions
struct CharacterStatusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var statusManager = CharacterStatusManager.shared
    @ObservedObject var overlayManager: GameOverlayManager = GameOverlayManager()

    private let isPhone = ScalingEnvironment.isPhone

    /// Initialize with optional overlay manager for equipment interactions
    init(overlayManager: GameOverlayManager? = nil) {
        if let manager = overlayManager {
            self._overlayManager = ObservedObject(wrappedValue: manager)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Identity header
                    if let status = statusManager.status {
                        identityHeader(status.identity)
                    }

                    // Interactive Paper Doll (tap slots to equip/remove)
                    InteractivePaperDollView(
                        statusManager: statusManager,
                        overlayManager: overlayManager,
                        isCompact: false
                    )

                    // Equipment list (detailed)
                    if let status = statusManager.status {
                        equipmentList(status.equipment)
                    }

                    // Conditions
                    if let status = statusManager.status, !status.activeConditions.isEmpty {
                        conditionsList(status.activeConditions)
                    }
                }
                .padding()
            }
            .background(Color.black.opacity(0.9))
            .navigationTitle("Character Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            statusManager.refresh()
        }
    }

    @ViewBuilder
    private func identityHeader(_ identity: CharacterIdentity) -> some View {
        VStack(spacing: 4) {
            Text("\(identity.roleName)")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("\(identity.raceName) \(identity.genderName) \(identity.alignmentName)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Text("Level \(identity.level) • XP: \(identity.experience)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func equipmentList(_ equipment: [EquippedItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equipment")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(equipment) { item in
                if !item.isEmpty {
                    equipmentRow(item)
                }
            }

            if equipment.allSatisfy({ $0.isEmpty }) {
                Text("No equipment worn")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func equipmentRow(_ item: EquippedItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.slot.icon)
                .font(.system(size: 16))
                .foregroundColor(item.slot.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundColor(.white)

                Text(item.slot.displayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // BUC badge
            if item.isCursed || item.isBlessed {
                bucBadge(item.bucStatus)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func bucBadge(_ status: ItemBUCStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 10))
            Text(status.rawValue.capitalized)
                .font(.caption2)
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(status.color.opacity(0.2))
        )
    }

    @ViewBuilder
    private func conditionsList(_ conditions: [PlayerCondition]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conditions")
                .font(.headline)
                .foregroundColor(.white)

            FlowLayout(spacing: 8) {
                ForEach(conditions, id: \.rawValue) { condition in
                    conditionBadge(condition)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func conditionBadge(_ condition: PlayerCondition) -> some View {
        HStack(spacing: 4) {
            Image(systemName: condition.icon)
                .font(.system(size: 12))
            Text(condition.shortLabel)
                .font(.caption)
        }
        .foregroundColor(condition.iconColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(condition.color)
        )
    }
}

// MARK: - Character Status Overlay (Modern Panel)

/// Modern overlay panel for character status - replaces old scrollable sheet
struct CharacterStatusOverlay: View {
    @ObservedObject var statusManager: CharacterStatusManager
    @ObservedObject var overlayManager: GameOverlayManager
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isPresented = false

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        GeometryReader { geometry in
            // LANDSCAPE FIX: Ensure we use landscape dimensions
            // In landscape, width should be > height
            let isLandscape = geometry.size.width > geometry.size.height
            let screenWidth = isLandscape ? geometry.size.width : geometry.size.height
            let screenHeight = isLandscape ? geometry.size.height : geometry.size.width

            // Panel dimensions for landscape
            let panelWidth: CGFloat = isPhone ? min(600, screenWidth * 0.75) : min(680, screenWidth * 0.6)
            let panelHeight: CGFloat = isPhone ? screenHeight * 0.85 : min(400, screenHeight * 0.8)
            let paperDollWidth: CGFloat = isPhone ? panelWidth * 0.5 : 280

            ZStack {
                // Dark backdrop - MUST consume all touch events
                Color.black.opacity(isPresented ? 0.6 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())  // Make entire area tappable
                    .onTapGesture { dismissWithAnimation() }
                    .gesture(DragGesture().onChanged { _ in })  // Block drag through

                // Main panel - HORIZONTAL layout for landscape
                HStack(spacing: 0) {
                    // Left: Paper Doll with header
                    VStack(spacing: 0) {
                        // Header
                        characterHeader
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        Divider()
                            .background(Color.white.opacity(0.1))

                        // Interactive Paper Doll
                        InteractivePaperDollView(
                            statusManager: statusManager,
                            overlayManager: overlayManager,
                            isCompact: isPhone
                        )
                        .padding(12)

                        Spacer()

                        // Close button
                        Button(action: dismissWithAnimation) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Close")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                            )
                        }
                        .padding(.bottom, 12)
                    }
                    .frame(width: paperDollWidth)

                    // Right: Equipment list + Conditions (always show in landscape)
                    Divider()
                        .background(Color.white.opacity(0.1))

                    VStack(alignment: .leading, spacing: 12) {
                        equipmentSummary
                        conditionsSummary
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                }
                .frame(width: panelWidth, height: panelHeight)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                .scaleEffect(isPresented ? 1.0 : 0.9)
                .opacity(isPresented ? 1.0 : 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())  // Ensure ZStack captures all touches
        }
        .allowsHitTesting(true)  // Ensure overlay blocks all touches to game below
        .onAppear {
            statusManager.refresh()
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                isPresented = true
            }
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
            isPresented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    // MARK: - Character Header

    private var characterHeader: some View {
        VStack(spacing: 6) {
            if let status = statusManager.status {
                // Role name with icon
                HStack(spacing: 8) {
                    Image(systemName: roleIcon(for: status.identity.roleName))
                        .font(.system(size: 20))
                        .foregroundColor(.yellow)

                    Text(status.identity.roleName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                // Race, Gender, Alignment
                Text("\(status.identity.raceName.capitalized) \(status.identity.genderName.capitalized)")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))

                // Level & XP
                HStack(spacing: 12) {
                    Label("Lv.\(status.identity.level)", systemImage: "star.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cyan)

                    Label("\(status.identity.experience) XP", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                Text("Loading...")
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func roleIcon(for role: String) -> String {
        switch role.lowercased() {
        case "archeologist": return "map.fill"
        case "barbarian": return "figure.martial.arts"
        case "caveman", "cavewoman": return "hand.raised.fill"
        case "healer": return "cross.fill"
        case "knight": return "shield.fill"
        case "monk": return "figure.mind.and.body"
        case "priest", "priestess": return "book.fill"
        case "ranger": return "arrow.up.right"
        case "rogue": return "theatermasks.fill"
        case "samurai": return "bolt.fill"
        case "tourist": return "camera.fill"
        case "valkyrie": return "sparkles"
        case "wizard": return "wand.and.stars"
        default: return "person.fill"
        }
    }

    // MARK: - Equipment Summary

    private var equipmentSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equipment")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            if let status = statusManager.status {
                let equippedItems = status.equipment.filter { !$0.isEmpty }

                if equippedItems.isEmpty {
                    Text("Nothing equipped")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.vertical, 8)
                } else {
                    ForEach(equippedItems.prefix(6)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.slot.icon)
                                .font(.system(size: 11))
                                .foregroundColor(item.slot.color)
                                .frame(width: 16)

                            Text(item.name)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)

                            Spacer()

                            if item.isCursed {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                            } else if item.isBlessed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if equippedItems.count > 6 {
                        Text("+\(equippedItems.count - 6) more")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Conditions Summary

    private var conditionsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            if let status = statusManager.status {
                // Hunger & Encumbrance
                HStack(spacing: 12) {
                    statusBadge(
                        icon: "fork.knife",
                        text: status.hungerName.isEmpty ? "Normal" : status.hungerName,
                        color: hungerColor(status.hungerState)
                    )

                    statusBadge(
                        icon: "bag.fill",
                        text: status.encumbranceName.isEmpty ? "Unencumbered" : status.encumbranceName,
                        color: encumbranceColor(status.encumbrance)
                    )
                }

                // Active conditions
                if !status.activeConditions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(status.activeConditions, id: \.rawValue) { condition in
                            conditionChip(condition)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }

    private func conditionChip(_ condition: PlayerCondition) -> some View {
        HStack(spacing: 3) {
            Image(systemName: condition.icon)
                .font(.system(size: 9))
            Text(condition.shortLabel)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(condition.iconColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(condition.color)
        )
    }

    private func hungerColor(_ state: Int) -> Color {
        switch state {
        case 0: return .green      // Normal
        case 1: return .yellow     // Hungry
        case 2: return .orange     // Weak
        case 3: return .red        // Fainting
        case 4: return .white      // Fainted
        case 5: return .green      // Satiated
        default: return .gray
        }
    }

    private func encumbranceColor(_ state: Int) -> Color {
        switch state {
        case 0: return .green      // Unencumbered
        case 1: return .yellow     // Burdened
        case 2: return .orange     // Stressed
        case 3: return .red        // Strained
        case 4: return .purple     // Overtaxed
        case 5: return .red        // Overloaded
        default: return .gray
        }
    }
}

// MARK: - Preview
// NOTE: FlowLayout is defined in ItemDetailView.swift

#Preview("Character Status Overlay") {
    ZStack {
        Color.black.ignoresSafeArea()
        CharacterStatusOverlay(
            statusManager: CharacterStatusManager.shared,
            overlayManager: GameOverlayManager(),
            onDismiss: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Character Status Sheet") {
    CharacterStatusSheet()
        .preferredColorScheme(.dark)
}

// MARK: - Character Status Button

/// Floating button to open Character Status sheet
struct CharacterStatusButton: View {
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone
    private let buttonSize: CGFloat = 44  // iOS HIG minimum touch target

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background circle with glass effect
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                // Character icon
                Image(systemName: "person.fill")
                    .font(.system(size: isPhone ? 18 : 20, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15),
            value: isPressed
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Character Status")
        .accessibilityHint("Shows equipment and character details")
    }
}

#Preview("Character Status Button") {
    CharacterStatusButton(onTap: {})
        .padding()
        .background(Color.black)
}

#Preview("Paper Doll Compact") {
    CharacterPaperDollView(
        statusManager: CharacterStatusManager.shared,
        isCompact: true
    )
    .padding()
    .background(Color.black)
}
