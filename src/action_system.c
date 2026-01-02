//
//  action_system.c
//  nethack
//
//  Generic action handler implementation
//  Eliminates code duplication for directional commands
//

#include "action_system.h"
#include <stdio.h>
#include <stdlib.h>

// NetHack includes
#include "../NetHack/include/hack.h"

// Map Y offset for message lines
#define MAP_Y_OFFSET 2

// Calculate direction from buffer coordinates to map coordinates
DirectionInfo calculate_direction(int buffer_x, int buffer_y) {
    DirectionInfo info = {0};
    extern struct you u;  // NetHack's player struct

    // Convert buffer coords to map coords
    // Buffer has 2 message lines at top, map doesn't
    info.map_x = buffer_x;
    info.map_y = buffer_y - MAP_Y_OFFSET;

    // Validate X coordinate
    if (info.map_x < 0 || info.map_x >= COLNO) {
        info.valid = false;
        fprintf(stderr, "[ActionSystem] Invalid map_x=%d from buffer(%d,%d)\n",
                info.map_x, buffer_x, buffer_y);
        return info;
    }

    // Validate Y coordinate
    if (info.map_y < 0 || info.map_y >= ROWNO) {
        info.valid = false;
        fprintf(stderr, "[ActionSystem] Invalid map_y=%d from buffer(%d,%d)\n",
                info.map_y, buffer_x, buffer_y);
        return info;
    }

    // Calculate direction offset from player to target
    info.dx = info.map_x - u.ux;
    info.dy = info.map_y - u.uy;
    info.valid = true;

    return info;
}

// Validate direction based on action requirements
bool validate_direction(const DirectionInfo* info, int flags, const char* action) {
    if (!info || !info->valid) {
        fprintf(stderr, "[%s] Invalid direction info\n", action);
        return false;
    }

    // Check self-targeting
    if ((flags & VALIDATION_NOT_SELF) && info->dx == 0 && info->dy == 0) {
        fprintf(stderr, "[%s] Cannot target own position\n", action);
        return false;
    }

    // Check adjacency (only for melee, not for ranged)
    if ((flags & VALIDATION_ADJACENT) &&
        !(flags & VALIDATION_RANGED) &&
        (abs(info->dx) > 1 || abs(info->dy) > 1)) {
        fprintf(stderr, "[%s] Target map(%d,%d) not adjacent to player map(%d,%d)\n",
                action, info->map_x, info->map_y,
                info->map_x - info->dx, info->map_y - info->dy);
        return false;
    }

    return true;
}

// Generic directional action executor
// This is the core function that ALL directional commands use
int execute_directional_action(
    int buffer_x,
    int buffer_y,
    int (*nethack_func)(void),
    const char* action_name,
    int validation_flags
) {
    // Sanity checks
    if (!nethack_func) {
        fprintf(stderr, "[%s] NULL NetHack function pointer\n", action_name);
        return -1;
    }

    if (!action_name) {
        action_name = "UNKNOWN";
    }

    // Step 1: Convert coordinates and calculate direction
    DirectionInfo dir = calculate_direction(buffer_x, buffer_y);
    if (!dir.valid) {
        return -1;
    }

    // Step 2: Validate based on action requirements
    if (!validate_direction(&dir, validation_flags, action_name)) {
        return -1;
    }

    // Step 3: Log action (for debugging)
    fprintf(stderr, "[%s] Executing at map(%d,%d) [buffer(%d,%d)] in direction (%d,%d)\n",
            action_name, dir.map_x, dir.map_y, buffer_x, buffer_y, dir.dx, dir.dy);

    // Step 4: Queue command + direction atomically
    // This is CRITICAL - must be atomic to avoid "In what direction?" prompts
    extern void cmdq_add_ec(int queue, int (*func)(void));
    extern void cmdq_add_dir(int queue, schar dx, schar dy, schar dz);

    cmdq_add_ec(CQ_CANNED, nethack_func);
    cmdq_add_dir(CQ_CANNED, (schar)dir.dx, (schar)dir.dy, 0);

    fprintf(stderr, "[%s] Queued command with direction (%d,%d)\n",
            action_name, dir.dx, dir.dy);

    // Step 5: CRITICAL - Wake up game thread!
    // The game thread is blocked in poskey() waiting for ios_queue_input.
    // CQ_CANNED is a separate queue that rhack() checks BEFORE calling poskey().
    // By queuing a null byte, we wake up poskey() so rhack() can check CQ_CANNED!
    extern void ios_queue_input(char);
    ios_queue_input('\0');  // Wake-up signal

    fprintf(stderr, "[%s] Wake-up signal sent to game thread\n", action_name);

    return 0;
}
