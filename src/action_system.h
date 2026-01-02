//
//  action_system.h
//  nethack
//
//  Generic action handler system for directional commands
//  Provides DRY, testable, extensible architecture for tile-based actions
//

#ifndef ACTION_SYSTEM_H
#define ACTION_SYSTEM_H

#include <stdbool.h>

// Validation flags for different action types
typedef enum {
    VALIDATION_NONE     = 0,        // No validation
    VALIDATION_ADJACENT = 1 << 0,   // Must be adjacent (melee actions)
    VALIDATION_NOT_SELF = 1 << 1,   // Cannot target own position
    VALIDATION_RANGED   = 1 << 2    // Ranged action (no adjacency check)
} ValidationFlags;

// Direction information after coordinate conversion
typedef struct {
    int map_x, map_y;     // Map coordinates (converted from buffer)
    int dx, dy;           // Direction offset from player
    bool valid;           // Did conversion succeed?
} DirectionInfo;

// Generic directional action executor
// This function handles ALL directional commands (kick, open, close, fire, etc.)
// Returns: 0 on success, -1 on error
int execute_directional_action(
    int buffer_x,               // Buffer X coordinate (from Swift)
    int buffer_y,               // Buffer Y coordinate (from Swift)
    int (*nethack_func)(void),  // NetHack function to call (dokick, doopen, etc.)
    const char* action_name,    // Action name for logging ("KICK", "OPEN", etc.)
    int validation_flags        // Validation requirements (VALIDATION_ADJACENT, etc.)
);

// Helper functions (can be used independently for testing)
DirectionInfo calculate_direction(int buffer_x, int buffer_y);
bool validate_direction(const DirectionInfo* info, int flags, const char* action);

#endif /* ACTION_SYSTEM_H */
