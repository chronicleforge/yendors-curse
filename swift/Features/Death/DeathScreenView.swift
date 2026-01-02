//
//  DeathScreenView.swift
//  nethack
//
//  Death screen showing final statistics and information
//  Two-column landscape layout with glass-morphic design
//
//  Redesigned: 2025-12-18
//

import SwiftUI

struct DeathScreenView: View {
    @Environment(DeathFlowController.self) private var deathFlow
    @Environment(NetHackGameManager.self) private var gameManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingDetails = false
    @State private var selectedDetailTab = 0

    // Staggered entrance animation states
    @State private var showSkull = false
    @State private var showTitle = false
    @State private var showMessage = false
    @State private var showScoreCard = false
    @State private var showStatsCard = false
    @State private var showHighlights = false
    @State private var showButtons = false

    /// Death info from controller (with fallback)
    private var deathInfo: DeathInfo {
        deathFlow.deathInfo ?? DeathInfo()
    }

    private var itemCount: Int {
        let text = deathInfo.possessions
        guard !text.isEmpty else { return 0 }
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    private var conductCount: Int {
        let text = deathInfo.conduct
        guard !text.isEmpty else { return 0 }
        let lines = text.components(separatedBy: "\n")
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.contains("broke") && !trimmed.contains("violated")
        }.count
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 700

            ZStack {
                // Dark gradient background - changes based on game end type
                LinearGradient(
                    colors: deathFlow.gameEndType.backgroundGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if isCompact {
                    // Compact layout (smaller iPads, large phones)
                    compactLayout(geometry: geometry)
                } else {
                    // Full two-column landscape layout
                    twoColumnLayout(geometry: geometry)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingDetails) {
            detailsSheet
        }
        .onAppear {
            triggerEntranceAnimations()
        }
    }

    // MARK: - Two-Column Layout (Landscape)

    private func twoColumnLayout(geometry: GeometryProxy) -> some View {
        // Calculate available width after safe areas
        let leftInset = max(geometry.safeAreaInsets.leading, 24)
        let rightInset = max(geometry.safeAreaInsets.trailing, 24)
        let availableWidth = geometry.size.width - leftInset - rightInset

        return HStack(spacing: 16) {
            // LEFT COLUMN: Hero + Actions (38%)
            VStack(spacing: 0) {
                Spacer()
                heroSection(isCompact: false)
                Spacer()
                actionButtons(isCompact: false)
            }
            .frame(width: availableWidth * 0.38)
            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))

            // RIGHT COLUMN: Stats Grid (62%)
            VStack(spacing: 16) {
                Spacer()

                // Top row: Score + Stats side by side - EQUAL HEIGHT
                HStack(alignment: .top, spacing: 16) {
                    scoreCard(isCompact: false)
                        .frame(maxHeight: .infinity)
                    statsCard(isCompact: false)
                        .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Bottom: Highlights
                highlightsCard(isCompact: false)

                Spacer()
            }
            .frame(width: availableWidth * 0.62)
            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
        }
        .padding(.leading, leftInset)
        .padding(.trailing, rightInset)
        .padding(.top, max(geometry.safeAreaInsets.top, 16))
    }

    // MARK: - Compact Layout (Smaller screens)

    private func compactLayout(geometry: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection(isCompact: true)

                HStack(alignment: .top, spacing: 12) {
                    scoreCard(isCompact: true)
                    statsCard(isCompact: true)
                }
                .fixedSize(horizontal: false, vertical: true)

                highlightsCard(isCompact: true)

                actionButtons(isCompact: true)
            }
            .padding(.horizontal, max(geometry.safeAreaInsets.leading, 20))
            .padding(.top, max(geometry.safeAreaInsets.top, 24))
            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 24))
        }
    }

    // MARK: - Entrance Animation

    private func triggerEntranceAnimations() {
        guard !reduceMotion else {
            showSkull = true
            showTitle = true
            showMessage = true
            showScoreCard = true
            showStatsCard = true
            showHighlights = true
            showButtons = true
            return
        }

        // Faster staggered timeline using AnimationConstants
        withAnimation(AnimationConstants.deathSkullEntrance.delay(AnimationConstants.deathSkullDelay)) {
            showSkull = true
        }

        withAnimation(AnimationConstants.deathTitleEntrance.delay(AnimationConstants.deathTitleDelay)) {
            showTitle = true
        }

        withAnimation(AnimationConstants.deathMessageEntrance.delay(AnimationConstants.deathMessageDelay)) {
            showMessage = true
        }

        withAnimation(AnimationConstants.deathScoreCardEntrance.delay(AnimationConstants.deathScoreCardDelay)) {
            showScoreCard = true
        }

        withAnimation(AnimationConstants.deathStatEntrance.delay(AnimationConstants.deathStatsBaseDelay)) {
            showStatsCard = true
        }

        withAnimation(AnimationConstants.deathStatEntrance.delay(AnimationConstants.deathStatsBaseDelay + AnimationConstants.deathStatsStagger)) {
            showHighlights = true
        }

        withAnimation(AnimationConstants.deathButtonsEntrance.delay(AnimationConstants.deathButtonsDelay)) {
            showButtons = true
        }
    }

    // MARK: - Hero Section (Left Column)

    private func heroSection(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 16) {
            // Icon changes based on game end type (skull for death, crown for victory)
            Image(systemName: deathFlow.gameEndType.iconName)
                .font(.system(size: isCompact ? 28 : 40))
                .foregroundStyle(deathFlow.gameEndType.accentColor.opacity(0.8))
                .scaleEffect(showSkull ? 1.0 : AnimationConstants.deathSkullInitialScale)
                .opacity(showSkull ? 1.0 : 0)

            // Subtitle changes based on game end type
            Text(deathFlow.gameEndType.subtitle)
                .font(.system(size: isCompact ? 20 : 28, weight: .medium, design: .serif))
                .foregroundColor(.white.opacity(0.9))
                .scaleEffect(showTitle ? 1.0 : AnimationConstants.deathTitleInitialScale)
                .opacity(showTitle ? 1.0 : 0)

            // Character name prominent - e.g. "Zoru the Barbarian"
            if !deathInfo.roleName.isEmpty {
                Text(deathInfo.roleName)
                    .font(.system(size: isCompact ? 18 : 24, weight: .bold))
                    .foregroundColor(.yellow)
                    .scaleEffect(showTitle ? 1.0 : 0.9)
                    .opacity(showTitle ? 1.0 : 0)
            }

            // Death message
            deathMessageView(isCompact: isCompact)
        }
    }

    private func deathMessageView(isCompact: Bool) -> some View {
        VStack(spacing: 6) {
            // Death reason - compact
            if !deathInfo.deathMessage.isEmpty || !deathInfo.deathReason.isEmpty {
                let message = deathInfo.deathMessage.isEmpty ? deathInfo.deathReason : deathInfo.deathMessage

                Text(message)
                    .font(.system(size: isCompact ? 13 : 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            // Location
            Text("Dlvl:\(deathInfo.dungeonLevel)")
                .font(.system(size: isCompact ? 11 : 13))
                .foregroundColor(.white.opacity(0.4))
        }
        .offset(y: showMessage ? 0 : AnimationConstants.deathMessageSlideDistance)
        .opacity(showMessage ? 1.0 : 0)
    }

    // MARK: - Score Card

    private func scoreCard(isCompact: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Text("FINAL SCORE")
                    .font(.system(size: isCompact ? 10 : 12, weight: .bold))
                    .foregroundColor(.yellow.opacity(0.7))
                    .tracking(2)

                Text("\(deathInfo.finalScore)")
                    .font(.system(size: isCompact ? 36 : 48, weight: .black, design: .rounded))
                    .foregroundColor(.yellow)
                    .contentTransition(.numericText())

                Text("points")
                    .font(.system(size: isCompact ? 10 : 12))
                    .foregroundColor(.yellow.opacity(0.5))

                Divider()
                    .background(Color.white.opacity(0.2))

                Text("\(deathInfo.finalTurns) turns")
                    .font(.system(size: isCompact ? 12 : 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? 16 : 20)
        .frame(maxWidth: .infinity)
        .background(glassCard(accentColor: .yellow))
        .offset(x: showScoreCard ? 0 : AnimationConstants.deathScoreCardSlideDistance)
        .opacity(showScoreCard ? 1.0 : 0)
    }

    // MARK: - Stats Card (NEW - shows HP, Gold, Level, Dlvl)

    private func statsCard(isCompact: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: isCompact ? 12 : 14))
                    Text("Final Stats")
                        .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: isCompact ? 8 : 12) {
                    DeathStatRow(icon: "heart.slash.fill", label: "HP", value: "\(deathInfo.finalHp)/\(deathInfo.finalMaxHp)", color: .red, isCompact: isCompact)
                    DeathStatRow(icon: "dollarsign.circle.fill", label: "Gold", value: "\(deathInfo.finalGold)", color: .yellow, isCompact: isCompact)
                    DeathStatRow(icon: "arrow.up.circle.fill", label: "Level", value: "\(deathInfo.finalLevel)", color: .green, isCompact: isCompact)
                    DeathStatRow(icon: "map.fill", label: "Dlvl", value: "\(deathInfo.dungeonLevel)", color: .purple, isCompact: isCompact)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? 16 : 20)
        .frame(maxWidth: .infinity)
        .background(glassCard(accentColor: .cyan))
        .scaleEffect(showStatsCard ? 1.0 : AnimationConstants.deathStatInitialScale)
        .opacity(showStatsCard ? 1.0 : 0)
    }

    // MARK: - Highlights Card (Conduct, Items, Kills)

    private func highlightsCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: isCompact ? 12 : 14))
                Text("Highlights")
                    .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()

                // Quick link to details
                Button(action: { showingDetails = true }) {
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.system(size: isCompact ? 11 : 12))
                        Image(systemName: "chevron.right")
                            .font(.system(size: isCompact ? 9 : 10))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            HStack(spacing: isCompact ? 8 : 12) {
                HighlightPill(icon: "bag.fill", value: "\(itemCount)", label: "Items", color: .blue, isCompact: isCompact)
                HighlightPill(icon: "medal.fill", value: "\(conductCount)", label: "Conduct", color: .green, isCompact: isCompact)

                if conductCount > 0 {
                    // Show conduct badge if any kept
                    Text("kept")
                        .font(.system(size: isCompact ? 10 : 11))
                        .foregroundColor(.green.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.15))
                        )
                }
            }
        }
        .padding(isCompact ? 16 : 20)
        .frame(maxWidth: .infinity)
        .background(glassCard(accentColor: .orange))
        .scaleEffect(showHighlights ? 1.0 : AnimationConstants.deathStatInitialScale)
        .opacity(showHighlights ? 1.0 : 0)
    }

    // MARK: - Action Buttons

    private func actionButtons(isCompact: Bool) -> some View {
        VStack(spacing: 12) {
            // PRIMARY: Play Again
            Button(action: startNewGame) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Play Again")
                }
                .font(.system(size: isCompact ? 16 : 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isCompact ? 14 : 18)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .green.opacity(0.4), radius: 8, y: 4)
                )
            }

            // Secondary row: View Details + Return to Menu
            HStack(spacing: 12) {
                Button(action: { showingDetails = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Details")
                    }
                    .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, isCompact ? 10 : 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                }

                Button(action: returnToMenu) {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                            .font(.system(size: isCompact ? 11 : 12))
                        Text("Menu")
                    }
                    .font(.system(size: isCompact ? 13 : 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .opacity(showButtons ? 1.0 : 0)
    }

    // MARK: - Glass Card Background

    private func glassCard(accentColor: Color, cornerRadius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.4),
                                Color.white.opacity(0.15),
                                accentColor.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
    }

    // MARK: - Details Sheet

    private var detailsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Category", selection: $selectedDetailTab) {
                    Text("Items").tag(0)
                    Text("Attributes").tag(1)
                    Text("Conduct").tag(2)
                    Text("Dungeon").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedDetailTab {
                        case 0:
                            detailSection(title: "Possessions", content: deathInfo.possessions)
                        case 1:
                            detailSection(title: "Attributes", content: deathInfo.attributes)
                        case 2:
                            detailSection(title: "Conduct", content: deathInfo.conduct)
                        case 3:
                            detailSection(title: "Dungeon Overview", content: deathInfo.dungeonOverview)
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingDetails = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func detailSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.yellow)

            if content.isEmpty {
                Text("No \(title.lowercased()) recorded")
                    .foregroundColor(.gray)
                    .italic()
            } else {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Actions

    private func startNewGame() {
        print("[Death] Starting new game...")
        deathFlow.playAgain()
        gameManager.startGame()
    }

    private func returnToMenu() {
        print("[Death] Returning to main menu...")
        deathFlow.returnToMenu()
    }
}

// MARK: - Helper Views

private struct DeathStatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: isCompact ? 12 : 14))
                .foregroundColor(color.opacity(0.8))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: isCompact ? 9 : 10))
                    .foregroundColor(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()
        }
    }
}

private struct HighlightPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: isCompact ? 12 : 14))
                .foregroundColor(color.opacity(0.8))

            Text(value)
                .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: isCompact ? 10 : 11))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, isCompact ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// Swift representation of DeathInfo - populated from C death info
struct DeathInfo {
    let deathMessage: String
    let possessions: String
    let attributes: String
    let conduct: String
    let dungeonOverview: String
    let finalLevel: Int
    let finalHp: Int
    let finalMaxHp: Int
    let finalGold: Int
    let finalScore: Int
    let finalTurns: Int
    let dungeonLevel: Int
    let roleName: String
    let deathReason: String

    init() {
        self.deathMessage = ""
        self.possessions = ""
        self.attributes = ""
        self.conduct = ""
        self.dungeonOverview = ""
        self.finalLevel = 0
        self.finalHp = 0
        self.finalMaxHp = 0
        self.finalGold = 0
        self.finalScore = 0
        self.finalTurns = 0
        self.dungeonLevel = 0
        self.roleName = ""
        self.deathReason = ""
    }

    /// Initialize from C death info - call this when player dies
    /// Uses accessor functions ONLY to avoid any C struct access issues
    static func fromCDeathInfo() -> DeathInfo {
        func safeString(_ ptr: UnsafePointer<CChar>?) -> String {
            guard let ptr = ptr else { return "" }
            return String(cString: ptr)
        }

        return DeathInfo(
            deathMessage: safeString(nethack_get_death_message()),
            possessions: safeString(nethack_get_death_possessions()),
            attributes: safeString(nethack_get_death_attributes()),
            conduct: safeString(nethack_get_death_conduct()),
            dungeonOverview: safeString(nethack_get_death_dungeon_overview()),
            finalLevel: Int(nethack_get_death_final_level()),
            finalHp: Int(nethack_get_death_final_hp()),
            finalMaxHp: Int(nethack_get_death_final_maxhp()),
            finalGold: Int(nethack_get_death_final_gold()),
            finalScore: Int(nethack_get_death_final_score()),
            finalTurns: Int(nethack_get_death_final_turns()),
            dungeonLevel: Int(nethack_get_death_dungeon_level()),
            roleName: safeString(nethack_get_death_role_name()),
            deathReason: safeString(nethack_get_death_reason())
        )
    }

    init(deathMessage: String, possessions: String, attributes: String,
         conduct: String, dungeonOverview: String, finalLevel: Int,
         finalHp: Int, finalMaxHp: Int, finalGold: Int, finalScore: Int,
         finalTurns: Int, dungeonLevel: Int, roleName: String, deathReason: String) {
        self.deathMessage = deathMessage
        self.possessions = possessions
        self.attributes = attributes
        self.conduct = conduct
        self.dungeonOverview = dungeonOverview
        self.finalLevel = finalLevel
        self.finalHp = finalHp
        self.finalMaxHp = finalMaxHp
        self.finalGold = finalGold
        self.finalScore = finalScore
        self.finalTurns = finalTurns
        self.dungeonLevel = dungeonLevel
        self.roleName = roleName
        self.deathReason = deathReason
    }
}
