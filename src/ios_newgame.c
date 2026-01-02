/*
 * ios_newgame.c - iOS-specific newgame implementation
 *
 * This replaces the standard NetHack newgame() with a version that
 * properly initializes everything for iOS, avoiding issues with
 * window procedures and status initialization.
 */

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <dispatch/dispatch.h>
#include "../NetHack/include/hack.h"
#include "../NetHack/include/dlb.h"
#include "ios_trace.h"

// External functions we'll test one by one
// notice_mon_off is a macro, not a function
extern void init_objects(void);
extern void role_init(void);
extern void ios_init_dungeons(void);
extern void init_artifacts(void);
// u_init was split into 3 functions in newer NetHack
extern void u_init_misc(void);
extern void u_init_inventory_attrs(void);
extern void u_init_skills_discoveries(void);
extern void l_nhcore_init(void);
extern void reset_glyphmap(enum glyphmap_change_triggers trigger);
extern void mklev(void);
extern void u_on_upstairs(void);
extern void vision_reset(void);
extern void check_special_room(boolean);
extern void docrt(void);
extern struct monst *makedog(void);

// External functions
extern void early_init(int argc, char *argv[]);
extern void mklev(void);
extern void oinit(void);
extern void mkstairs(coordxy x, coordxy y, char up, struct mkroom *room, boolean portal);

// External globals
extern struct instance_globals_saved_p svp;
extern struct flag flags;
extern int n_dgns;  // Number of dungeons

// Zone-based Lua memory allocator
#include "../zone_allocator/nethack_zone.h"

void *lua_simple_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    (void)ud; (void)osize;  // Unused parameters
    if (nsize == 0) {
        if (ptr) zone_free(ptr);
        return NULL;
    }
    // Use re_alloc from zone allocator (handles both alloc and realloc)
    return re_alloc((long*)ptr, nsize);
}

void ios_newgame(void) {
    fprintf(stderr, "[IOS_NEWGAME] Starting iOS new game initialization\n");
    fflush(stderr);

    // Follow NetHack's initialization order, adapted for iOS

    // 1. early_init() - GUARD CLAUSE (prevent double-init crash!)
    // CRITICAL: early_init() should only be called ONCE (in nethack_real_init)
    // Calling it twice causes init_dungeons() to panic("too many dungeons")!
    //
    // BUT: We have a problem - gn.nocreate* must be reset between games!
    // Solution: Keep guard clause, add targeted reset AFTER guard
    fprintf(stderr, "[IOS_NEWGAME] Step 1: Checking if early_init() already done...\n");
    extern int is_early_init_done(void);
    if (!is_early_init_done()) {
        fprintf(stderr, "[IOS_NEWGAME] early_init() not done yet, calling it...\n");
        early_init(0, NULL);
        fprintf(stderr, "[IOS_NEWGAME] ✓ early_init() OK\n");
    } else {
        fprintf(stderr, "[IOS_NEWGAME] ✓ early_init() already called in nethack_real_init, skipping\n");

        // CRITICAL FIX: Reset inventory exclusion filters for Game 2+
        // ROOT CAUSE: gn.nocreate* (nocreate, nocreate2, nocreate3, nocreate4)
        // are used by ini_inv() to exclude duplicate items during generation.
        // If not reset, Game 2+ uses STALE exclusions from Game 1!
        //
        // Result: mkobj() infinite loop → corrupt "0 blessed +1 spears"
        //
        // WHY LOADGAME() WORKS:
        // - restgamestate() loads inventory from file (no ini_inv() call)
        // - gn.nocreate* not used at all during restore
        fprintf(stderr, "[IOS_NEWGAME] Resetting inventory exclusion filters (gn.nocreate*)...\n");
        extern struct instance_globals_n gn;
        gn.nocreate = 0;
        gn.nocreate2 = 0;
        gn.nocreate3 = 0;
        gn.nocreate4 = 0;
        fprintf(stderr, "[IOS_NEWGAME] ✓ gn.nocreate* = {0, 0, 0, 0} - ready for fresh inventory\n");
    }

    // 2. choose_windows() - Skip the NetHack function, but we MUST set up window procs!
    fprintf(stderr, "[IOS_NEWGAME] Step 2: Setting up iOS window procedures...\n");

    // CRITICAL FIX: Initialize window procedures for NEW game
    // This is what LOAD game does in ios_save_integration.c:706
    // Without this, ios_putstr is never called, so no messages!
    extern void init_ios_windowprocs(void);
    init_ios_windowprocs();  // Sets windowprocs = ios_procs

    // Also initialize the window system (creates render queue)
    // This is safe to call multiple times - it has internal guards
    int dummy_argc = 0;
    char *dummy_argv[] = { NULL };
    init_nhwindows(&dummy_argc, dummy_argv);  // Allocates g_render_queue!

    fprintf(stderr, "[IOS_NEWGAME] ✓ Window procedures initialized\n");

    // NOW initialize status after window system is ready
    fprintf(stderr, "[IOS_NEWGAME] Calling status_initialize(FALSE)...\n");
    extern void status_initialize(boolean reassessment);
    status_initialize(0);  // FALSE = 0, do full init
    fprintf(stderr, "[IOS_NEWGAME] ✓ status_initialize() OK\n");

    // 3. initoptions() - Initialize options (minimal version for iOS)
    fprintf(stderr, "[IOS_NEWGAME] Step 3: Doing minimal option init for iOS...\n");

    // SAVEP should already be set by ios_filesys.c - don't override it!
    // SAVEF is in gs.SAVEF (managed by NetHack's set_savefile_name())
    extern char SAVEP[];
    fprintf(stderr, "[IOS_NEWGAME] Using existing SAVEP: %s\n", SAVEP);
    // NetHack will set gs.SAVEF when set_savefile_name() is called

    // Just do the absolute minimum needed for options
    extern void init_random(int (*fn)(int));
    extern int rn2(int);
    extern int rn2_on_display_rng(int);
    extern void sf_init(void);  // CRITICAL for save file operations!

    // Initialize the random number generators
    fprintf(stderr, "[IOS_NEWGAME]   Initializing RNG...\n");
    init_random(rn2);
    init_random(rn2_on_display_rng);

    // CRITICAL: Initialize save file function pointers!
    // Without this, store_version crashes with null function pointer
    fprintf(stderr, "[IOS_NEWGAME]   Initializing savefile format handlers (sf_init)...\n");
    sf_init();

    // Set some basic flags
    flags.pantheon = -1;  // Will be set by role_init

    // Set critical game flags that would normally be set by initoptions()
    // See docs/missing-defaults-analysis.md for complete list

    // Door interaction
    flags.autoopen = TRUE;  // Enable automatic door opening when walking into doors
    fprintf(stderr, "[IOS_NEWGAME]   Set flags.autoopen = TRUE\n");

    // Critical safety flags - prevent accidental disasters
    flags.safe_dog = TRUE;        // Prevent attacking pets (safe_pet option)
    flags.safe_wait = FALSE;       // Touch-UI: no accidental keypresses, allow wait near monsters
    flags.confirm = TRUE;          // Confirmation prompts for dangerous actions
    fprintf(stderr, "[IOS_NEWGAME]   Set safety flags (safe_pet, !safe_wait, confirm)\n");

    // Autopickup behavior - Touch-optimized defaults
    // IMPORTANT: flags.pickup is OFF by default in NetHack! We want it ON for mobile.
    flags.pickup = TRUE;           // Master autopickup toggle
    flags.pickup_stolen = TRUE;    // Autopickup stolen items
    flags.pickup_thrown = TRUE;    // Autopickup thrown items
    flags.autoquiver = TRUE;       // Auto-fill quiver when firing

    // Pickup categories: Match .nethackrc - NO Tools (includes chests)
    // $=Gold "=Amulets !=Potions ?=Scrolls /=Wands ==Rings +=Spellbooks
    // Tools excluded: chests/containers shouldn't be auto-picked
    const char *pickup_types = "$\"!?/=+";
    strncpy(flags.pickup_types, pickup_types, sizeof(flags.pickup_types) - 1);
    flags.pickup_types[sizeof(flags.pickup_types) - 1] = '\0';
    fprintf(stderr, "[IOS_NEWGAME]   Set pickup_types = '%s' (no Tools/containers)\n", pickup_types);

    // Burden limit: Stop autopickup at Stressed (MOD_ENCUMBER)
    // Items are silently left on ground when too heavy
    flags.pickup_burden = MOD_ENCUMBER;

    fprintf(stderr, "[IOS_NEWGAME]   Set autopickup: ON, burden=MOD_ENCUMBER, autoquiver=TRUE\n");

    // Important UI/Visual flags
    iflags.wc_color = TRUE;        // Enable color in map display
    iflags.bgcolors = TRUE;        // Enable background colors
    iflags.cmdassist = TRUE;       // Help for direction input errors
    flags.verbose = TRUE;          // Verbose messages (more detail)
    flags.help = TRUE;             // Show help messages

    // CRITICAL: Use graphical menus (not yn_function prompts)
    // MENU_FULL = 2, MENU_TRADITIONAL = 0
    // Without this, loot options use yn_function instead of menu system!
    flags.menu_style = MENU_FULL;
    fprintf(stderr, "[IOS_NEWGAME]   Set flags.menu_style = MENU_FULL (2)\n");

    // CRITICAL: Enable number_pad mode for numpad movement (1-9)
    // Numpad is better for touch interface:
    // - Dedicated movement keys 1-9 (no conflicts with commands)
    // - h/j/k/l can be used for other commands
    // - Well-tested NetHack feature
    iflags.num_pad = TRUE;         // Use numpad (1-9) for movement
    iflags.num_pad_mode = 0;       // Standard numpad layout

    // Tell NetHack to use numpad for movement
    // number_pad() is a macro that calls windowprocs.win_number_pad
    if (windowprocs.win_number_pad) {
        (*windowprocs.win_number_pad)(1);  // 1 = number pad, 0 = vi-keys
    }

    // CRITICAL FIX: Use DOUBLE reset_commands() pattern (matches LOAD path)
    // Step 1: Full reinitialization (like initoptions() does)
    // Step 2: Rebind with numpad (using iflags.num_pad = TRUE)
    // This pattern is REQUIRED - single reset_commands(FALSE) doesn't work!
    // early_init() called reset_commands(TRUE) which reset everything to vi-keys.
    // We MUST call reset_commands() TWICE to properly initialize movement bindings.
    // After reset_commands(), we restore C('_') retravel which might get overwritten.
    extern void reset_commands(boolean initial);
    reset_commands(TRUE);   // Full reinitialization first
    reset_commands(FALSE);  // Then rebind with numpad
    fprintf(stderr, "[IOS_NEWGAME]   Called reset_commands(TRUE) + reset_commands(FALSE) to bind numpad keys (num_pad=%d)\n", iflags.num_pad);

    // DEBUG: Check if '4' is actually bound to a movement command
    extern struct instance_globals_c gc;
    const void *cmd_4 = gc.Cmd.commands['4'];
    fprintf(stderr, "[IOS_NEWGAME]   DEBUG: Key '4' binding = %p (NULL=not bound)\n", cmd_4);
    fprintf(stderr, "[IOS_NEWGAME]   DEBUG: gc.Cmd.num_pad = %d, iflags.num_pad = %d\n",
            gc.Cmd.num_pad, iflags.num_pad);

    // CRITICAL: Restore C('_') retravel binding after reset_commands() call
    // reset_commands() may restore backed-up keys which can overwrite retravel
    extern boolean bind_key(uchar key, const char *command);
    bind_key(0x1F, "retravel");  // 0x1F = C('_')
    fprintf(stderr, "[IOS_NEWGAME]   Restored C('_') retravel binding\n");
    fprintf(stderr, "[IOS_NEWGAME]   Set UI flags (color, cmdassist, verbose, help, numpad=TRUE) + numpad keys bound!\n");

    // Disable tutorial (equivalent to OPTIONS=!tutorial in config file)
    flags.tutorial = FALSE;        // Skip tutorial prompt entirely
    fprintf(stderr, "[IOS_NEWGAME]   Set flags.tutorial = FALSE (skip tutorial)\n");

    // System features
    flags.bones = TRUE;            // Load bones files
    flags.ins_chkpt = TRUE;        // Checkpoint saves after level changes
    flags.tombstone = TRUE;        // Show tombstone on death
    flags.travelcmd = TRUE;        // Enable travel command
    flags.tips = TRUE;             // Show gameplay tips
    fprintf(stderr, "[IOS_NEWGAME]   Set system flags (bones, checkpoint, travel, tips)\n");

    // Additional commonly expected defaults
    flags.invlet_constant = TRUE;  // Keep inventory letters constant (fixinv)
    flags.sparkle = TRUE;          // Sparkle effect for things
    flags.sortpack = TRUE;         // Sort pack contents
    fprintf(stderr, "[IOS_NEWGAME]   Set additional flags (fixinv, sparkle, sortpack)\n");

    fprintf(stderr, "[IOS_NEWGAME] ✓ Minimal options init OK - Set %d critical defaults\n", 18);

    // 4. dlb_init() - REMOVED (already called in ios_full_dylib_init)
    // dlb_init() is now part of the unified dylib initialization in ios_dylib_lifecycle.c
    // No need to call it again here - it's a DYLIB-layer concern, not GAME-layer

    // CRITICAL: Initialize symbols for TTY display!
    fprintf(stderr, "[IOS_NEWGAME] Calling init_symbols()...\n");
    extern void init_symbols(void);
    init_symbols();
    fprintf(stderr, "[IOS_NEWGAME] ✓ init_symbols() OK - TTY chars initialized\n");

    // CRITICAL FIX: Apply iOS symbol overrides RIGHT AFTER init_symbols()
    // init_symbols() calls init_ov_primary_symbols() which WIPES all overrides to zero!
    // We MUST set our overrides NOW, before symbols are cached
    fprintf(stderr, "[IOS_NEWGAME] Applying iOS symbol overrides...\n");
    extern void ios_setup_default_symbols(void);
    ios_setup_default_symbols();
    fprintf(stderr, "[IOS_NEWGAME] ✓ iOS symbol overrides applied\n");

    // 5. vision_init() - CRITICAL! Must come BEFORE role_init()
    fprintf(stderr, "[IOS_NEWGAME] Step 5: Calling vision_init()...\n");
    extern void vision_init(void);
    vision_init();
    fprintf(stderr, "[IOS_NEWGAME] ✓ vision_init() OK\n");

    // 6. init_sound_disp_gamewindows() - Windows creation
    fprintf(stderr, "[IOS_NEWGAME] Step 6: Creating game windows...\n");

    // We need to create the windows ourselves since we're not calling init_sound_disp_gamewindows
    extern winid WIN_MAP, WIN_MESSAGE, WIN_STATUS, WIN_INVEN;

    WIN_MESSAGE = create_nhwindow(NHW_MESSAGE);
    fprintf(stderr, "[IOS_NEWGAME] WIN_MESSAGE = %d\n", WIN_MESSAGE);

    WIN_STATUS = create_nhwindow(NHW_STATUS);
    fprintf(stderr, "[IOS_NEWGAME] WIN_STATUS = %d\n", WIN_STATUS);

    WIN_MAP = create_nhwindow(NHW_MAP);
    fprintf(stderr, "[IOS_NEWGAME] WIN_MAP = %d\n", WIN_MAP);

    WIN_INVEN = create_nhwindow(NHW_MENU);
    fprintf(stderr, "[IOS_NEWGAME] WIN_INVEN = %d\n", WIN_INVEN);

    fprintf(stderr, "[IOS_NEWGAME] ✓ Windows created\n");

    fflush(stderr);

    // Now continue with game initialization steps
    fprintf(stderr, "[IOS_NEWGAME] Testing notice_mon_off() macro...\n");
    fflush(stderr);
    notice_mon_off();
    fprintf(stderr, "[IOS_NEWGAME] ✓ notice_mon_off() OK\n");
    fflush(stderr);

    fprintf(stderr, "[IOS_NEWGAME] Setting disp.botlx...\n");
    fflush(stderr);
    disp.botlx = TRUE;
    fprintf(stderr, "[IOS_NEWGAME] ✓ disp.botlx OK\n");

    fprintf(stderr, "[IOS_NEWGAME] Setting svc.context fields...\n");
    fflush(stderr);
    svc.context.ident = 2;
    svc.context.warnlevel = 1;
    svc.context.next_attrib_check = 600L;
    svc.context.tribute.enabled = TRUE;
    svc.context.tribute.tributesz = sizeof(struct tribute_info);
    fprintf(stderr, "[IOS_NEWGAME] ✓ svc.context OK\n");

    fprintf(stderr, "[IOS_NEWGAME] Setting mvitals loop...\n");
    fflush(stderr);
    int i;
    for (i = LOW_PM; i < NUMMONS; i++) {
        if (i % 100 == 0) {
            fprintf(stderr, "[IOS_NEWGAME] mvitals[%d]...\n", i);
            fflush(stderr);
        }
        svm.mvitals[i].mvflags = mons[i].geno & G_NOCORPSE;
    }
    fprintf(stderr, "[IOS_NEWGAME] ✓ mvitals loop OK\n");

    fprintf(stderr, "[IOS_NEWGAME] Calling init_objects()...\n");
    fflush(stderr);
    init_objects();
    fprintf(stderr, "[IOS_NEWGAME] ✓ init_objects() OK\n");

    // 7. role_init() - Vor Dungeons! (Must come AFTER vision_init())
    fprintf(stderr, "[IOS_NEWGAME] Step 7: Setting up for role_init()...\n");
    fflush(stderr);

    flags.pantheon = -1;

    // CRITICAL FIX: Restore backed-up character selection BEFORE defaults!
    // User's choices were backed up in nethack_finalize_character()
    // We MUST restore them NOW before the -1 checks below!
    fprintf(stderr, "[IOS_NEWGAME]   Restoring character selection from backup...\n");
    fflush(stderr);

    extern const char* nethack_get_backed_up_name(void);
    extern int nethack_get_backed_up_role(void);
    extern int nethack_get_backed_up_race(void);
    extern int nethack_get_backed_up_gender(void);
    extern int nethack_get_backed_up_align(void);

    const char* backup_name = nethack_get_backed_up_name();
    int backup_role = nethack_get_backed_up_role();
    int backup_race = nethack_get_backed_up_race();
    int backup_gender = nethack_get_backed_up_gender();
    int backup_align = nethack_get_backed_up_align();

    if (backup_name && backup_name[0] != '\0') {
        strncpy(svp.plname, backup_name, PL_NSIZ - 1);
        svp.plname[PL_NSIZ - 1] = '\0';
        fprintf(stderr, "[IOS_NEWGAME]   ✓ Restored plname: '%s'\n", svp.plname);
    }

    if (backup_role >= 0) {
        flags.initrole = backup_role;
        fprintf(stderr, "[IOS_NEWGAME]   ✓ Restored role: %d\n", flags.initrole);
    }

    if (backup_race >= 0) {
        flags.initrace = backup_race;
        fprintf(stderr, "[IOS_NEWGAME]   ✓ Restored race: %d\n", flags.initrace);
    }

    if (backup_gender >= 0) {
        flags.initgend = backup_gender;
        fprintf(stderr, "[IOS_NEWGAME]   ✓ Restored gender: %d\n", flags.initgend);
    }

    if (backup_align >= 0) {
        flags.initalign = backup_align;
        fprintf(stderr, "[IOS_NEWGAME]   ✓ Restored alignment: %d\n", flags.initalign);
    }

    fprintf(stderr, "[IOS_NEWGAME]   Character selection restored!\n");
    fflush(stderr);

    // NOW check for defaults (only if user didn't set anything AND backup is empty)
    if (flags.initrole == -1) {
        fprintf(stderr, "[IOS_NEWGAME]   No backup and no selection - Setting random role...\n");
        flags.initrole = -2;  // Random
    }
    if (flags.initrace == -1) {
        fprintf(stderr, "[IOS_NEWGAME]   No backup and no selection - Setting random race...\n");
        flags.initrace = -2;  // Random
    }
    if (flags.initgend == -1) {
        fprintf(stderr, "[IOS_NEWGAME]   No backup and no selection - Setting random gender...\n");
        flags.initgend = -2;  // Random
    }
    if (flags.initalign == -1) {
        fprintf(stderr, "[IOS_NEWGAME]   No backup and no selection - Setting random alignment...\n");
        flags.initalign = -2;  // Random
    }
    fflush(stderr);

    fprintf(stderr, "[IOS_NEWGAME] Step 7: Calling role_init()...\n");
    role_init();
    fprintf(stderr, "[IOS_NEWGAME] ✓ role_init() OK\n");
    fflush(stderr);

    // 8. init_dungeons() - Vor u_init()!
    // NOTE: Lua was already initialized in ios_full_dylib_init() via l_nhcore_init()
    // DO NOT call nhl_init() or nhl_done() here - it would destroy gl.luacore!
    fprintf(stderr, "[IOS_NEWGAME] Step 8: Calling init_dungeons()...\n");
    fflush(stderr);
    init_dungeons();

    fprintf(stderr, "[IOS_NEWGAME] ✓ init_dungeons() OK\n");
    fflush(stderr);

    // 9. init_artifacts() - Vor u_init()!
    fprintf(stderr, "[IOS_NEWGAME] Step 9: Calling init_artifacts()...\n");
    fflush(stderr);
    init_artifacts();
    fprintf(stderr, "[IOS_NEWGAME] ✓ init_artifacts() OK\n");
    fflush(stderr);

    // 10. u_init functions - Spieler (split into 3 parts in newer NetHack)
    fprintf(stderr, "[IOS_NEWGAME] Step 10: Preparing for u_init functions...\n");
    fflush(stderr);

    // REMOVED: status_initialize() - it's called later after window system is ready
    // Calling it here causes "2nd status_initialize" error
    // The proper place is after init_nhwindows() sets up the window system

    // CRITICAL FIX: Reset role inventory templates BEFORE u_init_inventory_attrs()
    // BUG: ini_inv() modifies static template arrays (decrements trquan)
    // On iOS, process stays alive across games, so templates persist modified!
    // Game 1: trquan=1 → decrement → trquan=0
    // Game 2: trquan=0 → decrement → trquan=-1 → WRAPS TO 63 (6-bit bitfield!)
    //         Creates 64 touchstones instead of 1!
    fprintf(stderr, "[IOS_NEWGAME] Resetting role inventory templates...\n");
    fflush(stderr);
    extern void ios_reset_role_inventory_templates(void);
    ios_reset_role_inventory_templates();

    fprintf(stderr, "[IOS_NEWGAME] Step 10: Calling u_init_misc()...\n");
    fflush(stderr);
    u_init_misc();
    fprintf(stderr, "[IOS_NEWGAME] ✓ u_init_misc() OK\n");

    fprintf(stderr, "[IOS_NEWGAME] Step 10: Calling u_init_inventory_attrs()...\n");
    fflush(stderr);
    u_init_inventory_attrs();
    fprintf(stderr, "[IOS_NEWGAME] ✓ u_init_inventory_attrs() OK\n");

    fprintf(stderr, "[IOS_NEWGAME] Step 10: Calling u_init_skills_discoveries()...\n");
    fflush(stderr);
    u_init_skills_discoveries();
    fprintf(stderr, "[IOS_NEWGAME] ✓ u_init_skills_discoveries() OK\n");
    fflush(stderr);

    // CRITICAL FIX: Initialize playtime tracking (matches allmain.c:846-847)
    // This prevents the "55 years" bug caused by uninitialized urealtime.start_timing
    fprintf(stderr, "[IOS_NEWGAME] Initializing urealtime for playtime tracking...\n");
    fflush(stderr);
    urealtime.realtime = 0L;
    urealtime.start_timing = getnow();
    fprintf(stderr, "[IOS_NEWGAME] ✓ urealtime initialized: start_timing=%ld, realtime=%ld\n",
            (long)urealtime.start_timing, urealtime.realtime);
    fflush(stderr);

    // CRITICAL FIX: Set save file name (matches allmain.c before line 846)
    // This must be called AFTER u_init() when character state is fully ready
    // Creates gs.SAVEF = "save/[uid][plname].sav" (e.g. "save/501Hero.sav")
    fprintf(stderr, "[IOS_NEWGAME] Setting save file name from plname='%s'...\n", svp.plname);
    fflush(stderr);
    extern void set_savefile_name(boolean);
    set_savefile_name(TRUE);
    fprintf(stderr, "[IOS_NEWGAME] ✓ gs.SAVEF = '%s'\n", gs.SAVEF);
    fflush(stderr);

    // CRITICAL FIX: Mark that we have data worth saving (matches allmain.c:851)
    // This allows save operations to proceed instead of being skipped
    program_state.something_worth_saving++;
    fprintf(stderr, "[IOS_NEWGAME] ✓ program_state.something_worth_saving = %d\n",
            program_state.something_worth_saving);
    fflush(stderr);

    // 11. l_nhcore_init() - REMOVED (already called in ios_full_dylib_init)
    // Lua core is now initialized as part of unified dylib init in ios_dylib_lifecycle.c
    // Calling it twice would reinitialize Lua and leak memory!
    // gl.luacore is already set up and ready to use

    // Reset glyphmap after l_nhcore_init
    fprintf(stderr, "[IOS_NEWGAME] Calling reset_glyphmap()...\n");
    fflush(stderr);
    reset_glyphmap(gm_newgame);
    fprintf(stderr, "[IOS_NEWGAME] ✓ reset_glyphmap() OK\n");
    fflush(stderr);

    // 12. mklev() - Erstes Level
    fprintf(stderr, "[IOS_NEWGAME] ========================\n");
    fprintf(stderr, "[IOS_NEWGAME] Step 12: About to call mklev()...\n");
    fprintf(stderr, "[IOS_NEWGAME] u.uz.dnum = %d, u.uz.dlevel = %d\n", u.uz.dnum, u.uz.dlevel);
    fprintf(stderr, "[IOS_NEWGAME] gl.luacore = %p\n", gl.luacore);
    fprintf(stderr, "[IOS_NEWGAME] ========================\n");
    fflush(stderr);

    // mklev() will call clear_level_structures() internally - don't call it manually!
    // Calling it here AND in mklev() causes double-clear which can corrupt state
    fprintf(stderr, "[IOS_NEWGAME]   mklev() will clear level structures internally\n");
    fflush(stderr);

    // Now generate the level
    fprintf(stderr, "[IOS_NEWGAME] Step 12: Calling mklev()...\n");
    fflush(stderr);
    mklev();
    fprintf(stderr, "[IOS_NEWGAME] ✓ mklev() OK\n");
    fflush(stderr);

    // CRITICAL DEBUG: Check gs.stairs immediately after mklev()!
    // SAFE: Only check pointer, don't iterate (avoid race conditions)
    fprintf(stderr, "[STAIRS_DEBUG] ========================================\n");
    fprintf(stderr, "[STAIRS_DEBUG] gs.stairs pointer = %p (NULL=BAD, non-NULL=GOOD)\n", (void*)gs.stairs);
    if (!gs.stairs) {
        fprintf(stderr, "[STAIRS_DEBUG] ✗✗✗ PROBLEM: gs.stairs is NULL after mklev()!\n");
    } else {
        fprintf(stderr, "[STAIRS_DEBUG] ✓ gs.stairs exists (stairs were created)\n");
    }
    fprintf(stderr, "[STAIRS_DEBUG] ========================================\n");
    fflush(stderr);

    // Place player on upstairs
    fprintf(stderr, "[IOS_NEWGAME] Calling u_on_upstairs()...\n");
    fflush(stderr);
    u_on_upstairs();
    fprintf(stderr, "[IOS_NEWGAME] ✓ u_on_upstairs() OK\n");
    fprintf(stderr, "[IOS_NEWGAME] Player position after u_on_upstairs: u.ux=%d, u.uy=%d\n", u.ux, u.uy);

    // Check what's in levl at player position
    if (u.ux > 0 && u.uy > 0) {
        struct rm *lev = &levl[u.ux][u.uy];
        fprintf(stderr, "[IOS_NEWGAME] Level at player pos: typ=%d, glyph=%d\n",
                lev->typ, lev->glyph);

        // Check a few surrounding positions too
        for (int dx = -1; dx <= 1; dx++) {
            for (int dy = -1; dy <= 1; dy++) {
                if (isok(u.ux + dx, u.uy + dy)) {
                    lev = &levl[u.ux + dx][u.uy + dy];
                    fprintf(stderr, "[IOS_NEWGAME] Level at (%d,%d): typ=%d\n",
                            u.ux + dx, u.uy + dy, lev->typ);
                }
            }
        }
    }
    fflush(stderr);

    // 13. vision_reset() - Nach mklev()!
    fprintf(stderr, "[IOS_NEWGAME] Step 13: Calling vision_reset()...\n");
    fflush(stderr);
    vision_reset();
    fprintf(stderr, "[IOS_NEWGAME] ✓ vision_reset() OK\n");
    fflush(stderr);

    // Check for special rooms
    fprintf(stderr, "[IOS_NEWGAME] Calling check_special_room()...\n");
    fflush(stderr);
    check_special_room(FALSE);
    fprintf(stderr, "[IOS_NEWGAME] ✓ check_special_room() OK\n");
    fflush(stderr);

    // Create pet if applicable
    fprintf(stderr, "[IOS_NEWGAME] Calling makedog()...\n");
    fflush(stderr);
    makedog();
    fprintf(stderr, "[IOS_NEWGAME] ✓ makedog() OK\n");
    fflush(stderr);

    // Note: moveloop_preamble is static, can't call it from here
    // But we don't need it for just displaying the map

    // 14. docrt() - Display
    fprintf(stderr, "[IOS_NEWGAME] Step 14: About to call docrt()...\n");
    fprintf(stderr, "[IOS_NEWGAME] Current location: u.ux=%d, u.uy=%d\n", u.ux, u.uy);

    // CRITICAL: u.ux MUST be non-zero or docrt will exit immediately!
    if (u.ux == 0) {
        fprintf(stderr, "[IOS_NEWGAME] WARNING: u.ux is 0! docrt will not run!\n");
        fprintf(stderr, "[IOS_NEWGAME] Forcing player position for testing...\n");
        u.ux = 10;
        u.uy = 10;
    }

    fprintf(stderr, "[IOS_NEWGAME] Calling docrt() NOW with u.ux=%d, u.uy=%d\n", u.ux, u.uy);
    fflush(stderr);

    docrt();

    fprintf(stderr, "[IOS_NEWGAME] ✓ docrt() returned\n");

    // Force a flush_screen to trigger display
    fprintf(stderr, "[IOS_NEWGAME] Calling flush_screen...\n");
    extern void flush_screen(int how);
    flush_screen(0);
    fprintf(stderr, "[IOS_NEWGAME] ✓ flush_screen done\n");
    fflush(stderr);

    // Debug: Print the map to see what we have
    fprintf(stderr, "[IOS_NEWGAME] Checking map buffer...\n");

    // Print first few lines of map buffer
    extern char map_buffer[40][121];
    extern int actual_map_width, actual_map_height;
    extern boolean map_dirty;

    fprintf(stderr, "[IOS_NEWGAME] Map size: %dx%d, dirty=%d\n",
            actual_map_width, actual_map_height, map_dirty);

    // No test map needed anymore - we have real maps!

    // NetHack uses 1-based coordinates! Show actual data
    // Show lines around player position (y=5-10 usually has content)
    for (int y = 0; y < 15 && y < actual_map_height; y++) {
        fprintf(stderr, "[IOS_NEWGAME] Map line %2d: '", y);
        int printed = 0;
        for (int x = 0; x < 120 && printed < 80; x++) {  // MAP_WIDTH = 120
            char c = map_buffer[y][x];
            if (c >= 32 && c <= 126) {
                fprintf(stderr, "%c", c);
                printed++;
            } else if (c == 0 && printed > 0) {
                break;  // End of line
            }
        }
        fprintf(stderr, "' (len=%d)\n", printed);
    }

    // DEBUG: Check specific player position with coordinate mapping
    extern struct you u;
    extern char captured_map[60][181];  // Use captured_map which is sent to Swift

    // Map coordinates are u.ux, u.uy
    // Buffer coordinates need Y offset of +2
    int buffer_x = u.ux;  // X has no offset
    int buffer_y = u.uy + 2;  // Y has +2 offset for message lines

    fprintf(stderr, "[IOS_NEWGAME] Player at map(%d,%d) -> buffer(%d,%d)\n",
            u.ux, u.uy, buffer_x, buffer_y);

    // Check both buffers to see where the data is
    fprintf(stderr, "[IOS_NEWGAME] map_buffer[%d][%d] = '%c' (0x%02X)\n",
            buffer_y, buffer_x, map_buffer[buffer_y][buffer_x],
            (unsigned char)map_buffer[buffer_y][buffer_x]);
    fprintf(stderr, "[IOS_NEWGAME] captured_map[%d][%d] = '%c' (0x%02X)\n",
            buffer_y, buffer_x, captured_map[buffer_y][buffer_x],
            (unsigned char)captured_map[buffer_y][buffer_x]);

    // Show 5x5 area around player from CAPTURED map (what Swift sees)
    fprintf(stderr, "[IOS_NEWGAME] 5x5 area around player from captured_map:\n");
    for (int dy = -2; dy <= 2; dy++) {
        int y = buffer_y + dy;
        if (y >= 0 && y < 40) {
            fprintf(stderr, "[IOS_NEWGAME]   Buffer Y=%2d (Map Y=%2d): ", y, y - 2);
            for (int dx = -2; dx <= 2; dx++) {
                int x = buffer_x + dx;
                if (x >= 0 && x < 120) {
                    char c = captured_map[y][x];
                    fprintf(stderr, "%c", (c >= 32 && c <= 126) ? c : '?');
                } else {
                    fprintf(stderr, " ");
                }
            }
            fprintf(stderr, "\n");
        }
    }

    // Welcome message
    fprintf(stderr, "[IOS_NEWGAME] Calling welcome(TRUE)...\n");
    fflush(stderr);
    extern void welcome(boolean);
    welcome(TRUE);
    fprintf(stderr, "[IOS_NEWGAME] ✓ welcome() OK\n");
    fflush(stderr);

    // Display player inventory
    fprintf(stderr, "\n[IOS_NEWGAME] ====== PLAYER INVENTORY ======\n");
    fprintf(stderr, "[IOS_NEWGAME] Player: %s the %s\n", svp.plname,
            rank_of(u.ulevel, Role_switch, flags.female));
    fprintf(stderr, "[IOS_NEWGAME] Class: %s, Race: %s, Gender: %s\n",
            roles[flags.initrole >= 0 ? flags.initrole : 0].name.m,
            races[flags.initrace >= 0 ? flags.initrace : 0].noun,
            flags.female ? "Female" : "Male");
    fprintf(stderr, "[IOS_NEWGAME] Level: %d, HP: %d/%d, AC: %d\n",
            u.ulevel, u.uhp, u.uhpmax, u.uac);

    // List inventory items
    struct obj *otmp;
    int item_count = 0;

    fprintf(stderr, "[IOS_NEWGAME] Inventory items:\n");
    for (otmp = gi.invent; otmp; otmp = otmp->nobj) {
        item_count++;
        char let = otmp->invlet;

        // Get item description
        char buf[256];
        extern char *doname(struct obj *);
        strlcpy(buf, doname(otmp), sizeof(buf));

        fprintf(stderr, "[IOS_NEWGAME]   %c - %s", let, buf);

        // Add special flags
        if (otmp->owornmask) {
            if (otmp->owornmask & W_WEP)
                fprintf(stderr, " (weapon in hand)");
            else if (otmp->owornmask & W_ARMOR)
                fprintf(stderr, " (being worn)");
            else if (otmp->owornmask & W_RING)
                fprintf(stderr, " (on finger)");
            else if (otmp->owornmask & W_AMUL)
                fprintf(stderr, " (on neck)");
            else if (otmp->owornmask & W_TOOL)
                fprintf(stderr, " (in use)");
            else if (otmp->owornmask & W_QUIVER)
                fprintf(stderr, " (in quiver)");
        }
        fprintf(stderr, "\n");
    }

    if (item_count == 0) {
        fprintf(stderr, "[IOS_NEWGAME]   (empty)\n");
    }

    fprintf(stderr, "[IOS_NEWGAME] Total items: %d\n", item_count);

    // Count gold pieces in inventory
    long gold_amount = 0;
    for (otmp = gi.invent; otmp; otmp = otmp->nobj) {
        if (otmp->oclass == COIN_CLASS) {
            gold_amount += otmp->quan;
        }
    }
    fprintf(stderr, "[IOS_NEWGAME] Gold: %ld\n", gold_amount);
    fprintf(stderr, "[IOS_NEWGAME] ==============================\n\n");
    fflush(stderr);

    // CRITICAL: Call save_currentstate() like main branch does!
    // Main branch analysis proved this is REQUIRED for stairs to work.
    // Previous theory that this wipes gs.stairs was WRONG!
#ifdef INSURANCE
    // DEFENSIVE FIX: Ensure 1lock.0 exists BEFORE save_currentstate()!
    // savestateinlock() tries to OPEN 1lock.0 (save.c:368) - if missing, triggers done(TRICKED)!
    // Even though RealNetHackBridge.c creates it initially, something might delete it during level gen.
    fprintf(stderr, "[IOS_NEWGAME] DEFENSIVE: Verifying 1lock.0 exists before save_currentstate()...\n");
    fflush(stderr);

    extern NHFILE* open_levelfile(int lev, char errbuf[]);
    extern NHFILE* create_levelfile(int lev, char errbuf[]);
    extern void close_nhfile(NHFILE*);
    extern void Sfo_int(NHFILE*, int*, const char*);

    char errbuf[256];
    NHFILE* test_nhfp = open_levelfile(0, errbuf);

    if (!test_nhfp) {
        // 1lock.0 missing! Recreate it NOW to prevent TRICKED death
        fprintf(stderr, "[IOS_NEWGAME] WARNING: 1lock.0 missing! Recreating NOW...\n");
        fprintf(stderr, "[IOS_NEWGAME]   open_levelfile error: %s\n", errbuf);
        fflush(stderr);

        NHFILE* lock_nhfp = create_levelfile(0, errbuf);
        if (lock_nhfp) {
            lock_nhfp->mode = WRITING;
            Sfo_int(lock_nhfp, &svh.hackpid, "hackpid");
            close_nhfile(lock_nhfp);
            fprintf(stderr, "[IOS_NEWGAME] ✓ 1lock.0 recreated with PID %d\n", svh.hackpid);
        } else {
            fprintf(stderr, "[IOS_NEWGAME] ✗✗✗ CRITICAL: Failed to create 1lock.0: %s\n", errbuf);
            fprintf(stderr, "[IOS_NEWGAME] save_currentstate() will FAIL!\n");
        }
        fflush(stderr);
    } else {
        fprintf(stderr, "[IOS_NEWGAME] ✓ 1lock.0 exists, safe to proceed\n");
        close_nhfile(test_nhfp);
        fflush(stderr);
    }

    fprintf(stderr, "[IOS_NEWGAME] Creating initial checkpoint with save_currentstate()...\n");
    fflush(stderr);
    extern void save_currentstate(void);
    save_currentstate();
    fprintf(stderr, "[IOS_NEWGAME] ✓ Initial checkpoint created\n");
    fflush(stderr);
#endif

    fprintf(stderr, "[IOS_NEWGAME] ✅ ALL STEPS COMPLETED SUCCESSFULLY!\n");
    fprintf(stderr, "[IOS_NEWGAME] Game is now initialized and ready for moveloop!\n");
    fflush(stderr);

    // CRITICAL: Render the map BEFORE notifying Swift!
    // Guardian Analysis: ios_notify_game_ready() was called BEFORE docrt()
    // This caused Swift to start listening but map_buffer was still empty
    // Map only rendered later in moveloop (too late!)
    fprintf(stderr, "[IOS_NEWGAME] Rendering initial map with docrt()...\n");
    fflush(stderr);

    // CRITICAL: Map will be rendered automatically by moveloop!
    // Don't try to render it here - moveloop() will call flush_screen()
    // which triggers print_glyph() for all tiles
    // Then ios_wait_synch() captures and notifies Swift automatically
    fprintf(stderr, "[IOS_NEWGAME] Map will be rendered when moveloop starts\n");
    fflush(stderr);

    // NOW game is TRULY ready - map rendered, messages sent
    // At this point:
    // - gi.invent is populated with starting items
    // - u.ux/u.uy contain player position
    // - Map has been rendered AND captured
    // - All globals are in valid state
    // Swift UI can safely query everything and display map immediately
    fprintf(stderr, "[IOS_NEWGAME] 🎯 Notifying Swift: Game ready for queries\n");
    extern void ios_notify_game_ready(void);
    ios_notify_game_ready();
    fflush(stderr);

    // The game is now fully initialized
    // Next step would be moveloop() but we'll handle that separately
}

// Enter the main game loop
void debug_enter_moveloop(void) {
    fprintf(stderr, "[DEBUG_MOVELOOP] Starting moveloop...\n");
    fflush(stderr);

    // Call the real NetHack moveloop
    extern void moveloop(boolean);

    // CRITICAL: Mark that we have something worth saving!
    // This must be set or dosave0() will return immediately
    program_state.something_worth_saving = 1;
    fprintf(stderr, "[IOS_NEWGAME] Set something_worth_saving = 1\n");

    // We're not resuming, this is a new game
    moveloop(FALSE);

    // This should never return in normal gameplay
    fprintf(stderr, "[DEBUG_MOVELOOP] moveloop returned (game ended)\n");
    fflush(stderr);
}

// Run one iteration of the game loop (for testing)
void debug_moveloop_once(void) {
    fprintf(stderr, "[DEBUG_MOVELOOP] Running one moveloop_core iteration...\n");
    fflush(stderr);

    // Call the real NetHack moveloop_core directly
    extern void moveloop_core(void);
    moveloop_core();

    fprintf(stderr, "[DEBUG_MOVELOOP] moveloop_core iteration complete\n");
    fflush(stderr);
}