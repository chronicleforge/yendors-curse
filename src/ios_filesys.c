/*
 * ios_filesys.c - iOS file system abstraction for NetHack
 *
 * Provides iOS-compatible paths for NetHack's save/load system
 */

#include "nethack_export.h"  // Symbol visibility control
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <CoreFoundation/CoreFoundation.h>

/* Include NetHack headers for struct definitions */
#include "../NetHack/include/hack.h"
#include "../NetHack/include/dlb.h"  /* for NHFILE */

/* NetHack function declarations */
extern const char* fqname(const char* basename, int whichprefix, int buffnum);

/* Define needed constants if not available */
#ifndef PATHLEN
#define PATHLEN 256
#endif

/* These should come from hack.h, but define them if missing
 * Using NetHack's actual values from hack.h */
#ifndef SAVEPREFIX
#define SAVEPREFIX 2      /* per-user save files */
#endif
#ifndef LEVELPREFIX
#define LEVELPREFIX 1     /* per-user level files */
#endif
#ifndef BONESPREFIX
#define BONESPREFIX 0     /* shared bones files */
#endif
#ifndef DATAPREFIX
#define DATAPREFIX 3      /* read-only data files */
#endif
#ifndef SCOREPREFIX
#define SCOREPREFIX 4     /* shared score files */
#endif
#ifndef LOCKPREFIX
#define LOCKPREFIX 5      /* per-user lock files */
#endif
#ifndef TROUBLEPREFIX
#define TROUBLEPREFIX 6   /* shared trouble files */
#endif

/* Don't define SAVEF here - NetHack uses gs.SAVEF internally.
 * We only need SAVEP for the save directory path.
 * On iOS/macOS we don't use MICRO so SAVEP isn't defined in NetHack */
NETHACK_EXPORT char SAVEP[256] = {0};

/* Get iOS Documents directory path */
NETHACK_EXPORT const char* get_ios_documents_path(void) {
    static char documents_path[PATHLEN];
    static int initialized = 0;

    if (!initialized) {
        /* Get REAL iOS sandbox Documents directory from Swift */
        extern int ios_swift_get_documents_path(char* buffer, int bufsize);

        if (ios_swift_get_documents_path(documents_path, PATHLEN) == 0) {
            fprintf(stderr, "[IOS_FILESYS] ERROR: Failed to get iOS Documents path from Swift!\n");
            /* Fallback to /tmp if Swift fails */
            snprintf(documents_path, sizeof(documents_path), "/tmp/NetHack");
        }

        /* Create directory if it doesn't exist */
        mkdir(documents_path, 0755);
        chmod(documents_path, 0755);

        /* NetHack will automatically create save/ subdirectory when needed */

        initialized = 1;
        fprintf(stderr, "[IOS_FILESYS] Documents path: %s\n", documents_path);
    }

    return documents_path;
}

/* Get bundle resource path using CoreFoundation (iOS native C API) */
static const char* ios_get_bundle_resource_path_c(void) {
    static char bundle_path[1024] = {0};
    static int initialized = 0;

    if (!initialized) {
        /* CRITICAL FIX: Look for lua_resources subdirectory in main bundle
         * The build script copies lua files to nethack/lua_resources/
         * which should be added to the Xcode project as a folder reference
         */
        CFBundleRef main_bundle = CFBundleGetMainBundle();
        if (main_bundle) {
            /* First try: lua_resources subdirectory (preferred location) */
            CFURLRef lua_resources_url = CFBundleCopyResourceURL(main_bundle,
                CFSTR("lua_resources"), NULL, NULL);

            if (lua_resources_url) {
                /* Found lua_resources folder - use it! */
                CFURLGetFileSystemRepresentation(lua_resources_url, true,
                    (UInt8*)bundle_path, sizeof(bundle_path));
                CFRelease(lua_resources_url);
                initialized = 1;
                fprintf(stderr, "[IOS_FILESYS] ✅ Found lua_resources in bundle: %s\n", bundle_path);
            } else {
                /* Fallback: main bundle resources directory */
                fprintf(stderr, "[IOS_FILESYS] ⚠️  lua_resources folder not found, using main bundle\n");
                CFURLRef resources_url = CFBundleCopyResourcesDirectoryURL(main_bundle);
                if (resources_url) {
                    CFURLGetFileSystemRepresentation(resources_url, true,
                        (UInt8*)bundle_path, sizeof(bundle_path));
                    CFRelease(resources_url);
                    initialized = 1;
                    fprintf(stderr, "[IOS_FILESYS] Bundle resource path (fallback): %s\n", bundle_path);
                }
            }
        }

        if (!initialized) {
            fprintf(stderr, "[IOS_FILESYS] ❌ ERROR: Cannot get bundle path!\n");
            fprintf(stderr, "[IOS_FILESYS]    Lua files will NOT be available!\n");
            fprintf(stderr, "[IOS_FILESYS]    Make sure lua_resources folder is added to Xcode project!\n");
            return NULL;
        }
    }

    return bundle_path;
}

/* Copy a single file from source to destination */
static int ios_copy_single_file(const char* src, const char* dest) {
    fprintf(stderr, "[IOS_FILESYS] ios_copy_single_file() ENTER\n");
    fprintf(stderr, "[IOS_FILESYS]   src: %s\n", src);
    fprintf(stderr, "[IOS_FILESYS]   dest: %s\n", dest);
    fflush(stderr);

    FILE* source = fopen(src, "rb");
    if (!source) {
        fprintf(stderr, "[IOS_FILESYS]   ERROR: fopen(src) failed - errno=%d (%s)\n", errno, strerror(errno));
        fflush(stderr);
        return 0;
    }

    FILE* target = fopen(dest, "wb");
    if (!target) {
        fprintf(stderr, "[IOS_FILESYS]   ERROR: fopen(dest) failed - errno=%d (%s)\n", errno, strerror(errno));
        fflush(stderr);
        fclose(source);
        return 0;
    }

    char buffer[4096];
    size_t bytes;
    size_t total_bytes = 0;
    while ((bytes = fread(buffer, 1, sizeof(buffer), source)) > 0) {
        fwrite(buffer, 1, bytes, target);
        total_bytes += bytes;
    }

    fclose(source);
    fclose(target);

    fprintf(stderr, "[IOS_FILESYS]   SUCCESS: Copied %zu bytes\n", total_bytes);
    fflush(stderr);
    return 1;
}

/* Create minimal stub data files for iOS */
static void ios_create_stub_data_files(const char* data_path) {
    fprintf(stderr, "[IOS_FILESYS] Creating stub data files...\n");

    /* Create a minimal rumors file with correct binary format */
    char rumors_path[BUFSZ];
    snprintf(rumors_path, sizeof(rumors_path), "%s/rumors", data_path);

    FILE *rf = fopen(rumors_path, "wb");
    if (rf) {
        /* Write header: "do not edit" line */
        fprintf(rf, "NetHack rumors file - do not edit.\n");

        /* Write format line: true_count, true_size, true_offset; false_count, false_size, false_offset; 0,0,eof_offset */
        /* Minimal file with 1 true rumor and 1 false rumor */
        const char *true_rumor = "Welcome to NetHack iOS!____________________________________________";
        const char *false_rumor = "This is just a stub file.__________________________________________";

        long true_start = 128;  /* After header */
        long true_size = strlen(true_rumor) + 1;
        long false_start = true_start + true_size;
        long false_size = strlen(false_rumor) + 1;
        long eof_offset = false_start + false_size;

        /* Write the format header */
        fprintf(rf, "1,%ld,%lx;1,%ld,%lx;0,0,%lx\n",
                true_size, true_start,
                false_size, false_start,
                eof_offset);

        /* Pad to offset 128 */
        long current = ftell(rf);
        while (current < true_start) {
            fputc('\n', rf);
            current++;
        }

        /* Write rumors */
        fwrite(true_rumor, 1, true_size, rf);
        fwrite(false_rumor, 1, false_size, rf);

        fclose(rf);
        fprintf(stderr, "[IOS_FILESYS] Created stub rumors file at %s\n", rumors_path);
    } else {
        fprintf(stderr, "[IOS_FILESYS] WARNING: Could not create rumors file at %s\n", rumors_path);
    }

    /* Create other stub files if needed in the future */
}

/* Copy all 130 lua files from app bundle to Documents/Data/ directory */
static void ios_copy_all_lua_files(const char* documents_path) {
    fprintf(stderr, "\n[IOS_FILESYS] ===== ios_copy_all_lua_files() ENTER =====\n");
    fprintf(stderr, "[IOS_FILESYS] documents_path parameter: %s\n", documents_path ? documents_path : "(NULL)");
    fflush(stderr);

    const char* bundle_path = ios_get_bundle_resource_path_c();
    fprintf(stderr, "[IOS_FILESYS] After ios_get_bundle_resource_path_c() call:\n");
    fprintf(stderr, "[IOS_FILESYS]   bundle_path = %s\n", bundle_path ? bundle_path : "(NULL)");
    fflush(stderr);

    if (!bundle_path) {
        fprintf(stderr, "[IOS_FILESYS] CRITICAL: Cannot get bundle path! ABORTING\n");
        fflush(stderr);
        return;
    }

    char data_dir[1024];
    snprintf(data_dir, sizeof(data_dir), "%s/Data", documents_path);
    fprintf(stderr, "[IOS_FILESYS] Built data_dir path: %s\n", data_dir);

    /* Create the Data directory if it doesn't exist */
    if (mkdir(data_dir, 0755) == 0) {
        fprintf(stderr, "[IOS_FILESYS] ✓ Created Data directory: %s\n", data_dir);
    } else if (errno == EEXIST) {
        fprintf(stderr, "[IOS_FILESYS] Data directory already exists: %s\n", data_dir);
    } else {
        fprintf(stderr, "[IOS_FILESYS] ERROR creating Data directory: %s (errno: %d - %s)\n",
                data_dir, errno, strerror(errno));
    }
    fflush(stderr);

    /* All 130 lua files from the bundle */
    const char* lua_files[] = {
        "dungeon.lua", "nhcore.lua", "nhlib.lua", "quest.lua",
        "Arc-fila.lua", "Arc-filb.lua", "Arc-goal.lua", "Arc-loca.lua", "Arc-strt.lua",
        "Bar-fila.lua", "Bar-filb.lua", "Bar-goal.lua", "Bar-loca.lua", "Bar-strt.lua",
        "Cav-fila.lua", "Cav-filb.lua", "Cav-goal.lua", "Cav-loca.lua", "Cav-strt.lua",
        "Hea-fila.lua", "Hea-filb.lua", "Hea-goal.lua", "Hea-loca.lua", "Hea-strt.lua",
        "Kni-fila.lua", "Kni-filb.lua", "Kni-goal.lua", "Kni-loca.lua", "Kni-strt.lua",
        "Mon-fila.lua", "Mon-filb.lua", "Mon-goal.lua", "Mon-loca.lua", "Mon-strt.lua",
        "Pri-fila.lua", "Pri-filb.lua", "Pri-goal.lua", "Pri-loca.lua", "Pri-strt.lua",
        "Ran-fila.lua", "Ran-filb.lua", "Ran-goal.lua", "Ran-loca.lua", "Ran-strt.lua",
        "Rog-fila.lua", "Rog-filb.lua", "Rog-goal.lua", "Rog-loca.lua", "Rog-strt.lua",
        "Sam-fila.lua", "Sam-filb.lua", "Sam-goal.lua", "Sam-loca.lua", "Sam-strt.lua",
        "Tou-fila.lua", "Tou-filb.lua", "Tou-goal.lua", "Tou-loca.lua", "Tou-strt.lua",
        "Val-fila.lua", "Val-filb.lua", "Val-goal.lua", "Val-loca.lua", "Val-strt.lua",
        "Wiz-fila.lua", "Wiz-filb.lua", "Wiz-goal.lua", "Wiz-loca.lua", "Wiz-strt.lua",
        "air.lua", "asmodeus.lua", "astral.lua", "baalz.lua", "castle.lua",
        "earth.lua", "fakewiz1.lua", "fakewiz2.lua", "fire.lua", "hellfill.lua",
        "juiblex.lua", "knox.lua", "oracle.lua", "orcus.lua", "sanctum.lua",
        "themerms.lua", "tower1.lua", "tower2.lua", "tower3.lua", "valley.lua",
        "water.lua", "wizard1.lua", "wizard2.lua", "wizard3.lua",
        "medusa-1.lua", "medusa-2.lua", "medusa-3.lua", "medusa-4.lua",
        "minefill.lua", "minend-1.lua", "minend-2.lua", "minend-3.lua",
        "minetn-1.lua", "minetn-2.lua", "minetn-3.lua", "minetn-4.lua",
        "minetn-5.lua", "minetn-6.lua", "minetn-7.lua",
        "bigrm-1.lua", "bigrm-2.lua", "bigrm-3.lua", "bigrm-4.lua",
        "bigrm-5.lua", "bigrm-6.lua", "bigrm-7.lua", "bigrm-8.lua",
        "bigrm-9.lua", "bigrm-10.lua", "bigrm-11.lua", "bigrm-12.lua",
        "soko1-1.lua", "soko1-2.lua", "soko2-1.lua", "soko2-2.lua",
        "soko3-1.lua", "soko3-2.lua", "soko4-1.lua", "soko4-2.lua",
        "tut-1.lua", "tut-2.lua",
        NULL
    };

    int copied = 0, skipped = 0;

    fprintf(stderr, "[IOS_FILESYS] Starting file copy loop (130 lua files)...\n");
    fflush(stderr);

    for (int i = 0; lua_files[i]; i++) {
        char src[1024], dest[1024];
        snprintf(src, sizeof(src), "%s/%s", bundle_path, lua_files[i]);
        snprintf(dest, sizeof(dest), "%s/%s", data_dir, lua_files[i]);

        /* Log first 5 files being processed */
        if (i < 5) {
            fprintf(stderr, "[IOS_FILESYS] Processing file #%d: %s\n", i, lua_files[i]);
            fprintf(stderr, "[IOS_FILESYS]   src: %s\n", src);
            fprintf(stderr, "[IOS_FILESYS]   dest: %s\n", dest);
            fflush(stderr);
        }

        /* Check if already exists with correct size */
        FILE* check = fopen(dest, "rb");
        if (check) {
            fseek(check, 0, SEEK_END);
            long size = ftell(check);
            fclose(check);

            if (size > 100) {  /* Valid file exists */
                skipped++;
                if (i < 5) {
                    fprintf(stderr, "[IOS_FILESYS]   SKIP: File exists with size=%ld bytes\n", size);
                    fflush(stderr);
                }
                continue;
            }
        }

        if (ios_copy_single_file(src, dest)) {
            copied++;
            fprintf(stderr, "[IOS_FILESYS] ✓ Copied %s (%d)\n", lua_files[i], copied);
            fflush(stderr);
        } else {
            fprintf(stderr, "[IOS_FILESYS] ✗ FAILED to copy %s\n", lua_files[i]);
            fflush(stderr);
        }
    }

    fprintf(stderr, "[IOS_FILESYS] Lua files: %d copied, %d skipped\n", copied, skipped);
    fprintf(stderr, "[IOS_FILESYS] ===== ios_copy_all_lua_files() EXIT =====\n\n");
    fflush(stderr);
}

/* Initialize NetHack's prefix system with iOS paths */
NETHACK_EXPORT void ios_init_file_prefixes(void) {
    const char* documents = get_ios_documents_path();
    char path_buffer[PATHLEN];

    fprintf(stderr, "[IOS_FILESYS] Initializing NetHack prefix system...\n");
    fprintf(stderr, "[IOS_FILESYS] Documents base path: %s\n", documents);

    /* CRITICAL: Set up NetHack's fqn_prefix array for proper path resolution */
    /* This is what fqname() uses to build full paths */

    /* SAVEPREFIX - for save files */
    /* NetHack automatically prepends "save/" to filenames on UNIX */
    /* So we just need to set the prefix to the base directory */
    snprintf(path_buffer, sizeof(path_buffer), "%s/", documents);
    gf.fqn_prefix[SAVEPREFIX] = dupstr(path_buffer);
    fprintf(stderr, "[IOS_FILESYS] Set SAVEPREFIX (index %d): %s\n", SAVEPREFIX, path_buffer);
    fprintf(stderr, "[IOS_FILESYS]   -> NetHack will add 'save/' to create: %ssave/\n", path_buffer);

    /* Create the save directory that NetHack expects to exist */
    char save_dir[PATHLEN];
    snprintf(save_dir, sizeof(save_dir), "%s/save", documents);
    if (mkdir(save_dir, 0755) == 0) {
        fprintf(stderr, "[IOS_FILESYS] Created save directory: %s\n", save_dir);
    } else {
        fprintf(stderr, "[IOS_FILESYS] Save directory exists or error: %s (errno: %d)\n", save_dir, errno);
    }
    chmod(save_dir, 0755);

    /* LEVELPREFIX - for level files */
    snprintf(path_buffer, sizeof(path_buffer), "%s/Levels/", documents);
    fprintf(stderr, "[IOS_FILESYS] Creating Levels directory: %s\n", path_buffer);
    if (mkdir(path_buffer, 0755) == 0) {
        fprintf(stderr, "[IOS_FILESYS]   -> Directory created successfully\n");
    } else {
        fprintf(stderr, "[IOS_FILESYS]   -> Directory exists or error (errno: %d - %s)\n",
                errno, strerror(errno));
    }
    gf.fqn_prefix[LEVELPREFIX] = dupstr(path_buffer);
    fprintf(stderr, "[IOS_FILESYS] Set LEVELPREFIX (index %d): %s\n", LEVELPREFIX, path_buffer);

    // Verify the values were set
    fprintf(stderr, "[IOS_FILESYS] Verification:\n");
    fprintf(stderr, "[IOS_FILESYS]   gf.fqn_prefix[%d] = %s\n", SAVEPREFIX,
            gf.fqn_prefix[SAVEPREFIX] ? gf.fqn_prefix[SAVEPREFIX] : "(NULL)");
    fprintf(stderr, "[IOS_FILESYS]   gf.fqn_prefix[%d] = %s\n", LEVELPREFIX,
            gf.fqn_prefix[LEVELPREFIX] ? gf.fqn_prefix[LEVELPREFIX] : "(NULL)");

    /* BONESPREFIX - for bones files */
    snprintf(path_buffer, sizeof(path_buffer), "%s/Bones/", documents);
    mkdir(path_buffer, 0755);
    gf.fqn_prefix[BONESPREFIX] = dupstr(path_buffer);
    fprintf(stderr, "[IOS_FILESYS] Set BONESPREFIX: %s\n", path_buffer);

    /* DATAPREFIX - for data files */
    snprintf(path_buffer, sizeof(path_buffer), "%s/Data/", documents);
    mkdir(path_buffer, 0755);
    gf.fqn_prefix[DATAPREFIX] = dupstr(path_buffer);
    fprintf(stderr, "[IOS_FILESYS] Set DATAPREFIX: %s\n", path_buffer);

    /* Create stub data files for iOS */
    ios_create_stub_data_files(path_buffer);

    /* SCOREPREFIX - for score files */
    snprintf(path_buffer, sizeof(path_buffer), "%s/score/", documents);
    mkdir(path_buffer, 0755);
    gf.fqn_prefix[SCOREPREFIX] = dupstr(path_buffer);
    fprintf(stderr, "[IOS_FILESYS] Set SCOREPREFIX: %s\n", path_buffer);

    /* LOCKPREFIX - for lock files */
    snprintf(path_buffer, sizeof(path_buffer), "%s/locks/", documents);
    mkdir(path_buffer, 0755);
    gf.fqn_prefix[LOCKPREFIX] = dupstr(path_buffer);
    fprintf(stderr, "[IOS_FILESYS] Set LOCKPREFIX: %s\n", path_buffer);

    /* TROUBLEPREFIX - for trouble/panic logs */
    snprintf(path_buffer, sizeof(path_buffer), "%s/trouble/", documents);
    mkdir(path_buffer, 0755);
    gf.fqn_prefix[TROUBLEPREFIX] = dupstr(path_buffer);
    fprintf(stderr, "[IOS_FILESYS] Set TROUBLEPREFIX: %s\n", path_buffer);

    /* SYSCONFPREFIX - for sysconf file */
    snprintf(path_buffer, sizeof(path_buffer), "%s/", documents);
    gf.fqn_prefix[7] = dupstr(path_buffer); /* SYSCONFPREFIX is 7 */
    fprintf(stderr, "[IOS_FILESYS] Set SYSCONFPREFIX (index 7): %s\n", path_buffer);

    /* Also set global SAVEP for compatibility */
    snprintf(SAVEP, PATHLEN, "%s/", documents);

    fprintf(stderr, "[IOS_FILESYS] NetHack prefix system initialized successfully!\n");

    /* Copy ALL lua files from app bundle to Documents/Data/ */
    ios_copy_all_lua_files(documents);

    // Create empty sysconf file to prevent initoptions from exiting
    char sysconf_path[BUFSZ];
    snprintf(sysconf_path, sizeof(sysconf_path), "%s/sysconf", documents);
    FILE *sysconf = fopen(sysconf_path, "w");
    if (sysconf) {
        fprintf(sysconf, "# iOS NetHack sysconf\n");
        fprintf(sysconf, "# Empty config - all defaults\n");
        fclose(sysconf);
        fprintf(stderr, "[IOS_FILESYS] Created empty sysconf file at: %s\n", sysconf_path);
    }
}

/* Initialize iOS save directory and paths */
void ios_init_savedir(void) {
    const char* documents = get_ios_documents_path();

    /* Set SAVEP to our Documents/NetHack directory */
    snprintf(SAVEP, PATHLEN, "%s/", documents);

    fprintf(stderr, "[IOS_FILESYS] Initialized SAVEP: %s\n", SAVEP);

    /* Create necessary directories */
    char path[PATHLEN];

    /* Levels directory */
    snprintf(path, sizeof(path), "%s/Levels", documents);
    mkdir(path, 0755);

    /* Bones directory */
    snprintf(path, sizeof(path), "%s/Bones", documents);
    mkdir(path, 0755);

    /* NetHack will create save/ directory automatically when needed */

    fprintf(stderr, "[IOS_FILESYS] All directories created\n");
}

/* Simplified: Just ensure directories exist, let NetHack handle the rest */
void ios_ensure_directories(void) {
    const char* documents = get_ios_documents_path();
    char path[PATHLEN];

    fprintf(stderr, "\n[IOS_FILESYS] === ENSURING ALL DIRECTORIES ===\n");
    fprintf(stderr, "[IOS_FILESYS] Documents path: %s\n", documents);

    /* Create necessary directories with proper permissions */
    /* Create save directory explicitly - NetHack's creat() needs it to exist */
    snprintf(path, sizeof(path), "%s/save", documents);
    mkdir(path, 0755);
    chmod(path, 0755);

    snprintf(path, sizeof(path), "%s/Levels", documents);
    mkdir(path, 0755);
    chmod(path, 0755);

    snprintf(path, sizeof(path), "%s/Bones", documents);
    mkdir(path, 0755);
    chmod(path, 0755);

    snprintf(path, sizeof(path), "%s/Data", documents);
    mkdir(path, 0755);
    chmod(path, 0755);

    snprintf(path, sizeof(path), "%s/score", documents);
    mkdir(path, 0755);
    chmod(path, 0755);

    snprintf(path, sizeof(path), "%s/locks", documents);
    mkdir(path, 0755);
    chmod(path, 0755);

    snprintf(path, sizeof(path), "%s/trouble", documents);
    mkdir(path, 0755);
    chmod(path, 0755);

    fprintf(stderr, "[IOS_FILESYS] All directories created with proper permissions\n");
}

/* Check if a save file exists */
int ios_savefile_exists(const char* filename) {
    const char* fullpath = fqname(filename, SAVEPREFIX, 0);
    return (access(fullpath, F_OK) == 0) ? 1 : 0;
}

/* Delete a save file */
int ios_delete_savefile(const char* filename) {
    const char* fullpath = fqname(filename, SAVEPREFIX, 0);
    int result = unlink(fullpath);
    fprintf(stderr, "[IOS_FILESYS] Delete savefile %s: %s\n",
            fullpath, (result == 0) ? "success" : "failed");
    return result;
}

/* Get the save directory path for listing saves */
void ios_get_save_dir(char *buf, size_t buflen) {
    if (!buf || buflen == 0) return;

    // Get the iOS documents directory
    const char* ios_dir = get_ios_documents_path();
    if (!ios_dir) {
        buf[0] = '\0';
        return;
    }

    // NetHack automatically creates and uses save/ subdirectory
    snprintf(buf, buflen, "%s/save", ios_dir);
}

/* Simple iOS fix: Just ensure the save directory exists when fqname is called */
void ios_ensure_save_dir_exists(void) {
    extern struct instance_globals_s gs;

    fprintf(stderr, "\n[IOS_FILESYS] === ENSURE SAVE DIR EXISTS ===\n");
    fprintf(stderr, "[IOS_FILESYS] gs.SAVEF = '%s'\n", gs.SAVEF);
    fprintf(stderr, "[IOS_FILESYS] strlen(gs.SAVEF) = %zu\n", strlen(gs.SAVEF));

    /* Build absolute path directly - don't rely on fqname() */
    const char* documents = get_ios_documents_path();
    char save_dir[PATHLEN];

    /* We want the save directory: Documents/NetHack/save */
    snprintf(save_dir, sizeof(save_dir), "%s/save", documents);
    fprintf(stderr, "[IOS_FILESYS] Save directory: %s\n", save_dir);

    /* Create all parent directories */
    char tmp[PATHLEN];
    strncpy(tmp, save_dir, PATHLEN - 1);
    tmp[PATHLEN - 1] = '\0';

    for (char* p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            int res = mkdir(tmp, 0755);
            if (res == 0 || errno == EEXIST) {
                fprintf(stderr, "[IOS_FILESYS]   Created/verified: %s\n", tmp);
            } else {
                fprintf(stderr, "[IOS_FILESYS]   mkdir('%s') failed: %s\n", tmp, strerror(errno));
            }
            *p = '/';
        }
    }

    /* Create final directory */
    int final_res = mkdir(tmp, 0755);
    if (final_res == 0 || errno == EEXIST) {
        fprintf(stderr, "[IOS_FILESYS] ✓ Save directory ready: %s\n", tmp);
    } else {
        fprintf(stderr, "[IOS_FILESYS] ⚠️  mkdir failed: %s\n", strerror(errno));
    }

    chmod(tmp, 0755);

    /* Verify directory exists and is writable */
    struct stat st;
    if (stat(tmp, &st) == 0 && S_ISDIR(st.st_mode)) {
        fprintf(stderr, "[IOS_FILESYS] ✓ Directory exists and is valid\n");
        if (access(tmp, W_OK) == 0) {
            fprintf(stderr, "[IOS_FILESYS] ✓ Directory is writable\n");
        } else {
            fprintf(stderr, "[IOS_FILESYS] ⚠️  Directory not writable\n");
        }
    } else {
        fprintf(stderr, "[IOS_FILESYS] ⚠️  Directory check failed\n");
    }
    fprintf(stderr, "[IOS_FILESYS] ==============================\n\n");
}