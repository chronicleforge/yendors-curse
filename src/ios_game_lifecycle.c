/*
 * ios_game_lifecycle.c
 *
 * Game lifecycle management for NetHack iOS port
 * Implements proper shutdown, memory cleanup, and reinitialization
 *
 * Created: 2025-10-02
 * Purpose: Enable multiple game sessions in same process without corruption
 *
 * ARCHITECTURE:
 * NetHack was designed for one-process-per-game:
 *   Game → freedynamicdata() → dlb_cleanup() → l_nhcore_done() → exit(0)
 *
 * iOS requires multiple games in same process:
 *   Game 1 → shutdown → wipe → reinit → Game 2 → shutdown → wipe → reinit → Game 3...
 *
 * This file implements the shutdown/wipe/reinit cycle following NetHack's own design.
 */

#include "nethack_export.h"  // Symbol visibility control
#include "hack.h"
#include "dlb.h"
#include "ios_game_lifecycle.h"
#include <stdio.h>
#include <string.h>

/* External functions from NetHack core */
extern void freedynamicdata(void);       /* end.c - Free ALL game objects */
extern void l_nhcore_done(void);         /* nhlua.c - Shutdown Lua state */
extern void l_nhcore_init(void);         /* nhlua.c - Initialize Lua state */
extern void nh_restart(void);            /* nethack_memory.c - Memset heap */
extern void ios_reset_all_static_state(void); /* ios_winprocs.c - Reset iOS state */

/* NOTE: dlb_init() and dlb_cleanup() are macros that expand to nothing
 * because DLB (data library) is disabled in our NetHack build.
 * They are defined in dlb.h as:
 *   #define dlb_init()
 *   #define dlb_cleanup()
 * We can still call them - they just do nothing.
 */

/* External program state */
extern struct sinfo program_state;

/*
 * ios_shutdown_game - Orderly NetHack shutdown
 *
 * This function performs the EXACT same sequence that NetHack does in really_done()
 * before calling exit(0). We just don't exit the process.
 *
 * CRITICAL ORDER:
 * 1. freedynamicdata() - Free ALL game objects (inventory, dungeon, monsters, etc.)
 * 2. dlb_cleanup() - Close all data file handles
 * 3. l_nhcore_done() - Shutdown Lua interpreter
 * 4. Reset program_state flags - Clean slate
 *
 * After this, NO NetHack structures are active. Memory wipe is now safe.
 */
NETHACK_EXPORT void ios_shutdown_game(void) {
    fprintf(stderr, "\n========================================\n");
    fprintf(stderr, "[LIFECYCLE] ios_shutdown_game() - Orderly NetHack shutdown\n");
    fprintf(stderr, "========================================\n");

    /* Step 1: Free ALL dynamic game data */
    fprintf(stderr, "[LIFECYCLE] Step 1: freedynamicdata() - Freeing ALL game objects...\n");

    /* Check if freedynamicdata was already called (e.g., via death/longjmp) */
    extern int ios_freedynamicdata_done;
    if (ios_freedynamicdata_done) {
        fprintf(stderr, "[LIFECYCLE]   ⊘ Already cleaned up via death path - skipping freedynamicdata\n");
    } else if (program_state.gameover || program_state.something_worth_saving) {
        freedynamicdata();
        fprintf(stderr, "[LIFECYCLE]   ✓ Game objects freed (inventory, dungeon, monsters, etc.)\n");
    } else {
        fprintf(stderr, "[LIFECYCLE]   ⊘ No game to clean up (never started)\n");
    }

    /* Step 2: Close data files */
    fprintf(stderr, "[LIFECYCLE] Step 2: dlb_cleanup() - Closing data files...\n");
    dlb_cleanup();
    fprintf(stderr, "[LIFECYCLE]   ✓ Data files closed\n");

    /* Step 3: Shutdown Lua interpreter */
    fprintf(stderr, "[LIFECYCLE] Step 3: l_nhcore_done() - Shutting down Lua...\n");
    l_nhcore_done();
    fprintf(stderr, "[LIFECYCLE]   ✓ Lua state destroyed\n");

    /* Step 3.5: Finish status system (CRITICAL before memory wipe!) */
    fprintf(stderr, "[LIFECYCLE] Step 3.5: status_finish() - Freeing status buffers...\n");
    if (VIA_WINDOWPORT()) {
        extern void status_finish(void);
        status_finish();
        fprintf(stderr, "[LIFECYCLE]   ✓ Status buffers freed\n");
    } else {
        fprintf(stderr, "[LIFECYCLE]   ⊘ Not using windowport, skipping status_finish()\n");
    }

    /* Step 4: Reset program state flags */
    fprintf(stderr, "[LIFECYCLE] Step 4: Resetting program_state flags...\n");
    program_state.gameover = 0;
    program_state.something_worth_saving = 0;
    program_state.in_moveloop = 0;
    program_state.exiting = 0;
    fprintf(stderr, "[LIFECYCLE]   ✓ Program state reset\n");

    fprintf(stderr, "[LIFECYCLE] ✓ Shutdown complete - All structures freed, ready for memory wipe\n");
    fprintf(stderr, "========================================\n\n");
}

/*
 * ios_wipe_memory - Zone allocator memory wipe
 *
 * Calls nh_restart() to memset the entire static heap to zero.
 *
 * CRITICAL: This is ONLY safe AFTER ios_shutdown_game() has freed all structures.
 * Calling this while game objects are active will cause crashes!
 *
 * Why we need this:
 * - Prevents stale pointers from old game
 * - Ensures clean memory state for new game
 * - Fixes "second game movement broken" bug
 */
NETHACK_EXPORT void ios_wipe_memory(void) {
    fprintf(stderr, "\n========================================\n");
    fprintf(stderr, "[LIFECYCLE] ios_wipe_memory() - Zone allocator reset\n");
    fprintf(stderr, "========================================\n");

    fprintf(stderr, "[LIFECYCLE] Calling nh_restart() - memset(heap, 0, size)...\n");
    nh_restart();
    fprintf(stderr, "[LIFECYCLE] ✓ Static heap wiped to zero\n");
    fprintf(stderr, "[LIFECYCLE] ✓ All pointers invalidated, ready for reinit\n");
    fprintf(stderr, "========================================\n\n");
}

/*
 * ios_reinit_subsystems - Re-initialize NetHack subsystems
 *
 * Re-initializes all subsystems in the EXACT order that NetHack uses
 * during initial startup in newgame().
 *
 * CRITICAL ORDER:
 * 0. ios_init_file_prefixes() - Re-initialize file paths (CRITICAL after dylib reload!)
 * 1. dlb_init() - Re-open data files
 * 2. l_nhcore_init() - Create new Lua state
 * 3. ios_reset_all_static_state() - Reset iOS bridge state
 *
 * After this, the system is ready for normal game start:
 * nethack_real_init() → nethack_real_newgame() → nethack_start_new_game()
 */
NETHACK_EXPORT void ios_reinit_subsystems(void) {
    fprintf(stderr, "\n========================================\n");
    fprintf(stderr, "[LIFECYCLE] ios_reinit_subsystems() - Reinitializing subsystems\n");
    fprintf(stderr, "========================================\n");

    /* Step 0: Re-initialize file prefixes (CRITICAL after dylib reload!) */
    fprintf(stderr, "[LIFECYCLE] Step 0: ios_init_file_prefixes() - Setting up iOS paths...\n");
    extern void ios_init_file_prefixes(void);
    ios_init_file_prefixes();
    fprintf(stderr, "[LIFECYCLE]   ✓ File prefixes initialized (DATAPREFIX, SAVEDIR, etc.)\n\n");

    /* Step 1: Re-initialize data file library */
    fprintf(stderr, "[LIFECYCLE] Step 1: dlb_init() - Re-opening data files...\n");
    dlb_init();
    fprintf(stderr, "[LIFECYCLE]   ✓ Data files reopened\n");

    /* Step 2: Create new Lua state */
    fprintf(stderr, "[LIFECYCLE] Step 2: l_nhcore_init() - Creating Lua state...\n");
    l_nhcore_init();
    fprintf(stderr, "[LIFECYCLE]   ✓ Lua interpreter ready\n");

    /* Step 2.25: Re-initialize status system */
    fprintf(stderr, "[LIFECYCLE] Step 2.25: status_initialize() - Allocating status buffers...\n");
    if (VIA_WINDOWPORT()) {
        extern void status_initialize(boolean);
        status_initialize(FALSE);  /* FALSE = full init, not reassessment */
        fprintf(stderr, "[LIFECYCLE]   ✓ Status system initialized (buffers allocated)\n");
    } else {
        fprintf(stderr, "[LIFECYCLE]   ⊘ Not using windowport, skipping status_initialize()\n");
    }

    /* Step 2.5: Set boulder symbol override to '0' */
    fprintf(stderr, "[LIFECYCLE] Step 2.5: Setting boulder symbol override to '0'...\n");
    go.ov_primary_syms[SYM_BOULDER + SYM_OFF_X] = '0';
    go.ov_rogue_syms[SYM_BOULDER + SYM_OFF_X] = '0';
    fprintf(stderr, "[LIFECYCLE]   ✓ Boulder symbol set to '0' (instead of default backtick)\n");

    /* Step 3: Reset iOS bridge static state */
    fprintf(stderr, "[LIFECYCLE] Step 3: ios_reset_all_static_state() - Resetting iOS state...\n");
    ios_reset_all_static_state();
    fprintf(stderr, "[LIFECYCLE]   ✓ iOS bridge state reset (menus, input queue, etc.)\n");

    /* Step 3.5: CRITICAL - Reset NetHack's gameover flag */
    /* Without this, ios_is_player_dead() returns true for new games! */
    fprintf(stderr, "[LIFECYCLE] Step 3.5: Resetting program_state.gameover...\n");
    extern struct sinfo program_state;
    program_state.gameover = 0;
    fprintf(stderr, "[LIFECYCLE]   ✓ program_state.gameover reset to 0\n");

    /* Step 4: Reset death cleanup flag for next game */
    extern int ios_freedynamicdata_done;
    ios_freedynamicdata_done = 0;
    fprintf(stderr, "[LIFECYCLE]   ✓ Death cleanup flag reset\n");

    fprintf(stderr, "[LIFECYCLE] ✓ Reinitialization complete - Ready for new game\n");
    fprintf(stderr, "========================================\n\n");
}
