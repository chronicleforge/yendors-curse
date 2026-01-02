import Foundation

// MARK: - Command Handler
// Centralized command execution replacing else-if cascades in ActionBarManager and GestureActionWheel
// Pattern: Dictionary lookup instead of cascading conditionals

/// Result of command execution
enum CommandResult {
    case handled          // Command was fully handled
    case sendToGame       // Send command string to game
    case requiresDirection // Command needs direction input
    case requiresTarget   // Command needs target selection
}

/// Centralized command handler for NetHack actions
@MainActor
struct CommandHandler {

    // MARK: - Handler Types

    /// Handler closure that executes a command
    typealias Handler = (NetHackGameManager, GameOverlayManager) -> CommandResult

    // MARK: - Command Registry

    /// Commands that show item selection UI
    private static let itemSelectionCommands: [String: (GameOverlayManager) -> Void] = [
        "e": { $0.requestItemSelection(context: .eat()) },
        "q": { $0.requestItemSelection(context: .quaff()) },
        "W": { $0.requestItemSelection(context: .wear()) },
        "w": { $0.requestItemSelection(context: .wield()) },
        "z": { $0.requestItemSelection(context: .zap()) },
        "a": { $0.requestItemSelection(context: .apply()) },
        "r": { $0.requestItemSelection(context: .read()) },
        "d": { $0.requestItemSelection(context: .drop()) },
        "R": { $0.requestItemSelection(context: .remove()) },
        "T": { $0.requestItemSelection(context: .takeOff()) },
        "P": { $0.requestItemSelection(context: .putOn()) },
        "Q": { $0.requestItemSelection(context: .quiver()) },
        "t": { $0.requestItemSelection(context: .throwItem()) },
        "#rub": { $0.requestItemSelection(context: .rub()) }
    ]

    /// Commands that show overlay UI
    /// NOTE: C-x (Attributes) removed - let NetHack show enlightenment menu via Menu system
    private static let overlayCommands: [String: (GameOverlayManager) -> Void] = [
        "i": { $0.showInventory() },
        "E": { $0.showEngraveSheet() },
        "\\": { $0.showDiscoveriesSheet() },
        "Z": { $0.showSpellSelectionSheet() },
        "C-o": { $0.showDungeonOverviewSheet() },
        "M-l": { $0.showLootOptionsPicker() },  // Loot - show picker BEFORE sending command
        "#enhance": { $0.showSkillEnhanceSheet() },  // Skills - show sheet BEFORE sending command
        "#chronicle": { $0.showChronicleSheet() },  // Chronicle - native Swift view
        "M-C": { $0.showConductSheet() }  // Conduct - native Swift view
    ]

    /// Travel commands mapped to GameManager methods
    private static let travelActionIDs: [String: (NetHackGameManager) -> Void] = [
        "travel_stairs_up": { $0.travelToStairsUp() },
        "travel_stairs_down": { $0.travelToStairsDown() },
        "travel_altar": { $0.travelToAltar() },
        "travel_fountain": { $0.travelToFountain() }
    ]

    // MARK: - Public API

    /// Execute an action through centralized command handling
    /// - Parameters:
    ///   - action: The NetHack action to execute
    ///   - gameManager: Game manager for sending commands
    ///   - overlayManager: Overlay manager for UI presentation
    /// - Returns: Result indicating how the command was handled
    static func execute(
        action: NetHackAction,
        gameManager: NetHackGameManager,
        overlayManager: GameOverlayManager
    ) -> CommandResult {
        let command = action.command
        let actionID = action.id

        // SLOG: Action dispatch entry point
        print("[ACTION_TRIGGERED] CommandHandler - Action: '\(action.name)' Command: '\(command)'")

        // 0a. Special iOS action: Grant wizard powers at runtime
        if actionID == "ios_grant_wizard" {
            print("[CommandHandler] 🧙 Granting wizard powers at runtime")
            NetHackBridge.shared.enableWizardMode()
            // Show confirmation message via game message system
            gameManager.sendCommand(":")  // Look command to trigger message refresh
            return .handled
        }

        // 0b. Environment test teleports (for testing visual theming)
        if actionID.hasPrefix("ios_test_") {
            let testTeleports: [String: (dungeon: String, level: String)] = [
                "ios_test_mines": ("mines", "3"),
                "ios_test_sokoban": ("sokoban", "1"),
                "ios_test_gehennom": ("gehennom", "1"),
                "ios_test_vlad": ("vlad", "1"),
                "ios_test_astral": ("astral", "")
            ]

            if let teleport = testTeleports[actionID] {
                print("[CommandHandler] 🧪 Test teleport to \(teleport.dungeon)")
                let bridge = NetHackBridge.shared

                // Send #wizlevelport command (M-V = Meta-V for level teleport)
                bridge.sendCommand("#wizlevelport\n")

                // Small delay then send dungeon name + newline
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    bridge.sendCommand("\(teleport.dungeon)\n")
                }

                // If level specified, send it after another delay
                if !teleport.level.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                        bridge.sendCommand("\(teleport.level)\n")
                    }
                }
                return .handled
            }
        }

        // 0c. Check for escape warning (climb up on level 1 without amulet)
        // Must be checked BEFORE sending "<" command to prevent accidental game ending
        if command == "<" {
            if NetHackBridge.shared.checkEscapeWarning() {
                print("[CommandHandler] Escape warning triggered - showing confirmation sheet")
                overlayManager.showEscapeWarningSheet()
                return .handled
            }
        }

        // 1. Check travel actions by ID
        if let travelHandler = travelActionIDs[actionID] {
            travelHandler(gameManager)
            return .handled
        }

        // 2. Check overlay commands
        if let overlayHandler = overlayCommands[command] {
            overlayHandler(overlayManager)
            return .handled
        }

        // 3. Check item selection commands
        if let itemHandler = itemSelectionCommands[command] {
            // Special case: Quaff ('q') - check if player is on fountain/sink
            // NetHack asks "Drink from fountain?" BEFORE item selection
            // We must let NetHack handle this flow, not intercept it
            if command == "q" {
                if let terrainChar = NetHackBridge.shared.getTerrainUnderPlayer() {
                    // Fountain = '{', Sink = '#'
                    if terrainChar == "{" || terrainChar == "#" {
                        print("[CommandHandler] Quaff on fountain/sink - not intercepting, letting NetHack ask about terrain first")
                        sendCommand(command, gameManager: gameManager)
                        return .sendToGame
                    }
                }
            }

            print("[ACTION_TRIGGERED] -> Showing item selection for '\(action.name)'")
            itemHandler(overlayManager)
            return .handled
        }

        // 4. Check if action requires direction BEFORE sending command
        // Direction picker will send command + direction together
        if action.requiresDirection {
            print("[CommandHandler] Action '\(action.name)' requires direction - deferring to picker")
            return .requiresDirection
        }

        // 5. Check if action requires target BEFORE sending command
        if action.requiresTarget {
            print("[CommandHandler] Action '\(action.name)' requires target - deferring to picker")
            return .requiresTarget
        }

        // 6. Send command to game engine (only for actions that don't need direction/target)
        sendCommand(command, gameManager: gameManager)
        return .sendToGame
    }

    // MARK: - Command String Processing

    /// Send a command string to the game, handling special prefixes
    /// - Parameters:
    ///   - command: Command string (may include #, M-, C- prefixes)
    ///   - gameManager: Game manager to send command through
    private static func sendCommand(_ command: String, gameManager: NetHackGameManager) {
        // Extended command (#command)
        // Format: "#" triggers doextcmd, then "name\n" is read by ios_get_ext_cmd
        if command.hasPrefix("#") {
            let extCmd = String(command.dropFirst())  // Remove '#'
            gameManager.sendCommand("#")              // Trigger extended command mode
            gameManager.sendCommand(extCmd + "\n")    // Send command name + Enter
            return
        }

        // Meta command (M-x -> high bit set: 0x80 | x)
        // NetHack defines M(c) as (0x80 | c), NOT ESC + c
        // CRITICAL: Must use sendRawByte to avoid UTF-8 encoding!
        // Character 0xC1 (193) would become 0xC3 0x81 (2 bytes) if sent as String
        if command.hasPrefix("M-") {
            let cmd = String(command.dropFirst(2))
            guard let char = cmd.first,
                  let asciiValue = char.asciiValue else { return }
            let metaByte = UInt8(asciiValue | 0x80)
            NetHackBridge.shared.sendRawByte(metaByte)
            return
        }

        // Control command (C-x -> control character)
        // CRITICAL: Must use sendRawByte like M-x to avoid String encoding issues!
        // Control chars (ASCII 1-31) don't survive String conversion reliably
        if command.hasPrefix("C-") {
            let cmd = String(command.dropFirst(2))
            guard let char = cmd.first,
                  let asciiValue = char.asciiValue else { return }
            let controlByte = UInt8(Int(asciiValue) - 96)  // 'x' (120) - 96 = 24 = Ctrl-X
            NetHackBridge.shared.sendRawByte(controlByte)
            return
        }

        // Regular command
        gameManager.sendCommand(command)
    }
}
