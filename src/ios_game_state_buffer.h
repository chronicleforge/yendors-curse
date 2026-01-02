/*
 * ios_game_state_buffer.h - Lock-Free Game State Push Model
 *
 * ARCHITECTURE: Push Model (Write on NetHack thread, Read on Swift main thread)
 * - NetHack writes snapshot after each turn (moves++)
 * - Swift reads snapshot anytime (NO async, NO waiting!)
 * - Double buffering for lock-free thread-safe reads
 *
 * PERFORMANCE BENEFITS:
 * - No async query overhead
 * - No debounce delays
 * - No race conditions
 * - Instant UI updates
 *
 * THREAD SAFETY:
 * - Writer: NetHack game thread (after each command)
 * - Reader: Swift main thread (anytime)
 * - Double buffering with atomic index swap (lock-free!)
 */

#ifndef IOS_GAME_STATE_BUFFER_H
#define IOS_GAME_STATE_BUFFER_H

#include <stdint.h>
#include <stdbool.h>
#include "nethack_export.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum counts for fixed-size arrays */
#define MAX_ADJACENT_DOORS 8   /* 8 directions around player */
#define MAX_NEARBY_ENEMIES 10  /* Nearby threats */
#define MAX_ITEMS_AT_POSITION 20  /* Items at player position */

/*
 * Door information for context actions
 */
typedef struct {
    int32_t x;           /* Map X coordinate (NetHack coords) */
    int32_t y;           /* Map Y coordinate (NetHack coords) */
    int32_t dx;          /* Delta X from player (-1, 0, 1) */
    int32_t dy;          /* Delta Y from player (-1, 0, 1) */
    bool is_open;        /* Door is open */
    bool is_closed;      /* Door is closed */
    bool is_locked;      /* Door is locked */
    char direction_cmd;  /* NetHack direction command ('7','8','9','4','6','1','2','3') */
} SnapshotDoorInfo;

/*
 * Enemy information for tactical display
 */
typedef struct {
    char name[64];       /* Monster name */
    int32_t x;           /* Map X coordinate */
    int32_t y;           /* Map Y coordinate */
    int32_t distance;    /* Distance from player (Manhattan distance) */
    int32_t hp;          /* Current HP (if known) */
    int32_t max_hp;      /* Max HP (if known) */
    char glyph_char;     /* Display character */
    bool is_hostile;     /* Is enemy hostile */
    bool is_peaceful;    /* Is enemy peaceful */
} SnapshotEnemyInfo;

/*
 * Complete game state snapshot
 * Written by NetHack thread, read by Swift thread
 * Double-buffered for lock-free access
 */
typedef struct {
    /* Turn tracking (for change detection) */
    int32_t turn_number;      /* moves counter */

    /* Player stats */
    int32_t player_hp;
    int32_t player_max_hp;
    int32_t player_ac;
    int32_t player_level;
    int32_t player_xp;
    int64_t player_gold;      /* Gold - calculated from game thread (no race!) */
    int32_t player_x;         /* Current position X */
    int32_t player_y;         /* Current position Y */
    bool has_container;       /* Container at player position */
    bool has_locked_container; /* Locked container at player position */

    /* Current tile context */
    int32_t terrain_type;     /* levl[x][y].typ */
    bool is_stairs_up;
    bool is_stairs_down;
    bool is_ladder;
    bool is_altar;
    bool is_fountain;
    bool is_sink;
    bool is_throne;
    char terrain_char;        /* Display character */
    char terrain_name[64];    /* Human-readable name */

    /* Level features (for autotravel) */
    int32_t stairs_up_x, stairs_up_y;         /* -1 if not found */
    int32_t stairs_down_x, stairs_down_y;     /* -1 if not found */
    int32_t altar_x, altar_y;                 /* -1 if not found */
    int32_t fountain_x, fountain_y;           /* -1 if not found */

    /* Adjacent doors (for context actions) */
    int32_t adjacent_door_count;
    SnapshotDoorInfo adjacent_doors[MAX_ADJACENT_DOORS];

    /* Nearby enemies (tactical info) */
    int32_t nearby_enemy_count;
    SnapshotEnemyInfo nearby_enemies[MAX_NEARBY_ENEMIES];

    /* Items at player position */
    int32_t item_count;
    /* NOTE: For PoC, we'll keep using async getObjectsAt for items
     * Full item snapshot can be added later if needed */
} GameStateSnapshot;

/*
 * Update game state snapshot (called by NetHack thread after each turn)
 * THREAD: NetHack game thread
 * TIMING: After nethack_send_input_threaded() processes command
 */
NETHACK_EXPORT void update_game_state_snapshot(void);

/*
 * Get current game state snapshot (called by Swift)
 * THREAD: Swift main thread (or any thread)
 * PARAMS: out - pointer to snapshot struct to fill
 * PERFORMANCE: ~1μs (just memcpy, no locks!)
 */
NETHACK_EXPORT void ios_get_game_state_snapshot(GameStateSnapshot *out);

/*
 * Initialize game state buffer (called once at startup)
 */
NETHACK_EXPORT void init_game_state_buffer(void);

#ifdef __cplusplus
}
#endif

#endif /* IOS_GAME_STATE_BUFFER_H */
