/*
 * ios_restore.c - iOS restore/load implementation
 *
 * This handles loading saved games on iOS by properly extracting
 * level files from the savefile archive.
 *
 * CRITICAL: Now includes memory state management!
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include "../NetHack/include/hack.h"
#include "../NetHack/include/dlb.h"
#include "ios_memory_integration.h"
#include "../zone_allocator/nethack_memory_final.h"

/* External NetHack functions */
extern int dorecover(NHFILE *);
extern NHFILE *open_savefile(void);
extern int validate(NHFILE *, const char *, boolean);
extern void get_plname_from_file(NHFILE *, char *, boolean);
extern void getlev(NHFILE *, int, xint8);
extern boolean restgamestate(NHFILE *);
extern NHFILE *create_levelfile(int, char[]);
extern void savelev(NHFILE *, xint8);
extern void close_nhfile(NHFILE *);
extern NHFILE *get_freeing_nhfile(void);
extern int delete_savefile(void);
extern void nh_terminate(int);

/* External game state */
extern struct sinfo program_state;
extern struct flag flags;
extern struct you u;
extern struct version_info version;
extern char SAVEF[];
extern struct context_info g_context;

/*
 * iOS-specific restore function that properly extracts level files
 * Returns: 0 on failure, 1 on success
 *
 * UPDATED: Now delegates to ios_restore_complete() which has all the fixes
 */
int ios_restore_saved_game(void) {
    fprintf(stderr, "[IOS_RESTORE] Redirecting to ios_restore_complete()...\n");

    // Extract directory from SAVEF path
    const char *save_path = SAVEF;
    char save_dir[1024];

    if (save_path && strrchr(save_path, '/')) {
        char *last_slash = strrchr(save_path, '/');
        size_t dir_len = last_slash - save_path;
        strncpy(save_dir, save_path, dir_len);
        save_dir[dir_len] = '\0';
    } else {
        // No directory, use current directory
        strcpy(save_dir, ".");
    }

    fprintf(stderr, "[IOS_RESTORE] Using save directory: %s\n", save_dir);

    // Call the new implementation with all fixes
    extern int ios_restore_complete(const char* save_dir);
    int result = ios_restore_complete(save_dir);

    // Convert result code (ios_restore_complete returns 0 for success, we need 1)
    return (result == 0) ? 1 : 0;
}

/*
 * Check if the current save file exists
 * Returns: 1 if exists, 0 if not
 */
static int check_current_savefile_exists(void) {
    if (SAVEF[0] && access(SAVEF, R_OK) == 0) {
        fprintf(stderr, "[IOS_RESTORE] Save file exists at: %s\n", SAVEF);
        return 1;
    }
    fprintf(stderr, "[IOS_RESTORE] No save file found\n");
    return 0;
}

/*
 * Load a saved game - main entry point
 * Returns: 1 on success, 0 on failure, -1 if no save file
 *
 * UPDATED: Now uses ios_restore_saved_game() which delegates to the fixed implementation
 */
int ios_load_saved_game(void) {
    fprintf(stderr, "\n[IOS_LOAD] ========================================\n");
    fprintf(stderr, "[IOS_LOAD] Starting load saved game process\n");
    fprintf(stderr, "[IOS_LOAD] ========================================\n");

    /* Check if save file exists */
    if (!check_current_savefile_exists()) {
        fprintf(stderr, "[IOS_LOAD] No save file to load\n");
        return -1;
    }

    /* Call our restore function (which now delegates to ios_restore_complete) */
    int result = ios_restore_saved_game();

    if (result == 1) {
        fprintf(stderr, "[IOS_LOAD] Load completed successfully\n");

        /* List the created lock files to verify */
        fprintf(stderr, "[IOS_LOAD] Checking for lock files:\n");
        char lockfile[256];
        for (int i = 0; i <= 10; i++) {
            snprintf(lockfile, sizeof(lockfile), "1lock.%d", i);
            if (access(lockfile, F_OK) == 0) {
                fprintf(stderr, "[IOS_LOAD]   Found: %s\n", lockfile);
            }
        }
    } else {
        fprintf(stderr, "[IOS_LOAD] Load failed!\n");
    }

    fprintf(stderr, "[IOS_LOAD] ========================================\n\n");
    return result;
}

/*
 * NOTE: ios_get_save_info() is implemented in ios_save_integration.c
 * The version in ios_save_integration.c includes turn count and memory usage.
 */