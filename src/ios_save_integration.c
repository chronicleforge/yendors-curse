/*
 * ios_save_integration.c - Complete save/load integration for NetHack iOS
 *
 * This file integrates the static memory allocator's save/restore with
 * NetHack's game state save/restore for PERFECT save/load functionality.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <dirent.h>
#include <dispatch/dispatch.h>
#include "../NetHack/include/hack.h"
#include "../zone_allocator/nethack_memory_final.h"
#include "../NetHack/include/dlb.h"
#include "nethack_export.h"
#include "ios_crash_handler.h"

// External functions from NetHack
extern void savegamestate(NHFILE *);
extern boolean restgamestate(NHFILE *);
extern void l_nhcore_init(void);
extern void save_currentstate(void);
extern int delete_savefile(void);
extern void close_nhfile(NHFILE *);
extern void store_version(NHFILE *);  // Calls store_critical_bytes() internally
extern void store_plname_in_file(NHFILE *);
extern void savelev(NHFILE *, xint8);
extern xint16 ledger_no(d_level *);
extern int uptodate(NHFILE *, const char *, unsigned long);  // Version validation
extern void relink_timers(boolean);           // Post-restore operations
extern void relink_light_sources(boolean);    // Post-restore operations

// Additional functions needed for correct save/restore sequence
extern void done_object_cleanup(void);      // Force in-flight objects to map (end.c:850)
extern void set_ustuck(struct monst *);     // Clear engulf pointer
extern void init_oclass_probs(void);        // Recalculate object probabilities (o_init.c:239)
extern void inven_inuse(boolean);           // Handle in-use items (restore.c:113)
extern void vision_reset(void);             // Reset vision system (vision.c:211)
extern void run_timers(void);               // Expire elapsed timers (timeout.c:2214)
extern void vision_recalc(int);             // Recalculate vision (vision.c)
// notice_mon_off() and notice_mon_on() are MACROS in flag.h, not functions
extern void change_luck(schar);             // Adjust luck value (luck.c)
extern void reglyph_darkroom(void);         // Re-glyph dark rooms (decl.c)
// restlevelstate() is static in restore.c and called internally by getlev()

// External objects/structures
extern struct obj *uball, *uchain;

// iOS versions of save/load functions (from ios_stubs.c)
extern NHFILE* ios_create_savefile(void);
extern NHFILE* ios_open_savefile(void);

// Memory allocator functions
extern int nh_save_state(const char* filename);
extern int nh_load_state(const char* filename);
extern size_t nh_memory_used(void);

// Snapshot restore flag from RealNetHackBridge.c
extern bool snapshot_loaded;

// Debug logging
#define SAVE_LOG(fmt, ...) fprintf(stderr, "[SAVE_INTEGRATION] " fmt "\n", ##__VA_ARGS__)

// VERSIONED SAVES - For debugging save corruption
// Keeps last N saves so we can compare them
static int save_version_counter = 0;
#define MAX_VERSIONED_SAVES 10

// Copy file for backup
static int copy_file(const char* src, const char* dst) {
    FILE* source = fopen(src, "rb");
    if (!source) return -1;

    FILE* dest = fopen(dst, "wb");
    if (!dest) {
        fclose(source);
        return -1;
    }

    char buffer[8192];
    size_t bytes;
    while ((bytes = fread(buffer, 1, sizeof(buffer), source)) > 0) {
        if (fwrite(buffer, 1, bytes, dest) != bytes) {
            fclose(source);
            fclose(dest);
            return -1;
        }
    }

    fclose(source);
    fclose(dest);
    return 0;
}

/*
 * COMPLETE SAVE FUNCTION
 * Saves both memory state AND game state atomically
 */
NETHACK_EXPORT int ios_save_complete(const char* save_dir) {
    SAVE_LOG("========== COMPLETE SAVE INITIATED ==========");

    if (!save_dir) {
        SAVE_LOG("ERROR: No save directory specified");
        return -1;
    }

    // CRITICAL: Comprehensive game-started checks (matching dosave0:100)
    // ALL five checks must pass before we can save
    extern struct instance_globals_s gs;
    extern struct instance_globals_saved_m svm;

    // DEBUG: Show what we're checking
    fprintf(stderr, "\n========================================\n");
    fprintf(stderr, "[SAVE_CHECK] gs.SAVEF = '%s' (length=%zu)\n", gs.SAVEF, strlen(gs.SAVEF));
    fprintf(stderr, "[SAVE_CHECK] gs.SAVEF[0] = %d (0x%02x)\n", gs.SAVEF[0], (unsigned char)gs.SAVEF[0]);
    fprintf(stderr, "[SAVE_CHECK] svp.plname = '%s'\n", svp.plname);
    fprintf(stderr, "[SAVE_CHECK] svm.moves = %ld\n", svm.moves);
    fprintf(stderr, "[SAVE_CHECK] u.uhp = %d\n", u.uhp);
    fprintf(stderr, "========================================\n\n");
    fflush(stderr);

    // Check 1: SAVEF must be set (after character creation completes)
    if (gs.SAVEF[0] == '\0') {
        SAVE_LOG("⏭️ SKIP: gs.SAVEF not set (character creation not complete)");
        SAVE_LOG("   DEBUG: svp.plname='%s', moves=%ld, hp=%d", svp.plname, svm.moves, u.uhp);
        return 0;
    }

    // Check 2: Moves must be > 0 (u_init sets svm.moves=1 at u_init.c:625)
    if (svm.moves == 0) {
        SAVE_LOG("⏭️ SKIP: svm.moves is 0 (u_init not called yet)");
        return 0;
    }

    // Check 3: HP must be > 0 (u_init sets u.uhp at u_init.c:986)
    if (u.uhp == 0) {
        SAVE_LOG("⏭️ SKIP: u.uhp is 0 (character not initialized)");
        return 0;
    }

    // Check 4: something_worth_saving must be set
    if (!program_state.something_worth_saving) {
        SAVE_LOG("⏭️ SKIP: program_state.something_worth_saving is FALSE");
        return 0;
    }

    // Check 5: Current level must be loaded (u.uz.dlevel > 0)
    if (u.uz.dlevel == 0) {
        SAVE_LOG("⏭️ SKIP: u.uz.dlevel is 0 (no level loaded)");
        return 0;
    }

    SAVE_LOG("✓ All checks passed - game is fully initialized");
    SAVE_LOG("  SAVEF: '%s'", gs.SAVEF);
    SAVE_LOG("  Moves: %ld", svm.moves);
    SAVE_LOG("  HP: %d/%d", u.uhp, u.uhpmax);
    SAVE_LOG("  Level: %d", u.uz.dlevel);

    // PHASE 1: Pre-save setup (matching dosave0:82-145)
    SAVE_LOG("PHASE 1: Pre-save setup");

    // Increment saving flag to suppress UI updates
    program_state.saving++;

    // Turn off monster notifications
    notice_mon_off();

    // Fix up state for hangup saves
    u.uinvulnerable = 0;
    if (iflags.save_uswallow)
        u.uswallow = 1, iflags.save_uswallow = 0;
    if (iflags.save_uinwater)
        u.uinwater = 1, iflags.save_uinwater = 0;
    if (iflags.save_uburied)
        u.uburied = 1, iflags.save_uburied = 0;

    // CRITICAL CLEANUP - Force in-flight objects to map
    // This MUST happen BEFORE any save operations to prevent "obj_is_local" panic
    SAVE_LOG("  Cleaning up in-flight objects (done_object_cleanup)");
    done_object_cleanup();

    // Shutdown vision system to prevent impossible() calls
    SAVE_LOG("  Shutting down vision system (vision_recalc)");
    vision_recalc(2);

    // Undo date-dependent luck adjustments (will restore after save)
    SAVE_LOG("  Undoing date-dependent luck adjustments");
    if (flags.moonphase == FULL_MOON)
        change_luck(-1);
    if (flags.friday13)
        change_luck(1);

    SAVE_LOG("✓ Pre-save setup complete");

    // Step 2: Save game state ONLY (no memory.dat!)
    // NetHack's save format properly serializes all data structures.
    // We DON'T save raw memory because ASLR relocates pointers every app restart!
    SAVE_LOG("Step 2: Preparing to save game state (NO memory.dat - only NetHack save)");

    // Step 3: Save game state (to temporary file first for atomicity)
    // CRITICAL FIX: Use FIXED filename "savegame" instead of player-specific names!
    // Why: gs.SAVEF (like "501Hero") is NOT persisted across app restarts.
    // After restart, gs.SAVEF is empty, causing restore to find wrong/old files.
    // Solution: Single fixed filename ensures we always load the latest save.
    char game_path[512];
    char game_temp_path[512];

    // Use fixed filename - iOS apps should only have ONE active save
    const char* savef_name = "savegame";
    SAVE_LOG("  Using fixed filename: %s", savef_name);

    // Build full paths for final and temp files
    int path_len = snprintf(game_path, sizeof(game_path), "%s/%s", save_dir, savef_name);
    if (path_len < 0 || path_len >= sizeof(game_path)) {
        SAVE_LOG("ERROR: Game path too long or formatting error");
        return -1;
    }
    path_len = snprintf(game_temp_path, sizeof(game_temp_path), "%s/%s.tmp", save_dir, savef_name);
    if (path_len < 0 || path_len >= sizeof(game_temp_path)) {
        SAVE_LOG("ERROR: Game temp path too long or formatting error");
        return -1;
    }

    SAVE_LOG("Step 3: Saving game state to temp file %s", game_temp_path);

    // Open temp save file directly (bypassing ios_create_savefile which hardcodes path)
    // This is based on ios_create_savefile() implementation but with our custom path
    NHFILE *nhfp = (NHFILE *) alloc(sizeof(NHFILE));
    if (!nhfp) {
        SAVE_LOG("ERROR: alloc failed for NHFILE!");
        return -1;
    }
    memset(nhfp, 0, sizeof(NHFILE));

    // Initialize NHFILE using NetHack's init function
    extern void init_nhfile(NHFILE *);
    init_nhfile(nhfp);

    // CRITICAL FIX: Initialize save file I/O procedures!
    // Without this, savegamestate() and savelev() write NOTHING (wcount=0)!
    extern void sf_init(void);
    sf_init();
    SAVE_LOG("  ✓ Save file I/O procedures initialized (sf_init)");

    // Configure for binary save file writing (matching ios_create_savefile)
    nhfp->ftype = NHF_SAVEFILE;
    nhfp->mode = COUNTING;  // CRITICAL FIX: Start with COUNTING pass
    nhfp->structlevel = TRUE;
    nhfp->fieldlevel = FALSE;
    nhfp->addinfo = FALSE;
    nhfp->style.deflt = FALSE;
    nhfp->style.binary = TRUE;
    nhfp->fnidx = historical;
    nhfp->fd = -1;
    nhfp->fpdef = (FILE *) 0;

    // CRITICAL FIX: Complete NHFILE initialization (missing fields from spec)
    nhfp->rcount = 0;      // Read byte counter
    nhfp->wcount = 0;      // Write byte counter
    nhfp->eof = FALSE;     // EOF flag
    nhfp->bendian = FALSE; // iOS/ARM is little-endian

    // Open the temp file for writing
    nhfp->fd = open(game_temp_path, O_WRONLY | O_CREAT | O_TRUNC, FCMASK);
    if (nhfp->fd < 0) {
        SAVE_LOG("ERROR: Failed to open temp save file! errno=%d (%s)", errno, strerror(errno));
        free(nhfp);
        return -1;
    }

    SAVE_LOG("  ✓ Save file opened successfully (fd=%d)", nhfp->fd);

    // CRITICAL FIX: Two-pass save system per NetHack spec
    // Pass 1: COUNTING - count objects/monsters without writing
    SAVE_LOG("Step 3a: Pass 1 - COUNTING mode");
    nhfp->mode = COUNTING;

    // Save ball/chain state if needed (must be set before both passes)
    gl.looseball = BALL_IN_MON ? uball : 0;
    gl.loosechain = CHAIN_IN_MON ? uchain : 0;

    // Count everything without writing
    // NOTE: store_version() calls store_critical_bytes() internally!
    store_version(nhfp);         // This writes format indicator + critical bytes
    store_plname_in_file(nhfp);
    savelev(nhfp, ledger_no(&u.uz));
    savegamestate(nhfp);

    SAVE_LOG("  ✓ Counting pass complete - rcount=%ld, wcount=%ld", nhfp->rcount, nhfp->wcount);

    // Reset file position for second pass
    lseek(nhfp->fd, 0, SEEK_SET);

    // Pass 2: WRITING - write data (NO FREEING on iOS!)
    // CRITICAL iOS FIX: DON'T use FREEING mode on iOS!
    // NetHack expects the process to exit after save (freeing memory is cleanup).
    // On iOS, the process stays alive for multiple saves.
    // If we free dungeon structures (svb.branches, svm.mapseenchn), the SECOND
    // save will crash trying to access freed memory!
    // This is the SAME issue as status_initialize() - static state persists between operations.
    SAVE_LOG("Step 3b: Pass 2 - WRITING mode (NO FREEING - iOS process persists!)");
    nhfp->mode = WRITING;
    nhfp->rcount = 0;
    nhfp->wcount = 0;

    // Now actually write everything
    store_version(nhfp);         // This writes format indicator + critical bytes + version
    store_plname_in_file(nhfp);
    savelev(nhfp, ledger_no(&u.uz));
    savegamestate(nhfp);

    SAVE_LOG("  ✓ Writing pass complete - wcount=%ld bytes written", nhfp->wcount);

    // CRITICAL: LEVEL CONSOLIDATION LOOP (dosave0:177-215)
    // We must save ALL visited levels to the save file, not just current level!
    // Without this, NetHack can't find level files when changing levels = TRICKED
    SAVE_LOG("Step 3c: Level consolidation - saving ALL visited levels");

    // RCA FIX 2025-12-30: Count timers BEFORE consolidation!
    // ========================================================================
    // ROOT CAUSE OF SECOND-LOAD CRASH:
    // - iOS uses WRITING mode WITHOUT FREEING to prevent dungeon crashes
    // - But without FREEING, save_timers() doesn't remove level timers
    // - During consolidation, getlev() calls restore_timers() which ADDS timers
    // - Timer ACCUMULATION: after N levels, gt.timer_base has N levels of timers!
    //
    // FIX: Count timers before consolidation. After consolidation, remove
    // excess timers (the ones added by getlev() calls). The current level
    // reload will restore proper timer state.
    // ========================================================================
    int timer_count_before = 0;
    {
        timer_element *t;
        for (t = gt.timer_base; t; t = t->next) timer_count_before++;
    }
    SAVE_LOG("Step 3c-pre: Timer count before consolidation: %d", timer_count_before);

    // Get level functions and globals from NetHack (matching extern.h signatures!)
    extern struct instance_globals_u gu;  // CRITICAL: Need gu for gu.uz_save
    extern xint16 maxledgerno(void);                   // Returns xint16 NOT xint8!
    extern xint16 ledger_no(d_level *);
    extern NHFILE *open_levelfile(int, char *);        // Takes int NOT xint8!
    extern void getlev(NHFILE *, int, xint8);
    extern void delete_levelfile(int);                 // Takes int NOT xint8!
    extern struct instance_globals_saved_l svl;
    extern struct instance_globals_saved_h svh;        // saved_h NOT just _h!

    // Zero out u.uz during consolidation (dosave0:177-183)
    gu.uz_save = u.uz;
    u.uz.dnum = u.uz.dlevel = 0;  // MUST be zero during level consolidation
    set_ustuck((struct monst *) 0);  // Clear engulf pointer
    u.usteed = (struct monst *) 0;   // Clear steed pointer

    // Loop through all levels and consolidate them into save file
    // RCA FIX 2025-12-27: Changed ltmp from xint8 to xint16 to prevent signed overflow
    // ROOT CAUSE: When maxledgerno() > 127, xint8 wraps to -128, causing 256 iterations
    // instead of expected ~10, resulting in 5MB bloated saves with garbage level data.
    // Vanilla NetHack has same bug (save.c:185) but maxledgerno() < 127 prevents trigger.
    // Debug logging added to diagnose iOS-specific high maxledgerno() values.
    xint16 max_ledger = maxledgerno();
    SAVE_LOG("DEBUG: maxledgerno() = %d (expect < 127, if > 127 investigate dungeon config)", max_ledger);
    for (xint16 ltmp = 1; ltmp <= max_ledger; ltmp++) {
        // Skip current level (already saved above)
        if (ltmp == ledger_no(&gu.uz_save)) {
            SAVE_LOG("  Level %d: Current level (already saved)", (int)ltmp);
            continue;
        }

        // Skip levels that don't exist (never visited)
        if (!(svl.level_info[ltmp].flags & LFILE_EXISTS)) {
            SAVE_LOG("  Level %d: Not visited (skipping)", (int)ltmp);
            continue;
        }

        SAVE_LOG("  Level %d: Loading from level file...", (int)ltmp);

        // Open the level file
        char whynot[256] = {0};  // Initialize to prevent garbage if open fails silently
        NHFILE *onhfp = open_levelfile(ltmp, whynot);
        if (!onhfp) {
            SAVE_LOG("ERROR: Failed to open level file %d: %s", (int)ltmp, whynot);
            close_nhfile(nhfp);
            unlink(game_temp_path);
            change_luck(flags.moonphase == FULL_MOON ? 1 : 0);
            change_luck(flags.friday13 ? -1 : 0);
            notice_mon_on();
            program_state.saving--;
            return -1;
        }

        // Load the level from disk
        getlev(onhfp, svh.hackpid, ltmp);
        close_nhfile(onhfp);
        SAVE_LOG("  Level %d: Loaded, saving to consolidated file...", (int)ltmp);

        // Write level number marker + level data to save file
        // CRITICAL: Must cast to xint8 for Sfo_xint8 - the format expects 8-bit level numbers
        xint8 ltmp8 = (xint8)ltmp;
        Sfo_xint8(nhfp, &ltmp8, "gamestate-level_number");
        savelev(nhfp, ltmp);

        // Delete the temporary level file (we've consolidated it)
        delete_levelfile(ltmp);
        SAVE_LOG("  Level %d: Consolidated and temp file deleted", (int)ltmp);
    }

    close_nhfile(nhfp);

    // RCA FIX 2025-12-30: Consolidation corrupts in-memory state!
    // ========================================================================
    // PROBLEM: Each getlev() during consolidation:
    //   1. Overwrites fobj/fmon with that level's objects/monsters
    //   2. Adds that level's timers to gt.timer_base
    // After consolidation, memory has WRONG level data and accumulated timers!
    //
    // FIX: Remove timers added during consolidation by truncating to original count.
    // Then reload current level to restore correct fobj/fmon/timers.
    // ========================================================================
    SAVE_LOG("Step 3c-post: Removing timers added during consolidation (iOS FIX)");
    {
        int timer_count_after = 0;
        timer_element *t;
        for (t = gt.timer_base; t; t = t->next) timer_count_after++;

        if (timer_count_after > timer_count_before) {
            int excess = timer_count_after - timer_count_before;
            SAVE_LOG("  Timer count after: %d (excess: %d)", timer_count_after, excess);

            // Remove excess timers from the END of the chain (they were added last)
            // Note: insert_timer() inserts based on timeout, so new timers may be
            // anywhere in the chain. But for consolidation, new timers typically
            // have timeouts in the future, so they tend to be at the end.
            // Safest approach: remove from the tail.
            timer_element *prev = NULL, *curr;
            int position = 0;

            for (curr = gt.timer_base; curr; prev = curr, curr = curr->next) {
                position++;
                if (position > timer_count_before) {
                    // Remove from here to end
                    if (prev)
                        prev->next = NULL;
                    else
                        gt.timer_base = NULL;

                    // Free remaining chain
                    timer_element *to_free;
                    while (curr) {
                        to_free = curr;
                        curr = curr->next;
                        free((genericptr_t) to_free);
                    }
                    break;
                }
            }
            SAVE_LOG("  ✓ Removed %d excess timers", excess);
        } else {
            SAVE_LOG("  No excess timers to remove");
        }
    }

    // Restore u.uz after consolidation (dosave0:218-219)
    u.uz = gu.uz_save;
    gu.uz_save.dnum = gu.uz_save.dlevel = 0;
    SAVE_LOG("✓ All levels consolidated into save file");

    // RCA FIX 2025-12-30: Restore current level from save file!
    // ========================================================================
    // The consolidation loop corrupted fobj/fmon by overwriting them with
    // the last consolidated level's data. We must reload the current level
    // to restore correct game state for continued iOS gameplay.
    // ========================================================================
    SAVE_LOG("Step 3d-post: Reloading current level from save file (iOS FIX)");
    {
        // Reopen the just-written save file
        NHFILE *reload_nhfp = (NHFILE *) alloc(sizeof(NHFILE));
        if (!reload_nhfp) {
            SAVE_LOG("ERROR: Failed to allocate NHFILE for reload!");
            // Continue anyway - game may be unstable but save succeeded
        } else {
            memset(reload_nhfp, 0, sizeof(NHFILE));
            extern void init_nhfile(NHFILE *);
            init_nhfile(reload_nhfp);

            // Open the temp file (not yet renamed to final)
            reload_nhfp->fd = open(game_temp_path, O_RDONLY, 0);
            if (reload_nhfp->fd < 0) {
                SAVE_LOG("ERROR: Failed to open temp file for reload! errno=%d", errno);
                free(reload_nhfp);
            } else {
                // Configure for reading
                reload_nhfp->ftype = NHF_SAVEFILE;
                reload_nhfp->mode = READING;
                reload_nhfp->structlevel = TRUE;
                reload_nhfp->fieldlevel = FALSE;
                reload_nhfp->addinfo = FALSE;
                reload_nhfp->style.deflt = FALSE;
                reload_nhfp->style.binary = TRUE;
                reload_nhfp->fnidx = historical;

                // Skip version header using uptodate()
                // uptodate() reads and validates version info, returning 1 if valid
                extern int uptodate(NHFILE *, const char *, unsigned long);
                if (!uptodate(reload_nhfp, "save file", UTD_CHECKSIZES)) {
                    SAVE_LOG("ERROR: Failed to validate save file for reload!");
                    close_nhfile(reload_nhfp);
                } else {
                    // Skip player name
                    extern void get_plname_from_file(NHFILE *, char *, boolean);
                    char plname_buf[PL_NSIZ + 1];
                    get_plname_from_file(reload_nhfp, plname_buf, TRUE);

                    // Reload current level
                    // Note: getlev() will call relink_timers() which is fine since
                    // we just cleared accumulated timers above.
                    // The level number for getlev() is 0 for "current" level in save
                    // format (save file stores current level first, with lev=0 marker)
                    extern xint16 ledger_no(d_level *);
                    xint8 curr_lev = (xint8) ledger_no(&u.uz);
                    getlev(reload_nhfp, 0, curr_lev);

                    SAVE_LOG("  ✓ Current level reloaded from save file");
                    close_nhfile(reload_nhfp);
                }
            }
        }
    }

    // Step 4: Verify temp file exists and is valid
    if (access(game_temp_path, F_OK) != 0) {
        SAVE_LOG("ERROR: Temp file verification failed!");
        unlink(game_temp_path);
        change_luck(flags.moonphase == FULL_MOON ? 1 : 0);
        change_luck(flags.friday13 ? -1 : 0);
        notice_mon_on();
        program_state.saving--;
        return -1;
    }

    // Step 5: VERSIONED BACKUP - Keep old saves for debugging
    SAVE_LOG("Step 5: Creating versioned backup of previous save");

    // Check if previous save exists, and if so, create a versioned backup
    if (access(game_path, F_OK) == 0) {
        // Create versioned backup path: savegame.v001, savegame.v002, etc.
        char backup_path[512];
        save_version_counter++;
        snprintf(backup_path, sizeof(backup_path), "%s.v%03d_L%d",
                 game_path, save_version_counter % MAX_VERSIONED_SAVES, u.uz.dlevel);

        if (copy_file(game_path, backup_path) == 0) {
            SAVE_LOG("  ✓ Backed up previous save to: %s", backup_path);

            // Also log the save file size for debugging
            struct stat st;
            if (stat(backup_path, &st) == 0) {
                SAVE_LOG("  📦 Backup size: %lld bytes", (long long)st.st_size);
            }
        } else {
            SAVE_LOG("  ⚠️ Failed to backup previous save (continuing anyway)");
        }
    } else {
        SAVE_LOG("  ℹ️ No previous save to backup (first save)");
    }

    // Also backup the NEW temp file we're about to commit
    char new_backup_path[512];
    snprintf(new_backup_path, sizeof(new_backup_path), "%s.v%03d_L%d_NEW",
             game_path, save_version_counter % MAX_VERSIONED_SAVES, u.uz.dlevel);
    if (copy_file(game_temp_path, new_backup_path) == 0) {
        struct stat st;
        if (stat(new_backup_path, &st) == 0) {
            SAVE_LOG("  📦 NEW save backup: %s (%lld bytes)", new_backup_path, (long long)st.st_size);
        }
    }

    // Step 6: ATOMIC RENAME - Make save file valid
    SAVE_LOG("Step 6: Performing atomic rename of game save file");

    // Rename game.sav.tmp -> game.sav (atomic operation)
    if (rename(game_temp_path, game_path) != 0) {
        SAVE_LOG("ERROR: Failed to rename game temp file! errno=%d (%s)", errno, strerror(errno));
        unlink(game_temp_path);
        change_luck(flags.moonphase == FULL_MOON ? 1 : 0);
        change_luck(flags.friday13 ? -1 : 0);
        notice_mon_on();
        program_state.saving--;
        return -1;
    }
    SAVE_LOG("  ✓ Game file atomically renamed");
    SAVE_LOG("✓ ATOMIC SAVE COMPLETE - Save file committed");

    // PHASE 4: Post-save cleanup (matching dosave0 end)
    SAVE_LOG("PHASE 4: Post-save cleanup");

    // Restore date-dependent luck adjustments
    SAVE_LOG("  Restoring luck adjustments");
    if (flags.moonphase == FULL_MOON)
        change_luck(1);
    if (flags.friday13)
        change_luck(-1);

    // Re-enable monster notifications
    notice_mon_on();

    // Decrement saving flag
    program_state.saving--;

    SAVE_LOG("✓ SAVE COMPLETE - Game state saved (no memory.dat needed!)");
    SAVE_LOG("  Game: %s", game_path);
    SAVE_LOG("==========================================");

    return 0;
}

/*
 * COMPLETE RESTORE FUNCTION
 * Restores memory state THEN game state in the CORRECT order
 */
NETHACK_EXPORT int ios_restore_complete(const char* save_dir) {
    CRASH_CHECKPOINT("ios_restore_complete_start");
    SAVE_LOG("========== COMPLETE RESTORE INITIATED ==========");

    if (!save_dir) {
        SAVE_LOG("ERROR: No save directory specified");
        return -1;
    }

    // CRITICAL: Reset exit flags FIRST!
    // Prevents stale exit state from previous session blocking the restored game
    SAVE_LOG("PHASE -1: Clear stale exit flags from previous session");
    extern void ios_reset_game_exit(void);  // Resets game_should_exit flag
    ios_reset_game_exit();
    extern struct sinfo program_state;
    program_state.gameover = 0;
    SAVE_LOG("  ✓ Exit flags cleared - ready for clean game restart");

    // CRITICAL: Correct initialization order for clean restore:
    // 1. Clear/Reset memory allocator - Start fresh!
    // 2. Initialize Lua subsystem
    // 3. Initialize window system
    // 4. Restore game state (NetHack will allocate as needed)

    // PHASE 0: Pre-restore setup
    SAVE_LOG("PHASE 0: Pre-restore setup");

    // Turn off monster notifications during restore
    notice_mon_off();
    SAVE_LOG("  ✓ Monster notifications suppressed");

    // Step 1: Reset memory allocator - NO loading of memory.dat!
    // NetHack's save format properly serializes everything.
    // Starting with a clean heap avoids ASLR pointer corruption!
    SAVE_LOG("Step 1: Resetting memory allocator (fresh heap, no memory.dat)");
    extern void nh_restart(void);
    nh_restart();  // Clear heap, ready for NetHack to allocate
    SAVE_LOG("✓ Memory allocator reset - clean heap ready");

    // Step 1a: CRITICAL - Clear command queue pointers after nh_restart()!
    // nh_restart() invalidates ALL allocated memory, but gc.command_queue[]
    // pointers are not automatically reset. They still point to memory from
    // BEFORE the restore, causing "Invalid magic" crash when cmdq_clear()
    // tries to free() them during the first move command!
    SAVE_LOG("Step 1a: Clearing command queue pointers (CRITICAL for first move!)");
    extern struct instance_globals_c gc;
    for (int i = 0; i < NUM_CQS; i++) {
        gc.command_queue[i] = NULL;
    }
    SAVE_LOG("✓ Command queue pointers cleared - safe for cmdq_clear()");

    // Step 1a1b: CRITICAL - Initialize current_fruit to prevent "Bad fruit #0?" error!
    // ROOT CAUSE: nh_restart() memsets heap to 0, including svc.context.current_fruit.
    // If ANY code creates SLIME_MOLD objects before restgamestate() runs, they get spe=0.
    // When fruit_from_indx(0) is called, it returns NULL causing "Bad fruit #0?" error.
    // FIX: Initialize current_fruit to 1 (valid fruit ID) as a defensive measure.
    // restgamestate() will overwrite this with the actual value from the save file.
    SAVE_LOG("Step 1a1b: Initializing current_fruit to prevent Bad fruit #0 error");
    svc.context.current_fruit = 1;  // Valid fruit ID (IDs start at 1, never 0)
    SAVE_LOG("  ✓ svc.context.current_fruit = 1 (defensive initialization)");

    // Step 1a2: CRITICAL - Clear ALL transient global pointers after nh_restart()!
    // nh_restart() invalidates memory, but many globals still point to old addresses.
    // This causes RANDOM crashes when these pointers are dereferenced.
    SAVE_LOG("Step 1a2: Clearing transient global pointers (PREVENTS RANDOM CRASHES!)");

    // Declare all instance_globals we need
    extern struct instance_globals_a ga;
    extern struct instance_globals_b gb;
    extern struct instance_globals_g gg;
    extern struct instance_globals_i gi;
    extern struct instance_globals_k gk;
    extern struct instance_globals_l gl;
    extern struct instance_globals_m gm;
    extern struct instance_globals_n gn;
    extern struct instance_globals_o go;
    extern struct instance_globals_p gp;
    extern struct instance_globals_t gt;
    extern struct instance_globals_w gw;
    extern struct instance_globals_x gx;
    extern struct instance_globals_y gy;
    extern struct instance_globals_saved_l svl;

    // MOST CRITICAL: gi.itermonarr - Used by iter_mons_safe()
    // This is what causes the random crashes during monster movement!
    gi.itermonarr = NULL;
    SAVE_LOG("  ✓ gi.itermonarr cleared (iter_mons_safe crash fix)");

    // Transient combat state pointers
    gb.buzzer = NULL;           // Current zapper/caster
    gm.mswallower = NULL;       // Gas spore swallower
    gm.mtarget = NULL;          // Monster being shot at
    gm.marcher = NULL;          // Monster doing the shooting

    // Transient gameplay state
    gc.current_wand = NULL;     // Wand being applied
    gc.current_container = NULL; // Container being looted
    gk.kickedobj = NULL;        // Object in flight from kick
    gt.thrownobj = NULL;        // Object in flight from throw
    gp.propellor = NULL;        // Projectile weapon

    // Runtime allocated lists (not from save)
    ga.apelist = NULL;          // Autopickup exceptions
    ga.animal_list = NULL;      // Animal monster cache
    gm.menu_colorings = NULL;   // Menu colorings
    gm.mydogs = NULL;           // Temporary pet list
    gm.maploc = NULL;           // Kick map location

    // Lua/Level generation state
    for (int i = 0; i < MAXDUNGEON; i++) {
        gl.luathemes[i] = NULL; // Lua theme handles
    }
    gl.lregions = NULL;         // Level regions
    gn.new_locations = NULL;    // Map generation buffer

    // Transient object state
    go.objs_deleted = NULL;     // Deleted objects list
    go.otg_otmp = NULL;         // object_to_glyph temp
    go.oldfruit = NULL;         // Bones fruit translation

    // UI/Display buffers
    // TODO ARCHITECTURAL: These buffers are shared between threads which violates Go's principle:
    //      "Share by communicating, not by sharing memory"
    //      Long-term fix: Replace with message queue (like input_queue) for C→Swift communication
    //      See: https://go.dev/blog/codelab-share - this is a TEMPORARY band-aid!
    gi.invbuf = NULL;           // Inventory buffer
    gi.invbufsiz = 0;           // CRITICAL: Reset size to prevent segfault when buffer reallocated
    gx.xnamep = NULL;           // Object name buffer
    gy.you_buf = NULL;          // Message buffer
    gy.you_buf_siz = 0;         // CRITICAL: Reset size to prevent segfault when buffer reallocated
    gl.last_winchoice = NULL;   // Window choice cache
    gg.gloc_filter_map = NULL;  // Location filter

    // Temporary save/restore state
    gl.looseball = NULL;        // Ball during save
    gl.loosechain = NULL;       // Chain during save
    gc.coder = NULL;            // Sp_lev compiler state
    gw.wportal = NULL;          // Maze portal

    // Clear level.monsters[][] grid (will be repopulated by getlev())
    for (int x = 0; x < COLNO; x++) {
        for (int y = 0; y < ROWNO; y++) {
            svl.level.monsters[x][y] = NULL;
        }
    }

    SAVE_LOG("✓ All transient global pointers cleared (random crashes prevented)");

    // Step 1a3: CRITICAL - Clear ALL worn item pointers after nh_restart()!
    // ROOT CAUSE OF SECOND RESTORE BUG: These pointers still reference memory
    // from the FIRST game, which was invalidated by nh_restart(). When setworn()
    // is called during restore, it dereferences these stale pointers (worn.c:86),
    // corrupting memory and causing "Invalid magic" errors.
    SAVE_LOG("Step 1a3: Clearing worn item pointers (FIXES SECOND RESTORE CORRUPTION!)");

    // Worn item pointers defined in decl.h:94-98
    extern struct obj *uarm, *uarmc, *uarmh, *uarms, *uarmg, *uarmf, *uarmu;
    extern struct obj *uwep, *uswapwep, *uquiver;
    extern struct obj *uleft, *uright, *uamul, *ublindf;
    extern struct obj *uball, *uchain;
    extern struct obj *uskin;  // Dragon scales when polymorphed

    // Clear ALL worn item pointers - prevents setworn() from dereferencing stale memory
    uarm = NULL;     // W_ARM: Suit
    uarmc = NULL;    // W_ARMC: Cloak
    uarmh = NULL;    // W_ARMH: Helmet (causes "Setworn: mask=0x00000100" on second restore)
    uarms = NULL;    // W_ARMS: Shield (causes "Setworn: mask=0x00000400" on second restore)
    uarmg = NULL;    // W_ARMG: Gloves
    uarmf = NULL;    // W_ARMF: Boots
    uarmu = NULL;    // W_ARMU: Shirt
    uwep = NULL;     // W_WEP: Weapon
    uswapwep = NULL; // W_SWAPWEP: Alternate weapon
    uquiver = NULL;  // W_QUIVER: Quiver
    uleft = NULL;    // W_RINGL: Left ring
    uright = NULL;   // W_RINGR: Right ring
    uamul = NULL;    // W_AMUL: Amulet
    ublindf = NULL;  // W_TOOL: Blindfold/towel/lenses
    uball = NULL;    // W_BALL: Chained ball
    uchain = NULL;   // W_CHAIN: Chain
    uskin = NULL;    // Dragon scales (polymorphed form)

    SAVE_LOG("  ✓ All 17 worn item pointers cleared - setworn() can now safely restore");

    // Step 1a4: CRITICAL - Clear dynamically allocated pointers in SAVED globals!
    // ROOT CAUSE OF TIMER CRASH: rot_organic() accesses level data freed during getlev()
    // svd.doors and other pointers reference memory from FIRST game.
    // getlev() calls free() on these, causing crashes in run_timers().
    SAVE_LOG("Step 1a4: Clearing saved globals with dynamic allocations (CRITICAL!)");

    // Declare saved globals that need clearing
    extern struct instance_globals_saved_d svd;
    extern struct instance_globals_saved_s svs;
    extern struct instance_globals_saved_l svl;
    extern struct instance_globals_f gf;
    extern struct instance_globals_o go;

    // svd.doors - freed in getlev() at restore.c:1111
    svd.doors = NULL;
    svd.doors_alloc = 0;
    SAVE_LOG("  ✓ svd.doors cleared (prevents getlev free crash)");

    // svl.level.bonesinfo - freed in restcemetery()
    svl.level.bonesinfo = NULL;

    // svl.level.damagelist - freed in restdamage()
    svl.level.damagelist = NULL;

    // svs.sp_levchn - freed in restlevchn()
    svs.sp_levchn = NULL;

    // gf.ffruit - freed in restgamestate() at restore.c:709
    gf.ffruit = NULL;

    // go.oldfruit - freed in getlev() for ghostly levels
    go.oldfruit = NULL;

    SAVE_LOG("  ✓ All saved globals with dynamic allocations cleared");

    // Step 1a4b: CRITICAL - Clear timer chain (gt.timer_base)!
    // ROOT CAUSE OF rot_organic() CRASH: Timers persist across nh_restart()!
    // The timer's arg.a_obj points to OLD objects from FIRST game.
    // When run_timers() fires, rot_organic() dereferences obj->cobj (contained objects)
    // which points to FREED/INVALID memory from before nh_restart()!
    // This is why svd.doors fix wasn't enough - timers are a SEPARATE chain!
    SAVE_LOG("Step 1a4b: Clearing timer chain (FIXES rot_organic crash!)");
    gt.timer_base = NULL;
    SAVE_LOG("  ✓ gt.timer_base cleared - timers won't access stale object pointers");

    // Step 1a4c: CRITICAL - Clear stairs chain (gs.stairs)!
    // ROOT CAUSE OF stairway_at() CRASH: Stairs persist across nh_restart()!
    // stairway_at() iterates gs.stairs linked list to check if coordinates have stairs.
    // After nh_restart(), gs.stairs still points to OLD stairway structs from FIRST game.
    // When On_stairs() → stairway_at() runs, it dereferences stale pointers!
    // This is the SAME pattern as gt.timer_base - another persisting chain!
    SAVE_LOG("Step 1a4c: Clearing stairs chain (FIXES stairway_at crash!)");
    gs.stairs = NULL;
    SAVE_LOG("  ✓ gs.stairs cleared - stairway_at() won't access stale pointers");

    // Step 1a4d: CRITICAL - Clear gamelog chain (gg.gamelog)!
    // ROOT CAUSE OF save_gamelog() CRASH: Gamelog persists across nh_restart()!
    // save_gamelog() iterates gg.gamelog linked list to save message history.
    // After nh_restart(), gg.gamelog still points to OLD gamelog_line structs from FIRST game.
    // Those structs were freed during first game's save (FREEING mode in save.c:251).
    // When SECOND save runs, save_gamelog() tries to iterate the freed chain:
    //   save.c:239: tmp = gg.gamelog
    //   save.c:245: slen = Strlen(tmp->text) ← CRASH! tmp->text is freed memory!
    // This is the THIRD instance of this bug pattern (after timer_base and stairs).
    SAVE_LOG("Step 1a4d: Clearing gamelog chain (FIXES save_gamelog crash!)");
    gg.gamelog = NULL;
    SAVE_LOG("  ✓ gg.gamelog cleared - save_gamelog() won't access stale pointers");

    // Step 1a5: Clear main object/monster chains (prevents invalid magic)
    SAVE_LOG("Step 1a5: Clearing main object/monster chains");

    // fobj and fmon are MACROS that expand to svl.level.objlist/monlist
    // So we can directly access them after svl is declared
    svl.level.objlist = NULL;   // fobj macro
    svl.level.monlist = NULL;   // fmon macro

    gi.invent = NULL;
    gm.migrating_objs = NULL;
    gm.migrating_mons = NULL;

    gb.billobjs = NULL;

    svl.level.buriedobjlist = NULL;

    SAVE_LOG("  ✓ Object/monster chains cleared");

    // Step 1b: CRITICAL - Reinitialize file prefixes after nh_restart()!
    // nh_restart() clears gf.fqn_prefix[], so NetHack can't find Level files!
    // Without this, level changes fail with "1lock.0 missing" and game ends!
    SAVE_LOG("Step 1b: Reinitializing file prefixes (CRITICAL for level changes!)");
    extern void ios_init_file_prefixes(void);
    ios_init_file_prefixes();
    SAVE_LOG("✓ File prefixes reinitialized - NetHack can create level files");

    // Step 2: Initialize Lua subsystem FIRST (before init_dungeons)!
    // CRITICAL ORDER: l_nhcore_init() must come BEFORE init_dungeons()!
    // Why: init_dungeons() creates and destroys a PRIVATE Lua state at the end (nhl_done()).
    // If we call it after l_nhcore_init(), it can corrupt the global Lua state!
    // This matches the order in newgame() at allmain.c:773-780.
    SAVE_LOG("Step 2: Initializing Lua subsystem (MUST BE BEFORE init_dungeons!)");
    l_nhcore_init();
    SAVE_LOG("✓ Lua initialized");

    // NOTE: We do NOT call init_dungeons() during restore!
    // restore_dungeon() (called by restgamestate()) loads the dungeon structures
    // from the save file, including the stairway registry. init_dungeons() is only
    // needed for NEW games to parse dungeon.lua and create initial structures.
    // Calling it during restore would:
    // 1. Waste time re-parsing dungeon.lua
    // 2. Create/destroy a private Lua state unnecessarily
    // 3. Potentially overwrite restored dungeon data
    SAVE_LOG("Step 2b: Skipping init_dungeons() - restore_dungeon() will handle it");

    // Step 2b: CRITICAL - Initialize window system!
    // This MUST be done BEFORE docrt() is called
    // Without this, g_render_queue is NULL and map rendering fails!
    SAVE_LOG("Step 2b: Initializing window system (init_ios_windowprocs + init_nhwindows)");
    extern void init_ios_windowprocs(void);
    init_ios_windowprocs();  // Sets windowprocs = ios_procs

    // CRITICAL FIX: Actually call init_nhwindows() to allocate g_render_queue!
    // init_ios_windowprocs() only sets the function pointers, it does NOT initialize!
    // We MUST call init_nhwindows() macro which calls ios_init_nhwindows()
    // This allocates g_render_queue and initializes the render system.
    int dummy_argc = 0;
    char *dummy_argv[] = { NULL };
    init_nhwindows(&dummy_argc, dummy_argv);  // Allocates g_render_queue!
    SAVE_LOG("✓ Window system initialized with render queue");

    // Step 2b2: Apply iOS symbol overrides after restore!
    // ios_setup_default_symbols() will call init_symbols() if needed
    // to ensure symbol arrays are populated after nh_restart()
    SAVE_LOG("Step 2b2: Applying iOS symbol overrides");
    extern void ios_setup_default_symbols(void);
    ios_setup_default_symbols();
    SAVE_LOG("  ✓ iOS symbol overrides applied");

    // Step 2c: CRITICAL - Create game windows!
    // Without this, WIN_MAP remains -1 and print_glyph() rejects all tiles!
    // CRITICAL ORDER: Must match static winid declarations in ios_winprocs.c!
    // message_win=1, map_win=2, status_win=3, menu_win=4
    SAVE_LOG("Step 2c: Creating game windows (matching ios_newgame.c)");
    extern winid WIN_MESSAGE, WIN_STATUS, WIN_MAP, WIN_INVEN;
    WIN_MESSAGE = create_nhwindow(NHW_MESSAGE);  // Should return 1
    WIN_MAP = create_nhwindow(NHW_MAP);          // Should return 2
    WIN_STATUS = create_nhwindow(NHW_STATUS);    // Should return 3
    WIN_INVEN = create_nhwindow(NHW_MENU);       // Should return 4
    SAVE_LOG("✓ Windows created (MESSAGE=%d, MAP=%d, STATUS=%d, INVEN=%d)",
             WIN_MESSAGE, WIN_MAP, WIN_STATUS, WIN_INVEN);

    // Step 3: Restore game state
    // CRITICAL: gs.SAVEF is not set after app restart! We need to find the actual save file
    extern struct instance_globals_s gs;
    char game_path[512];

    // CRITICAL FIX: Use FIXED filename "savegame" (same as save function!)
    // No more searching for random files - we know exactly where the save is.
    const char* savef_name = "savegame";
    SAVE_LOG("  Using fixed filename: %s", savef_name);

    // Build full path to the save file
    int path_len = snprintf(game_path, sizeof(game_path), "%s/%s", save_dir, savef_name);
    if (path_len < 0 || path_len >= sizeof(game_path)) {
        SAVE_LOG("ERROR: Game path too long or formatting error");
        return -1;
    }

    SAVE_LOG("Step 3: Restoring game state from %s", game_path);

    // Open save file directly (bypassing ios_open_savefile which hardcodes path)
    // This is based on ios_open_savefile() implementation but with our custom path
    NHFILE *nhfp = (NHFILE *) alloc(sizeof(NHFILE));
    if (!nhfp) {
        SAVE_LOG("ERROR: alloc failed for NHFILE!");
        return -1;
    }
    memset(nhfp, 0, sizeof(NHFILE));

    // Initialize NHFILE using NetHack's init function
    extern void init_nhfile(NHFILE *);
    init_nhfile(nhfp);

    // CRITICAL FIX: Initialize save file I/O procedures for READING! (Bug #2)
    // Without this, Sfi_* functions (used in getlev, restgamestate) won't work!
    // This is asymmetric with save which calls sf_init() at line 214-216.
    extern void sf_init(void);
    sf_init();
    SAVE_LOG("  ✓ Save file I/O procedures initialized for reading");

    // Configure for binary save file reading (matching ios_open_savefile)
    nhfp->ftype = NHF_SAVEFILE;
    nhfp->mode = READING;
    nhfp->structlevel = TRUE;
    nhfp->fieldlevel = FALSE;
    nhfp->addinfo = FALSE;
    nhfp->style.deflt = FALSE;
    nhfp->style.binary = TRUE;
    nhfp->fnidx = historical;
    nhfp->fd = -1;
    nhfp->fpdef = (FILE *) 0;

    // CRITICAL FIX: Complete NHFILE initialization (missing fields from spec)
    nhfp->rcount = 0;      // Read byte counter
    nhfp->wcount = 0;      // Write byte counter
    nhfp->eof = FALSE;     // EOF flag
    nhfp->bendian = FALSE; // iOS/ARM is little-endian

    // Open the file for reading using open() (fd is used by mread/bwrite!)
    // CRITICAL FIX: Sfi_* macros use nhfp->fd via mread(), NOT nhfp->fpdef!
    // Using fopen()/fseek() doesn't work because FILE* and fd have SEPARATE file positions.
    nhfp->fd = open(game_path, O_RDONLY, 0);
    if (nhfp->fd < 0) {
        SAVE_LOG("ERROR: Failed to open save file! errno=%d (%s)", errno, strerror(errno));
        free(nhfp);
        return -1;
    }

    SAVE_LOG("  ✓ Save file opened successfully (fd=%d)", nhfp->fd);

    // iOS FIX: Skip version header using RAW file I/O (bypassing NHFILE completely)
    // WHY RAW I/O: sfiprocs[] may not be initialized before NetHack core starts
    // WHY SKIP: uptodate() needs initialized globals (critical_sizes[], window system)
    // WHY SAFE: We control both save & load, version/arch can't change (same iOS app)
    //
    // Version header structure (from version.c:uptodate):
    //   1 byte:  format indicator
    //   1 byte:  critical_sizes count (N)
    //   N bytes: critical_sizes array
    //   sizeof(struct version_info): version info struct
    //
    SAVE_LOG("Step 3a: Skipping version header using raw I/O");

    unsigned char header_buf[512];  // Large enough for any version header
    ssize_t header_read = read(nhfp->fd, header_buf, sizeof(header_buf));
    if (header_read < 3) {
        SAVE_LOG("ERROR: Failed to read version header!");
        close(nhfp->fd);
        free(nhfp);
        return -1;
    }

    // Parse header to find where game data starts
    unsigned char format_indicator = header_buf[0];
    unsigned char csc_count = header_buf[1];
    SAVE_LOG("  Format indicator: %d", (int)format_indicator);
    SAVE_LOG("  Critical sizes count: %d", (int)csc_count);

    // Calculate total header size
    // 1 (indicator) + 1 (count) + csc_count (array) + sizeof(version_info)
    size_t version_info_size = sizeof(struct version_info);
    size_t total_header_size = 1 + 1 + csc_count + version_info_size;

    SAVE_LOG("  Total header size: %zu bytes (1+1+%d+%zu)",
             total_header_size, (int)csc_count, version_info_size);

    // Seek to start of actual game data (after header)
    if (lseek(nhfp->fd, (off_t)total_header_size, SEEK_SET) == -1) {
        SAVE_LOG("ERROR: Failed to seek past header! errno=%d", errno);
        close(nhfp->fd);
        free(nhfp);
        return -1;
    }

    SAVE_LOG("  ✓ Version header skipped");
    SAVE_LOG("  ✓ File positioned at game data start");

    // File position is now correctly positioned for get_plname_from_file()

    // Step 3b: Read player name
    SAVE_LOG("Step 3b: Reading player name from save");
    char plname_buf[PL_NSIZ_PLUS];
    extern void get_plname_from_file(NHFILE *, char *, boolean);
    get_plname_from_file(nhfp, plname_buf, TRUE);
    SAVE_LOG("  ✓ Player name: %s", plname_buf);

    // FIX: Copy loaded name to global player name variable
    // Without this, ios_askname() will set default "Hero" because svp.plname is empty
    extern struct instance_globals_saved_p svp;
    Strcpy(svp.plname, plname_buf);
    SAVE_LOG("  ✓ Copied to svp.plname: %s", svp.plname);

    // CRITICAL: Initialize status system BEFORE any level loading or restore
    // (restgamestate calls set_uasmon which requires status to be initialized)
    SAVE_LOG("Step 3c: Status system initialization check");

    // FIX for "init_blstats called more than once" error:
    // NetHack's status system uses static flags that persist between games.
    // When loading a save after playing a game, these flags are still TRUE:
    //   - static boolean initalready in init_blstats() (botl.c:1509)
    //   - gb.blinit in status_initialize() (botl.c:1447)
    //
    // NetHack expects the process to exit between games (resetting statics),
    // but iOS apps keep running. We must handle this carefully.
    //
    // Solution: Only initialize if not already initialized.
    // The status system persists between saves and that's OK - we just
    // need to avoid double initialization.
    extern struct instance_globals_b gb;
    extern void status_initialize(boolean);
    extern void status_finish(void);

    if (!gb.blinit) {
        // First load after app start - full status initialization required
        SAVE_LOG("  Status not initialized - calling status_initialize(FALSE)");
        status_initialize(FALSE);  // Full init, sets gb.blinit = TRUE
        SAVE_LOG("  ✓ Status system fully initialized");
    } else {
        // Subsequent restore - MUST refresh status for NEW game state!
        // CRITICAL FIX: We cannot SKIP status_initialize()!
        // The status system is in a STALE state from the previous game.
        //
        // NetHack provides REASSESS_ONLY mode exactly for this scenario:
        // "reassess status fields without re-initializing base structures"
        // Used in: polyself.c:123, options.c:5333,5371
        //
        // This refreshes status WITHOUT calling init_blstats() again,
        // preventing "init_blstats called more than once" error while
        // properly initializing status for inventory validation (Setworn).
        SAVE_LOG("  Status already initialized (gb.blinit=TRUE) - refreshing for new game");
        status_initialize(REASSESS_ONLY);  // Refresh status fields without re-init
        SAVE_LOG("  ✓ Status refreshed with REASSESS_ONLY");
    }

    // CRITICAL: Initialize vision system BEFORE getlev()!
    // From vision.c:117: "This must be called before mklev() is called in newgame(),
    // or before a game restore. Else we die a horrible death."
    // getlev() -> place_object() -> block_point() accesses gv.viz_array which is
    // allocated by vision_init(). Without this, we crash in block_point()!
    SAVE_LOG("Step 3c2: Initializing vision system (BEFORE getlev!)");
    extern void vision_init(void);
    vision_init();
    SAVE_LOG("  ✓ Vision system initialized (gv.viz_array allocated)");

    // CRITICAL: Set flags to suppress UI/vision updates during ALL restore operations
    // MUST be set BEFORE the first getlev() call!
    SAVE_LOG("Step 3d: Setting restore flags");
    program_state.restoring = REST_GSTATE;
    program_state.in_getlev = TRUE;  // Suppress vision_recalc during getlev() calls
    SAVE_LOG("  ✓ Restore flags set (restoring=%d, in_getlev=%d)",
             program_state.restoring, program_state.in_getlev);

    // Step 3e: Read current level FIRST!
    // CORRECT ORDER per NetHack's restore.c:790-805:
    //   1. get_plname_from_file()  - done above
    //   2. getlev()                - current level BEFORE game state!
    //   3. restgamestate()         - game state AFTER level
    //
    // Save file format is: version → plname → level → gamestate (NOT gamestate → level!)
    SAVE_LOG("Step 3e: Reading current level (BEFORE restgamestate per NetHack source!)");
    CRASH_CHECKPOINT("before_getlev");
    extern void getlev(NHFILE *, int, xint8);
    getlev(nhfp, 0, (xint8) 0);
    SAVE_LOG("  ✓ Current level restored");

    // Step 3f: NOW restore game state (file positioned after level data)
    SAVE_LOG("Step 3f: Restoring game state (AFTER level loading per NetHack source!)");
    CRASH_CHECKPOINT("before_restgamestate");

    // CRITICAL FIX: Bypass UID check in restgamestate()!
    // On iOS, getuid() returns different values between app launches due to
    // sandboxing. The save file has the old UID, current getuid() is different.
    // Setting converted_savefile_loaded=TRUE makes the UID mismatch non-fatal.
    gc.converted_savefile_loaded = TRUE;
    SAVE_LOG("  ✓ Set converted_savefile_loaded=TRUE to bypass UID check");

    // DEBUG: Verify NHFILE state before restgamestate
    SAVE_LOG("  DEBUG: nhfp=%p, fd=%d, fpdef=%p, mode=%d",
             (void*)nhfp, nhfp->fd, (void*)nhfp->fpdef, nhfp->mode);
    SAVE_LOG("  DEBUG: About to call restgamestate()...");
    fflush(stderr);  // CRITICAL: Ensure log is visible before potential crash

    if (!restgamestate(nhfp)) {
        SAVE_LOG("ERROR: Failed to restore game state!");
        program_state.restoring = 0;
        program_state.in_getlev = FALSE;
        close_nhfile(nhfp);
        return -1;
    }

    SAVE_LOG("✓ Game state restored successfully");

    // CRITICAL FIX 2025-12-31: Restore player name after restgamestate()!
    // ROOT CAUSE: restgamestate() → set_playmode() overwrites svp.plname to "wizard"
    // when wizard mode is active (options.c:12830). This corrupts the save file
    // because the next save uses the wrong player name.
    // FIX: plname_buf holds the correct name from the save file. Restore it now.
    if (strcmp(svp.plname, plname_buf) != 0) {
        SAVE_LOG("  ⚠️ Player name was changed by restgamestate(): '%s' → restoring to '%s'",
                 svp.plname, plname_buf);
        Strcpy(svp.plname, plname_buf);
        gp.plnamelen = (int) strlen(svp.plname);
        SAVE_LOG("  ✓ Player name restored: '%s' (len=%d)", svp.plname, gp.plnamelen);
    }

    // Step 3f2: Initialize object class probabilities
    SAVE_LOG("Step 3f2: Initializing object class probabilities");
    CRASH_CHECKPOINT("before_init_oclass_probs");
    init_oclass_probs();
    SAVE_LOG("  ✓ Object class probabilities initialized");

    // DEBUG: Check if stairs were loaded
    {
        extern struct instance_globals_s gs;
        stairway *stw = gs.stairs;
        int stair_count = 0;
        SAVE_LOG("  DEBUG: Checking gs.stairs after getlev()...");
        while (stw) {
            SAVE_LOG("    Stair #%d: (%d,%d) %s %s, tolev=%d,%d",
                     stair_count + 1,
                     stw->sx, stw->sy,
                     stw->up ? "UP" : "DOWN",
                     stw->isladder ? "ladder" : "stairs",
                     stw->tolev.dnum, stw->tolev.dlevel);
            stair_count++;
            stw = stw->next;
        }
        SAVE_LOG("  DEBUG: Total %d stairs loaded from save", stair_count);
    }

    // CRITICAL FIX: Re-establish worn item pointers IMMEDIATELY after restgamestate!
    // ROOT CAUSE: restgamestate() loads inventory objects with owornmask bits set,
    // but does NOT call setworn() to link them to worn item pointers (uarm, uarmh, uwep, etc.)
    // This is the EXACT loop from NetHack's restore.c:679-681.
    // MUST happen AFTER restgamestate() (which loads inventory) but BEFORE game logic runs.
    SAVE_LOG("Step 3f3: Re-establishing worn item pointers (CRITICAL!)");
    SAVE_LOG("  This loop links inventory objects to worn slots (uarm, uarmh, uwep, etc.)");

    struct obj *otmp;
    for (otmp = gi.invent; otmp; otmp = otmp->nobj) {
        if (otmp->owornmask) {
            setworn(otmp, otmp->owornmask);
            SAVE_LOG("  ✓ Set worn: %s (mask=0x%08lx)",
                     otmp->otyp ? OBJ_NAME(objects[otmp->otyp]) : "unknown",
                     (unsigned long)otmp->owornmask);
        }
    }
    SAVE_LOG("  ✓ Worn item pointers re-established");

    // RCA 2025-12-30: REMOVED redundant relink_timers() and relink_light_sources() calls!
    // ROOT CAUSE: restgamestate() at restore.c:718-719 ALREADY calls these functions.
    // Our manual call here caused DOUBLE PROCESSING:
    //   1. restgamestate() → relink_timers() (vanilla, correct)
    //   2. This manual call (REDUNDANT!)
    //   3. getlev() in extraction loop → relink_timers() for each level (corrupts chain!)
    // FIX: Trust vanilla NetHack's restore flow - restgamestate() handles timer relinking.
    // The iOS deferred patch in timeout.c:2774-2791 handles objects not yet loaded.
    SAVE_LOG("Step 3f2: Timer/light relinking (handled by restgamestate - vanilla flow)");
    SAVE_LOG("  ✓ Skipping manual relink - restgamestate() already did this at restore.c:718");

    // CRITICAL FIX: Re-initialize status buffers after dylib reload!
    // ROOT CAUSE: restgamestate() loads OLD pointer values from save file.
    // After dylib reload, those pointers point to FREED memory from old dylib!
    // MUST allocate fresh buffers in current dylib memory space.
    // WHY: bot() will crash/infinite loop if gb.blstats pointers are invalid.
    SAVE_LOG("Step 3f4: Re-initializing status buffers after dylib reload");
    extern void status_finish(void);
    extern void status_initialize(boolean);
    status_finish();  // Free old/invalid buffers (safe even if pointers invalid)

    // CRITICAL FIX: Reset gb.blinit flag before re-initialization
    // Without this, status_initialize(FALSE) sees gb.blinit == TRUE and triggers:
    // impossible("2nd status_initialize with full init.") in botl.c:1443
    // This happens because status_finish() does NOT clear gb.blinit!
    gb.blinit = FALSE;  // Reset flag for fresh initialization

    status_initialize(FALSE);  // Allocate fresh buffers in current dylib memory
    SAVE_LOG("  ✓ Status buffers re-allocated with fresh memory");

    // CRITICAL STEP: Write CURRENT level to level file FIRST! (dorecover:522-528)
    // After getlev() loads current level into memory (fmon, fobj, levl[][]),
    // we MUST write it to a level file BEFORE extracting other levels!
    // Without this, the current level file doesn't exist and the file pointer is misaligned!
    SAVE_LOG("Step 3g: Writing CURRENT level to level file (CRITICAL!)");

    // Get level functions from NetHack
    extern NHFILE *create_levelfile(int, char *);
    extern void bufon(int);
    extern xint16 ledger_no(d_level *);
    extern void savelev(NHFILE *, xint8);

    // Get current level number
    xint8 current_level = (xint8) ledger_no(&u.uz);
    SAVE_LOG("  Current level number: %d", (int)current_level);

    // Create level file for current level
    char whynot[256] = {0};  // Initialize to prevent garbage if create fails silently
    NHFILE *current_level_nhfp = create_levelfile(current_level, whynot);
    if (!current_level_nhfp) {
        SAVE_LOG("ERROR: Failed to create current level file %d: %s", (int)current_level, whynot);
        program_state.something_worth_saving = 0;
        close_nhfile(nhfp);
        return -1;
    }

    // FIX: Write FULL level data to level file, not just minimal header!
    // The current level data IS in memory from getlev() at line 776.
    // But when player uses stairs, NetHack will:
    //   1. Call savelev() to save current level to file
    //   2. Call getlev() to load new level from file
    // So the level file MUST contain full level data!
    //
    // Note: relink_timers() is called inside restgamestate() (restore.c:718).

    bufon(current_level_nhfp->fd);
    current_level_nhfp->mode = WRITING;
    savelev(current_level_nhfp, current_level);
    close_nhfile(current_level_nhfp);
    SAVE_LOG("✓ Current level written to level file (full data)");

    // NOW we can extract the OTHER consolidated levels from save file
    SAVE_LOG("Step 3h: Level extraction - extracting OTHER consolidated levels from save file");

    // Set restore flags for level extraction (matching dorecover:530)
    program_state.restoring = REST_LEVELS;
    u.ustuck = (struct monst *) 0;  // Clear during extraction
    u.usteed = (struct monst *) 0;  // Clear during extraction

    // CRITICAL: Tell mread() to return gracefully on EOF instead of erroring (dorecover:858)
    // Without this, we get "Read 0 instead of 1 bytes" error when reaching end of consolidated levels
    extern struct restore_info restoreinfo;

    // CRITICAL FIX: Initialize restoreinfo struct BEFORE using it! (Bug #1)
    // Without this, we're setting flags on uninitialized memory = undefined behavior
    memset(&restoreinfo, 0, sizeof(struct restore_info));
    SAVE_LOG("  ✓ restoreinfo struct initialized");

    restoreinfo.mread_flags = 1;  // "return despite error"
    SAVE_LOG("  ✓ mread_flags set - EOF will be handled gracefully");

    // Loop through consolidated levels in save file
    while (1) {
        xint8 ltmp = 0;
        // Read level number marker (or EOF)
        extern void Sfi_xint8(NHFILE *, xint8 *, const char *);
        Sfi_xint8(nhfp, &ltmp, "gamestate-level_number");

        if (nhfp->eof) {
            SAVE_LOG("  ✓ Reached end of consolidated levels");
            break;
        }

        SAVE_LOG("  Level %d: Extracting from consolidated save...", (int)ltmp);

        // FIX: Properly extract level data from consolidated save to individual level file
        // Step 1: Load level from consolidated save into memory
        // Note: getlev() internally calls relink_timers() so timers are properly linked
        getlev(nhfp, 0, ltmp);
        SAVE_LOG("    Step 1: Level %d loaded into memory from save file", (int)ltmp);

        // Step 2: Write level from memory to individual level file
        char whynot_level[256] = {0};  // Renamed to avoid shadowing outer whynot
        NHFILE *level_nhfp = create_levelfile(ltmp, whynot_level);
        if (!level_nhfp) {
            SAVE_LOG("ERROR: Failed to create level file %d: %s", (int)ltmp, whynot_level);
            program_state.something_worth_saving = 0;
            close_nhfile(nhfp);
            return -1;
        }

        bufon(level_nhfp->fd);
        // RCA 2025-12-30: Use WRITING | FREEING to match vanilla restlevelfile() (restore.c:760)
        // FREEING causes savelev() to FREE objects/monsters after writing them to file.
        // This is CRITICAL during extraction because:
        //   1. We load level N into memory (overwriting previous level data)
        //   2. We write level N to its level file
        //   3. We MUST free level N's objects before loading level N+1
        // Without FREEING, objects accumulate and corrupt timer/light chains.
        // NOTE: This is safe during RESTORE extraction (we don't need extracted levels in memory).
        level_nhfp->mode = WRITING | FREEING;
        savelev(level_nhfp, ltmp);
        close_nhfile(level_nhfp);

        SAVE_LOG("    Step 2: Level %d written to level file (WRITING|FREEING)", (int)ltmp);
    }

    // Reset mread_flags after extraction loop (dorecover:879)
    restoreinfo.mread_flags = 0;
    SAVE_LOG("  ✓ mread_flags reset to normal");

    SAVE_LOG("✓ All levels extracted successfully");

    // Step 3i: CRITICAL - Recreate 1lock.0 after restore!
    // NetHack's INSURANCE anti-cheat expects 1lock.0 to exist at all times.
    // Without this, level transitions trigger TRICKED death!
    // Background: dosave0() deletes 1lock.0 after consolidating levels (save.c:382).
    // The EXTRACT loop above only restores 1lock.1+, not 1lock.0.
    // NetHack checks for 1lock.0 existence during EVERY level transition (do.c:1705).
    // If missing: done(TRICKED) → instant death!
    SAVE_LOG("Step 3i: Recreating 1lock.0 (INSURANCE anti-cheat file)");

    char whynot_lock[256] = {0};  // Initialize to prevent garbage on failure
    NHFILE *lock_nhfp = create_levelfile(0, whynot_lock);
    if (!lock_nhfp) {
        SAVE_LOG("ERROR: Failed to create 1lock.0: %s", whynot_lock);
        SAVE_LOG("       Level transitions will fail with TRICKED death!");
    } else {
        // Write minimal 1lock.0 (just hackpid, matching RealNetHackBridge.c:323-330)
        lock_nhfp->mode = WRITING;
        extern struct instance_globals_saved_h svh;
        Sfo_int(lock_nhfp, &svh.hackpid, "gamestate-hackpid");
        close_nhfile(lock_nhfp);
        SAVE_LOG("✓ 1lock.0 recreated with PID %d", svh.hackpid);
        SAVE_LOG("  Level transitions will now work correctly");
    }

    // CRITICAL FINAL STEP: Reload current level from save file! (dorecover:586-593)
    // After all the restlevelfile() calls which used WRITING|FREEING mode,
    // memory state may have changed. We must reload the current level to ensure
    // it's in the correct final state!
    SAVE_LOG("Step 3i: FINAL reload of current level from save file (CRITICAL!)");

    // 1. Rewind save file to beginning (dorecover:586)
    extern void rewind_nhfile(NHFILE *);
    rewind_nhfile(nhfp);
    SAVE_LOG("  Save file rewound to beginning");

    // 2. Skip version header again (dorecover:587)
    // We need to re-seek past the header since we rewound
    if (lseek(nhfp->fd, (off_t)total_header_size, SEEK_SET) == -1) {
        SAVE_LOG("ERROR: Failed to re-seek past header!");
        close_nhfile(nhfp);
        return -1;
    }
    SAVE_LOG("  Version header skipped (re-seek)");

    // 3. Skip player name again (dorecover:588)
    get_plname_from_file(nhfp, plname_buf, TRUE);
    SAVE_LOG("  Player name skipped");

    // 4. Set final restore flag (dorecover:591)
    program_state.restoring = REST_CURRENT_LEVEL;
    SAVE_LOG("  Restore flag set to REST_CURRENT_LEVEL");

    // 5. Reload current level (dorecover:593) - OVERWRITES memory!
    SAVE_LOG("  Reloading current level from save file (FINAL STATE)...");
    getlev(nhfp, 0, (xint8) 0);
    SAVE_LOG("  ✓ Current level reloaded - FINAL STATE established");

    // NOW we can clear restore flags and close the file
    program_state.restoring = 0;
    program_state.in_getlev = FALSE;

    close_nhfile(nhfp);
    SAVE_LOG("✓ Save file closed - restore sequence complete");

    // Step 4: POST-RESTORE OPERATIONS (dorecover:815-920)
    // These are CRITICAL for proper game state restoration

    // CRITICAL FIX: Rebind commands after restore!
    // Snapshot restore DESTROYS all command bindings!
    // We MUST reinitialize commands completely
    extern void reset_commands(boolean initial);

    SAVE_LOG("Step 4_CRITICAL: Reinitializing ALL commands (like new game)");
    // Step 1: Full reinitialization (like initoptions() does)
    reset_commands(TRUE);  // This calls commands_init() internally

    // Step 2: Enable numpad mode BEFORE rebinding (like RealNetHackBridge.c does)
    // CRITICAL: nh_restart() cleared all flags, must restore numpad setting!
    iflags.num_pad = TRUE;  // Use numpad (1-9 for movement)
    iflags.num_pad_mode = 0;  // Standard numpad layout
    SAVE_LOG("  ✓ Numpad mode enabled (1-9 for movement)");

    // CRITICAL: Use graphical menus (MENU_FULL) not yn_function prompts (MENU_TRADITIONAL)
    // Without this, loot options use yn_function instead of menu system!
    flags.menu_style = MENU_FULL;
    SAVE_LOG("  ✓ Menu style set to MENU_FULL (2)");

    // Step 3: Rebind with numpad (like ios_newgame.c does)
    reset_commands(FALSE);  // Rebind with numpad settings NOW THAT num_pad is TRUE

    // Step 4: Restore C('_') retravel binding
    extern boolean bind_key(uchar key, const char *command);
    bind_key(0x1F, "retravel");  // 0x1F = C('_')

    SAVE_LOG("  ✓ Commands fully reinitialized, numpad bound, C('_') retravel restored");

    SAVE_LOG("Step 4a: Initializing object class probabilities");
    init_oclass_probs();  // Recalculate object generation probabilities (restore.c:815)

    // NOTE: relink_timers() and relink_light_sources() are called inside restgamestate()
    // at restore.c:718-719 - no manual call needed here (RCA 2025-12-30)
    // NOTE: reset_oattached_mids() is called inside restgamestate() after these

    // NOTE: restlevelstate() is static in restore.c and already called
    // internally by getlev() which is called by restgamestate()

    // Step 4c: Reset glyph mapping (restore.c:897)
    SAVE_LOG("Step 4c: Resetting glyph mapping");
    extern void reset_glyphmap(enum glyphmap_change_triggers trigger);
    reset_glyphmap(gm_levelchange);
    SAVE_LOG("  ✓ Glyph mapping reset");

    // Step 4d: Recompute rank size for status line (restore.c:898)
    SAVE_LOG("Step 4d: Recomputing rank size for status");
    extern void max_rank_sz(void);
    max_rank_sz();
    SAVE_LOG("  ✓ Rank size recomputed");

    // Step 4d2: Rogue level graphics check (restore.c:895-896)
    // The Rogue level uses special ASCII-only graphics, must be set after restore
    SAVE_LOG("Step 4d2: Checking for Rogue level graphics");
    extern void assign_graphics(int);
    if (Is_rogue_level(&u.uz)) {
        assign_graphics(ROGUESET);
        SAVE_LOG("  ✓ Rogue level detected - assigned ROGUESET graphics");
    }

    // Step 4d3: Ball & chain sanity check (restore.c:900-905)
    // Fix corrupted punishment state that could cause crashes
    SAVE_LOG("Step 4d3: Ball & chain sanity check");
    if ((uball && !uchain) || (uchain && !uball)) {
        impossible("ios_restore_complete: lost ball & chain");
        // Poor man's unpunish() - clear both worn slots
        setworn((struct obj *) 0, W_CHAIN);
        setworn((struct obj *) 0, W_BALL);
        SAVE_LOG("  ⚠ Fixed corrupted ball & chain state");
    }

    // Step 4e: Handling in-use inventory items (restore.c:912)
    SAVE_LOG("Step 4e: Handling in-use inventory items");
    inven_inuse(FALSE);  // Apply partially-used items (potions, etc.)

    // Step 4f: Re-glyphing dark rooms (restore.c:916)
    SAVE_LOG("Step 4f: Re-glyphing dark rooms");
    reglyph_darkroom();  // Re-glyph any dark rooms that need updating

    // Step 4g: Resetting vision system (restore.c:917-918)
    SAVE_LOG("Step 4g: Resetting vision system");
    vision_reset();  // Clear and reinitialize vision
    gv.vision_full_recalc = 1;  // Force full vision recalculation
    SAVE_LOG("  ✓ Vision reset, full recalc scheduled");

    // Step 5: Verify game is in valid state
    extern struct instance_globals_saved_m svm;
    extern int game_started;

    SAVE_LOG("Verification:");
    SAVE_LOG("  Moves: %ld", svm.moves);
    SAVE_LOG("  Game started: %d", game_started);
    // SAVE_LOG("  Memory used: %zu bytes", nh_memory_used());

    // Mark game as started
    game_started = 1;
    program_state.something_worth_saving = 1;

    // CRITICAL FIX: Set snapshot_loaded flag so nethack_run_game_threaded() calls moveloop(TRUE)!
    // Without this, restores call moveloop(FALSE) which starts a NEW game instead of resuming.
    snapshot_loaded = true;
    fprintf(stderr, "[SAVE] 🎯 snapshot_loaded = TRUE (was set at ios_save_integration.c:%d)\n", __LINE__);
    fflush(stderr);
    SAVE_LOG("  snapshot_loaded flag set - moveloop(TRUE) will be called on resume");

    // ===========================================================================
    // CRITICAL FIX (2025-12-20): RETRY deferred timer relinking!
    // ===========================================================================
    // ROOT CAUSE ANALYSIS:
    // - First relink_timers() at line 999 runs AFTER inventory loads but BEFORE
    //   level extraction loop. Timers referencing objects on OTHER levels can't
    //   be relinked yet (objects not loaded).
    // - ios_relink_timers_deferred.patch makes relink_timers() use `continue`
    //   instead of panic when find_oid() fails, keeping needs_fixup=1.
    // - But there was NO RETRY mechanism! Timers stayed unfixed.
    // - run_timers() would crash dereferencing unfixed timer's arg.a_uint as a pointer.
    //
    // FIX: Call relink_timers() AGAIN now that ALL levels are loaded.
    // Any timers that couldn't be fixed earlier should resolve now.
    // ===========================================================================
    SAVE_LOG("Step 4g2: RETRY deferred timer relinking (all levels now loaded)");
    {
        extern struct instance_globals_t gt;
        int deferred_count = 0;
        timer_element *t;

        // Count timers still needing fixup
        for (t = gt.timer_base; t; t = t->next) {
            if (t->needs_fixup) deferred_count++;
        }

        if (deferred_count > 0) {
            SAVE_LOG("  Found %d deferred timers - attempting relink...", deferred_count);
            relink_timers(FALSE);  // Second pass - should work now

            // Verify success
            int still_unfixed = 0;
            for (t = gt.timer_base; t; t = t->next) {
                if (t->needs_fixup) {
                    still_unfixed++;
                    fprintf(stderr, "[TIMER_RCA] WARNING: Timer %lu (func=%d o_id=%u) STILL unfixed!\n",
                           t->tid, t->func_index, t->arg.a_uint);
                }
            }

            if (still_unfixed > 0) {
                SAVE_LOG("  WARNING: %d/%d timers remain unfixed (objects destroyed?)",
                        still_unfixed, deferred_count);
            } else {
                SAVE_LOG("  ✓ All %d deferred timers successfully relinked", deferred_count);
            }
        } else {
            SAVE_LOG("  ✓ No deferred timers (all relinked on first pass)");
        }
    }

    // Step 4h: Expire elapsed timers (restore.c:920)
    // CRITICAL: Must be done before clearing restoring flag
    SAVE_LOG("Step 4h: Catching up on elapsed timers");

    // DEBUG: Log timer chain state before run_timers()
    {
        extern struct instance_globals_t gt;
        extern struct instance_globals_saved_m svm;
        timer_element *t = gt.timer_base;
        int timer_count = 0;
        SAVE_LOG("  DEBUG: Current moves=%ld", svm.moves);
        while (t) {
            SAVE_LOG("  DEBUG: Timer #%d: func=%d timeout=%ld kind=%d %s",
                     timer_count, t->func_index, t->timeout, t->kind,
                     t->timeout <= svm.moves ? "[WILL FIRE]" : "[future]");
            timer_count++;
            t = t->next;
            if (timer_count > 100) {
                SAVE_LOG("  DEBUG: Too many timers, stopping enumeration");
                break;
            }
        }
        SAVE_LOG("  DEBUG: Total %d timers in chain", timer_count);
    }

    CRASH_CHECKPOINT("before_run_timers");
    run_timers();  // Expire any timers that went off while game was saved
    SAVE_LOG("  ✓ Timers expired");

    // Step 4i: Clear restore flag (restore.c:921)
    // CRITICAL: "affects bot() so clear before docrt()" - restore.c comment
    // bot() behaves differently when program_state.restoring is set!
    SAVE_LOG("Step 4i: Clearing restore flag (affects bot() behavior!)");
    program_state.restoring = 0;
    SAVE_LOG("  ✓ Restore flag cleared - bot() now operates normally");

    // Step 5a: Set beyond_savefile_load flag (restore.c:932)
    // CRITICAL: Must be set BEFORE docrt() for proper display
    u.usteed_mid = u.ustuck_mid = 0;  // Clear mount/stuck monster refs (restore.c:931)
    program_state.beyond_savefile_load = 1;
    SAVE_LOG("Step 5a: Set beyond_savefile_load flag");
    SAVE_LOG("  DEBUG: u.ux=%d u.uy=%d (should be non-zero!)", u.ux, u.uy);
    SAVE_LOG("  DEBUG: program_state.in_docrt=%d (should be 0)", program_state.in_docrt);

    // Step 5b: Call vision_recalc() and docrt() to update display
    // CRITICAL: Must call vision_recalc() BEFORE docrt() to compute visible tiles!
    // (See allmain.c:568-569 tutorial mode sequence)
    SAVE_LOG("Step 5b: Recalculating vision and updating display");

    // DEBUG: Check if map output would be suppressed
    SAVE_LOG("  DEBUG BEFORE docrt(): program_state.restoring=%d, gi.in_mklev=%d",
             program_state.restoring, gi.in_mklev);

    // CRITICAL FIX: Ensure windowprocs is set to ios_procs!
    // After nh_restart(), windowprocs might be reset or corrupted
    // This is why COLD START (load first) fails but works after NEW game
    extern struct window_procs ios_procs;
    windowprocs = ios_procs;
    SAVE_LOG("  ✓ windowprocs set to ios_procs (ensuring map rendering works)");

    // CRITICAL FIX: Don't call vision_recalc() before docrt()!
    // docrt() does its own vision_recalc(2) then vision_recalc(0) internally
    // Calling it here interferes with docrt's internal vision management
    SAVE_LOG("  Skipping manual vision_recalc - docrt() handles it internally");

    // Draw map - docrt() will:
    // 1. Call vision_recalc(2) to shut down vision
    // 2. Call cls() to clear screen
    // 3. Call show_glyph() for all tiles (marks them as changed)
    // 4. Call vision_recalc(0) to recalculate
    // 5. Call see_monsters() to overlay monsters
    // But show_glyph() only MARKS tiles - doesn't call print_glyph!
    // Map will be rendered later when moveloop calls flush_screen()
    extern void docrt(void);
    docrt();
    SAVE_LOG("  ✓ docrt() complete - tiles marked for rendering");

    // CRITICAL FIX FOR COLD START: Render marked tiles to map_buffer immediately!
    // Without this, Swift queries map_buffer after ios_notify_game_ready() but before
    // moveloop starts (which would normally call flush_screen()).
    extern void flush_screen(int how);
    flush_screen(0);
    SAVE_LOG("  ✓ flush_screen() complete - tiles rendered to map_buffer");

    // DEBUG: Check if docrt() took early exit path
    SAVE_LOG("  DEBUG AFTER docrt(): Underwater=%d, u.uburied=%d, Is_waterlevel=%d",
             Underwater, u.uburied, Is_waterlevel(&u.uz));

    // CRITICAL: Do NOT capture/notify map here!
    // docrt() only MARKS tiles as changed (gg.gbuf[y][x].gnew = 1)
    // Actual rendering happens when moveloop() calls flush_screen()
    // which then calls print_glyph() for all changed tiles
    // Our ios_winprocs.c::print_glyph writes to map_buffer
    // Then ios_wait_synch() captures and notifies automatically
    SAVE_LOG("  Map will be captured automatically when moveloop calls flush_screen()");

    // CRITICAL: Display welcome message BEFORE clearing message window!
    // Guardian Analysis: clear_nhwindow() was deleting messages before Swift could see them
    // LOAD game had no welcome() call (vs NEW game which calls welcome(TRUE))
    // This caused messages to work in NEW but not LOAD
    SAVE_LOG("  Displaying welcome back message");
    extern void welcome(boolean);
    welcome(FALSE);  // FALSE = "welcome back" message for restored game
    SAVE_LOG("  ✓ Welcome message displayed (Swift received via callback)");

    // NOW safe to clear for fresh start - Swift already captured the welcome message
    clear_nhwindow(WIN_MESSAGE);  // Clear message window for fresh start (restore.c:935)
    SAVE_LOG("  ✓ Message window cleared for fresh game start");

    // Step 6: Post-restore finalization (matching dorecover:935-939)
    SAVE_LOG("Step 6: Post-restore finalization");

    // Check for special room effects (restore.c:939)
    SAVE_LOG("  Checking special room effects");
    extern void check_special_room(boolean);
    check_special_room(FALSE);
    SAVE_LOG("  ✓ Special room check complete");

    // SKIP welcome() for now - it might block waiting for input!
    // TODO: Implement welcome() properly for iOS
    // extern void welcome(boolean);
    // welcome(FALSE);  // FALSE = "welcome back"
    SAVE_LOG("  (Skipping welcome message - iOS doesn't block on messages)");

    // Re-enable monster notifications (not explicitly in restore.c but should be done)
    notice_mon_on();
    SAVE_LOG("  ✓ Monster notifications re-enabled");

    SAVE_LOG("✓ RESTORE COMPLETE - Game ready to continue");
    SAVE_LOG("==========================================");

    // CRITICAL FIX: Clear cached status to prevent garbage from previous session!
    // Without this, stale data from before restore causes corruption on first status update.
    // See RCA: ios_winprocs.c used to do illegal type casts, now fixed to use strtol().
    // But we still need to clear the cache to ensure fresh status on first bot().
    SAVE_LOG("🧹 Clearing cached status to prevent corruption");
    extern void ios_clear_status_cache(void);
    ios_clear_status_cache();
    SAVE_LOG("  ✓ Status cache cleared");

    // CRITICAL: Notify Swift that game is FULLY initialized and ready for queries!
    // At this point:
    // - gi.invent is populated with player's items
    // - u.ux/u.uy contain player position
    // - program_state.in_moveloop will be set when moveloop starts
    // - All globals are in valid state
    // NOW Swift UI can safely query inventory, player position, etc.
    SAVE_LOG("🎯 Notifying Swift: Game ready for queries");
    extern void ios_notify_game_ready(void);
    ios_notify_game_ready();

    // CRITICAL FIX (2025-12-30): Set gs.SAVEF AFTER restore completes!
    // ROOT CAUSE: gs.SAVEF is NOT persisted across app restarts.
    // When ios_quicksave() checks gs.SAVEF[0], it finds empty string and SKIPS saving!
    // Log evidence: "[SAVE_INTEGRATION] ⏭️ SKIP: gs.SAVEF not set (character creation not complete)"
    // FIX: Explicitly set gs.SAVEF after restore to enable subsequent saves.
    // This matches the fix in ios_character_save.c:479-482 for character saves.
    SAVE_LOG("🔧 Setting gs.SAVEF for subsequent saves");
    snprintf(gs.SAVEF, sizeof(gs.SAVEF), "save/savegame");
    SAVE_LOG("  ✓ gs.SAVEF = '%s' (saves after load will now work)", gs.SAVEF);

    return 0;
}

/*
 * Quick save function for Swift integration
 */
NETHACK_EXPORT int ios_quicksave(void) {
    SAVE_LOG("Quick save initiated");

    // Get REAL iOS sandbox path (not SAVEP!)
    extern const char* get_ios_documents_path(void);
    const char* documents = get_ios_documents_path();

    if (!documents) {
        SAVE_LOG("ERROR: Could not get iOS documents path");
        return -1;
    }

    char save_dir[512];
    int len = snprintf(save_dir, sizeof(save_dir), "%s/save", documents);
    if (len < 0 || len >= sizeof(save_dir)) {
        SAVE_LOG("ERROR: Save directory path too long");
        return -1;
    }

    SAVE_LOG("Saving to: %s", save_dir);
    return ios_save_complete(save_dir);
}

/*
 * Quick restore function for Swift integration
 */
NETHACK_EXPORT int ios_quickrestore(void) {
    CRASH_CHECKPOINT("ios_quickrestore_start");
    SAVE_LOG("Quick restore initiated");

    // Get REAL iOS sandbox path (not SAVEP!)
    extern const char* get_ios_documents_path(void);
    const char* documents = get_ios_documents_path();

    if (!documents) {
        SAVE_LOG("ERROR: Could not get iOS documents path");
        return -1;
    }

    char save_dir[512];
    int len = snprintf(save_dir, sizeof(save_dir), "%s/save", documents);
    if (len < 0 || len >= sizeof(save_dir)) {
        SAVE_LOG("ERROR: Save directory path too long");
        return -1;
    }

    SAVE_LOG("Restoring from: %s", save_dir);
    return ios_restore_complete(save_dir);
}

/*
 * Check if a save exists
 * Now we only look for NetHack save files, no memory.dat!
 */
NETHACK_EXPORT int ios_save_exists(void) {
    extern const char* get_ios_documents_path(void);  // From ios_filesys.c

    // Get iOS Documents path directly (independent of SAVEP initialization)
    const char* documents = get_ios_documents_path();
    if (!documents) {
        SAVE_LOG("Could not get iOS documents path");
        return 0;
    }

    char save_dir[512];

    // Build save directory path
    int len = snprintf(save_dir, sizeof(save_dir), "%s/save", documents);
    if (len < 0 || len >= sizeof(save_dir)) {
        return 0;
    }

    // Check for fixed filename "savegame"
    char game_path[512];
    int len2 = snprintf(game_path, sizeof(game_path), "%s/savegame", save_dir);
    if (len2 < 0 || len2 >= sizeof(game_path)) {
        return 0;
    }

    // Check if file exists
    int exists = (access(game_path, F_OK) == 0);
    if (exists) {
        SAVE_LOG("Found save file: savegame");
    }

    return exists;
}

/*
 * Delete a save
 * Now we only delete NetHack save files, no memory.dat!
 */
NETHACK_EXPORT void ios_delete_save(void) {
    SAVE_LOG("Deleting save files");

    // Use NetHack's own delete function - it handles all NetHack save files
    delete_savefile();

    SAVE_LOG("✓ NetHack save files deleted");
}

/*
 * Get save info for UI
 */
static char save_info_buffer[512];
NETHACK_EXPORT const char* ios_get_save_info(void) {
    extern struct instance_globals_saved_m svm;
    extern struct instance_globals_saved_p svp;

    int len = snprintf(save_info_buffer, sizeof(save_info_buffer),
                       "Character: %s\n"
                       "Turns: %ld\n"
                       "Save exists: %s",
                       svp.plname,
                       svm.moves,
                       ios_save_exists() ? "Yes" : "No");

    if (len < 0 || len >= sizeof(save_info_buffer)) {
        return "Error: Save info too long";
    }

    return save_info_buffer;
}
