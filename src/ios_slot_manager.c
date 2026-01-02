/*
 * ios_slot_manager.c - Character-based multi-slot save system for NetHack iOS
 *
 * Manages multiple CHARACTERS, each with up to 3 save slots.
 * Character name is the unique identifier.
 * Each slot contains: savegame file + metadata.json + map_snapshot.jpg
 * NO memory.dat (ASLR fix - use only NetHack's serialized save format)
 *
 * Architecture:
 *   /Documents/NetHack/characters/
 *     hero_name/              # Character name (lowercase, sanitized)
 *       slot_00001/
 *         savegame
 *         metadata.json
 *         map_snapshot.jpg
 *       slot_00002/
 *         savegame
 *         metadata.json
 *         map_snapshot.jpg
 *       slot_00003/
 *         savegame
 *         metadata.json
 *         map_snapshot.jpg
 *     wizard_joe/
 *       slot_00001/
 *         ...
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#include "../NetHack/include/hack.h"

#define SLOT_LOG(fmt, ...) fprintf(stderr, "[SLOT_MANAGER] " fmt "\n", ##__VA_ARGS__)

// Maximum slots per character
#define MAX_SLOTS 3

// Global active character name and slot
static char g_active_character[256] = {0};
static int g_active_slot_id = 0;

// Forward declarations
int* ios_list_slots(const char* character_name, int *count);
static char* sanitize_character_name(const char* name);

/*
 * Get the characters root directory path
 * Returns: /Documents/NetHack/characters
 */
static const char* get_characters_root(void) {
    extern char SAVEP[];
    static char characters_root[512];

    if (!SAVEP || SAVEP[0] == '\0') {
        return NULL;
    }

    int len = snprintf(characters_root, sizeof(characters_root), "%s/characters", SAVEP);
    if (len < 0 || len >= sizeof(characters_root)) {
        SLOT_LOG("ERROR: Buffer overflow in get_characters_root (SAVEP too long)");
        return NULL;
    }
    return characters_root;
}

/*
 * Sanitize character name for filesystem use
 * Converts to lowercase, replaces spaces with underscores, removes special chars
 * Returns: static buffer (caller should NOT free!)
 */
static char* sanitize_character_name(const char* name) {
    static char sanitized[256];
    int j = 0;

    for (int i = 0; name[i] != '\0' && j < sizeof(sanitized) - 1; i++) {
        char c = name[i];

        // Convert to lowercase
        if (c >= 'A' && c <= 'Z') {
            c = c + ('a' - 'A');
        }

        // Replace spaces with underscores
        if (c == ' ') {
            sanitized[j++] = '_';
        }
        // Allow alphanumeric and underscore
        else if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') {
            sanitized[j++] = c;
        }
        // Skip all other characters
    }

    sanitized[j] = '\0';
    return sanitized;
}

/*
 * Get character directory path
 * Returns: /Documents/NetHack/characters/hero_name
 */
static int get_character_path(const char* character_name, char *path, size_t path_size) {
    const char *root = get_characters_root();
    if (!root) {
        return 0;
    }

    const char *sanitized = sanitize_character_name(character_name);
    int len = snprintf(path, path_size, "%s/%s", root, sanitized);
    if (len < 0 || len >= path_size) {
        return 0;
    }

    return 1;
}

/*
 * Ensure characters root directory exists
 * CRITICAL FIX: Must create parent directory FIRST!
 * Path structure: /Documents/NetHack/characters
 *   - Parent: /Documents/NetHack (may not exist!)
 *   - Child: /Documents/NetHack/characters
 */
static int ensure_characters_root(void) {
    const char *root = get_characters_root();
    if (!root) {
        SLOT_LOG("ERROR: Failed to get characters root path");
        return 0;
    }

    SLOT_LOG("Ensuring directory structure for: %s", root);

    // STEP 1: Extract parent directory path
    // We need to create /Documents/NetHack BEFORE /Documents/NetHack/characters
    char parent[512];
    snprintf(parent, sizeof(parent), "%s", root);

    // Find last slash to separate parent from child
    char *last_slash = strrchr(parent, '/');
    if (!last_slash || last_slash == parent) {
        // Edge case: root path has no parent or is root directory itself
        SLOT_LOG("ERROR: Invalid path structure (no parent): %s", root);
        return 0;
    }

    // Terminate string at last slash to get parent path
    *last_slash = '\0';
    SLOT_LOG("  Parent directory: %s", parent);

    // STEP 2: Create parent directory first (/Documents/NetHack)
    if (mkdir(parent, 0755) != 0) {
        int saved_errno = errno;
        if (saved_errno != EEXIST) {
            SLOT_LOG("Failed to create parent directory: %s", strerror(saved_errno));
            return 0;
        }

        // EEXIST: Verify it's actually a directory
        struct stat st;
        if (stat(parent, &st) != 0) {
            SLOT_LOG("Failed to stat existing parent: %s", strerror(errno));
            return 0;
        }
        if (!S_ISDIR(st.st_mode)) {
            SLOT_LOG("Parent exists but is not a directory: %s", parent);
            return 0;
        }
    }
    SLOT_LOG("  ✓ Parent directory ensured: %s", parent);

    // STEP 3: Now create characters/ directory
    if (mkdir(root, 0755) != 0) {
        int saved_errno = errno;  // CRITICAL: Save errno IMMEDIATELY (thread safety)
        if (saved_errno != EEXIST) {
            SLOT_LOG("Failed to create characters root: %s", strerror(saved_errno));
            return 0;
        }

        // EEXIST edge case: Validate it's actually a directory (not a file)
        struct stat st;
        if (stat(root, &st) != 0) {
            SLOT_LOG("Failed to stat existing path: %s", strerror(errno));
            return 0;
        }
        if (!S_ISDIR(st.st_mode)) {
            SLOT_LOG("Path exists but is not a directory: %s", root);
            return 0;
        }
        // Verified: It's a directory - continue as success
    }

    SLOT_LOG("  ✓ Characters directory ensured: %s", root);
    return 1;
}

/*
 * Ensure character directory exists
 */
static int ensure_character_dir(const char* character_name) {
    if (!ensure_characters_root()) {
        return 0;
    }

    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return 0;
    }

    // Try to create directory - ignore EEXIST (already exists = success)
    // This handles race conditions where another process (ScreenshotService) creates it
    if (mkdir(char_path, 0755) != 0) {
        int saved_errno = errno;  // CRITICAL: Save errno IMMEDIATELY (thread safety)
        if (saved_errno != EEXIST) {
            SLOT_LOG("Failed to create character dir: %s", strerror(saved_errno));
            return 0;
        }

        // EEXIST edge case: Validate it's actually a directory (not a file)
        struct stat st;
        if (stat(char_path, &st) != 0) {
            SLOT_LOG("Failed to stat existing path: %s", strerror(errno));
            return 0;
        }
        if (!S_ISDIR(st.st_mode)) {
            SLOT_LOG("Path exists but is not a directory: %s", char_path);
            return 0;
        }
        // Verified: It's a directory - continue as success
    }

    return 1;
}

/*
 * Get slot directory path for a given character and slot ID
 * Returns: /Documents/NetHack/characters/hero_name/slot_00001
 */
static int get_slot_path(const char* character_name, int slot_id, char *path, size_t path_size) {
    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return 0;
    }

    int len = snprintf(path, path_size, "%s/slot_%05d", char_path, slot_id);
    if (len < 0 || len >= path_size) {
        return 0;
    }

    return 1;
}

/*
 * Check if a character exists
 */
int ios_character_exists(const char* character_name) {
    char char_path[512];

    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return 0;
    }

    return (access(char_path, F_OK) == 0);
}

/*
 * Check if a slot exists for a specific character
 */
int ios_slot_exists(const char* character_name, int slot_id) {
    char slot_path[512];

    if (!get_slot_path(character_name, slot_id, slot_path, sizeof(slot_path))) {
        return 0;
    }

    return (access(slot_path, F_OK) == 0);
}

/*
 * Find the next available slot ID for a specific character
 */
static int find_next_slot_id(const char* character_name) {
    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return -1;
    }

    DIR *dir = opendir(char_path);
    if (!dir) {
        // Character dir doesn't exist yet, start with slot 1
        return 1;
    }

    int max_id = 0;
    struct dirent *entry;

    while ((entry = readdir(dir)) != NULL) {
        // Parse "slot_XXXXX" format
        if (strncmp(entry->d_name, "slot_", 5) == 0) {
            int id = atoi(entry->d_name + 5);
            if (id > max_id) {
                max_id = id;
            }
        }
    }

    closedir(dir);
    return max_id + 1;
}

/*
 * Create a new slot for a character
 * Returns: slot_id on success, -1 on failure
 * Enforces MAX_SLOTS limit (3 slots per character)
 */
int ios_create_slot(const char* character_name) {
    if (!character_name || character_name[0] == '\0') {
        SLOT_LOG("ERROR: Character name is required");
        return -1;
    }

    if (!ensure_character_dir(character_name)) {
        return -1;
    }

    // Check slot count limit for THIS character
    int count = 0;
    int *existing_slots = ios_list_slots(character_name, &count);
    if (existing_slots) {
        free(existing_slots);
    }

    if (count >= MAX_SLOTS) {
        SLOT_LOG("ERROR: Character '%s' has maximum slots (%d). Delete a slot first.",
                 character_name, MAX_SLOTS);
        return -1;
    }

    int slot_id = find_next_slot_id(character_name);
    if (slot_id < 0) {
        return -1;
    }

    char slot_path[512];
    if (!get_slot_path(character_name, slot_id, slot_path, sizeof(slot_path))) {
        return -1;
    }

    // Create slot directory - ignore EEXIST (already exists = success)
    // This handles race conditions and allows idempotent slot creation
    if (mkdir(slot_path, 0755) != 0) {
        int saved_errno = errno;  // CRITICAL: Save errno IMMEDIATELY (thread safety)
        if (saved_errno != EEXIST) {
            SLOT_LOG("Failed to create slot %d for '%s': %s", slot_id, character_name, strerror(saved_errno));
            return -1;
        }

        // EEXIST edge case: Validate it's actually a directory (not a file)
        struct stat st;
        if (stat(slot_path, &st) != 0) {
            SLOT_LOG("Failed to stat existing path: %s", strerror(errno));
            return -1;
        }
        if (!S_ISDIR(st.st_mode)) {
            SLOT_LOG("Path exists but is not a directory: %s", slot_path);
            return -1;
        }
        // Verified: It's a directory - continue as success
    }

    SLOT_LOG("Created slot %d for '%s' at: %s (slot %d of %d)",
             slot_id, character_name, slot_path, count + 1, MAX_SLOTS);
    return slot_id;
}

/*
 * Copy a file (helper function)
 */
static int copy_file(const char *src, const char *dest) {
    FILE *src_fp = fopen(src, "rb");
    if (!src_fp) {
        SLOT_LOG("Failed to open source file: %s", src);
        return 0;
    }

    FILE *dest_fp = fopen(dest, "wb");
    if (!dest_fp) {
        fclose(src_fp);
        SLOT_LOG("Failed to open dest file: %s", dest);
        return 0;
    }

    // Copy in 64KB chunks
    char buffer[65536];
    size_t bytes;

    while ((bytes = fread(buffer, 1, sizeof(buffer), src_fp)) > 0) {
        if (fwrite(buffer, 1, bytes, dest_fp) != bytes) {
            fclose(src_fp);
            fclose(dest_fp);
            return 0;
        }
    }

    fclose(src_fp);
    fclose(dest_fp);
    return 1;
}

/*
 * Generate metadata.json for a slot
 */
static int generate_metadata(const char* character_name, int slot_id, int slot_number) {
    char metadata_path[512];
    char slot_path[512];

    if (!get_slot_path(character_name, slot_id, slot_path, sizeof(slot_path))) {
        return 0;
    }

    snprintf(metadata_path, sizeof(metadata_path), "%s/metadata.json", slot_path);

    FILE *fp = fopen(metadata_path, "w");
    if (!fp) {
        SLOT_LOG("Failed to create metadata: %s", strerror(errno));
        return 0;
    }

    // Get current game state
    time_t now = time(NULL);
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));

    // Get gender and alignment strings
    const char *gender_str = (flags.female) ? "female" : "male";
    const char *align_str = (u.ualign.type == A_LAWFUL) ? "lawful" :
                            (u.ualign.type == A_NEUTRAL) ? "neutral" : "chaotic";

    // Check if map snapshot exists
    char snapshot_path[512];
    snprintf(snapshot_path, sizeof(snapshot_path), "%s/map_snapshot.jpg", slot_path);
    int has_snapshot = (access(snapshot_path, F_OK) == 0);

    // Write JSON
    fprintf(fp, "{\n");
    fprintf(fp, "  \"slot_id\": %d,\n", slot_id);
    fprintf(fp, "  \"slot_number\": %d,\n", slot_number);
    fprintf(fp, "  \"character_name\": \"%s\",\n", svp.plname);
    fprintf(fp, "  \"role\": \"%s\",\n", gu.urole.name.m);
    fprintf(fp, "  \"race\": \"%s\",\n", gu.urace.noun);
    fprintf(fp, "  \"gender\": \"%s\",\n", gender_str);
    fprintf(fp, "  \"alignment\": \"%s\",\n", align_str);
    fprintf(fp, "  \"level\": %d,\n", u.ulevel);
    fprintf(fp, "  \"hp\": %d,\n", u.uhp);
    fprintf(fp, "  \"hpmax\": %d,\n", u.uhpmax);
    fprintf(fp, "  \"turns\": %ld,\n", svm.moves);
    fprintf(fp, "  \"dungeon_level\": %d,\n", u.uz.dlevel);
    fprintf(fp, "  \"has_map_snapshot\": %s,\n", has_snapshot ? "true" : "false");
    fprintf(fp, "  \"last_saved\": \"%s\"\n", timestamp);
    fprintf(fp, "}\n");

    fclose(fp);

    SLOT_LOG("Generated metadata for slot %d (character: %s, slot#: %d)", slot_id, character_name, slot_number);
    return 1;
}

/*
 * Save current game to a slot
 * Copies: savegame file (fixed filename) + generates metadata
 * NO memory.dat (ASLR fix - only NetHack's serialized save format)
 */
int ios_save_to_slot(const char* character_name, int slot_id) {
    extern char SAVEP[];
    extern int ios_quicksave(void);  // From ios_save_integration.c

    if (!character_name || character_name[0] == '\0') {
        SLOT_LOG("ERROR: Character name is required");
        return 0;
    }

    if (!ios_slot_exists(character_name, slot_id)) {
        SLOT_LOG("Slot %d for character '%s' doesn't exist", slot_id, character_name);
        return 0;
    }

    char slot_path[512];
    if (!get_slot_path(character_name, slot_id, slot_path, sizeof(slot_path))) {
        return 0;
    }

    SLOT_LOG("Saving to slot %d (character: %s)...", slot_id, character_name);

    // CRITICAL FIX: Update /save/savegame with CURRENT game state BEFORE copying!
    // Without this, we copy the OLD savegame (e.g. from Turn 1) instead of current state.
    // This is why slots always showed Turn 1 - we never updated the source file!
    SLOT_LOG("  Step 1: Saving current game state to /save/savegame...");
    if (ios_quicksave() != 0) {
        SLOT_LOG("ERROR: Failed to save current game state");
        return 0;
    }
    SLOT_LOG("  ✓ Current game state saved (fresh savegame ready to copy)");

    // Copy game file (using FIXED filename "savegame")
    char src_game[512], dest_game[512];
    int len;

    len = snprintf(src_game, sizeof(src_game), "%s/save/savegame", SAVEP);
    if (len < 0 || len >= sizeof(src_game)) {
        SLOT_LOG("ERROR: Buffer overflow constructing source path");
        return 0;
    }

    len = snprintf(dest_game, sizeof(dest_game), "%s/savegame", slot_path);
    if (len < 0 || len >= sizeof(dest_game)) {
        SLOT_LOG("ERROR: Buffer overflow constructing dest path");
        return 0;
    }

    if (!copy_file(src_game, dest_game)) {
        SLOT_LOG("Failed to copy game file");
        return 0;
    }

    SLOT_LOG("✓ Copied savegame");

    // Determine slot number (1, 2, or 3) by counting slots
    int count = 0;
    int *slots = ios_list_slots(character_name, &count);
    int slot_number = 1;
    if (slots) {
        // Find position of this slot_id in sorted list
        for (int i = 0; i < count; i++) {
            if (slots[i] == slot_id) {
                slot_number = i + 1;
                break;
            }
        }
        free(slots);
    }

    // Generate metadata
    if (!generate_metadata(character_name, slot_id, slot_number)) {
        SLOT_LOG("Warning: Failed to generate metadata");
        // Don't fail save for metadata
    }

    SLOT_LOG("✅ Slot %d (slot#%d) saved successfully for '%s'", slot_id, slot_number, character_name);
    return 1;
}

/*
 * Load game from a slot
 * Copies: savegame file (fixed filename) from slot to save/
 * NO memory.dat (ASLR fix - only NetHack's serialized save format)
 */
int ios_load_from_slot(const char* character_name, int slot_id) {
    extern char SAVEP[];

    if (!character_name || character_name[0] == '\0') {
        SLOT_LOG("ERROR: Character name is required");
        return 0;
    }

    if (!ios_slot_exists(character_name, slot_id)) {
        SLOT_LOG("Slot %d for character '%s' doesn't exist", slot_id, character_name);
        return 0;
    }

    char slot_path[512];
    if (!get_slot_path(character_name, slot_id, slot_path, sizeof(slot_path))) {
        return 0;
    }

    SLOT_LOG("Loading from slot %d (character: %s)...", slot_id, character_name);

    // Copy game file (using FIXED filename "savegame")
    char src_game[512], dest_game[512];
    int len;

    len = snprintf(src_game, sizeof(src_game), "%s/savegame", slot_path);
    if (len < 0 || len >= sizeof(src_game)) {
        SLOT_LOG("ERROR: Buffer overflow constructing source path");
        return 0;
    }

    len = snprintf(dest_game, sizeof(dest_game), "%s/save/savegame", SAVEP);
    if (len < 0 || len >= sizeof(dest_game)) {
        SLOT_LOG("ERROR: Buffer overflow constructing dest path");
        return 0;
    }

    if (!copy_file(src_game, dest_game)) {
        SLOT_LOG("Failed to copy savegame");
        return 0;
    }

    SLOT_LOG("✓ Copied savegame");

    // Set as active character and slot
    strncpy(g_active_character, character_name, sizeof(g_active_character) - 1);
    g_active_character[sizeof(g_active_character) - 1] = '\0';
    g_active_slot_id = slot_id;

    SLOT_LOG("✅ Slot %d loaded successfully for '%s'", slot_id, character_name);
    return 1;
}

/*
 * Delete a slot
 */
int ios_delete_slot(const char* character_name, int slot_id) {
    if (!character_name || character_name[0] == '\0') {
        SLOT_LOG("ERROR: Character name is required");
        return 0;
    }

    if (!ios_slot_exists(character_name, slot_id)) {
        return 0;
    }

    char slot_path[512];
    if (!get_slot_path(character_name, slot_id, slot_path, sizeof(slot_path))) {
        return 0;
    }

    SLOT_LOG("Deleting slot %d (character: %s)...", slot_id, character_name);

    // Delete all files in slot directory
    DIR *dir = opendir(slot_path);
    if (dir) {
        struct dirent *entry;
        char file_path[512];

        while ((entry = readdir(dir)) != NULL) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
                continue;
            }

            snprintf(file_path, sizeof(file_path), "%s/%s", slot_path, entry->d_name);
            unlink(file_path);
        }
        closedir(dir);
    }

    // Delete directory
    if (rmdir(slot_path) != 0) {
        int saved_errno = errno;  // CRITICAL: Save errno IMMEDIATELY (thread safety)
        SLOT_LOG("Failed to delete slot directory: %s", strerror(saved_errno));
        return 0;
    }

    SLOT_LOG("✅ Slot %d deleted for '%s'", slot_id, character_name);
    return 1;
}

/*
 * Delete an entire character (all slots)
 */
int ios_delete_character(const char* character_name) {
    if (!character_name || character_name[0] == '\0') {
        SLOT_LOG("ERROR: Character name is required");
        return 0;
    }

    if (!ios_character_exists(character_name)) {
        SLOT_LOG("Character '%s' doesn't exist", character_name);
        return 0;
    }

    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return 0;
    }

    SLOT_LOG("Deleting character '%s'...", character_name);

    // Delete all slot directories first
    DIR *char_dir = opendir(char_path);
    if (char_dir) {
        struct dirent *slot_entry;

        while ((slot_entry = readdir(char_dir)) != NULL) {
            if (strcmp(slot_entry->d_name, ".") == 0 || strcmp(slot_entry->d_name, "..") == 0) {
                continue;
            }

            // If it's a slot directory
            if (strncmp(slot_entry->d_name, "slot_", 5) == 0) {
                char slot_path[512];
                snprintf(slot_path, sizeof(slot_path), "%s/%s", char_path, slot_entry->d_name);

                // Delete all files in slot
                DIR *slot_dir = opendir(slot_path);
                if (slot_dir) {
                    struct dirent *file_entry;
                    char file_path[512];

                    while ((file_entry = readdir(slot_dir)) != NULL) {
                        if (strcmp(file_entry->d_name, ".") == 0 || strcmp(file_entry->d_name, "..") == 0) {
                            continue;
                        }

                        snprintf(file_path, sizeof(file_path), "%s/%s", slot_path, file_entry->d_name);
                        unlink(file_path);
                    }
                    closedir(slot_dir);
                }

                // Delete slot directory
                rmdir(slot_path);
            }
        }
        closedir(char_dir);
    }

    // Delete character directory
    if (rmdir(char_path) != 0) {
        int saved_errno = errno;  // CRITICAL: Save errno IMMEDIATELY (thread safety)
        SLOT_LOG("Failed to delete character directory: %s", strerror(saved_errno));
        return 0;
    }

    SLOT_LOG("✅ Character '%s' deleted", character_name);
    return 1;
}

/*
 * List all available slots for a character
 * Returns: Array of slot IDs (caller must free)
 * count: Number of slots found
 */
int* ios_list_slots(const char* character_name, int *count) {
    *count = 0;

    if (!character_name || character_name[0] == '\0') {
        return NULL;
    }

    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return NULL;
    }

    DIR *dir = opendir(char_path);
    if (!dir) {
        return NULL;
    }

    // First pass: count slots
    int num_slots = 0;
    struct dirent *entry;

    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "slot_", 5) == 0) {
            num_slots++;
        }
    }

    if (num_slots == 0) {
        closedir(dir);
        return NULL;
    }

    // Allocate array
    int *slots = malloc(num_slots * sizeof(int));
    if (!slots) {
        closedir(dir);
        return NULL;
    }

    // Second pass: collect slot IDs
    rewinddir(dir);
    int index = 0;

    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "slot_", 5) == 0) {
            int id = atoi(entry->d_name + 5);
            slots[index++] = id;
        }
    }

    closedir(dir);

    *count = num_slots;
    SLOT_LOG("Found %d slots for character '%s'", num_slots, character_name);

    return slots;
}

/*
 * List all characters
 * Returns: Array of character names (caller must free array AND strings)
 * count: Number of characters found
 */
char** ios_list_characters(int *count) {
    *count = 0;

    const char *root = get_characters_root();
    if (!root) {
        return NULL;
    }

    DIR *dir = opendir(root);
    if (!dir) {
        return NULL;
    }

    // First pass: count characters
    int num_chars = 0;
    struct dirent *entry;

    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }

        // Check if it's a directory
        char char_path[512];
        snprintf(char_path, sizeof(char_path), "%s/%s", root, entry->d_name);
        struct stat st;
        if (stat(char_path, &st) == 0 && S_ISDIR(st.st_mode)) {
            num_chars++;
        }
    }

    if (num_chars == 0) {
        closedir(dir);
        return NULL;
    }

    // Allocate array of string pointers
    char **characters = malloc(num_chars * sizeof(char*));
    if (!characters) {
        closedir(dir);
        return NULL;
    }

    // Second pass: collect character names
    rewinddir(dir);
    int index = 0;

    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }

        // Check if it's a directory
        char char_path[512];
        snprintf(char_path, sizeof(char_path), "%s/%s", root, entry->d_name);
        struct stat st;
        if (stat(char_path, &st) == 0 && S_ISDIR(st.st_mode)) {
            // Allocate and copy character name
            characters[index] = strdup(entry->d_name);
            if (characters[index]) {
                index++;
            }
        }
    }

    closedir(dir);

    *count = index;
    SLOT_LOG("Found %d characters", index);

    return characters;
}

/*
 * Get currently active character name
 */
const char* ios_get_active_character(void) {
    return g_active_character[0] != '\0' ? g_active_character : NULL;
}

/*
 * Get currently active slot ID
 */
int ios_get_active_slot(void) {
    return g_active_slot_id;
}

/*
 * Set active character and slot
 */
void ios_set_active_slot(const char* character_name, int slot_id) {
    if (character_name) {
        strncpy(g_active_character, character_name, sizeof(g_active_character) - 1);
        g_active_character[sizeof(g_active_character) - 1] = '\0';
    } else {
        g_active_character[0] = '\0';
    }

    g_active_slot_id = slot_id;
    SLOT_LOG("Active slot set to: %d (character: %s)", slot_id,
             character_name ? character_name : "none");
}

/*
 * Get slot metadata path
 */
int ios_get_slot_metadata_path(const char* character_name, int slot_id, char *path, size_t path_size) {
    char slot_path[512];

    if (!get_slot_path(character_name, slot_id, slot_path, sizeof(slot_path))) {
        return 0;
    }

    int len = snprintf(path, path_size, "%s/metadata.json", slot_path);
    if (len < 0 || len >= path_size) {
        return 0;
    }

    return 1;
}
