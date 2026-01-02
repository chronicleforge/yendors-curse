/*
 * ios_dylib_stubs.c - Platform-specific stubs for dylib build
 *
 * This file contains ONLY stubs that have NO Swift dependencies.
 * For static library builds compiled by Xcode, use ios_stubs.c instead.
 */

#include "nethack_export.h"  // Symbol visibility control
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <setjmp.h>  /* For clean game exit without crashing */
#include "../NetHack/include/hack.h"
#ifdef USE_ZONE_ALLOCATOR
#include "../zone_allocator/nethack_zone.h"
#endif

/* Define the buffer size BEFORE including the header to avoid macro conflicts */
#define OUTPUT_BUFFER_SIZE 8192

/* Global data - shared within dylib, accessed via functions externally
 * IMPORTANT: Do NOT use the output_buffer macro in this file!
 * The macro is for USERS of the buffer, not the PROVIDER.
 * Note: Not static so ios_winprocs.c can access it directly.
 */
char internal_output_buffer[OUTPUT_BUFFER_SIZE] = {0};

/* Now include the header which defines the accessor macros */
#include "nethack_bridge_common.h"

/* Accessor functions - ALWAYS export reliably from dylib */
NETHACK_EXPORT char* nethack_get_output_buffer(void) {
    fprintf(stderr, "[ACCESSOR] nethack_get_output_buffer() called, returning %p\n", (void*)internal_output_buffer);
    fflush(stderr);
    return internal_output_buffer;
}

NETHACK_EXPORT void nethack_clear_output_buffer(void) {
    memset(internal_output_buffer, 0, OUTPUT_BUFFER_SIZE);
}

NETHACK_EXPORT size_t nethack_get_output_buffer_size(void) {
    return OUTPUT_BUFFER_SIZE;
}

/* Safe append function - avoids __strncat_chk issues with function-returned buffers */
NETHACK_EXPORT void nethack_append_output(const char* text) {
    /* CRITICAL: Check for NULL AND invalid low addresses (error codes, offsets, etc.)
     * iOS can pass invalid pointers like 0x20 which are not NULL but still invalid! */
    if (!text || (uintptr_t)text < 4096) {
        fprintf(stderr, "[APPEND_OUTPUT] WARNING: Invalid pointer %p, skipping\n", (void*)text);
        return;
    }

    /* Use strnlen for safety - won't read past buffer end even if not null-terminated */
    size_t current_len = strnlen(internal_output_buffer, OUTPUT_BUFFER_SIZE);
    size_t text_len = strnlen(text, OUTPUT_BUFFER_SIZE);
    size_t available = OUTPUT_BUFFER_SIZE - current_len - 1; /* -1 for null terminator */

    if (text_len > available) {
        text_len = available;
    }

    if (text_len > 0) {
        memcpy(internal_output_buffer + current_len, text, text_len);
        internal_output_buffer[current_len + text_len] = '\0';
    }
}

/* Dylib constructor - CRITICAL for proper initialization
 * This runs BEFORE any exported functions are called,
 * ensuring output_buffer is zeroed before first use.
 */
__attribute__((constructor))
static void dylib_init(void) {
    // Explicitly zero output_buffer on dylib load
    memset(internal_output_buffer, 0, OUTPUT_BUFFER_SIZE);
    fprintf(stderr, "[DYLIB_INIT] output_buffer initialized at %p, size=%d\n",
            (void*)internal_output_buffer, OUTPUT_BUFFER_SIZE);
    fflush(stderr);
}

/* Global flag to track if early_init has been called */
static int global_early_init_done = 0;

/* Check if early init is complete - needed by ios_newgame.c */
NETHACK_EXPORT int is_early_init_done(void) {
    return global_early_init_done;
}

/**
 * CRITICAL: Reset early init flag for dylib reload
 *
 * macOS can reuse dylib memory addresses, meaning static variables
 * persist across dlclose/dlopen cycles!
 *
 * Without this reset, Game 2+ skips ios_early_init() → gi.invent not zeroed
 * → stale pointers → "0 +1 spears" corruption!
 */
NETHACK_EXPORT void ios_reset_early_init_flag(void) {
    fprintf(stderr, "[IOS_EARLY_INIT] Resetting global_early_init_done = 0\n");
    global_early_init_done = 0;
}

/* Early initialization - CRITICAL for NetHack globals */
NETHACK_EXPORT void ios_early_init(void) {
    if (global_early_init_done) {
        fprintf(stderr, "[IOS_EARLY_INIT] Already initialized globally, skipping\n");
        return;
    }
    global_early_init_done = 1;

    fprintf(stderr, "[IOS_EARLY_INIT] Starting early initialization...\n");
    fflush(stderr);

    fprintf(stderr, "[IOS_EARLY_INIT] Zeroing global structures first...\n");

    /* CRITICAL: Zero out ALL global structures first */
    extern struct instance_globals_a ga;
    extern struct instance_globals_b gb;
    extern struct instance_globals_c gc;
    extern struct instance_globals_d gd;
    extern struct instance_globals_e ge;
    extern struct instance_globals_f gf;
    extern struct instance_globals_g gg;
    extern struct instance_globals_h gh;
    extern struct instance_globals_i gi;
    extern struct instance_globals_j gj;
    extern struct instance_globals_k gk;
    extern struct instance_globals_l gl;
    extern struct instance_globals_m gm;
    extern struct instance_globals_n gn;
    extern struct instance_globals_o go;
    extern struct instance_globals_p gp;
    extern struct instance_globals_q gq;
    extern struct instance_globals_r gr;
    extern struct instance_globals_s gs;
    extern struct instance_globals_t gt;
    extern struct instance_globals_u gu;
    extern struct instance_globals_v gv;
    extern struct instance_globals_w gw;
    extern struct instance_globals_x gx;
    extern struct instance_globals_y gy;
    extern struct instance_globals_z gz;

    memset(&ga, 0, sizeof(ga));
    memset(&gb, 0, sizeof(gb));
    memset(&gc, 0, sizeof(gc));
    memset(&gd, 0, sizeof(gd));
    memset(&ge, 0, sizeof(ge));
    memset(&gf, 0, sizeof(gf));
    memset(&gg, 0, sizeof(gg));
    memset(&gh, 0, sizeof(gh));
    memset(&gi, 0, sizeof(gi));
    memset(&gj, 0, sizeof(gj));
    memset(&gk, 0, sizeof(gk));
    memset(&gl, 0, sizeof(gl));
    memset(&gm, 0, sizeof(gm));
    memset(&gn, 0, sizeof(gn));
    memset(&go, 0, sizeof(go));
    memset(&gp, 0, sizeof(gp));
    memset(&gq, 0, sizeof(gq));
    memset(&gr, 0, sizeof(gr));
    memset(&gs, 0, sizeof(gs));
    memset(&gt, 0, sizeof(gt));
    memset(&gu, 0, sizeof(gu));
    memset(&gv, 0, sizeof(gv));
    memset(&gw, 0, sizeof(gw));
    memset(&gx, 0, sizeof(gx));
    memset(&gy, 0, sizeof(gy));
    memset(&gz, 0, sizeof(gz));

    fprintf(stderr, "[IOS_EARLY_INIT] Global structures zeroed\n");
    fflush(stderr);

    fprintf(stderr, "[IOS_EARLY_INIT] Calling individual init functions...\n");
    fflush(stderr);

    /* Call the init functions that early_init would call */
    extern void decl_globals_init(void);
    extern void objects_globals_init(void);
    extern void monst_globals_init(void);
    extern void sys_early_init(void);
    extern void runtime_info_init(void);

    fprintf(stderr, "[IOS_EARLY_INIT]   Calling decl_globals_init()...\n");
    decl_globals_init();

    fprintf(stderr, "[IOS_EARLY_INIT]   Calling objects_globals_init()...\n");
    objects_globals_init();

    fprintf(stderr, "[IOS_EARLY_INIT]   Calling monst_globals_init()...\n");
    monst_globals_init();

    fprintf(stderr, "[IOS_EARLY_INIT]   Calling sys_early_init()...\n");
    sys_early_init();

    fprintf(stderr, "[IOS_EARLY_INIT]   Calling runtime_info_init()...\n");
    runtime_info_init();

    /* CRITICAL: Initialize savefile procedures */
    extern void sf_init(void);
    fprintf(stderr, "[IOS_EARLY_INIT]   Calling sf_init()...\n");
    sf_init();

    fprintf(stderr, "[IOS_EARLY_INIT] All init functions completed\n");
    fflush(stderr);
}

/* Platform-specific functions required by NetHack */

/* after_opt_showpaths - called when showing paths (--showpaths option) */
ATTRNORETURN void after_opt_showpaths(const char *msg) NORETURN;
NETHACK_EXPORT void after_opt_showpaths(const char *msg) {
    fprintf(stderr, "[iOS] showpaths: %s\n", msg ? msg : "(null)");
    exit(0);  /* Exit cleanly after showing paths */
}

/* authorize_explore_mode - called when entering explore/discovery mode */
NETHACK_EXPORT boolean authorize_explore_mode(void) {
    fprintf(stderr, "[iOS] authorize_explore_mode: always TRUE\n");
    return TRUE;  /* Always allow explore mode on iOS */
}

/* authorize_wizard_mode - called when entering wizard/debug mode */
NETHACK_EXPORT boolean authorize_wizard_mode(void) {
    fprintf(stderr, "[iOS] authorize_wizard_mode: always TRUE\n");
    return TRUE;  /* Always allow wizard mode on iOS */
}

/* error - NORETURN error handler */
ATTRNORETURN void error(const char *fmt, ...) NORETURN;
NETHACK_EXPORT void error(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[ERROR] ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
    exit(1);
}

/*
 * CRITICAL FIX: Clean exit from death via setjmp/longjmp
 *
 * PROBLEM: After player death, really_done() calls freedynamicdata() which
 * frees ALL game memory (monsters, items, level data). Then nh_terminate()
 * calls nethack_exit() which on iOS just returns (can't call exit() - would
 * kill app). Control unwinds back through the call stack, but all game data
 * is now FREED. When execution continues in moveloop_core(), it accesses
 * freed memory and CRASHES.
 *
 * SOLUTION: Use setjmp() in nethack_run_game_threaded() to establish a return
 * point. When nethack_exit() is called (after freedynamicdata()), longjmp()
 * directly back to the setjmp point, bypassing the corrupted call stack.
 *
 * This is safe because:
 * 1. freedynamicdata() already cleaned up all game resources
 * 2. longjmp() is specifically designed for this kind of non-local return
 * 3. The jmp_buf is set fresh for each game session
 */
jmp_buf ios_game_exit_jmp;      /* Jump buffer for clean exit */
int ios_game_exit_jmp_set = 0;  /* Flag: is jmp_buf valid? */
int ios_game_exit_status = 0;   /* Exit status to pass back */
int ios_freedynamicdata_done = 0;  /* Flag: freedynamicdata already called (via death) */

/* Platform exit function - uses longjmp to exit cleanly after death */
NETHACK_EXPORT void nethack_exit(int status) {
    fprintf(stderr, "[iOS] nethack_exit called with status: %d\n", status);

    /* Store exit status for caller */
    ios_game_exit_status = status;

    /*
     * If jmp_buf is set (we're inside nethack_run_game_threaded),
     * longjmp back to cleanly exit without crashing.
     *
     * This bypasses the corrupted call stack after freedynamicdata()
     * freed all game memory.
     */
    if (ios_game_exit_jmp_set) {
        fprintf(stderr, "[iOS] Using longjmp to exit cleanly from game loop\n");
        ios_game_exit_jmp_set = 0;  /* Reset before jump */
        ios_freedynamicdata_done = 1;  /* Mark that cleanup already happened */
        longjmp(ios_game_exit_jmp, 1);  /* Jump back to setjmp point */
        /* NOTREACHED */
    }

    /* If jmp_buf not set (shouldn't happen), just return */
    fprintf(stderr, "[iOS] WARNING: nethack_exit called without jmp_buf set\n");
}

/* File regularization - convert filename to valid format */
NETHACK_EXPORT void regularize(char *str) {
    /* On iOS, we just leave filenames as-is */
    /* Could add logic to replace invalid characters if needed */
}

/* Stub functions that return "not implemented" */
NETHACK_EXPORT int child(int dummy) {
    return 0;  /* Not supported on iOS */
}

NETHACK_EXPORT int dosh(void) {
    return 0;  /* Shell not supported on iOS */
}

NETHACK_EXPORT int dosuspend(void) {
    return 0;  /* Suspend not supported on iOS */
}

NETHACK_EXPORT void port_insert_pastebuf(char *str) {
    /* Paste buffer not implemented */
}

NETHACK_EXPORT void introff(void) {
    /* Terminal interrupt control not needed on iOS */
}

NETHACK_EXPORT void intron(void) {
    /* Terminal interrupt control not needed on iOS */
}

NETHACK_EXPORT int more(void) {
    return 0;  /* "more" paging not needed on iOS */
}

/* Config file stub */
FILE* fopen_config_file(const char* filename, int src) {
    /* No config files on iOS - settings come from app preferences */
    return NULL;
}

/* Regex stubs - minimal implementations */
__attribute__((visibility("default")))
struct nhregex *regex_init(void) {
    return NULL;
}

NETHACK_EXPORT boolean regex_compile(const char *pattern, struct nhregex *re) {
    return FALSE;
}

__attribute__((visibility("default")))
char *regex_error_desc(struct nhregex *re, char *buf) {
    if (buf) {
        strncpy(buf, "regex not implemented", 255);
        buf[255] = '\0';
    }
    return buf;
}

NETHACK_EXPORT void regex_free(struct nhregex *re) {
    /* Nothing to free */
}

NETHACK_EXPORT boolean regex_match(const char *str, struct nhregex *re) {
    return FALSE;
}

__attribute__((visibility("default")))
const char *regex_id(void) {
    return "none";
}

/* System random seed - use iOS native arc4random */
__attribute__((visibility("default")))
unsigned long sys_random_seed(void) {
    return (unsigned long)arc4random();
}

/* TTY stubs - minimal implementations */
static void tty_init_nhwindows(int *argc, char **argv);
static void tty_exit_nhwindows(const char *msg);
static void tty_raw_print(const char *str);
static void tty_raw_print_bold(const char *str);
static void tty_curs(winid window, int x, int y);
static void tty_putstr(winid window, int attr, const char *str);
static void tty_wait_synch(void);

/* Minimal TTY procs to pass choose_windows("tty") */
__attribute__((visibility("default")))
struct window_procs tty_procs = {
    "tty",  /* name */
    0,      /* type */
    0L, 0L, /* wincap, wincap2 */
    { 0 },  /* has_color array */
    tty_init_nhwindows,
    0, /* player_selection */
    0, /* askname */
    0, /* get_nh_event */
    tty_exit_nhwindows,
    0, /* suspend_nhwindows */
    0, /* resume_nhwindows */
    0, /* create_nhwindow */
    0, /* clear_nhwindow */
    0, /* display_nhwindow */
    0, /* destroy_nhwindow */
    tty_curs,
    tty_putstr,
    0, /* putmixed */
    0, /* display_file */
    0, /* start_menu */
    0, /* add_menu */
    0, /* end_menu */
    0, /* select_menu */
    0, /* message_menu */
    0, /* mark_synch */
    tty_wait_synch,
#ifdef CLIPPING
    0, /* cliparound */
#endif
#ifdef POSITIONBAR
    0, /* update_positionbar */
#endif
    0, /* print_glyph */
    tty_raw_print,
    tty_raw_print_bold,
};

static void tty_init_nhwindows(int *argc, char **argv) {
    extern struct instance_flags iflags;
    iflags.window_inited = TRUE;
}

static void tty_exit_nhwindows(const char *msg) {
    /* Nothing to do */
}

static void tty_curs(winid window, int x, int y) {
    /* Nothing to do */
}

static void tty_putstr(winid window, int attr, const char *str) {
    fprintf(stderr, "[TTY] %s\n", str ? str : "(null)");
}

static void tty_raw_print(const char *str) {
    fprintf(stderr, "[RAW] %s\n", str ? str : "(null)");
}

static void tty_raw_print_bold(const char *str) {
    fprintf(stderr, "[BOLD] %s\n", str ? str : "(null)");
}

static void tty_wait_synch(void) {
    /* Nothing to do */
}

NETHACK_EXPORT void win_tty_init(int dir) {
    /* Minimal initialization - iOS will override with its own procs */
}

/* Additional TTY stubs */
NETHACK_EXPORT void gettty(void) {
    /* Nothing to do */
}

NETHACK_EXPORT void settty(const char *s) {
    /* Nothing to do */
}

NETHACK_EXPORT void setftty(void) {
    /* Nothing to do */
}

NETHACK_EXPORT int tgetch(void) {
    return 0;
}

/* File exists check */
NETHACK_EXPORT boolean file_exists(const char *path) {
    if (!path) return FALSE;
    return (access(path, F_OK) == 0);
}

/* nomakedefs structure - version and build info */
__attribute__((visibility("default")))
struct nomakedefs_s nomakedefs = {
    "Thu, 18-Sep-2025 13:00:00 PDT",  /* build_date */
    "NetHack iOS Port",                /* copyright_banner_c */
    NULL,                              /* git_sha */
    "iOS-Port",                        /* git_branch */
    NULL,                              /* git_prefix */
    "3.7.0",                           /* version_string */
    "NetHack Version 3.7.0 - iOS Port", /* version_id */
    0x03070000UL,                      /* version_number */
    0x00000000UL,                      /* version_features */
    0x00000000UL,                      /* ignored_features */
    0x00000000UL,                      /* version_sanity1 */
    0UL                                /* build_time */
};

NETHACK_EXPORT void populate_nomakedefs(struct version_info *vi) {
    /* Initialize nomakedefs with version info */
    if (vi) {
        nomakedefs.version_number = vi->incarnation;
        nomakedefs.version_features = vi->feature_set;
        nomakedefs.version_sanity1 = vi->entity_count;
    }

    /* Set reasonable defaults if not provided */
    if (nomakedefs.version_number == 0) {
        nomakedefs.version_number = 0x03070000UL; /* 3.7.0 */
    }
}

NETHACK_EXPORT void free_nomakedefs(void) {
    /* Nothing to free for static initialization */
}

/* ============================================================================
 * DLB (Data Librarian) Implementation for iOS
 * This provides the dlb_* functions for loading data files from the iOS bundle.
 * ============================================================================ */

#include "ios_raw_file.h"  /* For ios_raw_file_data structure */
#include "RealNetHackBridge.h"  /* For DLB_LOG macro */

/* DLB structure - represents an open file in memory */
typedef struct dlb {
    const char* content;
    size_t size;
    size_t pos;
    int is_allocated;  /* 1 if content needs to be freed */
} dlb;

/* Forward declarations for Swift bridge functions */
extern const char* ios_get_dungeon_lua(void);  /* From ios_dungeon.c */
extern char* ios_swift_load_lua_file(const char* filename);   /* From Swift */
extern char* ios_swift_load_data_file(const char* filename);  /* From Swift (general loader) */
extern int ios_swift_file_exists(const char* filename);       /* From Swift */

static int dlb_initialized = 0;

/* Initialize DLB system */
NETHACK_EXPORT boolean dlb_init(void) {
    dlb_initialized = 1;
    fprintf(stderr, "[DLB] Data Librarian initialized for iOS\n");
    return TRUE;
}

NETHACK_EXPORT void dlb_cleanup(void) {
    dlb_initialized = 0;
}

/* Open a data file from the iOS bundle
 * This is the CRITICAL function for loading Lua files and other data files.
 * It tries multiple loading strategies in order:
 * 1. Documents/NetHack/Data/ directory FIRST (writable, where files are copied)
 * 2. iOS Bundle (read-only, embedded resources)
 * 3. Hardcoded fallbacks for critical files
 */
NETHACK_EXPORT dlb* dlb_fopen(const char* filename, const char* mode) {
    fprintf(stderr, "[DLB] dlb_fopen: %s (mode: %s)\n", filename, mode);
    fflush(stderr);

    if (!filename) {
        fprintf(stderr, "[DLB] ERROR: NULL filename passed\n");
        fflush(stderr);
        return NULL;
    }

    /* STRATEGY 1: Try Documents/NetHack/Data/ directory FIRST
     * This is where ios_copy_all_lua_files() copies the 130 Lua files.
     * NetHack's fqn_prefix[DATAPREFIX] points to this directory.
     */
    extern const char* fqname(const char* basename, int whichprefix, int buffnum);
    const char* documents_path = fqname(filename, DATAPREFIX, 0);
    if (documents_path) {
        DLB_LOG("Trying Documents/Data: %s", documents_path);
        fprintf(stderr, "[DLB] Trying Documents/Data: %s\n", documents_path);
        fflush(stderr);

        FILE* fp = fopen(documents_path, mode);
        if (fp) {
            /* Get file size */
            fseek(fp, 0, SEEK_END);
            long file_size = ftell(fp);
            fseek(fp, 0, SEEK_SET);

            if (file_size > 0) {
                /* Allocate buffer and read entire file */
                char* file_content = (char*)alloc(file_size + 1);
                if (!file_content) {
                    fclose(fp);
                    fprintf(stderr, "[DLB] ERROR: Failed to allocate %ld bytes for file content\n", file_size);
                    return NULL;
                }

                size_t read_bytes = fread(file_content, 1, file_size, fp);
                fclose(fp);

                if (read_bytes != file_size) {
                    zone_free(file_content);
                    fprintf(stderr, "[DLB] ERROR: Read %zu bytes but expected %ld\n", read_bytes, file_size);
                    return NULL;
                }

                file_content[file_size] = '\0';  /* Null terminator for safety */

                /* Create dlb structure */
                dlb* file = (dlb*)alloc(sizeof(dlb));
                if (!file) {
                    zone_free(file_content);
                    fprintf(stderr, "[DLB] ERROR: Failed to allocate dlb structure\n");
                    return NULL;
                }

                file->content = file_content;
                file->size = file_size;
                file->pos = 0;
                file->is_allocated = 1;

                DLB_LOG("✓ Found in Documents/Data: %s (%ld bytes)", filename, file_size);
                fprintf(stderr, "[DLB] ✓ Found in Documents/Data: %s (%ld bytes)\n", filename, file_size);
                fflush(stderr);
                return file;
            } else {
                fclose(fp);
                fprintf(stderr, "[DLB] WARNING: File exists but is empty: %s\n", documents_path);
            }
        } else {
            fprintf(stderr, "[DLB] Not found in Documents/Data: %s (errno: %d - %s)\n",
                    documents_path, errno, strerror(errno));
        }
    }

    /* STRATEGY 2: Try to load from bundle using Swift */
    DLB_LOG("Trying bundle for %s...", filename);
    fprintf(stderr, "[DLB] Trying bundle for %s...\n", filename);

    /* NEW: Try raw loading for Lua files first (no string conversion!) */
    if (strstr(filename, ".lua")) {
        ios_raw_file_data* raw_data = ios_swift_load_raw_lua_file(filename);
        if (raw_data && raw_data->data && raw_data->size > 0) {
            dlb* file = (dlb*)alloc(sizeof(dlb));
            if (!file) {
                ios_swift_free_raw_file(raw_data);
                fprintf(stderr, "[DLB] ERROR: Failed to allocate dlb structure\n");
                return NULL;
            }

            /* Copy raw bytes into zone memory */
            char* zone_content = (char*)alloc(raw_data->size + 1);  /* +1 for safety null terminator */
            if (!zone_content) {
                zone_free(file);
                ios_swift_free_raw_file(raw_data);
                fprintf(stderr, "[DLB] ERROR: Failed to allocate zone memory for content\n");
                return NULL;
            }

            /* Copy the RAW BYTES - no string conversion! */
            memcpy(zone_content, raw_data->data, raw_data->size);
            zone_content[raw_data->size] = '\0';  /* Add null terminator for safety */

            file->content = zone_content;
            file->size = raw_data->size;  /* Use actual file size! */
            file->pos = 0;
            file->is_allocated = 1;

            DLB_LOG("✓ Loaded RAW from bundle: %s (%zu bytes)", filename, file->size);
            fprintf(stderr, "[DLB] ✓ Loaded RAW from bundle: %s (%zu actual bytes)\n", filename, file->size);

            /* Show first few bytes in hex for debugging */
            fprintf(stderr, "[DLB] First 20 bytes (hex): ");
            for (int i = 0; i < 20 && i < raw_data->size; i++) {
                fprintf(stderr, "%02x ", (unsigned char)zone_content[i]);
            }
            fprintf(stderr, "\n");

            /* Free the Swift-allocated structure */
            ios_swift_free_raw_file(raw_data);
            return file;
        }
    }

    /* OLD: Fallback to string-based loading for non-Lua files */
    char* bundle_content = ios_swift_load_data_file(filename);
    if (!bundle_content && strstr(filename, ".lua")) {
        /* Double fallback to old lua loader if raw fails */
        bundle_content = ios_swift_load_lua_file(filename);
    }

    if (bundle_content) {
        dlb* file = (dlb*)alloc(sizeof(dlb));
        if (!file) {
            free(bundle_content);  /* Swift uses strdup which needs regular free */
            fprintf(stderr, "[DLB] ERROR: Failed to allocate dlb structure\n");
            return NULL;
        }

        /* Copy Swift-allocated content into zone memory */
        size_t content_size = strlen(bundle_content) + 1;
        char* zone_content = (char*)alloc(content_size);
        if (!zone_content) {
            zone_free(file);
            free(bundle_content);  /* Free Swift memory */
            fprintf(stderr, "[DLB] ERROR: Failed to allocate zone memory for content\n");
            return NULL;
        }
        /* Note: nh_malloc now clears memory automatically, no memset needed */
        memcpy(zone_content, bundle_content, content_size);

        /* Free the Swift-allocated memory now that we've copied it */
        free(bundle_content);

        file->content = zone_content;
        file->size = content_size - 1;  /* Don't include null terminator in size */
        file->pos = 0;
        file->is_allocated = 1;  /* Mark that content needs to be freed (zone memory) */
        DLB_LOG("✓ Loaded from bundle: %s (%zu bytes)", filename, file->size);
        fprintf(stderr, "[DLB] ✓ Loaded from bundle: %s (%zu bytes)\n", filename, file->size);
        fprintf(stderr, "[DLB] First 100 chars: %.100s\n", zone_content);
        return file;
    } else {
        DLB_LOG("File NOT found in bundle: %s", filename);
        fprintf(stderr, "[DLB] File NOT found in bundle: %s\n", filename);
    }

    /* Fallback to hardcoded versions for critical files */
    if (strcmp(filename, "dungeon.lua") == 0) {
        dlb* file = (dlb*)alloc(sizeof(dlb));
        if (!file) {
            fprintf(stderr, "[DLB] ERROR: Failed to allocate dlb structure\n");
            fflush(stderr);
            return NULL;
        }

        file->content = ios_get_dungeon_lua();
        if (!file->content) {
            fprintf(stderr, "[DLB] ERROR: ios_get_dungeon_lua returned NULL\n");
            fflush(stderr);
            zone_free(file);
            return NULL;
        }

        file->size = strlen(file->content);
        file->pos = 0;
        file->is_allocated = 0;  /* Static content, don't free */
        fprintf(stderr, "[DLB] Providing embedded dungeon.lua (%zu bytes)\n", file->size);
        fprintf(stderr, "[DLB] First 50 chars: %.50s\n", file->content);
        fflush(stderr);
        return file;
    }

    /* Provide epitaph file fallback */
    if (strcmp(filename, "epitaph") == 0) {
        fprintf(stderr, "[DLB] Providing fallback epitaph file\n");
        dlb* file = (dlb*)alloc(sizeof(dlb));
        if (!file) return NULL;

        static const char* epitaph_content =
            "# epitaph file\n"
            "Here lies an adventurer\n"
            "Rest in Peace\n"
            "Gone but not forgotten\n"
            "Killed by a newt\n"
            "Yet another victim\n";

        file->content = (char*)epitaph_content;
        file->size = strlen(epitaph_content);
        file->pos = 0;
        file->is_allocated = 0;
        return file;
    }

    /* Provide engrave file fallback */
    if (strcmp(filename, "engrave") == 0) {
        fprintf(stderr, "[DLB] Providing fallback engrave file\n");
        dlb* file = (dlb*)alloc(sizeof(dlb));
        if (!file) return NULL;

        static const char* engrave_content =
            "# engrave file\n"
            "Elbereth\n"
            "X marks the spot\n"
            "They say that reading is good\n"
            "Ad aerarium\n";

        file->content = (char*)engrave_content;
        file->size = strlen(engrave_content);
        file->pos = 0;
        file->is_allocated = 0;
        return file;
    }

    /* Provide nhcore.lua with proper content */
    if (strcmp(filename, "nhcore.lua") == 0) {
        fprintf(stderr, "[DLB] WARNING: Using hardcoded nhcore.lua fallback\n");
        fflush(stderr);

        dlb* file = (dlb*)alloc(sizeof(dlb));
        if (!file) return NULL;

        /* Essential nhcore.lua content */
        file->content =
            "-- NetHack nhcore.lua\n"
            "-- Core Lua functions for NetHack\n"
            "\n"
            "function getobj_filter(obj)\n"
            "   return true\n"
            "end\n"
            "\n"
            "function mon_hp_color(hpfrac)\n"
            "   if hpfrac >= 1.0 then\n"
            "      return \"green\"\n"
            "   elseif hpfrac > 0.66 then\n"
            "      return \"yellow\"\n"
            "   elseif hpfrac > 0.33 then\n"
            "      return \"orange\"\n"
            "   else\n"
            "      return \"red\"\n"
            "   end\n"
            "end\n";

        file->size = strlen(file->content);
        file->pos = 0;
        file->is_allocated = 0;  /* Static content */
        return file;
    }

    /* Provide quest.lua */
    if (strcmp(filename, "quest.lua") == 0) {
        fprintf(stderr, "[DLB] Providing quest.lua\n");
        fflush(stderr);

        dlb* file = (dlb*)alloc(sizeof(dlb));
        if (!file) return NULL;

        /* Minimal quest.lua */
        file->content = "-- NetHack quest.lua\n-- Quest definitions\n";
        file->size = strlen(file->content);
        file->pos = 0;
        file->is_allocated = 0;
        return file;
    }

    fprintf(stderr, "[DLB] File not found: %s\n", filename);
    fflush(stderr);
    return NULL;
}

/* Close a DLB file and free its memory */
NETHACK_EXPORT int dlb_fclose(dlb* file) {
    if (file) {
        /* Free allocated content if it was loaded from bundle */
        if (file->is_allocated && file->content) {
            zone_free((void*)file->content);
        }
        zone_free(file);
    }
    return 0;
}

/* Seek within a DLB file */
NETHACK_EXPORT int dlb_fseek(dlb* file, long offset, int whence) {
    if (!file) return -1;

    if (whence == SEEK_SET) {
        file->pos = offset;
    } else if (whence == SEEK_CUR) {
        file->pos += offset;
    } else if (whence == SEEK_END) {
        file->pos = file->size + offset;
    }

    if (file->pos > file->size) file->pos = file->size;
    if (file->pos < 0) file->pos = 0;

    return 0;
}

/* Get current position in DLB file */
NETHACK_EXPORT long dlb_ftell(dlb* file) {
    if (!file) return -1;
    return file->pos;
}

/* Read from a DLB file */
NETHACK_EXPORT int dlb_fread(char* buffer, int size, int count, dlb* file) {
    if (!file) return 0;

    size_t bytes = size * count;
    size_t available = file->size - file->pos;
    if (bytes > available) bytes = available;

    memcpy(buffer, file->content + file->pos, bytes);
    file->pos += bytes;

    return bytes / size;
}

/* Read a line from a DLB file */
NETHACK_EXPORT char* dlb_fgets(char* buffer, int size, dlb* file) {
    if (!file || file->pos >= file->size) return NULL;

    int i = 0;
    while (i < size - 1 && file->pos < file->size) {
        char c = file->content[file->pos++];
        buffer[i++] = c;
        if (c == '\n') break;
    }
    buffer[i] = '\0';

    return buffer;
}

/* ============================================================================
 * Swift Bridge Function Stubs
 * These are fallback implementations for when the dylib is built standalone.
 * When loaded into a Swift app, the real Swift implementations will override these.
 * ============================================================================ */

/* Documents path getter */
int ios_swift_get_documents_path(char* buffer, int bufsize) {
    const char *home = getenv("HOME");
    if (home && bufsize > 0) {
        snprintf(buffer, bufsize, "%s/Documents/NetHack", home);
        return 1;
    } else if (bufsize > 0) {
        strncpy(buffer, "/tmp/NetHack", bufsize - 1);
        buffer[bufsize - 1] = '\0';
        return 1;
    }
    return 0;
}

/* File loading stubs */
char* ios_swift_load_lua_file(const char* filename) {
    /* Return NULL - file not found */
    return NULL;
}

ios_raw_file_data* ios_swift_load_raw_lua_file(const char* filename) {
    /* Return NULL - file not found */
    return NULL;
}

char* ios_swift_load_data_file(const char* filename) {
    /* Return NULL - file not found */
    return NULL;
}

void ios_swift_free_raw_file(ios_raw_file_data* file_data) {
    /* Nothing to free in stub */
}

/* Notification stubs */
// ios_post_message_notification moved to ios_notifications.m (Objective-C implementation)
// This stub is no longer needed - real implementation uses NSNotificationCenter

/* NOTE: ios_restore_complete is defined in ios_save_integration.c - not here! */

/* Global variables */
char SAVEF[256] = "nethack.sav";  /* Default save filename */

/* init_nethack_core and test_nethack_functions are in NetHackCoreIntegration.c */
