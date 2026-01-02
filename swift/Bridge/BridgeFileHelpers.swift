import Foundation

// MARK: - C-Callable File Loading Helpers
// These standalone functions are called from C code via @_cdecl
// They handle loading Lua files and data files from the iOS bundle/documents

// MARK: - Raw File Data Structure

/// Structure to match C side for raw file data
@objc
class IOSRawFileData: NSObject {
    var data: UnsafeMutablePointer<UInt8>?
    var size: Int

    init(data: UnsafeMutablePointer<UInt8>?, size: Int) {
        self.data = data
        self.size = size
    }
}

// MARK: - Documents Path for C Code

/// Static storage for documents path (lives for app lifetime)
private var documentsPathStorage: UnsafeMutablePointer<CChar>?

/// Returns the Documents/NetHack path as a C string
/// Used by structured logging to write slog.jsonl
@_cdecl("ios_get_documents_path_c")
public func ios_get_documents_path_c() -> UnsafePointer<CChar>? {
    // Return cached path if available
    if let existing = documentsPathStorage {
        return UnsafePointer(existing)
    }

    guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        return nil
    }
    let nethackPath = documentsURL.appendingPathComponent("NetHack").path

    // Ensure directory exists
    try? FileManager.default.createDirectory(atPath: nethackPath, withIntermediateDirectories: true)

    // Store in static memory (strdup allocates permanent storage)
    documentsPathStorage = strdup(nethackPath)
    return UnsafePointer(documentsPathStorage)
}

// MARK: - File Path Resolution

/// 5-location search strategy for finding files:
/// 1. Documents/NetHack/Data/ (writable, runtime-copied)
/// 2. Bundle direct path (bypasses indexing)
/// 3. Bundle data_files/ subfolder (for bogusmon, epitaph, engrave)
/// 4. Bundle lua_resources/ subfolder (for Lua files)
/// 5. Bundle indexed resources (fallback)
private func findFilePath(_ filename: String) -> String? {
    // Location 1: Documents/NetHack/Data/
    if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
        let nethackDataPath = documentsURL.appendingPathComponent("NetHack/Data").appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: nethackDataPath.path) {
            return nethackDataPath.path
        }
    }

    // Location 2: Bundle direct path
    let bundleDirectPath = Bundle.main.bundlePath + "/" + filename
    if FileManager.default.fileExists(atPath: bundleDirectPath) {
        return bundleDirectPath
    }

    // Location 3: Bundle data_files/ subfolder (bogusmon, epitaph, engrave)
    let dataFilesPath = Bundle.main.bundlePath + "/data_files/" + filename
    if FileManager.default.fileExists(atPath: dataFilesPath) {
        return dataFilesPath
    }

    // Location 4: Bundle lua_resources/ subfolder
    let luaResourcesPath = Bundle.main.bundlePath + "/lua_resources/" + filename
    if FileManager.default.fileExists(atPath: luaResourcesPath) {
        return luaResourcesPath
    }

    // Location 5: Bundle indexed resources
    if filename.hasSuffix(".lua") {
        let baseName = filename.replacingOccurrences(of: ".lua", with: "")
        return Bundle.main.path(forResource: baseName, ofType: "lua")
    }
    return Bundle.main.path(forResource: filename, ofType: nil)
}

// MARK: - Raw Lua File Loading (Binary)

/// Load Lua file as raw bytes - NO string conversion
@_cdecl("ios_swift_load_raw_lua_file")
public func ios_swift_load_raw_lua_file(_ filename: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let filename = filename else {
        print("[Swift RAW] ERROR: NULL filename")
        return nil
    }

    let fileStr = String(cString: filename).trimmingCharacters(in: .whitespaces)
    print("[Swift RAW] Looking for Lua file: \(fileStr)")

    guard let path = findFilePath(fileStr) else {
        print("[Swift RAW] ❌ File not found: \(fileStr)")
        return nil
    }
    print("[Swift RAW] ✓ Found: \(path)")

    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        print("[Swift RAW] Loaded \(fileStr): \(data.count) raw bytes")

        let fileData = UnsafeMutablePointer<(UnsafeMutablePointer<UInt8>?, Int)>.allocate(capacity: 1)
        let rawBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        data.copyBytes(to: rawBytes, count: data.count)

        fileData.pointee.0 = rawBytes
        fileData.pointee.1 = data.count

        return UnsafeMutableRawPointer(fileData)
    } catch {
        print("[Swift RAW] Error loading \(fileStr): \(error)")
        return nil
    }
}

/// Free memory allocated by ios_swift_load_raw_lua_file
@_cdecl("ios_swift_free_raw_file")
public func ios_swift_free_raw_file(_ fileData: UnsafeMutableRawPointer?) {
    guard let fileData = fileData else { return }

    let typed = fileData.assumingMemoryBound(to: (UnsafeMutablePointer<UInt8>?, Int).self)
    if let dataPtr = typed.pointee.0 {
        dataPtr.deallocate()
    }
    typed.deallocate()
}

// MARK: - String Lua File Loading

/// Load Lua file as string with encoding fallbacks
@_cdecl("ios_swift_load_lua_file")
public func ios_swift_load_lua_file(_ filename: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let filename = filename else {
        print("[Swift] ERROR: NULL filename")
        return nil
    }

    let fileStr = String(cString: filename).trimmingCharacters(in: .whitespaces)
    print("[Swift] Looking for Lua file: \(fileStr)")

    guard let path = findFilePath(fileStr) else {
        print("[Swift] ❌ File not found: \(fileStr)")
        return nil
    }
    print("[Swift] ✓ Found: \(path)")

    return loadFileAsString(path: path, filename: fileStr)
}

// MARK: - Data File Loading

/// Load any data file as string
@_cdecl("ios_swift_load_data_file")
public func ios_swift_load_data_file(_ filename: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let filename = filename else { return nil }

    let fileStr = String(cString: filename).trimmingCharacters(in: .whitespaces)
    print("[Swift Data] Looking for: \(fileStr)")

    guard let path = findFilePath(fileStr) else {
        print("[Swift Data] ❌ File not found: \(fileStr)")
        return nil
    }
    print("[Swift Data] ✓ Found: \(path)")

    return loadFileAsString(path: path, filename: fileStr)
}

// MARK: - File Existence Check

/// Check if file exists in any of the search locations
@_cdecl("ios_swift_file_exists")
public func ios_swift_file_exists(_ filename: UnsafePointer<CChar>?) -> Int32 {
    guard let filename = filename else { return 0 }

    let fileStr = String(cString: filename).trimmingCharacters(in: .whitespaces)

    if findFilePath(fileStr) != nil {
        print("[Swift Exists] ✓ Found: \(fileStr)")
        return 1
    }

    print("[Swift Exists] ❌ Not found: \(fileStr)")
    return 0
}

// MARK: - Helper Functions

/// Load file with encoding fallbacks (UTF-8 → ASCII → ISO Latin-1 → lossy UTF-8)
private func loadFileAsString(path: String, filename: String) -> UnsafeMutablePointer<CChar>? {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var content: String?

        // Try encodings in order
        content = String(data: data, encoding: .utf8)
        if content == nil {
            print("[Swift] UTF-8 failed for \(filename), trying ASCII...")
            content = String(data: data, encoding: .ascii)
        }
        if content == nil {
            print("[Swift] ASCII failed for \(filename), trying ISO Latin-1...")
            content = String(data: data, encoding: .isoLatin1)
        }
        if content == nil {
            print("[Swift] All encodings failed for \(filename), using lossy UTF-8...")
            content = String(decoding: data, as: UTF8.self)
        }

        guard let finalContent = content else {
            print("[Swift] ERROR: Could not decode \(filename)")
            return nil
        }

        print("[Swift] Loaded \(filename): \(finalContent.count) chars")
        return strdup(finalContent)
    } catch {
        print("[Swift] Error loading \(filename): \(error)")
        return nil
    }
}

// MARK: - Death Animation Callback

/// C function pointer type for death animation callback
typealias DeathAnimationCallback = @convention(c) () -> Void

/// C function to register the callback - imported from dylib
@_silgen_name("ios_set_death_animation_callback")
func ios_set_death_animation_callback(_ callback: DeathAnimationCallback?)

/// The actual callback function - must be @convention(c) compatible
private let deathAnimationHandler: DeathAnimationCallback = {
    print("[Swift Death] ☠️ EARLY DEATH DETECTED - Starting animation IMMEDIATELY")

    // Post notification to main thread to start death animation
    // This runs IN PARALLEL with C-side death data collection
    DispatchQueue.main.async {
        print("[Swift Death] ON MAIN THREAD - Posting DeathAnimationStart notification")
        NotificationCenter.default.post(
            name: Notification.Name("NetHackDeathAnimationStart"),
            object: nil
        )
        print("[Swift Death] DeathAnimationStart notification POSTED")
    }
}

/// Call this at app startup to register the death animation callback
/// MUST be called AFTER dylib is loaded
public func registerDeathAnimationCallback() {
    print("[Swift Death] Registering death animation callback with C...")
    ios_set_death_animation_callback(deathAnimationHandler)
    print("[Swift Death] ✓ Callback registered")
}
