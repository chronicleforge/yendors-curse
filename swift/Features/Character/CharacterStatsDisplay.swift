import SwiftUI

struct CharacterStatsDisplay: View {
    let selectedRole: Int
    let selectedRace: Int?
    let selectedAlignment: Int?
    let gameManager: NetHackGameManager

    @State private var animateStats = false
    @State private var abilities: [String] = []

    // Base stats for each role (simplified)
    private let roleStats: [[String: Int]] = [
        // Archeologist
        ["STR": 12, "DEX": 10, "CON": 12, "INT": 16, "WIS": 14, "CHA": 12],
        // Barbarian
        ["STR": 18, "DEX": 12, "CON": 18, "INT": 7, "WIS": 8, "CHA": 8],
        // Caveman
        ["STR": 18, "DEX": 12, "CON": 16, "INT": 7, "WIS": 8, "CHA": 8],
        // Healer
        ["STR": 10, "DEX": 10, "CON": 12, "INT": 14, "WIS": 16, "CHA": 14],
        // Knight
        ["STR": 16, "DEX": 10, "CON": 14, "INT": 10, "WIS": 14, "CHA": 14],
        // Monk
        ["STR": 14, "DEX": 16, "CON": 14, "INT": 10, "WIS": 14, "CHA": 10],
        // Priest
        ["STR": 12, "DEX": 10, "CON": 12, "INT": 12, "WIS": 18, "CHA": 14],
        // Ranger
        ["STR": 14, "DEX": 14, "CON": 14, "INT": 12, "WIS": 14, "CHA": 10],
        // Rogue
        ["STR": 12, "DEX": 18, "CON": 12, "INT": 12, "WIS": 10, "CHA": 10],
        // Samurai
        ["STR": 16, "DEX": 14, "CON": 16, "INT": 10, "WIS": 10, "CHA": 10],
        // Tourist
        ["STR": 10, "DEX": 12, "CON": 10, "INT": 14, "WIS": 10, "CHA": 16],
        // Valkyrie
        ["STR": 18, "DEX": 12, "CON": 16, "INT": 10, "WIS": 10, "CHA": 10],
        // Wizard
        ["STR": 10, "DEX": 12, "CON": 10, "INT": 18, "WIS": 14, "CHA": 12]
    ]

    private let roleAbilities: [String: [String]] = [
        "Archeologist": ["Detect Hidden", "Artifact Knowledge", "Careful Study"],
        "Barbarian": ["Rage", "Tough Skin", "Weapon Mastery"],
        "Caveman": ["Stone Throw", "Animal Friend", "Primitive Craft"],
        "Healer": ["Cure Disease", "Extra Healing", "Blessed Touch"],
        "Knight": ["Mounted Combat", "Code of Honor", "Shield Bash"],
        "Monk": ["Martial Arts", "Speed Burst", "Mind over Body"],
        "Priest": ["Turn Undead", "Divine Protection", "Blessing"],
        "Ranger": ["Track", "Stealth", "Bow Expertise"],
        "Rogue": ["Backstab", "Pick Lock", "Hide in Shadows"],
        "Samurai": ["Two Weapons", "Discipline", "Honor Code"],
        "Tourist": ["Lucky", "Credit Card", "Photography"],
        "Valkyrie": ["Cold Resistance", "Speed", "Berserk"],
        "Wizard": ["Spell Memory", "Magic Resistance", "Identify"]
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Stats Grid
            VStack(alignment: .leading, spacing: 12) {
                Text("ATTRIBUTES")
                    .font(.headline)
                    .foregroundColor(.green)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(getStats().sorted(by: { $0.key < $1.key }), id: \.key) { stat, value in
                        StatBar(
                            label: stat,
                            value: value,
                            maxValue: 20,
                            color: getStatColor(for: stat, value: value),
                            animate: animateStats
                        )
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )

            // Special Abilities
            VStack(alignment: .leading, spacing: 12) {
                Text("SPECIAL ABILITIES")
                    .font(.headline)
                    .foregroundColor(.green)

                ForEach(abilities, id: \.self) { ability in
                    HStack {
                        Image(systemName: "sparkle")
                            .foregroundColor(.yellow)
                            .scaleEffect(animateStats ? 1.2 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                value: animateStats
                            )

                        Text(ability)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )

            // Race & Alignment Modifiers
            if selectedRace != nil || selectedAlignment != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MODIFIERS")
                        .font(.headline)
                        .foregroundColor(.green)

                    if let race = selectedRace {
                        HStack {
                            Text("Race Bonus:")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(getRaceBonus(race))
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                    }

                    if let alignment = selectedAlignment {
                        HStack {
                            Text("Alignment:")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(getAlignmentEffect(alignment))
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                animateStats = true
            }
            Task {
                abilities = await getAbilities() ?? []
            }
        }
        .onChange(of: selectedRole) { _ in
            animateStats = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    animateStats = true
                }
            }
            Task {
                abilities = await getAbilities() ?? []
            }
        }
    }

    private func getStats() -> [String: Int] {
        guard selectedRole < roleStats.count else {
            return ["STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10]
        }
        return roleStats[selectedRole]
    }

    private func getAbilities() async -> [String]? {
        let roleName = await gameManager.getRoleName(selectedRole)
        return roleAbilities[roleName]
    }

    private func getStatColor(for stat: String, value: Int) -> Color {
        if value >= 16 {
            return .green
        } else if value >= 12 {
            return .yellow
        } else {
            return .red
        }
    }

    private func getRaceBonus(_ race: Int) -> String {
        switch race {
        case 0: return "+1 Versatility"      // Human
        case 1: return "+1 DEX, Magic Affinity"  // Elf
        case 2: return "+2 CON, -1 CHA"      // Dwarf
        case 3: return "+1 INT, Small Size"   // Gnome
        case 4: return "+2 STR, -2 CHA"      // Orc
        default: return "None"
        }
    }

    private func getAlignmentEffect(_ alignment: Int) -> String {
        switch alignment {
        case 0: return "Artifact compatibility"   // Lawful
        case 1: return "Balanced approach"        // Neutral
        case 2: return "Sacrifice bonuses"        // Chaotic
        default: return "None"
        }
    }
}

struct StatBar: View {
    let label: String
    let value: Int
    let maxValue: Int
    let color: Color
    let animate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                Text("\(value)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    // Filled bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: animate ? geometry.size.width * (CGFloat(value) / CGFloat(maxValue)) : 0,
                            height: 6
                        )
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animate)
                }
            }
            .frame(height: 6)
        }
    }
}