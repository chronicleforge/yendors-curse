/*
 * ios_character_status.c - Character Status Bridge Functions
 *
 * Provides comprehensive character status information to the iOS UI:
 * - Equipment slots (15 slots: armor, weapons, accessories)
 * - Character identity (role, race, gender, alignment)
 * - Status conditions (30 conditions as bitmask)
 * - Encumbrance state (6 levels)
 * - Polymorph status
 *
 * All functions return data suitable for JSON serialization in Swift.
 */

#include "hack.h"
#include "RealNetHackBridge.h"

/* External game state flags */
extern int game_started;
extern int character_creation_complete;

/* ==========================================================================
 * EQUIPMENT SLOT FUNCTIONS
 * ==========================================================================
 * NetHack equipment variables (from decl.h):
 *   uarm    - body armor    (W_ARM)
 *   uarmc   - cloak         (W_ARMC)
 *   uarmh   - helmet/hat    (W_ARMH)
 *   uarms   - shield        (W_ARMS)
 *   uarmg   - gloves        (W_ARMG)
 *   uarmf   - boots         (W_ARMF)
 *   uarmu   - undershirt    (W_ARMU)
 *   uwep    - weapon        (W_WEP)
 *   uswapwep- secondary     (W_SWAPWEP)
 *   uquiver - quiver        (W_QUIVER)
 *   uamul   - amulet        (W_AMUL)
 *   uleft   - left ring     (W_RINGL)
 *   uright  - right ring    (W_RINGR)
 *   ublindf - blindfold     (W_TOOL)
 */

/* Equipment slot indices (for Swift interop) */
#define SLOT_BODY_ARMOR    0
#define SLOT_CLOAK         1
#define SLOT_HELMET        2
#define SLOT_SHIELD        3
#define SLOT_GLOVES        4
#define SLOT_BOOTS         5
#define SLOT_SHIRT         6
#define SLOT_WEAPON        7
#define SLOT_SECONDARY     8
#define SLOT_QUIVER        9
#define SLOT_AMULET        10
#define SLOT_LEFT_RING     11
#define SLOT_RIGHT_RING    12
#define SLOT_BLINDFOLD     13
#define SLOT_COUNT         14

/* Helper: Get object name safely - uses rotating buffers to avoid overwrite */
static const char* safe_obj_name(struct obj *obj) {
    static char namebufs[SLOT_COUNT][BUFSZ];
    static int buf_idx = 0;

    if (!obj) return NULL;

    /* Use rotating buffer index */
    char *namebuf = namebufs[buf_idx];
    buf_idx = (buf_idx + 1) % SLOT_COUNT;

    /* Use xname for identified objects, or just the base name */
    const char* name = xname(obj);
    if (name && *name) {
        strncpy(namebuf, name, BUFSZ - 1);
        namebuf[BUFSZ - 1] = '\0';
        return namebuf;
    }
    return NULL;
}

/* Helper: Get object pointer by slot index */
static struct obj* get_slot_object(int slot) {
    switch (slot) {
        case SLOT_BODY_ARMOR:  return uarm;
        case SLOT_CLOAK:       return uarmc;
        case SLOT_HELMET:      return uarmh;
        case SLOT_SHIELD:      return uarms;
        case SLOT_GLOVES:      return uarmg;
        case SLOT_BOOTS:       return uarmf;
        case SLOT_SHIRT:       return uarmu;
        case SLOT_WEAPON:      return uwep;
        case SLOT_SECONDARY:   return uswapwep;
        case SLOT_QUIVER:      return uquiver;
        case SLOT_AMULET:      return uamul;
        case SLOT_LEFT_RING:   return uleft;
        case SLOT_RIGHT_RING:  return uright;
        case SLOT_BLINDFOLD:   return ublindf;
        default:               return NULL;
    }
}

/* Get equipment item name for a slot (NULL if empty) */
NETHACK_EXPORT const char* ios_get_equipment_slot(int slot) {
    if (!game_started || !program_state.in_moveloop) return NULL;
    if (slot < 0 || slot >= SLOT_COUNT) return NULL;

    struct obj *obj = get_slot_object(slot);
    return safe_obj_name(obj);
}

/* Check if a slot has a cursed item - only if player knows BUC status! */
NETHACK_EXPORT int ios_is_slot_cursed(int slot) {
    if (!game_started || !program_state.in_moveloop) return 0;
    if (slot < 0 || slot >= SLOT_COUNT) return 0;

    struct obj *obj = get_slot_object(slot);
    if (!obj) return 0;
    /* Only reveal cursed status if player knows BUC (bknown) */
    return (obj->bknown && obj->cursed) ? 1 : 0;
}

/* Check if a slot has a blessed item - only if player knows BUC status! */
NETHACK_EXPORT int ios_is_slot_blessed(int slot) {
    if (!game_started || !program_state.in_moveloop) return 0;
    if (slot < 0 || slot >= SLOT_COUNT) return 0;

    struct obj *obj = get_slot_object(slot);
    if (!obj) return 0;
    /* Only reveal blessed status if player knows BUC (bknown) */
    return (obj->bknown && obj->blessed) ? 1 : 0;
}

/* Check if weapon is welded (cursed and cannot be removed) */
NETHACK_EXPORT int ios_is_weapon_welded(void) {
    if (!game_started || !program_state.in_moveloop) return 0;
    return (uwep && uwep->cursed) ? 1 : 0;
}

/* Check if left ring slot is available (not blocked by cursed gloves) */
NETHACK_EXPORT int ios_is_left_ring_available(void) {
    if (!game_started || !program_state.in_moveloop) return 0;
    /* Check if gloves are cursed - they block ring changes */
    if (uarmg && uarmg->cursed) return 0;
    return 1;
}

/* Check if right ring slot is available */
NETHACK_EXPORT int ios_is_right_ring_available(void) {
    if (!game_started || !program_state.in_moveloop) return 0;
    if (uarmg && uarmg->cursed) return 0;
    return 1;
}

/* ==========================================================================
 * CHARACTER IDENTITY FUNCTIONS
 * ==========================================================================
 */

/* Get current role (class) name */
NETHACK_EXPORT const char* ios_get_current_role_name(void) {
    if (!game_started) return "Unknown";

    /* gu.urole.name contains the role name struct */
    if (gu.urole.name.m && *gu.urole.name.m) {
        return gu.urole.name.m;  /* Male form used generically */
    }
    return "Unknown";
}

/* Get current race name */
NETHACK_EXPORT const char* ios_get_current_race_name(void) {
    if (!game_started) return "Unknown";

    if (gu.urace.noun && *gu.urace.noun) {
        return gu.urace.noun;
    }
    return "Unknown";
}

/* Get current gender (0=male, 1=female) */
NETHACK_EXPORT int ios_get_current_gender(void) {
    if (!game_started) return 0;
    return flags.female ? 1 : 0;
}

/* Get gender name string */
NETHACK_EXPORT const char* ios_get_current_gender_name(void) {
    if (!game_started) return "Unknown";
    return flags.female ? "Female" : "Male";
}

/* Get alignment type (-1=chaotic, 0=neutral, 1=lawful) */
NETHACK_EXPORT int ios_get_current_alignment(void) {
    if (!game_started) return 0;
    return u.ualign.type;
}

/* Get alignment name string */
NETHACK_EXPORT const char* ios_get_current_alignment_name(void) {
    if (!game_started) return "Unknown";

    switch (u.ualign.type) {
        case A_LAWFUL:  return "Lawful";
        case A_NEUTRAL: return "Neutral";
        case A_CHAOTIC: return "Chaotic";
        default:        return "Unknown";
    }
}

/* Get player level */
NETHACK_EXPORT int ios_get_player_level(void) {
    if (!game_started) return 0;
    return u.ulevel;
}

/* Get experience points */
NETHACK_EXPORT long ios_get_player_experience(void) {
    if (!game_started) return 0;
    return u.uexp;
}

/* ==========================================================================
 * ENCUMBRANCE FUNCTIONS
 * ==========================================================================
 * Encumbrance levels (from hack.h):
 *   0 = UNENCUMBERED (normal)
 *   1 = SLT_ENCUMBER (Burdened)
 *   2 = MOD_ENCUMBER (Stressed)
 *   3 = HVY_ENCUMBER (Strained)
 *   4 = EXT_ENCUMBER (Overtaxed)
 *   5 = OVERLOADED   (Overloaded - cannot move)
 */

/* Get current encumbrance level (0-5) */
NETHACK_EXPORT int ios_get_encumbrance(void) {
    if (!game_started || !program_state.in_moveloop) return 0;
    return near_capacity();
}

/* Get encumbrance name string */
NETHACK_EXPORT const char* ios_get_encumbrance_name(void) {
    static const char* enc_names[] = {
        "",          /* UNENCUMBERED */
        "Burdened",
        "Stressed",
        "Strained",
        "Overtaxed",
        "Overloaded"
    };

    if (!game_started || !program_state.in_moveloop) return "";

    int enc = near_capacity();
    if (enc < 0 || enc > 5) return "";
    return enc_names[enc];
}

/* ==========================================================================
 * HUNGER FUNCTIONS
 * ==========================================================================
 * Hunger states (from hack.h):
 *   0 = SATIATED
 *   1 = NOT_HUNGRY (normal, no display)
 *   2 = HUNGRY
 *   3 = WEAK
 *   4 = FAINTING
 *   5 = FAINTED
 *   6 = STARVED (death)
 */

/* Get current hunger state (0-6) */
NETHACK_EXPORT int ios_get_hunger_state(void) {
    if (!game_started || !program_state.in_moveloop) return 1; /* NOT_HUNGRY */
    return u.uhs;
}

/* Get hunger state name string */
NETHACK_EXPORT const char* ios_get_hunger_state_name(void) {
    static const char* hunger_names[] = {
        "Satiated",
        "",          /* NOT_HUNGRY - no display */
        "Hungry",
        "Weak",
        "Fainting",
        "Fainted",
        "Starved"
    };

    if (!game_started || !program_state.in_moveloop) return "";

    int hunger = u.uhs;
    if (hunger < 0 || hunger > 6) return "";
    return hunger_names[hunger];
}

/* ==========================================================================
 * POLYMORPH FUNCTIONS
 * ==========================================================================
 */

/* Check if player is polymorphed */
NETHACK_EXPORT int ios_is_polymorphed(void) {
    if (!game_started || !program_state.in_moveloop) return 0;
    return Upolyd ? 1 : 0;
}

/* Get polymorph form name (NULL if not polymorphed) */
NETHACK_EXPORT const char* ios_get_polymorph_form(void) {
    if (!game_started || !program_state.in_moveloop) return NULL;
    if (!Upolyd) return NULL;

    /* Get the monster name for current form */
    return mons[u.umonnum].pmnames[NEUTRAL];
}

/* Get turns remaining in polymorph form (0 if not polymorphed) */
NETHACK_EXPORT int ios_get_polymorph_turns_left(void) {
    if (!game_started || !program_state.in_moveloop) return 0;
    if (!Upolyd) return 0;
    return u.mtimedone;
}

/* ==========================================================================
 * STATUS CONDITIONS BITMASK
 * ==========================================================================
 * Returns a bitmask of all active conditions.
 * Uses BL_MASK_* values from botl.h (same as PlayerCondition.swift)
 */

NETHACK_EXPORT unsigned long ios_get_condition_mask(void) {
    unsigned long mask = 0;

    if (!game_started || !program_state.in_moveloop) return 0;

    /* Additional safety: Check if level data is valid before accessing map functions.
     * During load/restore, game_started may be true but level might not be fully loaded.
     * u.ux/u.uy of 0,0 typically means player position isn't set yet. */
    if (u.ux == 0 && u.uy == 0) return 0;

    /* Critical conditions */
    if (Stoned)         mask |= 0x00100000L;  /* BL_MASK_STONE */
    if (Slimed)         mask |= 0x00040000L;  /* BL_MASK_SLIME */
    if (Strangled)      mask |= 0x00200000L;  /* BL_MASK_STRNGL */
    if (Sick && (u.usick_type & SICK_VOMITABLE))
                        mask |= 0x00000080L;  /* BL_MASK_FOODPOIS */
    if (Sick && (u.usick_type & SICK_NONVOMITABLE))
                        mask |= 0x01000000L;  /* BL_MASK_TERMILL */

    /* Debilitating conditions */
    if (Blind)          mask |= 0x00000002L;  /* BL_MASK_BLIND */
    if (Deaf)           mask |= 0x00000010L;  /* BL_MASK_DEAF */
    if (Confusion)      mask |= 0x00000008L;  /* BL_MASK_CONF */
    if (Stunned)        mask |= 0x00400000L;  /* BL_MASK_STUN */
    if (Hallucination)  mask |= 0x00000400L;  /* BL_MASK_HALLU */

    /* Incapacitation */
    if (gm.multi < 0) {
        /* Check what's causing the paralysis */
        if (u.usleep)   mask |= 0x00020000L;  /* BL_MASK_SLEEPING */
        else            mask |= 0x00008000L;  /* BL_MASK_PARLYZ */
    }

    /* Movement modes */
    if (Levitation)     mask |= 0x00004000L;  /* BL_MASK_LEV */
    if (Flying)         mask |= 0x00000040L;  /* BL_MASK_FLY */
    if (u.usteed)       mask |= 0x00010000L;  /* BL_MASK_RIDE */

    /* Hazards */
    if (u.utrap) {
        mask |= 0x04000000L;  /* BL_MASK_TRAPPED */
        if (u.utraptype == TT_LAVA)
            mask |= 0x00002000L;  /* BL_MASK_INLAVA */
    }
    if (u.ustuck)       mask |= 0x00000800L;  /* BL_MASK_HELD */
    if (Underwater)     mask |= 0x00800000L;  /* BL_MASK_SUBMERGED */

    /* Check for ice */
    if (is_ice(u.ux, u.uy))
                        mask |= 0x00001000L;  /* BL_MASK_ICY */

    /* Optional conditions */
    if (Wounded_legs)   mask |= 0x10000000L;  /* BL_MASK_WOUNDEDL */
    if (Glib)           mask |= 0x00080000L;  /* BL_MASK_SLIPPERY */
    if (!uwep)          mask |= 0x00000001L;  /* BL_MASK_BAREH */

    return mask;
}

/* ==========================================================================
 * COMPREHENSIVE CHARACTER STATUS JSON
 * ==========================================================================
 * Returns all character status information as a single JSON object.
 * This is more efficient than multiple individual calls from Swift.
 */

NETHACK_EXPORT const char* ios_get_character_status_json(void) {
    static char json_buffer[4096];

    if (!game_started || !program_state.in_moveloop) {
        return "{\"valid\":false}";
    }

    /* Gather all equipment names (with proper JSON escaping) */
    const char* eq_names[SLOT_COUNT];
    int eq_cursed[SLOT_COUNT];
    int eq_blessed[SLOT_COUNT];

    for (int i = 0; i < SLOT_COUNT; i++) {
        eq_names[i] = ios_get_equipment_slot(i);
        eq_cursed[i] = ios_is_slot_cursed(i);
        eq_blessed[i] = ios_is_slot_blessed(i);
    }

    /* Build JSON */
    int pos = 0;
    pos += snprintf(json_buffer + pos, sizeof(json_buffer) - pos,
        "{\"valid\":true,"
        "\"identity\":{"
        "\"role\":\"%s\","
        "\"race\":\"%s\","
        "\"gender\":\"%s\","
        "\"alignment\":\"%s\","
        "\"level\":%d,"
        "\"experience\":%ld"
        "},",
        ios_get_current_role_name(),
        ios_get_current_race_name(),
        ios_get_current_gender_name(),
        ios_get_current_alignment_name(),
        ios_get_player_level(),
        ios_get_player_experience()
    );

    /* Equipment section */
    pos += snprintf(json_buffer + pos, sizeof(json_buffer) - pos,
        "\"equipment\":{"
        "\"body\":%s%s%s,"
        "\"cloak\":%s%s%s,"
        "\"helmet\":%s%s%s,"
        "\"shield\":%s%s%s,"
        "\"gloves\":%s%s%s,"
        "\"boots\":%s%s%s,"
        "\"shirt\":%s%s%s,"
        "\"weapon\":%s%s%s,"
        "\"secondary\":%s%s%s,"
        "\"quiver\":%s%s%s,"
        "\"amulet\":%s%s%s,"
        "\"leftRing\":%s%s%s,"
        "\"rightRing\":%s%s%s,"
        "\"blindfold\":%s%s%s"
        "},",
        eq_names[0] ? "\"" : "null", eq_names[0] ? eq_names[0] : "", eq_names[0] ? "\"" : "",
        eq_names[1] ? "\"" : "null", eq_names[1] ? eq_names[1] : "", eq_names[1] ? "\"" : "",
        eq_names[2] ? "\"" : "null", eq_names[2] ? eq_names[2] : "", eq_names[2] ? "\"" : "",
        eq_names[3] ? "\"" : "null", eq_names[3] ? eq_names[3] : "", eq_names[3] ? "\"" : "",
        eq_names[4] ? "\"" : "null", eq_names[4] ? eq_names[4] : "", eq_names[4] ? "\"" : "",
        eq_names[5] ? "\"" : "null", eq_names[5] ? eq_names[5] : "", eq_names[5] ? "\"" : "",
        eq_names[6] ? "\"" : "null", eq_names[6] ? eq_names[6] : "", eq_names[6] ? "\"" : "",
        eq_names[7] ? "\"" : "null", eq_names[7] ? eq_names[7] : "", eq_names[7] ? "\"" : "",
        eq_names[8] ? "\"" : "null", eq_names[8] ? eq_names[8] : "", eq_names[8] ? "\"" : "",
        eq_names[9] ? "\"" : "null", eq_names[9] ? eq_names[9] : "", eq_names[9] ? "\"" : "",
        eq_names[10] ? "\"" : "null", eq_names[10] ? eq_names[10] : "", eq_names[10] ? "\"" : "",
        eq_names[11] ? "\"" : "null", eq_names[11] ? eq_names[11] : "", eq_names[11] ? "\"" : "",
        eq_names[12] ? "\"" : "null", eq_names[12] ? eq_names[12] : "", eq_names[12] ? "\"" : "",
        eq_names[13] ? "\"" : "null", eq_names[13] ? eq_names[13] : "", eq_names[13] ? "\"" : ""
    );

    /* Status section */
    pos += snprintf(json_buffer + pos, sizeof(json_buffer) - pos,
        "\"status\":{"
        "\"hunger\":%d,"
        "\"hungerName\":\"%s\","
        "\"encumbrance\":%d,"
        "\"encumbranceName\":\"%s\","
        "\"conditions\":%lu,"
        "\"polymorphed\":%s,"
        "\"polymorphForm\":%s%s%s,"
        "\"polymorphTurns\":%d,"
        "\"weaponWelded\":%s,"
        "\"leftRingAvailable\":%s,"
        "\"rightRingAvailable\":%s"
        "}}",
        ios_get_hunger_state(),
        ios_get_hunger_state_name(),
        ios_get_encumbrance(),
        ios_get_encumbrance_name(),
        ios_get_condition_mask(),
        ios_is_polymorphed() ? "true" : "false",
        ios_get_polymorph_form() ? "\"" : "null",
        ios_get_polymorph_form() ? ios_get_polymorph_form() : "",
        ios_get_polymorph_form() ? "\"" : "",
        ios_get_polymorph_turns_left(),
        ios_is_weapon_welded() ? "true" : "false",
        ios_is_left_ring_available() ? "true" : "false",
        ios_is_right_ring_available() ? "true" : "false"
    );

    return json_buffer;
}

/* ==========================================================================
 * RING SELECTION SUPPORT
 * ==========================================================================
 * Helper functions for the "Which ring-finger?" prompt
 */

/* Check which ring slots are available */
NETHACK_EXPORT int ios_get_ring_slot_availability(void) {
    if (!game_started || !program_state.in_moveloop) return 0;

    /* Return bitmask: bit 0 = left available, bit 1 = right available */
    int result = 0;

    /* Check if gloves are cursed (blocks all ring changes) */
    if (uarmg && uarmg->cursed) return 0;

    if (!uleft)  result |= 0x01;  /* Left slot empty */
    if (!uright) result |= 0x02;  /* Right slot empty */

    return result;
}

/* Get description of item that would be replaced */
NETHACK_EXPORT const char* ios_get_ring_slot_item(int which_hand) {
    if (!game_started || !program_state.in_moveloop) return NULL;

    struct obj *ring = (which_hand == 0) ? uleft : uright;
    return safe_obj_name(ring);
}
