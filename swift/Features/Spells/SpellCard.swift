import SwiftUI

// MARK: - Spell Card
/// Touch-friendly card for selecting a spell
/// Shows spell name, level, power cost, success rate, and retention
struct SpellCard: View {
    let spell: NetHackSpell
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var animation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)
    }

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onTap()
        }) {
            VStack(spacing: 6) {
                // Skill Type Icon
                Image(systemName: spell.skillType.icon)
                    .font(.system(size: 28))
                    .foregroundColor(spell.skillType.color)

                // Spell Letter Badge
                Text(String(spell.letter))
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(spell.skillType.color))

                // Spell Name
                Text(spell.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                // Level and Power Cost
                HStack(spacing: 4) {
                    Text("Lv.\(spell.level)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("\(spell.powerCost)Pw")
                        .font(.caption2.bold())
                        .foregroundColor(.blue)
                }

                // Success Rate
                HStack(spacing: 2) {
                    Image(systemName: "target")
                        .font(.system(size: 8))
                    Text("\(spell.successRate)%")
                        .font(.caption2.bold())
                }
                .foregroundColor(spell.successColor)

                // Retention Bar
                retentionBar
            }
            .frame(width: 100, height: 140)
            .background(cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(spell.skillType.color.opacity(0.4), lineWidth: 1.5)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(animation, value: isPressed)
        }
        .buttonStyle(.plain)
        .pressEvents { pressed in
            isPressed = pressed
        }
        .opacity(spell.isCastable ? 1.0 : 0.5)
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        ZStack {
            // Base material
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)

            // Subtle gradient based on skill type
            LinearGradient(
                colors: [
                    spell.skillType.color.opacity(0.1),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Retention Bar

    private var retentionBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { segment in
                RoundedRectangle(cornerRadius: 2)
                    .fill(segment < spell.retentionSegments
                          ? spell.retentionLevel.color
                          : Color.gray.opacity(0.3))
                    .frame(width: 14, height: 4)
            }
        }
    }
}

// MARK: - Compact Spell Card (for ActionBar)
/// Smaller spell card for use in action bar slots
struct CompactSpellCard: View {
    let spell: NetHackSpell
    let size: CGFloat

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 8)
                .fill(spell.skillType.color.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(spell.skillType.color.opacity(0.5), lineWidth: 1)
                )

            VStack(spacing: 2) {
                // Icon
                Image(systemName: spell.skillType.icon)
                    .font(.system(size: size * 0.35))
                    .foregroundColor(spell.skillType.color)

                // Letter
                Text(String(spell.letter))
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundColor(.primary)
            }

            // Power Badge (top-right)
            VStack {
                HStack {
                    Spacer()
                    Text("\(spell.powerCost)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.blue))
                }
                Spacer()
            }
            .padding(2)

            // Retention Indicator (bottom)
            if spell.isLowRetention {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Circle()
                            .fill(spell.retentionLevel.color)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(3)
            }
        }
        .frame(width: size, height: size)
        .opacity(spell.isCastable ? 1.0 : 0.5)
    }
}

// MARK: - Preview

#if DEBUG
struct SpellCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            HStack {
                ForEach(NetHackSpell.sampleSpells.prefix(3), id: \.id) { spell in
                    SpellCard(spell: spell) {
                        print("Cast \(spell.name)")
                    }
                }
            }

            Divider()

            HStack {
                ForEach(NetHackSpell.sampleSpells.prefix(4), id: \.id) { spell in
                    CompactSpellCard(spell: spell, size: 50)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
#endif
