/*
 * ios_object_bridge.h - iOS Bridge for NetHack Object Detection
 *
 * This file provides iOS-specific bridge functions to query objects
 * at map positions. NO game logic - only bridging to existing NetHack
 * object detection and naming functions.
 *
 * CRITICAL: This is a READ-ONLY bridge. It does not modify game state.
 */

#ifndef IOS_OBJECT_BRIDGE_H
#define IOS_OBJECT_BRIDGE_H

#include <stdbool.h>
#include "nethack_export.h"

/*
 * IOSObjectInfo - Object information struct for Swift consumption
 *
 * IMPORTANT: name field MUST be copied immediately from xname() result
 * due to NetHack's circular buffer system (10 buffers, overwritten after
 * 10 subsequent calls).
 */
typedef struct {
    char name[256];        /* Object display name (from xname, copied!) */
    int otyp;              /* Object type (CORPSE, WAND, etc.) */
    int oclass;            /* Object class (FOOD_CLASS=7, POTION_CLASS=8, etc.) */
    long quantity;         /* Stack quantity (quan field) */
    int enchantment;       /* Enchantment value (spe field) */
    bool blessed;          /* Blessed flag */
    bool cursed;           /* Cursed flag */
    bool bknown;           /* BUC status known */
    bool known;            /* Charges/enchantment known */
    bool dknown;           /* Description known */
    unsigned int o_id;     /* Unique object ID */
} IOSObjectInfo;

/*
 * ios_get_objects_at - Get all objects at a map position
 *
 * Parameters:
 *   x, y         - Map coordinates (checked against COLNO/ROWNO)
 *   buffer       - Output buffer for object info
 *   max_objects  - Maximum objects to return (buffer size)
 *
 * Returns:
 *   Number of objects found and written to buffer (0 if none)
 *
 * Notes:
 *   - Returns 0 if position is out of bounds
 *   - Returns 0 if objects are hidden (water/lava via covers_objects)
 *   - Skips OBJ_DELETED objects
 *   - Immediately copies xname() results to avoid buffer overwrites
 */
NETHACK_EXPORT int ios_get_objects_at(int x, int y, IOSObjectInfo *buffer, int max_objects);

/*
 * IOSTerrainInfo - Terrain/furniture information struct for Swift consumption
 *
 * Provides information about terrain features like stairs, doors, fountains, etc.
 * READ-ONLY bridge - does not modify game state.
 */
typedef struct {
    char terrain_name[64];    /* Human-readable name ("staircase up", "locked door", etc.) */
    int terrain_type;         /* Terrain type from rm.h (DOOR, STAIRS, FOUNTAIN, etc.) */
    int door_state;           /* Door state flags (D_CLOSED, D_LOCKED, etc.) if IS_DOOR */
    bool is_stairs_up;        /* true if stairs/ladder goes up */
    bool is_stairs_down;      /* true if stairs/ladder goes down */
    bool is_ladder;           /* true if ladder (can go both ways) */
    char terrain_char;        /* Display character ('<', '>', '+', '{', etc.) */
} IOSTerrainInfo;

/*
 * ios_get_terrain_at - Get terrain/furniture information at a map position
 *
 * Parameters:
 *   x, y         - Map coordinates (checked against COLNO/ROWNO)
 *   info_out     - Output struct for terrain info
 *
 * Returns:
 *   1 if special terrain found (stairs, door, furniture), 0 if ordinary floor/corridor
 *
 * Notes:
 *   - Uses stairway_at() to determine stairs direction (from stairs.h)
 *   - Checks levl[x][y].doormask for door states
 *   - Uses IS_DOOR, IS_FOUNTAIN, etc. macros from rm.h
 *   - Returns 0 for ordinary ROOM/CORR tiles
 *   - Handles out-of-bounds gracefully (returns 0)
 */
NETHACK_EXPORT int ios_get_terrain_at(int x, int y, IOSTerrainInfo *info_out);

/*
 * IOSMonsterInfo - Monster discovery information for Swift consumption
 *
 * Used for genocide/polymorph suggestions based on what player has seen.
 * READ-ONLY bridge - does not modify game state.
 */
typedef struct {
    char name[64];         /* Monster name (from mons[].pmnames[NEUTRAL]) */
    int monster_index;     /* Monster index (PM_KOBOLD, PM_DRAGON, etc.) */
    bool killed;           /* true if player has killed this type (died > 0) */
    bool seen_only;        /* true if seen but not killed */
    int killed_count;      /* Number of this type killed by player */
} IOSMonsterInfo;

/*
 * ios_get_discovered_monsters - Get all monsters the player has encountered
 *
 * Parameters:
 *   buffer       - Output buffer for monster info
 *   max_monsters - Maximum monsters to return (buffer size)
 *
 * Returns:
 *   Number of discovered monsters written to buffer
 *
 * Notes:
 *   - Only returns monsters with mvitals[].seen_close set
 *   - Sorted by monster index (not alphabetical)
 *   - Swift should sort by killed_count (killed section) or name (seen section)
 */
NETHACK_EXPORT int ios_get_discovered_monsters(IOSMonsterInfo *buffer, int max_monsters);

/*
 * ios_has_container_at - Check if there's a container at a map position
 *
 * Parameters:
 *   x, y         - Map coordinates (checked against COLNO/ROWNO)
 *
 * Returns:
 *   1 if at least one container found at position, 0 otherwise
 *
 * Notes:
 *   - Uses Is_container() macro from NetHack (checks for bags, boxes, chests, etc.)
 *   - Returns 0 for out-of-bounds positions
 *   - Does not count mimic containers or trapped containers specially
 */
NETHACK_EXPORT int ios_has_container_at(int x, int y);

#endif /* IOS_OBJECT_BRIDGE_H */
