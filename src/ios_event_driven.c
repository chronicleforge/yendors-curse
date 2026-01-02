/*
 * ios_event_driven.c - Event-driven NetHack for SwiftUI integration
 *
 * NO THREADING - NetHack runs one command at a time from the UI thread
 * This is the PROPER way to integrate with iOS!
 */

#include "../NetHack/include/hack.h"
#include "../NetHack/include/func_tab.h"

// State machine for event-driven operation
typedef enum {
    NETHACK_IDLE,           // Waiting for input
    NETHACK_PROCESSING,     // Processing a command
    NETHACK_NEEDS_INPUT,    // Needs user input (menu, prompt, etc)
    NETHACK_GAME_OVER       // Game ended
} NetHackState;

static NetHackState current_state = NETHACK_IDLE;
static int game_initialized = 0;

/*
 * Initialize NetHack for event-driven operation
 * Called once from SwiftUI at app start
 */
int ios_nethack_init_event_driven(void) {
    if (game_initialized) return 1;

    // Initialize using the compliant sequence we fixed
    extern void nethack_real_init(void);
    nethack_real_init();

    game_initialized = 1;
    current_state = NETHACK_IDLE;

    return 1;
}

/*
 * Start a new game - called from SwiftUI
 * Returns immediately after setup
 */
int ios_nethack_start_game(void) {
    if (!game_initialized) return 0;

    extern void nethack_real_newgame(void);
    nethack_real_newgame();

    current_state = NETHACK_IDLE;
    return 1;
}

/*
 * Process one input character
 * Called from SwiftUI when user taps/types
 * Returns immediately after processing
 */
int ios_nethack_process_input(char ch) {
    if (current_state != NETHACK_IDLE) {
        return 0; // Busy
    }

    current_state = NETHACK_PROCESSING;

    // Queue the input
    extern void ios_queue_input(char);
    ios_queue_input(ch);

    // Process ONE command through rhack
    extern void rhack(int);
    rhack(0);

    current_state = NETHACK_IDLE;
    return 1;
}

/*
 * Process pending NetHack events
 * Called from SwiftUI timer (60Hz or as needed)
 * Non-blocking - returns immediately
 */
int ios_nethack_tick(void) {
    if (current_state != NETHACK_IDLE) {
        return 0; // Still processing
    }

    // Check for any pending NetHack work
    extern void update_inventory(void);
    extern void bot(void);

    // Update status and botline
    bot();

    // Flush any pending output
    extern void flush_screen(int);
    flush_screen(0);

    return 1;
}

/*
 * Get current game state for SwiftUI
 */
NetHackState ios_nethack_get_state(void) {
    return current_state;
}

/*
 * Save game - synchronous, returns when complete
 */
int ios_nethack_save(const char* filepath) {
    if (current_state != NETHACK_IDLE) return 0;

    current_state = NETHACK_PROCESSING;

    extern int nethack_save_game(const char*);
    int result = nethack_save_game(filepath);

    current_state = NETHACK_IDLE;
    return result;
}

/*
 * Load game - synchronous, returns when complete
 */
int ios_nethack_load(const char* filepath) {
    if (game_initialized && current_state != NETHACK_IDLE) return 0;

    current_state = NETHACK_PROCESSING;

    extern int nethack_load_game_new(const char*);
    int result = nethack_load_game_new(filepath);

    current_state = result ? NETHACK_IDLE : NETHACK_GAME_OVER;
    return result;
}

/*
 * Clean shutdown
 */
void ios_nethack_cleanup(void) {
    if (!game_initialized) return;

    // Clean shutdown through proper NetHack exit
    extern void nh_terminate(int);
    nh_terminate(0);

    game_initialized = 0;
    current_state = NETHACK_GAME_OVER;
}