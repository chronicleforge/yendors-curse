/*
 * ios_character_save.c - SIMPLIFIED character-based save system for NetHack iOS
 *
 * ONE save per character. No slots. No complexity.
 * Uses the SAME logic as ios_quicksave/ios_quickrestore but with character-specific paths.
 *
 * Architecture:
 *   /Documents/NetHack/characters/
 *     hero_name/
 *       savegame        # NetHack save file (fixed name)
 *       metadata.json   # Save metadata
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#include <ctype.h>
#include "../NetHack/include/hack.h"
#include "nethack_export.h"
#include "ios_character_save.h"

#define CHAR_SAVE_LOG(fmt, ...) fprintf(stderr, "[CHAR_SAVE] " fmt "\n", ##__VA_ARGS__)

/*
 * Strip trailing slashes from a path
 * Modifies path in-place
 */
static void strip_trailing_slashes(char *path) {
    if (!path) {
        return;
    }

    size_t len = strlen(path);
    while (len > 1 && path[len-1] == '/') {
        path[len-1] = '\0';
        len--;
    }
}

/*
 * Get the characters root directory path
 * Returns: /Documents/NetHack/characters
 *
 * CRITICAL FIX: This function is called at app launch BEFORE SAVEP is initialized!
 * We MUST use ios_get_documents_path() directly instead of relying on SAVEP.
 * See RCA: Initialization order bug - Character Selection appears before NetHack init.
 */
static const char* get_characters_root(void) {
    static char characters_root[512];

    // Get iOS Documents path DIRECTLY (always available, no init needed)
    extern const char* get_ios_documents_path(void);
    const char* docs_path = get_ios_documents_path();

    if (!docs_path || docs_path[0] == '\0') {
        CHAR_SAVE_LOG("ERROR: Could not get iOS documents path");
        return NULL;
    }

    // Build path: /Documents/NetHack/characters
    // NOTE: docs_path ALREADY includes "/NetHack" from Swift (ios_swift_get_documents_path)
    // So we only append "/characters" here!
    int len = snprintf(characters_root, sizeof(characters_root), "%s/characters", docs_path);
    if (len < 0 || len >= sizeof(characters_root)) {
        CHAR_SAVE_LOG("ERROR: Buffer overflow in get_characters_root (path too long)");
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

    if (!name || !name[0]) {
        sanitized[0] = '\0';
        return sanitized;
    }

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
    if (!character_name || !character_name[0]) {
        return 0;
    }

    const char *root = get_characters_root();
    if (!root) {
        return 0;
    }

    const char *sanitized = sanitize_character_name(character_name);
    if (!sanitized[0]) {
        return 0;
    }

    int len = snprintf(path, path_size, "%s/%s", root, sanitized);
    if (len < 0 || len >= path_size) {
        return 0;
    }

    // Validate no double slashes (indicates path construction error)
    char *double_slash = strstr(path, "//");
    if (double_slash) {
        CHAR_SAVE_LOG("ERROR: Double slash detected in path: %s", path);
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
        CHAR_SAVE_LOG("ERROR: Failed to get characters root path");
        return 0;
    }

    CHAR_SAVE_LOG("Ensuring directory structure for: %s", root);

    // STEP 1: Extract parent directory path
    // We need to create /Documents/NetHack BEFORE /Documents/NetHack/characters
    char parent[512];
    snprintf(parent, sizeof(parent), "%s", root);

    // Find last slash to separate parent from child
    char *last_slash = strrchr(parent, '/');
    if (!last_slash || last_slash == parent) {
        // Edge case: root path has no parent or is root directory itself
        CHAR_SAVE_LOG("ERROR: Invalid path structure (no parent): %s", root);
        return 0;
    }

    // Terminate string at last slash to get parent path
    *last_slash = '\0';
    CHAR_SAVE_LOG("  Parent directory: %s", parent);

    // STEP 2: Create parent directory first (/Documents/NetHack)
    if (mkdir(parent, 0755) != 0) {
        int saved_errno = errno;  // CRITICAL: Save errno IMMEDIATELY (thread safety)
        if (saved_errno != EEXIST) {
            CHAR_SAVE_LOG("ERROR: Failed to create parent directory: %s", strerror(saved_errno));
            return 0;
        }

        // EEXIST is OK - validate it's a directory
        struct stat st;
        if (stat(parent, &st) != 0) {
            CHAR_SAVE_LOG("ERROR: Failed to stat existing parent: %s", strerror(errno));
            return 0;
        }
        if (!S_ISDIR(st.st_mode)) {
            CHAR_SAVE_LOG("ERROR: Parent exists but is not a directory: %s", parent);
            return 0;
        }
        CHAR_SAVE_LOG("  ✓ Parent directory verified (already exists)");
    } else {
        CHAR_SAVE_LOG("  ✓ Parent directory created: %s", parent);
    }

    // STEP 3: Now create characters directory (/Documents/NetHack/characters)
    CHAR_SAVE_LOG("  Creating characters directory: %s", root);
    if (mkdir(root, 0755) != 0) {
        int saved_errno = errno;  // CRITICAL: Save errno IMMEDIATELY (thread safety)
        if (saved_errno != EEXIST) {
            CHAR_SAVE_LOG("ERROR: Failed to create characters root: %s", strerror(saved_errno));
            return 0;
        }

        // EEXIST is OK - validate it's a directory
        struct stat st;
        if (stat(root, &st) != 0) {
            CHAR_SAVE_LOG("ERROR: Failed to stat existing path: %s", strerror(errno));
            return 0;
        }
        if (!S_ISDIR(st.st_mode)) {
            CHAR_SAVE_LOG("ERROR: Path exists but is not a directory: %s", root);
            return 0;
        }
        CHAR_SAVE_LOG("  ✓ Characters directory verified (already exists)");
    } else {
        CHAR_SAVE_LOG("  ✓ Characters directory created: %s", root);
    }

    CHAR_SAVE_LOG("✓ Directory structure ready: %s", root);
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
            CHAR_SAVE_LOG("Failed to create character dir: %s", strerror(saved_errno));
            return 0;
        }

        // EEXIST edge case: Validate it's actually a directory (not a file)
        struct stat st;
        if (stat(char_path, &st) != 0) {
            CHAR_SAVE_LOG("Failed to stat existing path: %s", strerror(errno));
            return 0;
        }
        if (!S_ISDIR(st.st_mode)) {
            CHAR_SAVE_LOG("Path exists but is not a directory: %s", char_path);
            return 0;
        }
        // Verified: It's a directory - continue as success
    }

    return 1;
}

/*
 * Copy a file
 */
static int copy_file(const char *src, const char *dest) {
    FILE *src_fp = fopen(src, "rb");
    if (!src_fp) {
        CHAR_SAVE_LOG("Failed to open source file: %s", src);
        return 0;
    }

    FILE *dest_fp = fopen(dest, "wb");
    if (!dest_fp) {
        fclose(src_fp);
        CHAR_SAVE_LOG("Failed to open dest file: %s", dest);
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
 * Read a JSON string value from file content
 * Returns pointer to static buffer or NULL if not found
 */
static const char* json_get_string(const char* json, const char* key) {
    // NOTE: Static buffer - this function is only called sequentially in generate_metadata()
    // Thread safety not required since C save operations are single-threaded
    static char value[256];
    char search[64];
    snprintf(search, sizeof(search), "\"%s\":", key);

    const char* pos = strstr(json, search);
    if (!pos) return NULL;

    // Find the opening quote of the value
    pos = strchr(pos + strlen(search), '"');
    if (!pos) return NULL;
    pos++; // Skip opening quote

    // Copy until closing quote
    int i = 0;
    while (*pos && *pos != '"' && i < sizeof(value) - 1) {
        value[i++] = *pos++;
    }
    value[i] = '\0';
    return value;
}

/*
 * Generate metadata.json for a character's save
 * Preserves existing timestamps (created_at, synced_at, downloaded_at)
 * Swift manages synced_at/downloaded_at - C only writes created_at and updated_at
 */
static int generate_metadata(const char* character_name) {
    char char_path[512];
    char metadata_path[512];

    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return 0;
    }

    snprintf(metadata_path, sizeof(metadata_path), "%s/metadata.json", char_path);

    // Preserve existing timestamps from previous metadata
    char created_at[64] = "";
    char synced_at[64] = "";
    char downloaded_at[64] = "";

    // Try to read existing metadata to preserve timestamps
    FILE *existing_fp = fopen(metadata_path, "r");
    if (existing_fp) {
        fseek(existing_fp, 0, SEEK_END);
        long fsize = ftell(existing_fp);
        fseek(existing_fp, 0, SEEK_SET);

        if (fsize > 0 && fsize < 8192) {
            char* existing_json = malloc(fsize + 1);
            if (existing_json) {
                fread(existing_json, 1, fsize, existing_fp);
                existing_json[fsize] = '\0';

                // Preserve created_at (first save only sets this)
                const char* val = json_get_string(existing_json, "created_at");
                if (val) strncpy(created_at, val, sizeof(created_at) - 1);

                // Preserve synced_at (Swift manages this)
                val = json_get_string(existing_json, "synced_at");
                if (val) strncpy(synced_at, val, sizeof(synced_at) - 1);

                // Preserve downloaded_at (Swift manages this)
                val = json_get_string(existing_json, "downloaded_at");
                if (val) strncpy(downloaded_at, val, sizeof(downloaded_at) - 1);

                free(existing_json);
            }
        }
        fclose(existing_fp);
    }

    FILE *fp = fopen(metadata_path, "w");
    if (!fp) {
        CHAR_SAVE_LOG("Failed to create metadata: %s", strerror(errno));
        return 0;
    }

    // Current timestamp for updated_at (and created_at if first save)
    time_t now = time(NULL);
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));

    // Set created_at only on first save
    if (created_at[0] == '\0') {
        strncpy(created_at, timestamp, sizeof(created_at) - 1);
        CHAR_SAVE_LOG("  First save - setting created_at");
    }

    // Get gender and alignment strings
    const char *gender_str = (flags.female) ? "female" : "male";
    const char *align_str = (u.ualign.type == A_LAWFUL) ? "lawful" :
                            (u.ualign.type == A_NEUTRAL) ? "neutral" : "chaotic";

    // DEBUG: Log what we're about to save
    CHAR_SAVE_LOG("  DEBUG: Capturing metadata from game state:");
    CHAR_SAVE_LOG("    svp.plname='%s'", svp.plname);
    CHAR_SAVE_LOG("    u.ulevel=%d (character level)", u.ulevel);
    CHAR_SAVE_LOG("    gu.urole.name.m='%s'", gu.urole.name.m);
    CHAR_SAVE_LOG("    gu.urace.noun='%s'", gu.urace.noun);
    CHAR_SAVE_LOG("    u.uhp=%d/%d", u.uhp, u.uhpmax);
    CHAR_SAVE_LOG("    svm.moves=%ld", svm.moves);
    CHAR_SAVE_LOG("    u.uz.dlevel=%d", u.uz.dlevel);

    // Write JSON with all timestamp fields
    fprintf(fp, "{\n");
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
    fprintf(fp, "  \"last_saved\": \"%s\",\n", timestamp);
    fprintf(fp, "  \"created_at\": \"%s\",\n", created_at);
    fprintf(fp, "  \"updated_at\": \"%s\"", timestamp);

    // Add Swift-managed fields only if they exist (preserve them)
    if (synced_at[0] != '\0') {
        fprintf(fp, ",\n  \"synced_at\": \"%s\"", synced_at);
    }
    if (downloaded_at[0] != '\0') {
        fprintf(fp, ",\n  \"downloaded_at\": \"%s\"", downloaded_at);
    }

    fprintf(fp, "\n}\n");

    fclose(fp);

    CHAR_SAVE_LOG("  ✓ Metadata written to: %s", metadata_path);
    CHAR_SAVE_LOG("Generated metadata for character: %s (Level %d %s %s)",
                  character_name, u.ulevel, gu.urace.noun, gu.urole.name.m);
    return 1;
}

/*
 * Save current game for a character
 * Uses SAME logic as ios_quicksave() but with character-specific path
 */
NETHACK_EXPORT int ios_save_character(const char* character_name) {
    extern int ios_quicksave(void);  // From ios_save_integration.c

    if (!character_name || character_name[0] == '\0') {
        CHAR_SAVE_LOG("ERROR: Character name is required");
        return 0;
    }

    CHAR_SAVE_LOG("Saving game for character: %s", character_name);

    // Ensure character directory exists
    if (!ensure_character_dir(character_name)) {
        CHAR_SAVE_LOG("ERROR: Failed to create character directory");
        return 0;
    }

    // CRITICAL FIX: Step 0 - Generate metadata FIRST while game state is still valid!
    // ios_quicksave() exits moveloop which can corrupt u.ulevel, svp.plname etc.
    // We MUST capture metadata BEFORE the save sequence begins!
    CHAR_SAVE_LOG("  Step 0: CRITICAL - Generate metadata BEFORE ios_quicksave()");
    if (!generate_metadata(character_name)) {
        CHAR_SAVE_LOG("WARNING: Failed to generate metadata (non-fatal)");
        // Don't fail save for metadata, but this is a bug!
    }
    CHAR_SAVE_LOG("  ✓ Metadata captured with VALID game state");

    // Step 1: CRITICAL - Set gs.SAVEF so ios_quicksave() doesn't skip!
    extern struct instance_globals_s gs;
    CHAR_SAVE_LOG("  Step 1a: Setting gs.SAVEF for ios_quicksave()");
    snprintf(gs.SAVEF, sizeof(gs.SAVEF), "save/savegame");
    CHAR_SAVE_LOG("  DEBUG: gs.SAVEF = '%s'", gs.SAVEF);

    // Step 1b: Save to /save/savegame (ios_quicksave does the heavy lifting)
    CHAR_SAVE_LOG("  Step 1b: Calling ios_quicksave() to save current game state");
    if (ios_quicksave() != 0) {
        CHAR_SAVE_LOG("ERROR: ios_quicksave() failed");
        return 0;
    }
    CHAR_SAVE_LOG("  ✓ Current game state saved to /save/savegame");

    // Step 2: Copy to character-specific path
    char src_game[512], dest_game[512];
    int len;

    // CRITICAL FIX: Use get_ios_documents_path() directly (SAVEP may not be initialized after dylib reload!)
    extern const char* get_ios_documents_path(void);
    const char* docs_path = get_ios_documents_path();
    if (!docs_path || docs_path[0] == '\0') {
        CHAR_SAVE_LOG("ERROR: Could not get iOS documents path");
        return 0;
    }

    len = snprintf(src_game, sizeof(src_game), "%s/save/savegame", docs_path);
    if (len < 0 || len >= sizeof(src_game)) {
        CHAR_SAVE_LOG("ERROR: Buffer overflow constructing source path");
        return 0;
    }

    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        CHAR_SAVE_LOG("ERROR: Failed to get character path");
        return 0;
    }

    len = snprintf(dest_game, sizeof(dest_game), "%s/savegame", char_path);
    if (len < 0 || len >= sizeof(dest_game)) {
        CHAR_SAVE_LOG("ERROR: Buffer overflow constructing dest path");
        return 0;
    }

    CHAR_SAVE_LOG("  Step 2: Copying savegame to character directory");
    if (!copy_file(src_game, dest_game)) {
        CHAR_SAVE_LOG("ERROR: Failed to copy savegame file");
        return 0;
    }
    CHAR_SAVE_LOG("  ✓ Savegame copied to %s", dest_game);

    // Step 3: Metadata already generated in Step 0!
    CHAR_SAVE_LOG("  Step 3: Metadata already generated in Step 0 (skipping)");
    // OLD CODE (REMOVED): generate_metadata() was called HERE - TOO LATE!

    CHAR_SAVE_LOG("✅ Save complete for character: %s", character_name);
    return 1;
}

/*
 * Load game for a character
 * Uses SAME logic as ios_quickrestore() but with character-specific path
 */
NETHACK_EXPORT int ios_load_character(const char* character_name) {
    extern int ios_quickrestore(void);  // From ios_save_integration.c

    if (!character_name || character_name[0] == '\0') {
        CHAR_SAVE_LOG("ERROR: Character name is required");
        return 0;
    }

    CHAR_SAVE_LOG("Loading game for character: %s", character_name);

    // Check if character save exists
    if (!ios_character_save_exists(character_name)) {
        CHAR_SAVE_LOG("ERROR: No save exists for character: %s", character_name);
        return 0;
    }

    // Step 1: Copy character save to /save/savegame
    char src_game[512], dest_game[512];
    int len;

    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        CHAR_SAVE_LOG("ERROR: Failed to get character path");
        return 0;
    }

    len = snprintf(src_game, sizeof(src_game), "%s/savegame", char_path);
    if (len < 0 || len >= sizeof(src_game)) {
        CHAR_SAVE_LOG("ERROR: Buffer overflow constructing source path");
        return 0;
    }

    // CRITICAL FIX: Use get_ios_documents_path() directly (SAVEP may not be initialized after dylib reload!)
    extern const char* get_ios_documents_path(void);
    const char* docs_path = get_ios_documents_path();
    if (!docs_path || docs_path[0] == '\0') {
        CHAR_SAVE_LOG("ERROR: Could not get iOS documents path");
        return 0;
    }

    len = snprintf(dest_game, sizeof(dest_game), "%s/save/savegame", docs_path);
    if (len < 0 || len >= sizeof(dest_game)) {
        CHAR_SAVE_LOG("ERROR: Buffer overflow constructing dest path");
        return 0;
    }

    CHAR_SAVE_LOG("  Step 1: Copying character savegame to /save/savegame");
    if (!copy_file(src_game, dest_game)) {
        CHAR_SAVE_LOG("ERROR: Failed to copy savegame file");
        return 0;
    }
    CHAR_SAVE_LOG("  ✓ Savegame copied to %s", dest_game);

    // Step 2: Load from /save/savegame (ios_quickrestore does the heavy lifting)
    CHAR_SAVE_LOG("  Step 2: Calling ios_quickrestore() to load game");
    if (ios_quickrestore() != 0) {
        CHAR_SAVE_LOG("ERROR: ios_quickrestore() failed");
        return 0;
    }
    CHAR_SAVE_LOG("  ✓ Game state loaded successfully");

    CHAR_SAVE_LOG("✅ Load complete for character: %s", character_name);
    return 1;
}

/*
 * Check if a character has a save
 */
NETHACK_EXPORT int ios_character_save_exists(const char* character_name) {
    if (!character_name || character_name[0] == '\0') {
        return 0;
    }

    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return 0;
    }

    // Check if savegame file exists
    char savegame_path[512];
    snprintf(savegame_path, sizeof(savegame_path), "%s/savegame", char_path);

    return (access(savegame_path, F_OK) == 0);
}

/*
 * Delete a character's save
 */
NETHACK_EXPORT int ios_delete_character_save(const char* character_name) {
    if (!character_name || character_name[0] == '\0') {
        CHAR_SAVE_LOG("ERROR: Character name is required");
        return 0;
    }

    char char_path[512];
    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return 0;
    }

    CHAR_SAVE_LOG("Deleting save for character: %s", character_name);

    // Delete all files in character directory
    DIR *dir = opendir(char_path);
    if (dir) {
        struct dirent *entry;
        char file_path[512];

        while ((entry = readdir(dir)) != NULL) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
                continue;
            }

            snprintf(file_path, sizeof(file_path), "%s/%s", char_path, entry->d_name);
            unlink(file_path);
            CHAR_SAVE_LOG("  Deleted: %s", entry->d_name);
        }
        closedir(dir);
    }

    // Delete directory
    if (rmdir(char_path) != 0) {
        int saved_errno = errno;  // CRITICAL: Save errno IMMEDIATELY (thread safety)
        CHAR_SAVE_LOG("Failed to delete character directory: %s", strerror(saved_errno));
        return 0;
    }

    CHAR_SAVE_LOG("✅ Save deleted for character: %s", character_name);
    return 1;
}

/*
 * List all characters with saves
 * Returns: Array of character names (caller must free array AND strings)
 */
NETHACK_EXPORT char** ios_list_saved_characters(int *count) {
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
            // Check if it has a savegame file
            char savegame_path[512];
            snprintf(savegame_path, sizeof(savegame_path), "%s/savegame", char_path);
            if (access(savegame_path, F_OK) == 0) {
                num_chars++;
            }
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

        // Check if it's a directory with savegame
        char char_path[512];
        snprintf(char_path, sizeof(char_path), "%s/%s", root, entry->d_name);
        struct stat st;
        if (stat(char_path, &st) == 0 && S_ISDIR(st.st_mode)) {
            char savegame_path[512];
            snprintf(savegame_path, sizeof(savegame_path), "%s/savegame", char_path);
            if (access(savegame_path, F_OK) == 0) {
                // Allocate and copy character name
                characters[index] = strdup(entry->d_name);
                if (characters[index]) {
                    index++;
                }
            }
        }
    }

    closedir(dir);

    *count = index;
    CHAR_SAVE_LOG("Found %d saved characters", index);

    return characters;
}

/*
 * Get metadata path for a character's save
 */
NETHACK_EXPORT int ios_get_character_metadata_path(const char* character_name, char *path, size_t path_size) {
    char char_path[512];

    if (!get_character_path(character_name, char_path, sizeof(char_path))) {
        return 0;
    }

    int len = snprintf(path, path_size, "%s/metadata.json", char_path);
    if (len < 0 || len >= path_size) {
        return 0;
    }

    return 1;
}
