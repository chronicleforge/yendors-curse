/*
 * ios_object_bridge.c - iOS Bridge for NetHack Object Detection
 *
 * This file ONLY provides bridging functions. NO game logic!
 * All object detection and naming logic comes from NetHack source.
 *
 * Key NetHack Functions Used:
 *   - vobj_at(x, y)         : Get object chain head at position
 *   - xname(obj)            : Get object display name (CIRCULAR BUFFER!)
 *   - covers_objects(x, y)  : Check if objects are visible
 *   - stairway_at(x, y)     : Get stairway info (direction, is_ladder)
 *
 * CRITICAL MEMORY MANAGEMENT:
 *   xname() returns pointer to circular buffer (10 buffers × 256 bytes)
 *   MUST copy result immediately before next xname() call!
 */

#include "ios_object_bridge.h"
#include "../NetHack/include/hack.h"
#include "../NetHack/include/stairs.h"
#include "nethack_safe.h"  // For MAP_Y_OFFSET coordinate conversion
#include "nethack_export.h"
#include <string.h>

/* External death flag - stops queries when player dies */
extern int player_has_died;

/*
 * ios_get_objects_at - Get all objects at a map position
 *
 * COORDINATE SPACE: NETHACK COORDINATES (1-based X, 0-based Y)
 * @param x: NetHack X coordinate (1-79, 1-based)
 * @param y: NetHack Y coordinate (0-20, 0-based)
 * @param buffer: Output buffer for object information
 * @param max_objects: Maximum number of objects to return
 *
 * CRITICAL: This function expects NETHACK coordinates.
 * Swift code MUST convert via CoordinateConverter.swiftToNetHack() first!
 * See: MapAPI.getObjectsAt() for proper usage pattern.
 *
 * Implementation follows NetHack's object chain traversal pattern
 * (see origin/NetHack/src/invent.c:sobj_at for reference)
 */
NETHACK_EXPORT int ios_get_objects_at(int x, int y, IOSObjectInfo *buffer, int max_objects)
{
    struct obj *otmp;
    int count = 0;

    /* Guard: NULL buffer check */
    if (!buffer) {
        return 0;
    }

    /* Guard: Invalid max_objects */
    if (max_objects <= 0) {
        return 0;
    }

    /* Guard: Don't access objects during death - game state may be invalid */
    if (player_has_died || program_state.gameover) {
        return 0;
    }

    /* COORDINATE SYSTEM: NetHack coordinates (via MapAPI conversion)
     * MapAPI.getObjectsAt() converts Swift → NetHack before calling this function
     *
     * Input coordinates (from MapAPI):
     *   x: NetHack X (1-79, 1-based)
     *   y: NetHack Y (0-20, 0-based)
     *
     * These are already in NetHack's native coordinate space - use directly!
     */
    int map_x = x;  // Already NetHack coordinate
    int map_y = y;  // Already NetHack coordinate

    /* Guard: Bounds check using map coordinates */
    if (map_x < 0 || map_x >= COLNO || map_y < 0 || map_y >= ROWNO) {
        return 0;
    }

    /* Guard: Check if objects are visible at this position
     * covers_objects() returns true for water/lava that hide objects
     */
    if (covers_objects(map_x, map_y)) {
        return 0;
    }
    
    /* Iterate through object chain at position
     * Pattern: vobj_at(x,y) returns head, traverse via nexthere
     * (see origin/NetHack/src/invent.c for canonical pattern)
     */
    for (otmp = vobj_at(map_x, map_y); 
         otmp && count < max_objects; 
         otmp = otmp->nexthere) {
        
        /* Skip objects marked for deletion */
        if (otmp->where == OBJ_DELETED) {
            continue;
        }
        
        /*
         * CRITICAL SECTION: xname() Buffer Management
         *
         * xname() returns pointer to circular buffer pool (10 buffers).
         * Buffer gets overwritten after 10 subsequent xname() calls.
         * MUST copy immediately to our struct!
         *
         * Reference: origin/NetHack/src/objnam.c:nextobuf()
         */
        char *name_ptr = xname(otmp);
        strncpy(buffer[count].name, name_ptr, 255);
        buffer[count].name[255] = '\0';  /* Ensure null terminator */
        
        /* Copy object fields directly from struct obj
         * All fields are read-only - no game state modification
         */
        buffer[count].otyp = otmp->otyp;
        buffer[count].oclass = otmp->oclass;  /* Object class: FOOD_CLASS=7, POTION_CLASS=8, etc. */
        buffer[count].quantity = otmp->quan;
        buffer[count].enchantment = otmp->spe;
        buffer[count].blessed = otmp->blessed;
        buffer[count].cursed = otmp->cursed;
        buffer[count].bknown = otmp->bknown;
        buffer[count].known = otmp->known;
        buffer[count].dknown = otmp->dknown;
        buffer[count].o_id = otmp->o_id;
        
        count++;
    }

    return count;
}

/*
 * ios_get_terrain_at - Get terrain/furniture information at a map position
 *
 * COORDINATE SPACE: NETHACK COORDINATES (1-based X, 0-based Y)
 * @param x: NetHack X coordinate (1-79, 1-based)
 * @param y: NetHack Y coordinate (0-20, 0-based)
 * @param info_out: Output structure for terrain information
 *
 * CRITICAL: This function expects NETHACK coordinates.
 * Swift code MUST convert via CoordinateConverter.swiftToNetHack() first!
 * See: MapAPI.getTerrainAt() for proper usage pattern.
 *
 * Implementation follows NetHack's terrain detection patterns.
 * Uses stairway_at() for stairs direction (see origin/NetHack/src/do.c:doup/dodown)
 * Uses IS_DOOR, IS_FOUNTAIN macros (see origin/NetHack/include/rm.h)
 */
NETHACK_EXPORT int ios_get_terrain_at(int x, int y, IOSTerrainInfo *info_out)
{
    /* Guard: NULL pointer check */
    if (!info_out) {
        return 0;
    }

    /* Guard: Don't access terrain during death - game state may be invalid */
    if (player_has_died || program_state.gameover) {
        return 0;
    }

    /* COORDINATE SYSTEM: NetHack coordinates (via MapAPI conversion)
     * MapAPI.getTerrainAt() converts Swift → NetHack before calling this function
     *
     * Input coordinates (from MapAPI):
     *   x: NetHack X (1-79, 1-based)
     *   y: NetHack Y (0-20, 0-based)
     *
     * These are already in NetHack's native coordinate space - use directly!
     */
    int map_x = x;  // Already NetHack coordinate
    int map_y = y;  // Already NetHack coordinate

    /* Guard: Bounds check using map coordinates */
    if (map_x < 0 || map_x >= COLNO || map_y < 0 || map_y >= ROWNO) {
        return 0;
    }

    /* Initialize output struct */
    memset(info_out, 0, sizeof(IOSTerrainInfo));

    /* Get terrain type from level structure */
    int typ = levl[map_x][map_y].typ;
    info_out->terrain_type = typ;

    /*
     * Check for STAIRS or LADDER
     * Pattern from origin/NetHack/src/do.c:doup() line 1300
     */
    if (typ == STAIRS || typ == LADDER) {
        stairway *stway = stairway_at(map_x, map_y);

        /* Guard: Defensive NULL check (shouldn't happen but be safe) */
        if (!stway) {
            strncpy(info_out->terrain_name, "staircase", 63);
            info_out->terrain_name[63] = '\0';
            info_out->terrain_char = '?';
            return 1;
        }

        /* Copy stairway information from struct (see stairs.h) */
        info_out->is_ladder = stway->isladder;
        info_out->is_stairs_up = stway->up;
        info_out->is_stairs_down = !stway->up;

        /* Set human-readable name and display character */
        if (stway->isladder) {
            strncpy(info_out->terrain_name, "ladder", 63);
            /* Ladders can go both ways, show primary direction */
            info_out->terrain_char = stway->up ? '<' : '>';
        } else {
            if (stway->up) {
                strncpy(info_out->terrain_name, "staircase up", 63);
                info_out->terrain_char = '<';
            } else {
                strncpy(info_out->terrain_name, "staircase down", 63);
                info_out->terrain_char = '>';
            }
        }
        info_out->terrain_name[63] = '\0';

        return 1;
    }

    /*
     * Check for DOOR
     * Pattern from origin/NetHack/src/lock.c (door handling)
     */
    if (IS_DOOR(typ)) {
        int mask = levl[map_x][map_y].doormask;
        info_out->door_state = mask;
        info_out->terrain_char = '+';

        /* Determine door state from mask bits (see rm.h) */
        if (mask & D_LOCKED) {
            strncpy(info_out->terrain_name, "locked door", 63);
        } else if (mask & D_CLOSED) {
            strncpy(info_out->terrain_name, "closed door", 63);
        } else if (mask & D_ISOPEN) {
            strncpy(info_out->terrain_name, "open door", 63);
        } else if (mask & D_BROKEN) {
            strncpy(info_out->terrain_name, "broken door", 63);
        } else {
            /* D_NODOOR - open doorway */
            strncpy(info_out->terrain_name, "doorway", 63);
        }

        /* Check for trapped flag (can be OR'd with states) */
        if (mask & D_TRAPPED) {
            strncat(info_out->terrain_name, " (trapped)", 63 - strlen(info_out->terrain_name));
        }
        info_out->terrain_name[63] = '\0';

        return 1;
    }

    /*
     * Check for FOUNTAIN
     * Pattern from origin/NetHack/src/fountain.c
     */
    if (IS_FOUNTAIN(typ)) {
        strncpy(info_out->terrain_name, "fountain", 63);
        info_out->terrain_name[63] = '\0';
        info_out->terrain_char = '{';
        return 1;
    }

    /*
     * Check for ALTAR
     * Pattern from origin/NetHack/src/pray.c
     */
    if (IS_ALTAR(typ)) {
        strncpy(info_out->terrain_name, "altar", 63);
        info_out->terrain_name[63] = '\0';
        info_out->terrain_char = '_';
        return 1;
    }

    /*
     * Check for THRONE
     * Pattern from origin/NetHack/src/sit.c
     */
    if (IS_THRONE(typ)) {
        strncpy(info_out->terrain_name, "throne", 63);
        info_out->terrain_name[63] = '\0';
        info_out->terrain_char = '\\';
        return 1;
    }

    /*
     * Check for SINK
     * Pattern from origin/NetHack/src/fountain.c (sinks share file with fountains)
     */
    if (IS_SINK(typ)) {
        strncpy(info_out->terrain_name, "sink", 63);
        info_out->terrain_name[63] = '\0';
        info_out->terrain_char = '#';
        return 1;
    }

    /*
     * Check for GRAVE
     * Pattern from origin/NetHack/src/dig.c
     */
    if (IS_GRAVE(typ)) {
        strncpy(info_out->terrain_name, "grave", 63);
        info_out->terrain_name[63] = '\0';
        info_out->terrain_char = '|';
        return 1;
    }

    /* No special terrain - ordinary floor/corridor */
    return 0;
}

/*
 * ios_get_discovered_monsters - Get all monsters the player has encountered
 *
 * Uses mvitals[].seen_close to determine which monsters player has seen.
 * Uses mvitals[].died to determine kill count.
 *
 * Reference: origin/NetHack/src/mon.c lines 5965-5966 for seen_close
 * Reference: origin/NetHack/include/hack.h for mvitals struct
 */
NETHACK_EXPORT int ios_get_discovered_monsters(IOSMonsterInfo *buffer, int max_monsters)
{
    int count = 0;

    /* Guard: NULL buffer check */
    if (!buffer) {
        return 0;
    }

    /* Guard: Invalid max_monsters */
    if (max_monsters <= 0) {
        return 0;
    }

    /* Guard: Don't access during death - game state may be invalid */
    if (player_has_died || program_state.gameover) {
        return 0;
    }

    /* Iterate through all monster types
     * LOW_PM (0) to NUMMONS-1 covers all valid monster indices
     * Reference: origin/NetHack/include/permonst.h for PM_* constants
     */
    for (int i = LOW_PM; i < NUMMONS && count < max_monsters; i++) {
        /* Skip monsters player hasn't seen up close */
        if (!svm.mvitals[i].seen_close) {
            continue;
        }

        /* Copy monster name from mons array
         * pmnames[NEUTRAL] gives the gender-neutral name
         * Reference: origin/NetHack/src/monst.c for mons[] array
         */
        const char *name = mons[i].pmnames[NEUTRAL];
        if (!name) {
            continue;  /* Defensive: skip if no name */
        }

        strncpy(buffer[count].name, name, 63);
        buffer[count].name[63] = '\0';

        /* Copy monster info */
        buffer[count].monster_index = i;
        buffer[count].killed_count = svm.mvitals[i].died;
        buffer[count].killed = (svm.mvitals[i].died > 0);
        buffer[count].seen_only = !buffer[count].killed;

        count++;
    }

    return count;
}

/*
 * ios_has_container_at - Check if there's a container at a map position
 *
 * Uses Is_container() macro from NetHack (objclass.h) to detect:
 *   - Bags (sack, bag of holding, etc.)
 *   - Boxes (large box, chest)
 *   - Ice boxes
 *
 * Returns 1 if any container found, 0 otherwise.
 */
NETHACK_EXPORT int ios_has_container_at(int x, int y)
{
    struct obj *otmp;

    /* Guard: Don't access during death - game state may be invalid */
    if (player_has_died || program_state.gameover) {
        return 0;
    }

    /* Guard: Bounds check */
    if (x < 0 || x >= COLNO || y < 0 || y >= ROWNO) {
        return 0;
    }

    /* Guard: Check if objects are visible at this position */
    if (covers_objects(x, y)) {
        return 0;
    }

    /* Iterate through object chain looking for containers */
    for (otmp = vobj_at(x, y); otmp; otmp = otmp->nexthere) {
        /* Skip objects marked for deletion */
        if (otmp->where == OBJ_DELETED) {
            continue;
        }

        /* Is_container() macro checks for bags, boxes, ice boxes
         * Defined in origin/NetHack/include/objclass.h
         */
        if (Is_container(otmp)) {
            return 1;
        }
    }

    return 0;
}
