/*
 * ios_memory_integration.h - Memory allocator integration interface
 */

#ifndef IOS_MEMORY_INTEGRATION_H
#define IOS_MEMORY_INTEGRATION_H

#include "../NetHack/include/dlb.h"

/* Initialize memory subsystem (call at startup) */
int ios_memory_init(void);

/* Save/restore with memory state */
int ios_savegamestate_with_memory(NHFILE *nhfp);
int ios_restgamestate_with_memory(NHFILE *nhfp);

/* Cleanup for new game */
void ios_cleanup_memory_state(void);

/* Debug */
void ios_dump_memory_stats(void);

#endif /* IOS_MEMORY_INTEGRATION_H */