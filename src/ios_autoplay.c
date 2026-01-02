/*
 * iOS Auto-Play Configuration
 * Sets up NetHack for automatic character selection for debugging
 */

#include <stdio.h>
#include <string.h>
#include "../NetHack/include/hack.h"
#include "../NetHack/include/flag.h"
#include "nethack_export.h"  // For NETHACK_EXPORT

/* External declarations */
extern struct flag flags;
extern struct instance_flags iflags;  /* Instance flags including menu_requested */
extern struct sysopt_s sysopt;  /* Correct type name from sys.h */
extern struct instance_globals_saved_p svp;  /* Correct type from decl.h */
extern int game_started;  /* From RealNetHackBridge.c */

/* Enable auto-select for debugging */
void ios_enable_autoselect(void) {
    fprintf(stderr, "[IOS_AUTO] Enabling auto-select mode for debugging\n");
    fflush(stderr);

    /* Set specific role, race, gender, alignment for consistent testing */
    /* Valkyrie, Human, Female, Lawful - a classic combo */
    flags.initrole = 13;   /* Valkyrie (check role.c for exact index) */
    flags.initrace = 0;    /* Human */
    flags.initgend = 1;    /* Female */
    flags.initalign = 0;   /* Lawful */

    /* Alternative: Random selection */
    // flags.randomall = 1;  /* Randomly pick everything */

    /* Set player name */
    strcpy(svp.plname, "DebugHero");

    /* Skip various prompts */
    flags.ins_chkpt = 0;   /* No checkpoint saves */
    /* flags.num_pad doesn't exist in this version */

    fprintf(stderr, "[IOS_AUTO] Auto-select configured:\n");
    fprintf(stderr, "  Role: %d (Valkyrie)\n", flags.initrole);
    fprintf(stderr, "  Race: %d (Human)\n", flags.initrace);
    fprintf(stderr, "  Gender: %d (Female)\n", flags.initgend);
    fprintf(stderr, "  Alignment: %d (Lawful)\n", flags.initalign);
    fprintf(stderr, "  Name: %s\n", svp.plname);
    fflush(stderr);
}

/* Parse command line style arguments for iOS */
void ios_parse_debug_flags(const char *flagstr) {
    if (!flagstr) return;

    fprintf(stderr, "[IOS_AUTO] Parsing debug flags: %s\n", flagstr);
    fflush(stderr);

    /* Simple flag parser */
    if (strstr(flagstr, "--auto")) {
        ios_enable_autoselect();
    }

    if (strstr(flagstr, "--random")) {
        fprintf(stderr, "[IOS_AUTO] Enabling random character selection\n");
        flags.randomall = 1;
        strcpy(svp.plname, "RandomHero");
        fflush(stderr);
    }

    if (strstr(flagstr, "--wizard")) {
        fprintf(stderr, "[IOS_AUTO] Enabling wizard mode\n");
        flags.debug = 1;
        wizard = TRUE;
        fflush(stderr);
    }

    /* Role selection shortcuts */
    if (strstr(flagstr, "--valkyrie")) {
        flags.initrole = 13;  /* Valkyrie */
    } else if (strstr(flagstr, "--samurai")) {
        flags.initrole = 11;  /* Samurai */
    } else if (strstr(flagstr, "--knight")) {
        flags.initrole = 4;   /* Knight */
    } else if (strstr(flagstr, "--barbarian")) {
        flags.initrole = 1;   /* Barbarian */
    }
}

/* Check if auto-mode is enabled - returns int for Swift compatibility */
int ios_is_auto_mode(void) {
    /* Check if we have preset values */
    return (flags.initrole >= 0 || flags.randomall) ? 1 : 0;
}

/* Get status for debugging */
void ios_debug_autoplay_status(void) {
    fprintf(stderr, "[IOS_AUTO] Current autoplay settings:\n");
    fprintf(stderr, "  initrole: %d\n", flags.initrole);
    fprintf(stderr, "  initrace: %d\n", flags.initrace);
    fprintf(stderr, "  initgend: %d\n", flags.initgend);
    fprintf(stderr, "  initalign: %d\n", flags.initalign);
    fprintf(stderr, "  randomall: %d\n", flags.randomall);
    fprintf(stderr, "  plname: %s\n", svp.plname);
    fprintf(stderr, "  wizard: %d\n", wizard);
    fflush(stderr);
}

/*
 * Clear iflags.menu_requested before #loot command and log menu_style
 *
 * PROBLEM: When iflags.menu_requested is TRUE, doloot() in pickup.c (line 2213)
 * skips directly to lootmon label (line 2295) which forces "Loot in what direction?"
 * prompt even when a container is directly under the player.
 *
 * CRITICAL: If menu_style is TRADITIONAL or COMBINATION (not FULL/PARTIAL),
 * pickup.c:3070-3081 uses yn_function() instead of in_or_out_menu()!
 *
 * ROOT CAUSE: Unknown - the flag shouldn't be set during normal iOS touch flow.
 * But empirically it is, causing the direction query to block loot auto-selection.
 *
 * SOLUTION: Clear the flag before sending #loot command.
 */
NETHACK_EXPORT void ios_clear_menu_requested(void) {
    /* Log current menu_style for debugging */
    const char *style_name;
    switch (flags.menu_style) {
        case MENU_TRADITIONAL: style_name = "TRADITIONAL"; break;
        case MENU_COMBINATION: style_name = "COMBINATION"; break;
        case MENU_PARTIAL:     style_name = "PARTIAL"; break;
        case MENU_FULL:        style_name = "FULL"; break;
        default:               style_name = "UNKNOWN"; break;
    }
    fprintf(stderr, "[IOS_LOOT] menu_style = %d (%s)\n", flags.menu_style, style_name);

    if (iflags.menu_requested) {
        fprintf(stderr, "[IOS_LOOT] Clearing menu_requested flag (was TRUE)\n");
    }
    iflags.menu_requested = FALSE;
    fflush(stderr);
}

/*
 * Wizard Mode Functions for iOS Debug
 */

/* Static flag to persist wizard mode request across game init */
static int wizard_mode_requested = 0;

/* Request wizard mode - call BEFORE nethack_start_new_game() */
NETHACK_EXPORT void ios_enable_wizard_mode(void) {
    fprintf(stderr, "[IOS_WIZARD] ========================================\n");
    fprintf(stderr, "[IOS_WIZARD] Enabling wizard mode\n");
    fprintf(stderr, "[IOS_WIZARD] BEFORE: wizard=%d, flags.debug=%d\n", wizard, flags.debug);

    wizard_mode_requested = 1;
    /* Also set immediately in case game already running */
    flags.debug = 1;
    wizard = TRUE;

    fprintf(stderr, "[IOS_WIZARD] AFTER: wizard=%d, flags.debug=%d\n", wizard, flags.debug);
    fprintf(stderr, "[IOS_WIZARD] game_started=%d\n", game_started);
    fprintf(stderr, "[IOS_WIZARD] ========================================\n");

    /* Show confirmation in game message window */
    if (game_started) {
        pline("Wizard mode activated! You have godlike powers.");
    }

    fflush(stderr);
}

/* Apply wizard mode after game init - called from nethack_start_new_game() */
NETHACK_EXPORT void ios_apply_wizard_mode(void) {
    if (!wizard_mode_requested) return;

    fprintf(stderr, "[IOS_WIZARD] Applying wizard mode after game init\n");
    flags.debug = 1;
    wizard = TRUE;
    fflush(stderr);
}

/* Check if wizard mode is enabled */
NETHACK_EXPORT int ios_is_wizard_mode(void) {
    return wizard ? 1 : 0;
}

/*
 * Spawn test scenario with containers and items
 * Spawns around player position:
 * - Wand of wishing (3 charges) at player's feet
 * - Empty chest to the east
 * - Chest with 3 sacks to the west
 * - Food/potion/scroll to the south
 * - Large box with 1000 gold to the north
 */
NETHACK_EXPORT void ios_spawn_test_scenario(void) {
    if (!wizard) {
        fprintf(stderr, "[IOS_TEST] ERROR: Wizard mode not enabled!\n");
        fflush(stderr);
        return;
    }

    fprintf(stderr, "[IOS_TEST] Spawning test scenario...\n");

    int px = u.ux;
    int py = u.uy;

    /* Wand of wishing (3 charges) at player's feet */
    struct obj *wand = mksobj_at(WAN_WISHING, px, py, TRUE, FALSE);
    if (wand) {
        wand->spe = 3;
        fprintf(stderr, "[IOS_TEST] + Wand of wishing (3 charges) at (%d,%d)\n", px, py);
    }

    /* Empty chest to the east */
    if (isok(px + 1, py)) {
        struct obj *chest1 = mksobj_at(CHEST, px + 1, py, FALSE, FALSE);
        if (chest1) {
            chest1->olocked = 0;
            fprintf(stderr, "[IOS_TEST] + Empty chest at (%d,%d)\n", px + 1, py);
        }
    }

    /* Chest with 3 sacks to the west */
    if (isok(px - 1, py)) {
        struct obj *chest2 = mksobj_at(CHEST, px - 1, py, FALSE, FALSE);
        if (chest2) {
            chest2->olocked = 0;
            for (int i = 0; i < 3; i++) {
                struct obj *sack = mksobj(SACK, TRUE, FALSE);
                if (sack) {
                    add_to_container(chest2, sack);
                }
            }
            fprintf(stderr, "[IOS_TEST] + Chest with 3 sacks at (%d,%d)\n", px - 1, py);
        }
    }

    /* Various items to the south */
    if (isok(px, py + 1)) {
        mksobj_at(FOOD_RATION, px, py + 1, TRUE, FALSE);
        mksobj_at(POT_HEALING, px, py + 1, TRUE, FALSE);
        mksobj_at(SCR_IDENTIFY, px, py + 1, TRUE, FALSE);
        fprintf(stderr, "[IOS_TEST] + Food/potion/scroll at (%d,%d)\n", px, py + 1);
    }

    /* Large box with 1000 gold to the north */
    if (isok(px, py - 1)) {
        struct obj *box = mksobj_at(LARGE_BOX, px, py - 1, FALSE, FALSE);
        if (box) {
            box->olocked = 0;
            struct obj *gold = mksobj(GOLD_PIECE, FALSE, FALSE);
            if (gold) {
                gold->quan = 1000;
                gold->owt = weight(gold);
                add_to_container(box, gold);
            }
            fprintf(stderr, "[IOS_TEST] + Large box with 1000 gold at (%d,%d)\n", px, py - 1);
        }
    }

    /* Update vision for all spawned locations */
    newsym(px, py);
    newsym(px + 1, py);
    newsym(px - 1, py);
    newsym(px, py + 1);
    newsym(px, py - 1);

    fprintf(stderr, "[IOS_TEST] Test scenario complete!\n");
    fflush(stderr);
}