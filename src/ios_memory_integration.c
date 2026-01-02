/*
 * ios_memory_integration.c - Integrates static memory allocator with save/restore
 *
 * CRITICAL: This file ensures memory state is preserved across saves!
 * Without this, all pointers become invalid after restore.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include "../NetHack/include/hack.h"
#include "../zone_allocator/nethack_memory_final.h"

/* External NetHack functions */
extern void savegamestate(NHFILE *);          /* NetHack save function (made public via patch) */
extern boolean restgamestate(NHFILE *);       /* NetHack restore function */
extern void l_nhcore_init(void);              /* Lua initialization */

/* External game state */
extern struct sinfo program_state;
extern struct flag flags;
extern char SAVEF[];

/* Memory state file paths */
#define MEMORY_STATE_FILE "memory.dat"
#define MEMORY_BACKUP_FILE "memory.bak"

/*
 * Get full path for memory state file
 */
static const char* get_memory_state_path(void) {
    static char path[1024];
    char *base = strrchr(SAVEF, '/');

    if (base) {
        size_t dir_len = base - SAVEF;
        strncpy(path, SAVEF, dir_len);
        path[dir_len] = '\0';
        strcat(path, "/");
        strcat(path, MEMORY_STATE_FILE);
    } else {
        strcpy(path, MEMORY_STATE_FILE);
    }

    fprintf(stderr, "[MEMORY_INT] Memory state path: %s\n", path);
    return path;
}

/*
 * Initialize memory allocator and Lua BEFORE any operations
 * Must be called at program startup
 */
int ios_memory_init(void) {
    fprintf(stderr, "[MEMORY_INT] Initializing memory subsystem...\n");

    /* Reset the static allocator */
    nh_restart();

    /* DO NOT initialize Lua here - let restore_luadata handle it
     * Double initialization causes memory corruption and crashes!
     * restore_luadata() will initialize Lua if needed at line 1310
     */
    fprintf(stderr, "[MEMORY_INT] Memory subsystem initialized (Lua init deferred)\n");
    return 1;
}

/*
 * Save game state WITH memory state
 * This wraps the original savegamestate() and adds memory save
 * Now enabled since savegamestate is exported
 */
int ios_savegamestate_with_memory(NHFILE *nhfp) {
    int result;
    const char *mem_path;

    fprintf(stderr, "[MEMORY_INT] === SAVE WITH MEMORY STATE ===\n");

    /* First save the game state */
    fprintf(stderr, "[MEMORY_INT] Calling savegamestate()...\n");
    savegamestate(nhfp);  /* This is void, no return value */
    result = 1;  /* Assume success if no crash */

    /* Now save the memory state */
    mem_path = get_memory_state_path();
    fprintf(stderr, "[MEMORY_INT] Saving memory state to: %s\n", mem_path);

    if (nh_save_state(mem_path) != 0) {
        fprintf(stderr, "[MEMORY_INT] ERROR: Failed to save memory state!\n");
        return 0;
    }

    /* Get memory stats for verification */
    size_t used, allocations;
    nh_memory_stats(&used, &allocations);
    fprintf(stderr, "[MEMORY_INT] Memory saved: %zu bytes, %zu allocations\n",
            used, allocations);

    fprintf(stderr, "[MEMORY_INT] === SAVE COMPLETE ===\n");
    return result;
}

/*
 * Restore game state WITH memory state
 * This wraps the original restgamestate() and adds memory load
 * Now enabled since restgamestate is exported
 */
int ios_restgamestate_with_memory(NHFILE *nhfp) {
    int result;
    const char *mem_path;

    fprintf(stderr, "[MEMORY_INT] === RESTORE WITH MEMORY STATE ===\n");

    /* CRITICAL: Load memory state FIRST */
    mem_path = get_memory_state_path();
    fprintf(stderr, "[MEMORY_INT] Loading memory state from: %s\n", mem_path);

    if (access(mem_path, R_OK) == 0) {
        if (nh_load_state(mem_path) != 0) {
            fprintf(stderr, "[MEMORY_INT] ERROR: Failed to load memory state!\n");
            fprintf(stderr, "[MEMORY_INT] Attempting fresh start...\n");
            nh_restart();
        } else {
            size_t used, allocations;
            nh_memory_stats(&used, &allocations);
            fprintf(stderr, "[MEMORY_INT] Memory restored: %zu bytes, %zu allocations\n",
                    used, allocations);
        }
    } else {
        fprintf(stderr, "[MEMORY_INT] WARNING: No memory state file found\n");
        fprintf(stderr, "[MEMORY_INT] Starting with fresh memory\n");
        nh_restart();
    }

    /* DO NOT initialize Lua here - restore_luadata will handle it
     * The correct flow is:
     * 1. Load memory state (restores heap)
     * 2. Call restgamestate which calls restore_luadata
     * 3. restore_luadata checks gl.luacore and initializes if NULL
     */

    /* Now restore the game state */
    fprintf(stderr, "[MEMORY_INT] Calling restgamestate()...\n");
    result = restgamestate(nhfp) ? 1 : 0;  /* Convert boolean to int */

    if (!result) {
        fprintf(stderr, "[MEMORY_INT] ERROR: restgamestate failed!\n");
    }

    fprintf(stderr, "[MEMORY_INT] === RESTORE COMPLETE ===\n");
    return result;
}

/*
 * Clean up memory state files (called on successful new game start)
 */
void ios_cleanup_memory_state(void) {
    const char *mem_path = get_memory_state_path();

    fprintf(stderr, "[MEMORY_INT] Cleaning up old memory state files\n");

    if (unlink(mem_path) == 0) {
        fprintf(stderr, "[MEMORY_INT] Deleted: %s\n", mem_path);
    }

    /* Reset allocator for new game */
    nh_restart();
    fprintf(stderr, "[MEMORY_INT] Memory allocator reset for new game\n");
}

/*
 * Debug function to dump memory state
 */
void ios_dump_memory_stats(void) {
    size_t used, allocations;
    nh_memory_stats(&used, &allocations);

    fprintf(stderr, "[MEMORY_STATS] ================================\n");
    /* Can't access internal heap details from here anymore */
    fprintf(stderr, "[MEMORY_STATS] Used: %zu bytes\n", used);
    fprintf(stderr, "[MEMORY_STATS] Allocations: %zu\n", allocations);
    fprintf(stderr, "[MEMORY_STATS] ================================\n");
}