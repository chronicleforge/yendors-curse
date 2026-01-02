/*
 * ios_game_lifecycle.h
 *
 * Game lifecycle management for NetHack iOS port
 * Handles proper shutdown, memory cleanup, and reinitialization for multiple game sessions
 *
 * Created: 2025-10-02
 * Purpose: Enable multiple game sessions without process restart
 */

#ifndef IOS_GAME_LIFECYCLE_H
#define IOS_GAME_LIFECYCLE_H

#include "nethack_export.h"

/*
 * ios_shutdown_game - Orderly NetHack shutdown
 *
 * Performs complete game shutdown following NetHack's own design:
 * - Calls freedynamicdata() to free ALL game objects and memory
 * - Calls dlb_cleanup() to close data files
 * - Calls l_nhcore_done() to shutdown Lua state
 * - Resets program_state flags to clean state
 *
 * This mimics what NetHack does in really_done() before exit(0).
 * CRITICAL: Must be called BEFORE ios_wipe_memory()
 */
NETHACK_EXPORT void ios_shutdown_game(void);

/*
 * ios_wipe_memory - Zone allocator memory wipe
 *
 * Calls nh_restart() to memset the entire static heap to zero.
 * This is ONLY safe AFTER ios_shutdown_game() has freed all active structures.
 *
 * CRITICAL: Do NOT call while game structures are still active!
 * MUST be called after ios_shutdown_game() and before ios_reinit_subsystems().
 */
NETHACK_EXPORT void ios_wipe_memory(void);

/*
 * ios_reinit_subsystems - Re-initialize NetHack subsystems
 *
 * Re-initializes all subsystems that were shut down:
 * - Calls dlb_init() to re-initialize data file library
 * - Calls l_nhcore_init() to create new Lua state
 * - Calls ios_reset_all_static_state() to reset iOS bridge state
 *
 * After this, the system is ready for nethack_real_init() → startGame().
 * CRITICAL: Must be called AFTER ios_wipe_memory()
 */
NETHACK_EXPORT void ios_reinit_subsystems(void);

#endif /* IOS_GAME_LIFECYCLE_H */
