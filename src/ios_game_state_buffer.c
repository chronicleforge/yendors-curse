/*
 * ios_game_state_buffer.c - Lock-Free Game State Buffer Implementation
 *
 * DOUBLE BUFFERING:
 * - Two buffers: buffers[0] and buffers[1]
 * - Writer fills inactive buffer, then atomically swaps index
 * - Reader always reads from current_buffer_index (safe, no tearing)
 * - NO LOCKS needed!
 */

#include "ios_game_state_buffer.h"
#include <string.h>
#include <stdatomic.h>
#include <stdio.h>

/* NetHack headers */
#include "hack.h"

/* External death flag - stops updates when player dies */
extern int player_has_died;

/* Double buffer */
static GameStateSnapshot buffers[2];
static _Atomic int current_buffer_index = 0;

/*
 * Initialize buffer (called once at startup)
 */
void init_game_state_buffer(void)
{
    memset(&buffers[0], 0, sizeof(GameStateSnapshot));
    memset(&buffers[1], 0, sizeof(GameStateSnapshot));
    atomic_store(&current_buffer_index, 0);
}

/*
 * Get current snapshot (Swift bridge - lock-free read!)
 */
void ios_get_game_state_snapshot(GameStateSnapshot *out)
{
    if (!out) return;
    int read_idx = atomic_load(&current_buffer_index);
    *out = buffers[read_idx];  /* memcpy */
}

/*
 * Convert delta (dx, dy) to NetHack direction command
 */
static char get_direction_command(int dx, int dy)
{
    /* NetHack numpad directions:
     * 7  8  9
     * 4  .  6
     * 1  2  3
     */
    if (dx == -1 && dy == -1) return '7';  /* Top-left */
    if (dx ==  0 && dy == -1) return '8';  /* Top */
    if (dx ==  1 && dy == -1) return '9';  /* Top-right */
    if (dx == -1 && dy ==  0) return '4';  /* Left */
    if (dx ==  1 && dy ==  0) return '6';  /* Right */
    if (dx == -1 && dy ==  1) return '1';  /* Bottom-left */
    if (dx ==  0 && dy ==  1) return '2';  /* Bottom */
    if (dx ==  1 && dy ==  1) return '3';  /* Bottom-right */
    return '5';  /* Self (shouldn't happen) */
}

/*
 * Detect adjacent doors and fill snapshot
 */
static void detect_adjacent_doors(GameStateSnapshot *snapshot)
{
    int px = u.ux;
    int py = u.uy;
    int door_count = 0;

    /* Check all 8 adjacent tiles */
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;  /* Skip player position */

            int x = px + dx;
            int y = py + dy;

            /* Bounds check */
            if (x < 0 || x >= COLNO || y < 0 || y >= ROWNO) continue;

            /* Check if it's a door */
            int typ = levl[x][y].typ;
            if (IS_DOOR(typ)) {
                if (door_count >= MAX_ADJACENT_DOORS) break;

                SnapshotDoorInfo *door = &snapshot->adjacent_doors[door_count];
                door->x = x;
                door->y = y;
                door->dx = dx;
                door->dy = dy;

                int mask = levl[x][y].doormask;
                door->is_locked = (mask & D_LOCKED) != 0;
                door->is_closed = (mask & D_CLOSED) != 0;
                door->is_open = (mask & D_ISOPEN) != 0;
                door->direction_cmd = get_direction_command(dx, dy);

                door_count++;
            }
        }
    }

    snapshot->adjacent_door_count = door_count;
}

/*
 * Detect nearby enemies and fill snapshot
 */
static void detect_nearby_enemies(GameStateSnapshot *snapshot)
{
    int px = u.ux;
    int py = u.uy;
    int enemy_count = 0;

    /* Guard: fmon could be NULL if no monsters on level */
    if (!fmon) {
        snapshot->nearby_enemy_count = 0;
        return;
    }

    /* Scan nearby monsters (simple radius check for PoC) */
    struct monst *mtmp;
    for (mtmp = fmon; mtmp; mtmp = mtmp->nmon) {
        if (DEADMONSTER(mtmp)) continue;
        if (!mtmp->data) continue;

        int mx = mtmp->mx;
        int my = mtmp->my;

        /* Manhattan distance */
        int dist = abs(mx - px) + abs(my - py);
        if (dist > 10) continue;  /* Only nearby enemies */
        if (enemy_count >= MAX_NEARBY_ENEMIES) break;

        SnapshotEnemyInfo *enemy = &snapshot->nearby_enemies[enemy_count];
        const char *name = mon_nam(mtmp);
        strncpy(enemy->name, name, 63);
        enemy->name[63] = '\0';
        enemy->x = mx;
        enemy->y = my;
        enemy->distance = dist;
        enemy->hp = mtmp->mhp;
        enemy->max_hp = mtmp->mhpmax;
        enemy->is_hostile = !mtmp->mpeaceful;
        enemy->is_peaceful = mtmp->mpeaceful;
        enemy->glyph_char = monsym(mtmp->data);

        enemy_count++;
    }

    snapshot->nearby_enemy_count = enemy_count;
}

/*
 * Update game state snapshot (called after each NetHack turn)
 * THREAD: NetHack game thread
 */
void update_game_state_snapshot(void)
{
    /* Guard: Game must be running */
    if (!u.ux || !u.uy) {
        return;  /* Player not initialized yet */
    }

    /* Guard: Don't update during death - game state may be invalid */
    if (player_has_died || program_state.gameover) {
        return;
    }

    /* Get write buffer (inactive buffer) */
    int read_idx = atomic_load(&current_buffer_index);
    int write_idx = (read_idx + 1) % 2;
    GameStateSnapshot *snapshot = &buffers[write_idx];

    /* Clear previous data */
    memset(snapshot, 0, sizeof(GameStateSnapshot));

    /* Turn tracking */
    extern struct instance_globals_saved_m svm;
    snapshot->turn_number = svm.moves;

    /* Player stats */
    snapshot->player_hp = u.uhp;
    snapshot->player_max_hp = u.uhpmax;
    snapshot->player_ac = u.uac;
    snapshot->player_level = u.ulevel;
    snapshot->player_xp = u.uexp;
    snapshot->player_x = u.ux;
    snapshot->player_y = u.uy;

    /* Gold - safe to call from game thread (no race condition!) */
    extern struct instance_globals_i gi;
    extern long money_cnt(struct obj *);
    snapshot->player_gold = gi.invent ? money_cnt(gi.invent) : 0;

    /* Current tile terrain */
    int px = u.ux;
    int py = u.uy;
    snapshot->terrain_type = levl[px][py].typ;

    /* Check for stairs/ladder */
    if (levl[px][py].typ == STAIRS || levl[px][py].typ == LADDER) {
        stairway *stway = stairway_at(px, py);
        if (stway) {
            snapshot->is_ladder = stway->isladder;
            snapshot->is_stairs_up = stway->up;
            snapshot->is_stairs_down = !stway->up;

            if (stway->isladder) {
                strncpy(snapshot->terrain_name, "ladder", 63);
                snapshot->terrain_char = stway->up ? '<' : '>';
            } else {
                if (stway->up) {
                    strncpy(snapshot->terrain_name, "staircase up", 63);
                    snapshot->terrain_char = '<';
                } else {
                    strncpy(snapshot->terrain_name, "staircase down", 63);
                    snapshot->terrain_char = '>';
                }
            }
        }
    }

    /* Check for special terrain */
    snapshot->is_altar = IS_ALTAR(levl[px][py].typ);
    snapshot->is_fountain = IS_FOUNTAIN(levl[px][py].typ);
    snapshot->is_sink = IS_SINK(levl[px][py].typ);
    snapshot->is_throne = IS_THRONE(levl[px][py].typ);

    /* Find level features (stairs, altar, fountain) */
    /* Initialize to -1 (not found) */
    snapshot->stairs_up_x = -1;
    snapshot->stairs_up_y = -1;
    snapshot->stairs_down_x = -1;
    snapshot->stairs_down_y = -1;
    snapshot->altar_x = -1;
    snapshot->altar_y = -1;
    snapshot->fountain_x = -1;
    snapshot->fountain_y = -1;

    /* Find stairs using NetHack's stairway_find_dir() functions */
    stairway *stway_up = stairway_find_dir(TRUE);  /* Find upward stairs */
    if (stway_up) {
        snapshot->stairs_up_x = stway_up->sx;
        snapshot->stairs_up_y = stway_up->sy;
    }

    stairway *stway_down = stairway_find_dir(FALSE);  /* Find downward stairs */
    if (stway_down) {
        snapshot->stairs_down_x = stway_down->sx;
        snapshot->stairs_down_y = stway_down->sy;
    }

    /* Scan for first visible altar and fountain */
    for (int x = 1; x < COLNO; x++) {
        for (int y = 0; y < ROWNO; y++) {
            if (IS_ALTAR(levl[x][y].typ) && snapshot->altar_x == -1) {
                snapshot->altar_x = x;
                snapshot->altar_y = y;
            }
            if (IS_FOUNTAIN(levl[x][y].typ) && snapshot->fountain_x == -1) {
                snapshot->fountain_x = x;
                snapshot->fountain_y = y;
            }
        }
    }

    /* Detect adjacent doors */
    detect_adjacent_doors(snapshot);

    /* Detect nearby enemies */
    detect_nearby_enemies(snapshot);

    /* Count items at player position (for instant "Pick Up" button) */
    /* NOTE: Full item details still fetched async (names, descriptions) */
    /* This count is ONLY for showing "Pick Up" action instantly */
    int item_count = 0;
    bool has_container = false;
    bool has_locked_container = false;

    /* Bounds check (defensive programming) */
    if (px >= 0 && px < COLNO && py >= 0 && py < ROWNO) {
        /* Sanity limit - prevent infinite loop */
        const int MAX_ITEMS_PER_TILE = 100;
        struct obj *obj;
        struct obj *first_obj = svl.level.objects[px][py];

        for (obj = first_obj;
             obj && item_count < MAX_ITEMS_PER_TILE;
             obj = obj->nexthere) {
            if (obj != uchain) {  /* Exclude chain (if punished) */
                item_count++;
                /* Check for container (for Loot action) */
                if (Is_container(obj)) {
                    has_container = true;
                    /* Check if locked (for Force/Kick actions) */
                    if (obj->olocked) {
                        has_locked_container = true;
                    }
                }
            }
        }
    }

    snapshot->item_count = item_count;
    snapshot->has_container = has_container;
    snapshot->has_locked_container = has_locked_container;

    /* Atomic swap - readers now see new data (lock-free!) */
    atomic_store(&current_buffer_index, write_idx);
}
