import Foundation

/// Shared utility for character name sanitization
/// MUST match C implementation in ios_character_save.c:sanitize_character_name()
struct CharacterSanitization {
    
    /// Sanitize character name for filesystem use
    /// MUST match C implementation in ios_character_save.c:sanitize_character_name()
    /// - Converts to lowercase
    /// - Replaces spaces with underscores
    /// - Removes special characters
    /// - Only allows: a-z, 0-9, underscore
    ///
    /// ROOT CAUSE FIX: UTF-8/Unicode character mismatch
    /// - Bug: Swift char.isLetter included ß, ä, ö, ü etc. → directory "fußabdruck"
    /// - C only accepts ASCII a-z → directory "fuabdruck"
    /// - Result: Screenshot and save in DIFFERENT directories!
    /// - Fix: Both MUST use ASCII-only check for consistent paths
    static func sanitizeName(_ name: String) -> String {
        var result = ""

        for char in name {
            if char == " " {
                result.append("_")
            } else if let scalar = char.unicodeScalars.first {
                let value = scalar.value
                // CRITICAL: Match C implementation exactly - ONLY ASCII!
                // a-z: 0x61-0x7A, A-Z: 0x41-0x5A, 0-9: 0x30-0x39
                if (value >= 0x61 && value <= 0x7A) ||  // a-z
                   (value >= 0x41 && value <= 0x5A) ||  // A-Z (will be lowercased)
                   (value >= 0x30 && value <= 0x39) ||  // 0-9
                   value == 0x5F {                      // underscore
                    result.append(char.lowercased())
                }
                // Skip all other characters (including UTF-8/Unicode like ß, ä, ö, ü)
            }
        }

        return result.isEmpty ? "unnamed" : result
    }
    
    /// Get the character directory path for a character
    static func getCharacterDirectory(_ characterName: String) -> String {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let sanitized = sanitizeName(characterName)
        // Strip trailing slash from documentsPath if present
        let cleanPath = documentsPath.hasSuffix("/") ? String(documentsPath.dropLast()) : documentsPath
        return "\(cleanPath)/NetHack/characters/\(sanitized)"
    }

    /// Get the character directory URL for a character
    static func getCharacterDirectoryURL(_ characterName: String) -> URL {
        return URL(fileURLWithPath: getCharacterDirectory(characterName))
    }
}
