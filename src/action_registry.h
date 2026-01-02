//
//  action_registry.h
//  nethack
//
//  Central registry for all directional actions
//  Single source of truth for action configuration
//

#ifndef ACTION_REGISTRY_H
#define ACTION_REGISTRY_H

#include "action_system.h"

// Action definition structure
typedef struct {
    const char* name;           // Action name for logging ("KICK", "OPEN", etc.)
    int (*nethack_func)(void);  // NetHack function to execute
    int validation_flags;       // Validation requirements
} ActionDef;

// Directional action registry
// Add new actions here - this is the ONLY place you need to define them!
extern const ActionDef ACTION_KICK;
extern const ActionDef ACTION_OPEN;
extern const ActionDef ACTION_CLOSE;
extern const ActionDef ACTION_FIRE;
extern const ActionDef ACTION_THROW;
extern const ActionDef ACTION_UNLOCK;
extern const ActionDef ACTION_LOCK;

#endif /* ACTION_REGISTRY_H */
