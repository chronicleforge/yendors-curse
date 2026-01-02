//
//  action_registry.c
//  nethack
//
//  Action definitions - single source of truth
//

#include "action_registry.h"

// NetHack function declarations
extern int dokick(void);    // dokick.c - kick command
extern int doopen(void);    // lock.c - open door
extern int doclose(void);   // lock.c - close door
extern int dofire(void);    // dothrow.c - fire quiver
extern int dothrow(void);   // dothrow.c - throw item
extern int doapply(void);   // apply.c - apply tool (unlock/lock)

// Action definitions
// Each action specifies:
// - name: For logging/debugging
// - nethack_func: NetHack C function to call
// - validation_flags: Requirements (adjacent, not-self, ranged)

const ActionDef ACTION_KICK = {
    .name = "KICK",
    .nethack_func = dokick,
    .validation_flags = VALIDATION_ADJACENT | VALIDATION_NOT_SELF
};

const ActionDef ACTION_OPEN = {
    .name = "OPEN",
    .nethack_func = doopen,
    .validation_flags = VALIDATION_ADJACENT | VALIDATION_NOT_SELF
};

const ActionDef ACTION_CLOSE = {
    .name = "CLOSE",
    .nethack_func = doclose,
    .validation_flags = VALIDATION_ADJACENT | VALIDATION_NOT_SELF
};

const ActionDef ACTION_FIRE = {
    .name = "FIRE",
    .nethack_func = dofire,
    .validation_flags = VALIDATION_NOT_SELF | VALIDATION_RANGED  // Ranged, no adjacency!
};

const ActionDef ACTION_THROW = {
    .name = "THROW",
    .nethack_func = dothrow,
    .validation_flags = VALIDATION_NOT_SELF | VALIDATION_RANGED  // Ranged, no adjacency!
};

const ActionDef ACTION_UNLOCK = {
    .name = "UNLOCK",
    .nethack_func = doapply,
    .validation_flags = VALIDATION_ADJACENT | VALIDATION_NOT_SELF
};

const ActionDef ACTION_LOCK = {
    .name = "LOCK",
    .nethack_func = doapply,
    .validation_flags = VALIDATION_ADJACENT | VALIDATION_NOT_SELF
};
