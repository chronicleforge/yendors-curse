import SwiftUI

// MARK: - Spell Selection Sheet
/// SwiftUI sheet for selecting spells to cast
/// Displays known spells in a grid with filtering by skill type
struct SpellSelectionSheet: View {
    let spells: [NetHackSpell]
    let onSelect: (NetHackSpell) -> Void
    let onCancel: () -> Void

    @State private var selectedSkillType: SpellSkillType? = nil
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Filtered spells based on selected skill type
    var filteredSpells: [NetHackSpell] {
        guard let skillType = selectedSkillType else {
            return spells
        }
        return spells.filter { $0.skillType == skillType }
    }

    // Available skill types in current spell list
    var availableSkillTypes: [SpellSkillType] {
        Array(Set(spells.map { $0.skillType })).sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            filterBar

            if spells.isEmpty {
                emptyStateView
            } else if filteredSpells.isEmpty {
                noMatchingSpellsView
            } else {
                spellsGridView
            }

            bottomBar
        }
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 20)
        .transition(
            reduceMotion
                ? .opacity
                : .move(edge: .bottom).combined(with: .opacity)
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(.purple)

            Text("Cast which spell?")
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            // Power display
            if let power = getCurrentPower() {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.blue)
                    Text("\(power.current)/\(power.max)")
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                }
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All filter
                FilterChip(
                    title: "All",
                    icon: "sparkles",
                    color: .purple,
                    isSelected: selectedSkillType == nil
                ) {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedSkillType = nil
                    }
                }

                // Skill type filters
                ForEach(availableSkillTypes, id: \.self) { skillType in
                    FilterChip(
                        title: skillType.rawValue.capitalized,
                        icon: skillType.icon,
                        color: skillType.color,
                        isSelected: selectedSkillType == skillType
                    ) {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedSkillType = skillType
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }

    // MARK: - Spells Grid

    private var spellsGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 12)],
                spacing: 12
            ) {
                ForEach(filteredSpells, id: \.id) { spell in
                    SpellCard(spell: spell) {
                        onSelect(spell)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No spells known")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Read spellbooks to learn new spells.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noMatchingSpellsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No \(selectedSkillType?.rawValue ?? "") spells")
                .font(.headline)
                .foregroundColor(.secondary)

            Button("Show All") {
                withAnimation {
                    selectedSkillType = nil
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Spell count
            Text("\(filteredSpells.count) spell\(filteredSpells.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Helper

    private func getCurrentPower() -> (current: Int, max: Int)? {
        let current = Int(nethack_get_player_power())
        let max = Int(nethack_get_player_power_max())
        guard current >= 0 && max > 0 else { return nil }
        return (current, max)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.3) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color : Color.gray.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct SpellSelectionSheet_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()

                SpellSelectionSheet(
                    spells: NetHackSpell.sampleSpells,
                    onSelect: { spell in
                        print("Cast: \(spell.name)")
                    },
                    onCancel: {
                        print("Cancelled")
                    }
                )
                .frame(maxHeight: 500)
                .padding(.horizontal)

                Spacer()
            }
        }
    }
}
#endif
