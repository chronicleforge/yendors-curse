import Foundation

/// Runtime dynamic library loader for NetHack
///
/// **PURPOSE**: Load/unload libnethack.dylib at runtime to automatically reset ALL static state
/// between game sessions without manual pointer tracking.
///
/// **BENEFITS**:
/// - `dlclose()` unmaps entire dylib → automatic cleanup of ALL global/static state
/// - `dlopen()` loads fresh copy → pristine game state guaranteed
/// - Eliminates "persisting chain" bug class (timer_base, stairs, gamelog, etc.)
/// - Future-proof: any new NetHack globals automatically reset
///
/// **LIFECYCLE**:
/// ```
/// Game Start:  dylib.load()  → dlopen + lazy symbol resolution
/// Game Exit:   dylib.unload() → dlclose → ALL state cleared
/// New Game:    dylib.load()  → fresh dylib with pristine state
/// ```
///
/// **THREAD SAFETY**:
/// - NOT @MainActor to allow game thread access
/// - Internal synchronization via queue
/// - All methods are thread-safe
final class DylibLoader {

    // MARK: - Thread Safety

    /// Serial queue for thread-safe access to dylib handle and symbol cache
    private let queue = DispatchQueue(label: "com.nethack.dylibloader", qos: .userInitiated)

    // MARK: - Types

    /// Error types for dylib loading operations
    enum LoadError: Error, CustomStringConvertible {
        case dylibNotFound(path: String)
        case loadFailed(path: String, error: String)
        case symbolNotFound(symbol: String)
        case alreadyLoaded
        case notLoaded

        var description: String {
            switch self {
            case .dylibNotFound(let path):
                return "Dylib not found at path: \(path)"
            case .loadFailed(let path, let error):
                return "Failed to load dylib at \(path): \(error)"
            case .symbolNotFound(let symbol):
                return "Symbol not found: \(symbol)"
            case .alreadyLoaded:
                return "Dylib is already loaded"
            case .notLoaded:
                return "Dylib is not loaded"
            }
        }
    }

    // MARK: - Properties

    /// dlopen handle (nil when unloaded)
    private var handle: UnsafeMutableRawPointer?

    /// Symbol cache (lazy loading - only resolve on first use)
    /// Key: symbol name, Value: function pointer
    private var symbolCache: [String: UnsafeMutableRawPointer] = [:]

    /// Path to the dylib in app bundle
    private let dylibPath: String

    /// Is the dylib currently loaded?
    var isLoaded: Bool {
        queue.sync { handle != nil }
    }

    // MARK: - Initialization

    init() {
        // Get path to dylib in app bundle's Frameworks directory
        // The dylib will be embedded there by Xcode Copy Phase (NOT linked!)
        if let bundlePath = Bundle.main.bundlePath as String? {
            self.dylibPath = "\(bundlePath)/Frameworks/libnethack.dylib"
        } else {
            // Fallback (should never happen)
            self.dylibPath = "libnethack.dylib"
        }

        print("[DylibLoader] Initialized with path: \(dylibPath)")
    }

    deinit {
        // Ensure dylib is unloaded on dealloc
        // Note: deinit is nonisolated, so we must use nonisolated-unsafe access
        if let handle = handle {
            print("[DylibLoader] deinit - unloading dylib...")
            dlclose(handle)
        }
    }

    // MARK: - Load/Unload

    /// Load the dylib using dlopen
    ///
    /// - Returns: true if loaded successfully, false if already loaded
    /// - Throws: LoadError if dylib not found or dlopen fails
    @discardableResult
    func load() throws -> Bool {
        try queue.sync {
            // Already loaded?
            guard handle == nil else {
                print("[DylibLoader] ⚠️ Dylib already loaded")
                return false
            }

            // Verify dylib exists
            guard FileManager.default.fileExists(atPath: dylibPath) else {
                throw LoadError.dylibNotFound(path: dylibPath)
            }

            print("[DylibLoader] Loading dylib from: \(dylibPath)")

            // Load dylib with RTLD_NOW (resolve all symbols immediately for error detection)
            // and RTLD_LOCAL (symbols not available for other dylibs - encapsulation)
            handle = dlopen(dylibPath, RTLD_NOW | RTLD_LOCAL)

            guard let handle = handle else {
                let errorMsg = String(cString: dlerror())
                throw LoadError.loadFailed(path: dylibPath, error: errorMsg)
            }

            print("[DylibLoader] ✅ Dylib loaded successfully (handle: \(handle))")

            // Clear symbol cache (fresh load = fresh symbols)
            symbolCache.removeAll()

            return true
        }
    }

    /// Unload the dylib using dlclose
    ///
    /// **CRITICAL**: This unmaps the entire dylib from memory, clearing ALL static/global state!
    /// This is the automatic cleanup mechanism that eliminates manual pointer tracking.
    func unload() {
        queue.sync {
            guard let handle = handle else {
                print("[DylibLoader] ⚠️ Dylib not loaded, nothing to unload")
                return
            }

            print("[DylibLoader] Unloading dylib...")

            // Unload dylib - this UNMAPS entire address space, clearing ALL static state!
            let result = dlclose(handle)
            if result != 0 {
                let errorMsg = String(cString: dlerror())
                print("[DylibLoader] ⚠️ dlclose failed: \(errorMsg)")
            } else {
                print("[DylibLoader] ✅ Dylib unloaded - ALL static state cleared!")
            }

            // Clear handle and symbol cache
            self.handle = nil
            symbolCache.removeAll()
        }
    }

    // MARK: - Symbol Resolution

    /// Resolve a symbol using dlsym (with caching)
    ///
    /// Symbols are resolved lazily - only on first use. This makes initial dlopen faster.
    ///
    /// - Parameter symbolName: Name of the exported symbol (e.g., "nethack_real_init")
    /// - Returns: Function pointer to the symbol
    /// - Throws: LoadError if dylib not loaded or symbol not found
    func resolveSymbol(_ symbolName: String) throws -> UnsafeMutableRawPointer {
        try queue.sync {
            // Dylib loaded?
            guard let handle = handle else {
                throw LoadError.notLoaded
            }

            // Already cached?
            if let cachedSymbol = symbolCache[symbolName] {
                return cachedSymbol
            }

            // Resolve symbol with dlsym
            guard let symbol = dlsym(handle, symbolName) else {
                let errorMsg = String(cString: dlerror())
                print("[DylibLoader] ❌ Symbol not found: \(symbolName) - \(errorMsg)")
                throw LoadError.symbolNotFound(symbol: symbolName)
            }

            // Cache for future calls
            symbolCache[symbolName] = symbol
            print("[DylibLoader] ✓ Resolved symbol: \(symbolName)")

            return symbol
        }
    }

    /// Resolve a symbol and cast to specific function type (type-safe wrapper)
    ///
    /// Example usage:
    /// ```swift
    /// let nethack_init: @convention(c) () -> Void = try dylib.resolveFunction("nethack_real_init")
    /// nethack_init()
    /// ```
    func resolveFunction<T>(_ symbolName: String) throws -> T {
        let symbol = try resolveSymbol(symbolName)
        return unsafeBitCast(symbol, to: T.self)
    }

    // MARK: - Diagnostics

    /// Get loading statistics for debugging
    func getStats() -> String {
        """
        [DylibLoader Stats]
          Loaded: \(isLoaded)
          Path: \(dylibPath)
          Handle: \(handle.map { String(describing: $0) } ?? "nil")
          Cached Symbols: \(symbolCache.count)
        """
    }
}

// MARK: - Convenience Extensions

extension DylibLoader {

    /// Reload the dylib (unload + load)
    ///
    /// **USE CASE**: Between game sessions to reset ALL static state
    ///
    /// Example:
    /// ```swift
    /// // Game ended - unload to clear all state
    /// dylib.unload()
    ///
    /// // Starting new game - reload fresh dylib
    /// try dylib.reload()
    /// ```
    func reload() throws {
        unload()
        try load()
    }
}
