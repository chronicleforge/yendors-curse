import Foundation

// MARK: - Log Level

enum LogLevel: Int, Comparable, CaseIterable {
    case verbose = 0  // Everything
    case debug = 1    // Development details
    case info = 2     // Normal operation
    case warning = 3  // Potential issues
    case error = 4    // Errors
    case none = 5     // Silence all

    var prefix: String {
        switch self {
        case .verbose: return "[VERBOSE]"
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        case .none: return ""
        }
    }

    var emoji: String {
        switch self {
        case .verbose: return ""
        case .debug: return ""
        case .info: return ""
        case .warning: return "⚠️"
        case .error: return "❌"
        case .none: return ""
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log Category

enum LogCategory: String, CaseIterable {
    // High-noise categories (off by default)
    case render = "RENDER"        // SceneKit tile updates
    case mapUpdate = "MAP"        // Map change notifications
    case input = "INPUT"          // Input queue operations
    case sceneKit = "SCENEKIT"    // SceneKit node operations
    case synch = "SYNCH"          // wait_synch calls
    case perf = "PERF"            // Performance metrics

    // Medium-noise categories
    case bridge = "BRIDGE"        // C/Swift bridge
    case winproc = "WINPROC"      // Window procedure calls
    case menu = "MENU"            // Menu operations
    case filesys = "FILESYS"      // File system operations

    // Low-noise categories (on by default)
    case game = "GAME"            // Game state changes
    case death = "DEATH"          // Death handling
    case save = "SAVE"            // Save/Load operations
    case lifecycle = "LIFECYCLE"  // App/dylib lifecycle
    case character = "CHAR"       // Character creation

    // Always shown
    case error = "ERROR"          // Errors (always on)
    case critical = "CRITICAL"    // Critical issues (always on)

    var defaultEnabled: Bool {
        switch self {
        // High-noise: OFF by default
        case .render, .mapUpdate, .input, .sceneKit, .synch, .perf:
            return false
        // Everything else: ON by default
        default:
            return true
        }
    }
}

// MARK: - Logger

final class Log {
    static let shared = Log()

    private var enabledCategories: Set<LogCategory>
    private var minLevel: LogLevel
    private let queue = DispatchQueue(label: "com.nethack.logger", qos: .utility)

    private init() {
        // Load settings from UserDefaults or use defaults
        if let savedCategories = UserDefaults.standard.array(forKey: "LogEnabledCategories") as? [String] {
            enabledCategories = Set(savedCategories.compactMap { LogCategory(rawValue: $0) })
        } else {
            // Default: enable all except high-noise
            enabledCategories = Set(LogCategory.allCases.filter { $0.defaultEnabled })
        }

        minLevel = LogLevel(rawValue: UserDefaults.standard.integer(forKey: "LogMinLevel")) ?? .info
    }

    // MARK: - Configuration

    static func setLevel(_ level: LogLevel) {
        shared.minLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: "LogMinLevel")
    }

    static func enable(_ category: LogCategory) {
        shared.enabledCategories.insert(category)
        saveCategories()
    }

    static func disable(_ category: LogCategory) {
        shared.enabledCategories.remove(category)
        saveCategories()
    }

    static func toggle(_ category: LogCategory) {
        if shared.enabledCategories.contains(category) {
            shared.enabledCategories.remove(category)
        } else {
            shared.enabledCategories.insert(category)
        }
        saveCategories()
    }

    static func enableAll() {
        shared.enabledCategories = Set(LogCategory.allCases)
        saveCategories()
    }

    static func disableAll() {
        shared.enabledCategories = [.error, .critical]  // Keep errors
        saveCategories()
    }

    static func resetToDefaults() {
        shared.enabledCategories = Set(LogCategory.allCases.filter { $0.defaultEnabled })
        shared.minLevel = .info
        saveCategories()
        UserDefaults.standard.set(LogLevel.info.rawValue, forKey: "LogMinLevel")
    }

    private static func saveCategories() {
        let categoryStrings = shared.enabledCategories.map { $0.rawValue }
        UserDefaults.standard.set(categoryStrings, forKey: "LogEnabledCategories")
    }

    // MARK: - Logging Methods

    static func verbose(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(level: .verbose, category: category, message: message())
    }

    static func debug(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(level: .debug, category: category, message: message())
    }

    static func info(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(level: .info, category: category, message: message())
    }

    static func warning(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(level: .warning, category: category, message: message())
    }

    static func error(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(level: .error, category: category, message: message())
    }

    // Convenience for errors without category
    static func error(_ message: @autoclosure () -> String) {
        log(level: .error, category: .error, message: message())
    }

    private static func log(level: LogLevel, category: LogCategory, message: String) {
        // Always show errors and critical
        guard category == .error || category == .critical ||
              (level >= shared.minLevel && shared.enabledCategories.contains(category)) else {
            return
        }

        let output = "\(level.emoji)[\(category.rawValue)] \(message)"

        // Print synchronously for now (can be made async if needed)
        print(output)
    }

    // MARK: - Status

    static func printStatus() {
        print("========================================")
        print("LOGGER STATUS")
        print("========================================")
        print("Min Level: \(shared.minLevel)")
        print("Enabled Categories:")
        for cat in LogCategory.allCases {
            let status = shared.enabledCategories.contains(cat) ? "ON" : "OFF"
            print("  \(cat.rawValue): \(status)")
        }
        print("========================================")
    }
}

// MARK: - C Bridge Logging (for use from C code via Swift callbacks)

@_cdecl("swift_log_verbose")
func swift_log_verbose(_ category: UnsafePointer<CChar>, _ message: UnsafePointer<CChar>) {
    let cat = String(cString: category)
    let msg = String(cString: message)
    if let logCat = LogCategory(rawValue: cat) {
        Log.verbose(logCat, msg)
    } else {
        Log.verbose(.bridge, "[\(cat)] \(msg)")
    }
}

@_cdecl("swift_log_debug")
func swift_log_debug(_ category: UnsafePointer<CChar>, _ message: UnsafePointer<CChar>) {
    let cat = String(cString: category)
    let msg = String(cString: message)
    if let logCat = LogCategory(rawValue: cat) {
        Log.debug(logCat, msg)
    } else {
        Log.debug(.bridge, "[\(cat)] \(msg)")
    }
}

@_cdecl("swift_log_info")
func swift_log_info(_ category: UnsafePointer<CChar>, _ message: UnsafePointer<CChar>) {
    let cat = String(cString: category)
    let msg = String(cString: message)
    if let logCat = LogCategory(rawValue: cat) {
        Log.info(logCat, msg)
    } else {
        Log.info(.bridge, "[\(cat)] \(msg)")
    }
}

@_cdecl("swift_log_warning")
func swift_log_warning(_ category: UnsafePointer<CChar>, _ message: UnsafePointer<CChar>) {
    let cat = String(cString: category)
    let msg = String(cString: message)
    if let logCat = LogCategory(rawValue: cat) {
        Log.warning(logCat, msg)
    } else {
        Log.warning(.bridge, "[\(cat)] \(msg)")
    }
}

@_cdecl("swift_log_error")
func swift_log_error(_ category: UnsafePointer<CChar>, _ message: UnsafePointer<CChar>) {
    let cat = String(cString: category)
    let msg = String(cString: message)
    if let logCat = LogCategory(rawValue: cat) {
        Log.error(logCat, msg)
    } else {
        Log.error(.bridge, "[\(cat)] \(msg)")
    }
}
