/*
 * ios_dylib_lifecycle.c
 *
 * UNIFIED DYLIB LIFECYCLE MANAGEMENT
 *
 * This is the SINGLE SOURCE OF TRUTH for dylib initialization and shutdown.
 * All paths (NEW GAME, CONTINUE CHARACTER) MUST use these functions.
 *
 * Design Philosophy:
 * - ONE function for init: ios_full_dylib_init()
 * - ONE function for shutdown: ios_full_dylib_shutdown()
 * - IDENTICAL flow for both NEW and CONTINUE paths
 * - FAIL FAST with assertions if called out of order
 *
 * Author: Root Cause Analysis Enforcer
 * Date: 2025-10-19
 */

#include "nethack_export.h"  // Symbol visibility control
#include "hack.h"
#include "dlb.h"
#include <stdio.h>
#include <string.h>

/* ========================================================================
 * LIFECYCLE STATE TRACKING
 * ======================================================================== */

static int full_init_called = 0;

/* ========================================================================
 * EXTERNAL FUNCTIONS
 * ======================================================================== */

// NetHack core
extern void early_init(int argc, char **argv);
extern void status_initialize(boolean);
extern void status_finish(void);
extern void freedynamicdata(void);
// dlb_cleanup() is a macro, not a function - no extern needed

// iOS bridge
extern void ios_init_savedir(void);
extern void ios_init_file_prefixes(void);
extern void ios_reset_all_static_state(void);

// Lua - declarations from extern.h
extern void l_nhcore_init(void);  // Returns void per extern.h:2066
extern void l_nhcore_done(void);

/* ========================================================================
 * UNIFIED DYLIB INITIALIZATION
 * ======================================================================== */

/**
 * CRITICAL: This function is the ONLY place where dylib initialization happens.
 *
 * Call Order (MANDATORY):
 * 1. ios_early_init()           - Zero globals, set up gs.subrooms, early_init()
 * 2. ios_init_file_prefixes()   - Set iOS file paths (BEFORE dlb_init!)
 * 3. dlb_init()                 - Initialize data file system
 * 4. l_nhcore_init()            - Initialize Lua scripting
 * 5. REMOVED: status_initialize() - MOVED to game initialization!
 *    (Requires window system to be initialized first - see ios_newgame.c and ios_save_integration.c)
 * 6. ios_reset_all_static_state() - Reset iOS bridge state
 * 7. Boulder symbol override    - Fix boulder display
 *
 * This function is called:
 * - On first dylib load (NetHackBridge.ensureDylibLoaded)
 * - After dylib reload (not currently, but future-proof)
 *
 * MUST NOT be called twice without ios_full_dylib_shutdown() in between!
 */
NETHACK_EXPORT void ios_full_dylib_init(void)
{
    fprintf(stderr, "\n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "[DYLIB_LIFECYCLE] FULL DYLIB INITIALIZATION\n");
    fprintf(stderr, "========================================\n");

    // ASSERTION: Should only be called once per dylib load
    if (full_init_called) {
        panic("ios_full_dylib_init() called twice - architecture bug!");
    }
    full_init_called = 1;

    // Step 1: Early init (gs.subrooms, early_init(), ios_init_savedir())
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 1: ios_early_init()...\n");
    extern void ios_early_init(void);
    ios_early_init();
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ Globals zeroed, gs.subrooms set, early_init() done\n");

    // Step 2: File prefixes (iOS paths) - CRITICAL: Before dlb_init()!
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 2: ios_init_file_prefixes()...\n");
    ios_init_file_prefixes();
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ iOS file paths configured\n");

    // Step 3: DLB init (data files) - dlb_init() is a macro that expands to nothing (DLB disabled)
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 3: dlb_init()...\n");
    dlb_init();  // Expands to nothing, but kept for API consistency
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ Data file system initialized (DLB disabled)\n");

    // Step 4: Lua init
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 4: l_nhcore_init()...\n");
    l_nhcore_init();  // void return, no error checking needed
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ Lua scripting initialized\n");

    // Step 5: REMOVED - status_initialize() moved to game initialization!
    // ROOT CAUSE: status_initialize() calls windowprocs.win_status_init()
    // which requires window system to be initialized first.
    // CORRECT LOCATION: ios_newgame.c and ios_save_integration.c
    // (after init_ios_windowprocs() is called)
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 5: SKIPPED - status_initialize() is game-level, not dylib-level\n");
    fprintf(stderr, "[DYLIB_LIFECYCLE]   (Will be called in ios_newgame or ios_restore_complete)\n");

    // Step 6: iOS bridge state
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 6: ios_reset_all_static_state()...\n");
    ios_reset_all_static_state();
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ iOS bridge state reset\n");

    // Step 7: Boulder symbol override (iOS-specific fix)
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 7: Boulder symbol override...\n");
    extern struct instance_globals_o go;
    go.ov_primary_syms[SYM_BOULDER + SYM_OFF_X] = '0';
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ Boulder symbol set to '0'\n");

    fprintf(stderr, "========================================\n");
    fprintf(stderr, "[DYLIB_LIFECYCLE] ✅ FULL INIT COMPLETE\n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "\n");
}

/* ========================================================================
 * UNIFIED DYLIB SHUTDOWN
 * ======================================================================== */

/**
 * CRITICAL: This function is the ONLY place where dylib shutdown happens.
 *
 * Call Order (MANDATORY):
 * 1. status_finish()         - Free status buffers
 * 2. freedynamicdata()       - Free NetHack dynamic memory
 * 3. l_nhcore_done()         - Shutdown Lua
 * 4. dlb_cleanup()           - Clean up data files
 *
 * This function is called:
 * - Before dylib unload (NetHackBridge.stopGameAsync)
 * - Before memory wipe (NetHackGameManager.resetForNewGame)
 *
 * After this function, ios_full_dylib_init() can be called again.
 */
NETHACK_EXPORT void ios_full_dylib_shutdown(void)
{
    fprintf(stderr, "\n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "[DYLIB_LIFECYCLE] FULL DYLIB SHUTDOWN\n");
    fprintf(stderr, "========================================\n");

    // ASSERTION: Should only be called if init was called
    if (!full_init_called) {
        fprintf(stderr, "[DYLIB_LIFECYCLE] ⚠️  Shutdown called without init - ignoring\n");
        return;
    }

    // Step 1: Status system
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 1: status_finish()...\n");
    status_finish();
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ Status buffers freed\n");

    // Step 2: Free dynamic data
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 2: freedynamicdata()...\n");
    freedynamicdata();
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ NetHack dynamic memory freed\n");

    // Step 3: Lua shutdown
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 3: l_nhcore_done()...\n");
    l_nhcore_done();
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ Lua scripting shut down\n");

    // Step 4: DLB cleanup - dlb_cleanup() is a macro that expands to nothing (DLB disabled)
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 4: dlb_cleanup()...\n");
    dlb_cleanup();  // Expands to nothing, but kept for API consistency
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ Data file system cleaned up (DLB disabled)\n");

    // Step 5: CRITICAL - Reset global_early_init_done for next dylib load
    // ROOT CAUSE: macOS reuses dylib memory → static variables persist!
    // If not reset, ios_early_init() skips zeroing gi.invent → corruption!
    fprintf(stderr, "[DYLIB_LIFECYCLE] Step 5: Resetting global initialization flags...\n");
    extern void ios_reset_early_init_flag(void);  // Defined in ios_dylib_stubs.c
    ios_reset_early_init_flag();
    fprintf(stderr, "[DYLIB_LIFECYCLE]   ✓ global_early_init_done reset to 0\n");

    // Reset local flag for next initialization
    full_init_called = 0;

    fprintf(stderr, "========================================\n");
    fprintf(stderr, "[DYLIB_LIFECYCLE] ✅ FULL SHUTDOWN COMPLETE\n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "\n");
}

/* ========================================================================
 * LIFECYCLE STATE QUERIES
 * ======================================================================== */

/**
 * Check if dylib has been fully initialized.
 * Useful for assertions in other code.
 */
NETHACK_EXPORT int ios_dylib_is_initialized(void)
{
    return full_init_called;
}
