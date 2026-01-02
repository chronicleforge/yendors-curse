import SwiftUI
import Combine

// MARK: - C Bridge Imports

/// Clear iflags.menu_requested before #loot to prevent direction query
@_silgen_name("ios_clear_menu_requested")
private func ios_clear_menu_requested()

// MARK: - Pending Loot Mode Storage

/// Thread-safe storage for pending loot mode (used by MenuBridge auto-selection)
/// When user selects a loot mode from LootOptionsPicker (native mode),
/// we store it here so MenuBridge can auto-select it when the menu appears.
///
/// Two-phase flow for "put in" / "both" operations:
/// 1. Menu 1: Loot options (o, i, b, r, s, :, n, q) - auto-select based on pendingMode
/// 2. Menu 2: Category selection ("Put in what type of objects?") - auto-select all if expectCategorySelection
final class PendingLootModeStorage {
    static let shared = PendingLootModeStorage()

    private let lock = NSLock()
    private var _pendingMode: LootMode?
    private var _expectCategorySelection: Bool = false

    private init() {}

    /// Store a pending loot mode for auto-selection
    func store(_ mode: LootMode) {
        lock.lock()
        _pendingMode = mode
        _expectCategorySelection = false
        lock.unlock()
        print("[PendingLootMode] Stored: \(mode.displayName)")
    }

    /// Consume and return the pending mode (returns nil if none)
    /// If mode is putIn/both/reversed, sets expectCategorySelection flag
    func consume() -> LootMode? {
        lock.lock()
        let mode = _pendingMode
        _pendingMode = nil

        // If this was a put-in related mode, we expect a category selection menu next
        if let mode = mode {
            let expectsCategory = mode == .putIn || mode == .both || mode == .reversed
            if expectsCategory {
                _expectCategorySelection = true
            }
            let suffix = expectsCategory ? " - expecting category selection next" : ""
            print("[PendingLootMode] Consumed: \(mode.displayName)\(suffix)")
        }

        lock.unlock()
        return mode
    }

    /// Check if there's a pending mode (without consuming)
    func hasPending() -> Bool {
        lock.lock()
        let result = _pendingMode != nil
        lock.unlock()
        return result
    }

    /// Check and consume expectCategorySelection flag
    /// Returns true if we should auto-select all categories in the next menu
    func consumeExpectCategorySelection() -> Bool {
        lock.lock()
        let result = _expectCategorySelection
        _expectCategorySelection = false
        lock.unlock()
        if result {
            print("[PendingLootMode] Consumed expectCategorySelection flag")
        }
        return result
    }
}

// MARK: - Loot Flow State

enum LootMode: String, CaseIterable {
    case takeOut = "o"      // Take items out of container
    case putIn = "i"        // Put items into container
    case both = "b"         // Both (take out then put in)
    case reversed = "r"     // Reversed (put in then take out)
    case stash = "s"        // Stash all matching items
    case look = ":"         // Just look at contents

    var displayName: String {
        switch self {
        case .takeOut: return "Take Out"
        case .putIn: return "Put In"
        case .both: return "Both"
        case .reversed: return "Reversed"
        case .stash: return "Stash All"
        case .look: return "Look"
        }
    }

    var icon: String {
        switch self {
        case .takeOut: return "arrow.up.circle"
        case .putIn: return "arrow.down.circle"
        case .both: return "arrow.up.arrow.down"
        case .reversed: return "arrow.left.arrow.right"
        case .stash: return "archivebox"
        case .look: return "eye"
        }
    }

    var character: Character {
        Character(rawValue)
    }
}

// MARK: - Game Overlay Types
enum GameOverlay: String, CaseIterable {
    case none = "None"
    case inventory = "Inventory"
    case character = "Character"
    case spellbook = "Spellbook"
    case map = "Map"
    case help = "Help"
    case discoveries = "Discoveries"

    var icon: String {
        switch self {
        case .none: return ""
        case .inventory: return "backpack.fill"
        case .character: return "person.text.rectangle.fill"
        case .spellbook: return "book.fill"
        case .map: return "map.fill"
        case .help: return "questionmark.circle.fill"
        case .discoveries: return "sparkles"
        }
    }
}

// MARK: - Game Overlay Manager
@MainActor
final class GameOverlayManager: ObservableObject {
    @Published var activeOverlay: GameOverlay = .none
    @Published var showAsPanel: Bool = false // Full overlay instead of side panel
    @Published var panelWidth: CGFloat = 400
    @Published var items: [NetHackItem] = [] // Real inventory from NetHack bridge

    // For drag & drop between inventory and hotbar
    @Published var draggedItem: NetHackItem?
    @Published var isDraggingToHotbar: Bool = false

    // MARK: - Item Selection State
    @Published var showItemSelection: Bool = false
    @Published var itemSelectionContext: ItemSelectionContext?

    // MARK: - Quantity Picker State
    @Published var showQuantityPicker: Bool = false
    @Published var quantityPickerItem: InventoryItem?
    @Published var quantityPickerAction: NetHackAction?
    @Published var quantityPickerMaxQuantity: Int = 1
    @Published var quantityPickerCompletion: ((Int?) -> Void)?

    // MARK: - Error State
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    // MARK: - Engraving State
    @Published var showEngraveFlow: Bool = false

    // MARK: - Discoveries State
    @Published var showDiscoveries: Bool = false

    // MARK: - Dungeon Overview State
    @Published var showDungeonOverview: Bool = false

    // MARK: - Spell Selection State
    @Published var showSpellSelection: Bool = false
    @Published var spells: [NetHackSpell] = []
    @Published var selectedSpellForDirection: NetHackSpell? = nil
    @Published var showDirectionPicker: Bool = false

    // MARK: - Action Direction Picker State
    @Published var selectedActionForDirection: NetHackAction? = nil
    @Published var showActionDirectionPicker: Bool = false

    // MARK: - Item + Direction State (for throw, zap)
    @Published var pendingItemForDirection: Character? = nil
    @Published var pendingCommandForDirection: String? = nil

    // MARK: - Hand Picker State (for ring equipment)
    @Published var showHandPicker: Bool = false
    private var handSelectionCancellable: AnyCancellable?

    // MARK: - Loot Options State (legacy - removed LootOptionsPicker)
    @Published var availableLootModes: Set<Character> = []  // Available options from NetHack
    private var lootOptionsCancellable: AnyCancellable?
    private var textInputCancellable: AnyCancellable?

    // MARK: - Skill Enhance State
    @Published var showSkillEnhance: Bool = false
    @Published var skillEnhanceData: (skills: [SkillInfo], slots: Int) = ([], 0)

    // MARK: - Escape Warning State
    @Published var showEscapeWarning: Bool = false

    // MARK: - Text Input State (for getlin() actions: Name, Genocide, Polymorph, Engrave custom)
    @Published var showTextInput: Bool = false
    @Published var textInputContext: TextInputContext?

    // MARK: - Container Transfer State
    @Published var showContainerPicker: Bool = false
    @Published var showContainerTransfer: Bool = false
    @Published var floorContainers: [FloorContainerInfo] = []
    @Published var selectedFloorContainer: FloorContainerInfo?

    // MARK: - Chronicle State
    @Published var showChronicle: Bool = false
    @Published var chronicleEntries: [ChronicleEntry] = []

    // MARK: - Conduct State
    @Published var showConduct: Bool = false
    @Published var conductData: ConductData?

    // PERF: Debounce inventory updates - multiple notifications can fire per action
    private var lastInventoryUpdate: CFTimeInterval = 0
    private let inventoryDebounceInterval: CFTimeInterval = 0.1  // 100ms

    init() {
        // Subscribe to hand selection notification from C bridge
        handSelectionCancellable = NotificationCenter.default
            .publisher(for: Notification.Name("NetHackHandSelection"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleHandSelectionRequest()
            }

        // Subscribe to loot options notification from C bridge
        // This handles RE-PROMPTS when initial choice was invalid (e.g., "both" on empty container)
        lootOptionsCancellable = NotificationCenter.default
            .publisher(for: Notification.Name("NetHackLootOptions"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleLootOptionsRequest(notification)
            }

        // Subscribe to text input notification from C bridge
        // For genocide, polymorph, name prompts - shows TextInputSheet with suggestions
        textInputCancellable = NotificationCenter.default
            .publisher(for: Notification.Name("NetHackTextInput"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleTextInputRequest(notification)
            }
    }

    // MARK: - Hand Picker

    /// Called when C bridge requests hand selection (putting on ring)
    private func handleHandSelectionRequest() {
        print("[HAND_PICKER] Received hand selection request from C bridge")

        // Refresh character status to get current ring state
        Task {
            await CharacterStatusManager.shared.refresh()

            await MainActor.run {
                withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                    self.showHandPicker = true
                }
            }
        }
    }

    /// User selected a hand - queue the response
    func handleHandSelected(_ hand: Character) {
        guard let ascii = hand.asciiValue else { return }

        print("[HAND_PICKER] User selected hand: \(hand)")

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showHandPicker = false
        }

        // Queue the hand selection response
        ios_queue_input(Int8(ascii))
    }

    /// User cancelled hand selection
    func cancelHandSelection() {
        print("[HAND_PICKER] User cancelled hand selection")

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showHandPicker = false
        }

        // Queue ESC to cancel
        ios_queue_input(0x1b)
    }

    // MARK: - Loot Options Picker (Native Interception)
    // NOTE: This is the NATIVE approach - UI appears BEFORE #loot command is sent
    // CommandHandler intercepts M-l and calls showLootOptionsPicker()
    // User selects mode, THEN we send the full command sequence

    /// Show loot options picker - called by CommandHandler BEFORE sending #loot to NetHack
    /// Now first checks for floor containers and shows native transfer UI if found
    func showLootOptionsPicker() {
        guard NetHackBridge.shared.gameStarted else { return }

        // Check for containers at player position
        let containers = ContainerTransferService.shared.getFloorContainers()

        guard !containers.isEmpty else {
            // No containers found - send native #loot command to NetHack
            // NetHack will handle "There is nothing here to loot" message
            print("[LOOT_OPTIONS] No floor containers - sending native #loot command")
            sendNativeLootCommand()
            return
        }

        // Filter out locked containers - only show unlocked ones in custom UI
        let unlockedContainers = containers.filter { !$0.isLocked }

        if unlockedContainers.isEmpty {
            // ALL containers are locked - fall back to native loot
            // NetHack will handle "Unlock it?" prompts for lock picking etc.
            print("[LOOT_OPTIONS] All containers locked - falling back to native #loot")
            sendNativeLootCommand()
            return
        }

        print("[LOOT_OPTIONS] Found \(unlockedContainers.count) unlocked container(s)")
        floorContainers = unlockedContainers

        // Multiple unlocked containers - show picker first
        guard unlockedContainers.count == 1 else {
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                showContainerPicker = true
            }
            return
        }

        // Single unlocked container - go directly to transfer view
        selectedFloorContainer = unlockedContainers[0]
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showContainerTransfer = true
        }
    }

    /// Send the native #loot command to NetHack
    private func sendNativeLootCommand() {
        // Clear iflags.menu_requested before #loot
        ios_clear_menu_requested()

        // Send M-l (Meta-l) as raw byte
        let metaByte = UInt8(0x80 | UInt8(ascii: "l"))
        NetHackBridge.shared.sendRawByte(metaByte)

        print("[LOOT_OPTIONS] Sent native M-l command")
    }

    /// User selected a container from the picker
    func selectFloorContainer(_ container: FloorContainerInfo) {
        print("[LOOT_OPTIONS] Selected container: \(container.name)")

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showContainerPicker = false
        }

        selectedFloorContainer = container

        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showContainerTransfer = true
        }
    }

    /// Dismiss container transfer UI
    func dismissContainerTransfer() {
        print("[LOOT_OPTIONS] Dismissing container transfer")

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showContainerTransfer = false
            showContainerPicker = false
        }

        selectedFloorContainer = nil
        floorContainers = []
    }

    /// Open an inventory container (called from Apply action on container items)
    /// - Parameter item: The container item from inventory
    /// - Returns: true if container was opened successfully
    @discardableResult
    func openInventoryContainer(_ item: NetHackItem) -> Bool {
        print("[CONTAINER] Opening inventory container: \(item.fullName)")

        guard item.isContainer else {
            print("[CONTAINER] Item is not a container")
            return false
        }

        // Get container info and set as current
        guard let containerInfo = ContainerTransferService.shared.getInventoryContainerInfo(item: item) else {
            print("[CONTAINER] Could not get container info")
            return false
        }

        // Set as current container via C bridge
        guard ContainerTransferService.shared.setInventoryContainer(invlet: item.invlet) != nil else {
            print("[CONTAINER] Could not set inventory container")
            return false
        }

        // Close inventory first
        closeOverlay()

        // Set the container and show transfer UI
        selectedFloorContainer = containerInfo

        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showContainerTransfer = true
        }

        return true
    }

    /// User selected a loot mode - send command to NetHack
    /// In native mode: stores pending mode for auto-selection when menu appears
    /// In callback mode: sends just the mode character (NetHack is waiting)
    func handleLootModeSelected(_ mode: LootMode) {
        print("[LOOT_OPTIONS] ====== LOOT MODE SELECTED ======")
        print("[LOOT_OPTIONS] Mode: \(mode.displayName) ('\(mode.rawValue)')")
        print("[LOOT_OPTIONS] availableLootModes: \(availableLootModes)")

        // Check if we're in callback mode (NetHack sent us available options)
        let isCallbackMode = !availableLootModes.isEmpty
        print("[LOOT_OPTIONS] isCallbackMode: \(isCallbackMode)")

        availableLootModes = []

        // Callback mode: NetHack is already waiting for yn_function response
        if isCallbackMode {
            let charValue = Int8(mode.character.asciiValue!)
            ios_queue_input(charValue)
            print("[LOOT_OPTIONS] Sent mode character '\(mode.rawValue)' (0x\(String(format: "%02x", charValue))) (callback mode)")
            print("[LOOT_OPTIONS] ==============================")
            return
        }

        // Native mode: Store pending mode for auto-selection when menu appears
        // With menu_style=MENU_FULL, loot options come through graphical menu
        // The mode character won't be read from input queue - menu blocks for UI
        PendingLootModeStorage.shared.store(mode)
        print("[LOOT_OPTIONS] Stored pending mode for auto-selection")

        // CRITICAL: Clear iflags.menu_requested before #loot
        // When this flag is TRUE, doloot() skips container detection and forces
        // "Loot in what direction?" prompt, breaking our auto-selection flow.
        // See pickup.c line 2213-2214 for the problematic goto lootmon.
        ios_clear_menu_requested()
        print("[LOOT_OPTIONS] Cleared menu_requested flag")

        // Send "#" to trigger extended command mode, then "loot\n"
        // ESC is NOT correct here - '#' triggers doextcmd() then ios_get_ext_cmd reads name
        print("[LOOT_OPTIONS] Queuing '#' + 'loot' + newline")
        ios_queue_input(Int8(Character("#").asciiValue!))  // '#' - triggers extended command
        for char in "loot" {
            ios_queue_input(Int8(char.asciiValue!))
        }
        ios_queue_input(Int8(Character("\n").asciiValue!))  // newline - end of command
        print("[LOOT_OPTIONS] Sent command sequence: #loot (native mode)")
        print("[LOOT_OPTIONS] ==============================")
    }

    /// User cancelled loot options - dismiss and send 'q' if in callback mode
    func cancelLootOptions() {
        print("[LOOT_OPTIONS] User cancelled loot options")

        // If we have available modes, we're in callback mode (NetHack is waiting)
        let isCallbackMode = !availableLootModes.isEmpty

        availableLootModes = []

        if isCallbackMode {
            // Send 'q' to cancel the NetHack prompt
            ios_queue_input(Int8(Character("q").asciiValue!))
            print("[LOOT_OPTIONS] Sent 'q' to cancel NetHack prompt")
        }
        // NOTE: In native mode, no command was sent yet so nothing to cancel
    }

    /// Called when C bridge detects loot options prompt (re-prompt after invalid choice)
    /// Auto-selects 'o' (out - take items out) instead of showing picker
    private func handleLootOptionsRequest(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
              let optionsString = userInfo["options"] as? String else {
            print("[LOOT_OPTIONS] Invalid notification format")
            return
        }

        print("[LOOT_OPTIONS] C bridge requesting loot options (available: \(optionsString))")

        // Auto-select 'o' (out) - take items out of container
        // User can use ContainerTransfer UI for more control
        if optionsString.contains("o") {
            ios_queue_input(Int8(Character("o").asciiValue!))
            print("[LOOT_OPTIONS] Auto-selected 'o' (out)")
        } else if optionsString.contains("i") {
            // Fallback to 'i' (in) if 'o' not available
            ios_queue_input(Int8(Character("i").asciiValue!))
            print("[LOOT_OPTIONS] Auto-selected 'i' (in)")
        } else {
            // Cancel if neither available
            ios_queue_input(Int8(Character("q").asciiValue!))
            print("[LOOT_OPTIONS] No valid option - sent 'q'")
        }
    }

    /// Check if a loot mode is currently available (for empty container handling)
    func isLootModeAvailable(_ mode: LootMode) -> Bool {
        // If no specific modes set (native interception), all are available
        guard !availableLootModes.isEmpty else { return true }
        return availableLootModes.contains(mode.character)
    }

    // MARK: - Skill Enhance (Native Interception)
    // NOTE: This is the NATIVE approach - UI appears BEFORE #enhance command is sent
    // CommandHandler intercepts #enhance and calls showSkillEnhanceSheet()
    // User selects skill, THEN we call the bridge to advance it

    /// Show skill enhance sheet - called by CommandHandler BEFORE sending #enhance to NetHack
    func showSkillEnhanceSheet() {
        print("[SKILL_ENHANCE] Showing skill enhance sheet (native interception)")

        // Fetch skill data from C bridge
        let skills = SkillBridgeService.shared.getAllSkills()
        let slots = SkillBridgeService.shared.getAvailableSlots()

        skillEnhanceData = (skills, slots)

        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showSkillEnhance = true
        }
    }

    /// Show the hero's chronicle (game event log)
    func showChronicleSheet() {
        print("[CHRONICLE] Fetching chronicle entries from C bridge")

        // Fetch chronicle entries from C bridge
        chronicleEntries = NetHackBridge.shared.getChronicleEntries()

        print("[CHRONICLE] Loaded \(chronicleEntries.count) entries")

        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            showChronicle = true
        }
    }

    /// Show conduct (voluntary challenges) sheet
    func showConductSheet() {
        print("[CONDUCT] Fetching conduct data from C bridge")

        // Fetch conduct data from C bridge
        conductData = NetHackBridge.shared.getConductData()

        if let data = conductData {
            let entries = data.getConductEntries()
            let maintained = entries.filter { $0.status == .maintained || $0.status == .permanent }.count
            print("[CONDUCT] Loaded \(entries.count) conducts, \(maintained) maintained")
        }

        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            showConduct = true
        }
    }

    /// User selected a skill to advance
    func handleSkillAdvance(_ skill: SkillInfo) {
        print("[SKILL_ENHANCE] User advancing skill: \(skill.name) (id=\(skill.id))")

        // Call bridge to advance the skill
        let success = SkillBridgeService.shared.advanceSkill(skill.id)

        if success {
            // Refresh skill data after advancement
            let skills = SkillBridgeService.shared.getAllSkills()
            let slots = SkillBridgeService.shared.getAvailableSlots()
            skillEnhanceData = (skills, slots)

            // Check if any more skills can be advanced
            let advanceableCount = SkillBridgeService.shared.getAdvanceableCount()
            if advanceableCount == 0 {
                // No more skills to advance - dismiss sheet
                withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
                    showSkillEnhance = false
                }
            }
        }
    }

    /// User cancelled skill enhance - just dismiss
    func cancelSkillEnhance() {
        print("[SKILL_ENHANCE] User cancelled skill enhance")

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showSkillEnhance = false
        }
    }

    // MARK: - Escape Warning (Native Interception)
    // NOTE: This is the NATIVE approach - UI appears BEFORE "<" command is sent when on level 1 without amulet
    // CommandHandler intercepts "<" and calls showEscapeWarning()
    // User confirms/cancels, THEN we either send the command or do nothing

    /// Show escape warning sheet - called by CommandHandler when player tries to escape without amulet
    func showEscapeWarningSheet() {
        print("[ESCAPE_WARNING] Showing escape warning sheet (native interception)")

        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showEscapeWarning = true
        }
    }

    /// User confirmed or cancelled the escape warning
    /// - Parameter confirmed: true = escape (send "<" to NetHack), false = stay (do nothing)
    func confirmEscape(_ confirmed: Bool) {
        print("[ESCAPE_WARNING] User \(confirmed ? "confirmed escape" : "chose to stay")")

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showEscapeWarning = false
        }

        guard confirmed else {
            // User chose to stay - do nothing
            return
        }

        // User confirmed escape - send the climb up command to NetHack
        // The "<" command will trigger y_n("Beware, there will be no return! Still climb?")
        // We must also send 'y' to confirm that prompt!
        let lessThan = Int8(Character("<").asciiValue!)
        let yChar = Int8(Character("y").asciiValue!)
        print("[ESCAPE_WARNING] 🚨 About to queue '<' (0x\(String(format: "%02x", UInt8(bitPattern: lessThan)))) and 'y' (0x\(String(format: "%02x", UInt8(bitPattern: yChar))))")
        ios_queue_input(lessThan)
        print("[ESCAPE_WARNING] ✓ Queued '<'")
        ios_queue_input(yChar)
        print("[ESCAPE_WARNING] ✓ Queued 'y' - Both commands sent to NetHack")
    }

    // MARK: - Text Input (for getlin() actions)

    /// Request text input for getlin() actions (Name, Genocide, Polymorph, Engrave custom)
    /// The context defines prompt, suggestions, and callback
    func requestTextInput(context: TextInputContext) {
        print("[TEXT_INPUT] Showing text input sheet: '\(context.prompt)'")

        textInputContext = context
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showTextInput = true
        }
    }

    /// Handle text input submission - queue text to NetHack and close sheet
    func handleTextInputSubmit(_ text: String) {
        print("[TEXT_INPUT] User submitted: '\(text)'")

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showTextInput = false
        }

        // Queue text to NetHack character by character, then newline
        for char in text {
            guard let ascii = char.asciiValue else { continue }
            ios_queue_input(Int8(ascii))
        }
        ios_queue_input(Int8(Character("\n").asciiValue!))

        print("[TEXT_INPUT] Queued text '\(text)' + newline to NetHack")

        // Clear context after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.textInputContext = nil
        }
    }

    /// Cancel text input - send ESC to NetHack and close sheet
    func cancelTextInput() {
        print("[TEXT_INPUT] User cancelled text input")

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showTextInput = false
        }

        // Send ESC to cancel the getlin() prompt
        ios_queue_input(0x1b)
        print("[TEXT_INPUT] Sent ESC to cancel NetHack prompt")

        // Clear context after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.textInputContext = nil
        }
    }

    /// Called when C bridge requests text input (genocide, polymorph, name prompts)
    private func handleTextInputRequest(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
              let inputType = userInfo["type"] as? String else {
            print("[TEXT_INPUT] Invalid notification format")
            return
        }

        let prompt = userInfo["prompt"] as? String ?? "Enter text:"
        print("[TEXT_INPUT] C bridge requesting text input - type: '\(inputType)', prompt: '\(prompt)'")

        // Create appropriate context based on input type
        let context: TextInputContext
        switch inputType {
        case "genocide":
            context = .genocide { [weak self] text in
                self?.handleTextInputSubmit(text)
            }
        case "polymorph":
            context = .polymorph { [weak self] text in
                self?.handleTextInputSubmit(text)
            }
        case "name":
            context = .name(prompt: prompt) { [weak self] text in
                self?.handleTextInputSubmit(text)
            }
        case "wish":
            context = .wish { [weak self] text in
                self?.handleTextInputSubmit(text)
            }
        case "annotation":
            context = .annotation(prompt: prompt) { [weak self] text in
                self?.handleTextInputSubmit(text)
            }
        default:
            // Generic text input
            context = TextInputContext(
                prompt: prompt,
                icon: "keyboard",
                color: .blue,
                placeholder: "Enter text...",
                showSearch: false,
                killedMonsters: [],
                seenMonsters: [],
                staticSuggestions: [],
                onSubmit: { [weak self] text in
                    self?.handleTextInputSubmit(text)
                }
            )
        }

        requestTextInput(context: context)
    }

    // Update inventory from NetHack (synchronous request/response)
    func updateInventory() {
        // CRITICAL: Don't access C inventory after death - memory may be freed
        guard NetHackBridge.shared.gameStarted else {
            print("[INVENTORY] ⚠️ Game not running - skipping inventory update")
            items = []
            return
        }

        // PERF: Debounce - skip if called within 100ms (multiple notifications per action)
        let now = CACurrentMediaTime()
        guard now - lastInventoryUpdate >= inventoryDebounceInterval else {
            return  // Skip - too soon since last update
        }
        lastInventoryUpdate = now

        let count = Int(nethack_get_inventory_count())
        guard count > 0 else {
            items = []
            return
        }

        // Allocate array for C inventory items
        var cItems = Array(repeating: InventoryItem(), count: count)
        let actualCount = Int(nethack_get_inventory_items(&cItems, Int32(count)))

        defer {
            // CRITICAL: Free allocated C strings
            nethack_free_inventory_items(&cItems, Int32(actualCount))
        }

        // Convert C items to Swift NetHackItem
        items = (0..<actualCount).map { i in
            let cItem = cItems[i]

            // Convert BUC status
            let bucStatus: ItemBUCStatus
            switch cItem.buc_status {
            case Int8(UnicodeScalar("B").value): bucStatus = .blessed
            case Int8(UnicodeScalar("C").value): bucStatus = .cursed
            case Int8(UnicodeScalar("U").value): bucStatus = .uncursed
            default: bucStatus = .unknown
            }

            // Convert object class to category
            let category = ItemCategory.fromOclass(cItem.oclass)

            // Get item name (already allocated by C bridge)
            let nameStr = String(cString: cItem.name, encoding: .utf8) ?? ""

            // Create NetHackItem (use default init with only essential params)
            var item = NetHackItem(
                invlet: Character(UnicodeScalar(UInt8(cItem.invlet))),
                name: nameStr,
                fullName: nameStr,
                category: category,
                quantity: Int(cItem.quantity)
            )
            // Set additional properties
            item.bucStatus = bucStatus
            item.bucKnown = cItem.buc_known  // Only show BUC if player knows it!
            item.enchantment = Int(cItem.enchantment)

            // Parse equipment status from C struct
            item.properties.isWorn = cItem.is_equipped
            if cItem.is_equipped {
                let slotStr = withUnsafePointer(to: cItem.equipped_slot) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: 16) { cStr in
                        String(cString: cStr)
                    }
                }
                item.properties.isWielded = slotStr.contains("wield")
                // isWorn stays true for armor worn
            }

            // Container support - enable "Open" button for bags/boxes
            item.isContainer = cItem.is_container

            return item
        }
    }


    // MARK: - Reset for New Game

    /// Reset all overlay state for a fresh game start
    func resetForNewGame() {
        print("[OverlayManager] Resetting all state for new game...")
        activeOverlay = .none
        showAsPanel = false
        items = []
        draggedItem = nil
        isDraggingToHotbar = false
        showItemSelection = false
        itemSelectionContext = nil
        showQuantityPicker = false
        quantityPickerItem = nil
        quantityPickerAction = nil
        quantityPickerMaxQuantity = 1
        quantityPickerCompletion = nil
        showError = false
        errorMessage = ""
        showEngraveFlow = false
        showDiscoveries = false
        showDungeonOverview = false
        showSpellSelection = false
        spells = []
        selectedSpellForDirection = nil
        selectedActionForDirection = nil
        showActionDirectionPicker = false
        pendingItemForDirection = nil
        pendingCommandForDirection = nil
        showHandPicker = false
        showSkillEnhance = false
        skillEnhanceData = ([], 0)
        showEscapeWarning = false
        showTextInput = false
        textInputContext = nil
        showContainerPicker = false
        showContainerTransfer = false
        floorContainers = []
        selectedFloorContainer = nil
        print("[OverlayManager] ✓ All state reset")
    }

    // MARK: - Actions
    func toggleOverlay(_ overlay: GameOverlay) {
        // No withAnimation here - let the view handle it with .animation() modifier
        activeOverlay = (activeOverlay == overlay) ? .none : overlay
    }

    func closeOverlay() {
        // No withAnimation here - let the view handle it with .animation() modifier
        // This ensures consistent scale+opacity transition (not just fade)
        activeOverlay = .none
    }

    func showInventory() {
        // PERF: No updateInventory() call here! Inventory is auto-cached by
        // NetHackGameManager.updateGameState() every turn.
        // RCA: On-demand parsing blocked UI thread for 50-100ms
        // Solution: Pre-cached inventory = instant open (0ms latency)

        // Animate the transition for zoom effect
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            activeOverlay = .inventory
            showAsPanel = false // Full overlay mode
        }
    }

    func showCharacter() {
        activeOverlay = .character
        showAsPanel = false
    }

    func showEngraveSheet() {
        // CRITICAL: Update inventory BEFORE showing sheet so tool selector has access to wands
        updateInventory()
        showEngraveFlow = true
    }

    func showDiscoveriesSheet() {
        showDiscoveries = true
    }

    func showDungeonOverviewSheet() {
        showDungeonOverview = true
    }

    // MARK: - Spell Selection

    /// Refresh spell list from NetHack bridge
    func updateSpells() {
        SpellManager.shared.refreshSpells()
        spells = SpellManager.shared.spells
    }

    /// Show spell selection UI
    func showSpellSelectionSheet() {
        // Refresh spells before showing
        updateSpells()

        guard !spells.isEmpty else {
            showError = true
            errorMessage = "You don't know any spells yet."
            return
        }

        showSpellSelection = true
    }

    /// Handle spell selection from sheet
    func handleSpellSelected(_ spell: NetHackSpell) {
        showSpellSelection = false

        // If spell requires direction, show direction picker
        guard spell.requiresDirection else {
            // NODIR spell - cast immediately
            _ = SpellManager.shared.castSpellAtSelf(spell)
            return
        }

        // Show direction picker for directional spells
        selectedSpellForDirection = spell
        showDirectionPicker = true
    }

    /// Handle direction selected for spell
    func handleDirectionSelected(_ direction: Character) {
        guard let spell = selectedSpellForDirection else { return }

        showDirectionPicker = false
        selectedSpellForDirection = nil

        // Cast spell with direction
        _ = SpellManager.shared.castSpell(spell, direction: direction)
    }

    /// Cancel spell selection
    func cancelSpellSelection() {
        showSpellSelection = false
        showDirectionPicker = false
        selectedSpellForDirection = nil
    }

    // MARK: - Action Direction Picker

    /// Show direction picker for an action that requires direction
    func showActionDirectionPickerFor(_ action: NetHackAction) {
        selectedActionForDirection = action
        withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
            showActionDirectionPicker = true
        }
    }

    /// Handle direction selected for action
    func handleActionDirectionSelected(_ direction: Character) {
        guard let action = selectedActionForDirection else { return }

        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showActionDirectionPicker = false
        }

        let command = action.command

        // Check if this is item + direction flow (throw, zap)
        if let pendingItem = pendingItemForDirection, let pendingCommand = pendingCommandForDirection {
            // Item + direction flow: command + item + direction
            // NetHack expects: t<item><direction> or z<item><direction>
            print("[ACTION_DIRECTION] Item+Direction flow: '\(pendingCommand)\(pendingItem)\(direction)'")

            for char in pendingCommand {
                if let ascii = char.asciiValue {
                    ios_queue_input(Int8(ascii))
                }
            }
            ios_queue_input(Int8(pendingItem.asciiValue!))
            ios_queue_input(Int8(direction.asciiValue!))

            // Clear pending state
            pendingItemForDirection = nil
            pendingCommandForDirection = nil
            return
        }

        // Regular direction flow (kick, open, close, etc.)
        // Build command string based on prefix type
        if command.hasPrefix("#") {
                // Extended command: # + name + \n + direction
                let extCmd = String(command.dropFirst())
                ios_queue_input(Int8(Character("#").asciiValue!))
                for char in extCmd {
                    if let ascii = char.asciiValue {
                        ios_queue_input(Int8(ascii))
                    }
                }
                ios_queue_input(Int8(Character("\n").asciiValue!))
                ios_queue_input(Int8(direction.asciiValue!))
            } else if command.hasPrefix("M-") {
                // Meta command: ESC + char + direction
                let cmd = String(command.dropFirst(2))
                ios_queue_input(0x1b) // ESC
                if let cmdChar = cmd.first, let ascii = cmdChar.asciiValue {
                    ios_queue_input(Int8(ascii))
                }
                ios_queue_input(Int8(direction.asciiValue!))
            } else if command.hasPrefix("C-") {
                // Control command: control char + direction
                let cmd = String(command.dropFirst(2))
                if let char = cmd.first, let asciiValue = char.asciiValue {
                    let controlChar = Int8(Int(asciiValue) - 96)
                    ios_queue_input(controlChar)
                }
                ios_queue_input(Int8(direction.asciiValue!))
            } else {
                // Regular command: command + direction
                for char in command {
                    if let ascii = char.asciiValue {
                        ios_queue_input(Int8(ascii))
                    }
                }
                ios_queue_input(Int8(direction.asciiValue!))
            }

        print("[ACTION_DIRECTION] Sent command '\(command)' with direction '\(direction)'")

        // Clear state after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.selectedActionForDirection = nil
        }
    }

    /// Cancel action direction selection
    func cancelActionDirection() {
        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showActionDirectionPicker = false
        }
        selectedActionForDirection = nil
        // Clear pending item+direction state if any
        pendingItemForDirection = nil
        pendingCommandForDirection = nil
    }

    // MARK: - Item Selection

    /// Request item selection for a specific command type
    /// Updates inventory first, then shows selection sheet with appropriate filter
    func requestItemSelection(context: ItemSelectionContext) {
        print("[ITEM_SELECTION] Request for command '\(context.command)': \(context.prompt)")

        // CRITICAL: Request/Response pattern - update inventory synchronously
        updateInventory()

        // Set context and show sheet - ItemSelectionSheet handles empty state internally
        itemSelectionContext = context
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showItemSelection = true
        }
    }

    /// Queue a command string to NetHack, handling M-x, C-x, and #xxx prefixes
    private func queueCommandString(_ command: String) {
        // Meta command (M-x -> ESC + x)
        if command.hasPrefix("M-") {
            let cmd = String(command.dropFirst(2))
            ios_queue_input(27)  // ESC
            for char in cmd {
                if let ascii = char.asciiValue {
                    ios_queue_input(Int8(ascii))
                }
            }
            return
        }

        // Control command (C-x -> control character)
        if command.hasPrefix("C-") {
            let cmd = String(command.dropFirst(2))
            if let char = cmd.first, let asciiValue = char.asciiValue {
                ios_queue_input(Int8(Int(asciiValue) - 96))
            }
            return
        }

        // Extended command (#xxx -> # + xxx + newline)
        if command.hasPrefix("#") {
            let extCmd = String(command.dropFirst())
            ios_queue_input(Int8(Character("#").asciiValue!))
            for char in extCmd {
                if let ascii = char.asciiValue {
                    ios_queue_input(Int8(ascii))
                }
            }
            ios_queue_input(10)  // newline
            return
        }

        // Single character command
        for char in command {
            if let ascii = char.asciiValue {
                ios_queue_input(Int8(ascii))
            }
        }
    }

    /// User selected an item - check quantity and show picker if needed, or queue command directly
    func selectItem(_ invlet: Character) {
        guard let invletAscii = invlet.asciiValue,
              let context = itemSelectionContext else { return }

        // Find the selected item
        guard let selectedItem = items.first(where: { $0.invlet == invlet }) else {
            print("[ITEM_SELECTION] Item not found for invlet: \(invlet)")
            return
        }

        // Check if item is stacked and action supports quantity
        if context.supportsQuantity && selectedItem.quantity > 1 {
            // Show quantity picker for stacked items
            print("[ITEM_SELECTION] Showing quantity picker for '\(selectedItem.name)' (quantity: \(selectedItem.quantity))")

            // Create InventoryItem wrapper
            var inventoryItem = InventoryItem()
            inventoryItem.invlet = Int8(invletAscii)
            inventoryItem.quantity = Int32(selectedItem.quantity)

            // Allocate and copy name string
            selectedItem.name.withCString { cStr in
                let length = strlen(cStr) + 1
                let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(length))
                strcpy(buffer, cStr)
                inventoryItem.name = buffer
            }

            // Create NetHackAction from context
            let action = NetHackAction(
                name: context.prompt,
                command: context.command,
                icon: context.icon,
                category: .items,
                description: context.prompt,
                requiresDirection: false,
                requiresTarget: false,
                supportsQuantity: true
            )

            // Close item selection sheet first
            showItemSelection = false
            let savedCommand = context.command
            itemSelectionContext = nil

            // Show quantity picker
            showQuantityPicker(for: inventoryItem, action: action, maxQuantity: selectedItem.quantity) { [weak self] selectedQuantity in
                // Free name buffer
                if let namePtr = inventoryItem.name {
                    namePtr.deallocate()
                }

                guard let quantity = selectedQuantity else {
                    print("[ITEM_SELECTION] Quantity picker cancelled")
                    return
                }

                // Queue command with quantity: command + quantity digits + invlet
                print("[ITEM_SELECTION] Queuing command with quantity: '\(savedCommand)\(quantity)\(invlet)'")

                self?.queueCommandString(savedCommand)  // e.g., 'd' for drop

                // Queue quantity digits
                for digit in String(quantity) {
                    if let digitAscii = digit.asciiValue {
                        ios_queue_input(Int8(digitAscii))  // e.g., '2'
                    }
                }

                ios_queue_input(Int8(invletAscii))  // e.g., 'd' for item
            }
        } else {
            // Single item or no quantity support

            // Check if this action needs direction after item selection (throw, zap)
            if context.needsDirectionAfter {
                print("[ITEM_SELECTION] Action '\(context.command)' needs direction after item selection")

                // Store item and command for direction picker
                pendingItemForDirection = invlet
                pendingCommandForDirection = context.command

                // Create action for direction picker UI
                let action = NetHackAction(
                    name: context.prompt.replacingOccurrences(of: "What do you want to ", with: "").capitalized,
                    command: context.command,
                    icon: context.icon,
                    category: .combat,
                    description: context.prompt,
                    requiresDirection: true
                )

                // Close item selection and show direction picker
                withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                    showItemSelection = false
                    itemSelectionContext = nil
                }

                // Show direction picker after brief delay for smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.showActionDirectionPickerFor(action)
                }
                return
            }

            // Normal flow - queue command directly
            print("[ITEM_SELECTION] Queued atomic command: '\(context.command)\(invlet)'")

            queueCommandString(context.command)  // e.g., 'e' for eat, 'M-r' for rub
            ios_queue_input(Int8(invletAscii))   // e.g., 'g' for item

            // Close sheet
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                showItemSelection = false
                itemSelectionContext = nil
            }
        }
    }

    /// User cancelled item selection - just close the sheet
    func cancelItemSelection() {
        // CRITICAL FIX: No need to send ESC because command was never queued
        // With the new flow, action buttons show ItemSelectionSheet BEFORE queueing
        // NetHack never entered the command flow, so there's nothing to cancel
        // Only the atomic "command + item" is queued when user selects an item

        print("[ITEM_SELECTION] User cancelled - closing sheet without queueing")

        // Close sheet
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showItemSelection = false
            itemSelectionContext = nil
        }
    }

    /// User selected a ground item (from floor) - queue command + 'y' to accept floor prompt
    /// Works for eat command where NetHack asks "There is <item> here; eat it? [ynq]"
    func selectGroundItem(_ objectID: UInt32) {
        guard let context = itemSelectionContext else {
            print("[ITEM_SELECTION] No context for ground item selection")
            return
        }

        print("[ITEM_SELECTION] Selected ground item (objectID: \(objectID)) for command '\(context.command)'")

        // Queue the command (e.g., 'e' for eat)
        queueCommandString(context.command)

        // Queue 'y' to accept the floor item prompt
        // NetHack asks "There is <item> here; eat it? [ynq]" via floorfood()
        ios_queue_input(Int8(Character("y").asciiValue!))

        print("[ITEM_SELECTION] Queued '\(context.command)' + 'y' for ground item")

        // Close sheet
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showItemSelection = false
            itemSelectionContext = nil
        }
    }

    // MARK: - Quantity Picker

    /// Show quantity picker for an item action
    func showQuantityPicker(
        for item: InventoryItem,
        action: NetHackAction,
        maxQuantity: Int,
        completion: @escaping (Int?) -> Void
    ) {
        print("[GameOverlayManager] showQuantityPicker called")
        if let namePtr = item.name {
            print("  - item.name: \(String(cString: namePtr))")
        } else {
            print("  - item.name: (null)")
        }
        print("  - action.name: \(action.name)")
        print("  - maxQuantity: \(maxQuantity)")

        quantityPickerItem = item
        quantityPickerAction = action
        quantityPickerMaxQuantity = maxQuantity
        quantityPickerCompletion = completion

        print("[GameOverlayManager] State before animation:")
        print("  - showQuantityPicker: \(showQuantityPicker)")

        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showQuantityPicker = true
        }

        print("[GameOverlayManager] State after animation:")
        print("  - showQuantityPicker: \(showQuantityPicker)")
    }

    /// Hide quantity picker
    func hideQuantityPicker() {
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            showQuantityPicker = false
        }

        // Clear state after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.quantityPickerItem = nil
            self.quantityPickerAction = nil
            self.quantityPickerCompletion = nil
        }
    }

    // MARK: - Item to Action Conversion
    func createActionFromItem(_ item: NetHackItem) -> NetHackAction? {
        switch item.category {
        case .weapons:
            return NetHackAction(
                name: "Wield \(item.name)",
                command: "w",
                icon: "hand.raised.fill",
                category: .items,
                description: "Wield \(item.displayName)"
            )
        case .armor:
            return NetHackAction(
                name: "Wear \(item.name)",
                command: "W",
                icon: "tshirt.fill",
                category: .items,
                description: "Wear \(item.displayName)"
            )
        case .potions:
            return NetHackAction(
                name: "Quaff \(item.name)",
                command: "q",
                icon: "drop.fill",
                category: .items,
                description: "Drink \(item.displayName)"
            )
        case .scrolls:
            return NetHackAction(
                name: "Read \(item.name)",
                command: "r",
                icon: "scroll.fill",
                category: .items,
                description: "Read \(item.displayName)"
            )
        case .food:
            return NetHackAction(
                name: "Eat \(item.name)",
                command: "e",
                icon: "fork.knife",
                category: .items,
                description: "Eat \(item.displayName)"
            )
        case .wands:
            return NetHackAction(
                name: "Zap \(item.name)",
                command: "z",
                icon: "wand.and.stars",
                category: .items,
                description: "Zap \(item.displayName)"
            )
        case .tools:
            return NetHackAction(
                name: "Apply \(item.name)",
                command: "a",
                icon: "wrench.and.screwdriver.fill",
                category: .items,
                description: "Apply \(item.displayName)"
            )
        default:
            return nil
        }
    }

    // MARK: - Container Transfer

    /// Show container transfer UI for floor containers at player position
    /// If multiple containers present, shows picker first
    /// If single container, goes directly to transfer view
    func showContainerTransferUI() {
        print("[CONTAINER] Checking for floor containers...")

        // Get floor containers from service
        let containers = ContainerTransferService.shared.getFloorContainers()

        guard !containers.isEmpty else {
            showError = true
            errorMessage = "No containers here to open"
            return
        }

        // Filter out locked containers (can still show them but disabled)
        floorContainers = containers

        // If single unlocked container, go directly to transfer
        let unlockedContainers = containers.filter { !$0.isLocked }

        if unlockedContainers.count == 1 {
            // Single container - open directly
            selectedFloorContainer = unlockedContainers.first
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                showContainerTransfer = true
            }
        } else if unlockedContainers.count > 1 {
            // Multiple containers - show picker
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                showContainerPicker = true
            }
        }

        // All containers are locked - fall back to NetHack's #loot command
        // This will show "It is locked" and identify the container
        guard !unlockedContainers.isEmpty else {
            print("[CONTAINER] All containers locked - sending #loot to NetHack")
            ios_queue_input(Int8(Character("#").asciiValue!))
            for char in "loot" {
                ios_queue_input(Int8(char.asciiValue!))
            }
            ios_queue_input(Int8(Character("\n").asciiValue!))
            return
        }
    }

    /// Handle container selection from picker
    func handleContainerSelected(_ container: FloorContainerInfo) {
        selectedFloorContainer = container
        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showContainerPicker = false
        }

        // Brief delay for smooth transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                self.showContainerTransfer = true
            }
        }
    }

    /// Close container transfer UI
    func closeContainerTransfer() {
        withAnimation(.spring(duration: 0.2, bounce: 0.05)) {
            showContainerTransfer = false
            showContainerPicker = false
        }

        // Clear state after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.selectedFloorContainer = nil
            self.floorContainers = []
        }
    }
}