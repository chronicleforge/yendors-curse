/*
 * RealNetHackBridge.c - Bridge between Swift and NetHack C
 *
 * This file ONLY provides bridging functions. NO game logic!
 * All game logic must come from the original NetHack source.
 */

// Enable zone allocator for snapshot support
#define USE_ZONE_ALLOCATOR 1

#include "nethack_export.h"  // Symbol visibility control
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <sys/time.h>  // For gettimeofday() performance measurement
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#include <ctype.h>
#include <fcntl.h>
#include <setjmp.h>  // For clean game exit via longjmp
// REMOVED: pthread.h - NetHack is NOT thread-safe!
#include <zlib.h>  // For manual decompression workaround
#include <dispatch/dispatch.h>  // For dispatch_async in game ready signal
#include "RealNetHackBridge.h"
#include "action_system.h"
#include "action_registry.h"
#include "../NetHack/include/hack.h"  // For instance_globals_saved_p and other NetHack types
#include "../NetHack/include/dlb.h"   // For NHFILE type
#include "../NetHack/include/func_tab.h"  // For struct ext_func_tab (command lookup)
#ifdef USE_ZONE_ALLOCATOR
#include "../zone_allocator/nethack_zone.h"
#endif

// Define PATHLEN if not already defined
#ifndef PATHLEN
#define PATHLEN 256  // Maximum path length for save files
#endif

// Use GLOBAL output buffer - single source of truth:
// - For DYLIB builds: defined in ios_dylib_stubs.c:16
// - For STATIC builds: defined in ios_stubs.c:202 (guarded with #ifndef BUILD_DYLIB)
// Accessed via extern declaration in nethack_bridge_common.h
#include "nethack_bridge_common.h"
// #include "ios_travel.h"  // DISABLED: Travel feature not yet implemented
#include "ios_game_state_buffer.h"  // For GameStateSnapshot type

static int game_initialized = 0;
NETHACK_EXPORT int game_started = 0;  // Made non-static for ios_winprocs.c
int character_creation_complete = 0;  // Track if character creation is done

// Thread control variables for snapshot loading
// REMOVED: Threading variables - VIOLATION of porting guidelines!

// Track whether we need to resume from snapshot (non-static for access from ios_save_integration.c)
NETHACK_EXPORT bool snapshot_loaded = false;

// iOS travel interrupt flag - checked by lookaround() in hack.c via patch
// Set by nethack_travel_to() when user taps new destination during active travel
volatile int ios_travel_interrupt_pending = 0;

// Forward declaration of our helper functions
const char* nethack_get_savef(void);

// External notification posting (implemented in ios_notifications.m)
extern void ios_post_message_notification(const char* message, const char* category, int attr);

// Lua debug log buffer
#define LUA_LOG_BUFFER_SIZE 32768
static char lua_log_buffer[LUA_LOG_BUFFER_SIZE];
static int lua_log_pos = 0;

// Message history buffer for Swift access
#define MESSAGE_HISTORY_SIZE 100
#define MESSAGE_MAX_LENGTH 256
typedef struct {
    char message[MESSAGE_MAX_LENGTH];
    char category[32];
    long turn;  // Turn number when message was added
    int attr;   // NetHack ATR_* attributes (ATR_BOLD, ATR_DIM, etc.)
} MessageEntry;

// Death info from ios_winprocs.c
extern DeathInfo death_info;
extern int player_has_died;

static MessageEntry message_history[MESSAGE_HISTORY_SIZE];
static int message_history_index = 0;
static int message_history_count = 0;
static char message_history_json[MESSAGE_HISTORY_SIZE * 300];  // JSON buffer

// Message queue for buffering messages before Swift is ready
#define MESSAGE_QUEUE_SIZE 50
typedef struct {
    char message[MESSAGE_MAX_LENGTH];
    char category[32];
    int attr;
} QueuedMessage;

static QueuedMessage message_queue[MESSAGE_QUEUE_SIZE];
static int message_queue_count = 0;
static int swift_ready_for_messages = 0;  // 0 = not ready, 1 = ready

// External NetHack functions we bridge to
extern const char* test_nethack_functions(void);
extern void init_nethack_core(void);
extern int get_nethack_seed(void);

// Version info from NetHack
extern char *version_string(char *buf, size_t bufsz);  // From version.c

// Real NetHack game functions from origin/NetHack
extern void newgame(void);  // From allmain.c
extern void test_init_step1(void);
extern void test_init_step2(void);
extern void test_init_step3(void);
extern void test_init_step4(void);
extern void vision_init(void);  // From vision.c
extern void display_gamewindows(void);  // From display.c

// iOS window procedures
extern void init_ios_windowprocs(void);
extern struct window_procs ios_procs;

// Initialize the bridge - following OFFICIAL NetHack porting guidelines
void nethack_real_init(void) {
    // Debug: Verify output_buffer is accessible
    fprintf(stderr, "[DEBUG] nethack_real_init: output_buffer at %p\n", (void*)output_buffer);
    fprintf(stderr, "[DEBUG] About to memset output_buffer...\n");
    fflush(stderr);

    // Always reinitialize to get new random seed each time
    memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);

    fprintf(stderr, "[DEBUG] memset complete, first byte: %d\n", output_buffer[0]);
    fflush(stderr);

    // Clear Lua logs at start
    nethack_clear_lua_logs();

#ifdef USE_ZONE_ALLOCATOR
    // Start with character creation zone
    fprintf(stderr, "[BRIDGE] Initializing with CHARACTER_CREATION zone\n");
    nethack_zone_switch(ZONE_TYPE_CHARACTER_CREATION);
    nethack_zone_print_stats();
#endif

    // Log initialization start
    nethack_append_log("[BRIDGE] Starting NetHack initialization (OFFICIAL sequence)...");
    fprintf(stderr, "[TEST] Direct fprintf works!\n");
    LUA_LOG("TEST: LUA_LOG macro works!");
    DLB_LOG("TEST: DLB_LOG macro works!");

    // Add timestamp to verify we're running new code
    time_t t = time(NULL);
    char timestamp[100];
    snprintf(timestamp, sizeof(timestamp), "NetHack Bridge Init at %ld\n", (long)t);
    nethack_append_output(timestamp);

    // === OFFICIAL NetHack Initialization Sequence (per porting guidelines) ===
    // Reference: sys/unix/unixmain.c lines 65, 103, 151, 175

    // Step 1: early_init() - Initialize globals (REQUIRED FIRST)
    extern void early_init(int, char**);
    static char *dummy_argv[] = { "nethack", NULL };
    static int dummy_argc = 1;
    early_init(dummy_argc, dummy_argv);
    nethack_append_output("[1/6] early_init() complete\n");

    // Step 2: iOS-specific paths (before choose_windows)
    extern void ios_init_savedir(void);
    ios_init_savedir();
    ios_init_file_prefixes();
    nethack_append_output("[2/6] iOS paths initialized\n");

    // Step 3: REMOVED DUPLICATE early_init() call
    // early_init() was already called at line 131 (Step 1)
    // Calling it twice resets command bindings and breaks travel!
    nethack_append_output("[3/8] Skipping duplicate early_init()\n");

    // Step 4: Initialize window system
    // CRITICAL: NetHack REQUIRES choose_windows to be called
    // We use tty as base then immediately override
    extern void choose_windows(const char *);
    extern struct window_procs ios_procs;

    choose_windows("tty");  // Initialize windowprocs structure

    // NOW override with our iOS implementation
    windowprocs = ios_procs;

    nethack_append_output("[4/8] SwiftUI window system configured\n");

    // Step 5: Initialize options
    // TRUE TO ORIGINAL: initoptions() will call initoptions_init() which calls reset_commands(TRUE)
    // This binds ALL commands including movement and special commands like retravel (0x1F)
    extern void initoptions(void);
    fprintf(stderr, "[BRIDGE] Calling initoptions() - this will call reset_commands(TRUE)...\n");
    initoptions();

    nethack_append_output("[5/8] initoptions() complete - commands bound\n");

    // Step 6: init_nhwindows() - Initialize window system (REQUIRED)
    // Note: init_nhwindows is a macro, call through windowprocs
    if (windowprocs.win_init_nhwindows) {
        (*windowprocs.win_init_nhwindows)(&dummy_argc, dummy_argv);
        nethack_append_output("[6/8] init_nhwindows() complete\n");
    }

    // Step 7: process_options() - Not available (static in unixmain.c)
    // For iOS, command line processing is not needed
    nethack_append_output("[7/8] Command line processing skipped (iOS)\n");

    // Step 8: Configure numpad mode for iOS touch interface
    // Numpad is better for touch because:
    // - Digits 1-9 are dedicated to movement (no conflicts with other commands)
    // - More keys available for other commands (h/j/k/l can do other things)
    // - NetHack's numpad is well-tested and reliable
    extern void reset_commands(boolean initial);

    fprintf(stderr, "[BRIDGE] Enabling numpad mode for iOS...\n");
    iflags.num_pad = TRUE;  // Use numpad (1-9 for movement)
    iflags.num_pad_mode = 0;  // Standard numpad layout

    fprintf(stderr, "[BRIDGE] Calling reset_commands(FALSE) to rebind with numpad...\n");
    reset_commands(FALSE);  // Rebind with numpad enabled (FALSE = not initial)
    fprintf(stderr, "[BRIDGE] ✓ Numpad movement bindings active (1-9 for movement)\n");
    fprintf(stderr, "[BRIDGE]   Layout: 7=NW 8=N 9=NE / 4=W 5=wait 6=E / 1=SW 2=S 3=SE\n");

    // CRITICAL FIX: reset_commands(FALSE) clears C('_') in backup loop!
    // Restore the retravel command binding that got cleared
    extern int dotravel_target(void);
    extern boolean bind_key(uchar key, const char *command);
    fprintf(stderr, "[BRIDGE] Restoring C('_') retravel binding (cleared by reset_commands)...\n");
    bind_key(0x1F, "retravel");  // 0x1F = C('_') = Ctrl+_
    fprintf(stderr, "[BRIDGE] ✓ Retravel command restored at key 0x1F\n");

    nethack_append_output("[8/8] Numpad mode configured + retravel restored\n");

    // REMOVED: Direct global modification (svh.hackpid) - VIOLATES porting guidelines!
    // NetHack will set this itself through proper channels

    // Initialize NetHack core (sets random seed)
    init_nethack_core();

    // Test that NetHack functions work
    const char* test_result = test_nethack_functions();
    nethack_append_output(test_result);

    game_initialized = 1;
}

// Start new game - calls REAL NetHack!
void nethack_real_newgame(void) {
    if (!game_initialized) {
        nethack_real_init();
    }

    if (game_started) {
        nethack_append_output("Game already started!\n");
        return;
    }

    // Call the REAL NetHack newgame function!
    nethack_append_output("Calling real NetHack newgame()...\n");

    // Try to call the real NetHack newgame now that we have window procs
    nethack_append_output("\n=== Starting Real NetHack Game ===\n");

    // Attempt to start the real game with detailed logging!
    nethack_append_output("Starting real NetHack game engine...\n");

    nethack_append_output("Calling newgame() now...\n");

    fprintf(stderr, "[DEBUG] Testing initialization steps...\n");
    fflush(stderr);

    // Check if auto-mode is enabled from environment/flags
    if (ios_is_auto_mode()) {
        fprintf(stderr, "[BRIDGE] Auto-mode detected, skipping character selection\n");
        ios_debug_autoplay_status();
        fflush(stderr);
    }

    // Test steps removed - they were in test_init.c which is now in nethack_tests/
    // The real initialization happens in debug_newgame.c

    // Force nhl_init to be linked (prevent dead code elimination)
    extern lua_State *nhl_init(nhl_sandbox_info *);
    void *force_link_nhl = (void*)&nhl_init;
    (void)force_link_nhl;  // Suppress unused warning

    // STEP 1: Set up minimal initialization before newgame()
    fprintf(stderr, "[BRIDGE] Setting up for real newgame()...\n");

    // Initialize windows procedures first
    fprintf(stderr, "[BRIDGE] Setting window procedures...\n");
    extern struct window_procs ios_procs;
    // REMOVED: Direct windowprocs assignment - choose_windows() handles this

    // REMOVED: Direct iflags.window_inited modification - init_nhwindows() handles this

    // ios_newgame() handles all the initialization that the standard
    // newgame() expects to be already done:
    // - dlb_init()
    // - vision_init()
    // - window creation
    // - status_initialize()
    // - init_symbols()
    // This avoids the issues with VIA_WINDOWPORT() and wincap2

    // Set default character if not set (to avoid player_selection dialog)
    if (flags.initrole < 0) {
        fprintf(stderr, "[BRIDGE] No role set, using Valkyrie\n");
        flags.initrole = 11;   // Valkyrie
        flags.initrace = 0;    // Human
        flags.initgend = 1;    // Female
        flags.initalign = 0;   // Lawful (Valkyrie must be lawful)
    }

    fprintf(stderr, "[BRIDGE] Character flags before newgame: role=%d, race=%d, gender=%d, align=%d\n",
            flags.initrole, flags.initrace, flags.initgend, flags.initalign);

    // CRITICAL: Set hackpid to 1 for iOS - must be consistent for save/load
    // This MUST be done before any save operations!
    extern struct instance_globals_saved_h svh;
    svh.hackpid = 1;  // Always use PID 1 on iOS for save/load consistency
    fprintf(stderr, "[BRIDGE] Set svh.hackpid to 1 (iOS standard)\n");

#ifdef INSURANCE
    // Create initial 1lock.0 BEFORE calling ios_newgame()
    // ios_newgame() will call save_currentstate() which needs this file to exist
    extern NHFILE* create_levelfile(int lev, char errbuf[]);
    extern void close_nhfile(NHFILE*);
    extern struct instance_globals_h gh;

    // Make sure gh.havestate is false initially
    gh.havestate = FALSE;
    fprintf(stderr, "[BRIDGE] Set gh.havestate = FALSE (initial state)\n");

    // Create initial 1lock.0 with just the PID
    char errbuf[256];
    NHFILE *nhfp = create_levelfile(0, errbuf);
    if (nhfp) {
        // Write the PID that savestateinlock() expects to read
        nhfp->mode = WRITING;
        extern void Sfo_int(NHFILE*, int*, const char*);
        Sfo_int(nhfp, &svh.hackpid, "hackpid");
        close_nhfile(nhfp);
        fprintf(stderr, "[BRIDGE] Created initial 1lock.0 with PID 1 (iOS standard)\n");

        // REMOVED: Direct flags.ins_chkpt modification - VIOLATION!
    } else {
        fprintf(stderr, "[BRIDGE] ERROR: Failed to create initial 1lock.0: %s\n", errbuf);
        // REMOVED: Direct flags modification
    }
#endif

    // Mark that we're in character creation
    character_creation_complete = 0;
    fprintf(stderr, "\n");
    fprintf(stderr, "[BRIDGE] ═══════════════════════════════════════════════════\n");
    fprintf(stderr, "[BRIDGE] Starting character creation phase...\n");
    fprintf(stderr, "[BRIDGE] ═══════════════════════════════════════════════════\n");
    fprintf(stderr, "\n");
    fflush(stderr);

    // Call our iOS-specific newgame that properly handles initialization
    extern void ios_newgame(void);
    fprintf(stderr, "[BRIDGE] >>> Calling ios_newgame()...\n");
    fprintf(stderr, "[BRIDGE] >>> This will init dungeons, Lua, artifacts, player\n");
    fflush(stderr);

    ios_newgame();

    fprintf(stderr, "\n");
    fprintf(stderr, "[BRIDGE] <<< ios_newgame() RETURNED SUCCESSFULLY!\n");
    fflush(stderr);

    // Character creation is now complete
    character_creation_complete = 1;
    fprintf(stderr, "[BRIDGE] ✓ Character creation complete!\n");
    fprintf(stderr, "\n");
    fflush(stderr);

#ifdef USE_ZONE_ALLOCATOR
    // Switch to game zone after character creation
    fprintf(stderr, "[BRIDGE] Switching to GAME zone after character creation\n");
    nethack_zone_switch(ZONE_TYPE_GAME);
#endif

    fprintf(stderr, "[BRIDGE] ios_newgame() returned successfully\n");
    fprintf(stderr, "[BRIDGE] After newgame: u.uhp=%d, u.uhpmax=%d\n", u.uhp, u.uhpmax);
    fprintf(stderr, "[BRIDGE] Role: %s, Race: %s\n",
            gu.urole.name.m ? gu.urole.name.m : "unknown",
            gu.urace.noun ? gu.urace.noun : "unknown");

    // Create our first save immediately after game start
    fprintf(stderr, "[BRIDGE] Creating initial save file...\n");
    /* Snapshots handled at Swift level */
    int save_result = 1;
    if (save_result == 0) {
        fprintf(stderr, "[BRIDGE] ✓ Initial save created successfully!\n");
    } else {
        fprintf(stderr, "[BRIDGE] WARNING: Initial save failed with result: %d\n", save_result);
    }

    // With zone-based snapshots, we don't need file-level operations
    // Just set minimal required values
    fprintf(stderr, "[BRIDGE] Using zone-based snapshots - skipping file level initialization\n");

    // Set basic lock name for compatibility (some code might check it)
    strcpy(gl.lock, "1lock");

    // Set save file name ALWAYS after character creation
    extern void set_savefile_name(boolean);
    fprintf(stderr, "[BRIDGE] Before set_savefile_name: SAVEF='%s', plname='%s'\n",
            gs.SAVEF, svp.plname);
    set_savefile_name(TRUE);
    fprintf(stderr, "[BRIDGE] After set_savefile_name: SAVEF='%s'\n", gs.SAVEF);

    // Zone-based snapshots don't need file system level checks
    fprintf(stderr, "[BRIDGE] Zone-based system ready\n");

    // Check if character is dead
    if (u.uhp <= 0) {
        fprintf(stderr, "[BRIDGE] ERROR: Character is DEAD after newgame! u.uhp=%d\n", u.uhp);
        fprintf(stderr, "[BRIDGE] This means newgame() didn't properly initialize HP\n");
    }
    fflush(stderr);

    // Set critical game state flags
    fprintf(stderr, "[BRIDGE] Setting critical game state flags...\n");
    fflush(stderr);

    // NOTE: We do NOT set in_moveloop here! moveloop() sets it internally via moveloop_preamble()
    // Setting it here causes the game thread to think moveloop is already running and exit immediately!
    // See: origin/NetHack/src/allmain.c:108 where moveloop_preamble() sets in_moveloop = 1
    // WORKAROUND: We'll set it manually AFTER moveloop() starts in the thread (see nethack_run_game_threaded)

    // CRITICAL: This is what allows saving! From moveloop_preamble in allmain.c:813
    program_state.something_worth_saving++; // useful data now exists

    // Set up basic movement
    // REMOVED: Direct u.umovement modification - VIOLATION!
    svc.context.move = 1;  // CRITICAL: Must be 1 for turns to increment!

    // Force status update
    disp.botlx = TRUE;

    fprintf(stderr, "[BRIDGE] Critical flags set - game ready for play!\n");
    fprintf(stderr, "[BRIDGE] program_state.in_moveloop = %d\n", program_state.in_moveloop);
    fprintf(stderr, "[BRIDGE] u.umovement = %d\n", u.umovement);
    fflush(stderr);

    // Skip docrt() here - it might crash with uninitialized display data
    // Let moveloop handle the initial display
    fprintf(stderr, "[BRIDGE] Skipping initial docrt() - moveloop will handle display\n");

    fprintf(stderr, "[BRIDGE] Map display complete\n");
    fflush(stderr);

    nethack_append_output("\n✅ NetHack game started successfully!\n");

    game_started = 1;
}

// Start the game loop on a background thread
// Process a single command/turn - called for each user input
int nethack_process_command(void) {
    if (!game_started) {
        fprintf(stderr, "[BRIDGE] Cannot process command - game not started\n");
        return 0;
    }

    // We need to simulate what the normal moveloop does:
    // The infinite for(;;) { moveloop_core(); } loop
    //
    // moveloop_core() has a complex flow:
    // 1. If context.move is 1, it processes the turn (monsters, etc)
    // 2. Sets context.move = 1 at the end
    // 3. Calls rhack() to process user input
    //
    // Since we're turn-based, we need to call moveloop_core() twice:
    // - First call: processes the previous command's results (if context.move = 1)
    // - If still alive and able to move, rhack() gets called to process new input

    extern void moveloop_core(void);
    extern struct instance_globals_saved_c svc;

    // Log current state
    fprintf(stderr, "[BRIDGE] process_command: context.move=%d, moves=%ld\n",
            svc.context.move, nethack_get_turn_count());

    // Call moveloop_core once - NetHack handles its own flow internally
    moveloop_core();

    fprintf(stderr, "[BRIDGE] After processing: context.move=%d, moves=%ld\n",
            svc.context.move, nethack_get_turn_count());

    // Print the map to console for debugging
    extern char map_buffer[40][121];  // From ios_winprocs.c
    extern int actual_map_width;
    extern int actual_map_height;
    fprintf(stderr, "\n========== MAP (Turn %ld) ==========\n", nethack_get_turn_count());
    int height = actual_map_height > 0 ? actual_map_height : 25;
    int width = actual_map_width > 0 ? actual_map_width : 80;

    // First, print the raw map
    for (int y = 0; y < height && y < 40; y++) {
        for (int x = 0; x < width && x < 120; x++) {
            char ch = map_buffer[y][x];
            if (ch == 0) ch = ' ';

            // FORCE player symbol at player position
            if (x == u.ux && y == u.uy) {
                ch = '@';
                fprintf(stderr, "@");  // Always show player
            } else {
                fprintf(stderr, "%c", ch);
            }
        }
        fprintf(stderr, "\n");
    }
    fprintf(stderr, "====================================\n");
    fprintf(stderr, "Player pos: (%d, %d), HP: %d/%d\n", u.ux, u.uy, u.uhp, u.uhpmax);

    // Check what's at the player position in the buffer
    char at_player = map_buffer[u.uy][u.ux];
    fprintf(stderr, "[DEBUG] Character at player pos in buffer: '%c' (0x%02x)\n",
            at_player ? at_player : ' ', (unsigned char)at_player);

    // Return 1 if game continues, 0 if game over
    return (u.uhp > 0) ? 1 : 0;
}

// Randomize character for auto-start
void nethack_real_randomize(void) {
    if (!game_initialized) {
        nethack_real_init();
    }

    memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);
    nethack_append_output("[AUTO] Randomizing character...\n");

    // Set random flags for role, race, gender, alignment
    // -1 means "pick random"
    flags.initrole = -1;    // Random role
    flags.initrace = -1;    // Random race
    flags.initgend = -1;    // Random gender
    flags.initalign = -1;   // Random alignment

    // Set a random player name
    const char *names[] = {
        "Hero", "Adventurer", "Explorer", "Wanderer",
        "Champion", "Seeker", "Warrior", "Pilgrim"
    };
    int idx = arc4random_uniform(8);
    strcpy(svp.plname, names[idx]);

    nethack_append_output("[AUTO] Character randomized!\n");
}

// Callback pointers for Swift (instead of weak symbols which don't work with dylib)
static void (*ios_swift_map_update_callback_ptr)(void) = NULL;
static void (*ios_swift_game_ready_callback_ptr)(void) = NULL;

// Functions to register callbacks from Swift
// CRITICAL: Must be explicitly exported with default visibility for Swift to find them
__attribute__((visibility("default")))
void ios_register_map_update_callback(void (*callback)(void)) {
    ios_swift_map_update_callback_ptr = callback;
    fprintf(stderr, "[BRIDGE] Map update callback registered at %p\n", (void*)callback);
}

__attribute__((visibility("default")))
void ios_register_game_ready_callback(void (*callback)(void)) {
    ios_swift_game_ready_callback_ptr = callback;
    fprintf(stderr, "[BRIDGE] Game ready callback registered at %p\n", (void*)callback);
}

// Called by ios_winprocs when the map changes
void ios_notify_map_changed(void) {
    if (ios_swift_map_update_callback_ptr) {
        ios_swift_map_update_callback_ptr();
    }
}

// Forward declaration for flush_message_queue
static void flush_message_queue(void);

// Called when game is fully initialized and ready for queries
NETHACK_EXPORT void ios_notify_game_ready(void) {
    fprintf(stderr, "[GAME_READY] ✅ Game fully initialized - notifying Swift\n");
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ios_swift_game_ready_callback_ptr) {
            ios_swift_game_ready_callback_ptr();
        } else {
            fprintf(stderr, "[GAME_READY] ❌ NO callback registered!\n");
        }
    });
}

// Called by Swift when it's ready to receive messages
NETHACK_EXPORT void ios_swift_ready_for_messages(void) {
    fprintf(stderr, "[MSG_QUEUE] Swift signaled ready for messages\n");

    swift_ready_for_messages = 1;

    // Flush any queued messages
    if (message_queue_count > 0) {
        flush_message_queue();
    }

    fprintf(stderr, "[MSG_QUEUE] Swift message handler ready, future messages will be sent immediately\n");
}

// Called when starting a NEW game (Swift is already ready)
NETHACK_EXPORT void ios_swift_ready_for_new_game(void) {
    fprintf(stderr, "[MSG_QUEUE] NEW game - Swift already ready (view is visible)\n");
    swift_ready_for_messages = 1;
}

// Called to reset message queue state (from ios_winprocs.c during reset)
void ios_reset_message_queue_state(void) {
    fprintf(stderr, "[MSG_QUEUE] Resetting message queue state\n");
    // Reset the ready flag to 0 - each game session should start fresh
    // NEW games will set this to 1 immediately
    // LOAD games will set this to 1 when view appears
    swift_ready_for_messages = 0;
    message_queue_count = 0;
    memset(message_queue, 0, sizeof(message_queue));
}

// Bridge function that Swift actually calls
void nethack_start_new_game(void) {
    fprintf(stderr, "\n");
    fprintf(stderr, "╔════════════════════════════════════════════════════════════╗\n");
    fprintf(stderr, "║                                                            ║\n");
    fprintf(stderr, "║     nethack_start_new_game() CALLED FROM SWIFT             ║\n");
    fprintf(stderr, "║                                                            ║\n");
    fprintf(stderr, "╚════════════════════════════════════════════════════════════╝\n");
    fprintf(stderr, "\n");
    fflush(stderr);

    memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);
    nethack_append_output("Starting new NetHack game...\n");

    // Set runmode to "walk" (RUN_STEP = 2) for better travel behavior
    // From flag.h: RUN_TPORT=0, RUN_LEAP=1, RUN_STEP=2, RUN_CRAWL=3
    flags.runmode = 2;  // RUN_STEP - show every step
    flags.travelcmd = TRUE;  // Enable travel command for mouse/touch
    flags.time = TRUE;  // Show time updates
    fprintf(stderr, "[BRIDGE] Setting runmode to walk (RUN_STEP=2) with visual updates\n");
    fflush(stderr);

    fprintf(stderr, "\n");
    fprintf(stderr, "[BRIDGE] ╔════════════════════════════════════════╗\n");
    fprintf(stderr, "[BRIDGE] ║   CALLING nethack_real_newgame()      ║\n");
    fprintf(stderr, "[BRIDGE] ╚════════════════════════════════════════╝\n");
    fprintf(stderr, "[BRIDGE] >>> BEFORE nethack_real_newgame() call...\n");
    fflush(stderr);

    nethack_real_newgame();

    fprintf(stderr, "\n");
    fprintf(stderr, "[BRIDGE] <<< AFTER nethack_real_newgame() returned!\n");
    fprintf(stderr, "[BRIDGE] ✅ SUCCESS! nethack_real_newgame() did NOT crash!\n");
    fprintf(stderr, "\n");
    fflush(stderr);

    // Set options AGAIN after newgame (in case they got reset)
    flags.runmode = 2;  // RUN_STEP = walk mode
    flags.travelcmd = TRUE;  // Enable travel
    fprintf(stderr, "[BRIDGE] Re-setting runmode to walk after newgame\n");
    fflush(stderr);

    // Apply wizard mode if it was requested before game start
    extern void ios_apply_wizard_mode(void);
    ios_apply_wizard_mode();

    // After newgame, NetHack is ready for the main game loop
    fprintf(stderr, "[BRIDGE] Game initialized, ready for commands\n");

    // Enable save capability by setting the necessary flags
    // newgame() already set something_worth_saving++
    // NOTE: We do NOT set in_moveloop = 1 here!
    // moveloop() will set it internally when the game thread actually starts the loop.
    // Setting it prematurely causes the thread guard to think moveloop is already running!

    // Mark game as started so commands can be processed
    game_started = 1;

    fprintf(stderr, "[INVENTORY] game_started set to 1 after new game start\n");
    fprintf(stderr, "[BRIDGE] Game at turn 1 - saves enabled (something_worth_saving=%d, moves=%ld)\n",
            program_state.something_worth_saving, svm.moves);
    fprintf(stderr, "[BRIDGE] Game ready - save capability initialized\n");
}

// Backup storage for character creation (survives early_init)
static char char_creation_backup_name[PL_NSIZ] = "";
static int char_creation_backup_role = -1;
static int char_creation_backup_race = -1;
static int char_creation_backup_gender = -1;
static int char_creation_backup_align = -1;

// Character creation functions
void nethack_finalize_character(void) {
    fprintf(stderr, "\n========================================\n");
    fprintf(stderr, "[FINALIZE] *** FUNCTION CALLED ***\n");
    fprintf(stderr, "[FINALIZE] svp.plname = '%s'\n", svp.plname);
    fprintf(stderr, "[FINALIZE] flags: role=%d race=%d gender=%d align=%d\n",
            flags.initrole, flags.initrace, flags.initgend, flags.initalign);
    fprintf(stderr, "========================================\n\n");

    // CRITICAL: Validate character selection BEFORE finalizing!
    int validation_result = nethack_validate_character_selection();
    if (validation_result != 0) {
        fprintf(stderr, "[FINALIZE] ❌ ABORT: Character validation failed with code %d\n", validation_result);
        fprintf(stderr, "[FINALIZE] Character will NOT be finalized!\n");
        fprintf(stderr, "========================================\n\n");
        // Don't finalize - validation failed
        return;
    }

    // CRITICAL: Backup ALL character creation data! ios_newgame() calls early_init() which resets everything
    strncpy(char_creation_backup_name, svp.plname, PL_NSIZ - 1);
    char_creation_backup_name[PL_NSIZ - 1] = '\0';
    char_creation_backup_role = flags.initrole;
    char_creation_backup_race = flags.initrace;
    char_creation_backup_gender = flags.initgend;
    char_creation_backup_align = flags.initalign;

    fprintf(stderr, "[FINALIZE] ✅ Backed up character data:\n");
    fprintf(stderr, "[FINALIZE]   Name: '%s'\n", char_creation_backup_name);
    fprintf(stderr, "[FINALIZE]   Role: %d, Race: %d, Gender: %d, Align: %d\n",
            char_creation_backup_role, char_creation_backup_race,
            char_creation_backup_gender, char_creation_backup_align);

    // Set up character for NetHack
    nethack_append_output("Character finalized: ");
    nethack_append_output(svp.plname);
    nethack_append_output("\n");

    // NOTE: set_savefile_name() moved to ios_newgame() AFTER u_init()
    // This ensures character state is fully initialized before setting save filename

    // Just ensure save directory exists
    extern void ios_ensure_save_dir_exists(void);
    ios_ensure_save_dir_exists();

    fprintf(stderr, "\n========================================\n");
    fprintf(stderr, "[FINALIZE] ✅ COMPLETE - plname='%s'\n", svp.plname);
    fprintf(stderr, "[FINALIZE] NOTE: gs.SAVEF will be set in ios_newgame() after u_init()\n");
    fprintf(stderr, "========================================\n\n");
    fflush(stderr);
}

// Get backed up character data (for ios_newgame to restore after early_init)
const char* nethack_get_backed_up_name(void) {
    return char_creation_backup_name[0] ? char_creation_backup_name : NULL;
}

int nethack_get_backed_up_role(void) {
    return char_creation_backup_role;
}

int nethack_get_backed_up_race(void) {
    return char_creation_backup_race;
}

int nethack_get_backed_up_gender(void) {
    return char_creation_backup_gender;
}

int nethack_get_backed_up_align(void) {
    return char_creation_backup_align;
}

// Get output for Swift
const char* nethack_real_get_output(void) {
    return output_buffer;
}

// Clear output buffer
void nethack_real_clear_output(void) {
    memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);
}

// Get current turn/move counter
long nethack_get_turn_count(void) {
    // NetHack stores turn count in svm.moves (struct instance_globals_saved_m)
    // This is declared in decl.h and available via hack.h
    extern struct instance_globals_saved_m svm;
    return svm.moves;
}

// Save/Load functions
int nethack_save_game(const char* filepath) {
    fprintf(stderr, "\n[BRIDGE] ========== SAVE GAME ATTEMPT ==========\n");
    fprintf(stderr, "[BRIDGE] Save requested to: %s\n", filepath ? filepath : "(null)");
    fprintf(stderr, "[BRIDGE] game_started = %d\n", game_started);
    fprintf(stderr, "[BRIDGE] character_creation_complete = %d\n", character_creation_complete);
    fprintf(stderr, "[BRIDGE] program_state.something_worth_saving = %d\n",
            program_state.something_worth_saving);
    fprintf(stderr, "[BRIDGE] program_state.in_moveloop = %d\n", program_state.in_moveloop);

    if (!game_started) {
        fprintf(stderr, "[BRIDGE] Cannot save - game not started\n");
        return 0;
    }

    // Check if we're in the main game loop (required for saving)
    // program_state is already declared in decl.h as struct sinfo
    if (!program_state.in_moveloop) {
        fprintf(stderr, "[BRIDGE] Cannot save - not in game loop yet\n");
        return 0;
    }

    // Check if multi is 0 (not in the middle of an action)
    // gm.multi is already available from hack.h
    if (gm.multi != 0) {
        fprintf(stderr, "[BRIDGE] Cannot save - action in progress (multi=%ld)\n", gm.multi);
        return 0;
    }

    // NetHack expects to manage its own save files through set_savefile_name()
    // We should only set the player name and let NetHack build the path
    if (filepath) {
        fprintf(stderr, "[BRIDGE] iOS requests save to: %s\n", filepath);

        // Extract player name from filename (assuming format: slot#_playername.nhsav)
        const char* filename = strrchr(filepath, '/');
        if (filename) filename++;
        else filename = filepath;

        // Parse player name from filename
        char playername[PL_NSIZ];
        const char* underscore = strchr(filename, '_');
        if (underscore) {
            // Skip the slot prefix, get the player name
            strncpy(playername, underscore + 1, PL_NSIZ - 1);
            playername[PL_NSIZ - 1] = '\0';
            // Remove the .nhsav extension if present
            char* dot = strrchr(playername, '.');
            if (dot) *dot = '\0';


            // Set the player name for NetHack to use
            extern struct instance_globals_saved_p svp;
            // REMOVED: Direct svp.plname modification - use proper name setting
            fprintf(stderr, "[BRIDGE] Player name should be set through proper channels\n");
        } else {
            // Use the whole filename as player name (minus extension)
            strncpy(playername, filename, PL_NSIZ - 1);
            playername[PL_NSIZ - 1] = '\0';
            char* dot = strrchr(playername, '.');
            if (dot) *dot = '\0';

            extern struct instance_globals_saved_p svp;
            // REMOVED: Direct svp.plname modification - use proper name setting
            fprintf(stderr, "[BRIDGE] Player name should be set through proper channels\n");
        }

        // Now let NetHack build the proper save filename
        // This sets gs.SAVEF which is what dosave0() checks
        extern void set_savefile_name(boolean);
        set_savefile_name(TRUE);

        // Just ensure save directory exists
        extern void ios_ensure_save_dir_exists(void);
        ios_ensure_save_dir_exists();

        // Ensure the save directory exists
        extern void ios_ensure_save_dir_exists(void);
        ios_ensure_save_dir_exists();

        const char* savef = nethack_get_savef();
        fprintf(stderr, "[BRIDGE] Save filename for save: %s\n", savef ? savef : "(null)");

        // Note: gs.SAVEF is what dosave0() uses internally
        // We can't directly access it, but set_savefile_name() sets it
        fprintf(stderr, "[BRIDGE] NetHack will determine save path internally\n");
    }

    // Call NetHack's actual save function
    // Use dosave0() instead of dosave() to avoid nh_terminate()
    extern int dosave0(void);
    extern void pline(const char*, ...);
    extern void docrt(void);
    // clear_nhwindow and display_nhwindow are macros from winprocs.h

    // Don't use pline during save - it can cause display issues
    fprintf(stderr, "[BRIDGE] Starting save process...\n");

    // Check that something_worth_saving is set (should be from newgame)
    fprintf(stderr, "[BRIDGE] program_state.something_worth_saving = %d\n",
            program_state.something_worth_saving);

    if (!program_state.something_worth_saving) {
        fprintf(stderr, "[BRIDGE] WARNING: something_worth_saving not set! Setting it now...\n");
        program_state.something_worth_saving = 1;
    }

    // Try to create a test file to verify we can write
    if (filepath) {
        FILE* test = fopen(filepath, "w");
        if (test) {
            fprintf(test, "test");
            fclose(test);
            fprintf(stderr, "[BRIDGE] Successfully created test file at %s\n", filepath);
            unlink(filepath);  // Remove test file
        } else {
            fprintf(stderr, "[BRIDGE] ERROR: Cannot create file at %s - %s\n",
                    filepath, strerror(errno));
        }
    }

    // Debug: Check gs.SAVEF and full path before saving
    fprintf(stderr, "[BRIDGE] Before dosave0():\n");
    fprintf(stderr, "[BRIDGE]   gs.SAVEF = '%s'\n", gs.SAVEF);
    extern const char* fqname(const char* basename, int whichprefix, int buffnum);
    const char* pre_save_path = fqname(gs.SAVEF, SAVEPREFIX, 0);
    fprintf(stderr, "[BRIDGE]   Full save path = %s\n", pre_save_path ? pre_save_path : "(null)");

    /* Just ensure directories exist and call NetHack's save */
    extern void ios_ensure_save_dir_exists(void);
    ios_ensure_save_dir_exists();

    // Use non-destructive save for iOS
    fprintf(stderr, "[BRIDGE] Snapshot save - handled at Swift level\n");
    int result = 1; /* Always success - actual snapshot is handled by Swift */
    fprintf(stderr, "[BRIDGE] Snapshot save returns: %d (1=success)\n", result);

    // Check if file was actually created
    fprintf(stderr, "[BRIDGE] ===== POST-SAVE FILE CHECK =====\n");
    if (pre_save_path) {
        if (access(pre_save_path, F_OK) == 0) {
            fprintf(stderr, "[BRIDGE] ✅ Save file EXISTS at %s\n", pre_save_path);
            // Get file size
            struct stat st;
            if (stat(pre_save_path, &st) == 0) {
                fprintf(stderr, "[BRIDGE]   File size: %lld bytes\n", (long long)st.st_size);
                fprintf(stderr, "[BRIDGE]   File mode: %o\n", st.st_mode & 0777);
                fprintf(stderr, "[BRIDGE]   Modified: %s", ctime(&st.st_mtime));
            }
        } else {
            fprintf(stderr, "[BRIDGE] ❌ Save file NOT FOUND at %s\n", pre_save_path);
            fprintf(stderr, "[BRIDGE]   errno = %d (%s)\n", errno, strerror(errno));
        }
    } else {
        fprintf(stderr, "[BRIDGE] ⚠️  pre_save_path was NULL\n");
    }

    if (result) {
        fprintf(stderr, "[BRIDGE] Save successful!\n");

        // CRITICAL: Also save memory state!
        fprintf(stderr, "[BRIDGE] Saving memory state...\n");
        char memory_file[1024];
        const char *save_dir = gs.SAVEF;
        if (save_dir && strrchr(save_dir, '/')) {
            char *base = strrchr(save_dir, '/');
            size_t dir_len = base - save_dir;
            strncpy(memory_file, save_dir, dir_len);
            memory_file[dir_len] = '\0';
            strcat(memory_file, "/memory.dat");
        } else {
            strcpy(memory_file, "memory.dat");
        }

        // Import function from memory allocator
        extern int nh_save_state(const char* filename);
        extern void nh_memory_stats(size_t* used, size_t* allocations);

        if (nh_save_state(memory_file) == 0) {
            size_t used, allocations;
            nh_memory_stats(&used, &allocations);
            fprintf(stderr, "[BRIDGE] Memory state saved: %zu bytes, %zu allocations\n",
                    used, allocations);
            fprintf(stderr, "[BRIDGE] Memory file: %s\n", memory_file);
        } else {
            fprintf(stderr, "[BRIDGE] WARNING: Failed to save memory state!\n");
        }

        // Don't set u.uhp = -1 or terminate like dosave() does
        // We want to continue playing
        // Message will be shown by Swift UI

        // Let's verify the file was actually created
        if (filepath) {
            FILE* test = fopen(filepath, "r");
            if (test) {
                fprintf(stderr, "[BRIDGE] Verified: Save file exists at %s\n", filepath);
                fclose(test);

                // Create metadata file for the UI to display saved game info
                char meta_path[512];
                snprintf(meta_path, sizeof(meta_path), "%s.meta.json", filepath);

                // Get role/race/etc. names for metadata
                const char* role_name = gu.urole.name.m ? gu.urole.name.m : "Unknown";
                const char* race_name = gu.urace.noun ? gu.urace.noun : "Unknown";
                const char* gender = flags.female ? "female" : "male";
                // Get actual alignment from u.ualign
                const char* alignment = (u.ualign.type == A_LAWFUL) ? "lawful" :
                                      (u.ualign.type == A_NEUTRAL) ? "neutral" :
                                      (u.ualign.type == A_CHAOTIC) ? "chaotic" : "unknown";

                // Get location name
                const char* location = "Dungeons of Doom";  // Default
                if (Is_knox(&u.uz)) location = "Fort Ludios";
                else if (Is_valley(&u.uz)) location = "Valley of the Dead";
                else if (Is_astralevel(&u.uz)) location = "Astral Plane";

                // Calculate actual play time in seconds
                extern struct u_realtime urealtime;
                extern time_t getnow(void);
                long play_seconds = urealtime.realtime;
                if (urealtime.start_timing) {
                    // Add current session time if game is still running
                    play_seconds += (long)difftime(getnow(), urealtime.start_timing);
                }
                time_t now = time(NULL);

                // FIX: Use guard clause to prevent FILE* leak
                FILE* meta = fopen(meta_path, "w");
                if (!meta) {
                    fprintf(stderr, "[BRIDGE] ERROR: Cannot create metadata file: %s\n", meta_path);
                    // Continue execution - metadata is optional
                } else {
                    // Write metadata JSON - file is guaranteed open
                    fprintf(meta, "{\n");
                    fprintf(meta, "  \"name\": \"%s\",\n", svp.plname);
                    fprintf(meta, "  \"level\": %d,\n", u.ulevel);
                    fprintf(meta, "  \"className\": \"%s\",\n", role_name);
                    fprintf(meta, "  \"raceName\": \"%s\",\n", race_name);
                    fprintf(meta, "  \"gender\": \"%s\",\n", gender);
                    fprintf(meta, "  \"alignment\": \"%s\",\n", alignment);
                    fprintf(meta, "  \"location\": \"%s\",\n", location);
                    fprintf(meta, "  \"dungeonLevel\": %d,\n", u.uz.dlevel);

                    // Get gold safely - check for NULL inventory
                    long save_gold = 0;
                    if (gi.invent) {
                        extern long money_cnt(struct obj *);
                        save_gold = money_cnt(gi.invent);
                    }
                    fprintf(meta, "  \"gold\": %ld,\n", save_gold);
                    fprintf(meta, "  \"playTime\": %ld,\n", play_seconds);
                    fprintf(meta, "  \"lastPlayed\": %ld,\n", (long)now);
                    fprintf(meta, "  \"saveVersion\": 1\n");
                    fprintf(meta, "}\n");

                    // CRITICAL: Always close file after writing
                    fclose(meta);
                    fprintf(stderr, "[BRIDGE] ✓ Created metadata file: %s\n", meta_path);
                }
            } else {
                fprintf(stderr, "[BRIDGE] WARNING: Save file not found at %s\n", filepath);
            }
        }
    } else {
        fprintf(stderr, "[BRIDGE] Save failed! dosave0() returned 0\n");
        pline("Save failed!");

        // Note: dosave0() failed - it checks gs.SAVEF not our local SAVEF
        // The issue is that gs.SAVEF may not be set properly
        fprintf(stderr, "[BRIDGE] dosave0() failed - gs.SAVEF may be empty\n");
    }

    // Refresh display after save
    docrt();

    return result;
}

const char* nethack_get_lib_version(void) {

    static char version_buf[128];
    // Get version string from NetHack's version.c
    version_string(version_buf, sizeof(version_buf));
    return version_buf;
}

// API Version and compatibility
#define NETHACK_API_VERSION 1

int nethack_get_api_version(void) {
    return NETHACK_API_VERSION;
}

int nethack_check_compatibility(int swift_api_version) {
    return swift_api_version == NETHACK_API_VERSION;
}

const char* nethack_get_build_info(void) {
    return "NetHack 3.7.0 iOS Port";
}

// Role/Race/Gender/Alignment queries - simplified for now
int nethack_get_available_roles(void) {
    // Return bitmap with all 13 roles available (bits 0-12 set)
    return 0x1FFF;  // Binary: 1111111111111 = all 13 roles available
}

int nethack_get_available_races_for_role(int role_index) {
    // Guard clause: validate role_index
    if (role_index < 0 || role_index >= NUM_ROLES) {
        return 0;  // Invalid role
    }

    // Use NetHack's validrace() to build bitmask of valid races
    int valid_races = 0;
    for (int i = 0; i < NUM_RACES; i++) {
        if (validrace(role_index, i)) {
            valid_races |= (1 << i);
        }
    }
    return valid_races;
}

int nethack_get_available_genders_for_role(int role_index) {
    // Guard clause: validate role_index
    if (role_index < 0 || role_index >= NUM_ROLES) {
        return 0;  // Invalid role
    }

    // CRITICAL: validgend() requires a VALID race index (0-4), not ROLE_RANDOM!
    // Since we don't have a race selected yet, we must check ALL valid races
    // and return the UNION of all valid genders across all valid races for this role.
    int valid_genders = 0;

    // Loop through all possible races
    for (int race_idx = 0; race_idx < NUM_RACES; race_idx++) {
        // Only check races that are valid for this role
        if (validrace(role_index, race_idx)) {
            // For each valid race, check which genders are valid
            for (int gend_idx = 0; gend_idx < 3; gend_idx++) {  // 3 genders: Male, Female, Neuter
                if (validgend(role_index, race_idx, gend_idx)) {
                    valid_genders |= (1 << gend_idx);
                }
            }
        }
    }
    return valid_genders;
}

int nethack_get_available_alignments_for_role(int role_index) {
    // Guard clause: validate role_index
    if (role_index < 0 || role_index >= NUM_ROLES) {
        return 0;  // Invalid role
    }

    // CRITICAL: validalign() requires a VALID race index (0-4), not ROLE_RANDOM!
    // Since we don't have a race selected yet, we must check ALL valid races
    // and return the UNION of all valid alignments across all valid races for this role.
    int valid_aligns = 0;

    // Loop through all possible races
    for (int race_idx = 0; race_idx < NUM_RACES; race_idx++) {
        // Only check races that are valid for this role
        if (validrace(role_index, race_idx)) {
            // For each valid race, check which alignments are valid
            for (int align_idx = 0; align_idx < 3; align_idx++) {  // 3 alignments: Lawful, Neutral, Chaotic
                if (validalign(role_index, race_idx, align_idx)) {
                    valid_aligns |= (1 << align_idx);
                }
            }
        }
    }
    return valid_aligns;
}

const char* nethack_get_role_name(int role_index) {
    const char* roles[] = {
        "Archeologist", "Barbarian", "Caveman", "Healer", "Knight",
        "Monk", "Priest", "Rogue", "Ranger", "Samurai",
        "Tourist", "Valkyrie", "Wizard"
    };
    if (role_index >= 0 && role_index < 13) {
        return roles[role_index];
    }
    return "Unknown";
}

const char* nethack_get_race_name(int race_index) {
    const char* races[] = {"human", "elf", "dwarf", "gnome", "orc"};
    if (race_index >= 0 && race_index < 5) {
        return races[race_index];
    }
    return "Unknown";
}

const char* nethack_get_gender_name(int gender_index) {
    if (gender_index == 0) return "male";
    if (gender_index == 1) return "female";
    return "Unknown";
}

const char* nethack_get_alignment_name(int align_index) {
    if (align_index == 0) return "lawful";
    if (align_index == 1) return "neutral";
    if (align_index == 2) return "chaotic";
    return "Unknown";
}

// Lua logging functions
void nethack_append_log(const char* format, ...) {
    va_list args;

    // FIRST: Output to stderr immediately for debugging
    va_start(args, format);
    vfprintf(stderr, format, args);
    if (format[strlen(format) - 1] != '\n') {
        fprintf(stderr, "\n");
    }
    fflush(stderr);
    va_end(args);

    // THEN: Also save to buffer
    va_start(args, format);
    int space_left = LUA_LOG_BUFFER_SIZE - lua_log_pos - 1;
    if (space_left > 0) {
        int written = vsnprintf(lua_log_buffer + lua_log_pos, space_left, format, args);
        if (written > 0 && written < space_left) {
            lua_log_pos += written;

            // Add newline if not present
            if (lua_log_pos > 0 && lua_log_buffer[lua_log_pos - 1] != '\n') {
                if (lua_log_pos < LUA_LOG_BUFFER_SIZE - 1) {
                    lua_log_buffer[lua_log_pos++] = '\n';
                }
            }
        }
    }
    va_end(args);
}

const char* nethack_get_lua_logs(void) {
    lua_log_buffer[lua_log_pos] = '\0';  // Ensure null-terminated
    return lua_log_buffer;
}

void nethack_clear_lua_logs(void) {
    lua_log_pos = 0;
    lua_log_buffer[0] = '\0';
}

// =============== MESSAGE HISTORY FUNCTIONS ===============

// Add a message to the history buffer (legacy - without attributes)
void nethack_add_message(const char* message, const char* category) {
    nethack_add_message_with_attrs(message, category, 0);  // ATR_NONE
}

// Flush queued messages to Swift (called when Swift becomes ready)
static void flush_message_queue(void) {
    fprintf(stderr, "[MSG_QUEUE] Flushing %d queued messages to Swift\n", message_queue_count);

    for (int i = 0; i < message_queue_count; i++) {
        ios_post_message_notification(
            message_queue[i].message,
            message_queue[i].category,
            message_queue[i].attr
        );
    }

    message_queue_count = 0;  // Clear the queue
    fprintf(stderr, "[MSG_QUEUE] Queue flushed successfully\n");
}

// Add a message with ATR_* attributes to the history buffer
void nethack_add_message_with_attrs(const char* message, const char* category, int attr) {
    if (!message) return;

    // Get actual turn count from NetHack (svm.moves is the correct variable)
    long current_moves = svm.moves;

    // Copy message and category into the circular buffer
    strncpy(message_history[message_history_index].message, message, MESSAGE_MAX_LENGTH - 1);
    message_history[message_history_index].message[MESSAGE_MAX_LENGTH - 1] = '\0';

    if (category) {
        strncpy(message_history[message_history_index].category, category, 31);
        message_history[message_history_index].category[31] = '\0';
    } else {
        strcpy(message_history[message_history_index].category, "MSG");
    }

    message_history[message_history_index].turn = current_moves;
    message_history[message_history_index].attr = attr;  // Store NetHack attributes

    // NEW: Check if Swift is ready to receive messages
    if (!swift_ready_for_messages) {
        // Swift not ready - queue the message for later
        if (message_queue_count < MESSAGE_QUEUE_SIZE) {
            strncpy(message_queue[message_queue_count].message,
                   message_history[message_history_index].message, MESSAGE_MAX_LENGTH - 1);
            message_queue[message_queue_count].message[MESSAGE_MAX_LENGTH - 1] = '\0';

            strncpy(message_queue[message_queue_count].category,
                   message_history[message_history_index].category, 31);
            message_queue[message_queue_count].category[31] = '\0';

            message_queue[message_queue_count].attr = attr;
            message_queue_count++;

            fprintf(stderr, "[MSG_QUEUE] Message queued (Swift not ready): '%s' (queue size: %d)\n",
                    message, message_queue_count);
        } else {
            fprintf(stderr, "[MSG_QUEUE] WARNING: Queue full, dropping message: '%s'\n", message);
        }
    } else {
        // Swift is ready - send immediately
        ios_post_message_notification(
            message_history[message_history_index].message,  // Use truncated buffer (safe)
            message_history[message_history_index].category, // Use category buffer (safe)
            attr
        );
    }

    // Update circular buffer index AFTER notification
    message_history_index = (message_history_index + 1) % MESSAGE_HISTORY_SIZE;
    if (message_history_count < MESSAGE_HISTORY_SIZE) {
        message_history_count++;
    }
}

// Get message history as JSON array
const char* nethack_get_message_history(void) {
    message_history_json[0] = '\0';
    strcat(message_history_json, "[");

    int start_idx = 0;
    if (message_history_count == MESSAGE_HISTORY_SIZE) {
        // Buffer is full, start from oldest message
        start_idx = message_history_index;
    }

    int first = 1;
    for (int i = 0; i < message_history_count; i++) {
        int idx = (start_idx + i) % MESSAGE_HISTORY_SIZE;

        if (!first) {
            strcat(message_history_json, ",");
        }
        first = 0;

        // Escape message text for JSON (replace " with \")
        char escaped_msg[MESSAGE_MAX_LENGTH * 2];
        const char *src = message_history[idx].message;
        char *dst = escaped_msg;
        while (*src && (dst - escaped_msg) < (MESSAGE_MAX_LENGTH * 2 - 2)) {
            if (*src == '"' || *src == '\\') {
                *dst++ = '\\';
            }
            *dst++ = *src++;
        }
        *dst = '\0';

        char entry[500];
        snprintf(entry, sizeof(entry),
                "{\"message\":\"%s\",\"category\":\"%s\",\"turn\":%ld,\"attr\":%d}",
                escaped_msg,
                message_history[idx].category,
                message_history[idx].turn,
                message_history[idx].attr);
        strcat(message_history_json, entry);
    }

    strcat(message_history_json, "]");
    return message_history_json;
}

// Get count of messages in history
int nethack_get_message_count(void) {
    return message_history_count;
}

// Clear message history
void nethack_clear_message_history(void) {
    message_history_index = 0;
    message_history_count = 0;
    memset(message_history, 0, sizeof(message_history));
}

// =============== MAP DATA FUNCTIONS ===============
// Export map data for Swift UI
extern char map_buffer[40][121];  // From ios_winprocs.c - bigger now!
extern boolean map_dirty;
extern int actual_map_width;
extern int actual_map_height;

// Enhanced map cell structure
typedef struct {
    int glyph;
    char ch;
    unsigned char color;
    unsigned char bg;
} MapCell;

extern MapCell map_cells[40][120];

NETHACK_EXPORT const char* nethack_get_map_data(void) {
    static char map_output[120 * 40 + 100];  // Room for larger map
    memset(map_output, 0, sizeof(map_output));

    // Use actual map dimensions
    int height = actual_map_height > 0 ? actual_map_height : 25;
    int width = actual_map_width > 0 ? actual_map_width : 80;

    // CRITICAL: Read from captured_map (what print_glyph wrote), NOT map_buffer
    // captured_map is populated by ios_capture_map() after print_glyph draws
    extern char captured_map[60][181];

    // CRITICAL FIX: captured_map has message area at rows 0-1, map starts at row 2
    // We need to read ALL buffer rows including the message offset!
    #define MAP_Y_OFFSET 2

    // Read the actual map area - ALL rows from buffer
    for (int y = 0; y < height && y < 40; y++) {
        if (y > 0) strcat(map_output, "\n");
        for (int x = 0; x < width && x < 120; x++) {
            // Read from buffer including message area (don't skip offset!)
            char ch = captured_map[y][x];
            if (ch == 0) ch = ' ';  // Replace nulls with spaces
            strncat(map_output, &ch, 1);
        }
    }

    return map_output;
}

// Get enhanced map data as JSON-like format
NETHACK_EXPORT const char* nethack_get_map_data_enhanced(void) {
    static char map_output[120 * 40 * 20];  // Much larger for JSON
    memset(map_output, 0, sizeof(map_output));

    int height = actual_map_height > 0 ? actual_map_height : 25;
    int width = actual_map_width > 0 ? actual_map_width : 80;

    sprintf(map_output, "{\"width\":%d,\"height\":%d,\"tiles\":[", width, height);

    for (int y = 0; y < height && y < 40; y++) {
        for (int x = 0; x < width && x < 120; x++) {
            if (y > 0 || x > 0) strcat(map_output, ",");

            char tile_json[100];
            sprintf(tile_json, "{\"x\":%d,\"y\":%d,\"ch\":'%c',\"glyph\":%d,\"color\":%d}",
                    x, y,
                    map_cells[y][x].ch ? map_cells[y][x].ch : ' ',
                    map_cells[y][x].glyph,
                    map_cells[y][x].color);
            strcat(map_output, tile_json);
        }
    }

    strcat(map_output, "]}");
    return map_output;
}

int nethack_is_map_dirty(void) {
    return map_dirty ? 1 : 0;
}

void nethack_clear_map_dirty(void) {
    map_dirty = FALSE;
}

// =============== TEST HELPER FUNCTIONS ===============
// These functions expose internal state for testing

// Get the something_worth_saving flag
int nethack_get_something_worth_saving(void) {
    extern struct flag flags;
    extern struct you u;
    return program_state.something_worth_saving;
}

// Get the in_moveloop flag
int nethack_get_in_moveloop(void) {
    return program_state.in_moveloop;
}

// Get the current SAVEF value from gamestate
const char* nethack_get_savef(void) {
    // gs is defined in decl.h as instance_globals_s
    extern struct instance_globals_s gs;
    if (gs.SAVEF[0] == '\0') {
        return NULL;
    }
    return gs.SAVEF;
}

// Clean up game state for testing
void nethack_cleanup_game(void) {
    fprintf(stderr, "[BRIDGE] Cleaning up game state...\n");

    // CRITICAL FIX: Use nh_restart() instead of freedynamicdata()!
    // freedynamicdata() causes "Invalid magic" memory corruption with our custom allocator
    // because ASLR makes saved pointers invalid across sessions.
    // nh_restart() just clears the heap cleanly without pointer dereferencing.
    if (program_state.gameover || game_started) {
        fprintf(stderr, "[BRIDGE] Calling nh_restart() to clean heap (NO freedynamicdata - ASLR issue!)\n");
        extern void nh_restart(void);
        nh_restart();  // Clear heap cleanly without freeing (avoids ASLR pointer corruption)
    }

    // Reset flags
    game_initialized = 0;
    game_started = 0;

    // Clear buffers
    memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);
    nethack_clear_lua_logs();

    // Reset program state if needed
    program_state.something_worth_saving = 0;
    program_state.gameover = 0;  // Reset gameover flag

#ifdef USE_ZONE_ALLOCATOR
    // Zone allocator cleanup is now handled by nh_reset() after this function
    // Don't do it here anymore
    fprintf(stderr, "[BRIDGE] Zone cleanup will be handled by nh_reset()\n");
#endif
    program_state.in_moveloop = 0;

    fprintf(stderr, "[BRIDGE] Game cleanup complete\n");
}

// Save current game state to snapshot
int nethack_save_snapshot(const char* filepath) {
    nethack_append_log("[SNAPSHOT] Saving snapshot to file...");

#ifdef USE_ZONE_ALLOCATOR
    int result = nethack_zone_snapshot_save(filepath);
    if (result == 0) {
        nethack_append_log("[SNAPSHOT] Snapshot saved successfully");
    } else {
        nethack_append_log("[SNAPSHOT] Failed to save snapshot");
    }
    return result;
#else
    nethack_append_log("[SNAPSHOT] Zone allocator not available");
    return -1;
#endif
}

// Load game state from snapshot
int nethack_load_snapshot(const char* filepath) {
    nethack_append_log("[SNAPSHOT] Loading fixed-memory snapshot...");

#ifdef USE_FIXED_MEMORY
    fprintf(stderr, "[SNAPSHOT] Loading from fixed memory snapshot\n");

    // Load the memory snapshot
    int result = nethack_zone_snapshot_load(filepath);

    if (result == 0) {
        nethack_append_log("[SNAPSHOT] Snapshot loaded successfully - pointers still valid!");

        // Restore critical game state flags
        game_started = 1;
        game_initialized = 1;
        character_creation_complete = 1;

        fprintf(stderr, "[INVENTORY] game_started set to 1 after restore\n");
        fprintf(stderr, "[INVENTORY] gi.invent pointer after restore: %p\n", gi.invent);

        // Mark that we need to resume from snapshot
        snapshot_loaded = true;

        program_state.something_worth_saving = 1;

        // Make sure window system is initialized
        iflags.window_inited = TRUE;

        // Re-init the game thread
        // REMOVED: Thread synchronization - NetHack is single-threaded!

        nethack_append_log("[SNAPSHOT] Ready to resume - all pointers preserved!");
        return 0;
    } else {
        nethack_append_log("[SNAPSHOT] Failed to load snapshot");
        return -1;
    }
#else
    nethack_append_log("[SNAPSHOT] Fixed memory not available");
    return -1;
#endif
}


// =============== YN CALLBACK BRIDGE FUNCTIONS ===============
// These bridge to the yn callback system in ios_winprocs.c

void nethack_set_yn_auto_yes(void) {
    extern void ios_enable_yn_auto_yes(void);
    ios_enable_yn_auto_yes();
}

void nethack_set_yn_auto_no(void) {
    extern void ios_enable_yn_auto_no(void);
    ios_enable_yn_auto_no();
}

void nethack_set_yn_ask_user(void) {
    extern void ios_enable_yn_ask_user(void);
    ios_enable_yn_ask_user();
}

void nethack_set_yn_default(void) {
    extern void ios_set_yn_mode(int);
    ios_set_yn_mode(3); // YN_MODE_DEFAULT
}

void nethack_set_next_yn_response(char response) {
    extern void ios_set_next_yn_response(char);
    ios_set_next_yn_response(response);
}

// Missing bridge functions for Swift compatibility
int nethack_can_save(void) {
    // Snapshot system is always available
    return 1;
}

void nethack_enable_threaded_mode(void) {
    // Threading is handled by iOS layer, no special setup needed
    // This is a no-op for now
}

int nethack_get_dungeon_level(void) {
    // Return current dungeon level
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.uz.dlevel;
}

const char* nethack_get_location_name(void) {
    static char location_buf[BUFSZ];

    if (!game_started || !program_state.in_moveloop) {
        return "Unknown";
    }

    // Get current location name from NetHack
    extern int describe_level(char *, int);
    describe_level(location_buf, BUFSZ);
    return location_buf;
}

long nethack_get_play_time(void) {
    // Return play time in seconds (using moves as proxy)
    if (!game_started) {
        return 0;
    }
    // NetHack tracks moves, not real time - return move count as proxy
    return svm.moves;
}

// Additional missing functions
int nethack_get_player_level(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.ulevel;
}

long nethack_get_player_gold(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    // Check if inventory exists before calling money_cnt
    if (!gi.invent) {
        return 0;  // No inventory = no gold
    }
    extern long money_cnt(struct obj *);
    return money_cnt(gi.invent);
}

// =============== PLAYER STATS FUNCTIONS ===============
// Direct implementation - read from NetHack's global 'u' structure
// No JSON needed, no indirection through ios_winprocs

int nethack_get_player_hp(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.uhp;
}

int nethack_get_player_hp_max(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.uhpmax;
}

int nethack_get_player_power(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.uen;
}

int nethack_get_player_power_max(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.uenmax;
}

long nethack_get_player_exp(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.uexp;
}

int nethack_get_player_ac(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 10;  // Default AC is 10 (no armor)
    }
    return u.uac;
}

int nethack_get_player_str(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    // NetHack uses ACURR(A_STR) macro to get current strength
    // A_STR is 0, and u.acurr is the current attributes
    return u.acurr.a[0];  // A_STR = 0
}

int nethack_get_player_dex(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.acurr.a[1];  // A_DEX = 1
}

int nethack_get_player_con(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.acurr.a[2];  // A_CON = 2
}

int nethack_get_player_int(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.acurr.a[3];  // A_INT = 3
}

int nethack_get_player_wis(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.acurr.a[4];  // A_WIS = 4
}

int nethack_get_player_cha(void) {
    if (!game_started || !program_state.in_moveloop) {
        return 0;
    }
    return u.acurr.a[5];  // A_CHA = 5
}

// Simple player stats without JSON - Swift will call individual functions
// External getter for conditions from ios_winprocs.c
extern unsigned long ios_get_current_conditions(void);

const char* nethack_get_player_stats_json(void) {
    static char json_buffer[512];

    if (!game_started || !program_state.in_moveloop) {
        // Return complete JSON structure with all required fields (including attributes)
        return "{\"hp\":0,\"hpmax\":0,\"pw\":0,\"pwmax\":0,\"level\":0,\"exp\":0,\"ac\":10,"
               "\"str\":0,\"dex\":0,\"con\":0,\"int\":0,\"wis\":0,\"cha\":0,"
               "\"gold\":0,\"moves\":0,\"dungeonLevel\":0,\"align\":\"unknown\",\"hunger\":0,\"conditions\":0}";
    }

    // Gold from snapshot (updated by game thread, safe to read)
    // This avoids the race condition with money_cnt() traversing inventory
    GameStateSnapshot snapshot;
    ios_get_game_state_snapshot(&snapshot);
    long gold = snapshot.player_gold;

    // Get conditions bitmask from ios_winprocs
    unsigned long conditions = ios_get_current_conditions();

    snprintf(json_buffer, sizeof(json_buffer),
        "{\"hp\":%d,\"hpmax\":%d,\"pw\":%d,\"pwmax\":%d,"
        "\"level\":%d,\"exp\":%ld,\"ac\":%d,"
        "\"str\":%d,\"dex\":%d,\"con\":%d,\"int\":%d,\"wis\":%d,\"cha\":%d,"
        "\"gold\":%ld,\"moves\":%ld,\"dungeonLevel\":%d,"
        "\"align\":\"%s\",\"hunger\":%d,\"conditions\":%lu}",
        u.uhp, u.uhpmax,
        u.uen, u.uenmax,
        u.ulevel, u.uexp, u.uac,
        u.acurr.a[0], u.acurr.a[1], u.acurr.a[2],  // STR, DEX, CON
        u.acurr.a[3], u.acurr.a[4], u.acurr.a[5],  // INT, WIS, CHA
        gold,
        svm.moves,
        u.uz.dlevel,
        (u.ualign.type == A_LAWFUL) ? "lawful" :
        (u.ualign.type == A_NEUTRAL) ? "neutral" :
        (u.ualign.type == A_CHAOTIC) ? "chaotic" : "unknown",
        (int)u.uhs,  /* hunger STATE (0-6), not raw counter u.uhunger */
        conditions
    );

    return json_buffer;
}


// NEW CLEAN LOAD IMPLEMENTATION - Uses ios_restore.c
int nethack_load_game_new(const char* filepath) {
    fprintf(stderr, "\n[LOAD_NEW_LOG] ========================================\n");
    fprintf(stderr, "[LOAD_NEW_LOG] Starting new load implementation\n");
    fprintf(stderr, "[LOAD_NEW_LOG] ========================================\n");

    if (!filepath || !*filepath) {
        fprintf(stderr, "[LOAD_NEW_LOG] ERROR: NULL or empty save path provided.\n");
        return 0;
    }

    fprintf(stderr, "[LOAD_NEW_LOG] Loading from: %s\n", filepath);

    // Step 1: Clean up any previous game state
    fprintf(stderr, "[LOAD_NEW_LOG] Step 1: Cleaning up previous game state...\n");
    nethack_cleanup_game();
    fprintf(stderr, "[LOAD_NEW_LOG] Step 1 finished.\n");

    // Step 2: SKIP nethack_real_init() during load!
    // CRITICAL FIX: Do NOT call nethack_real_init() here!
    // It calls early_init() and reset_commands() which corrupts the command queue.
    // ios_restore_complete() will handle ALL initialization properly.
    fprintf(stderr, "[LOAD_NEW_LOG] Step 2: Skipping nethack_real_init() - restore will handle it\n");
    fprintf(stderr, "[LOAD_NEW_LOG] Step 2 finished.\n");

    // Step 3: SKIP subsystem initialization - restore will handle it!
    // CRITICAL FIX: Do NOT initialize these here!
    // ios_restore_complete() calls init_nhwindows, l_nhcore_init, vision_init, etc.
    // Calling them twice causes corruption!
    fprintf(stderr, "[LOAD_NEW_LOG] Step 3: Skipping subsystem init - restore will handle it\n");
    fprintf(stderr, "[LOAD_NEW_LOG] Step 3 finished.\n");

    // Step 4: Set the save file name in gs.SAVEF
    // CRITICAL: NetHack expects gs.SAVEF to be just the filename, NOT the full path!
    // Extract just the filename from the full path
    const char* filename = strrchr(filepath, '/');
    if (filename) {
        filename++; // Skip the '/'
    } else {
        filename = filepath; // No path separator, use as-is
    }

    fprintf(stderr, "[LOAD_NEW_LOG] Step 4: Extracting filename from path\n");
    fprintf(stderr, "[LOAD_NEW_LOG]   Full path: %s\n", filepath);
    fprintf(stderr, "[LOAD_NEW_LOG]   Filename only: %s\n", filename);

    // Set gs.SAVEF to just the filename (NetHack will add SAVEPREFIX)
    strncpy(gs.SAVEF, filename, SAVESIZE - 1);
    gs.SAVEF[SAVESIZE - 1] = '\0';

    // Also keep a full path copy for compatibility if needed
    extern char SAVEF[256];  // Defined in ios_stubs_missing.c
    strncpy(SAVEF, filepath, 255);
    SAVEF[255] = '\0';

    fprintf(stderr, "[LOAD_NEW_LOG] Step 4 finished. gs.SAVEF='%s'\n", gs.SAVEF);

    // Step 5: Call the iOS restore function which handles everything
    fprintf(stderr, "[LOAD_NEW_LOG] Step 5: Calling ios_load_saved_game()...\n");
    extern int ios_load_saved_game(void);
    int result = ios_load_saved_game();
    fprintf(stderr, "[LOAD_NEW_LOG] Step 5 finished, result: %d (1=success, 0=fail, -1=no file)\n", result);

    // Step 6: Handle the result
    fprintf(stderr, "[LOAD_NEW_LOG] Step 6: Handling result...\n");
    if (result == 1) {
        fprintf(stderr, "[LOAD_NEW_LOG] ✅ SUCCESS! Game loaded and restored!\n");

        // Mark game as started
        game_started = 1;
        character_creation_complete = 1;
        program_state.something_worth_saving = 1;

        // Initialize display
        extern void docrt(void);
        fprintf(stderr, "[LOAD_NEW_LOG] Refreshing display...\n");
        docrt();

        fprintf(stderr, "[LOAD_NEW_LOG] Game is ready to play!\n");
    } else if (result == -1) {
        fprintf(stderr, "[LOAD_NEW_LOG] ⚠️ No save file found at the specified location\n");
    } else {
        fprintf(stderr, "[LOAD_NEW_LOG] ❌ ERROR: Failed to load game (result code %d)\n", result);
    }
    fprintf(stderr, "[LOAD_NEW_LOG] Step 6 finished.\n");

    fprintf(stderr, "[LOAD_NEW_LOG] ========================================\n");
    fprintf(stderr, "[LOAD_NEW_LOG] Load process complete. Final Result: %s\n",
            result == 1 ? "SUCCESS" : "FAILURE");
    fprintf(stderr, "[LOAD_NEW_LOG] ========================================\n\n");

    return result == 1 ? 1 : 0;
}

const char* nethack_get_save_info(void) {
    static char info_buf[BUFSZ];
    if (!game_started) {
        return "No game active";
    }
    snprintf(info_buf, BUFSZ, "Lvl:%d HP:%d/%d",
             u.uz.dlevel, u.uhp, u.uhpmax);
    return info_buf;
}

int nethack_real_is_initialized(void) {
    return game_initialized;
}

int nethack_real_is_started(void) {
    return game_started;
}

// Travel and examination functions
void nethack_travel_to(int swift_x, int swift_y) {
    // PERF TIMESTAMP
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double start_time = ts.tv_sec + ts.tv_nsec / 1e9;
    fprintf(stderr, "[%.3f] [C Bridge] nethack_travel_to START Swift(%d,%d)\n", start_time, swift_x, swift_y);

    // CRITICAL FIX: Swift sends SWIFT coordinates (0-based X and Y), NOT buffer coordinates!
    //
    // COORDINATE SYSTEMS:
    // - Swift:   X=0-78 (0-based), Y=0-20 (0-based) - array indices
    // - NetHack: X=1-79 (1-based), Y=0-20 (0-based) - game coordinates
    // - Buffer:  X=1-79, Y=2-22 (map_y + 2 offset for message lines)
    //
    // CONVERSION: Swift → NetHack
    // - map_x = swift_x + 1  (0-based → 1-based)
    // - map_y = swift_y      (already 0-based, no change)
    //
    // See: NetHackCoordinate.swift:174-178 for Swift→NetHack conversion
    // See: MapData.swift:29-33 for MapTile coordinate documentation

    extern struct you u;
    extern struct instance_flags iflags;

    // Convert Swift coords to NetHack MAP coords
    int map_x = swift_x + 1;  // 0-based → 1-based
    int map_y = swift_y;      // Already 0-based, use directly

    // Validate coordinates BEFORE any calculations
    if (map_x < 1 || map_x >= COLNO) {
        fprintf(stderr, "[%.3f] [C Bridge] Invalid map_x=%d from Swift(%d,%d)\n",
                start_time, map_x, swift_x, swift_y);
        return;
    }
    if (map_y < 0 || map_y >= ROWNO) {
        fprintf(stderr, "[%.3f] [C Bridge] Invalid map_y=%d from Swift(%d,%d)\n",
                start_time, map_y, swift_x, swift_y);
        return;
    }

    // Check if already at destination
    if (map_x == u.ux && map_y == u.uy) {
        return;
    }

    // CRITICAL FIX: Interrupt any ongoing travel FIRST!
    // When gm.multi > 0 (during travel), rhack() is never called, so CQ_CANNED is never checked.
    // We must call nomul(0) to set gm.multi = 0, which lets the next moveloop iteration
    // fall through to rhack(0) where CQ_CANNED is processed.
    //
    // ADDITIONAL FIX: Set ios_travel_interrupt_pending flag so lookaround() returns early.
    // This is checked at the START of each travel step (via patch in hack.c), allowing
    // immediate response to new taps instead of waiting for current step to complete.
    extern void nomul(int);
    extern void cmdq_clear(int);
    extern struct instance_globals_m gm;  // Contains 'multi' counter
    extern volatile int ios_travel_interrupt_pending;

    if (svc.context.travel || gm.multi > 0) {
        // Set interrupt flag - lookaround() checks this before any delay
        ios_travel_interrupt_pending = 1;
        nomul(0);
        svc.context.travel = svc.context.travel1 = 0;
        svc.context.run = 0;
        svc.context.mv = FALSE;
        cmdq_clear(CQ_CANNED);
    }

    // Set the travel destination in MAP coordinates
    iflags.travelcc.x = map_x;
    iflags.travelcc.y = map_y;
    u.tx = map_x;
    u.ty = map_y;

    // PERFORMANCE FIX: Use command queue instead of input queue for immediate travel!
    //
    // OLD APPROACH (slow):
    //   1. Queue Ctrl+_ character to input queue
    //   2. Wake up poskey() which is polling with 100ms timeout
    //   3. Game thread consumes character, looks up command binding
    //   4. Command binding maps to dotravel_target()
    //   Result: 100-2000ms delay depending on polling timing
    //
    // NEW APPROACH (immediate):
    //   1. Look up the retravel command's function pointer from gc.Cmd.commands
    //   2. Add dotravel_target() directly to CQ_CANNED command queue
    //   3. Send wake-up signal (null byte) to poskey()
    //   4. rhack() checks CQ_CANNED BEFORE calling poskey()
    //   5. dotravel_target() executes immediately
    //   Result: <10ms response time
    //
    // This is the same pattern used by action_system.c for kick, open, etc.
    // Note: dotravel_target is static in cmd.c, so we look it up via key binding.

    extern void cmdq_add_ec(int queue, int (*func)(void));
    extern void ios_queue_input(char);
    extern struct instance_globals_c gc;  // NetHack's global 'c' struct containing Cmd

    // Look up the retravel command (Ctrl+_ = 0x1F) from the command table
    // This gives us the ext_func_tab entry which contains the function pointer
    const struct ext_func_tab *retravel_cmd = gc.Cmd.commands[0x1F];
    if (!retravel_cmd || !retravel_cmd->ef_funct) {
        fprintf(stderr, "[%.3f] [C Bridge] ERROR: retravel command not bound!\n", start_time);
        // Fallback to old approach
        char travel_cmd[2] = {0x1F, 0};
        nethack_real_send_input(travel_cmd);
        return;
    }

    // Queue travel command and wake game thread
    cmdq_add_ec(CQ_CANNED, retravel_cmd->ef_funct);
    ios_queue_input('\0');
}

// Check if travel is currently in progress
// Returns: 1 if traveling, 0 if idle
int nethack_is_traveling(void) {
    if (!game_started) {
        return 0;
    }

    // svc.context.travel is true when travel command is active
    // svc.context.run == 8 means travel mode is active
    // Either condition means we're traveling
    return (svc.context.travel || svc.context.run == 8) ? 1 : 0;
}

const char* nethack_examine_tile(int swift_x, int swift_y) {
    // CRITICAL FIX: Swift sends SWIFT coordinates (0-based X and Y), NOT buffer coordinates!
    // Same coordinate conversion as nethack_travel_to()
    // See nethack_travel_to() comments for full coordinate system documentation

    extern struct you u;

    // Convert Swift coords to NetHack MAP coords
    int map_x = swift_x + 1;  // 0-based → 1-based
    int map_y = swift_y;      // Already 0-based, use directly

    // Validate coordinates BEFORE any use
    if (map_x < 1 || map_x >= COLNO) {
        fprintf(stderr, "[C Bridge] Invalid map_x=%d from Swift(%d,%d)\n",
                map_x, swift_x, swift_y);
        return NULL;
    }
    if (map_y < 0 || map_y >= ROWNO) {
        fprintf(stderr, "[C Bridge] Invalid map_y=%d from Swift(%d,%d)\n",
                map_y, swift_x, swift_y);
        return NULL;
    }

    // PERF: Get start timestamp for performance measurement
    struct timeval tv_start, tv_end;
    gettimeofday(&tv_start, NULL);
    double start_ms = tv_start.tv_sec * 1000.0 + tv_start.tv_usec / 1000.0;

    fprintf(stderr, "[C Bridge] [%.3fms] Examine tile at map(%d,%d) [Swift(%d,%d)] (player at map(%d,%d))\n",
            start_ms, map_x, map_y, swift_x, swift_y, u.ux, u.uy);

    // ARCHITECTURAL FIX: Removed suppress_messages_during_examine flag
    // OLD APPROACH: Bridge suppressed Swift callbacks to prevent 8s main thread hang
    // NEW APPROACH: examineTileAsync() runs on background queue → callbacks can't block UI
    // Bridge is now a pure adapter - no message delivery control (game logic)!

    // DIRECT LOOKAT() CALL - Same as `;` (farlook) command!
    // lookat() is explicitly exported for iOS Bridge (pager.c:655)
    // This gives us precise descriptions instead of generic "spellbook or door"
    //
    // lookat() returns:
    // - buf: Main description (e.g., "a closed door", "tame dog called Fido")
    // - monbuf: How monster was seen (e.g., "telepathy", "infravision")
    // - return: struct permonst* for monster data lookup (unused here)
    extern struct permonst *lookat(coordxy, coordxy, char *, char *);
    extern char *doname(struct obj *);

    static char buf[BUFSZ];
    static char monbuf[BUFSZ];
    static char result_buf[BUFSZ * 4];  // Larger buffer for object piles

    gettimeofday(&tv_end, NULL);
    double before_lookat_ms = tv_end.tv_sec * 1000.0 + tv_end.tv_usec / 1000.0;
    fprintf(stderr, "[C Bridge] [%.3fms] Calling lookat(%d,%d) [+%.3fms setup]\n",
            before_lookat_ms, map_x, map_y, before_lookat_ms - start_ms);

    // Call lookat() directly - this is what `;` does!
    struct permonst *pm = lookat(map_x, map_y, buf, monbuf);
    (void)pm;  // Unused for now, but could be used for "more info" lookup

    gettimeofday(&tv_end, NULL);
    double after_lookat_ms = tv_end.tv_sec * 1000.0 + tv_end.tv_usec / 1000.0;
    fprintf(stderr, "[C Bridge] [%.3fms] lookat() returned buf='%s', monbuf='%s' [+%.3fms lookat]\n",
            after_lookat_ms, buf, monbuf, after_lookat_ms - before_lookat_ms);

    // Check if we got any description
    if (buf[0] == '\0') {
        fprintf(stderr, "[C Bridge] [%.3fms] No description from lookat() [+%.3fms total]\n",
                after_lookat_ms, after_lookat_ms - start_ms);
        return "unexplored area";
    }

    // Format result: combine buf and monbuf if both present
    // buf = "tame dog called Fido"
    // monbuf = "[seen: telepathy]" or ""
    if (monbuf[0] != '\0') {
        Sprintf(result_buf, "%s %s", buf, monbuf);
    } else {
        Strcpy(result_buf, buf);
    }

    // CHECK FOR OBJECT PILES - Show first 6 items, then "+X items" if 7+
    // svl.level.objects[x][y] is the first object at location
    // otmp->nexthere chains to additional objects
    struct obj *otmp = svl.level.objects[map_x][map_y];
    if (otmp) {
        // Count total objects first
        int total_count = 0;
        for (struct obj *count_obj = otmp; count_obj; count_obj = count_obj->nexthere) {
            total_count++;
        }

        if (total_count > 1) {
            // Multiple objects - show list instead of lookat() description
            result_buf[0] = '\0';  // Clear lookat result, show clean list

            // Show up to 6 items (no point showing "+1 more")
            int max_show = (total_count <= 6) ? total_count : 5;
            int shown = 0;
            for (struct obj *list_obj = otmp; list_obj && shown < max_show; list_obj = list_obj->nexthere) {
                if (shown > 0) Strcat(result_buf, "\n");
                Strcat(result_buf, doname(list_obj));
                shown++;
            }

            // Show "+X items" only if 2+ remaining
            int remaining = total_count - shown;
            if (remaining >= 2) {
                char more_buf[32];
                Sprintf(more_buf, "\n+%d more items", remaining);
                Strcat(result_buf, more_buf);
            }

            fprintf(stderr, "[C Bridge] Object pile: %d total, showing %d\n", total_count, shown);
        }
    }

    gettimeofday(&tv_end, NULL);
    double end_ms = tv_end.tv_sec * 1000.0 + tv_end.tv_usec / 1000.0;
    fprintf(stderr, "[C Bridge] [%.3fms] Final description: '%s' [%.3fms TOTAL]\n",
            end_ms, result_buf, end_ms - start_ms);

    return result_buf;  // Return to Swift - same info as `;` + object pile list!
}


// Directional action handlers - now using generic action system
// All validation, coordinate conversion, and command queueing is handled
// by execute_directional_action() in action_system.c

void nethack_kick_door(int buffer_x, int buffer_y) {
    execute_directional_action(buffer_x, buffer_y, ACTION_KICK.nethack_func,
                               ACTION_KICK.name, ACTION_KICK.validation_flags);
}

void nethack_open_door(int buffer_x, int buffer_y) {
    execute_directional_action(buffer_x, buffer_y, ACTION_OPEN.nethack_func,
                               ACTION_OPEN.name, ACTION_OPEN.validation_flags);
}

void nethack_close_door(int buffer_x, int buffer_y) {
    execute_directional_action(buffer_x, buffer_y, ACTION_CLOSE.nethack_func,
                               ACTION_CLOSE.name, ACTION_CLOSE.validation_flags);
}

void nethack_fire_quiver(int buffer_x, int buffer_y) {
    execute_directional_action(buffer_x, buffer_y, ACTION_FIRE.nethack_func,
                               ACTION_FIRE.name, ACTION_FIRE.validation_flags);
}

void nethack_throw_item(int buffer_x, int buffer_y) {
    execute_directional_action(buffer_x, buffer_y, ACTION_THROW.nethack_func,
                               ACTION_THROW.name, ACTION_THROW.validation_flags);
}

void nethack_unlock_door(int buffer_x, int buffer_y) {
    execute_directional_action(buffer_x, buffer_y, ACTION_UNLOCK.nethack_func,
                               ACTION_UNLOCK.name, ACTION_UNLOCK.validation_flags);
}

void nethack_lock_door(int buffer_x, int buffer_y) {
    execute_directional_action(buffer_x, buffer_y, ACTION_LOCK.nethack_func,
                               ACTION_LOCK.name, ACTION_LOCK.validation_flags);
}

// =============================================================================
// AUTOTRAVEL TO INTERESTING LOCATIONS
// =============================================================================

// External functions from NetHack source
extern void domove(void);  // From hack.c - execute movement (triggers travel)
extern stairway *stairway_find_dir(boolean up);  // From stairs.c - find stairs
// cansee is a macro defined in vision.h - no extern needed

// =============================================================================
// TRAVEL HELPER - Triggers travel to given NetHack coordinates
// =============================================================================
// Coordinates are in NetHack format: X=1-79 (1-based), Y=0-20 (0-based)
// This is the same pattern used by nethack_travel_to() for map taps.

static int ios_trigger_travel_internal(int nethack_x, int nethack_y) {
    extern struct you u;
    extern struct instance_flags iflags;
    extern void cmdq_add_ec(int queue, int (*func)(void));
    extern void ios_queue_input(char);
    extern struct instance_globals_c gc;
    extern void nomul(int);
    extern void cmdq_clear(int);
    extern struct instance_globals_m gm;
    extern volatile int ios_travel_interrupt_pending;

    // Validate coordinates
    if (nethack_x < 1 || nethack_x >= COLNO) {
        fprintf(stderr, "[Bridge] ios_trigger_travel: Invalid x=%d\n", nethack_x);
        return 0;
    }
    if (nethack_y < 0 || nethack_y >= ROWNO) {
        fprintf(stderr, "[Bridge] ios_trigger_travel: Invalid y=%d\n", nethack_y);
        return 0;
    }

    // Already at destination?
    if (nethack_x == u.ux && nethack_y == u.uy) {
        printf("[Bridge] Already at destination (%d,%d)\n", nethack_x, nethack_y);
        return 1;  // Success - we're there
    }

    // Interrupt any ongoing travel first
    if (svc.context.travel || gm.multi > 0) {
        ios_travel_interrupt_pending = 1;
        nomul(0);
        svc.context.travel = svc.context.travel1 = 0;
        svc.context.run = 0;
        svc.context.mv = FALSE;
        cmdq_clear(CQ_CANNED);
    }

    // Set travel destination (NetHack coordinates)
    iflags.travelcc.x = nethack_x;
    iflags.travelcc.y = nethack_y;
    u.tx = nethack_x;
    u.ty = nethack_y;

    // Queue retravel command (Ctrl+_ = 0x1F)
    const struct ext_func_tab *retravel_cmd = gc.Cmd.commands[0x1F];
    if (!retravel_cmd || !retravel_cmd->ef_funct) {
        fprintf(stderr, "[Bridge] ERROR: retravel command not bound!\n");
        return 0;
    }

    // Queue command and wake game thread
    cmdq_add_ec(CQ_CANNED, retravel_cmd->ef_funct);
    ios_queue_input('\0');

    printf("[Bridge] Travel queued to (%d,%d)\n", nethack_x, nethack_y);
    return 1;
}

// Travel to upward stairs
int nethack_travel_to_stairs_up(void) {
    if (!game_started) {
        fprintf(stderr, "[Bridge] nethack_travel_to_stairs_up: game not started\n");
        return 0;
    }

    // OPTIMIZATION: Use cached snapshot coordinates (updated once per turn)
    // instead of calling stairway_find_dir() which searches the entire map
    extern void ios_get_game_state_snapshot(GameStateSnapshot *out);
    GameStateSnapshot snapshot;
    ios_get_game_state_snapshot(&snapshot);

    if (snapshot.stairs_up_x < 0 || snapshot.stairs_up_y < 0) {
        fprintf(stderr, "[Bridge] No upward stairs found on this level\n");
        return 0;
    }

    printf("[Bridge] Found upward stairs at (%d, %d) [from snapshot]\n",
           snapshot.stairs_up_x, snapshot.stairs_up_y);

    // Trigger travel to stairs (coordinates are already in NetHack format)
    return ios_trigger_travel_internal(snapshot.stairs_up_x, snapshot.stairs_up_y);
}

// Travel to downward stairs
int nethack_travel_to_stairs_down(void) {
    if (!game_started) {
        fprintf(stderr, "[Bridge] nethack_travel_to_stairs_down: game not started\n");
        return 0;
    }

    // CRITICAL FIX: If player is already ON downstairs, just send ">" command
    // Travel is for MOVING to stairs, not descending them!
    stairway *current_stway = stairway_at(u.ux, u.uy);
    if (current_stway && !current_stway->up) {
        // Player is on DOWN stairs - send descent command
        printf("[Bridge] Player on DOWN stairs at (%d,%d) - sending '>' command\n", u.ux, u.uy);
        nethack_send_input_threaded(">");
        return 1;
    }

    // OPTIMIZATION: Use cached snapshot coordinates (updated once per turn)
    // instead of calling stairway_find_dir() which searches the entire map
    extern void ios_get_game_state_snapshot(GameStateSnapshot *out);
    GameStateSnapshot snapshot;
    ios_get_game_state_snapshot(&snapshot);

    if (snapshot.stairs_down_x < 0 || snapshot.stairs_down_y < 0) {
        fprintf(stderr, "[Bridge] No downward stairs found on this level\n");
        return 0;
    }

    printf("[Bridge] Found downward stairs at (%d, %d) [from snapshot]\n",
           snapshot.stairs_down_x, snapshot.stairs_down_y);

    // Trigger travel to stairs (coordinates are already in NetHack format)
    return ios_trigger_travel_internal(snapshot.stairs_down_x, snapshot.stairs_down_y);
}

// Travel to nearest visible altar
int nethack_travel_to_altar(void) {
    if (!game_started) {
        fprintf(stderr, "[Bridge] nethack_travel_to_altar: game not started\n");
        return 0;
    }

    // OPTIMIZATION: Use cached snapshot coordinates (updated once per turn)
    // instead of scanning the entire map
    extern void ios_get_game_state_snapshot(GameStateSnapshot *out);
    GameStateSnapshot snapshot;
    ios_get_game_state_snapshot(&snapshot);

    if (snapshot.altar_x < 0 || snapshot.altar_y < 0) {
        fprintf(stderr, "[Bridge] No altar found on this level\n");
        return 0;
    }

    printf("[Bridge] Found altar at (%d, %d) [from snapshot]\n",
           snapshot.altar_x, snapshot.altar_y);

    // Trigger travel to altar (coordinates are already in NetHack format)
    return ios_trigger_travel_internal(snapshot.altar_x, snapshot.altar_y);
}

// Travel to nearest visible fountain
int nethack_travel_to_fountain(void) {
    if (!game_started) {
        fprintf(stderr, "[Bridge] nethack_travel_to_fountain: game not started\n");
        return 0;
    }

    // OPTIMIZATION: Use cached snapshot coordinates (updated once per turn)
    // instead of scanning the entire map
    extern void ios_get_game_state_snapshot(GameStateSnapshot *out);
    GameStateSnapshot snapshot;
    ios_get_game_state_snapshot(&snapshot);

    if (snapshot.fountain_x < 0 || snapshot.fountain_y < 0) {
        fprintf(stderr, "[Bridge] No fountain found on this level\n");
        return 0;
    }

    printf("[Bridge] Found fountain at (%d, %d) [from snapshot]\n",
           snapshot.fountain_x, snapshot.fountain_y);

    // Trigger travel to fountain (coordinates are already in NetHack format)
    return ios_trigger_travel_internal(snapshot.fountain_x, snapshot.fountain_y);
}

// =============================================================================
// ENGRAVING FUNCTIONS (Phase 1: Quick phrases for combat)
// =============================================================================

// External NetHack functions for engraving
extern struct engr *engr_at(coordxy x, coordxy y);  // From engrave.c - check for engraving at position

// Check if player can engrave at current location
// Returns: true if engraving is possible, false otherwise
bool nethack_can_engrave(void) {
    if (!game_started) {
        return false;
    }

    // Check game state conditions that prevent engraving
    // Based on NetHack's engrave.c:doengrave() checks
    if (Levitation) {
        return false;  // Can't engrave while levitating
    }
    if (u.uinwater) {
        return false;  // Can't engrave underwater
    }
    if (Is_airlevel(&u.uz)) {
        return false;  // Can't engrave on Plane of Air
    }
    if (is_lava(u.ux, u.uy)) {
        return false;  // Can't engrave in lava
    }

    return true;
}

// Get engraving text at player's current position
// Returns: C string with engraving text, or NULL if no engraving
const char* nethack_get_engraving_at_player(void) {
    if (!game_started) {
        return NULL;
    }

    // Call NetHack's engr_at() to check for engraving
    struct engr *ep = engr_at(u.ux, u.uy);

    if (!ep) {
        return NULL;  // No engraving at this position
    }

    // Return the actual engraving text (index 0 of engr_txt array)
    return ep->engr_txt[0];
}

// Quick engrave with finger (for combat-speed Elbereth)
// Sends command sequence: E → - (finger) → text → \n
// Returns: true on success, false on failure
bool nethack_quick_engrave(const char* text) {
    if (!nethack_can_engrave()) {
        return false;
    }

    if (!text || strlen(text) == 0) {
        fprintf(stderr, "[Bridge] nethack_quick_engrave: empty text\n");
        return false;
    }

    // Build complete command string atomically
    // Format: E-[text]\n
    // E = engrave command
    // - = use finger (DUST engraving, 1 turn)
    // text = what to engrave
    // \n = confirm
    char command[BUFSZ];
    int written = snprintf(command, BUFSZ, "E-%s\n", text);

    if (written < 0 || written >= BUFSZ) {
        fprintf(stderr, "[Bridge] nethack_quick_engrave: command too long\n");
        return false;
    }

    // Send complete command atomically as one string
    nethack_real_send_input(command);

    printf("[Bridge] Quick engraved: '%s' (with finger)\n", text);
    return true;
}

// Engrave with a specific tool (wand, athame, etc.)
// tool_invlet: inventory letter of tool to use (e.g., 'a' for wand)
// Returns: true on success, false on failure
bool nethack_engrave_with_tool(const char* text, char tool_invlet) {
    if (!nethack_can_engrave()) {
        return false;
    }

    if (!text || strlen(text) == 0) {
        fprintf(stderr, "[Bridge] nethack_engrave_with_tool: empty text\n");
        return false;
    }

    // Build complete command string atomically
    // Format: E[invlet][text]\n
    // E = engrave command
    // invlet = inventory letter of tool
    // text = what to engrave
    // \n = confirm
    char command[BUFSZ];
    int written = snprintf(command, BUFSZ, "E%c%s\n", tool_invlet, text);

    if (written < 0 || written >= BUFSZ) {
        fprintf(stderr, "[Bridge] nethack_engrave_with_tool: command too long\n");
        return false;
    }

    // Send complete command atomically as one string
    nethack_real_send_input(command);

    printf("[Bridge] Engraved: '%s' (with tool '%c')\n", text, tool_invlet);
    return true;
}

void nethack_reset_memory(void) {
    // CRITICAL: Full memory wipe for clean restart
    // MUST use nh_restart() not nh_reset() to clear old block headers!
    // Without memset, old BLOCK_MAGIC and corrupt pointers remain in heap
    // causing crashes on 3rd+ game restart
    extern void nh_restart(void);  // from nethack_memory_final.c
    fprintf(stderr, "[BRIDGE] Full memory restart (memset heap to zero)\n");
    nh_restart();
}

// Check if we're resuming from a snapshot (for startGame to skip reset)
bool nethack_is_snapshot_loaded(void) {
    return snapshot_loaded;
}

void nethack_run_game_threaded(void) {
    // The game loop is actually moveloop() from allmain.c
    extern void moveloop(boolean);
    extern int use_threaded_mode;  // from ios_winprocs.c

    /*
     * CRITICAL FIX: Clean exit from death via setjmp/longjmp
     *
     * These are defined in ios_dylib_stubs.c and provide a clean exit path
     * when the player dies and nethack_exit() is called.
     *
     * Without this fix, after death:
     * 1. really_done() calls freedynamicdata() - frees all game memory
     * 2. nh_terminate() calls nethack_exit() which returns (doesn't exit on iOS)
     * 3. Control unwinds back through the call stack
     * 4. moveloop_core() continues executing with FREED memory -> CRASH
     *
     * With this fix:
     * 1. setjmp() establishes return point here
     * 2. When nethack_exit() is called, longjmp() jumps directly back
     * 3. moveloop_core() is bypassed entirely
     * 4. Function returns cleanly
     */
    extern jmp_buf ios_game_exit_jmp;
    extern int ios_game_exit_jmp_set;
    extern int ios_game_exit_status;

    if (!game_started) {
        fprintf(stderr, "[BRIDGE] Cannot run game - not properly initialized\n");
        return;
    }

    // CRITICAL: Enable threaded mode BEFORE moveloop starts
    // This makes nh_poskey() BLOCK until input is available
    // Without this, nh_poskey() returns 0 (no input) and NetHack waits forever
    use_threaded_mode = 1;
    fprintf(stderr, "[BRIDGE] Set use_threaded_mode=1 for blocking input\n");

    // CRITICAL FIX: Set game_thread_running=1 so nh_poskey_blocking actually waits!
    // Without this, the while loop is skipped and ESC is returned immediately
    extern volatile int game_thread_running;
    game_thread_running = 1;
    fprintf(stderr, "[BRIDGE] Set game_thread_running=1 for pthread_cond_wait\n");

    /*
     * Set up the longjmp return point for clean game exit.
     *
     * When setjmp() returns:
     * - 0 = initial call, continue to moveloop
     * - non-zero = returned via longjmp from nethack_exit(), game is over
     */
    int jmp_result = setjmp(ios_game_exit_jmp);
    if (jmp_result != 0) {
        /* Returned via longjmp from nethack_exit() - game ended cleanly */
        fprintf(stderr, "[BRIDGE] Game exited cleanly via longjmp (status=%d)\n",
                ios_game_exit_status);
        ios_game_exit_jmp_set = 0;  /* Mark jmp_buf as invalid */
        return;  /* Exit without crashing */
    }

    /* Mark jmp_buf as valid for nethack_exit() to use */
    ios_game_exit_jmp_set = 1;
    fprintf(stderr, "[BRIDGE] setjmp established for clean game exit\n");

    // If we loaded a snapshot, we need to restart moveloop with resuming=TRUE
    if (snapshot_loaded) {
        fprintf(stderr, "[BRIDGE] Resuming moveloop from snapshot\n");
        snapshot_loaded = false;  // Reset flag

        // CRITICAL: moveloop(TRUE) internally calls moveloop_preamble(TRUE)
        // This sets u.umovement = NORMAL_SPEED and other restore-specific setup

        // NOTE: For restored games, ios_restore_complete() already sent the game ready signal
        // after it finished restoring all game state. No need to signal here.

        moveloop(TRUE);  // TRUE = resuming from save/snapshot
    } else if (!program_state.in_moveloop) {
        // Normal new game start
        fprintf(stderr, "[BRIDGE] Starting new moveloop\n");

        // DEBUG: Check command bindings before starting moveloop
        extern struct instance_globals_c gc;
        extern struct instance_flags iflags;
        const void *cmd_4 = gc.Cmd.commands['4'];
        fprintf(stderr, "[BRIDGE] DEBUG BEFORE moveloop(): gc.Cmd.num_pad=%d, iflags.num_pad=%d\n",
                gc.Cmd.num_pad, iflags.num_pad);
        fprintf(stderr, "[BRIDGE] DEBUG: Key '4' binding = %p (NULL=not bound)\n", cmd_4);

        // NOTE: moveloop() calls moveloop_preamble() which sets program_state.in_moveloop = 1
        // We let NetHack handle this flag naturally instead of setting it manually
        // This ensures all moveloop_preamble() initialization happens correctly

        // NOTE: For new games, the game ready signal will be sent from the FIRST
        // ios_nh_poskey() call when NetHack yields waiting for input.
        // At that point, moveloop_preamble() has completed and all globals are initialized.

        moveloop(FALSE);  // FALSE = not resuming from save
    } else {
        fprintf(stderr, "[BRIDGE] Already in moveloop, not starting another\n");
    }

    /* If we reach here, moveloop exited normally (program_state.gameover check) */
    ios_game_exit_jmp_set = 0;  /* Mark jmp_buf as invalid */
    fprintf(stderr, "[BRIDGE] moveloop exited normally\n");
}

// Send input to NetHack (actual implementation)
void nethack_real_send_input(const char* input) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double timestamp = ts.tv_sec + ts.tv_nsec / 1e9;

    if (!input) return;

    fprintf(stderr, "[%.3f] [C Bridge] nethack_real_send_input START\n", timestamp);

    // Queue each character to the iOS input system
    extern void ios_queue_input(char);
    while (*input) {
        fprintf(stderr, "[%.3f] [C Bridge] Queueing char 0x%02X\n", timestamp, (unsigned char)*input);
        ios_queue_input(*input);
        input++;
    }

    clock_gettime(CLOCK_MONOTONIC, &ts);
    double end_time = ts.tv_sec + ts.tv_nsec / 1e9;
    fprintf(stderr, "[%.3f] [C Bridge] nethack_real_send_input END (took %.3fms)\n", end_time, (end_time - timestamp) * 1000);
}

void nethack_send_input_threaded(const char* input) {
    // Just call the regular send input function
    nethack_real_send_input(input);
}

// Character creation setters
void nethack_set_role(int role_idx) {
    fprintf(stderr, "[C SET_ROLE] Called with role_idx=%d, NUM_ROLES=%d\n", role_idx, NUM_ROLES);
    fprintf(stderr, "[C SET_ROLE] flags.initrole BEFORE: %d\n", flags.initrole);

    if (role_idx >= 0 && role_idx < NUM_ROLES) {
        flags.initrole = role_idx;
        fprintf(stderr, "[C SET_ROLE] ✅ SET flags.initrole = %d\n", flags.initrole);
    } else {
        fprintf(stderr, "[C SET_ROLE] ❌ INVALID role_idx %d (must be 0-%d)\n",
                role_idx, NUM_ROLES-1);
    }
}

void nethack_set_race(int race_idx) {
    fprintf(stderr, "[C SET_RACE] Called with race_idx=%d, NUM_RACES=%d\n", race_idx, NUM_RACES);
    fprintf(stderr, "[C SET_RACE] flags.initrace BEFORE: %d\n", flags.initrace);

    if (race_idx >= 0 && race_idx < NUM_RACES) {
        flags.initrace = race_idx;
        fprintf(stderr, "[C SET_RACE] ✅ SET flags.initrace = %d\n", flags.initrace);
    } else {
        fprintf(stderr, "[C SET_RACE] ❌ INVALID race_idx %d (must be 0-%d)\n",
                race_idx, NUM_RACES-1);
    }
}

void nethack_set_gender(int gender_idx) {
    fprintf(stderr, "[C SET_GENDER] Called with gender_idx=%d, ROLE_GENDERS=%d\n",
            gender_idx, ROLE_GENDERS);
    fprintf(stderr, "[C SET_GENDER] flags.initgend BEFORE: %d\n", flags.initgend);

    if (gender_idx >= 0 && gender_idx < ROLE_GENDERS) {
        flags.initgend = gender_idx;
        fprintf(stderr, "[C SET_GENDER] ✅ SET flags.initgend = %d\n", flags.initgend);
    } else {
        fprintf(stderr, "[C SET_GENDER] ❌ INVALID gender_idx %d (must be 0-%d)\n",
                gender_idx, ROLE_GENDERS-1);
    }
}

void nethack_set_alignment(int align_idx) {
    fprintf(stderr, "[C SET_ALIGNMENT] Called with align_idx=%d, ROLE_ALIGNS=%d\n",
            align_idx, ROLE_ALIGNS);
    fprintf(stderr, "[C SET_ALIGNMENT] flags.initalign BEFORE: %d\n", flags.initalign);

    if (align_idx >= 0 && align_idx < ROLE_ALIGNS) {
        flags.initalign = align_idx;
        fprintf(stderr, "[C SET_ALIGNMENT] ✅ SET flags.initalign = %d\n", flags.initalign);
    } else {
        fprintf(stderr, "[C SET_ALIGNMENT] ❌ INVALID align_idx %d (must be 0-%d)\n",
                align_idx, ROLE_ALIGNS-1);
    }
}

void nethack_set_player_name(const char* name) {
    if (!name || !*name) return;

    // Set the player name in svp.plname
    strncpy(svp.plname, name, PL_NSIZ - 1);
    svp.plname[PL_NSIZ - 1] = '\0';
}

const char* nethack_get_player_name(void) {
    // Return the player name from svp.plname
    if (svp.plname[0]) {
        return svp.plname;
    }
    return NULL;
}

const char* nethack_get_player_class_name(void) {
    // Return the current player's class/role name
    if (gu.urole.name.m) {
        return gu.urole.name.m;
    }
    return "Unknown";
}

const char* nethack_get_player_race_name(void) {
    // Return the current player's race name
    if (gu.urace.noun) {
        return gu.urace.noun;
    }
    return "Unknown";
}

// Validate character selection before finalizing
// Returns 0 if valid, error code otherwise
int nethack_validate_character_selection(void) {
    fprintf(stderr, "\n[VALIDATE] === CHARACTER VALIDATION START ===\n");
    fprintf(stderr, "[VALIDATE] Checking character selection...\n");
    fprintf(stderr, "[VALIDATE] Name: '%s'\n", svp.plname);
    fprintf(stderr, "[VALIDATE] Role: %d (NONE=-1, RANDOM=-2)\n", flags.initrole);
    fprintf(stderr, "[VALIDATE] Race: %d (NONE=-1, RANDOM=-2)\n", flags.initrace);
    fprintf(stderr, "[VALIDATE] Gender: %d (NONE=-1, RANDOM=-2)\n", flags.initgend);
    fprintf(stderr, "[VALIDATE] Alignment: %d (NONE=-1, RANDOM=-2)\n", flags.initalign);

    // Validate player name
    if (!svp.plname[0]) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Player name is empty!\n");
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 1; // Error: empty name
    }

    // Validate role - must be >= 0 (valid) or -2 (random), NOT -1 (none)
    if (flags.initrole == ROLE_NONE) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Role is NONE (-1)!\n");
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 2; // Error: role not selected
    }

    if (flags.initrole != ROLE_RANDOM && (flags.initrole < 0 || flags.initrole >= NUM_ROLES)) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Role %d is out of range (must be 0-%d or -2 for random)!\n",
                flags.initrole, NUM_ROLES-1);
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 3; // Error: role out of range
    }

    // Validate race - must be >= 0 (valid) or -2 (random), NOT -1 (none)
    if (flags.initrace == ROLE_NONE) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Race is NONE (-1)!\n");
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 4; // Error: race not selected
    }

    if (flags.initrace != ROLE_RANDOM && (flags.initrace < 0 || flags.initrace >= NUM_RACES)) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Race %d is out of range (must be 0-%d or -2 for random)!\n",
                flags.initrace, NUM_RACES-1);
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 5; // Error: race out of range
    }

    // Validate gender - must be >= 0 (valid) or -2 (random), NOT -1 (none)
    if (flags.initgend == ROLE_NONE) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Gender is NONE (-1)!\n");
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 6; // Error: gender not selected
    }

    if (flags.initgend != ROLE_RANDOM && (flags.initgend < 0 || flags.initgend >= ROLE_GENDERS)) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Gender %d is out of range (must be 0-%d or -2 for random)!\n",
                flags.initgend, ROLE_GENDERS-1);
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 7; // Error: gender out of range
    }

    // Validate alignment - must be >= 0 (valid) or -2 (random), NOT -1 (none)
    if (flags.initalign == ROLE_NONE) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Alignment is NONE (-1)!\n");
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 8; // Error: alignment not selected
    }

    if (flags.initalign != ROLE_RANDOM && (flags.initalign < 0 || flags.initalign >= ROLE_ALIGNS)) {
        fprintf(stderr, "[VALIDATE] ❌ FAIL: Alignment %d is out of range (must be 0-%d or -2 for random)!\n",
                flags.initalign, ROLE_ALIGNS-1);
        fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION FAILED ===\n\n");
        return 9; // Error: alignment out of range
    }

    fprintf(stderr, "[VALIDATE] ✅ SUCCESS: All character fields are valid!\n");
    fprintf(stderr, "[VALIDATE] === CHARACTER VALIDATION COMPLETE ===\n\n");
    return 0; // Success
}

// Death information functions are implemented in ios_winprocs.c
// (nethack_is_player_dead, nethack_get_death_info, nethack_clear_death_info)

// =============================================================================
// INVENTORY SYSTEM - Real NetHack inventory data
// =============================================================================

// Get count of items in player inventory
int nethack_get_inventory_count(void) {
    // FIX: Removed in_moveloop check - inventory should be accessible anytime during gameplay
    // User wants to check inventory while waiting for input, not just during move processing
    if (!game_started) {
        return 0;
    }
    if (!gi.invent) {
        return 0;
    }

    int count = 0;
    struct obj *otmp;

    // gi.invent is the global inventory linked list
    for (otmp = gi.invent; otmp; otmp = otmp->nobj) {
        count++;
    }

    return count;
}

// Fill inventory array with real NetHack items
int nethack_get_inventory_items(InventoryItem *items, int max_items) {
    // FIX: Removed in_moveloop check - inventory should be accessible anytime during gameplay
    // User wants to check inventory while waiting for input, not just during move processing
    if (!game_started) {
        return 0;
    }
    if (!gi.invent) {
        return 0;
    }

    int count = 0;
    struct obj *otmp;

    if (!items) {
        return 0;
    }

    for (otmp = gi.invent; otmp && count < max_items; otmp = otmp->nobj) {
        InventoryItem *item = &items[count];

        // Basic info
        item->invlet = otmp->invlet;
        item->quantity = (int)otmp->quan;
        item->oclass = otmp->oclass;

        // Get full name (WARNING: doname() returns static buffer, must copy!)
        char *name = doname(otmp);
        item->name = strdup(name);  // Caller must free()

        // BUC status (Blessed/Uncursed/Cursed)
        item->buc_known = otmp->bknown ? true : false;
        if (otmp->bknown) {
            if (otmp->blessed) {
                item->buc_status = 'B';  // Blessed
            } else if (otmp->cursed) {
                item->buc_status = 'C';  // Cursed
            } else {
                item->buc_status = 'U';  // Uncursed
            }
        } else {
            item->buc_status = '?';  // Unknown
        }

        // Enchantment (+1, -2, etc.)
        item->enchantment = (int)otmp->spe;

        // Equipped status (wielded, worn, etc.)
        item->is_equipped = (otmp->owornmask != 0);
        if (otmp->owornmask & W_WEP) {
            strcpy(item->equipped_slot, "wielded");
        } else if (otmp->owornmask & W_ARM) {
            strcpy(item->equipped_slot, "worn");
        } else if (otmp->owornmask & W_RINGL) {
            strcpy(item->equipped_slot, "left ring");
        } else if (otmp->owornmask & W_RINGR) {
            strcpy(item->equipped_slot, "right ring");
        } else if (otmp->owornmask & W_AMUL) {
            strcpy(item->equipped_slot, "amulet");
        } else if (otmp->owornmask) {
            strcpy(item->equipped_slot, "equipped");
        } else {
            item->equipped_slot[0] = '\0';
        }

        // Container check (bag, box, chest)
        item->is_container = Is_container(otmp) ? true : false;

        count++;
    }

    return count;
}

// Free allocated memory in inventory items
void nethack_free_inventory_items(InventoryItem *items, int count) {
    if (!items) return;

    for (int i = 0; i < count; i++) {
        if (items[i].name) {
            free(items[i].name);
            items[i].name = NULL;
        }
    }
}

// =============================================================================
// TERRAIN DETECTION - Get underlying terrain at player position
// =============================================================================

// Get the terrain character at player position
// Returns '>' for down stairs, '<' for up stairs, '\0' for no special terrain
NETHACK_EXPORT char ios_get_terrain_under_player(void) {
    if (!game_started || !program_state.in_moveloop) {
        return '\0';  // Not in game
    }

    extern struct you u;
    // Note: levl is a macro defined in rm.h as svl.level.locations - already available via hack.h

    // Get terrain type at player position
    schar typ = levl[u.ux][u.uy].typ;

    fprintf(stderr, "[TERRAIN] Player at (%d,%d), typ=%d\n", u.ux, u.uy, (int)typ);

    // Check for stairs
    if (typ == STAIRS) {
        // Check stairway structure to determine direction
        extern stairway *stairway_at(coordxy, coordxy);
        stairway *stw = stairway_at(u.ux, u.uy);
        if (stw) {
            char direction = stw->up ? '<' : '>';
            fprintf(stderr, "[TERRAIN] Found %s stairs at player pos\n",
                    stw->up ? "UP" : "DOWN");
            return direction;
        }
        // If no stairway found, default to down stairs
        fprintf(stderr, "[TERRAIN] Stairs found but no stairway struct, defaulting to DOWN\n");
        return '>';
    }

    // Check for other terrain types (can be extended later)
    if (typ == FOUNTAIN) return '{';
    if (typ == ALTAR) return '_';
    if (typ == THRONE) return '\\';
    if (typ == SINK) return '#';  // Sink uses same symbol as corridor

    fprintf(stderr, "[TERRAIN] No special terrain at player pos\n");
    return '\0';  // No special terrain
}

// Get player position in NetHack coordinates
// Returns coordinates via output parameters
NETHACK_EXPORT void ios_get_player_position(int *x, int *y) {
    if (!game_started || !program_state.in_moveloop) {
        if (x) *x = -1;
        if (y) *y = -1;
        return;
    }

    extern struct you u;
    if (x) *x = u.ux;
    if (y) *y = u.uy;
    fprintf(stderr, "[PLAYER_POS] NetHack player at (%d,%d)\n", u.ux, u.uy);
}

// =============================================================================
// CONTAINER SYSTEM BRIDGE FUNCTIONS
// =============================================================================
// CRITICAL: Thread safety - all functions must be called on game thread!
// CRITICAL: Buffer rotation - doname/xname use 12 rotating buffers, copy immediately!

// Check if object is a container
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
bool ios_is_container(struct obj *obj) {
    if (!obj) return false;

    // Use NetHack's native macro - defined in obj.h
    return Is_container(obj) || obj->otyp == BAG_OF_TRICKS;
}

// Get count of items in container
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
int ios_get_container_item_count(struct obj *container) {
    if (!container) return 0;
    if (!ios_is_container(container)) return 0;

    // CRITICAL FIX #1: Infinite loop protection
    #define MAX_CONTAINER_ITEMS 5000

    int count = 0;
    struct obj *item;

    // Traverse linked list via cobj->nobj chain
    // CRITICAL: Save next pointer before processing (container could be destroyed)
    for (item = container->cobj; item; item = item->nobj) {
        count++;
        // Protect against circular linked lists or corrupted data
        if (count > MAX_CONTAINER_ITEMS) {
            impossible("Container has too many items (>%d)", MAX_CONTAINER_ITEMS);
            return MAX_CONTAINER_ITEMS;
        }
    }

    return count;
}

// Check if container is locked
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
bool ios_container_is_locked(struct obj *container) {
    if (!container) return false;
    if (!ios_is_container(container)) return false;

    return container->olocked ? true : false;
}

// Check if container is trapped
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
bool ios_container_is_trapped(struct obj *container) {
    if (!container) return false;
    if (!ios_is_container(container)) return false;

    return container->otrapped ? true : false;
}

// Check if container contents are known to player
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
bool ios_container_contents_known(struct obj *container) {
    if (!container) return false;
    if (!ios_is_container(container)) return false;

    return container->cknown ? true : false;
}

// Get container contents as allocated array
// CRITICAL: Caller MUST call ios_free_container_contents() to free memory!
// CRITICAL: doname/xname buffer rotation - MUST copy strings immediately!
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
/* RETURN VALUES:
 *   -1 = Error (malloc failure, invalid parameters, allocation too large)
 *    0 = Empty container (no items)
 *   >0 = Success, number of items returned */
int ios_get_container_contents(struct obj *container, ios_item_info **items_out) {
    // Guard clauses
    if (!container) return -1;
    if (!items_out) return -1;
    if (!ios_is_container(container)) return -1;

    // Get count first
    int count = ios_get_container_item_count(container);
    if (count == 0) {
        *items_out = NULL;
        return 0;  // Empty container - not an error
    }

    // CRITICAL FIX #2: Memory allocation size limit (100MB)
    size_t alloc_size = count * sizeof(ios_item_info);
    if (alloc_size > 100 * 1024 * 1024) {
        pline("Container too large to display");
        fprintf(stderr, "[CONTAINER] ERROR: Allocation size %zu exceeds 100MB limit\n", alloc_size);
        return -1;  // Error - allocation too large
    }

    // Allocate array - use calloc for zero initialization
    ios_item_info *items = calloc(count, sizeof(ios_item_info));
    if (!items) {
        fprintf(stderr, "[CONTAINER] ERROR: Failed to allocate memory for %d items\n", count);
        return -1;  // Error - malloc failure
    }

    // Fill array by traversing container->cobj linked list
    int i = 0;
    struct obj *item;
    struct obj *nobj;  // CRITICAL: Save next pointer before processing

    for (item = container->cobj; item && i < count; item = nobj) {
        nobj = item->nobj;  // Save next pointer NOW (item could be destroyed)

        // Inventory letter (may be 0 if not in inventory)
        items[i].invlet = item->invlet ? item->invlet : '\0';

        // CRITICAL: doname/xname use rotating buffers - MUST copy immediately!
        // Get short name from xname()
        const char *short_name = xname(item);
        if (short_name) {
            strncpy(items[i].name, short_name, 255);
            items[i].name[255] = '\0';  // Ensure null termination
        }

        // Get full name from doname()
        const char *full_name = doname(item);
        if (full_name) {
            strncpy(items[i].fullname, full_name, 255);
            items[i].fullname[255] = '\0';  // Ensure null termination
        }

        // Quantity
        items[i].quantity = (int)item->quan;

        // Weight in aum
        items[i].weight = (int)item->owt;

        // Is this item also a container?
        items[i].is_container = ios_is_container(item);

        // Equipped status
        items[i].is_equipped = (item->owornmask != 0);

        // BUC status
        if (item->bknown) {
            if (item->blessed) {
                items[i].buc_status = 'B';
            } else if (item->cursed) {
                items[i].buc_status = 'C';
            } else {
                items[i].buc_status = 'U';
            }
        } else {
            items[i].buc_status = '?';  // Unknown
        }

        i++;
    }

    *items_out = items;
    return i;  // Return actual count filled
}

// Free container contents array
// Safe to call from any thread (just a free() call)
void ios_free_container_contents(ios_item_info *items, int count) {
    if (items) {
        free(items);
    }
}

// Get full item name (doname) - returns static buffer
// CRITICAL: Buffer rotates after 12 calls - copy immediately!
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
const char* ios_get_item_fullname(struct obj *obj) {
    if (!obj) return "";

    // Use NetHack's doname() - returns pointer to rotating buffer
    return doname(obj);
}

// Get short item name (xname) - returns static buffer
// CRITICAL: Buffer rotates after 12 calls - copy immediately!
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
const char* ios_get_item_shortname(struct obj *obj) {
    if (!obj) return "";

    // Use NetHack's xname() - returns pointer to rotating buffer
    return xname(obj);
}

// Get comprehensive item details
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
void ios_get_item_details(struct obj *obj, ios_item_details *out) {
    // Guard clauses
    if (!obj) return;
    if (!out) return;

    // Zero-initialize output struct
    memset(out, 0, sizeof(ios_item_details));

    // Names - CRITICAL: Copy immediately due to buffer rotation!
    const char *full = doname(obj);
    if (full) {
        strncpy(out->fullname, full, 255);
        out->fullname[255] = '\0';
    }

    const char *short_name = xname(obj);
    if (short_name) {
        strncpy(out->shortname, short_name, 255);
        out->shortname[255] = '\0';
    }

    // BUC status
    out->buc_known = obj->bknown ? true : false;
    if (obj->bknown) {
        if (obj->cursed) {
            out->buc_status = -1;
        } else if (obj->blessed) {
            out->buc_status = 1;
        } else {
            out->buc_status = 0;
        }
    } else {
        out->buc_status = 0;  // Unknown
    }

    // Numeric properties
    out->enchantment = obj->spe;
    out->charges = obj->spe;
    out->quantity = obj->quan;
    out->weight = obj->owt;

    // Type-specific properties
    // NOTE: Damage/AC/nutrition are complex calculations in NetHack
    // For now we set them to 0 and can add specific calculations later if needed
    // The full item name from doname() already includes most important info
    out->damage_dice = 0;
    out->damage_sides = 0;
    out->armor_class = 0;
    out->nutrition = 0;

    // Artifact
    if (obj->oartifact) {
        out->is_artifact = true;
        extern const char *artiname(int);
        const char *arti_name = artiname(obj->oartifact);
        if (arti_name) {
            strncpy(out->artifact_name, arti_name, 63);
            out->artifact_name[63] = '\0';
        }
    }

    // Erodeproof status
    out->is_erodeproof = obj->oerodeproof ? true : false;

    // Equipment status
    out->is_equipped = (obj->owornmask != 0);
    if (obj->owornmask & W_WEP) {
        strcpy(out->equipped_slot, "wielded");
    } else if (obj->owornmask & W_ARM) {
        strcpy(out->equipped_slot, "worn");
    } else if (obj->owornmask & W_RINGL) {
        strcpy(out->equipped_slot, "left ring");
    } else if (obj->owornmask & W_RINGR) {
        strcpy(out->equipped_slot, "right ring");
    } else if (obj->owornmask & W_AMUL) {
        strcpy(out->equipped_slot, "amulet");
    } else if (obj->owornmask & W_QUIVER) {
        strcpy(out->equipped_slot, "quiver");
    } else if (obj->owornmask) {
        strcpy(out->equipped_slot, "equipped");
    }

    // Container properties
    out->is_container = ios_is_container(obj);
    if (out->is_container) {
        out->container_item_count = ios_get_container_item_count(obj);
        out->container_locked = ios_container_is_locked(obj);
        out->container_trapped = ios_container_is_trapped(obj);
    }
}

// =============================================================================
// CONTAINER OPERATIONS - FIX #3 and FIX #4
// =============================================================================

// CRITICAL FIX #3: Get inventory item by invlet character
// Needed for Swift to convert invlet → NetHack obj* for drag-and-drop
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
NETHACK_EXPORT struct obj* ios_get_inventory_item_by_invlet(char invlet) {
    if (!game_started) return NULL;

    extern struct you u;
    for (struct obj *otmp = gi.invent; otmp; otmp = otmp->nobj) {
        if (otmp->invlet == invlet) {
            return otmp;
        }
    }
    return NULL;
}

// CRITICAL FIX #4: Bag of Holding explosion validation
// Prevents the deadly BoH→BoH combination that destroys items
/* THREAD SAFETY: Must be called from game thread only.
 * Calling from any other thread will cause crashes/corruption. */
/* WHY THIS EXISTS:
 * In NetHack, placing a Bag of Holding inside another Bag of Holding
 * causes a catastrophic explosion that destroys both bags and scatters
 * all items. This is a core game mechanic that MUST be preserved.
 * See origin/NetHack/src/pickup.c:2490-2509 for NetHack's implementation. */
bool ios_can_contain(struct obj *container, struct obj *item) {
    if (!container) return false;
    if (!item) return false;
    if (!ios_is_container(container)) return false;

    // CRITICAL: Bag of Holding in Bag of Holding = EXPLOSION
    // This is NetHack's core mechanic - do NOT bypass this check!
    if (container->otyp == BAG_OF_HOLDING && item->otyp == BAG_OF_HOLDING) {
        return false;  // Will explode - prevent insertion
    }

    // Check if item is itself a container with a BoH inside
    // This prevents indirect BoH→BoH via nested containers
    if (Is_container(item) && container->otyp == BAG_OF_HOLDING) {
        for (struct obj *o = item->cobj; o; o = o->nobj) {
            if (o->otyp == BAG_OF_HOLDING) {
                return false;  // Nested BoH would explode
            }
        }
    }

    // TODO(nethack-guardian): Add Wand of Cancellation check
    // See NetHack source: pickup.c mbag_explodes() function
    // WAN_CANCELLATION is not exported properly - need proper implementation
    // if (container->otyp == BAG_OF_HOLDING && item->otyp == WAN_CANCELLATION) {
    //     if (item->spe > 0) {
    //         return false;  // Will explode - prevent insertion
    //     }
    // }

    return true;  // Safe to contain
}

// =============================================================================
// DISCOVERIES SYSTEM - Expose NetHack's discovery tracking to iOS
// =============================================================================

#include "../NetHack/include/objclass.h"

// Get total number of object types
NETHACK_EXPORT int ios_get_num_objects(void) {
    return NUM_OBJECTS;
}

// Get object class definition by type ID
// Returns pointer to NetHack's internal objects[] array
NETHACK_EXPORT struct objclass* ios_get_object_class(int otyp) {
    // Guard clause: bounds check
    if (otyp < 0 || otyp >= NUM_OBJECTS) {
        return NULL;
    }

    // Return pointer to internal objects array
    extern struct objclass objects[];
    return &objects[otyp];
}

// Check if object type has been discovered
NETHACK_EXPORT bool ios_is_object_discovered(int otyp) {
    // Guard clause: bounds check
    if (otyp < 0 || otyp >= NUM_OBJECTS) {
        return false;
    }

    // Check discovery status from NetHack's objects array
    extern struct objclass objects[];
    return objects[otyp].oc_name_known != 0;
}

// Get object name (uses NetHack's OBJ_NAME macro)
NETHACK_EXPORT const char* ios_get_object_name(int otyp) {
    // Guard clause: bounds check
    if (otyp < 0 || otyp >= NUM_OBJECTS) {
        return NULL;
    }

    extern struct objclass objects[];
    // Use OBJ_NAME macro from objclass.h
    return OBJ_NAME(objects[otyp]);
}

// Get object description/appearance (uses NetHack's OBJ_DESCR macro)
NETHACK_EXPORT const char* ios_get_object_description(int otyp) {
    // Guard clause: bounds check
    if (otyp < 0 || otyp >= NUM_OBJECTS) {
        return NULL;
    }

    extern struct objclass objects[];
    // Use OBJ_DESCR macro from objclass.h
    return OBJ_DESCR(objects[otyp]);
}

// Get object class character
NETHACK_EXPORT signed char ios_get_object_class_char(int otyp) {
    // Guard clause: bounds check
    if (otyp < 0 || otyp >= NUM_OBJECTS) {
        return 0;
    }

    extern struct objclass objects[];
    return objects[otyp].oc_class;
}

// Check if object has been encountered by the hero
NETHACK_EXPORT bool ios_is_object_encountered(int otyp) {
    // Guard clause: bounds check
    if (otyp < 0 || otyp >= NUM_OBJECTS) {
        return false;
    }

    extern struct objclass objects[];
    return objects[otyp].oc_encountered != 0;
}

// Check if object is unique
NETHACK_EXPORT bool ios_is_object_unique(int otyp) {
    // Guard clause: bounds check
    if (otyp < 0 || otyp >= NUM_OBJECTS) {
        return false;
    }

    extern struct objclass objects[];
    return objects[otyp].oc_unique != 0;
}

// Check if object has a user-given name (via #name command)
NETHACK_EXPORT bool ios_has_user_name(int otyp) {
    // Guard clause: bounds check
    if (otyp < 0 || otyp >= NUM_OBJECTS) {
        return false;
    }

    extern struct objclass objects[];
    return objects[otyp].oc_uname != NULL;
}

// =============================================================================
// DISCOVERIES - Get discovered items using disco[] array (like vanilla)
// =============================================================================

// Buffer for discoveries JSON - sized for reasonable max discoveries
#define DISCOVERIES_JSON_BUFFER_SIZE 32768
static char discoveries_json_buffer[DISCOVERIES_JSON_BUFFER_SIZE];

// Helper: Check if object is interesting to discover (matches o_init.c:interesting_to_discover)
static bool ios_interesting_to_discover(int otyp) {
    extern struct objclass objects[];

    // User has named this object type
    if (objects[otyp].oc_uname != NULL) {
        return true;
    }

    // (name_known OR encountered) AND has randomizable description
    if ((objects[otyp].oc_name_known || objects[otyp].oc_encountered)
        && OBJ_DESCR(objects[otyp]) != NULL) {
        return true;
    }

    return false;
}

// Get discoveries as JSON using disco[] array (matches vanilla's dodiscovered())
// Returns JSON array of discovered items
NETHACK_EXPORT const char* ios_get_discoveries_json(void) {
    extern struct objclass objects[];

    // Guard: Game not running
    if (player_has_died || program_state.gameover) {
        return "[]";
    }

    int pos = 0;
    int count = 0;

    // Start JSON array
    pos += snprintf(discoveries_json_buffer + pos, DISCOVERIES_JSON_BUFFER_SIZE - pos, "[");

    // Class order from flags.inv_order (standard NetHack order)
    // We use a fixed order matching MAXOCLASSES
    for (int oclass = 1; oclass < MAXOCLASSES; oclass++) {
        // Skip certain classes that aren't discoverable
        if (oclass == COIN_CLASS || oclass == BALL_CLASS ||
            oclass == CHAIN_CLASS || oclass == ROCK_CLASS) {
            continue;
        }

        // Iterate through disco[] for this class
        // disco[] is indexed from bases[oclass] to bases[oclass+1]-1
        for (int i = svb.bases[oclass];
             i < NUM_OBJECTS && objects[i].oc_class == oclass;
             i++) {

            int dis = svd.disco[i];

            // disco[i] == 0 means no discovery at this slot
            if (dis == 0) {
                continue;
            }

            // Check if this is interesting to show
            if (!ios_interesting_to_discover(dis)) {
                continue;
            }

            // Get object info
            const char* name = OBJ_NAME(objects[dis]);
            const char* descr = OBJ_DESCR(objects[dis]);
            bool is_known = objects[dis].oc_name_known != 0;
            bool is_encountered = objects[dis].oc_encountered != 0;
            bool is_unique = objects[dis].oc_unique != 0;

            // Add comma if not first
            if (count > 0) {
                pos += snprintf(discoveries_json_buffer + pos,
                               DISCOVERIES_JSON_BUFFER_SIZE - pos, ",");
            }

            // Add JSON object
            pos += snprintf(discoveries_json_buffer + pos,
                           DISCOVERIES_JSON_BUFFER_SIZE - pos,
                           "{"
                           "\"otyp\":%d,"
                           "\"oclass\":%d,"
                           "\"name\":\"%s\","
                           "\"description\":%s%s%s,"
                           "\"is_known\":%s,"
                           "\"is_encountered\":%s,"
                           "\"is_unique\":%s"
                           "}",
                           dis,
                           oclass,
                           name ? name : "",
                           descr ? "\"" : "null",
                           descr ? descr : "",
                           descr ? "\"" : "",
                           is_known ? "true" : "false",
                           is_encountered ? "true" : "false",
                           is_unique ? "true" : "false");

            count++;

            // Safety check for buffer overflow
            if (pos >= DISCOVERIES_JSON_BUFFER_SIZE - 200) {
                break;
            }
        }
    }

    // Close JSON array
    snprintf(discoveries_json_buffer + pos, DISCOVERIES_JSON_BUFFER_SIZE - pos, "]");

    return discoveries_json_buffer;
}

// =============================================================================
// SPELL SYSTEM - Bridge functions for iOS spell casting UI
// =============================================================================

// Local constants matching spell.c
#define IOS_KEEN 20000

// Local macros to access spell data (same as spell.c)
#define ios_spellid(spell) svs.spl_book[spell].sp_id
#define ios_spellev(spell) svs.spl_book[spell].sp_lev
#define ios_spellknow(spell) svs.spl_book[spell].sp_know
#define ios_spellname(spell) OBJ_NAME(objects[ios_spellid(spell)])
#define ios_spellet(spell) ((char)((spell < 26) ? ('a' + spell) : ('A' + spell - 26)))

// Get skill type name string (mirrors spelltypemnemonic from spell.c)
static const char* ios_get_skill_type_name(int skill) {
    switch (skill) {
    case P_ATTACK_SPELL:
        return "attack";
    case P_HEALING_SPELL:
        return "healing";
    case P_DIVINATION_SPELL:
        return "divination";
    case P_ENCHANTMENT_SPELL:
        return "enchantment";
    case P_CLERIC_SPELL:
        return "clerical";
    case P_ESCAPE_SPELL:
        return "escape";
    case P_MATTER_SPELL:
        return "matter";
    default:
        return "unknown";
    }
}

// Calculate spell success rate (simplified version of percent_success from spell.c)
// This replicates the core logic without all the static function dependencies
static int ios_calculate_success_rate(int spell) {
    // Guard clause: validate spell index
    if (spell < 0 || spell >= MAXSPELL) {
        return 0;
    }
    if (ios_spellid(spell) == NO_SPELL) {
        return 0;
    }

    int chance, splcaster, special, statused;
    int difficulty;
    int skill;
    int skilltype = objects[ios_spellid(spell)].oc_skill;

    // Knights don't get metal armor penalty for clerical spells
    boolean paladin_bonus = (Role_if(PM_KNIGHT) && skilltype == P_CLERIC_SPELL);

    // Calculate intrinsic ability (splcaster)
    splcaster = gu.urole.spelbase;
    special = gu.urole.spelheal;
    statused = ACURR(gu.urole.spelstat);

    // Armor penalties
    if (uarm && is_metallic(uarm) && !paladin_bonus) {
        splcaster += (uarmc && uarmc->otyp == ROBE) ? gu.urole.spelarmr / 2
                                                    : gu.urole.spelarmr;
    } else if (uarmc && uarmc->otyp == ROBE) {
        splcaster -= gu.urole.spelarmr;
    }
    if (uarms) {
        splcaster += gu.urole.spelshld;
    }

    // Quarterstaff bonus
    if (uwep && uwep->otyp == QUARTERSTAFF) {
        splcaster -= 3;
    }

    // Metal armor penalties (if not paladin casting clerical)
    if (!paladin_bonus) {
        if (uarmh && is_metallic(uarmh)) {
            splcaster += 4;  // uarmhbon
        }
        if (uarmg && is_metallic(uarmg)) {
            splcaster += 6;  // uarmgbon
        }
        if (uarmf && is_metallic(uarmf)) {
            splcaster += 2;  // uarmfbon
        }
    }

    // Role-specific spell bonus
    if (ios_spellid(spell) == gu.urole.spelspec) {
        splcaster += gu.urole.spelsbon;
    }

    // Healing spell bonus
    if (ios_spellid(spell) == SPE_HEALING || ios_spellid(spell) == SPE_EXTRA_HEALING
        || ios_spellid(spell) == SPE_CURE_BLINDNESS
        || ios_spellid(spell) == SPE_CURE_SICKNESS
        || ios_spellid(spell) == SPE_RESTORE_ABILITY
        || ios_spellid(spell) == SPE_REMOVE_CURSE) {
        splcaster += special;
    }

    if (splcaster > 20) {
        splcaster = 20;
    }

    // Calculate learned ability based on magic stat
    chance = 11 * statused / 2;

    // Skill and difficulty calculation
    skill = P_SKILL(skilltype);
    skill = max(skill, P_UNSKILLED) - 1;  // unskilled => 0
    difficulty = (ios_spellev(spell) - 1) * 4 - ((skill * 6) + (u.ulevel / 3) + 1);

    if (difficulty > 0) {
        // Player is too low level or unskilled
        chance -= isqrt(900 * difficulty + 2000);
    } else {
        // Player is above level, diminishing returns
        int learning = 15 * -difficulty / ios_spellev(spell);
        chance += learning > 20 ? 20 : learning;
    }

    // Clamp chance
    if (chance < 0) {
        chance = 0;
    }
    if (chance > 120) {
        chance = 120;
    }

    // Heavy shield penalty
    if (uarms && weight(uarms) > (int)objects[SMALL_SHIELD].oc_weight) {
        if (ios_spellid(spell) == gu.urole.spelspec) {
            chance /= 2;
        } else {
            chance /= 4;
        }
    }

    // Combine chance with ability
    chance = chance * (20 - splcaster) / 15 - splcaster;

    // Final clamp to percentile
    if (chance > 100) {
        chance = 100;
    }
    if (chance < 0) {
        chance = 0;
    }

    return chance;
}

// Get count of known spells
NETHACK_EXPORT int ios_get_spell_count(void) {
    // Guard clause: game must be started
    if (!game_started) {
        return 0;
    }

    int count = 0;
    for (int i = 0; i < MAXSPELL; i++) {
        if (ios_spellid(i) == NO_SPELL) {
            break;  // Spells are contiguous, first empty slot means end
        }
        count++;
    }

    return count;
}

// Fill array with spell data
NETHACK_EXPORT int ios_get_spells(SpellInfo *spells, int max_spells) {
    // Guard clause: game must be started
    if (!game_started) {
        return 0;
    }
    // Guard clause: valid output array
    if (!spells) {
        return 0;
    }
    // Guard clause: reasonable max
    if (max_spells <= 0) {
        return 0;
    }

    int count = 0;
    for (int i = 0; i < MAXSPELL && count < max_spells; i++) {
        // Guard clause: check for end of spell list
        if (ios_spellid(i) == NO_SPELL) {
            break;
        }

        SpellInfo *info = &spells[count];
        int spell_otyp = ios_spellid(i);

        // Basic info
        info->index = i;
        info->letter = ios_spellet(i);

        // Spell name (safe copy)
        const char *name = ios_spellname(i);
        if (name) {
            strncpy(info->name, name, sizeof(info->name) - 1);
            info->name[sizeof(info->name) - 1] = '\0';
        } else {
            info->name[0] = '\0';
        }

        // Level and power cost
        info->level = ios_spellev(i);
        info->power_cost = info->level * 5;  // SPELL_LEV_PW macro

        // Success rate (100 - fail rate, as NetHack shows fail rate)
        info->success_rate = ios_calculate_success_rate(i);

        // Retention (percentage of KEEN remaining)
        int sp_know = ios_spellknow(i);
        if (sp_know <= 0) {
            info->retention = 0;  // Forgotten
        } else if (sp_know >= IOS_KEEN) {
            info->retention = 100;  // Full retention
        } else {
            // Calculate percentage (avoid overflow with long)
            info->retention = (int)((sp_know * 100L) / IOS_KEEN);
        }

        // Direction type from objects array
        int oc_dir = objects[spell_otyp].oc_dir;
        switch (oc_dir) {
        case NODIR:
            info->direction_type = IOS_SPELL_DIR_NODIR;
            break;
        case IMMEDIATE:
            info->direction_type = IOS_SPELL_DIR_IMMEDIATE;
            break;
        case RAY:
            info->direction_type = IOS_SPELL_DIR_RAY;
            break;
        default:
            info->direction_type = IOS_SPELL_DIR_UNKNOWN;
            break;
        }

        // Skill type name
        int skilltype = objects[spell_otyp].oc_skill;
        const char *skill_name = ios_get_skill_type_name(skilltype);
        strncpy(info->skill_type, skill_name, sizeof(info->skill_type) - 1);
        info->skill_type[sizeof(info->skill_type) - 1] = '\0';

        count++;
    }

    return count;
}

// Get success rate for a specific spell
NETHACK_EXPORT int ios_get_spell_success_rate(int spell_index) {
    // Guard clause: game must be started
    if (!game_started) {
        return -1;
    }
    // Guard clause: valid index
    if (spell_index < 0 || spell_index >= MAXSPELL) {
        return -1;
    }
    // Guard clause: spell must exist
    if (ios_spellid(spell_index) == NO_SPELL) {
        return -1;
    }

    return ios_calculate_success_rate(spell_index);
}

// Get retention for a specific spell
NETHACK_EXPORT int ios_get_spell_retention(int spell_index) {
    // Guard clause: game must be started
    if (!game_started) {
        return -1;
    }
    // Guard clause: valid index
    if (spell_index < 0 || spell_index >= MAXSPELL) {
        return -1;
    }
    // Guard clause: spell must exist
    if (ios_spellid(spell_index) == NO_SPELL) {
        return -1;
    }

    int sp_know = ios_spellknow(spell_index);
    if (sp_know <= 0) {
        return 0;
    }
    if (sp_know >= IOS_KEEN) {
        return 100;
    }

    return (int)((sp_know * 100L) / IOS_KEEN);
}

// =============================================================================
// INTRINSICS SYSTEM
// =============================================================================

// Get all player intrinsics in one call
NETHACK_EXPORT void ios_get_player_intrinsics(PlayerIntrinsics *out) {
    if (!out) return;

    // Zero out the structure
    memset(out, 0, sizeof(PlayerIntrinsics));

    // Guard: game must be started
    if (!game_started) return;

    // Resistances - use the combined macros (intrinsic OR extrinsic)
    out->fire_resistance = Fire_resistance ? true : false;
    out->cold_resistance = Cold_resistance ? true : false;
    out->sleep_resistance = Sleep_resistance ? true : false;
    out->disintegration_resistance = Disint_resistance ? true : false;
    out->shock_resistance = Shock_resistance ? true : false;
    out->poison_resistance = Poison_resistance ? true : false;
    out->drain_resistance = Drain_resistance ? true : false;
    out->magic_resistance = Antimagic ? true : false;
    out->acid_resistance = Acid_resistance ? true : false;
    out->stone_resistance = Stone_resistance ? true : false;
    out->sick_resistance = Sick_resistance ? true : false;

    // Vision abilities
    out->see_invisible = See_invisible ? true : false;
    out->telepathy = Blind_telepat ? true : false;
    out->infravision = Infravision ? true : false;
    out->warning = Warning ? true : false;
    out->searching = Searching ? true : false;

    // Movement abilities
    out->levitation = Levitation ? true : false;
    out->flying = Flying ? true : false;
    out->swimming = Swimming ? true : false;
    out->magical_breathing = Amphibious ? true : false;
    out->passes_walls = Passes_walls ? true : false;
    out->slow_digestion = Slow_digestion ? true : false;
    out->regeneration = Regeneration ? true : false;
    out->teleportation = Teleportation ? true : false;
    out->teleport_control = Teleport_control ? true : false;
    out->polymorph = Polymorph ? true : false;
    out->polymorph_control = Polymorph_control ? true : false;

    // Combat abilities
    out->stealth = Stealth ? true : false;
    out->aggravate_monster = Aggravate_monster ? true : false;
    out->conflict = Conflict ? true : false;
    out->protection = Protection ? true : false;
    out->reflection = Reflecting ? true : false;
    out->free_action = Free_action ? true : false;

    // Status conditions
    out->hallucinating = Hallucination ? true : false;
    out->confused = Confusion ? true : false;
    out->stunned = Stunned ? true : false;
    out->blinded = Blind ? true : false;
    out->deaf = Deaf ? true : false;
    out->sick = Sick ? true : false;
    out->stoned = Stoned ? true : false;
    out->strangled = Strangled ? true : false;
    out->slimed = Slimed ? true : false;
    out->wounded_legs = Wounded_legs ? true : false;
    out->fumbling = Fumbling ? true : false;
}

// Individual intrinsic checks
NETHACK_EXPORT bool ios_has_fire_resistance(void) {
    if (!game_started) return false;
    return Fire_resistance ? true : false;
}

NETHACK_EXPORT bool ios_has_cold_resistance(void) {
    if (!game_started) return false;
    return Cold_resistance ? true : false;
}

NETHACK_EXPORT bool ios_has_poison_resistance(void) {
    if (!game_started) return false;
    return Poison_resistance ? true : false;
}

NETHACK_EXPORT bool ios_has_see_invisible(void) {
    if (!game_started) return false;
    return See_invisible ? true : false;
}

NETHACK_EXPORT bool ios_has_telepathy(void) {
    if (!game_started) return false;
    return Blind_telepat ? true : false;
}

// =============================================================================
// MONSTER INFO SYSTEM
// =============================================================================

// Helper: Fill MonsterInfo from a monst struct
static void fill_monster_info(struct monst *mtmp, MonsterInfo *info) {
    if (!mtmp || !info) return;

    memset(info, 0, sizeof(MonsterInfo));

    info->x = mtmp->mx;
    info->y = mtmp->my;

    // Get monster symbol
    if (mtmp->data) {
        info->symbol = def_monsyms[(int)mtmp->data->mlet].sym;
    } else {
        info->symbol = '?';
    }

    // Get monster name
    if (mtmp->data && mtmp->data->pmnames[NEUTRAL]) {
        strncpy(info->name, mtmp->data->pmnames[NEUTRAL], 63);
        info->name[63] = '\0';
    } else {
        strcpy(info->name, "unknown");
    }

    // HP info - only reveal if we can see detailed info (pets, etc.)
    info->current_hp = mtmp->mhp;
    info->max_hp = mtmp->mhpmax;
    info->level = mtmp->m_lev;

    // Status flags
    info->is_pet = (mtmp->mtame > 0);
    info->is_peaceful = (mtmp->mpeaceful && !mtmp->mtame);
    info->is_hostile = (!mtmp->mpeaceful && !mtmp->mtame);
    info->is_invisible = (mtmp->minvis != 0);
    info->is_fleeing = (mtmp->mflee != 0);
    info->is_sleeping = (mtmp->msleeping != 0);
    info->is_stunned = (mtmp->mstun != 0);
    info->is_confused = (mtmp->mconf != 0);
}

// Get count of visible monsters
NETHACK_EXPORT int ios_get_visible_monster_count(void) {
    if (!game_started) return 0;

    int count = 0;
    struct monst *mtmp;

    for (mtmp = fmon; mtmp; mtmp = mtmp->nmon) {
        if (DEADMONSTER(mtmp)) continue;
        // Check if monster is visible to player
        if (canseemon(mtmp) || sensemon(mtmp)) {
            count++;
        }
    }

    return count;
}

// Get info for all visible monsters
NETHACK_EXPORT int ios_get_visible_monsters(MonsterInfo *monsters, int max_monsters) {
    if (!game_started || !monsters || max_monsters <= 0) return 0;

    int count = 0;
    struct monst *mtmp;

    for (mtmp = fmon; mtmp && count < max_monsters; mtmp = mtmp->nmon) {
        if (DEADMONSTER(mtmp)) continue;
        // Check if monster is visible to player
        if (canseemon(mtmp) || sensemon(mtmp)) {
            fill_monster_info(mtmp, &monsters[count]);
            count++;
        }
    }

    return count;
}

// Get info for monster at specific coordinates
NETHACK_EXPORT bool ios_get_monster_at(int x, int y, MonsterInfo *out) {
    if (!game_started || !out) return false;

    struct monst *mtmp = m_at(x, y);
    if (!mtmp || DEADMONSTER(mtmp)) {
        return false;
    }

    fill_monster_info(mtmp, out);
    return true;
}

// =============================================================================
// SKILL/ENHANCE SYSTEM IMPLEMENTATION
// =============================================================================

// Helper: Calculate slots required for next advancement
// Based on weapon.c slots_required() - static there, we replicate logic
static int ios_skill_slots_required(int skill) {
    extern struct you u;
    int level = P_SKILL(skill);

    // Weapon skills and two-weapon combat use level directly
    if (skill <= P_LAST_WEAPON || skill == P_TWO_WEAPON_COMBAT) {
        return level;
    }

    // Fighting skills use (level + 1) / 2
    return (level + 1) / 2;
}

// Helper: Check if skill could advance with more slots (has practice, needs slots)
// Based on weapon.c could_advance() - static there, we replicate logic
static int ios_skill_could_advance(int skill) {
    extern struct you u;

    // Restricted skills cannot advance
    if (P_RESTRICTED(skill)) {
        return 0;
    }
    // Already at max
    if (P_SKILL(skill) >= P_MAX_SKILL(skill)) {
        return 0;
    }
    // Hit global limit
    if (u.skills_advanced >= P_SKILL_LIMIT) {
        return 0;
    }
    // Has enough practice points?
    return ((int)P_ADVANCE(skill) >= practice_needed_to_advance(P_SKILL(skill))) ? 1 : 0;
}

// Helper: Check if skill is peaked (at max, with enough practice for next if possible)
// Based on weapon.c peaked_skill() - static there, we replicate logic
static int ios_skill_peaked(int skill) {
    extern struct you u;

    if (P_RESTRICTED(skill)) {
        return 0;
    }

    // At max level AND has practice for (impossible) next level
    return (P_SKILL(skill) >= P_MAX_SKILL(skill)
            && ((int)P_ADVANCE(skill) >= practice_needed_to_advance(P_SKILL(skill)))) ? 1 : 0;
}

// Helper: Determine skill category
static int ios_skill_get_category(int skill) {
    if (skill >= P_FIRST_WEAPON && skill <= P_LAST_WEAPON) {
        return IOS_SKILL_CATEGORY_WEAPON;
    }
    if (skill >= P_FIRST_SPELL && skill <= P_LAST_SPELL) {
        return IOS_SKILL_CATEGORY_SPELL;
    }
    // P_BARE_HANDED_COMBAT, P_TWO_WEAPON_COMBAT, P_RIDING
    return IOS_SKILL_CATEGORY_FIGHTING;
}

// Helper: Fill ios_skill_info_t from skill ID
static void ios_fill_skill_info(int skill_id, ios_skill_info_t *out) {
    extern struct you u;

    memset(out, 0, sizeof(ios_skill_info_t));

    out->skill_id = skill_id;

    // Get skill name from NetHack
    const char *name = skill_name(skill_id);
    if (name) {
        strncpy(out->name, name, sizeof(out->name) - 1);
        out->name[sizeof(out->name) - 1] = '\0';
    }

    out->current_level = P_SKILL(skill_id);
    out->max_level = P_MAX_SKILL(skill_id);
    out->practice_points = P_ADVANCE(skill_id);
    out->points_needed = practice_needed_to_advance(P_SKILL(skill_id));
    out->can_advance = can_advance(skill_id, FALSE) ? 1 : 0;
    out->could_advance = ios_skill_could_advance(skill_id);
    out->is_peaked = ios_skill_peaked(skill_id);
    out->slots_required = ios_skill_slots_required(skill_id);
    out->category = ios_skill_get_category(skill_id);

    // Get level name
    const char *level_name = ios_get_skill_level_name(out->current_level);
    if (level_name) {
        strncpy(out->level_name, level_name, sizeof(out->level_name) - 1);
        out->level_name[sizeof(out->level_name) - 1] = '\0';
    }
}

// Get total available skill slots
NETHACK_EXPORT int ios_get_available_skill_slots(void) {
    if (!game_started) {
        return 0;
    }

    extern struct you u;
    return u.weapon_slots;
}

// Get count of non-restricted skills
NETHACK_EXPORT int ios_get_skill_count(void) {
    if (!game_started) {
        return 0;
    }

    extern struct you u;
    int count = 0;

    for (int i = 0; i < P_NUM_SKILLS; i++) {
        if (!P_RESTRICTED(i)) {
            count++;
        }
    }

    return count;
}

// Get skill info at index (iterates through non-restricted skills only)
NETHACK_EXPORT int ios_get_skill_info(int index, ios_skill_info_t *out) {
    if (!game_started) {
        return 0;
    }
    if (!out) {
        return 0;
    }
    if (index < 0) {
        return 0;
    }

    extern struct you u;
    int current_index = 0;

    for (int i = 0; i < P_NUM_SKILLS; i++) {
        if (P_RESTRICTED(i)) {
            continue;
        }

        if (current_index == index) {
            ios_fill_skill_info(i, out);
            return 1;
        }

        current_index++;
    }

    return 0;  // Index out of bounds
}

// Get all non-restricted skills in one call
NETHACK_EXPORT int ios_get_all_skills(ios_skill_info_t *out, int *count) {
    if (!game_started) {
        if (count) *count = 0;
        return 0;
    }
    if (!out) {
        if (count) *count = 0;
        return 0;
    }

    extern struct you u;
    int filled = 0;

    for (int i = 0; i < P_NUM_SKILLS; i++) {
        if (P_RESTRICTED(i)) {
            continue;
        }

        ios_fill_skill_info(i, &out[filled]);
        filled++;
    }

    if (count) {
        *count = filled;
    }

    return filled;
}

// Get skill info by skill ID (0-37)
NETHACK_EXPORT int ios_get_skill_by_id(int skill_id, ios_skill_info_t *out) {
    if (!game_started) {
        return 0;
    }
    if (!out) {
        return 0;
    }
    if (skill_id < 0 || skill_id >= P_NUM_SKILLS) {
        return 0;
    }

    extern struct you u;

    // Can query even restricted skills by ID
    ios_fill_skill_info(skill_id, out);
    return 1;
}

// Advance a skill (spend skill slot to increase level)
NETHACK_EXPORT int ios_advance_skill(int skill_id) {
    if (!game_started) {
        return 0;
    }
    if (skill_id < 0 || skill_id >= P_NUM_SKILLS) {
        return 0;
    }

    extern struct you u;

    // Check if can actually advance
    if (!can_advance(skill_id, FALSE)) {
        return 0;
    }

    // Calculate slots required
    int slots_needed = ios_skill_slots_required(skill_id);
    if (u.weapon_slots < slots_needed) {
        return 0;  // Not enough slots
    }

    // Perform the advancement (replicating skill_advance from weapon.c)
    u.weapon_slots -= slots_needed;
    P_SKILL(skill_id)++;
    u.skill_record[u.skills_advanced++] = skill_id;

    // Log the advancement
    fprintf(stderr, "[SKILL] Advanced %s to level %d (slots remaining: %d)\n",
            skill_name(skill_id), P_SKILL(skill_id), u.weapon_slots);

    return 1;
}

// Get count of skills that can be advanced RIGHT NOW
NETHACK_EXPORT int ios_get_advanceable_skill_count(void) {
    if (!game_started) {
        return 0;
    }

    extern struct you u;
    int count = 0;

    for (int i = 0; i < P_NUM_SKILLS; i++) {
        if (can_advance(i, FALSE)) {
            count++;
        }
    }

    return count;
}

// Get skill level name string
NETHACK_EXPORT const char* ios_get_skill_level_name(int level) {
    switch (level) {
        case 0: return "Restricted";
        case 1: return "Unskilled";
        case 2: return "Basic";
        case 3: return "Skilled";
        case 4: return "Expert";
        case 5: return "Master";
        case 6: return "Grand Master";
        default: return "Unknown";
    }
}

// Check if player would escape the dungeon (needs escape warning)
// Returns: 0 = normal stairs, 1 = escape warning needed (level 1, no amulet)
// Logic from doup() in origin/NetHack/src/do.c lines 1330-1335
NETHACK_EXPORT int ios_check_escape_warning(void) {
    fprintf(stderr, "[ESCAPE_CHECK] game_started=%d\n", game_started);
    if (!game_started) return 0;

    // Check 1: Is player on dungeon level 1?
    // ledger_no(&u.uz) == 1 means first level of main dungeon
    int ledger = ledger_no(&u.uz);
    fprintf(stderr, "[ESCAPE_CHECK] ledger_no=%d (need 1)\n", ledger);
    if (ledger != 1) return 0;

    // Check 2: Does player NOT have the Amulet of Yendor?
    // With amulet, player can leave and return
    fprintf(stderr, "[ESCAPE_CHECK] has_amulet=%d (need 0)\n", u.uhave.amulet);
    if (u.uhave.amulet) return 0;

    // Check 3: Is player standing on an upstairs?
    stairway *stway = stairway_at(u.ux, u.uy);
    fprintf(stderr, "[ESCAPE_CHECK] stway=%p, up=%d at (%d,%d)\n",
            (void*)stway, stway ? stway->up : -1, u.ux, u.uy);
    if (!stway || !stway->up) return 0;

    // All conditions met: player would escape without the amulet
    fprintf(stderr, "[ESCAPE_CHECK] ✅ WARNING NEEDED!\n");
    return 1;
}

// =============================================================================
// AUTOPICKUP SYSTEM (user preference control from Swift)
// =============================================================================

// Set autopickup enabled state
// enabled: 1 = on, 0 = off
NETHACK_EXPORT void ios_set_autopickup_enabled(int enabled) {
    flags.pickup = enabled ? TRUE : FALSE;
    fprintf(stderr, "[AUTOPICKUP] Set flags.pickup = %s\n", enabled ? "TRUE" : "FALSE");
}

// Set autopickup item types
// types: String of object class symbols (e.g., "$\"?!/=(+" for gold, amulets, scrolls, etc.)
// Empty string = pickup all types (NetHack convention)
// CRITICAL: Must convert symbol chars to class indices!
// NetHack's oc_to_str() expects class indices (0-17), not symbol chars (ASCII 33-126)
NETHACK_EXPORT void ios_set_autopickup_types(const char* types) {
    if (!types || types[0] == '\0') {
        flags.pickup_types[0] = '\0';
        fprintf(stderr, "[AUTOPICKUP] Set pickup_types = (empty = all types)\n");
        return;
    }

    // Convert symbol characters to class indices using def_char_to_objclass()
    // This is what NetHack's options.c does when parsing pickup_types option
    extern int def_char_to_objclass(char c);

    int num = 0;
    const char* op = types;
    while (*op && num < MAXOCLASSES - 1) {
        int oc_sym = def_char_to_objclass(*op);
        // Only add valid class indices (def_char_to_objclass returns MAXOCLASSES for invalid)
        if (oc_sym != MAXOCLASSES) {
            flags.pickup_types[num++] = (char)oc_sym;
        }
        op++;
    }
    flags.pickup_types[num] = '\0';

    fprintf(stderr, "[AUTOPICKUP] Set pickup_types: symbols=\"%s\" -> %d class indices\n", types, num);
}

// Get current autopickup types string (for debugging)
NETHACK_EXPORT const char* ios_get_autopickup_types(void) {
    return flags.pickup_types;
}

// Check if autopickup is enabled
NETHACK_EXPORT int ios_is_autopickup_enabled(void) {
    return flags.pickup ? 1 : 0;
}

// =============================================================================
// CHRONICLE / GAMELOG SYSTEM (hero's journey log)
// =============================================================================

// Get count of gamelog entries
NETHACK_EXPORT int ios_gamelog_count(void) {
    if (!game_started) return 0;

    int count = 0;
    struct gamelog_line *entry = gg.gamelog;
    while (entry) {
        count++;
        entry = entry->next;
    }
    return count;
}

// Get gamelog entry by index (0 = oldest)
// Returns 1 if found, 0 if not
// flags uses LL_* constants from global.h:
//   LL_WISH=0x0001, LL_ACHIEVE=0x0002, LL_UMONST=0x0004, LL_DIVINEGIFT=0x0008
//   LL_LIFESAVE=0x0010, LL_CONDUCT=0x0020, LL_ARTIFACT=0x0040, LL_GENOCIDE=0x0080
//   LL_KILLEDPET=0x0100, LL_ALIGNMENT=0x0200, LL_MINORAC=0x1000, LL_SPOILER=0x2000
NETHACK_EXPORT int ios_gamelog_entry(int idx, long *turn, long *flags_out, const char **text) {
    if (!game_started) return 0;
    if (!turn || !flags_out || !text) return 0;

    struct gamelog_line *entry = gg.gamelog;
    for (int i = 0; i < idx && entry; i++) {
        entry = entry->next;
    }

    if (!entry) return 0;

    *turn = entry->turn;
    *flags_out = entry->flags;
    *text = entry->text ? entry->text : "";
    return 1;
}

// Get gamelog entries as JSON array (for efficient bulk transfer)
// Returns pointer to static buffer - valid until next call
// Filters out LL_SPOILER entries (hidden from player during game)
#define GAMELOG_JSON_BUFFER_SIZE 65536
static char gamelog_json_buffer[GAMELOG_JSON_BUFFER_SIZE];

NETHACK_EXPORT const char* ios_gamelog_json(void) {
    if (!game_started) {
        strcpy(gamelog_json_buffer, "[]");
        return gamelog_json_buffer;
    }

    int pos = 0;
    pos += snprintf(gamelog_json_buffer + pos, GAMELOG_JSON_BUFFER_SIZE - pos, "[");

    int first = 1;
    struct gamelog_line *entry = gg.gamelog;
    while (entry && pos < GAMELOG_JSON_BUFFER_SIZE - 512) {
        // Skip spoiler entries (hidden from #chronicle during game)
        if (entry->flags & LL_SPOILER) {
            entry = entry->next;
            continue;
        }

        if (!first) {
            pos += snprintf(gamelog_json_buffer + pos, GAMELOG_JSON_BUFFER_SIZE - pos, ",");
        }
        first = 0;

        // Escape text for JSON
        char escaped_text[512];
        int j = 0;
        const char *src = entry->text ? entry->text : "";
        while (*src && j < 500) {
            if (*src == '"' || *src == '\\') {
                escaped_text[j++] = '\\';
            }
            escaped_text[j++] = *src++;
        }
        escaped_text[j] = '\0';

        pos += snprintf(gamelog_json_buffer + pos, GAMELOG_JSON_BUFFER_SIZE - pos,
            "{\"turn\":%ld,\"flags\":%ld,\"text\":\"%s\"}",
            entry->turn, entry->flags, escaped_text);

        entry = entry->next;
    }

    snprintf(gamelog_json_buffer + pos, GAMELOG_JSON_BUFFER_SIZE - pos, "]");
    return gamelog_json_buffer;
}

// =============================================================================
// CONDUCT SYSTEM (voluntary challenges tracking)
// =============================================================================

// Get conduct data as JSON
// Returns all conduct fields from u.uconduct and u.uroleplay
#define CONDUCT_JSON_BUFFER_SIZE 2048
static char conduct_json_buffer[CONDUCT_JSON_BUFFER_SIZE];

NETHACK_EXPORT const char* ios_get_conduct_json(void) {
    if (!game_started) {
        strcpy(conduct_json_buffer, "{}");
        return conduct_json_buffer;
    }

    // Check if Sokoban has been entered (for sokocheat display)
    extern boolean sokoban_in_play(void);
    int sokoban_entered = sokoban_in_play() ? 1 : 0;

    // Get genocide count
    extern int num_genocides(void);
    int ngenocided = num_genocides();

    snprintf(conduct_json_buffer, CONDUCT_JSON_BUFFER_SIZE,
        "{"
        "\"unvegetarian\":%ld,"
        "\"unvegan\":%ld,"
        "\"food\":%ld,"
        "\"gnostic\":%ld,"
        "\"weaphit\":%ld,"
        "\"killer\":%ld,"
        "\"literate\":%ld,"
        "\"polypiles\":%ld,"
        "\"polyselfs\":%ld,"
        "\"wishes\":%ld,"
        "\"wisharti\":%ld,"
        "\"sokocheat\":%ld,"
        "\"pets\":%ld,"
        "\"blind\":%d,"
        "\"deaf\":%d,"
        "\"nudist\":%d,"
        "\"pauper\":%d,"
        "\"sokoban_entered\":%d,"
        "\"genocides\":%d,"
        "\"turns\":%ld"
        "}",
        u.uconduct.unvegetarian,
        u.uconduct.unvegan,
        u.uconduct.food,
        u.uconduct.gnostic,
        u.uconduct.weaphit,
        u.uconduct.killer,
        u.uconduct.literate,
        u.uconduct.polypiles,
        u.uconduct.polyselfs,
        u.uconduct.wishes,
        u.uconduct.wisharti,
        u.uconduct.sokocheat,
        u.uconduct.pets,
        u.uroleplay.blind ? 1 : 0,
        u.uroleplay.deaf ? 1 : 0,
        u.uroleplay.nudist ? 1 : 0,
        u.uroleplay.pauper ? 1 : 0,
        sokoban_entered,
        ngenocided,
        svm.moves
    );

    return conduct_json_buffer;
}
