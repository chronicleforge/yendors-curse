//
//  IntrinsicsView.swift
//  nethack
//
//  Premium Abilities/Intrinsics display for Equipment Panel.
//  Shows player's active resistances, abilities, and status conditions.
//
//  Design: Only shows DISCOVERED abilities (what player would know via #attributes)
//  This is NOT a cheat - it's a modern UI for existing information.
//

import SwiftUI

// MARK: - Intrinsic Category

/// Categories for organizing intrinsics display
enum IntrinsicCategory: String, CaseIterable {
    case resistances = "Resistances"
    case vision = "Vision"
    case movement = "Movement"
    case combat = "Combat"
    case conditions = "Conditions"

    var icon: String {
        switch self {
        case .resistances: return "shield.lefthalf.filled"
        case .vision: return "eye.fill"
        case .movement: return "figure.walk"
        case .combat: return "burst.fill"
        case .conditions: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .resistances: return .cyan
        case .vision: return .purple
        case .movement: return .green
        case .combat: return .orange
        case .conditions: return .red
        }
    }
}

// MARK: - Intrinsic Item

/// Individual intrinsic ability display data
struct IntrinsicItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let isActive: Bool
    let isNegative: Bool

    init(name: String, icon: String, color: Color, isActive: Bool, isNegative: Bool = false) {
        self.name = name
        self.icon = icon
        self.color = color
        self.isActive = isActive
        self.isNegative = isNegative
    }
}

// MARK: - Swift Intrinsics Model

/// Swift wrapper for PlayerIntrinsics from C bridge
struct SwiftPlayerIntrinsics {
    // Resistances
    var fireResistance: Bool = false
    var coldResistance: Bool = false
    var sleepResistance: Bool = false
    var disintegrationResistance: Bool = false
    var shockResistance: Bool = false
    var poisonResistance: Bool = false
    var drainResistance: Bool = false
    var magicResistance: Bool = false
    var acidResistance: Bool = false
    var stoneResistance: Bool = false
    var sickResistance: Bool = false

    // Vision
    var seeInvisible: Bool = false
    var telepathy: Bool = false
    var infravision: Bool = false
    var warning: Bool = false
    var searching: Bool = false

    // Movement
    var levitation: Bool = false
    var flying: Bool = false
    var swimming: Bool = false
    var magicalBreathing: Bool = false
    var passesWalls: Bool = false
    var slowDigestion: Bool = false
    var regeneration: Bool = false
    var teleportation: Bool = false
    var teleportControl: Bool = false
    var polymorph: Bool = false
    var polymorphControl: Bool = false

    // Combat
    var stealth: Bool = false
    var aggravateMonster: Bool = false
    var conflict: Bool = false
    var protection: Bool = false
    var reflection: Bool = false
    var freeAction: Bool = false

    // Conditions (negative)
    var hallucinating: Bool = false
    var confused: Bool = false
    var stunned: Bool = false
    var blinded: Bool = false
    var deaf: Bool = false
    var sick: Bool = false
    var stoned: Bool = false
    var strangled: Bool = false
    var slimed: Bool = false
    var woundedLegs: Bool = false
    var fumbling: Bool = false

    /// Load from C bridge
    static func load() -> SwiftPlayerIntrinsics {
        var cIntrinsics = PlayerIntrinsics()
        ios_get_player_intrinsics(&cIntrinsics)

        var swift = SwiftPlayerIntrinsics()

        // Resistances
        swift.fireResistance = cIntrinsics.fire_resistance
        swift.coldResistance = cIntrinsics.cold_resistance
        swift.sleepResistance = cIntrinsics.sleep_resistance
        swift.disintegrationResistance = cIntrinsics.disintegration_resistance
        swift.shockResistance = cIntrinsics.shock_resistance
        swift.poisonResistance = cIntrinsics.poison_resistance
        swift.drainResistance = cIntrinsics.drain_resistance
        swift.magicResistance = cIntrinsics.magic_resistance
        swift.acidResistance = cIntrinsics.acid_resistance
        swift.stoneResistance = cIntrinsics.stone_resistance
        swift.sickResistance = cIntrinsics.sick_resistance

        // Vision
        swift.seeInvisible = cIntrinsics.see_invisible
        swift.telepathy = cIntrinsics.telepathy
        swift.infravision = cIntrinsics.infravision
        swift.warning = cIntrinsics.warning
        swift.searching = cIntrinsics.searching

        // Movement
        swift.levitation = cIntrinsics.levitation
        swift.flying = cIntrinsics.flying
        swift.swimming = cIntrinsics.swimming
        swift.magicalBreathing = cIntrinsics.magical_breathing
        swift.passesWalls = cIntrinsics.passes_walls
        swift.slowDigestion = cIntrinsics.slow_digestion
        swift.regeneration = cIntrinsics.regeneration
        swift.teleportation = cIntrinsics.teleportation
        swift.teleportControl = cIntrinsics.teleport_control
        swift.polymorph = cIntrinsics.polymorph
        swift.polymorphControl = cIntrinsics.polymorph_control

        // Combat
        swift.stealth = cIntrinsics.stealth
        swift.aggravateMonster = cIntrinsics.aggravate_monster
        swift.conflict = cIntrinsics.conflict
        swift.protection = cIntrinsics.protection
        swift.reflection = cIntrinsics.reflection
        swift.freeAction = cIntrinsics.free_action

        // Conditions
        swift.hallucinating = cIntrinsics.hallucinating
        swift.confused = cIntrinsics.confused
        swift.stunned = cIntrinsics.stunned
        swift.blinded = cIntrinsics.blinded
        swift.deaf = cIntrinsics.deaf
        swift.sick = cIntrinsics.sick
        swift.stoned = cIntrinsics.stoned
        swift.strangled = cIntrinsics.strangled
        swift.slimed = cIntrinsics.slimed
        swift.woundedLegs = cIntrinsics.wounded_legs
        swift.fumbling = cIntrinsics.fumbling

        return swift
    }

    /// Get items for a category (only active ones, unless showAll)
    func items(for category: IntrinsicCategory, showAll: Bool = false) -> [IntrinsicItem] {
        let allItems: [IntrinsicItem]

        switch category {
        case .resistances:
            allItems = [
                IntrinsicItem(name: "Fire", icon: "flame.fill", color: .red, isActive: fireResistance),
                IntrinsicItem(name: "Cold", icon: "snowflake", color: .cyan, isActive: coldResistance),
                IntrinsicItem(name: "Sleep", icon: "moon.zzz.fill", color: .indigo, isActive: sleepResistance),
                IntrinsicItem(name: "Disintegrate", icon: "atom", color: .purple, isActive: disintegrationResistance),
                IntrinsicItem(name: "Shock", icon: "bolt.fill", color: .yellow, isActive: shockResistance),
                IntrinsicItem(name: "Poison", icon: "drop.fill", color: .green, isActive: poisonResistance),
                IntrinsicItem(name: "Drain", icon: "heart.slash.fill", color: .gray, isActive: drainResistance),
                IntrinsicItem(name: "Magic", icon: "wand.and.stars", color: .blue, isActive: magicResistance),
                IntrinsicItem(name: "Acid", icon: "bubbles.and.sparkles.fill", color: .green, isActive: acidResistance),
                IntrinsicItem(name: "Stone", icon: "mountain.2.fill", color: .brown, isActive: stoneResistance),
                IntrinsicItem(name: "Sickness", icon: "cross.vial.fill", color: .mint, isActive: sickResistance),
            ]

        case .vision:
            allItems = [
                IntrinsicItem(name: "See Invisible", icon: "eye.trianglebadge.exclamationmark.fill", color: .purple, isActive: seeInvisible),
                IntrinsicItem(name: "Telepathy", icon: "brain.head.profile.fill", color: .pink, isActive: telepathy),
                IntrinsicItem(name: "Infravision", icon: "eye.fill", color: .red, isActive: infravision),
                IntrinsicItem(name: "Warning", icon: "exclamationmark.shield.fill", color: .orange, isActive: warning),
                IntrinsicItem(name: "Searching", icon: "magnifyingglass", color: .blue, isActive: searching),
            ]

        case .movement:
            allItems = [
                IntrinsicItem(name: "Levitation", icon: "arrow.up.circle.fill", color: .cyan, isActive: levitation),
                IntrinsicItem(name: "Flying", icon: "wind", color: .blue, isActive: flying),
                IntrinsicItem(name: "Swimming", icon: "drop.triangle.fill", color: .blue, isActive: swimming),
                IntrinsicItem(name: "Water Breathing", icon: "lungs.fill", color: .teal, isActive: magicalBreathing),
                IntrinsicItem(name: "Phasing", icon: "square.on.square.dashed", color: .purple, isActive: passesWalls),
                IntrinsicItem(name: "Slow Digestion", icon: "tortoise.fill", color: .green, isActive: slowDigestion),
                IntrinsicItem(name: "Regeneration", icon: "heart.circle.fill", color: .red, isActive: regeneration),
                IntrinsicItem(name: "Teleportation", icon: "sparkles", color: .purple, isActive: teleportation),
                IntrinsicItem(name: "Teleport Control", icon: "location.fill", color: .blue, isActive: teleportControl),
                IntrinsicItem(name: "Polymorph", icon: "person.2.wave.2.fill", color: .orange, isActive: polymorph),
                IntrinsicItem(name: "Polymorph Control", icon: "person.badge.key.fill", color: .green, isActive: polymorphControl),
            ]

        case .combat:
            allItems = [
                IntrinsicItem(name: "Stealth", icon: "eye.slash.fill", color: .gray, isActive: stealth),
                IntrinsicItem(name: "Aggravate", icon: "speaker.wave.3.fill", color: .red, isActive: aggravateMonster, isNegative: true),
                IntrinsicItem(name: "Conflict", icon: "person.2.slash.fill", color: .orange, isActive: conflict),
                IntrinsicItem(name: "Protection", icon: "shield.fill", color: .blue, isActive: protection),
                IntrinsicItem(name: "Reflection", icon: "arrow.triangle.2.circlepath", color: .cyan, isActive: reflection),
                IntrinsicItem(name: "Free Action", icon: "figure.walk.motion", color: .green, isActive: freeAction),
            ]

        case .conditions:
            allItems = [
                IntrinsicItem(name: "Hallucinating", icon: "eye.trianglebadge.exclamationmark", color: .purple, isActive: hallucinating, isNegative: true),
                IntrinsicItem(name: "Confused", icon: "questionmark.circle.fill", color: .yellow, isActive: confused, isNegative: true),
                IntrinsicItem(name: "Stunned", icon: "star.circle.fill", color: .orange, isActive: stunned, isNegative: true),
                IntrinsicItem(name: "Blinded", icon: "eye.slash.fill", color: .gray, isActive: blinded, isNegative: true),
                IntrinsicItem(name: "Deaf", icon: "ear.trianglebadge.exclamationmark", color: .gray, isActive: deaf, isNegative: true),
                IntrinsicItem(name: "Sick", icon: "facemask.fill", color: .green, isActive: sick, isNegative: true),
                IntrinsicItem(name: "Stoning", icon: "mountain.2.fill", color: .brown, isActive: stoned, isNegative: true),
                IntrinsicItem(name: "Strangled", icon: "hand.raised.slash.fill", color: .red, isActive: strangled, isNegative: true),
                IntrinsicItem(name: "Slimed", icon: "drop.fill", color: .green, isActive: slimed, isNegative: true),
                IntrinsicItem(name: "Wounded Legs", icon: "figure.stand", color: .red, isActive: woundedLegs, isNegative: true),
                IntrinsicItem(name: "Fumbling", icon: "hand.thumbsdown.fill", color: .yellow, isActive: fumbling, isNegative: true),
            ]
        }

        return showAll ? allItems : allItems.filter { $0.isActive }
    }

    /// Check if any intrinsics are active in a category
    func hasActiveIntrinsics(in category: IntrinsicCategory) -> Bool {
        !items(for: category).isEmpty
    }
}

// MARK: - Intrinsics View

/// Premium intrinsics/abilities display for the Hero Panel
struct IntrinsicsView: View {
    let isCompact: Bool

    @State private var intrinsics = SwiftPlayerIntrinsics()
    @State private var showAllAbilities = false
    @State private var isTogglePressed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with toggle
            headerView

            Divider()
                .background(Color.white.opacity(0.15))

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Show categories that have active intrinsics (or all if toggled)
                    ForEach(IntrinsicCategory.allCases, id: \.rawValue) { category in
                        let items = intrinsics.items(for: category, showAll: showAllAbilities)
                        if !items.isEmpty || showAllAbilities {
                            categorySection(category, items: items)
                        }
                    }

                    // Empty state if nothing active
                    if !hasAnyActiveIntrinsics && !showAllAbilities {
                        emptyStateView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            refreshIntrinsics()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Abilities")
                .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            // Toggle for showing all abilities
            Button(action: {
                HapticManager.shared.tap()
                withAnimation(reduceMotion ? nil : AnimationConstants.categorySelection) {
                    showAllAbilities.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: showAllAbilities ? "eye.fill" : "eye.slash")
                        .font(.system(size: isCompact ? 10 : 12))
                        .contentTransition(.symbolEffect(.replace))
                    Text(showAllAbilities ? "All" : "Active")
                        .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                }
                .foregroundColor(showAllAbilities ? .purple : .white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(showAllAbilities ? Color.purple.opacity(0.3) : Color.white.opacity(0.1))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    showAllAbilities ? Color.purple.opacity(0.4) : Color.white.opacity(0.1),
                                    lineWidth: 0.5
                                )
                        )
                )
                .scaleEffect(isTogglePressed ? AnimationConstants.pressScale : 1.0)
                .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isTogglePressed)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 70, minHeight: 44)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isTogglePressed = true }
                    .onEnded { _ in isTogglePressed = false }
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(_ category: IntrinsicCategory, items: [IntrinsicItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: isCompact ? 11 : 13))
                    .foregroundColor(category.color)

                Text(category.rawValue)
                    .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Active count with smooth number animation
                let activeCount = items.filter { $0.isActive }.count
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                        .foregroundColor(category.color)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : AnimationConstants.statusUpdate, value: activeCount)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(category.color.opacity(0.2))
                        )
                }
            }

            // Items grid
            if items.isEmpty {
                Text("None active")
                    .font(.system(size: isCompact ? 11 : 12))
                    .foregroundColor(.white.opacity(0.3))
                    .italic()
                    .padding(.vertical, 8)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(items) { item in
                        intrinsicBadge(item)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Intrinsic Badge

    private func intrinsicBadge(_ item: IntrinsicItem) -> some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.system(size: isCompact ? 10 : 12))
                .foregroundColor(item.isActive ? item.color : .white.opacity(0.3))

            Text(item.name)
                .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                .foregroundColor(item.isActive ? .white.opacity(0.9) : .white.opacity(0.3))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(item.isActive
                    ? (item.isNegative ? Color.red.opacity(0.2) : item.color.opacity(0.2))
                    : Color.white.opacity(0.05))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            item.isActive
                                ? (item.isNegative ? Color.red.opacity(0.4) : item.color.opacity(0.3))
                                : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        )
        .opacity(item.isActive ? 1.0 : 0.5)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.2))

            Text("No special abilities yet")
                .font(.system(size: isCompact ? 13 : 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Text("Gain intrinsics from corpses, equipment, or leveling up")
                .font(.system(size: isCompact ? 10 : 11))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)

            Button(action: {
                HapticManager.shared.tap()
                showAllAbilities = true
            }) {
                Text("Show All Abilities")
                    .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.2))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .frame(minWidth: 140, minHeight: 44)  // Apple HIG: 44pt minimum
            .contentShape(Rectangle())  // SWIFTUI-M-003: Full hit area
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private var hasAnyActiveIntrinsics: Bool {
        IntrinsicCategory.allCases.contains { intrinsics.hasActiveIntrinsics(in: $0) }
    }

    private func refreshIntrinsics() {
        intrinsics = SwiftPlayerIntrinsics.load()
    }
}

// MARK: - Preview

#if DEBUG
struct IntrinsicsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            IntrinsicsView(isCompact: false)
                .frame(width: 350)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
        }
        .preferredColorScheme(.dark)
    }
}
#endif
