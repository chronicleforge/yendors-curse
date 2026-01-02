import Foundation
import Combine

/// SIMPLIFIED Character Manager - ONE save per character, NO slots
/// Provides character-level operations (list, delete, check existence)
class SimplifiedCharacterManager: ObservableObject {
    @Published var characters: [SavedCharacter] = []
    @Published var errorMessage: String?
    
    static let shared = SimplifiedCharacterManager()
    
    private init() {
        loadCharacters()
    }
    
    // MARK: - Character Operations
    
    /// Check if a character save exists
    func characterHasSave(_ name: String) -> Bool {
        return ios_character_save_exists(name) == 1
    }
    
    /// List all characters with saves
    /// CRITICAL FIX: Do character discovery in PURE SWIFT, no C dependency!
    /// This ensures it works BEFORE dylib is loaded (initialization order bug fix)
    func loadCharacters() {
        // Get iOS Documents directory DIRECTLY in Swift (always available!)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let charactersURL = documentsURL.appendingPathComponent("NetHack/characters")

        // Check if directory exists
        guard FileManager.default.fileExists(atPath: charactersURL.path) else {
            print("[SimplifiedCharacterManager] Characters directory doesn't exist yet: \(charactersURL.path)")
            characters = []
            return
        }

        // Scan directory for character subdirectories with savegame files
        var savedCharacters: [SavedCharacter] = []

        do {
            let characterDirs = try FileManager.default.contentsOfDirectory(at: charactersURL, includingPropertiesForKeys: nil)

            for charDir in characterDirs {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: charDir.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }

                // Check if savegame file exists
                let savegameURL = charDir.appendingPathComponent("savegame")
                guard FileManager.default.fileExists(atPath: savegameURL.path) else {
                    continue
                }

                    let characterName = charDir.lastPathComponent

                // Load metadata DIRECTLY from Swift FileManager (no C bridge needed!)
                let metadataURL = charDir.appendingPathComponent("metadata.json")

                guard let metadata = loadMetadataFromPath(metadataURL.path) else {
                    print("[SimplifiedCharacterManager] Failed to load metadata for \(characterName)")
                    continue
                }

                let character = SavedCharacter(characterName: characterName, metadata: metadata)
                savedCharacters.append(character)
            }

            // Sort characters by most recent activity
            savedCharacters.sort { $0.metadata.lastSaved > $1.metadata.lastSaved }

            DispatchQueue.main.async {
                self.characters = savedCharacters
            }

        } catch {
            print("[SimplifiedCharacterManager] Error scanning characters directory: \(error)")
            DispatchQueue.main.async {
                self.characters = []
            }
        }
    }
    
    /// Delete a character's save
    func deleteCharacter(_ characterName: String) -> Bool {
        let result = ios_delete_character_save(characterName)
        
        if result == 0 {
            errorMessage = "Failed to delete character \(characterName)"
            print("[SimplifiedCharacterManager] ❌ Delete character \(characterName) failed")
            return false
        }
        
        print("[SimplifiedCharacterManager] ✅ Deleted character \(characterName)")
        
        // Reload character list
        loadCharacters()
        
        return true
    }
    
    /// Get character by name
    func getCharacter(_ name: String) -> SavedCharacter? {
        return characters.first { $0.characterName == name }
    }
    
    // MARK: - Utilities
    
    func hasCharacters() -> Bool {
        return !characters.isEmpty
    }
    
    func characterCount() -> Int {
        return characters.count
    }
    
    func refresh() {
        loadCharacters()
    }
    
    // MARK: - Private Helpers
    
    private func loadMetadataFromPath(_ path: String) -> CharacterSaveInfo? {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            print("[SimplifiedCharacterManager] Metadata file doesn't exist: \(path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let metadata = try decoder.decode(CharacterSaveInfo.self, from: data)
            return metadata
        } catch {
            print("[SimplifiedCharacterManager] Failed to load metadata from \(path): \(error)")
            return nil
        }
    }
}

// MARK: - Data Models

/// Represents a saved character with metadata
struct SavedCharacter: Identifiable {
    let id = UUID()
    let characterName: String
    let metadata: CharacterSaveInfo
}

/// Character save metadata (from metadata.json)
struct CharacterSaveInfo: Codable {
    let characterName: String
    let role: String
    let race: String
    let gender: String
    let alignment: String
    let level: Int
    let hp: Int
    let hpmax: Int
    let turns: Int
    let dungeonLevel: Int
    let lastSaved: Date
    
    enum CodingKeys: String, CodingKey {
        case characterName = "character_name"
        case role
        case race
        case gender
        case alignment
        case level
        case hp
        case hpmax
        case turns
        case dungeonLevel = "dungeon_level"
        case lastSaved = "last_saved"
    }
}
