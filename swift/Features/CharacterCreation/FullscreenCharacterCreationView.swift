import SwiftUI

/// Simplified Character Creation View
/// Uses VStack-based layout with extracted components
/// RESPONSIVE DESIGN: Works on ALL devices using ResponsiveLayout
struct FullscreenCharacterCreationView: View {
    var gameManager: NetHackGameManager
    @Binding var isPresented: Bool

    @State private var selectedClassIndex = 0
    @State private var characterName = ""
    @State private var selectedRaceIndex = 0
    @State private var selectedGenderIndex = 0
    @State private var selectedAlignmentIndex = 0
    @State private var showNameError = false
    @State private var nameErrorMessage = ""

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let classes: [ClassInfo] = ClassDataProvider.allClasses

    // Fantasy Names Lists
    private let maleNames = ["Abaet", "Aldren", "Aerden", "Aidan", "Albright", "Anumi", "Atlin", "Aysen", "Barkydle", "Bedic", "Beston", "Brighton", "Calden", "Cayold", "Cedric", "Chamon", "Connell", "Cordale", "Dakamon", "Darkboon", "Darko", "Darmor", "Defearon", "Derik", "Desil", "Dorn", "Drakoe", "Drandon", "Dritz", "Dryden", "Duran", "Eckard", "Efar", "Eli", "Elson", "Elthin", "Endor", "Erikarn", "Erim", "Escariet", "Ethen", "Etran", "Faowind", "Fearlock", "Fenrirr", "Firedorn", "Floran", "Fronar", "Fydar", "Gafolern", "Gai", "Galain", "Galiron", "Gametris", "Gemardt", "Gerirr", "Geth", "Gibolt", "Gothikar", "Gresforn", "Gryn", "Gundir", "Gustov", "Halmar", "Harrenhal", "Hasten", "Hectar", "Hecton", "Hildar", "Hyten", "Idon", "Ikar", "Illium", "Ironmark", "Isen", "Ithric", "Jackson", "Jalil", "Jamik", "Janus", "Jayco", "Jaython", "Jesco", "Jespar", "Jethil", "Jin", "Juktar", "Kafar", "Kaldar", "Kellan", "Keran", "Kesad", "Kethren", "Kilburn", "Kinorn", "Kirder", "Kyrad", "Laderic", "Lahorn", "Ledale", "Lerin", "Lesphares", "Lidorn", "Lin", "Loban", "Ludokrin", "Lurd", "Macon", "Mardin", "Markard", "Mashasen", "Mathar", "Medarin", "Merdon", "Merkesh", "Michael", "Mick", "Migorn", "Milo", "Mitar", "Modric", "Mudon", "Mylo", "Mythik", "Mythil", "Nadeer", "Nalfar", "Naphates", "Neowyld", "Nidale", "Nikpal", "Niro", "Nothar", "Nydale", "Nythil", "Okar", "Omarn", "Orin", "Ospar", "Othelen", "Palid", "Peitar", "Pelphides", "Pender", "Perder", "Perol", "Phairdon", "Phoenix", "Pictal", "Pildoor", "Ponith", "Poran", "Prothalon", "Puthor", "Pyder", "Qidan", "Quiad", "Quid", "Randar", "Raysdan", "Rayth", "Reaper", "Reth", "Rethik", "Rhithik", "Rhysling", "Riandur", "Rikar", "Rismak", "Ritic", "Rogeir", "Rogoth", "Rydan", "Ryfar", "Ryodan", "Rythen", "Sabal", "Sadareen", "Samon", "Scoth", "Scythe", "Secor", "Sedar", "Senick", "Serin", "Sermak", "Seryth", "Seth", "Setlo", "Shade", "Shadowbane", "Shane", "Shard", "Shardo", "Shillen", "Sildo", "Sithik", "Soderman", "Steven", "Suktor", "Suth", "Sythril", "Talberon", "Temil", "Tempist", "Tespar", "Tessino", "Tethran", "Tholan", "Tibers", "Tibolt", "Tilner", "Tithan", "Tobale", "Toma", "Tothale", "Towerlock", "Tuk", "Tusdar", "Tyden", "Ugmar", "Uhrd", "Undin", "Uther", "Vaccon", "Valkeri", "Valynard", "Vectomon", "Vespar", "Victor", "Vider", "Vigoth", "Vilan", "Vildar", "Vinald", "Vinkolt", "Virde", "Voltain", "Voudim", "Vythethi", "Walkar", "Wekmar", "Werymn", "Weshin", "William", "Willican", "Wiltmar", "Wishane", "Wrathran", "Wraythe", "Wuthmon", "Wyder", "Wyeth", "Wyvorn", "Xander", "Xavier", "Xenil", "Xithyl", "Xuio", "Yabaro", "Yepal", "Yesirn", "Yssik", "Yssith", "Zak", "Zakarn", "Zeke", "Zerin", "Zidar", "Zigmal", "Zile", "Zio", "Zoru", "Zotar", "Zutar", "Zyten"]

    private let femaleNames = ["Acele", "Ada", "Adorra", "Ahanna", "Akara", "Akassa", "Amaerilde", "Amara", "Amarisa", "Amarizi", "Ana", "Andonna", "Annalyn", "Ariannona", "Arina", "Arryn", "Asada", "Awnia", "Ayne", "Basete", "Bethe", "Brana", "Brianan", "Bridonna", "Brynhilde", "Calene", "Calina", "Celestine", "Celoa", "Chani", "Chrystyne", "Corda", "Cyelena", "Dalavesta", "Desini", "Dylena", "Ebatryne", "Efari", "Enaldie", "Enoka", "Enoona", "Errinaya", "Fayne", "Frederika", "Frida", "Gene", "Gessane", "Gronalyn", "Gwethana", "Halete", "Helenia", "Hildandi", "Hyza", "Idona", "Ikini", "Ilene", "Illia", "Iona", "Jessika", "Jezzine", "Justalyne", "Kassina", "Kilayox", "Kilia", "Kilyne", "Kressara", "Laela", "Laenaya", "Lelani", "Lenala", "Linyah", "Lloyanda", "Lolinda", "Lyna", "Lynessa", "Mehande", "Melisande", "Midiga", "Mirayam", "Mylene", "Nachaloa", "Naria", "Narisa", "Nelenna", "Niraya", "Nymira", "Ochala", "Olivia", "Onathe", "Ondola", "Orwyne", "Parthinia", "Pascheine", "Pela", "Periel", "Pharysene", "Philadona", "Prisane", "Prysala", "Pythe", "Qiara", "Qipala", "Quasee", "Rhyanon", "Rivatha", "Ryiah", "Sanala", "Sathe", "Senira", "Sennetta", "Sepherene", "Serane", "Sevestra", "Sidara", "Sidathe", "Sina", "Sunete", "Synestra", "Sythini", "Szene", "Tabika", "Tabithi", "Tajule", "Tamare", "Teresse", "Tolida", "Tonica", "Treka", "Tressa", "Trinsa", "Tryane", "Tybressa", "Tycane", "Tysinni", "Undaria", "Uneste", "Urda", "Usara", "Useli", "Ussesa", "Venessa", "Veseere", "Voladea", "Vysarane", "Vythica", "Wanera", "Welisarne", "Wellisa", "Wesolyne", "Wyeta", "Yilvoxe", "Ysane", "Yve", "Yviene", "Yvonnette", "Yysara", "Zana", "Zathe", "Zecele", "Zenobia", "Zephale", "Zephere", "Zerma", "Zestia", "Zilka", "Zoura", "Zrye", "Zyneste", "Zynoa"]

    // MARK: - Computed Properties

    private var selectedClass: ClassInfo {
        classes[selectedClassIndex]
    }

    private var canStartGame: Bool {
        !characterName.isEmpty
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let device = DeviceCategory.detect(for: geometry)
            let isCompact = device.isPhone && geometry.size.width > geometry.size.height
            let cardPadding: CGFloat = isCompact ? 16 : 24
            let spacing: CGFloat = isCompact ? 12 : 16

            ZStack {
                // Background
                backgroundLayer
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                // ONE UNIFIED CARD
                VStack(spacing: 0) {
                    // HEADER: Back | Name | Start
                    headerRow(geometry: geometry, isCompact: isCompact)
                        .padding(.bottom, spacing)

                    // Subtle divider
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                        .padding(.horizontal, -cardPadding)

                    // TWO COLUMNS: Tips left | Class+Picker right
                    HStack(alignment: .top, spacing: spacing * 1.5) {
                        // LEFT: Tips (static, no collapse)
                        tipsColumn(isCompact: isCompact)
                            .frame(width: isCompact ? 220 : 280)

                        // Vertical divider
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 1)

                        // RIGHT: Class selector + Pickers
                        VStack(spacing: spacing) {
                            classSection(geometry: geometry, isCompact: isCompact)
                            pickerSection(isCompact: isCompact)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, spacing)
                }
                .padding(cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                .frame(maxWidth: min(geometry.size.width - 40, 800))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)
            }
            .environment(\.deviceCategory, device)
        }
        .onChange(of: selectedClassIndex) { _, _ in
            selectedRaceIndex = 0
            selectedGenderIndex = 0
            selectedAlignmentIndex = 0
        }
        .alert("Invalid Name", isPresented: $showNameError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(nameErrorMessage)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Row

    @ViewBuilder
    private func headerRow(geometry: GeometryProxy, isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 12 : 16) {
            // Back button
            Button(action: { dismissView() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                    Text("Back")
                        .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                )
            }

            Spacer()

            // Name input
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .foregroundColor(.nethackAccent.opacity(0.7))
                    .font(.system(size: isCompact ? 12 : 14))

                TextField("Enter name...", text: $characterName)
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.white)
                    .frame(width: isCompact ? 100 : 140)

                Button(action: { generateRandomName() }) {
                    Image(systemName: "dice.fill")
                        .font(.system(size: isCompact ? 16 : 18))
                        .foregroundColor(.nethackAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )

            Spacer()

            // Start button
            Button(action: { startGame() }) {
                HStack(spacing: 6) {
                    Text("Start")
                        .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: isCompact ? 12 : 14, weight: .bold))
                }
                .foregroundColor(canStartGame ? .white : .white.opacity(0.4))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(canStartGame ? Color.nethackSuccess : Color.white.opacity(0.1))
                )
            }
            .disabled(!canStartGame)
        }
    }

    // MARK: - Tips Column (Left)

    @ViewBuilder
    private func tipsColumn(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.nethackAccent)
                    .font(.system(size: isCompact ? 12 : 14))
                Text("TIPS")
                    .font(.system(size: isCompact ? 11 : 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1)
                Spacer()
            }

            // Tips list
            VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                ForEach(selectedClass.keyHighlights.prefix(3), id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                            .foregroundColor(.nethackSuccess)
                            .frame(width: 12)
                        Text(highlight)
                            .font(.system(size: isCompact ? 11 : 12))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(isCompact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Class Section (Right Top)

    @ViewBuilder
    private func classSection(geometry: GeometryProxy, isCompact: Bool) -> some View {
        let sectionHeight: CGFloat = isCompact ? 110 : 140

        HStack(spacing: 0) {
            // Previous arrow - full height touch target, arrow centered
            Button(action: { navigatePrevious() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: isCompact ? 16 : 20, weight: .bold))
                    .foregroundColor(selectedClassIndex > 0 ? .white.opacity(0.8) : .white.opacity(0.2))
                    .frame(width: 44, height: sectionHeight)
                    .contentShape(Rectangle())
            }
            .disabled(selectedClassIndex == 0)

            // Class info - fixed height to prevent jumping
            // SWIPE GESTURE: Swipe left/right to change class
            VStack(spacing: isCompact ? 4 : 6) {
                Image(systemName: selectedClass.icon)
                    .font(.system(size: isCompact ? 24 : 32, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(height: isCompact ? 28 : 36) // Fixed icon height

                Text(selectedClass.name.uppercased())
                    .font(.custom("PirataOne-Regular", size: isCompact ? 22 : 28))
                    .foregroundColor(.white)
                    .frame(height: isCompact ? 26 : 32) // Fixed title height

                Text(selectedClass.playstyle)
                    .font(.system(size: isCompact ? 11 : 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .frame(height: isCompact ? 14 : 16) // Fixed playstyle height

                // Difficulty badge
                Text(selectedClass.difficulty.rawValue)
                    .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                    .foregroundColor(selectedClass.difficulty.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(selectedClass.difficulty.color.opacity(0.2))
                    )
                    .frame(height: isCompact ? 20 : 24) // Fixed badge height
            }
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? 110 : 140) // Fixed total height
            .contentShape(Rectangle()) // Make entire area tappable/swipeable
            .gesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        if horizontal < -30 { navigateNext() }
                        else if horizontal > 30 { navigatePrevious() }
                    }
            )

            // Next arrow - full height touch target, arrow centered
            Button(action: { navigateNext() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: isCompact ? 16 : 20, weight: .bold))
                    .foregroundColor(selectedClassIndex < classes.count - 1 ? .white.opacity(0.8) : .white.opacity(0.2))
                    .frame(width: 44, height: sectionHeight)
                    .contentShape(Rectangle())
            }
            .disabled(selectedClassIndex == classes.count - 1)
        }
        .padding(.vertical, isCompact ? 8 : 12)
    }

    // MARK: - Picker Section (Right Bottom)

    @ViewBuilder
    private func pickerSection(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 10) {
            attributeRow(label: "Race", icon: "person.3.fill",
                        value: selectedClass.races[safe: selectedRaceIndex] ?? "Human",
                        onPrev: { if selectedRaceIndex > 0 { selectedRaceIndex -= 1 } },
                        onNext: { if selectedRaceIndex < selectedClass.races.count - 1 { selectedRaceIndex += 1 } },
                        canPrev: selectedRaceIndex > 0,
                        canNext: selectedRaceIndex < selectedClass.races.count - 1,
                        isCompact: isCompact)

            attributeRow(label: "Gender", icon: "figure.stand",
                        value: selectedGenderIndex == 0 ? "Male" : "Female",
                        onPrev: { if selectedGenderIndex > 0 { selectedGenderIndex -= 1 } },
                        onNext: { if selectedGenderIndex < 1 { selectedGenderIndex += 1 } },
                        canPrev: selectedGenderIndex > 0,
                        canNext: selectedGenderIndex < 1,
                        isCompact: isCompact)

            attributeRow(label: "Align", icon: "sparkles",
                        value: selectedClass.alignments[safe: selectedAlignmentIndex] ?? "Neutral",
                        onPrev: { if selectedAlignmentIndex > 0 { selectedAlignmentIndex -= 1 } },
                        onNext: { if selectedAlignmentIndex < selectedClass.alignments.count - 1 { selectedAlignmentIndex += 1 } },
                        canPrev: selectedAlignmentIndex > 0,
                        canNext: selectedAlignmentIndex < selectedClass.alignments.count - 1,
                        isCompact: isCompact)
        }
    }

    @ViewBuilder
    private func attributeRow(label: String, icon: String, value: String,
                             onPrev: @escaping () -> Void, onNext: @escaping () -> Void,
                             canPrev: Bool, canNext: Bool, isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 8 : 12) {
            // Label with icon
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isCompact ? 10 : 12))
                    .foregroundColor(.nethackAccent.opacity(0.7))
                Text(label)
                    .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(width: isCompact ? 60 : 70, alignment: .leading)

            // Picker - SWIPE GESTURE: Swipe left/right to change value
            HStack(spacing: 0) {
                Button(action: onPrev) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                        .foregroundColor(canPrev ? .white.opacity(0.7) : .white.opacity(0.2))
                        .frame(width: 32, height: 32)
                }
                .disabled(!canPrev)

                Text(value)
                    .font(.system(size: isCompact ? 13 : 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(minWidth: isCompact ? 70 : 90)

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                        .foregroundColor(canNext ? .white.opacity(0.7) : .white.opacity(0.2))
                        .frame(width: 32, height: 32)
                }
                .disabled(!canNext)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        if horizontal < -20 && canNext { onNext() }
                        else if horizontal > 20 && canPrev { onPrev() }
                    }
            )
        }
    }

    private func difficultyColor(_ difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "easy": return .nethackSuccess
        case "medium": return .nethackAccent
        case "hard": return .orange
        case "very hard", "expert": return .red
        default: return .white
        }
    }

    private func navigatePrevious() {
        guard selectedClassIndex > 0 else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            selectedClassIndex -= 1
        }
    }

    private func navigateNext() {
        guard selectedClassIndex < classes.count - 1 else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            selectedClassIndex += 1
        }
    }

    // MARK: - Actions

    private func dismissView() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2)) {
            isPresented = false
        }
    }

    private func generateRandomName() {
        let names = selectedGenderIndex == 0 ? maleNames : femaleNames
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) {
            characterName = names.randomElement() ?? ""
        }
    }

    private func startGame() {
        createCharacter()
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        Group {
            if let _ = UIImage(named: "nethack-background-v1") {
                Image("nethack-background-v1")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(red: 50/255, green: 48/255, blue: 47/255), Color.nethackGray100.opacity(0.8), Color(red: 50/255, green: 48/255, blue: 47/255)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay {
            Color(red: 50/255, green: 48/255, blue: 47/255).opacity(0.5)
        }
    }

    // MARK: - Helper Functions

    private func createCharacter() {
        guard !characterName.isEmpty else {
            nameErrorMessage = "Please enter a character name"
            showNameError = true
            return
        }

        let coordinator = SimplifiedSaveLoadCoordinator.shared
        guard !coordinator.characterHasSave(characterName) else {
            nameErrorMessage = "A character named '\(characterName)' already exists"
            showNameError = true
            return
        }

        // Convert Swift UI indices to NetHack indices
        let nethackRoleIndex = ClassDataProvider.nethackRoleIndex(for: selectedClassIndex)
        let nethackRaceIndex = ClassDataProvider.nethackRaceIndex(for: selectedClass.races[selectedRaceIndex])
        let nethackAlignIndex = ClassDataProvider.nethackAlignmentIndex(for: selectedClass.alignments[selectedAlignmentIndex])

        print("[CharCreation] Role: Swift \(selectedClassIndex) -> NetHack \(nethackRoleIndex)")
        print("[CharCreation] Race: '\(selectedClass.races[selectedRaceIndex])' -> NetHack \(nethackRaceIndex)")
        print("[CharCreation] Align: '\(selectedClass.alignments[selectedAlignmentIndex])' -> NetHack \(nethackAlignIndex)")

        gameManager.setRole(nethackRoleIndex)
        gameManager.setRace(nethackRaceIndex)
        gameManager.setGender(selectedGenderIndex)
        gameManager.setAlignment(nethackAlignIndex)
        gameManager.setPlayerName(characterName)
        gameManager.finalizeCharacter()

        guard coordinator.startNewGame(characterName: characterName) else {
            return
        }

        // Load per-character preferences for new character
        CommandGroupManager.shared.loadForCharacter(characterName, role: selectedClass.name)
        print("[CharCreation] ✅ Loaded preferences for new \(selectedClass.name)")

        gameManager.isGameRunning = true
        gameManager.startNewGame()
        gameManager.updateGameState()
        isPresented = false
    }

}

// MARK: - Class Info Model

struct ClassInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let difficulty: Difficulty
    let races: [String]
    let alignments: [String]
    let playstyle: String
    let description: String
    let keyHighlights: [String] // NEW: 2-3 absolute must-knows for beginners
    let recommendedRaces: [String] // NEW: Top 2 recommended races
    let startingEquipment: [String] // Reduced to max 3 items
    let strengths: [String] // Reduced to max 3 items
    let weaknesses: [String] // Reduced to 2-3 items
    let beginnerTips: [String] // Reduced to max 3 items
}

enum Difficulty: String {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    case hardest = "Hardest"

    var color: Color {
        switch self {
        case .easy: return .ccSecondary
        case .medium: return Color.lch(l: 60, c: 65, h: 90)
        case .hard: return Color.lch(l: 60, c: 65, h: 40)
        case .hardest: return Color.lch(l: 50, c: 60, h: 12)
        }
    }
}

// MARK: - Character Creation Colors

extension Color {
    static let ccPrimary = Color.lch(l: 55, c: 65, h: 260)
    static let ccSecondary = Color.lch(l: 60, c: 55, h: 140)
    static let ccBackground = Color.lch(l: 95, c: 3, h: 0)
    static let ccPanel = Color.lch(l: 98, c: 2, h: 0)
    static let ccBorder = Color.lch(l: 85, c: 10, h: 260)
    static let ccText = Color.lch(l: 20, c: 3, h: 0)
    static let ccTextSecondary = Color.lch(l: 50, c: 3, h: 0)
}

// MARK: - Class Data Provider

struct ClassDataProvider {
    /// Maps Swift class indices to NetHack C role indices
    /// NetHack's role order (from role.c): Archeologist=0, Barbarian=1, Caveman=2,
    /// Healer=3, Knight=4, Monk=5, Priest=6, Rogue=7, Ranger=8, Samurai=9,
    /// Tourist=10, Valkyrie=11, Wizard=12
    /// Swift's order (for UI): Barbarian=0, Valkyrie=1, Knight=2, etc.
    static let swiftToNethackRoleIndex: [Int] = [
        1,   // Swift 0 (Barbarian) -> NetHack 1
        11,  // Swift 1 (Valkyrie) -> NetHack 11
        4,   // Swift 2 (Knight) -> NetHack 4
        8,   // Swift 3 (Ranger) -> NetHack 8
        7,   // Swift 4 (Rogue) -> NetHack 7
        9,   // Swift 5 (Samurai) -> NetHack 9
        6,   // Swift 6 (Priest) -> NetHack 6
        3,   // Swift 7 (Healer) -> NetHack 3
        5,   // Swift 8 (Monk) -> NetHack 5
        10,  // Swift 9 (Tourist) -> NetHack 10
        12,  // Swift 10 (Wizard) -> NetHack 12
        0,   // Swift 11 (Archeologist) -> NetHack 0
        2    // Swift 12 (Caveman) -> NetHack 2
    ]

    /// Convert Swift class index to NetHack role index
    static func nethackRoleIndex(for swiftIndex: Int) -> Int {
        guard swiftIndex >= 0 && swiftIndex < swiftToNethackRoleIndex.count else {
            return 0 // Default to Archeologist if invalid
        }
        return swiftToNethackRoleIndex[swiftIndex]
    }

    /// NetHack race indices (from role.c):
    /// Human=0, Elf=1, Dwarf=2, Gnome=3, Orc=4
    static func nethackRaceIndex(for raceName: String) -> Int {
        switch raceName.lowercased() {
        case "human": return 0
        case "elf": return 1
        case "dwarf": return 2
        case "gnome": return 3
        case "orc": return 4
        default:
            print("[CharCreation] ⚠️ Unknown race '\(raceName)', defaulting to Human")
            return 0
        }
    }

    /// NetHack alignment indices (from role.c):
    /// Lawful=0, Neutral=1, Chaotic=2
    static func nethackAlignmentIndex(for alignmentName: String) -> Int {
        switch alignmentName.lowercased() {
        case "lawful": return 0
        case "neutral": return 1
        case "chaotic": return 2
        default:
            print("[CharCreation] ⚠️ Unknown alignment '\(alignmentName)', defaulting to Neutral")
            return 1
        }
    }

    static let allClasses: [ClassInfo] = [
        // Barbarian - Easy
        ClassInfo(
            id: "barbarian",
            name: "Barbarian",
            icon: "hammer.fill",
            difficulty: .easy,
            races: ["Human", "Orc"],
            alignments: ["Neutral", "Chaotic"],
            playstyle: "Pure melee warrior, highest HP",
            description: "Warriors from the hinterland, hardened to battle. Best starting HP of any role. Poison resistance from Level 1. Simple, straightforward melee combat. Perfect for beginners.",
            keyHighlights: [
                "Highest HP in the game - incredible survivability",
                "Poison resistance from Level 1 (prevents instadeath)",
                "Simple pure melee - perfect first class"
            ],
            recommendedRaces: ["Human", "Orc"],
            startingEquipment: [
                "Two-handed sword or Battle-axe",
                "Ring mail armor",
                "Food ration"
            ],
            strengths: [
                "Highest HP in the game",
                "Poison resistance from start",
                "Simple melee combat"
            ],
            weaknesses: [
                "No spellcasting",
                "Limited ranged options"
            ],
            beginnerTips: [
                "Your high HP is your main advantage - tank and smash",
                "Two-handed weapons deal massive damage",
                "Don't worry about spells - pure melee works"
            ]
        ),

        // Valkyrie - Easy
        ClassInfo(
            id: "valkyrie",
            name: "Valkyrie",
            icon: "shield.fill",
            difficulty: .easy,
            races: ["Human", "Dwarf"],
            alignments: ["Lawful", "Neutral"],
            playstyle: "Melee specialist, great defenses",
            description: "Hardy warrior women from the Northlands. Cold resistance and stealth from start. Excellent gear with +1 long sword and +3 small shield. Perfect beginner class.",
            keyHighlights: [
                "Best starting gear (+1 sword, +3 shield)",
                "Cold resistance & Stealth from Level 1",
                "Simple melee focus - excellent for beginners"
            ],
            recommendedRaces: ["Dwarf", "Human"],
            startingEquipment: [
                "+1 Long sword",
                "+3 Small shield (best starting AC!)",
                "Dagger for ranged"
            ],
            strengths: [
                "Best starting weapon and shield",
                "Cold resistance from Level 1",
                "Stealth from start"
            ],
            weaknesses: [
                "Always female",
                "Limited spellcasting"
            ],
            beginnerTips: [
                "Your +3 shield is amazing - keep it!",
                "+1 long sword is excellent early game",
                "Dwarven Valkyrie is best for beginners"
            ]
        ),

        // Knight - Medium
        ClassInfo(
            id: "knight",
            name: "Knight",
            icon: "flag.fill",
            difficulty: .medium,
            races: ["Human"],
            alignments: ["Lawful"],
            playstyle: "Mounted warrior, chivalry code",
            description: "Noble warriors bound by honor. Start with a saddled pony. Excalibur access (1/6 chance). Code of chivalry restricts some actions. Strong melee with mobility.",
            keyHighlights: [
                "Saddled pony from start - unique mobility",
                "Best Excalibur access (1/6 chance)",
                "Code of chivalry - honor matters"
            ],
            recommendedRaces: ["Human"],
            startingEquipment: [
                "+1 Long sword",
                "Saddled pony (mount!)",
                "Ring mail + small shield"
            ],
            strengths: [
                "Saddled pony from start",
                "Best Excalibur access (1/6)",
                "Strong melee combat"
            ],
            weaknesses: [
                "Code of chivalry restrictions",
                "Quest is challenging"
            ],
            beginnerTips: [
                "Use your pony for mobility advantage",
                "Excalibur is powerful - dip at fountains",
                "Chivalry code: don't attack peaceful monsters"
            ]
        ),

        // Ranger - Medium
        ClassInfo(
            id: "ranger",
            name: "Ranger",
            icon: "leaf.fill",
            difficulty: .medium,
            races: ["Human", "Elf", "Gnome", "Orc"],
            alignments: ["Neutral", "Chaotic"],
            playstyle: "Ranged specialist, multishot expert",
            description: "Masters of archery and wilderness. Start with +2 arrows and bow. Highest multishot potential. Good for ranged combat but requires arrow management.",
            keyHighlights: [
                "Highest multishot bonus - devastating ranged",
                "50+ +2 arrows & +2 cloak at start",
                "Stay at distance - avoid melee"
            ],
            recommendedRaces: ["Elf", "Human"],
            startingEquipment: [
                "+1 Dagger",
                "+1 Bow with 50-59 +2 arrows!",
                "+2 Cloak of displacement"
            ],
            strengths: [
                "Excellent starting projectiles",
                "Highest multishot bonus",
                "Cloak of displacement"
            ],
            weaknesses: [
                "Arrow management complex",
                "Weak early melee"
            ],
            beginnerTips: [
                "Stay at distance - ranged is your strength",
                "Save +2 arrows for tough enemies",
                "Get a luckstone for better multishot"
            ]
        ),

        // Rogue - Medium
        ClassInfo(
            id: "rogue",
            name: "Rogue",
            icon: "eye.slash.fill",
            difficulty: .medium,
            races: ["Human", "Orc"],
            alignments: ["Chaotic"],
            playstyle: "Stealth, backstabbing, trap expert",
            description: "Agile thieves with surprise attacks. Backstab damage scales with level. No penalty for stealing. Stealth from Level 1. Tricky but rewarding.",
            keyHighlights: [
                "Backstab damage scales with level",
                "No steal penalty - unique to Rogue!",
                "Stealth from Level 1"
            ],
            recommendedRaces: ["Orc", "Human"],
            startingEquipment: [
                "Short sword",
                "6-16 Daggers (great ranged!)",
                "Leather armor + lock pick"
            ],
            strengths: [
                "Backstab bonus damage",
                "No steal penalty (unique!)",
                "Stealth from Level 1"
            ],
            weaknesses: [
                "Low starting strength",
                "Complex mechanics"
            ],
            beginnerTips: [
                "Use stealth for positioning",
                "Backstab fleeing enemies for bonus damage",
                "Steal from shops freely - no penalty!"
            ]
        ),

        // Samurai - Medium
        ClassInfo(
            id: "samurai",
            name: "Samurai",
            icon: "wind",
            difficulty: .medium,
            races: ["Human"],
            alignments: ["Lawful"],
            playstyle: "Sword master, two-weapon specialist",
            description: "Elite warriors of feudal Nippon. Highest starting CON. Katana and rustproof armor. Bushido code of honor. Two-weapon combat excellent.",
            keyHighlights: [
                "Katana - superior to long sword",
                "Rustproof splint mail from start",
                "Highest starting CON (HP bonus)"
            ],
            recommendedRaces: ["Human"],
            startingEquipment: [
                "Katana (superior weapon!)",
                "Short sword",
                "Rustproof splint mail"
            ],
            strengths: [
                "Best starting CON (HP)",
                "Katana excellent weapon",
                "Rustproof armor"
            ],
            weaknesses: [
                "Bushido code restrictions",
                "Very hard quest"
            ],
            beginnerTips: [
                "Katana is better than long sword - keep it",
                "Rustproof armor is precious",
                "Don't grave dig - bushido code forbids it"
            ]
        ),

        // Priest - Medium
        ClassInfo(
            id: "priest",
            name: "Priest",
            icon: "cross.fill",
            difficulty: .medium,
            races: ["Human", "Elf"],
            alignments: ["Lawful", "Neutral", "Chaotic"],
            playstyle: "Divine caster, undead specialist",
            description: "Clerics with divine magic. Know item beatitude. Holy water and blessed mace. Turn undead ability. Good spellcasting despite weapon restrictions.",
            keyHighlights: [
                "Know item beatitude (cursed/blessed)",
                "4 holy water potions at start",
                "Turn undead power vs zombies"
            ],
            recommendedRaces: ["Human", "Elf"],
            startingEquipment: [
                "Blessed +1 Mace",
                "4 Potions of holy water!",
                "2 Random spellbooks"
            ],
            strengths: [
                "Know item beatitude",
                "Holy water start",
                "Turn undead power"
            ],
            weaknesses: [
                "Weapon restrictions (no swords)",
                "Fragile early"
            ],
            beginnerTips: [
                "Holy water is precious - conserve it",
                "Use turn undead on zombie packs",
                "Avoid swords - weapon restriction applies"
            ]
        ),

        // Healer - Hard
        ClassInfo(
            id: "healer",
            name: "Healer",
            icon: "cross.case.fill",
            difficulty: .hard,
            races: ["Human", "Gnome"],
            alignments: ["Neutral"],
            playstyle: "Medical specialist, poison immunity",
            description: "Doctors with healing skills. Poison immunity from start. Stone to flesh at Level 3. Weak early combat but powerful utility. Challenging but rewarding.",
            keyHighlights: [
                "Poison immunity from start (instadeath prevention)",
                "Stone to flesh spell at Level 3!",
                "Weakest weapon - avoid combat early"
            ],
            recommendedRaces: ["Gnome", "Human"],
            startingEquipment: [
                "Scalpel (weak weapon)",
                "Stethoscope",
                "Healing spells & potions"
            ],
            strengths: [
                "Poison immunity from start",
                "Stone to flesh spell (Level 3!)",
                "Healing expertise"
            ],
            weaknesses: [
                "Weakest starting weapon",
                "Fragile early game"
            ],
            beginnerTips: [
                "Avoid combat early - you're very weak",
                "Stone to flesh at Level 3 is game-changing",
                "Use stethoscope to avoid risky fights"
            ]
        ),

        // Monk - Hard
        ClassInfo(
            id: "monk",
            name: "Monk",
            icon: "figure.martial.arts",
            difficulty: .hard,
            races: ["Human", "Orc"],
            alignments: ["Lawful", "Neutral", "Chaotic"],
            playstyle: "Unarmed master, 17 intrinsics",
            description: "Martial artists fighting unarmed. 17 intrinsics by Level 25! Multiple playstyles. No armor or weapons. Hardest role with highest potential.",
            keyHighlights: [
                "17 intrinsics (most of any role!)",
                "No armor or weapons allowed",
                "Avoid as beginner - hardest class"
            ],
            recommendedRaces: ["Human", "Orc"],
            startingEquipment: [
                "Robe (no armor!)",
                "Food rations",
                "Healing potions"
            ],
            strengths: [
                "17 intrinsics (most of any role!)",
                "Unarmed combat scales with level",
                "Incredible late-game potential"
            ],
            weaknesses: [
                "No armor or weapons",
                "Very fragile early game"
            ],
            beginnerTips: [
                "Avoid this class as beginner!",
                "Unarmed damage scales with level",
                "Speed and stealth are survival keys"
            ]
        ),

        // Tourist - Hardest
        ClassInfo(
            id: "tourist",
            name: "Tourist",
            icon: "camera.fill",
            difficulty: .hardest,
            races: ["Human"],
            alignments: ["Neutral"],
            playstyle: "Jack of all trades, late-game powerhouse",
            description: "Lowest starting HP but highest gold. Camera and credit card. Darts only weapon. Hardest early game but becomes incredibly powerful late. Not for beginners!",
            keyHighlights: [
                "Massive starting gold (1-1000!)",
                "Camera blinds/scares enemies",
                "Lowest HP - hardest early game"
            ],
            recommendedRaces: ["Human"],
            startingEquipment: [
                "Expensive camera (powerful!)",
                "Credit card (opens locks)",
                "21-40 +2 Darts"
            ],
            strengths: [
                "Massive starting gold",
                "Camera blinds/scares",
                "Amazing late-game flexibility"
            ],
            weaknesses: [
                "Lowest starting HP",
                "Darts only trained weapon"
            ],
            beginnerTips: [
                "DON'T pick this as first class!",
                "Camera is better than weapons early",
                "Survive to mid-game for power spike"
            ]
        ),

        // Wizard - Hardest
        ClassInfo(
            id: "wizard",
            name: "Wizard",
            icon: "wand.and.stars",
            difficulty: .hardest,
            races: ["Human", "Elf", "Gnome", "Orc"],
            alignments: ["Neutral", "Chaotic"],
            playstyle: "Pure spellcaster, magic master",
            description: "Best spellcasters but hardest role. Hungerless casting at INT 17+. Low HP, weak melee. Requires energy management. Incredibly powerful late-game.",
            keyHighlights: [
                "Best spellcasting in the game",
                "Hungerless casting at INT 17+",
                "Lowest HP - avoid melee entirely"
            ],
            recommendedRaces: ["Elf", "Gnome"],
            startingEquipment: [
                "Blessed force bolt spellbook",
                "Cloak of magic resistance",
                "Random spellbook + wand"
            ],
            strengths: [
                "Best spellcasting",
                "Hungerless casting (INT 17+)",
                "Double energy on level-up"
            ],
            weaknesses: [
                "Lowest starting HP",
                "Very weak melee"
            ],
            beginnerTips: [
                "NOT for beginners!",
                "Manage spellcasting energy carefully",
                "Use pet for early combat - avoid melee"
            ]
        ),

        // Archeologist - Medium
        ClassInfo(
            id: "archeologist",
            name: "Archeologist",
            icon: "fossil.shell.fill",
            difficulty: .medium,
            races: ["Human", "Dwarf", "Gnome"],
            alignments: ["Lawful", "Neutral"],
            playstyle: "Scholar, trap expert, balanced",
            description: "Scholarly adventurers. Start with bullwhip and fedora. Touch-identify gems and stones. Trap expertise. Balanced attributes and good survivability.",
            keyHighlights: [
                "Touch-identify gems & stones",
                "Bullwhip hits from distance",
                "Balanced attributes - jack-of-all-trades"
            ],
            recommendedRaces: ["Dwarf", "Human"],
            startingEquipment: [
                "Bullwhip (unique!)",
                "Fedora + leather jacket",
                "Pick-axe"
            ],
            strengths: [
                "Touch-identify gems/stones",
                "Bullwhip for distant enemies",
                "Good trap expertise"
            ],
            weaknesses: [
                "Weak early weapons",
                "No major advantages"
            ],
            beginnerTips: [
                "Bullwhip hits from distance safely",
                "Identify gems by touch for value",
                "Use pick-axe to dig shortcuts"
            ]
        ),

        // Caveman - Easy-Medium
        ClassInfo(
            id: "caveman",
            name: "Caveman",
            icon: "figure.hunting",
            difficulty: .medium,
            races: ["Human", "Dwarf", "Gnome"],
            alignments: ["Lawful", "Neutral"],
            playstyle: "Primitive warrior, club/sling expert",
            description: "Primitive warriors. High starting HP and STR. Club and sling expertise. Simple playstyle. Good for beginners after Barbarian.",
            keyHighlights: [
                "High starting HP & STR",
                "Sling provides ranged option",
                "Simple straightforward combat"
            ],
            recommendedRaces: ["Dwarf", "Human"],
            startingEquipment: [
                "Club",
                "Sling + rocks",
                "Leather armor"
            ],
            strengths: [
                "High starting HP/STR",
                "Sling for ranged combat",
                "Simple combat"
            ],
            weaknesses: [
                "Basic equipment",
                "Limited weapon options"
            ],
            beginnerTips: [
                "Use sling for ranged attacks",
                "High HP lets you tank hits",
                "Good second class after Barbarian/Valkyrie"
            ]
        )
    ]
}

// MARK: - Responsive Swipe Picker

/// A swipe picker that adapts to device size with proper touch targets
struct ResponsiveSwipePicker: View {
    let label: String
    @Binding var selectedIndex: Int
    let options: [String]
    let geometry: GeometryProxy

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var isLandscape: Bool {
        geometry.size.width > geometry.size.height
    }

    private var labelFontSize: CGFloat {
        // IPHONE LANDSCAPE FIX: Smaller label on phone landscape
        if device.isPhone && isLandscape {
            return 9
        }
        return ResponsiveLayout.fontSize(.footnote, for: geometry)
    }

    private var valueFontSize: CGFloat {
        // IPHONE LANDSCAPE FIX: Smaller value text on phone landscape
        if device.isPhone && isLandscape {
            return 15
        }
        switch device {
        case .phone: return 18
        case .tabletCompact: return 20
        case .tablet: return 22
        }
    }

    private var arrowSize: CGFloat {
        // IPHONE LANDSCAPE FIX: Smaller arrows on phone landscape
        if device.isPhone && isLandscape {
            return 14
        }
        switch device {
        case .phone: return 16
        case .tabletCompact: return 18
        case .tablet: return 20
        }
    }

    private var pickerHeight: CGFloat {
        // MINIMUM 44pt for touch target
        // IPHONE LANDSCAPE FIX: Use minimum 44pt on phone landscape
        if device.isPhone && isLandscape {
            return 44  // Minimum touch target, saves vertical space
        }
        switch device {
        case .phone: return 48
        case .tabletCompact: return 54
        case .tablet: return 60
        }
    }

    private var arrowWidth: CGFloat {
        // MINIMUM 44pt for touch target
        // IPHONE LANDSCAPE FIX: Tighter arrow buttons
        if device.isPhone && isLandscape {
            return 36
        }
        switch device {
        case .phone: return 44
        case .tabletCompact: return 48
        case .tablet: return 50
        }
    }

    private var cornerRadius: CGFloat {
        // IPHONE LANDSCAPE FIX: Smaller corner radius
        if device.isPhone && isLandscape {
            return 8
        }
        return ResponsiveLayout.cornerRadius(for: geometry)
    }

    private var labelSpacing: CGFloat {
        // IPHONE LANDSCAPE FIX: Tighter spacing between label and picker
        if device.isPhone && isLandscape {
            return 2
        }
        return 6
    }

    var body: some View {
        guard !options.isEmpty, selectedIndex >= 0, selectedIndex < options.count else {
            return AnyView(
                VStack(alignment: .leading, spacing: labelSpacing) {
                    Text(label.uppercased())
                        .font(.system(size: labelFontSize, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                    Text("No options")
                        .font(.custom("PirataOne-Regular", size: valueFontSize))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(height: pickerHeight)
                }
            )
        }

        return AnyView(
            VStack(alignment: .leading, spacing: labelSpacing) {
                // Label
                Text(label.uppercased())
                    .font(.system(size: labelFontSize, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .shadow(color: .black.opacity(0.7), radius: 1)

                // Picker box
                HStack(spacing: 0) {
                    // Left arrow
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) {
                            guard selectedIndex > 0 else { return }
                            selectedIndex -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: arrowSize, weight: .bold))
                            .foregroundColor(selectedIndex > 0 ? .white : .white.opacity(0.3))
                            .frame(width: arrowWidth, height: pickerHeight)
                            .contentShape(Rectangle())
                    }
                    .disabled(selectedIndex == 0)

                    Spacer()

                    // Current value
                    Text(options[selectedIndex])
                        .font(.custom("PirataOne-Regular", size: valueFontSize))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.9), radius: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .offset(x: dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation.width
                                }
                                .onEnded { value in
                                    let swipeThreshold: CGFloat = 50

                                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                                        if value.translation.width < -swipeThreshold && selectedIndex < options.count - 1 {
                                            selectedIndex += 1
                                        } else if value.translation.width > swipeThreshold && selectedIndex > 0 {
                                            selectedIndex -= 1
                                        }
                                        dragOffset = 0
                                    }
                                }
                        )

                    Spacer()

                    // Right arrow
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) {
                            guard selectedIndex < options.count - 1 else { return }
                            selectedIndex += 1
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: arrowSize, weight: .bold))
                            .foregroundColor(selectedIndex < options.count - 1 ? .white : .white.opacity(0.3))
                            .frame(width: arrowWidth, height: pickerHeight)
                            .contentShape(Rectangle())
                    }
                    .disabled(selectedIndex == options.count - 1)
                }
                .frame(height: pickerHeight)
                .background(Color.nethackGray200.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.nethackGray100.opacity(0.5), radius: 5, y: 3)
            }
        )
    }
}

