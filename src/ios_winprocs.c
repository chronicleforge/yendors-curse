/*
 * ios_winprocs.c - iOS Window Procedures for NetHack
 *
 * This implements the window interface that NetHack needs to run.
 * All display output from NetHack goes through these functions.
 */

#include "nethack_export.h"  // Symbol visibility control
#include "../NetHack/include/hack.h"
#include "../NetHack/include/func_tab.h"  /* For extcmds_match, ECM_* */
#include "../NetHack/include/winprocs.h" /* For WC_ constants */
#include "ios_render_queue.h" /* PHASE 1: Lock-free render queue */
#include "ios_wincap.h"
#include "ios_yn_callback.h"
#include <ctype.h> /* For isprint() */
#include <stdio.h>
#include <string.h>
#include <time.h> /* For clock_gettime */

/* Temporarily undefine FALSE/TRUE to avoid conflict with iOS headers */
#ifdef FALSE
#undef FALSE
#endif
#ifdef TRUE
#undef TRUE
#endif

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdatomic.h> /* C11 atomics for thread-safe exit flag */

/* Restore NetHack's definitions after iOS headers */
#ifndef FALSE
#define FALSE ((boolean)0)
#endif
#ifndef TRUE
#define TRUE ((boolean)1)
#endif

/* External buffer for output
 * CRITICAL: ios_winprocs.c is compiled INTO the dylib and needs direct
 * buffer access, not through the macro. We declare the actual buffer here.
 */
#define OUTPUT_BUFFER_SIZE 8192
extern char internal_output_buffer[OUTPUT_BUFFER_SIZE];
#define output_buffer internal_output_buffer

/* External game state */
extern int game_started;
extern int character_creation_complete;

/* Player stats storage for Swift access */
typedef struct {
  int hp, hpmax;
  int pw, pwmax; /* Power/mana */
  int level;
  long exp;
  int ac;
  int str, dex, con, intel, wis, cha;
  long gold;
  long moves;
  char align[16]; /* Alignment string */
  int hunger;     /* Hunger state */
  unsigned long conditions; /* BL_CONDITION bitmask (30 flags) */
} PlayerStats;

static PlayerStats current_stats = {0};

/* Getter for current_stats.conditions - used by RealNetHackBridge.c */
unsigned long ios_get_current_conditions(void) {
    return current_stats.conditions;
}

/* Death information */
#include "RealNetHackBridge.h"
DeathInfo death_info = {0}; // Made non-static for RealNetHackBridge.c
static int is_capturing_death_info = 0;
static int death_info_stage =
    0; // 0=not capturing, 1=possessions, 2=attributes, 3=conduct, 4=overview,
       // 5=vanquished
int player_has_died = 0; // Made non-static for RealNetHackBridge.c
YNResponseCallback yn_callback =
    NULL;                           // Made non-static for RealNetHackBridge.c
YNContext current_yn_context = {0}; // Made non-static for RealNetHackBridge.c

/* Debug logging */
#define WIN_LOG(fmt, ...) fprintf(stderr, "[WINPROC] " fmt "\n", ##__VA_ARGS__)

/* Forward declaration for ios_wait_synch - used in ios_get_nh_event */
void ios_wait_synch(void);  // Non-static - also used by RealNetHackBridge.c

/* Safe buffer append - prevents buffer overflow */
static void safe_append_to_output(const char *str) {
  if (!str)
    return;

  size_t current_len = strlen(output_buffer);
  size_t str_len = strlen(str);
  size_t available =
      OUTPUT_BUFFER_SIZE - current_len - 1; /* -1 for null terminator */

  if (str_len >= available) {
    fprintf(
        stderr,
        "[WINPROC] WARNING: Buffer overflow prevented, truncating output\n");
    strncat(output_buffer, str, available);
    return;
  }

  strcat(output_buffer, str);
}

/* Forward declarations for map functions */
extern void ios_swift_map_update_callback(void);

/* Death animation callback - registered by Swift at startup */
typedef void (*DeathAnimationCallback)(void);
static DeathAnimationCallback death_animation_callback = NULL;

/* Register death animation callback from Swift */
NETHACK_EXPORT void ios_set_death_animation_callback(DeathAnimationCallback callback) {
    death_animation_callback = callback;
    fprintf(stderr, "[DEATH] Death animation callback registered: %p\n", (void*)callback);
}

/* Call death animation callback (if registered) */
static void trigger_death_animation(void) {
    if (death_animation_callback) {
        fprintf(stderr, "[DEATH] ☠️ TRIGGERING SWIFT DEATH ANIMATION\n");
        death_animation_callback();
    } else {
        fprintf(stderr, "[DEATH] ⚠️ No death animation callback registered\n");
    }
}

/* Window handles */
static winid message_win = 1;
static winid map_win = 2;
static winid status_win = 3;
static winid menu_win = 4;
static winid text_win = 5;

/* Menu system state - must be declared early for destroy_nhwindow */
#define MAX_MENU_ITEMS 256
#define MAX_MENU_TEXT 256
static MENU_ITEM_P menu_items[MAX_MENU_ITEMS]; // Storage for menu selections
static char menu_selectors[MAX_MENU_ITEMS];    // Selector characters for each menu item
static char menu_texts[MAX_MENU_ITEMS][MAX_MENU_TEXT];  // Store menu item text for Swift
static int menu_glyphs[MAX_MENU_ITEMS];        // Store glyph IDs for Swift
static int menu_attributes[MAX_MENU_ITEMS];    // Store ATR_* attributes for Swift
static unsigned int menu_itemflags[MAX_MENU_ITEMS];  // Store itemflags for Swift
static int menu_item_count = 0;
static winid current_menu_win = 0;
static boolean menu_is_active = FALSE;
static char last_menu_prompt[256] = {0}; // Store last menu prompt for tutorial detection

/* Menu callback system - for Swift UI integration */
static IOSMenuCallback swift_menu_callback = NULL;
static pthread_mutex_t menu_callback_mutex = PTHREAD_MUTEX_INITIALIZER;

/* Menu response synchronization - C waits for Swift to respond */
static IOSMenuSelection menu_response_selections[MAX_MENU_ITEMS];
static int menu_response_count = -1;  // -1 = waiting, 0+ = got response
static pthread_mutex_t menu_response_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t menu_response_cond = PTHREAD_COND_INITIALIZER;

/* Input queue for commands from iOS */
#define INPUT_QUEUE_SIZE 256
static char input_queue[INPUT_QUEUE_SIZE];
static int input_queue_head = 0;
static int input_queue_tail = 0;

/* Thread synchronization for input */
static pthread_mutex_t input_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t input_cond = PTHREAD_COND_INITIALIZER;
volatile int game_thread_running = 0; /* Made global for RealNetHackBridge.c */

/* Mode selection flag - 0 = old mode, 1 = threaded mode */
int use_threaded_mode = 0; /* Made global for RealNetHackBridge.c */

/* Exit flag - when 1, game loop should terminate cleanly
 * CRITICAL: Uses C11 atomics for ARM64 thread safety (volatile is NOT
 * sufficient!) Root Cause: volatile only prevents compiler optimizations, NOT
 * CPU reordering Fix: atomic_int guarantees memory barriers for multi-core
 * correctness
 */
static atomic_int game_should_exit = ATOMIC_VAR_INIT(0);

// Map data buffer - dynamically sized for modern displays
// Maximum supported dimensions
#define MAX_MAP_WIDTH 180 // Support ultra-wide displays
#define MAX_MAP_HEIGHT 60 // Support tall displays
// Default dimensions (can be adjusted at runtime)
#define DEFAULT_MAP_WIDTH 120 // Larger for iPad
#define DEFAULT_MAP_HEIGHT 40 // More vertical space

/*
 * === COORDINATE SYSTEM DOCUMENTATION ===
 *
 * This iOS port uses THREE coordinate spaces that must be carefully
 * transformed:
 *
 * 1. NetHack Engine Coordinates (used by NetHack core):
 *    - X: 1-79 (1-based, COLNO=80, column 0 is unused by NetHack)
 *    - Y: 0-20 (0-based, ROWNO=21)
 *    - Example: Player at NetHack (8, 5) means column 8, row 5
 *
 * 2. C Buffer Coordinates (internal to ios_winprocs.c):
 *    - X: 1-79 (same as NetHack, 1-based)
 *    - Y: 2-22 (NetHack Y + 2 offset for message lines at top)
 *    - map_buffer[buffer_y][buffer_x] stores the ASCII char
 *    - map_cells[buffer_y][buffer_x] stores full glyph data
 *
 * 3. Swift Coordinates (used by iOS UI code):
 *    - X: 0-(width-1) (0-based array indices)
 *    - Y: 0-(height-1) (0-based array indices)
 *    - tiles[swift_y][swift_x] in MapState
 *    - Example: NetHack (8, 5) → Swift (7, 5) after 1-based → 0-based
 * conversion
 *
 * CRITICAL: When passing coordinates to Swift via ios_capture_map(), we must:
 *   1. Remove the buffer Y offset (-2)
 *   2. Convert NetHack 1-based X to Swift 0-based X (-1)
 *   3. NetHack 0-based Y already matches Swift 0-based Y (no change)
 *
 * The coordinate conversion API below handles NetHack ↔ Buffer transformations.
 * Swift side uses CoordinateConverter class for Swift ↔ SceneKit
 * transformations.
 */

// NetHack coordinate system constants
// NetHack map: x: 1-79 (COLNO=80, col 0 unused), y: 0-20 (ROWNO=21)
// Terminal layout has 2+ message lines at top, then map
#define MAP_Y_OFFSET 2 // Offset from NetHack map Y to display buffer Y

// Defensive coordinate mapping API
static inline int map_y_to_buffer_y(int map_y) {
  // NetHack map Y (0-20) -> Buffer Y (2-22)
  if (map_y < 0 || map_y >= ROWNO)
    return -1; // Invalid
  return map_y + MAP_Y_OFFSET;
}

static inline int map_x_to_buffer_x(int map_x) {
  // NetHack map X (1-79) -> Buffer X (1-79) - no offset
  if (map_x < 1 || map_x >= COLNO)
    return -1; // Invalid (col 0 unused)
  return map_x;
}

// REMOVED: buffer_y_to_map_y() - not needed with queue-based rendering

// Helper: NetHack X to Swift X (for reference - not used in C, but documents
// conversion) static inline int nethack_x_to_swift_x(int nethack_x) {
//     // NetHack X (1-79) -> Swift X (0-78)
//     return nethack_x - 1;
// }

// Simple map buffer for ASCII
char map_buffer[MAX_MAP_HEIGHT][MAX_MAP_WIDTH + 1];   // +1 for null terminator
char captured_map[MAX_MAP_HEIGHT][MAX_MAP_WIDTH + 1]; // Captured map for Swift
boolean map_dirty = FALSE;

// Enhanced map data with glyph info
typedef struct {
  int glyph;           // NetHack glyph ID
  char ch;             // ASCII character
  unsigned char color; // Color index
  unsigned char bg;    // Background color
} MapCell;

MapCell map_cells[MAX_MAP_HEIGHT][MAX_MAP_WIDTH]; // Full map data
int actual_map_width = DEFAULT_MAP_WIDTH;         // Runtime-adjustable width
int actual_map_height = DEFAULT_MAP_HEIGHT;       // Runtime-adjustable height

// Function to dynamically adjust map dimensions based on device
void ios_set_map_dimensions(int width, int height) {
  if (width > 0 && width <= MAX_MAP_WIDTH) {
    actual_map_width = width;
  }
  if (height > 0 && height <= MAX_MAP_HEIGHT) {
    actual_map_height = height;
  }
  WIN_LOG("Map dimensions set to %dx%d", actual_map_width, actual_map_height);
}

/* === Window Procedures Implementation === */

static void ios_init_nhwindows(int *argcp, char **argv) {
  WIN_LOG("init_nhwindows");

  // === DISPLAY COPYRIGHT BANNER (REQUIRED by porting guidelines) ===
  // Reference: doc/window.txt Section VII
  raw_print("");
  raw_print(COPYRIGHT_BANNER_A);
  raw_print(COPYRIGHT_BANNER_B);
  raw_print(COPYRIGHT_BANNER_C);
  raw_print(COPYRIGHT_BANNER_D);
  raw_print("");

  iflags.cbreak = ON;
  iflags.echo = OFF;

  // Initialize game state buffer (Push Model for lock-free Swift reads)
  extern void init_game_state_buffer(void);
  init_game_state_buffer();

  // Clear map buffer on init
  memset(map_buffer, ' ', sizeof(map_buffer));
  for (int y = 0; y < MAX_MAP_HEIGHT; y++) {
    map_buffer[y][MAX_MAP_WIDTH] = '\0'; // Null terminate each row
  }
  map_dirty = FALSE;

  // PHASE 1: Initialize render queue
  if (!g_render_queue) {
    g_render_queue = (RenderQueue *)malloc(sizeof(RenderQueue));
    if (g_render_queue) {
      render_queue_init(g_render_queue);
      fprintf(stderr, "[QUEUE] Render queue initialized\n");
    } else {
      fprintf(stderr, "[QUEUE] ERROR: Failed to allocate render queue!\n");
    }
  }

  fprintf(stderr, "[MAP] Map buffer initialized\n");
}

static void ios_player_selection(void) {
  WIN_LOG("player_selection");
  /* Character selection is handled by Swift UI */
}

// External globals for player name
extern struct instance_globals_saved_p svp;

static void ios_askname(void) {
  WIN_LOG("askname");

  // Check if name was already set by UI
  if (strlen(svp.plname) == 0) {
    strcpy(svp.plname, "Hero");
    fprintf(stderr, "[IOS] Using default player name: %s\n", svp.plname);
  } else {
    fprintf(stderr, "[IOS] Player name already set by UI: %s\n", svp.plname);
  }
}

static void ios_get_nh_event(void) {
  /* WIN_LOG("get_nh_event"); - too verbose */
  // This function is called to process events
  // For iOS, we don't need to do anything special here
  // Input is handled through nh_poskey

  // CRITICAL FIX: Call wait_synch() after EVERY event!
  // NetHack's moveloop calls get_nh_event() after processing each command
  // This is the perfect place to sync the display with Swift UI
  ios_wait_synch();

  // Debug logging for player position issue
  static int debug_counter = 0;
  if (debug_counter++ % 100 == 0) { // Log every 100th call to reduce spam
    fprintf(stderr,
            "[GET_NH_EVENT] u.umovement=%d u.umoved=%d u.ux=%d u.uy=%d\n",
            u.umovement, u.umoved, u.ux, u.uy);
    fflush(stderr);
  }
}

/* Flag to track if we're in a save operation - not static so
 * ios_save_intercept.c can access it */
int ios_save_exit_intercepted = 0;

static void ios_exit_nhwindows(const char *str) {
  WIN_LOG("exit_nhwindows: %s", str ? str : "(null)");

  /* Check if player died and we have death info */
  if (player_has_died && (death_info.death_message[0] != '\0' ||
                          death_info.possessions[0] != '\0')) {
    fprintf(stderr, "[WINPROCS] ☠️ Player died - death info captured\n");
    fprintf(stderr, "[DEATH] Message: %s\n", death_info.death_message);
    fprintf(stderr, "[DEATH] Has possessions: %s\n",
            death_info.possessions[0] ? "yes" : "no");
    fprintf(stderr, "[DEATH] Has attributes: %s\n",
            death_info.attributes[0] ? "yes" : "no");
    fprintf(stderr, "[DEATH] Has conduct: %s\n",
            death_info.conduct[0] ? "yes" : "no");
    fprintf(stderr, "[DEATH] Has overview: %s\n",
            death_info.dungeon_overview[0] ? "yes" : "no");

    /* Clean shutdown of game engine only - NOT the app */
    fprintf(stderr, "[WINPROCS] Shutting down game engine (death case)...\n");

    /* Reset game state for next play */
    extern int game_started;
    extern int character_creation_complete;
    game_started = 0;
    character_creation_complete = 0;

    /* Don't call any cleanup that would crash - just return */
    /* Swift will handle showing the death screen and returning to menu */
    return;
  }

  /* Check if this is a save exit - NetHack uses "Be seeing you..." for saves */
  if (str && strstr(str, "Be seeing you")) {
    fprintf(stderr,
            "[WINPROCS] ✅ Detected save exit - creating snapshot instead\n");

    /* Create snapshot instead of normal save */
    {
      int result = 1; /* Snapshot is handled at Swift level */
      if (result) {
        fprintf(stderr,
                "[WINPROCS] Snapshot will be created - game continues\n");
        /* Don't set intercepted flag - we want game to continue */
        ios_save_exit_intercepted = 0;
        /* Clear the "Be seeing you" message since we're not actually exiting */
        return;
      } else {
        fprintf(stderr,
                "[WINPROCS] Snapshot failed - falling back to normal save\n");
      }
    }

    /* Fall back to normal save if snapshot not available or failed */
    ios_save_exit_intercepted = 1;

    /* Still add message to buffer so user sees it */
    if (str) {
      safe_append_to_output(str);
      safe_append_to_output("\n");
    }

    /* Don't do normal exit cleanup - we want to keep playing */
    return;
  }

  /* Normal exit */
  if (str) {
    safe_append_to_output(str);
    safe_append_to_output("\n");
  }
}

static void ios_suspend_nhwindows(const char *str) {
  WIN_LOG("suspend_nhwindows");
  /* iOS doesn't need special suspend handling */
}

static void ios_resume_nhwindows(void) {
  WIN_LOG("resume_nhwindows");
  /* iOS doesn't need special resume handling */
}

static winid ios_create_nhwindow(int type) {
  WIN_LOG("create_nhwindow");
  switch (type) {
  case NHW_MESSAGE:
    return message_win;
  case NHW_MAP:
    return map_win;
  case NHW_STATUS:
    return status_win;
  case NHW_MENU:
    return menu_win;
  case NHW_TEXT:
    return text_win;
  default:
    return text_win;
  }
}

static void ios_clear_nhwindow(winid win) {
  /* WIN_LOG("clear_nhwindow"); - DISABLED to reduce spam */
  if (win == map_win) {
    /* Clear map buffer when clearing map window */
    memset(map_buffer, ' ', sizeof(map_buffer));
    /* Null terminate each row */
    for (int y = 0; y < MAX_MAP_HEIGHT; y++) {
      map_buffer[y][MAX_MAP_WIDTH - 1] = '\0';
    }

    /* FIX: Also clear map_cells to prevent ghost tiles on level change */
    memset(map_cells, 0, sizeof(map_cells));

    /* FIX: Also clear captured_map */
    memset(captured_map, ' ', sizeof(captured_map));

    // PHASE 1: Enqueue clear command
    if (g_render_queue) {
      RenderQueueElement elem = {
          .type = CMD_CLEAR_MAP,
          .data.command = {.blocking = 0, .turn_number = 0}};
      render_queue_enqueue(g_render_queue, &elem);
    }

    map_dirty = TRUE; /* Mark as dirty so it gets redrawn */
  }
}

// REMOVED: debug_print_map() forward declaration - function deleted

// Callback for notifying Swift that the display needs updating
extern void ios_notify_map_changed(void);

// REMOVED: map_mutex - not needed with lock-free queue

// Capture the current map buffer for Swift to read
void ios_capture_map(void) {
  // Direct copy - no mutex needed in single-threaded app
  memcpy(captured_map, map_buffer, sizeof(map_buffer));
}

// Get a line from the captured map
const char *ios_get_captured_map_line(int y) {
  if (y >= 0 && y < MAX_MAP_HEIGHT) {
    // Direct access - single-threaded
    static char line_copy[MAX_MAP_WIDTH + 1];
    strncpy(line_copy, captured_map[y], MAX_MAP_WIDTH);
    line_copy[MAX_MAP_WIDTH] = '\0';
    return line_copy;
  }
  return "";
}

static void ios_display_nhwindow(winid win, boolean blocking) {
  /* NetHack rendering - ALWAYS NOTIFY on map changes.
   *
   * Called by flush_screen() for spell beams, explosions, turn updates.
   *
   * PREVIOUS BUG: Atomic coalescing dropped updates when main thread was busy.
   * FIX: Remove coalescing, always notify. Swift handles rapid updates fine.
   */

  if (win == map_win && map_dirty) {
    ios_capture_map();
    map_dirty = FALSE;

    // Always notify Swift - no coalescing, no dropped frames
    dispatch_async(dispatch_get_main_queue(), ^{
      ios_notify_map_changed();
    });
  }
}

static void ios_destroy_nhwindow(winid win) {
  WIN_LOG("destroy_nhwindow");

  // CRITICAL: Reset menu state when destroying menu windows
  // NetHack core ALWAYS calls destroy_nhwindow() after select_menu()
  // If we don't reset state, subsequent menus will access stale data
  // Reference: TTY port (wintty.c:2008), X11 port (winX.c:1224)

  if (win == menu_win || win == current_menu_win) {
    // Reset menu lifecycle state
    menu_item_count = 0;
    current_menu_win = 0;
    menu_is_active = FALSE;

    // Clear ALL menu arrays to prevent stale data access
    memset(menu_items, 0, sizeof(menu_items));
    memset(menu_selectors, 0, sizeof(menu_selectors));
    memset(menu_texts, 0, sizeof(menu_texts));
    memset(menu_glyphs, 0, sizeof(menu_glyphs));
    memset(menu_attributes, 0, sizeof(menu_attributes));
    memset(menu_itemflags, 0, sizeof(menu_itemflags));
    memset(last_menu_prompt, 0, sizeof(last_menu_prompt));

    fprintf(stderr, "[MENU] Menu window destroyed, state reset\n");
  }

  // Note: iOS uses static window IDs (not dynamic allocation)
  // So we don't free() window descriptors like TTY/X11 ports
  // We only reset transient state (menu data)
}

static void ios_curs(winid win, int x, int y) {
  /* WIN_LOG("curs"); - too verbose */
}

// REMOVED: suppress_messages_during_examine flag (architectural violation)
// OLD PROBLEM: do_look() Swift callbacks blocked main thread for 8 seconds
// NEW SOLUTION: examineTileAsync() runs on background queue → no main thread blocking
// Bridge should NOT control message delivery - that's game logic territory!

static void ios_putstr(winid win, int attr, const char *str) {
  if (!str) {
    return;
  }

  // Categorize message based on content (strip [brackets] for clean category
  // names)
  const char *category = "MSG"; // Default category

  // Categorize message based on content
  if (strstr(str, "door") || strstr(str, "Door") || strstr(str, "gate")) {
    category = "DOOR";
  } else if (strstr(str, "hit") || strstr(str, "Hit") ||
             strstr(str, "attack") || strstr(str, "miss") ||
             strstr(str, "kill") || strstr(str, "die") ||
             strstr(str, "damage") || strstr(str, "wound")) {
    category = "COMBAT";
  } else if (strstr(str, "pick up") || strstr(str, "drop") ||
             strstr(str, "throw") || strstr(str, "wield") ||
             strstr(str, "wear") || strstr(str, "take off") ||
             strstr(str, "put on") || strstr(str, "quiver")) {
    category = "ITEM";
  } else if (strstr(str, "eat") || strstr(str, "drink") ||
             strstr(str, "hungry") || strstr(str, "satiated") ||
             strstr(str, "starving")) {
    category = "FOOD";
  } else if (strstr(str, "move") || strstr(str, "walk") || strstr(str, "run") ||
             strstr(str, "climb") || strstr(str, "descend") ||
             strstr(str, "ascend")) {
    category = "MOVE";
  } else if (strstr(str, "cast") || strstr(str, "spell") ||
             strstr(str, "magic") || strstr(str, "mana")) {
    category = "MAGIC";
  } else if (strstr(str, "pray") || strstr(str, "altar") ||
             strstr(str, "sacrifice")) {
    category = "PRAY";
  } else if (strstr(str, "trap") || strstr(str, "Trap")) {
    category = "TRAP";
  } else if (strstr(str, "save") || strstr(str, "Save") ||
             strstr(str, "restore")) {
    category = "SAVE";
  } else if (strstr(str, "Welcome") || strstr(str, "Goodbye") ||
             strstr(str, "level")) {
    category = "SYSTEM";
    // Capture death messages and parse score only during death sequence
    if (!is_capturing_death_info) {
      // Not in death sequence - skip death message processing
    } else if (strstr(str, "Goodbye") || strstr(str, "You died") ||
               strstr(str, "You were")) {
      strncpy(death_info.death_message, str,
              sizeof(death_info.death_message) - 1);
      // Parse score from "with X point" in death message
      const char *point_str = strstr(str, " point");
      if (!point_str) {
        // No score in this death message
      } else {
        const char *with_str = strstr(str, "with ");
        if (with_str && with_str < point_str) {
          long parsed_score = strtol(with_str + 5, NULL, 10);
          if (parsed_score > 0) {
            death_info.final_score = parsed_score;
            fprintf(stderr, "[DEATH] Parsed final score from message: %ld\n",
                    parsed_score);
          }
        }
      }
    }
  } else if (win == message_win) {
    category = "INFO";
  }

  // Log with category and ATR_* attributes for better debugging
  fprintf(stderr, "[%s] '%s' (attr=0x%02X", category, str, attr);
  if (attr & ATR_BOLD)
    fprintf(stderr, " BOLD");
  if (attr & ATR_DIM)
    fprintf(stderr, " DIM");
  if (attr & ATR_INVERSE)
    fprintf(stderr, " INVERSE");
  if (attr & ATR_URGENT)
    fprintf(stderr, " URGENT");
  fprintf(stderr, ")\n");

  // PHASE 3: Enqueue message to render queue
  if (g_render_queue) {
    RenderQueueElement elem = {
        .type = UPDATE_MESSAGE,
        .data.message = {
            .text = strdup(str), // MUST strdup - NetHack reuses buffers
            .category = strdup(category),
            .attr = attr}};
    render_queue_enqueue(g_render_queue, &elem);
  }

  // Add to message history for Swift access WITH attributes (KEEP for backward
  // compatibility)
  extern void nethack_add_message_with_attrs(const char *message,
                                             const char *category, int attr);
  nethack_add_message_with_attrs(str, category, attr);

  // Add to output buffer for Swift (KEEP for backward compatibility)
  safe_append_to_output(str);
  safe_append_to_output("\n");

  // If we're capturing death info, also add to the appropriate buffer
  if (is_capturing_death_info && death_info_stage > 0) {
    switch (death_info_stage) {
    case 1: { // Capturing possessions
      size_t available =
          sizeof(death_info.possessions) - strlen(death_info.possessions) - 1;
      if (available > 1) {
        strncat(death_info.possessions, str, available - 1);
        strncat(death_info.possessions, "\n", available - strlen(str) - 1);
      }
      break;
    }
    case 2: { // Capturing attributes
      size_t available =
          sizeof(death_info.attributes) - strlen(death_info.attributes) - 1;
      if (available > 1) {
        strncat(death_info.attributes, str, available - 1);
        strncat(death_info.attributes, "\n", available - strlen(str) - 1);
      }
      break;
    }
    case 3: { // Capturing conduct
      size_t available =
          sizeof(death_info.conduct) - strlen(death_info.conduct) - 1;
      if (available > 1) {
        strncat(death_info.conduct, str, available - 1);
        strncat(death_info.conduct, "\n", available - strlen(str) - 1);
      }
      break;
    }
    case 4: { // Capturing overview
      size_t available = sizeof(death_info.dungeon_overview) -
                         strlen(death_info.dungeon_overview) - 1;
      if (available > 1) {
        strncat(death_info.dungeon_overview, str, available - 1);
        strncat(death_info.dungeon_overview, "\n", available - strlen(str) - 1);
      }
      break;
    }
    }
  }
}

static void ios_putmixed(winid win, int attr, const char *str) {
  // CRITICAL: putmixed() is called by do_look() with \GXXXXNNNN escape sequences!
  // We MUST decode them before sending to Swift, otherwise UI shows raw escapes.
  // decode_mixed() converts \G1C4C02CE → @ (player glyph), etc.

  // DEBUG: Trace execution for inspect bug
  fprintf(stderr, "[DEBUG ios_putmixed] CALLED! win=%d attr=0x%02X str='%s'\n",
          win, attr, str ? str : "(null)");
  fflush(stderr);

  if (!str) {
    ios_putstr(win, attr, "");
    return;
  }

  // Decode glyph escape sequences using NetHack's decode_mixed()
  char decoded_buf[BUFSZ];
  extern char *decode_mixed(char *, const char *);
  decode_mixed(decoded_buf, str);

  fprintf(stderr, "[DEBUG ios_putmixed] Decoded: '%s'\n", decoded_buf);
  fflush(stderr);

  // Send decoded string to Swift (no escape sequences)
  ios_putstr(win, attr, decoded_buf);

  fprintf(stderr, "[DEBUG ios_putmixed] After ios_putstr, buffer='%s'\n",
          output_buffer);
  fflush(stderr);
}

// Menu state variables now declared at top of file (lines 111-115)

static void ios_display_file(const char *fname, boolean complain) {
  WIN_LOG("display_file");
}

static void ios_start_menu(winid win, unsigned long mbehavior) {
  WIN_LOG("start_menu");
  // Reset menu tracking - clear ALL menu arrays
  menu_item_count = 0;
  memset(menu_selectors, 0, sizeof(menu_selectors));
  memset(menu_texts, 0, sizeof(menu_texts));
  memset(menu_glyphs, 0, sizeof(menu_glyphs));
  memset(menu_attributes, 0, sizeof(menu_attributes));
  memset(menu_itemflags, 0, sizeof(menu_itemflags));
  current_menu_win = win;
  menu_is_active = TRUE;
}

static void ios_add_menu(winid win, const glyph_info *glyph,
                         const ANY_P *identifier, char ch, char gch, int attr,
                         int clr, const char *str, unsigned int itemflags) {
  WIN_LOG("add_menu");

  // Guard clause: NULL identifier - store empty item (header/separator)
  if (!identifier) {
    fprintf(stderr, "[MENU] add_menu with NULL identifier (header/separator): %s\n",
            str ? str : "(null)");
    // Still add text for display but with no selectable identifier
    if (menu_item_count < MAX_MENU_ITEMS) {
      memset(&menu_items[menu_item_count].item, 0, sizeof(ANY_P));
      menu_items[menu_item_count].count = 0;
      menu_items[menu_item_count].itemflags = itemflags;
      menu_selectors[menu_item_count] = 0;  // Not selectable
      if (str) {
        strncpy(menu_texts[menu_item_count], str, MAX_MENU_TEXT - 1);
        menu_texts[menu_item_count][MAX_MENU_TEXT - 1] = '\0';
        safe_append_to_output(str);
        safe_append_to_output("\n");
      } else {
        menu_texts[menu_item_count][0] = '\0';
      }
      menu_glyphs[menu_item_count] = glyph ? glyph->glyph : 0;
      menu_attributes[menu_item_count] = attr;
      menu_itemflags[menu_item_count] = itemflags;
      menu_item_count++;
    }
    return;
  }

  // Guard clause: menu buffer full
  if (menu_item_count >= MAX_MENU_ITEMS) {
    fprintf(stderr, "[MENU] WARNING: Menu buffer full!\n");
    return;
  }

  // Store menu item for later selection
  menu_items[menu_item_count].item = *identifier;
  menu_items[menu_item_count].count = 0; // Not selected yet
  menu_items[menu_item_count].itemflags = itemflags;
  menu_selectors[menu_item_count] = ch;  // Store selector character for matching user input

  // Store additional data for Swift menu UI
  if (str) {
    strncpy(menu_texts[menu_item_count], str, MAX_MENU_TEXT - 1);
    menu_texts[menu_item_count][MAX_MENU_TEXT - 1] = '\0';
  } else {
    menu_texts[menu_item_count][0] = '\0';
  }
  menu_glyphs[menu_item_count] = glyph ? glyph->glyph : 0;
  menu_attributes[menu_item_count] = attr;
  menu_itemflags[menu_item_count] = itemflags;

  if (str) {
    fprintf(stderr, "[MENU] Added item %d: selector='%c' a_int=%d glyph=%d attr=%d - %.40s\n",
            menu_item_count, ch ? ch : ' ', identifier->a_int,
            glyph ? glyph->glyph : 0, attr,
            str ? str : "(null)");
    safe_append_to_output(str);
    safe_append_to_output("\n");
  }
  menu_item_count++;
}

// last_menu_prompt now declared at top of file (line 116)

static void ios_end_menu(winid win, const char *prompt) {
  WIN_LOG("end_menu");
  if (prompt) {
    fprintf(stderr, "[MENU] Prompt: %s\n", prompt);
    strncpy(last_menu_prompt, prompt, sizeof(last_menu_prompt) - 1);
    last_menu_prompt[sizeof(last_menu_prompt) - 1] = '\0';
  } else {
    last_menu_prompt[0] = '\0';
  }
  menu_is_active = FALSE;
}

/*
 * Helper function to allocate and copy selected menu items.
 * NetHack core expects the returned menu_list to survive destroy_nhwindow(),
 * and the caller is responsible for free()ing it.
 * This fixes use-after-free bug where pointers into menu_items[] would
 * point to zeroed memory after ios_destroy_nhwindow() calls memset.
 */
static int alloc_menu_selection(MENU_ITEM_P **menu_list, int index, int count) {
  MENU_ITEM_P *result = (MENU_ITEM_P *)malloc(sizeof(MENU_ITEM_P));
  if (!result) {
    fprintf(stderr, "[MENU] ERROR: malloc failed for menu selection\n");
    return 0;
  }
  result->item = menu_items[index].item;  // Copy the union
  result->count = count;
  *menu_list = result;
  return 1;
}

/*
 * Build IOSMenuContext from current menu state for Swift callback.
 * Returns pointer to static context (valid until next menu operation).
 */
static IOSMenuContext* build_menu_context(int how) {
  static IOSMenuContext ctx;

  ctx.how = how;
  ctx.window_id = current_menu_win;
  ctx.item_count = menu_item_count;

  // Copy prompt
  strncpy(ctx.prompt, last_menu_prompt, IOS_MAX_MENU_TEXT - 1);
  ctx.prompt[IOS_MAX_MENU_TEXT - 1] = '\0';

  // Copy items
  for (int i = 0; i < menu_item_count && i < IOS_MAX_MENU_ITEMS; i++) {
    ctx.items[i].selector = menu_selectors[i];
    ctx.items[i].glyph = menu_glyphs[i];
    strncpy(ctx.items[i].text, menu_texts[i], IOS_MAX_MENU_TEXT - 1);
    ctx.items[i].text[IOS_MAX_MENU_TEXT - 1] = '\0';
    ctx.items[i].attributes = menu_attributes[i];
    ctx.items[i].identifier = menu_items[i].item.a_int;
    ctx.items[i].itemflags = menu_itemflags[i];
  }

  return &ctx;
}

/*
 * Try to handle menu selection via Swift callback.
 * Returns: 1 if handled by Swift (result in menu_list), 0 if should use fallback
 */
static int try_swift_menu_callback(int how, MENU_ITEM_P **menu_list) {
  // Check if callback is registered
  pthread_mutex_lock(&menu_callback_mutex);
  IOSMenuCallback callback = swift_menu_callback;
  pthread_mutex_unlock(&menu_callback_mutex);

  if (!callback) {
    return 0;  // No callback - use fallback
  }

  fprintf(stderr, "[MENU] Using Swift menu callback for %s\n",
          how == PICK_ONE ? "PICK_ONE" : (how == PICK_ANY ? "PICK_ANY" : "PICK_NONE"));

  // CHECK FOR QUEUED INPUT FIRST (before blocking on Swift UI)
  // This allows ios_queue_input to pre-select menu items (e.g., loot mode 'i', 'o', 'b')
  if (how == PICK_ONE) {
    pthread_mutex_lock(&input_mutex);
    if (input_queue_head != input_queue_tail) {
      char queued_ch = input_queue[input_queue_head];
      pthread_mutex_unlock(&input_mutex);

      // Try to find matching menu item
      for (int i = 0; i < menu_item_count; i++) {
        if (menu_selectors[i] == queued_ch) {
          fprintf(stderr, "[MENU] Queued input '%c' matches menu item %d - auto-selecting\n",
                  queued_ch, i);
          // Consume the character from queue
          pthread_mutex_lock(&input_mutex);
          input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
          pthread_mutex_unlock(&input_mutex);

          // Allocate and return the selection
          MENU_ITEM_P *result = (MENU_ITEM_P *)malloc(sizeof(MENU_ITEM_P));
          if (result) {
            result->item = menu_items[i].item;
            result->count = -1;  // All
            result->itemflags = menu_items[i].itemflags;
            *menu_list = result;
            return 1;  // Handled via queued input
          }
          break;
        }
      }
      // Character didn't match - fall through to Swift UI
      fprintf(stderr, "[MENU] Queued input '%c' (0x%02x) did not match any menu selector\n",
              isprint(queued_ch) ? queued_ch : '?', (unsigned char)queued_ch);
    } else {
      pthread_mutex_unlock(&input_mutex);
    }
  }

  // Build context
  IOSMenuContext* ctx = build_menu_context(how);

  fprintf(stderr, "[MENU] ====== CALLING SWIFT CALLBACK ======\n");
  fprintf(stderr, "[MENU] Mode: %s, Items: %d\n",
          how == 0 ? "PICK_NONE" : (how == 1 ? "PICK_ONE" : "PICK_ANY"),
          menu_item_count);

  // Call Swift callback
  IOSMenuSelection selections[MAX_MENU_ITEMS];
  int num_selections = callback(ctx, selections, MAX_MENU_ITEMS);

  fprintf(stderr, "[MENU] Swift callback returned %d selection(s)\n", num_selections);

  // Handle result
  if (num_selections < 0) {
    // Error
    fprintf(stderr, "[MENU] Swift callback error\n");
    return 0;  // Use fallback
  }

  if (num_selections == 0) {
    // Cancelled
    fprintf(stderr, "[MENU] Swift callback cancelled\n");
    *menu_list = NULL;
    return 1;  // Handled, result is cancel
  }

  // Allocate result array
  MENU_ITEM_P *result = (MENU_ITEM_P *)malloc(num_selections * sizeof(MENU_ITEM_P));
  if (!result) {
    fprintf(stderr, "[MENU] ERROR: malloc failed for Swift menu result\n");
    return 0;  // Use fallback
  }

  // Copy selections
  for (int i = 0; i < num_selections; i++) {
    int idx = selections[i].item_index;
    if (idx < 0 || idx >= menu_item_count) {
      fprintf(stderr, "[MENU] ERROR: Invalid selection index %d\n", idx);
      free(result);
      return 0;  // Use fallback
    }
    result[i].item = menu_items[idx].item;
    result[i].count = selections[i].count > 0 ? selections[i].count : -1;  // -1 = all
    result[i].itemflags = menu_items[idx].itemflags;
    fprintf(stderr, "[MENU] Selection %d: index=%d count=%ld a_int=%d\n",
            i, idx, result[i].count, result[i].item.a_int);
  }

  *menu_list = result;
  return 1;  // Handled by Swift
}

static int ios_select_menu(winid win, int how, MENU_ITEM_P **menu_list) {
  WIN_LOG("select_menu how=%d item_count=%d", how, menu_item_count);

  // PICK_NONE: Display-only menus (like Attributes/Enlightenment)
  // Must still show menu to user, just no selection required
  if (how == PICK_NONE) {
    fprintf(stderr, "[MENU] PICK_NONE - display only menu with %d items\n", menu_item_count);

    // Skip during character creation (no UI available yet)
    if (!character_creation_complete) {
      fprintf(stderr, "[MENU] PICK_NONE during char creation - skipping\n");
      return 0;
    }

    // Use Swift callback to display the menu
    int swift_result = try_swift_menu_callback(how, menu_list);
    if (swift_result) {
      fprintf(stderr, "[MENU] PICK_NONE displayed via Swift callback\n");
    } else {
      fprintf(stderr, "[MENU] PICK_NONE - Swift callback not available, skipping display\n");
    }
    return 0;  // PICK_NONE always returns 0 (no selection)
  }

  // During character creation, auto-select first item (bypass Swift UI)
  // NOTE: Only for PICK_ONE/PICK_ANY menus now, since PICK_NONE is handled above
  if (!character_creation_complete) {
    if (menu_item_count > 0) {
      fprintf(stderr, "[MENU] Character creation: selected item a_int=%d\n",
              menu_items[0].item.a_int);
      if (!alloc_menu_selection(menu_list, 0, 1)) return -1;
      return 1;
    }
    return -1;
  }

  // No items in menu
  if (menu_item_count == 0) {
    fprintf(stderr, "[MENU] No items in menu\n");

    // CRITICAL: If we just showed dungeon overview (death_info_stage == 4),
    // this is the LAST menu of death screen - mark player as dead NOW
    if (death_info_stage == 4) {
      fprintf(stderr,
              "[MENU] Death screen complete - marking player_has_died = 1\n");
      player_has_died = 1;
      is_capturing_death_info = 0;
      death_info_stage = 0;
    }

    return -1;
  }

  // Check for tutorial auto-skip BEFORE trying Swift callback
  if (how == PICK_ONE && last_menu_prompt[0] != '\0' && strstr(last_menu_prompt, "tutorial")) {
    fprintf(stderr, "[MENU] Tutorial menu detected - auto-selecting 'n' (No)\n");
    for (int i = 0; i < menu_item_count; i++) {
      if (menu_selectors[i] == 'n') {
        fprintf(stderr, "[MENU] Auto-selected 'n' to skip tutorial\n");
        if (!alloc_menu_selection(menu_list, i, 1)) return -1;
        return 1;
      }
    }
  }

  // Try Swift callback first for PICK_ONE and PICK_ANY
  if (how == PICK_ONE || how == PICK_ANY) {
    int swift_result = try_swift_menu_callback(how, menu_list);
    if (swift_result) {
      // Swift handled it
      return (*menu_list) ? (how == PICK_ONE ? 1 : menu_response_count) : -1;
    }
    // Fall through to keyboard input fallback
    fprintf(stderr, "[MENU] Swift callback not available, using keyboard fallback\n");
  }

  // FALLBACK: Keyboard input path (original implementation)

  // PICK_ONE: Wait for user input and select matching item
  if (how == PICK_ONE) {
    // Log available selectors for debugging
    fprintf(stderr, "[MENU] PICK_ONE - waiting for user input. Available selectors: ");
    for (int i = 0; i < menu_item_count; i++) {
      if (menu_selectors[i]) {
        fprintf(stderr, "'%c' ", menu_selectors[i]);
      }
    }
    fprintf(stderr, "\n");

    // Block and wait for user input (same pattern as ios_yn_function)
    pthread_mutex_lock(&input_mutex);

    // Check if input is already queued
    if (input_queue_head != input_queue_tail) {
      char ch = input_queue[input_queue_head];
      input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
      pthread_mutex_unlock(&input_mutex);

      fprintf(stderr, "[MENU] Got queued input: '%c' (0x%02x)\n",
              isprint(ch) ? ch : '?', (unsigned char)ch);

      // Handle ESC/Space to cancel
      if (ch == '\033' || ch == ' ') {
        fprintf(stderr, "[MENU] Cancel requested\n");
        return -1;
      }

      // Find matching selector
      for (int i = 0; i < menu_item_count; i++) {
        if (menu_selectors[i] == ch) {
          fprintf(stderr, "[MENU] Selected item %d with selector '%c', a_int=%d\n",
                  i, ch, menu_items[i].item.a_int);
          if (!alloc_menu_selection(menu_list, i, 1)) return -1;
          return 1;
        }
      }

      // No match found - cancel
      fprintf(stderr, "[MENU] No item matches selector '%c', canceling\n", ch);
      return -1;
    }

    // Wait for input
    fprintf(stderr, "[MENU] Blocking for user input...\n");
    while (input_queue_head == input_queue_tail && game_thread_running) {
      pthread_cond_wait(&input_cond, &input_mutex);
    }

    // Check if we got input
    if (input_queue_head != input_queue_tail) {
      char ch = input_queue[input_queue_head];
      input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
      pthread_mutex_unlock(&input_mutex);

      fprintf(stderr, "[MENU] Got input after wait: '%c' (0x%02x)\n",
              isprint(ch) ? ch : '?', (unsigned char)ch);

      // Handle ESC/Space to cancel
      if (ch == '\033' || ch == ' ') {
        fprintf(stderr, "[MENU] Cancel requested\n");
        return -1;
      }

      // Find matching selector
      for (int i = 0; i < menu_item_count; i++) {
        if (menu_selectors[i] == ch) {
          fprintf(stderr, "[MENU] Selected item %d with selector '%c', a_int=%d\n",
                  i, ch, menu_items[i].item.a_int);
          if (!alloc_menu_selection(menu_list, i, 1)) return -1;
          return 1;
        }
      }

      // No match found - cancel
      fprintf(stderr, "[MENU] No item matches selector '%c', canceling\n", ch);
      return -1;
    }

    pthread_mutex_unlock(&input_mutex);
    fprintf(stderr, "[MENU] Game thread stopped, canceling\n");
    return -1;
  }

  // PICK_ANY: Fallback - auto-select first few SELECTABLE items (not headers)
  if (how == PICK_ANY) {
    fprintf(stderr, "[MENU] PICK_ANY fallback - looking for selectable items\n");

    // Count selectable items (those with valid identifiers)
    int selectable_indices[5];
    int selectable_count = 0;
    for (int i = 0; i < menu_item_count && selectable_count < 5; i++) {
      // Skip items with no identifier (headers/info text)
      // Note: selector 0 means not selectable (header/separator)
      if (menu_items[i].item.a_int == 0 && (menu_selectors[i] == 0 || menu_selectors[i] == ' ')) {
        fprintf(stderr, "[MENU]   Skipping header item %d (selector=%d): %s\n",
                i, (int)menu_selectors[i], menu_texts[i]);
        continue;
      }
      selectable_indices[selectable_count++] = i;
    }

    // If no selectable items, just return -1 (canceled/empty)
    if (selectable_count == 0) {
      fprintf(stderr, "[MENU] PICK_ANY - no selectable items found, returning -1\n");
      return -1;
    }

    MENU_ITEM_P *result = (MENU_ITEM_P *)malloc(selectable_count * sizeof(MENU_ITEM_P));
    if (!result) {
      fprintf(stderr, "[MENU] ERROR: malloc failed for PICK_ANY\n");
      return -1;
    }
    for (int i = 0; i < selectable_count; i++) {
      int idx = selectable_indices[i];
      result[i].item = menu_items[idx].item;
      result[i].count = 1;
    }
    *menu_list = result;
    fprintf(stderr, "[MENU] PICK_ANY - auto-selected %d items\n", selectable_count);
    return selectable_count;
  }

  return -1;
}

static void ios_update_inventory(int arg) { WIN_LOG("update_inventory"); }

static void ios_mark_synch(void) { /* WIN_LOG("mark_synch"); - too verbose */ }

// Made non-static so RealNetHackBridge.c can call it for travel animation
void ios_wait_synch(void) {
  /* This is called after NetHack processes a command and wants to sync display
   */

  extern struct instance_globals_saved_m svm;

  // PHASE 1: Enqueue turn complete marker
  if (g_render_queue) {
    RenderQueueElement elem = {
        .type = CMD_TURN_COMPLETE,
        .data.command = {.blocking = 0, .turn_number = svm.moves}};
    render_queue_enqueue(g_render_queue, &elem);
  }

  // PUSH MODEL: Update game state snapshot for lock-free Swift reads
  extern void update_game_state_snapshot(void);
  update_game_state_snapshot();

  // Always capture the current state and notify Swift
  ios_capture_map();

  // Notify Swift on main thread (queue flush happens in Swift)
  dispatch_async(dispatch_get_main_queue(), ^{
    ios_notify_map_changed();
  });
}

static void ios_cliparound(int x, int y) {
  /* WIN_LOG("cliparound"); - too verbose */
}

// (Map buffer already defined above - removed duplicate)

// Track old player position to clear ghost
static int old_player_x = -1;
static int old_player_y = -1;

static void ios_print_glyph(winid win, coordxy x, coordxy y,
                            const glyph_info *glyph,
                            const glyph_info *bkglyph) {
  // DEBUG: Count print_glyph calls to verify docrt() is drawing map
  static int glyph_call_count = 0;
  glyph_call_count++;
  if (glyph_call_count % 100 == 1 || glyph_call_count <= 5) {
    fprintf(stderr, "[PRINT_GLYPH] Call #%d: win=%d (expect %d) x=%d y=%d\n",
            glyph_call_count, win, map_win, x, y);
  }

  // CRITICAL FIX: During restore, docrt() may pass win=-1
  // Accept either the correct map_win OR win=-1 (which means "map" during
  // restore)
  if (win != map_win && win != -1) {
    if (glyph_call_count <= 5) {
      fprintf(stderr, "[PRINT_GLYPH] REJECT: win=%d != map_win=%d and != -1\n",
              win, map_win);
    }
    return;
  }

  // IMPORTANT: x, y are NetHack coordinates (x: 1-79, y: 0-20)
  // We will convert to buffer coordinates for internal storage
  // Swift will later convert to Swift coordinates (0-based) for display

  // Bounds check on NetHack coordinates
  if (x < 0 || x >= MAX_MAP_WIDTH || y < 0 || y >= MAX_MAP_HEIGHT)
    return;

  // Get the ASCII character for this glyph
  char ch = ' ';
  int glyphnum = 0;
  unsigned char color = 0;
  unsigned int glyphflags = 0;

  if (glyph) {
    glyphnum = glyph->glyph;

    // If ttychar is not set, we need to get the proper mapping
    if (glyph->ttychar == 0 && glyphnum != NO_GLYPH) {
      // Try map_glyphinfo first
      glyph_info gi;
      extern void map_glyphinfo(coordxy x, coordxy y, int glyph,
                                unsigned mgflags, glyph_info *glyphinfo);
      map_glyphinfo(x, y, glyphnum, 0, &gi);
      ch = gi.ttychar;
      color = gi.gm.sym.color;
      glyphflags = gi.gm.glyphflags;

      // If still no char, use hardcoded mappings for common glyphs
      if (ch == 0) {
        // Check for specific known glyphs
        if (glyphnum == GLYPH_UNEXPLORED || glyphnum == 9616) {
          ch = ' '; // Unexplored area
        } else if (glyphnum >= 2359 && glyphnum < 2400) {
          ch = '.'; // Room/floor
        } else if (glyphnum >= 2400 && glyphnum < 2450) {
          ch = '#'; // Corridor
        } else if (glyphnum >= 2450 && glyphnum < 2500) {
          ch = '-'; // Horizontal wall
        } else if (glyphnum >= 2500 && glyphnum < 2550) {
          ch = '|'; // Vertical wall
        } else if (glyphnum >= 2550 && glyphnum < 2600) {
          ch = '+'; // Door
        } else if (glyphnum >= 2600 && glyphnum < 2650) {
          ch = '#'; // Tree/wall
        } else if (glyphnum < 400) {
          // Monster range - use letters
          ch = 'M';
        } else if (glyphnum < 800) {
          // Object range
          ch = '*';
        } else {
          ch = '?'; // Unknown
        }
      }
    } else {
      ch = glyph->ttychar;
      color = glyph->gm.sym.color;
      glyphflags = glyph->gm.glyphflags;
    }

    // Final fallback
    if (ch == 0) {
      ch = '?';
    }

  } else {
    // No glyph provided - use space
    ch = ' ';
  }

  // Convert NetHack map coordinates to buffer coordinates using defensive API
  // NetHack (x:1-79, y:0-20) → Buffer (x:1-79, y:2-22)
  int buffer_x = map_x_to_buffer_x(x);
  int buffer_y = map_y_to_buffer_y(y);

  // Guard: Invalid coordinates
  if (buffer_x < 0 || buffer_y < 0) {
    fprintf(stderr, "[MAP] Invalid coordinates: [NH:%d,%d] -> [BUF:%d,%d]\n", x,
            y, buffer_x, buffer_y);
    return;
  }

  // Guard: Out of buffer bounds
  if (buffer_x >= MAX_MAP_WIDTH || buffer_y >= MAX_MAP_HEIGHT) {
    fprintf(stderr, "[MAP] Out of bounds: [BUF:%d,%d] >= max(%d,%d)\n",
            buffer_x, buffer_y, MAX_MAP_WIDTH, MAX_MAP_HEIGHT);
    return;
  }

  // Debug: Log what we're drawing at key positions
  extern struct you u; // Get player position

  // ALWAYS log player position draws with coordinate space labels
  if (x == u.ux && y == u.uy) {
    fprintf(
        stderr,
        "[MAP] PLAYER GLYPH at [NH:%d,%d] -> [BUF:%d,%d]: glyph=%d -> '%c'\n",
        x, y, buffer_x, buffer_y, glyphnum, ch);
    fflush(stderr);
  }

  // Log interesting glyphs with coordinate space labels
  if (glyphnum != NO_GLYPH && glyphnum != 9616) { // Not empty space
    if (ch == '@' || ch == 'd' || ch == 'f' || ch == '|' ||
        ch == '-') { // Player, pets, walls
      fprintf(stderr,
              "[MAP] Drawing '%c' at [NH:%d,%d] -> [BUF:%d,%d], glyph=%d, flags=0x%x%s\n", ch,
              x, y, buffer_x, buffer_y, glyphnum, glyphflags,
              (glyphflags & 0x00010) ? " [PET]" : "");
    }
  }

  // Store in map buffer with coordinate mapping (KEEP for backward
  // compatibility during transition)
  map_buffer[buffer_y][buffer_x] = ch;

  // Store enhanced data
  map_cells[buffer_y][buffer_x].glyph = glyphnum;
  map_cells[buffer_y][buffer_x].ch = ch;
  map_cells[buffer_y][buffer_x].color = color;
  map_cells[buffer_y][buffer_x].bg = 0; // Black background for now

  // Track actual map size (in buffer coordinates)
  if (buffer_x >= actual_map_width)
    actual_map_width = buffer_x + 1;
  if (buffer_y >= actual_map_height)
    actual_map_height = buffer_y + 1;

  // PHASE 1: Enqueue glyph update to render queue
  if (g_render_queue) {
    RenderQueueElement elem = {.type = UPDATE_GLYPH,
                               .data.map = {.x = x, // NetHack coordinates
                                            .y = y,
                                            .glyph = glyphnum,
                                            .ch = ch,
                                            .color = color,
                                            .glyphflags = glyphflags}};
    render_queue_enqueue(g_render_queue, &elem);
  }

  map_dirty = TRUE;

  // REMOVED: Don't flush during docrt() - causes partial map capture!
  // wait_synch() will flush AFTER all tiles are drawn.

  // Track player position for debugging
  if (x == u.ux && y == u.uy) {
    static int last_player_x = -1;
    static int last_player_y = -1;

    if (last_player_x != x || last_player_y != y) {
      WIN_LOG("Player moved to (%d,%d)", x, y);
      last_player_x = x;
      last_player_y = y;
      // No flush here - let wait_synch() handle it after docrt() completes
    }
  }
}

static void ios_raw_print(const char *str) {
  if (str) {
    safe_append_to_output(str);
    safe_append_to_output("\n");
  }
}

static void ios_raw_print_bold(const char *str) { ios_raw_print(str); }

static int ios_nhgetch(void) {
  WIN_LOG("nhgetch - waiting for input");

  pthread_mutex_lock(&input_mutex);

  // Check if input already queued
  if (input_queue_head != input_queue_tail) {
    char ch = input_queue[input_queue_head];
    input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
    pthread_mutex_unlock(&input_mutex);
    fprintf(stderr, "[NHGETCH] Got queued input: '%c' (0x%02x)\n",
            isprint(ch) ? ch : '?', (unsigned char)ch);
    return ch;
  }

  // Wait for input
  fprintf(stderr, "[NHGETCH] Blocking for user input...\n");
  while (input_queue_head == input_queue_tail && game_thread_running) {
    pthread_cond_wait(&input_cond, &input_mutex);
  }

  // Check exit
  if (!game_thread_running || input_queue_head == input_queue_tail) {
    pthread_mutex_unlock(&input_mutex);
    fprintf(stderr, "[NHGETCH] Interrupted or no input\n");
    return '\033'; // ESC to cancel
  }

  char ch = input_queue[input_queue_head];
  input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
  pthread_mutex_unlock(&input_mutex);

  fprintf(stderr, "[NHGETCH] Got input after wait: '%c' (0x%02x)\n",
          isprint(ch) ? ch : '?', (unsigned char)ch);
  return ch;
}

// Single-threaded input queue
// Thread-safe input queue with signaling (RESTORED FROM MAIN)
void ios_queue_input(char ch) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  double timestamp = ts.tv_sec + ts.tv_nsec / 1e9;

  fprintf(stderr, "[%.3f] [INPUT] ios_queue_input START char=0x%02x\n", timestamp, (unsigned char)ch);

  pthread_mutex_lock(&input_mutex);

  int next_tail = (input_queue_tail + 1) % INPUT_QUEUE_SIZE;
  if (next_tail != input_queue_head) {
    int old_tail = input_queue_tail;
    input_queue[input_queue_tail] = ch;
    input_queue_tail = next_tail;
    // Enhanced logging to show ALL characters including control codes
    fprintf(stderr, "[%.3f] [INPUT] Queued char=0x%02x at tail=%d, new tail=%d, head=%d\n",
            timestamp, (unsigned char)ch, old_tail, input_queue_tail, input_queue_head);

    // Wake up game thread if it's waiting
    // CRITICAL FIX: Use broadcast instead of signal to ensure wake-up
    // Signal can be lost if thread is between queue check and timedwait
    pthread_cond_broadcast(&input_cond);
    fprintf(stderr, "[%.3f] [INPUT] pthread_cond_broadcast sent\n", timestamp);
  } else {
    fprintf(stderr, "[%.3f] [INPUT] QUEUE FULL - dropping char 0x%02x!\n", timestamp, (unsigned char)ch);
  }

  pthread_mutex_unlock(&input_mutex);

  clock_gettime(CLOCK_MONOTONIC, &ts);
  double end_time = ts.tv_sec + ts.tv_nsec / 1e9;
  fprintf(stderr, "[%.3f] [INPUT] ios_queue_input END (took %.3fms)\n", end_time, (end_time - timestamp) * 1000);
}

// Request game thread to exit cleanly
void ios_request_game_exit(void) {
  fprintf(
      stderr,
      "[EXIT] Setting exit flag - game will terminate after current turn\n");
  atomic_store(&game_should_exit, 1); // Thread-safe atomic write

  // Set gameover flag to ensure proper cleanup
  extern struct sinfo program_state;
  program_state.gameover = 1;

  // CRITICAL FIX: Wake up thread if blocked in pthread_cond_wait()
  // The game thread may be waiting for input in ios_poskey() - signal it to
  // check exit flag
  pthread_mutex_lock(&input_mutex);
  game_thread_running = 0;          // CRITICAL: Reset thread running flag
  pthread_cond_signal(&input_cond); // Wake up blocked thread!
  pthread_mutex_unlock(&input_mutex);

  fprintf(stderr, "[EXIT] ✓ Exit signaled and thread notified\n");
}

// Reset exit flag for new game
void ios_reset_game_exit(void) {
  atomic_store(&game_should_exit, 0); // Thread-safe atomic write
  fprintf(stderr, "[EXIT] Exit flag reset for new game\n");
}

// Check if exit was requested
int ios_was_exit_requested(void) {
  return atomic_load(&game_should_exit); // Thread-safe atomic read
}

// Flag to track if we've sent game ready signal for new games
// Reset in ios_reset_all_static_state() for new game
static int game_ready_signaled = 0;

// Blocking version of nh_poskey for game thread (RESTORED FROM MAIN)
static int ios_nh_poskey_blocking(coordxy *x, coordxy *y, int *mod) {
  struct timespec ts_perf;
  clock_gettime(CLOCK_MONOTONIC, &ts_perf);
  double timestamp = ts_perf.tv_sec + ts_perf.tv_nsec / 1e9;

  fprintf(stderr, "[%.3f] [POSKEY] ios_nh_poskey_blocking START\n", timestamp);

  // CRITICAL: First input wait for new games means game is initialized!
  // For restored games, ios_restore_complete() already sent the signal.
  // For new games, signal NOW before waiting for first input.
  if (!game_ready_signaled) {
    game_ready_signaled = 1; // Signal only once

    // Check if this is a new game (NOT a restored game)
    // Restored games already have character_creation_complete=1 from restore
    if (!character_creation_complete) {
      // NEW GAME: moveloop_preamble() has completed, all globals initialized
      fprintf(stderr, "[%.3f] [POSKEY] 🎯 First input wait for NEW game - notifying Swift\n", timestamp);
      extern void ios_notify_game_ready(void);
      ios_notify_game_ready();
    } else {
      // RESTORED GAME: Signal already sent from ios_restore_complete(), don't duplicate
      fprintf(stderr, "[%.3f] [POSKEY] Restored game - already signaled\n", timestamp);
    }
  }

  pthread_mutex_lock(&input_mutex);

  // Wait for input (blocks game thread)
  // Use timedwait instead of wait to allow periodic exit flag checking
  while (input_queue_head == input_queue_tail && game_thread_running) {
    // 10ms timeout for responsive input while allowing exit flag checking
    struct timespec ts = {0, 10000000};
    pthread_cond_timedwait_relative_np(&input_cond, &input_mutex, &ts);

    // Check exit flags after wake
    extern struct sinfo program_state;
    if (atomic_load(&game_should_exit) || program_state.gameover) {
      pthread_mutex_unlock(&input_mutex);
      return '\033';
    }
  }

  // Check if we should exit
  if (!game_thread_running) {
    pthread_mutex_unlock(&input_mutex);
    return '\033'; // ESC to quit
  }

  // Get the input
  char ch = input_queue[input_queue_head];
  input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
  pthread_mutex_unlock(&input_mutex);

  if (x)
    *x = 0;
  if (y)
    *y = 0;
  if (mod)
    *mod = 0;

  // Get current turn count for debugging
  extern struct instance_globals_saved_m svm;
  extern struct instance_flags iflags;
  long current_turn = svm.moves;

  clock_gettime(CLOCK_MONOTONIC, &ts_perf);
  double end_time = ts_perf.tv_sec + ts_perf.tv_nsec / 1e9;
  fprintf(stderr,
          "[%.3f] [POSKEY] Returning '%c' (0x%02X) Turn=%ld (took %.3fms)\n",
          end_time, isprint(ch) ? ch : '?', (unsigned char)ch, current_turn, (end_time - timestamp) * 1000);

  // Note: We don't need to mark map dirty here because wait_synch
  // will handle the update notification after NetHack processes the command

  return ch;
}

static int ios_nh_poskey(coordxy *x, coordxy *y, int *mod) {
  if (use_threaded_mode) {
    // Use blocking version for game thread
    return ios_nh_poskey_blocking(x, y, mod);
  } else {
    // Use existing non-blocking version
    if (input_queue_head == input_queue_tail) {
      return 0; // No input
    }
    char ch = input_queue[input_queue_head];
    input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
    if (x)
      *x = 0;
    if (y)
      *y = 0;
    if (mod)
      *mod = 0;
    return ch;
  }
}

static void ios_nhbell(void) {
  /* WIN_LOG("nhbell"); - DISABLED to reduce spam */
}

static int ios_doprev_message(void) {
  WIN_LOG("doprev_message");
  return 0;
}

/* YN Callback System Implementation */
static yn_response_mode_t current_yn_mode = YN_MODE_DEFAULT;
static char next_yn_response = 0; // Specific response override
static yn_callback_func custom_yn_callback = NULL;
static pthread_mutex_t yn_callback_mutex =
    PTHREAD_MUTEX_INITIALIZER; // Thread safety for yn_callback

// Weak-linked Swift callback that can be overridden
__attribute__((weak)) char ios_swift_yn_callback(const char *query,
                                                 const char *resp, char def) {
  // Default implementation if Swift doesn't override
  return 0; // 0 means "not handled by Swift"
}

// NOTE: Death animation callback is now registered via ios_set_death_animation_callback()
// See trigger_death_animation() near top of file

void ios_set_yn_mode(yn_response_mode_t mode) {
  current_yn_mode = mode;
  fprintf(stderr, "[YN] Mode set to: %d\n", mode);
}

yn_response_mode_t ios_get_yn_mode(void) { return current_yn_mode; }

void ios_set_next_yn_response(char response) {
  next_yn_response = response;
  fprintf(stderr, "[YN] Next response set to: '%c'\n", response);
}

void ios_enable_yn_auto_yes(void) { ios_set_yn_mode(YN_MODE_AUTO_YES); }

void ios_enable_yn_auto_no(void) { ios_set_yn_mode(YN_MODE_AUTO_NO); }

void ios_enable_yn_ask_user(void) { ios_set_yn_mode(YN_MODE_ASK_USER); }

void ios_set_yn_callback(yn_callback_func callback) {
  custom_yn_callback = callback;
}

static char ios_yn_function(const char *query, const char *resp, char def) {
  WIN_LOG("yn_function");
  fprintf(stderr, "[IOS_YN] Query: %s | resp: %s | def: %c\n",
          query ? query : "(null)", resp ? resp : "(null)", def);

  // Update current YN context
  current_yn_context.query = query;
  current_yn_context.responses = resp;
  current_yn_context.default_response = def;
  memset(current_yn_context.captured_output, 0,
         sizeof(current_yn_context.captured_output));

  // CRITICAL FIX: Clear output_buffer before yn_function to prevent
  // accumulation Root Cause: Buffer was never cleared during normal gameplay,
  // causing overflow after enough game output accumulated (RCA:
  // nethack-rca-enforcer)
  memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);

  /* Log if this is a save-related prompt */
  if (query && (strstr(query, "save") || strstr(query, "Save") ||
                strstr(query, "SAVE"))) {
    fprintf(stderr, "[IOS_YN] ⚠️  SAVE-RELATED PROMPT DETECTED!\n");
  }

  if (query) {
    fprintf(stderr, "[YN_FUNCTION] Query: '%s', resp: '%s', def: '%c'\n", query,
            resp ? resp : "(null)", def ? def : '?');
    safe_append_to_output(query);
    safe_append_to_output("\n");
  }

  // ========================================
  // CRITICAL FIX: Check input queue FIRST!
  // This enables atomic commands like "da" (drop item 'a')
  // ========================================
  pthread_mutex_lock(&input_mutex);
  if (input_queue_head != input_queue_tail) {
    // PEEK without consuming - validate BEFORE removing from queue
    char ch = input_queue[input_queue_head];

    fprintf(stderr, "[IOS_YN] Peeked queued input: '%c' (0x%02x)\n",
            isprint(ch) ? ch : '?', (unsigned char)ch);

    // Validate against allowed responses (if resp is provided)
    if (!resp || strchr(resp, ch)) {
      // VALID - now consume from queue
      input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
      pthread_mutex_unlock(&input_mutex);
      fprintf(stderr, "[IOS_YN] Valid response, consumed and returning: '%c'\n", ch);
      return ch;
    }

    // INVALID - consume the bad input and return ESC to cancel
    // This prevents the infinite loop where invalid input was lost
    input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
    pthread_mutex_unlock(&input_mutex);
    fprintf(stderr,
            "[IOS_YN] Invalid response '%c' for allowed set '%s', returning ESC to cancel\n",
            ch, resp ? resp : "(any)");
    return '\033';  // ESC cancels selection dialogs like spell casting
  } else {
    // FIX: Detect selection-style queries and block for input
    // Selection types:
    // 1. Item selection: resp has many inventory letters (e.g., "abcdefghij...")
    // 2. Spell selection: resp is NULL but query has "[a-b *?]" pattern
    int needs_blocking_input = 0;

    if (resp) {
      // Type 1: Check resp for inventory letters
      int lowercase_count = 0;
      for (const char *p = resp; *p; p++) {
        if (*p >= 'a' && *p <= 'z') {
          lowercase_count++;
        }
      }
      // Block for input if resp is provided and non-trivial
      // This includes item selection (many letters) AND short prompts like "lr" for hand
      // Only skip blocking for EXACT "yn" (simple yes/no) or single-char responses
      // FIX: Use strcmp instead of strstr - "ynaq" contains "yn" but needs blocking!
      needs_blocking_input = (strlen(resp) > 1 && strcmp(resp, "yn") != 0);
      fprintf(stderr, "[IOS_YN] Detected resp '%s' (len=%zu), needs_blocking=%d\n",
              resp, strlen(resp), needs_blocking_input);

      // FIX: Hand selection detection MUST be inside if(resp) block!
      // When putting on a ring, resp="lr" is provided, so the else-if chain below is never reached.
      // Check for hand/finger query here and trigger UI notification.
      if (needs_blocking_input && query && (strstr(query, "hand") || strstr(query, "finger"))) {
        extern void ios_request_hand_selection(void);
        ios_request_hand_selection();
        fprintf(stderr, "[IOS_YN] Hand selection detected (inside resp block), triggering UI...\n");
      }

      // NOTE: Loot options are now handled via NATIVE INTERCEPTION in Swift
      // CommandHandler intercepts M-l BEFORE sending to C, shows picker, then sends full sequence
      // No notification needed - the loot mode character is already queued when yn_function is called
    } else if (query && strstr(query, "[") && strstr(query, "*?]")) {
      // Type 2: NULL resp but selection-style query (spell casting, etc.)
      // Pattern: "Cast which spell? [a-b *?]"
      needs_blocking_input = 1;
      fprintf(stderr, "[IOS_YN] Detected selection prompt with NULL resp: '%s'\n", query);
    } else if (query && (strstr(query, "direction") || strstr(query, "Direction"))) {
      // Type 3: Direction queries (spell targeting, looking, etc.)
      // Pattern: "In what direction?" or similar
      needs_blocking_input = 1;
      fprintf(stderr, "[IOS_YN] Detected direction prompt: '%s'\n", query);
    } else if (query && (strstr(query, "hand") || strstr(query, "finger"))) {
      // Type 4: Hand/finger selection for rings
      // Signal Swift to show hand selection UI
      extern void ios_request_hand_selection(void);
      ios_request_hand_selection();
      fprintf(stderr, "[IOS_YN] Hand selection detected, blocking for input...\n");
      needs_blocking_input = 1;
    } else if (resp && strchr(resp, ':') && (strchr(resp, 'i') || strchr(resp, 'o'))) {
      // Type 5: Loot/container options prompt
      // Pattern: resp contains ':' (look) and 'i' (put in) or 'o' (take out)
      // Full set: ":oibrs" or empty container: ":irs" (no 'o' or 'b')
      // Signal Swift to show loot options picker
      extern void ios_request_loot_options(const char *available_options);
      ios_request_loot_options(resp);
      fprintf(stderr, "[IOS_YN] Loot options detected (resp: %s), blocking for input...\n", resp);
      needs_blocking_input = 1;
    }

    if (needs_blocking_input) {
      fprintf(stderr, "[IOS_YN] Selection detected, blocking for input...\n");

      // Block and wait for input instead of falling back to mode
      while (input_queue_head == input_queue_tail && game_thread_running) {
        pthread_cond_wait(&input_cond, &input_mutex);
      }

      // Check if we got input
      if (input_queue_head != input_queue_tail) {
        char ch = input_queue[input_queue_head];
        input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;
        pthread_mutex_unlock(&input_mutex);

        fprintf(stderr, "[IOS_YN] Got selection input: '%c' (0x%02x)\n",
                isprint(ch) ? ch : '?', (unsigned char)ch);
        return ch;
      }

      // If we broke out of loop due to game_thread_running = 0, fall through
      fprintf(stderr, "[IOS_YN] Game thread stopped, using fallback\n");
    }

    pthread_mutex_unlock(&input_mutex);
    fprintf(stderr, "[IOS_YN] Queue empty, using mode-based response\n");
  }
  // ========================================
  // END QUEUE CHECK
  // ========================================

  char result = 0;

  // First check if we have a specific next response set
  if (next_yn_response != 0) {
    result = next_yn_response;
    next_yn_response = 0; // Clear it after use
    fprintf(stderr, "[YN_FUNCTION] Using specific response: '%c'\n", result);
    return result;
  }

  // Check current mode
  switch (current_yn_mode) {
  case YN_MODE_AUTO_YES:
    result = 'y';
    fprintf(stderr, "[YN_FUNCTION] AUTO_YES mode - returning 'y'\n");
    break;

  case YN_MODE_AUTO_NO:
    result = '\033'; // ESC (proper cancel for getobj)
    fprintf(stderr, "[YN_FUNCTION] AUTO_NO mode - returning ESC (cancel)\n");
    break;

  case YN_MODE_ASK_USER:
    // Try Swift callback first
    result = ios_swift_yn_callback(query, resp, def);
    if (result != 0) {
      fprintf(stderr, "[YN_FUNCTION] Swift callback returned: '%c'\n", result);
      break;
    }
    // If Swift doesn't handle it, fall through to default
    // In a real implementation, we'd block here waiting for UI response
    fprintf(
        stderr,
        "[YN_FUNCTION] ASK_USER mode but no Swift response, using default\n");
    /* FALLTHROUGH */

  case YN_MODE_DEFAULT:
  default:
    // Handle special cases
    if (query) {
      // Check for save confirmation
      if (strstr(query, "Really save")) {
        // For save, we should check if we're in a save operation
        result = 'y'; // Default to yes for saves
        fprintf(stderr, "[YN_FUNCTION] Save confirmation - returning 'y'\n");
        break;
      }

      // Check for death screen questions and capture info
      if (strstr(query, "possessions identified")) {
        fprintf(stderr, "[YN_FUNCTION] Death screen - capturing possessions\n");
        player_has_died = 1; // Set flag at death start!
        is_capturing_death_info = 1;
        death_info_stage = 1;
        // CRITICAL: Clear ALL death_info buffers at start to prevent stale data
        // from previous deaths corrupting this death's info
        memset(death_info.possessions, 0, sizeof(death_info.possessions));
        memset(death_info.attributes, 0, sizeof(death_info.attributes));
        memset(death_info.conduct, 0, sizeof(death_info.conduct));
        memset(death_info.dungeon_overview, 0, sizeof(death_info.dungeon_overview));
        memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);

        // CRITICAL: Capture final stats from NetHack globals directly
        // Using u.* globals is more reliable than current_stats which may not be updated
        death_info.final_level = u.ulevel;           // Player's experience level
        death_info.final_hp = u.uhp;                 // HP at death (0 or negative)
        death_info.final_maxhp = u.uhpmax;           // Maximum HP
        death_info.final_gold = money_cnt(gi.invent); // Total gold in inventory
        death_info.final_turns = svm.moves;          // Total game turns
        death_info.dungeon_level = depth(&u.uz);     // Current dungeon depth

        // Capture role name (e.g., "Zoru the Barbarian")
        char role_buf[64];
        snprintf(role_buf, sizeof(role_buf), "%s the %s",
                 svp.plname,
                 (flags.female && gu.urole.name.f) ? gu.urole.name.f : gu.urole.name.m);
        strncpy(death_info.role_name, role_buf, sizeof(death_info.role_name) - 1);

        // Score is u.urexp - the experience/score accumulator
        death_info.final_score = u.urexp;

        fprintf(stderr, "[YN_FUNCTION] ☠️ Captured death stats: Lv%d HP%d/%d Gold%ld Turns%ld Dlvl%d Score%ld Role='%s'\n",
                death_info.final_level, death_info.final_hp, death_info.final_maxhp,
                death_info.final_gold, death_info.final_turns, death_info.dungeon_level,
                death_info.final_score, death_info.role_name);

        // CRITICAL FIX: Trigger death animation IMMEDIATELY, BEFORE data collection
        // This allows the 2s animation to run IN PARALLEL with the ~10s data collection
        // (instead of sequentially, which would add 2s delay on top of 10s)
        fprintf(stderr, "[YN_FUNCTION] ☠️ TRIGGERING EARLY DEATH ANIMATION CALLBACK\n");
        trigger_death_animation();

        result = 'y'; // Say yes to see possessions
        break;
      }
      if (strstr(query, "see your attributes")) {
        // NOTE: Possessions already captured directly in ios_putstr() via strncat
        // The buffer-based copy was REMOVED because it OVERWROTE correct data
        // See: RCA by nethack-guardian - dual capture mechanism conflict
        fprintf(stderr, "[YN_FUNCTION] Death screen - capturing attributes\n");
        death_info_stage = 2;
        result = 'y'; // Say yes to see attributes
        break;
      }
      if (strstr(query, "see your conduct")) {
        // NOTE: Attributes already captured directly in ios_putstr() via strncat
        // The buffer-based copy was REMOVED because it OVERWROTE correct data
        fprintf(stderr, "[YN_FUNCTION] Death screen - capturing conduct\n");
        death_info_stage = 3;
        result = 'y'; // Say yes to see conduct
        break;
      }
      if (strstr(query, "creatures vanquished")) {
        // NOTE: Attributes already captured directly in ios_putstr() via strncat
        fprintf(stderr,
                "[YN_FUNCTION] Death screen - skipping vanquished for now\n");
        death_info_stage = 3; // Skip to conduct
        result = 'n';         // Skip vanquished list for now
        break;
      }
      // NOTE: Duplicate "see your conduct" case removed - already handled above
      if (strstr(query, "see the dungeon overview")) {
        // NOTE: Conduct already captured directly in ios_putstr() via strncat
        fprintf(stderr,
                "[YN_FUNCTION] Death screen - capturing dungeon overview\n");
        death_info_stage = 4;
        result = 'y'; // Say yes to see overview
        break;
      }
      if (strstr(query, "Dump core")) {
        // NOTE: Dungeon overview already captured directly in ios_putstr() via strncat
        fprintf(stderr,
                "[YN_FUNCTION] Death screen complete - all info captured\n");
        is_capturing_death_info = 0;
        death_info_stage = 0;
        player_has_died = 1; // Mark that player has died
        result = 'n';        // Don't dump core
        break;
      }

      // Character selection prompts
      if (strstr(query, "Shall I pick") || strstr(query, "random")) {
        result = 'y';
        break;
      }

      if (strstr(query, "Is this ok")) {
        result = 'y';
        break;
      }
    }

    // Use default if no special case matched
    if (result == 0) {
      result = def ? def : 'n';
    }
    break;
  }

  // Store the actual response
  current_yn_context.user_response = result;

  // If we have a callback registered, use it instead (THREAD-SAFE)
  pthread_mutex_lock(&yn_callback_mutex);
  YNResponseCallback callback_copy = yn_callback; // Make copy while locked
  pthread_mutex_unlock(&yn_callback_mutex);

  if (callback_copy) {
    char callback_result = callback_copy(&current_yn_context);
    if (callback_result != 0) {
      fprintf(stderr, "[YN_FUNCTION] Callback overrode with: '%c'\n",
              callback_result);
      result = callback_result;
    }
  }

  fprintf(stderr, "[YN_FUNCTION] Returning: '%c'\n", result);
  return result;
}

// Extern declaration for text input notification
extern void ios_request_text_input(const char *prompt, const char *input_type);

static void ios_getlin(const char *query, char *bufp) {
  WIN_LOG("getlin");
  fprintf(stderr, "[GETLIN] Query: %s\n", query ? query : "");

  if (query) {
    safe_append_to_output(query);
    safe_append_to_output("\n");

    // Auto-responses for character creation prompts only
    if (strstr(query, "save") || strstr(query, "Save")) {
      strcpy(bufp, "save");
      fprintf(stderr, "[GETLIN] Auto-responding with: save\n");
      return;
    }

    // Notify Swift UI for prompts that need TextInputSheet
    // Genocide: "What monster do you want to genocide? [type the name]"
    if (strstr(query, "genocide") || strstr(query, "Genocide")) {
      fprintf(stderr, "[GETLIN] Genocide prompt detected - notifying Swift\n");
      ios_request_text_input(query, "genocide");
    }
    // Polymorph: "Become what kind of monster? [type the name]"
    else if (strstr(query, "Become what") || strstr(query, "polymorph")) {
      fprintf(stderr, "[GETLIN] Polymorph prompt detected - notifying Swift\n");
      ios_request_text_input(query, "polymorph");
    }
    // Name prompts: "What do you want to name ..."
    else if ((strstr(query, "name") || strstr(query, "Name")) &&
             (strstr(query, "What") || strstr(query, "what"))) {
      fprintf(stderr, "[GETLIN] Name prompt detected - notifying Swift\n");
      ios_request_text_input(query, "name");
    }
    // Wish: "For what do you wish?"
    else if (strstr(query, "wish") || strstr(query, "Wish")) {
      fprintf(stderr, "[GETLIN] Wish prompt detected - notifying Swift\n");
      ios_request_text_input(query, "wish");
    }
    // Annotation: "Replace annotation \"...\" with?" OR "What do you want to call this dungeon level?"
    else if (strstr(query, "annotation") ||
             (strstr(query, "call") && strstr(query, "level"))) {
      fprintf(stderr, "[GETLIN] Annotation prompt detected - notifying Swift\n");
      ios_request_text_input(query, "annotation");
    }
  }

  // Read text input from queue (like ios_get_ext_cmd pattern)
  int bufidx = 0;

  fprintf(stderr, "[GETLIN] Reading text from input queue...\n");

  pthread_mutex_lock(&input_mutex);

  while (bufidx < BUFSZ - 1) {
    // Wait for input if queue is empty
    while (input_queue_head == input_queue_tail && game_thread_running) {
      pthread_cond_wait(&input_cond, &input_mutex);
    }

    // Check for exit
    if (!game_thread_running) {
      pthread_mutex_unlock(&input_mutex);
      fprintf(stderr, "[GETLIN] Game thread stopped, returning empty\n");
      bufp[0] = '\0';
      return;
    }

    // Get character from queue
    char ch = input_queue[input_queue_head];
    input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;

    fprintf(stderr, "[GETLIN] Got char: '%c' (0x%02x)\n",
            isprint(ch) ? ch : '?', (unsigned char)ch);

    // Handle special characters
    if (ch == '\033') {  // ESC - cancel
      pthread_mutex_unlock(&input_mutex);
      fprintf(stderr, "[GETLIN] ESC pressed, canceling\n");
      // CRITICAL: Return ESC char, NOT empty string!
      // NetHack's do_genocide() checks: if (*buf == '\033') return;
      // Empty string causes "Type the name of a type of monster" loop!
      bufp[0] = '\033';
      bufp[1] = '\0';
      return;
    }

    if (ch == '\n' || ch == '\r') {  // Enter - done
      break;
    }

    // Accumulate printable characters
    if (isprint(ch)) {
      bufp[bufidx++] = ch;
    }
  }

  pthread_mutex_unlock(&input_mutex);
  bufp[bufidx] = '\0';

  fprintf(stderr, "[GETLIN] Returning text: \"%s\"\n", bufp);
}

static int ios_get_ext_cmd(void) {
  WIN_LOG("get_ext_cmd");

  // Read extended command name from input queue
  // When user sends "#pray", the '#' triggers doextcmd() which calls this.
  // We need to read "pray\n" from the queue and match it.

  char buf[BUFSZ];
  int bufidx = 0;
  int *ecmatches = NULL;
  int nmatches;

  fprintf(stderr, "[EXT_CMD] Reading extended command from input queue...\n");

  // Read characters until newline, ESC, or buffer full
  pthread_mutex_lock(&input_mutex);

  while (bufidx < BUFSZ - 1) {
    // Wait for input if queue is empty
    while (input_queue_head == input_queue_tail && game_thread_running) {
      pthread_cond_wait(&input_cond, &input_mutex);
    }

    // Check for exit
    if (!game_thread_running) {
      pthread_mutex_unlock(&input_mutex);
      fprintf(stderr, "[EXT_CMD] Game thread stopped, canceling\n");
      return -1;
    }

    // Get character from queue
    char ch = input_queue[input_queue_head];
    input_queue_head = (input_queue_head + 1) % INPUT_QUEUE_SIZE;

    fprintf(stderr, "[EXT_CMD] Got char: '%c' (0x%02x)\n",
            isprint(ch) ? ch : '?', (unsigned char)ch);

    // Handle special characters
    if (ch == '\033') {  // ESC - cancel
      pthread_mutex_unlock(&input_mutex);
      fprintf(stderr, "[EXT_CMD] ESC pressed, canceling\n");
      return -1;
    }

    if (ch == '\n' || ch == '\r') {  // Enter - done
      break;
    }

    // Accumulate printable characters
    if (isprint(ch)) {
      buf[bufidx++] = ch;
    }
  }

  pthread_mutex_unlock(&input_mutex);
  buf[bufidx] = '\0';

  fprintf(stderr, "[EXT_CMD] Command name: \"%s\"\n", buf);

  // Empty command or just whitespace - cancel
  if (buf[0] == '\0') {
    fprintf(stderr, "[EXT_CMD] Empty command, canceling\n");
    return -1;
  }

  // Match against extended command list
  // ECM_IGNOREAC = ignore auto-completion flag
  // ECM_EXACTMATCH = require exact match (not prefix)
  nmatches = extcmds_match(buf, ECM_IGNOREAC | ECM_EXACTMATCH, &ecmatches);

  if (nmatches != 1) {
    if (nmatches == 0) {
      fprintf(stderr, "[EXT_CMD] Unknown command: \"%s\"\n", buf);
      pline("#%s: unknown extended command.", buf);
    } else {
      fprintf(stderr, "[EXT_CMD] Ambiguous command: \"%s\" (%d matches)\n",
              buf, nmatches);
      pline("#%s: ambiguous extended command.", buf);
    }
    return -1;
  }

  fprintf(stderr, "[EXT_CMD] Matched command index: %d\n", ecmatches[0]);
  return ecmatches[0];
}

static void ios_number_pad(int num) { WIN_LOG("number_pad"); }

// REMOVED: ios_flush_map() - replaced by queue-based rendering

// Adaptive throttling state for delay_output
static volatile int delay_update_pending = 0;
static int consecutive_drops = 0;
static uint64_t last_dispatch_time_ns = 0;

// Helper to get current time in nanoseconds
static uint64_t get_time_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static void ios_delay_output(void) {
  /* Called during travel/run to show intermediate steps
   *
   * ADAPTIVE FRAME TIMING FIX:
   * - Problem: Dropping too many frames caused teleport effect (user can't see
   * steps!)
   * - Old approach: Simple throttle → dropped frames silently → teleport
   * - New approach: Adaptive timing with intelligent sleeps
   *
   * Strategy:
   * 1. Measure actual UI render time
   * 2. If UI is lagging (consecutive drops), slow down NetHack with small sleep
   * 3. Adjust sleep time based on measured render performance
   * 4. Show ALMOST EVERY step (max 2 consecutive drops before tactical pause)
   *
   * Root Cause: Rate mismatch between NetHack (100+ steps/sec) and iOS (60 FPS)
   * Solution: Intelligent pacing that respects both performance and UX
   */

  // PHASE 1: Measure UI render time
  uint64_t now = get_time_ns();
  uint64_t elapsed_ns =
      (last_dispatch_time_ns > 0) ? (now - last_dispatch_time_ns) : 0;
  uint64_t elapsed_ms = elapsed_ns / 1000000ULL;

  // PHASE 2: Adaptive throttling - drop frames only if necessary
  if (delay_update_pending) {
    consecutive_drops++;

    // If we're dropping too many frames, SLOW DOWN NetHack
    // This ensures user sees most steps instead of teleporting
    if (consecutive_drops > 2) {
      // UI is lagging - give it breathing room
      // 5ms tactical pause is imperceptible but prevents excessive drops
      usleep(5000);
    }

    return; // Skip this frame (but we'll show the next one!)
  }

  // Successfully rendering - reset consecutive drop counter
  consecutive_drops = 0;
  delay_update_pending = 1;
  last_dispatch_time_ns = now;

  // Capture current map state
  ios_capture_map();

  // Notify Swift UI (non-blocking dispatch)
  dispatch_async(dispatch_get_main_queue(), ^{
    ios_notify_map_changed();
    delay_update_pending = 0;
  });

  // PHASE 3: Intelligent pacing - control movement SPEED (not FPS!)
  // User wants: 60 FPS smooth rendering BUT slower character movement
  // Solution: Longer sleeps = NetHack generates steps slower = character moves
  // slower
  //           But UI still renders at 60 FPS (smooth!)
  if (elapsed_ms < 16) {
    // UI renders fast (60 FPS) - slow down character movement
    // Each step visible longer for better perception
    usleep(30000); // 30ms per step = ~33 steps/sec, smooth at 60 FPS
  } else if (elapsed_ms < 33) {
    // UI at 30-60 FPS - slightly slower movement
    usleep(35000); // 35ms per step = ~28 steps/sec
  } else {
    // UI slow (<30 FPS) - much slower movement
    usleep(40000); // 40ms per step = ~25 steps/sec
  }

  // Result: User sees smooth step-by-step animation at device-appropriate FPS
  // No teleport, no memory leak, no stuttering!
}

// REMOVED: ios_start_screen() and ios_end_screen() - not used in iOS
// implementation

static void ios_outrip(winid win, int how, time_t when) { WIN_LOG("outrip"); }

static void ios_preference_update(const char *pref) {
  WIN_LOG("preference_update");
}

static char *ios_getmsghistory(boolean init) {
  WIN_LOG("getmsghistory");
  return NULL;
}

static void ios_putmsghistory(const char *msg, boolean is_restoring) {
  WIN_LOG("putmsghistory");
}

static void ios_status_init(void) {
  WIN_LOG("status_init - Initializing iOS status display");
  /* Initialize status window with all fields */
  memset(&current_stats, 0, sizeof(current_stats));
  /* Status initialization complete */
}

static void ios_status_finish(void) {
  WIN_LOG("status_finish - Cleaning up iOS status display");
  /* Clean up status resources */
  memset(&current_stats, 0, sizeof(current_stats));
}

/* PUBLIC: Clear status cache (called after restore to prevent corruption) */
NETHACK_EXPORT void ios_clear_status_cache(void) {
  WIN_LOG("🧹 ios_clear_status_cache() - Clearing cached status");
  memset(&current_stats, 0, sizeof(current_stats));
}

static void ios_status_enablefield(int fieldidx, const char *nm,
                                   const char *fmt, boolean enable) {
  // Silenced: too verbose (24 fields × 2 logs = 48 lines!)
  // Only log during initial debug if needed
  /* Track which fields are enabled for proper display */
  static boolean field_enabled[24]; /* MAXBLSTATS */
  if (fieldidx >= 0 && fieldidx < BL_FLUSH) {
    field_enabled[fieldidx] = enable;
  }
}

static void ios_status_update(int idx, genericptr_t ptr, int chg, int percent,
                              int color, unsigned long *colormasks) {
  /* Import the status field enums from botl.h */
  enum statusfields {
    BL_CHARACTERISTICS = -3,
    BL_RESET = -2,
    BL_FLUSH = -1,
    BL_TITLE = 0,
    BL_STR = 1,
    BL_DX = 2,
    BL_CO = 3,
    BL_IN = 4,
    BL_WI = 5,
    BL_CH = 6,
    BL_ALIGN = 7,
    BL_SCORE = 8,
    BL_CAP = 9,
    BL_GOLD = 10,
    BL_ENE = 11,
    BL_ENEMAX = 12,
    BL_XP = 13,
    BL_AC = 14,
    BL_HD = 15,
    BL_TIME = 16,
    BL_HUNGER = 17,
    BL_HP = 18,
    BL_HPMAX = 19,
    BL_LEVELDESC = 20,
    BL_EXP = 21,
    BL_CONDITION = 22,
    BL_VERS = 23
  };

  /* Some fields might not have ptr data */
  if (!ptr && idx != BL_RESET && idx != BL_FLUSH) {
    WIN_LOG("Warning: NULL ptr for field %d", idx);
    return;
  }

  /* Update our cached stats based on which field is being updated
   * NOTE: NetHack sends FORMATTED STRINGS for most fields, NOT raw integers!
   * Example: "HP:16(16)" instead of raw int 16
   * We must parse these strings, not cast pointers!
   * See origin/NetHack/src/botl.c:147 for format
   */
  switch (idx) {
  case BL_HP:
    current_stats.hp = (int)strtol((char *)ptr, NULL, 10);
    WIN_LOG("HP updated: %d", current_stats.hp);
    break;
  case BL_HPMAX:
    current_stats.hpmax = (int)strtol((char *)ptr, NULL, 10);
    WIN_LOG("HP Max updated: %d", current_stats.hpmax);
    break;
  case BL_ENE:
    current_stats.pw = (int)strtol((char *)ptr, NULL, 10);
    WIN_LOG("Power updated: %d", current_stats.pw);
    break;
  case BL_ENEMAX:
    current_stats.pwmax = (int)strtol((char *)ptr, NULL, 10);
    WIN_LOG("Power Max updated: %d", current_stats.pwmax);
    break;
  case BL_XP:
    current_stats.level = (int)strtol((char *)ptr, NULL, 10);
    WIN_LOG("Level updated: %d", current_stats.level);
    break;
  case BL_EXP:
    current_stats.exp = strtol((char *)ptr, NULL, 10);
    WIN_LOG("Experience updated: %ld", current_stats.exp);
    break;
  case BL_AC:
    current_stats.ac = (int)strtol((char *)ptr, NULL, 10);
    WIN_LOG("AC updated: %d", current_stats.ac);
    break;
  case BL_GOLD:
    current_stats.gold = strtoll((char *)ptr, NULL, 10);
    WIN_LOG("Gold updated: %lld", current_stats.gold);
    break;
  case BL_TIME:
    current_stats.moves = strtol((char *)ptr, NULL, 10);
    WIN_LOG("Moves updated: %ld", current_stats.moves);
    break;
  case BL_STR:
    current_stats.str = (int)strtol((char *)ptr, NULL, 10);
    break;
  case BL_DX:
    current_stats.dex = (int)strtol((char *)ptr, NULL, 10);
    break;
  case BL_CO:
    current_stats.con = (int)strtol((char *)ptr, NULL, 10);
    break;
  case BL_IN:
    current_stats.intel = (int)strtol((char *)ptr, NULL, 10);
    break;
  case BL_WI:
    current_stats.wis = (int)strtol((char *)ptr, NULL, 10);
    break;
  case BL_CH:
    current_stats.cha = (int)strtol((char *)ptr, NULL, 10);
    break;
  case BL_ALIGN:
    if (ptr) {
      strncpy(current_stats.align, (char *)ptr,
              sizeof(current_stats.align) - 1);
      current_stats.align[sizeof(current_stats.align) - 1] = '\0';
    }
    break;
  case BL_HUNGER:
    /* ptr is a string like "Satiated", "Hungry", "Weak", etc.
     * Empty string means NOT_HUNGRY (normal state).
     * Convert to numeric: 0=Satiated, 1=Normal, 2=Hungry, 3=Weak, 4=Fainting, 5=Fainted, 6=Starved */
    if (ptr) {
      const char *hunger_str = (const char *)ptr;
      if (!hunger_str[0] || !strcmp(hunger_str, " ")) {
        current_stats.hunger = 1;  /* NOT_HUNGRY (normal) */
      } else if (strstr(hunger_str, "Satiated")) {
        current_stats.hunger = 0;
      } else if (strstr(hunger_str, "Hungry")) {
        current_stats.hunger = 2;
      } else if (strstr(hunger_str, "Weak")) {
        current_stats.hunger = 3;
      } else if (strstr(hunger_str, "Fainting")) {
        current_stats.hunger = 4;
      } else if (strstr(hunger_str, "Fainted")) {
        current_stats.hunger = 5;
      } else if (strstr(hunger_str, "Starved")) {
        current_stats.hunger = 6;
      } else {
        current_stats.hunger = 1;  /* Default to normal */
      }
      WIN_LOG("Hunger updated: %d (from '%s')", current_stats.hunger, hunger_str);
    }
    break;
  case BL_CONDITION:
    /* ptr is unsigned long* containing 30-bit condition bitmask */
    current_stats.conditions = *(unsigned long *)ptr;
    WIN_LOG("Conditions updated: 0x%lx", current_stats.conditions);
    break;
  case BL_RESET:
    WIN_LOG("Status reset requested");
    /* Reset could mean we should clear stats, but often it means "refresh all"
     */
    memset(&current_stats, 0, sizeof(current_stats));
    break;
  case BL_FLUSH:
    WIN_LOG("Status flush requested");
    /* Flush means all pending updates are done - enqueue status to render queue
     */
    if (g_render_queue) {
      RenderQueueElement elem = {
          .type = UPDATE_STATUS,
          .data.status = {.hp = current_stats.hp,
                          .hpmax = current_stats.hpmax,
                          .pw = current_stats.pw,
                          .pwmax = current_stats.pwmax,
                          .level = current_stats.level,
                          .exp = current_stats.exp,
                          .ac = current_stats.ac,
                          .str = current_stats.str,
                          .dex = current_stats.dex,
                          .con = current_stats.con,
                          .intel = current_stats.intel,
                          .wis = current_stats.wis,
                          .cha = current_stats.cha,
                          .gold = current_stats.gold,
                          .moves = current_stats.moves,
                          .hunger = current_stats.hunger,
                          .conditions = current_stats.conditions}};
      // Copy align string separately
      strncpy(elem.data.status.align, current_stats.align,
              sizeof(elem.data.status.align) - 1);
      elem.data.status.align[sizeof(elem.data.status.align) - 1] = '\0';

      render_queue_enqueue(g_render_queue, &elem);
    }
    break;
  default:
    /* Ignore other fields for now */
    break;
  }
}

static boolean ios_can_suspend(void) { return FALSE; }

static char ios_message_menu(char let, int how, const char *mesg) {
  WIN_LOG("message_menu");
  return let;
}

static win_request_info *ios_ctrl_nhwindow(winid win, int request,
                                           win_request_info *wri) {
  WIN_LOG("ctrl_nhwindow");
  return wri;
}

/* === Window Procedures Structure === */
/* This is simpler - let NetHack fill in the defaults */
NETHACK_EXPORT struct window_procs ios_procs = {
    "swift", /* SwiftUI window system */
    WC_IOS,  /* wp_id - iOS specific ID */
    WC_COLOR | WC_HILITE_PET | WC_FONT_MAP | WC_FONT_MENU | WC_FONT_STATUS |
        WC_FONT_MESSAGE | WC_FONT_TEXT | WC_FONTSIZ_MAP | WC_FONTSIZ_MENU |
        WC_FONTSIZ_STATUS | WC_FONTSIZ_MESSAGE | WC_FONTSIZ_TEXT |
        WC_SCROLL_AMOUNT | WC_SPLASH_SCREEN | WC_POPUP_DIALOG |
        WC_MOUSE_SUPPORT, /* Enhanced capabilities for 9/10 */
    WC2_FLUSH_STATUS | WC2_RESET_STATUS | WC2_HILITE_STATUS | WC2_TERM_SIZE |
        WC2_STATUSLINES | WC2_PETATTR | WC2_MENU_SHIFT |
        WC2_HITPOINTBAR, /* Full wincap2 support */
    {0},                 /* has_color array */
    ios_init_nhwindows,
    ios_player_selection,
    ios_askname,
    ios_get_nh_event,
    ios_exit_nhwindows,
    ios_suspend_nhwindows,
    ios_resume_nhwindows,
    ios_create_nhwindow,
    ios_clear_nhwindow,
    ios_display_nhwindow,
    ios_destroy_nhwindow,
    ios_curs,
    ios_putstr,
    ios_putmixed,
    ios_display_file,
    ios_start_menu,
    ios_add_menu,
    ios_end_menu,
    ios_select_menu,
    ios_message_menu,
    ios_mark_synch,
    ios_wait_synch,
#ifdef CLIPPING
    ios_cliparound,
#endif
#ifdef POSITIONBAR
    donull, /* update_positionbar */
#endif
    ios_print_glyph,
    ios_raw_print,
    ios_raw_print_bold,
    ios_nhgetch,
    ios_nh_poskey,
    ios_nhbell,
    ios_doprev_message,
    ios_yn_function,
    ios_getlin,
    ios_get_ext_cmd,
    ios_number_pad,
    ios_delay_output,
#ifdef CHANGE_COLOR
    donull, /* change_color */
#ifdef MAC
    donull, /* change_background */
    donull, /* set_font_name */
#endif
    donull, /* get_color_string */
#endif
    ios_outrip,
    ios_preference_update,
    ios_getmsghistory,
    ios_putmsghistory,
    ios_status_init,
    ios_status_finish,
    ios_status_enablefield,
    ios_status_update,
    ios_can_suspend,
    ios_update_inventory,
    ios_ctrl_nhwindow};

/* Swift window system is just ios_procs with a different name */
/* We'll use ios_procs directly and bypass the window registration */

// REMOVED: debug_print_map() - obsolete with queue-based rendering

/* Get player stats for Swift access */
PlayerStats *ios_get_player_stats(void) { return &current_stats; }

/* Get player stats as JSON string */
const char *ios_get_player_stats_json(void) {
  static char json_buffer[512];

  // Get dungeon level from NetHack globals
  extern struct you u; // Player position and dungeon level
  int dungeon_level = (u.uz.dnum >= 0 && u.uz.dlevel > 0) ? u.uz.dlevel : 0;

  snprintf(json_buffer, sizeof(json_buffer),
           "{\"hp\":%d,\"hpmax\":%d,\"pw\":%d,\"pwmax\":%d,"
           "\"level\":%d,\"exp\":%ld,\"ac\":%d,"
           "\"str\":%d,\"dex\":%d,\"con\":%d,\"int\":%d,\"wis\":%d,\"cha\":%d,"
           "\"gold\":%ld,\"moves\":%ld,\"dungeonLevel\":%d,\"align\":\"%s\","
           "\"hunger\":%d}",
           current_stats.hp, current_stats.hpmax, current_stats.pw,
           current_stats.pwmax, current_stats.level, current_stats.exp,
           current_stats.ac, current_stats.str, current_stats.dex,
           current_stats.con, current_stats.intel, current_stats.wis,
           current_stats.cha, current_stats.gold, current_stats.moves,
           dungeon_level, current_stats.align, current_stats.hunger);
  return json_buffer;
}

/* Check if there is pending input in the queue */
int ios_has_pending_input(void) {
  return (input_queue_head != input_queue_tail) ? 1 : 0;
}

/* Queue a string of commands */
void ios_queue_command(const char *cmd) {
  if (!cmd)
    return;

  fprintf(stderr, "[INPUT] Queueing command: \"%s\"\n", cmd);
  while (*cmd) {
    ios_queue_input(*cmd);
    cmd++;
  }
}

/* Initialize iOS window procedures */
NETHACK_EXPORT void init_ios_windowprocs(void) {
  WIN_LOG("init_ios_windowprocs");

  fprintf(stderr, "[WINPROC] About to set windowprocs...\n");
  fprintf(stderr, "[WINPROC] ios_procs.win_status_init = %p\n",
          ios_procs.win_status_init);
  fflush(stderr);

  windowprocs = ios_procs;

  fprintf(stderr, "[WINPROC] After assignment:\n");
  fprintf(stderr, "[WINPROC] windowprocs.win_status_init = %p\n",
          windowprocs.win_status_init);
  fflush(stderr);

  /* Set some required globals */
  iflags.window_inited = TRUE;
  iflags.cbreak = ON;
  iflags.echo = OFF;
}

/* Initialize for window port */
void win_ios_init(int dir) {
  WIN_LOG("win_ios_init");
  init_ios_windowprocs();
}

/* Export map buffer for Swift */
const char *get_map_buffer_line(int y) {
  if (y < 0 || y >= MAX_MAP_HEIGHT)
    return "";
  return map_buffer[y];
}

int get_map_width(void) { return actual_map_width; }

int get_map_height(void) { return actual_map_height; }

boolean is_map_dirty(void) { return map_dirty; }

/* Death info implementation */
const DeathInfo *nethack_get_death_info(void) { return &death_info; }

int nethack_is_player_dead(void) {
  // FIXED: Use the flag we set during death menu processing
  // OR NetHack's official gameover flag
  extern struct sinfo program_state;
  return player_has_died || program_state.gameover;
}

void nethack_clear_death_info(void) {
  memset(&death_info, 0, sizeof(death_info));
  is_capturing_death_info = 0;
  death_info_stage = 0;
  player_has_died = 0; // CRITICAL: Reset for next game!
}

/* Death info accessors - for Swift interop (avoid C struct access completely) */
const char* nethack_get_death_message(void) { return death_info.death_message; }
const char* nethack_get_death_possessions(void) { return death_info.possessions; }
const char* nethack_get_death_attributes(void) { return death_info.attributes; }
const char* nethack_get_death_conduct(void) { return death_info.conduct; }
const char* nethack_get_death_dungeon_overview(void) { return death_info.dungeon_overview; }
const char* nethack_get_death_role_name(void) { return death_info.role_name; }

/* Called from end.c to set death reason based on how parameter */
void ios_set_death_reason(int how) {
    const char* reason;
    switch (how) {
        case 0:  reason = "died"; break;
        case 1:  reason = "choked"; break;
        case 2:  reason = "poisoned"; break;
        case 3:  reason = "starved"; break;
        case 4:  reason = "drowned"; break;
        case 5:  reason = "burned"; break;
        case 6:  reason = "dissolved"; break;
        case 7:  reason = "crushed"; break;
        case 8:  reason = "petrified"; break;
        case 9:  reason = "slimed"; break;
        case 10: reason = "genocided"; break;
        case 11: reason = "panicked"; break;
        case 12: reason = "tricked"; break;
        case 13: reason = "quit"; break;
        case 14: reason = "escaped"; break;
        case 15: reason = "ascended"; break;
        default: reason = "unknown"; break;
    }
    strncpy(death_info.death_reason, reason, sizeof(death_info.death_reason) - 1);
    death_info.death_reason[sizeof(death_info.death_reason) - 1] = '\0';
}

const char* nethack_get_death_reason(void) { return death_info.death_reason; }
int nethack_get_death_final_level(void) { return death_info.final_level; }
int nethack_get_death_final_hp(void) { return death_info.final_hp; }
int nethack_get_death_final_maxhp(void) { return death_info.final_maxhp; }
long nethack_get_death_final_gold(void) { return death_info.final_gold; }
long nethack_get_death_final_score(void) { return death_info.final_score; }
long nethack_get_death_final_turns(void) { return death_info.final_turns; }
int nethack_get_death_dungeon_level(void) { return death_info.dungeon_level; }

/* YN callback implementation - THREAD SAFE */
void nethack_register_yn_callback(YNResponseCallback callback) {
  pthread_mutex_lock(&yn_callback_mutex);
  yn_callback = callback;
  pthread_mutex_unlock(&yn_callback_mutex);
  fprintf(stderr, "[YN_CALLBACK] Registered callback (thread-safe)\n");
}

void nethack_unregister_yn_callback(void) {
  pthread_mutex_lock(&yn_callback_mutex);
  yn_callback = NULL;
  pthread_mutex_unlock(&yn_callback_mutex);
  fprintf(stderr, "[YN_CALLBACK] Unregistered callback (thread-safe)\n");
}

const YNContext *nethack_get_current_yn_context(void) {
  return &current_yn_context;
}

/*
 * ============================================================================
 * MENU CALLBACK IMPLEMENTATION (C -> Swift Menu Display)
 * ============================================================================
 *
 * These functions allow Swift to register a callback for menu display.
 * When NetHack needs to show a menu, it calls the Swift callback which
 * shows the NHMenuSheet UI and returns the user's selection.
 */

void ios_register_menu_callback(IOSMenuCallback callback) {
  pthread_mutex_lock(&menu_callback_mutex);
  swift_menu_callback = callback;
  pthread_mutex_unlock(&menu_callback_mutex);
  fprintf(stderr, "[MENU_CALLBACK] Registered menu callback (thread-safe)\n");
}

void ios_unregister_menu_callback(void) {
  pthread_mutex_lock(&menu_callback_mutex);
  swift_menu_callback = NULL;
  pthread_mutex_unlock(&menu_callback_mutex);
  fprintf(stderr, "[MENU_CALLBACK] Unregistered menu callback (thread-safe)\n");
}

bool ios_has_menu_callback(void) {
  pthread_mutex_lock(&menu_callback_mutex);
  bool has_callback = (swift_menu_callback != NULL);
  pthread_mutex_unlock(&menu_callback_mutex);
  return has_callback;
}

/*
 * Async menu response - called by Swift after user makes selection.
 * This is for future async implementation where C doesn't block.
 * Currently the callback is synchronous (blocks until Swift returns).
 */
void ios_menu_response(IOSMenuSelection* selections, int count) {
  pthread_mutex_lock(&menu_response_mutex);

  // Copy selections
  menu_response_count = count;
  if (count > 0 && selections) {
    int copy_count = count < MAX_MENU_ITEMS ? count : MAX_MENU_ITEMS;
    memcpy(menu_response_selections, selections, copy_count * sizeof(IOSMenuSelection));
  }

  // Signal waiting thread
  pthread_cond_signal(&menu_response_cond);
  pthread_mutex_unlock(&menu_response_mutex);

  fprintf(stderr, "[MENU_CALLBACK] Received menu response with %d selection(s)\n", count);
}

/*
 * ============================================================================
 * SYMBOL CUSTOMIZATION SYSTEM
 * ============================================================================
 *
 * iOS-specific symbol overrides for better mobile visibility.
 * Changes boulders from backtick (`) to zero (0) for clarity.
 */
void ios_setup_default_symbols(void) {
  // Access global options structure
  extern struct instance_globals_o go;

  // Safety: Ensure symbols are initialized
  // CRITICAL FIX: After nh_restart(), go.ov_primary_syms might be non-NULL
  // but point to ZEROED memory! We need to check if the actual VALUES are zero.
  // Check if first symbol is zero (which would never be valid)
  extern struct instance_globals_s gs;

  if (!go.ov_primary_syms || gs.showsyms[0] == 0) {
    fprintf(stderr, "[IOS_SYMBOLS] Symbol arrays empty/zeroed after restore, calling "
                    "init_symbols()...\n");

    // Initialize the symbol system (from symbols.c)
    extern void init_symbols(void);
    init_symbols();

    // Check again after initialization
    if (!go.ov_primary_syms || gs.showsyms[0] == 0) {
      fprintf(
          stderr,
          "[IOS_SYMBOLS] ERROR: init_symbols() failed to populate arrays!\n");
      // Try one more time with explicit reset
      init_symbols();
    }
    fprintf(stderr, "[IOS_SYMBOLS] ✓ Symbol system initialized (showsyms[0]='%c')\n",
            gs.showsyms[0] ? gs.showsyms[0] : '?');
  } else {
    fprintf(stderr, "[IOS_SYMBOLS] Symbols already initialized (showsyms[0]='%c')\n",
            gs.showsyms[0]);
  }

  // Boulder symbol override: backtick (`) → zero (0)
  // Uses NetHack's highest priority override array
  // SYM_BOULDER is defined in sym.h as 2
  // SYM_OFF_X is defined in hack.h as the offset for misc symbols
  // This matches the pattern used in options.c:2944
  go.ov_primary_syms[SYM_BOULDER + SYM_OFF_X] = '0';

  // Also set for rogue level consistency
  go.ov_rogue_syms[SYM_BOULDER + SYM_OFF_X] = '0';

  // CRITICAL: Refresh display cache with new override
  // Without this, gs.showsyms[] still contains old backtick symbol
  extern void assign_graphics(int which_set);

  fprintf(stderr, "[IOS_SYMBOLS] Refreshing symbol cache...\n");

  // Check which graphics set is currently active
  extern struct instance_globals_c gc;
  int current_set = gc.currentgraphics;

  // CRITICAL: currentgraphics is not initialized properly after restore
  // For iOS, we always use PRIMARYSET (which is actually 0)
  // But we need to ensure init_symbols() was called first!
  fprintf(stderr, "[IOS_SYMBOLS] currentgraphics = %d\n", current_set);

  // Update the active symbol set to apply our overrides
  // This copies from go.ov_primary_syms[] to gs.showsyms[]
  // and calls reset_glyphmap(gm_symchange) internally
  assign_graphics(current_set);

  fprintf(stderr,
          "[IOS_SYMBOLS] ✓ Boulder symbol set to '0' and cache refreshed\n");
}

/*
 * ============================================================================
 * COMPREHENSIVE STATE RESET SYSTEM
 * ============================================================================
 *
 * CRITICAL: This function resets ALL static variables in ios_winprocs.c
 * Must be called when starting a new game to prevent state leakage.
 *
 * Bug Context: Without this, second game shows first game's stats, menus,
 * death info, and has corrupted input queue.
 *
 * Call Sites:
 * - GameManager.resetForNewGame() (Swift)
 * - ios_newgame.c initialization
 * - After death screen is dismissed
 */
void ios_reset_all_static_state(void) {
  fprintf(stderr, "[IOS_RESET] ========================================\n");
  fprintf(stderr, "[IOS_RESET] Resetting ALL static state for new game\n");
  fprintf(stderr, "[IOS_RESET] ========================================\n");

  // 1. PLAYER STATS SYSTEM (line 39)
  fprintf(stderr, "[IOS_RESET] Clearing player stats...\n");
  memset(&current_stats, 0, sizeof(PlayerStats));

  // 2. DEATH INFO SYSTEM (lines 43-46)
  fprintf(stderr, "[IOS_RESET] Clearing death info system...\n");
  memset(&death_info, 0, sizeof(DeathInfo));
  is_capturing_death_info = 0;
  death_info_stage = 0;
  player_has_died = 0;

  // 3. INPUT QUEUE SYSTEM (lines 67-68)
  fprintf(stderr, "[IOS_RESET] Clearing input queue...\n");
  pthread_mutex_lock(&input_mutex);
  memset(input_queue, 0, INPUT_QUEUE_SIZE);
  input_queue_head = 0;
  input_queue_tail = 0;
  pthread_mutex_unlock(&input_mutex);

  // 4. EXIT FLAG (line 119 - atomic version)
  fprintf(stderr, "[IOS_RESET] Resetting exit flag...\n");
  atomic_store(&game_should_exit, 0); // Thread-safe atomic write

  // 5. MENU SYSTEM (lines 481-484, 522)
  fprintf(stderr, "[IOS_RESET] Clearing menu system...\n");
  menu_item_count = 0;
  current_menu_win = 0;
  menu_is_active = FALSE;
  memset(last_menu_prompt, 0, sizeof(last_menu_prompt));
  memset(menu_items, 0, sizeof(menu_items));       // Clear menu items array
  memset(menu_selectors, 0, sizeof(menu_selectors)); // Clear menu selectors array
  memset(menu_texts, 0, sizeof(menu_texts));       // Clear menu text array
  memset(menu_glyphs, 0, sizeof(menu_glyphs));     // Clear menu glyph array
  memset(menu_attributes, 0, sizeof(menu_attributes)); // Clear menu attributes array
  memset(menu_itemflags, 0, sizeof(menu_itemflags)); // Clear menu itemflags array

  // Menu callback stays registered - don't reset swift_menu_callback

  // 6. PLAYER TRACKING (lines 643-644)
  fprintf(stderr, "[IOS_RESET] Resetting player position tracking...\n");
  old_player_x = -1;
  old_player_y = -1;

  // 7. Y/N SYSTEM (lines 912-914)
  fprintf(stderr, "[IOS_RESET] Clearing Y/N response system...\n");
  current_yn_mode = YN_MODE_DEFAULT;
  next_yn_response = 0;
  custom_yn_callback = NULL; // Note: yn_callback set by Swift, don't clear
  memset(&current_yn_context, 0, sizeof(YNContext));

  // 8. GAME STATE FLAGS (from RealNetHackBridge.c integration)
  fprintf(stderr, "[IOS_RESET] Resetting game state flags...\n");
  extern int game_started;
  extern int character_creation_complete;
  game_started = 0;
  character_creation_complete = 0;

  // 9. DELAY OUTPUT THROTTLING (lines 1273-1275)
  fprintf(stderr, "[IOS_RESET] Resetting delay_output throttling...\n");
  delay_update_pending = 0;
  consecutive_drops = 0;
  last_dispatch_time_ns = 0;

  // 10. GAME READY SIGNAL FLAG (line 966)
  fprintf(stderr, "[IOS_RESET] Resetting game ready signal flag...\n");
  game_ready_signaled = 0;

  // 11. MESSAGE QUEUE STATE (for Swift message buffering)
  fprintf(stderr, "[IOS_RESET] Resetting message queue state...\n");
  extern void ios_reset_message_queue_state(void);
  ios_reset_message_queue_state();

  // 12. OUTPUT BUFFER (CRITICAL: prevents stale death data from breaking new games)
  fprintf(stderr, "[IOS_RESET] Clearing output_buffer...\n");
  memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);

  fprintf(stderr, "[IOS_RESET] ✓ ALL STATIC STATE CLEARED\n");
  fprintf(stderr, "[IOS_RESET] ✓ Ready for new game\n");
  fprintf(stderr, "[IOS_RESET] ========================================\n");
}

/*
 * ============================================================================
 * VANQUISHED MONSTERS API
 * ============================================================================
 *
 * Functions to access monster kill statistics for the death screen.
 * Uses svm.mvitals[] array which tracks born/died counts per monster type.
 */

/* Get total number of monsters killed */
int ios_get_total_kills(void) {
    extern struct instance_globals_saved_m svm;
    extern struct sinfo program_state;
    /* Guard: only access if game is running or game over */
    if (!program_state.in_moveloop && !program_state.gameover) {
        return 0;
    }
    int total = 0;
    for (int i = LOW_PM; i < NUMMONS; i++) {
        total += svm.mvitals[i].died;
    }
    return total;
}

/* Get number of unique monster types killed */
int ios_get_unique_kills_count(void) {
    extern struct instance_globals_saved_m svm;
    extern struct sinfo program_state;
    /* Guard: only access if game is running or game over */
    if (!program_state.in_moveloop && !program_state.gameover) {
        return 0;
    }
    int count = 0;
    for (int i = LOW_PM; i < NUMMONS; i++) {
        if (svm.mvitals[i].died > 0) {
            count++;
        }
    }
    return count;
}

/* Get kill count for specific monster type */
int ios_get_monster_kills(int mndx) {
    extern struct instance_globals_saved_m svm;
    if (mndx < LOW_PM || mndx >= NUMMONS) {
        return 0;
    }
    return svm.mvitals[mndx].died;
}

/* Get monster name by index */
const char* ios_get_monster_name(int mndx) {
    if (mndx < LOW_PM || mndx >= NUMMONS) {
        return "";
    }
    return mons[mndx].pmnames[NEUTRAL];
}

/* Fill arrays with top N monster kills (sorted by kill count descending) */
int ios_get_top_kills(int* indices, int* counts, int max_results) {
    extern struct instance_globals_saved_m svm;
    if (!indices || !counts || max_results <= 0) {
        return 0;
    }

    /* First collect all monsters with kills */
    int all_indices[NUMMONS];
    int all_counts[NUMMONS];
    int num_killed = 0;

    for (int i = LOW_PM; i < NUMMONS; i++) {
        if (svm.mvitals[i].died > 0) {
            all_indices[num_killed] = i;
            all_counts[num_killed] = svm.mvitals[i].died;
            num_killed++;
        }
    }

    /* Simple bubble sort by kill count (descending) */
    for (int i = 0; i < num_killed - 1; i++) {
        for (int j = 0; j < num_killed - i - 1; j++) {
            if (all_counts[j] < all_counts[j + 1]) {
                int tmp_idx = all_indices[j];
                int tmp_cnt = all_counts[j];
                all_indices[j] = all_indices[j + 1];
                all_counts[j] = all_counts[j + 1];
                all_indices[j + 1] = tmp_idx;
                all_counts[j + 1] = tmp_cnt;
            }
        }
    }

    /* Copy top N to output arrays */
    int result_count = num_killed < max_results ? num_killed : max_results;
    for (int i = 0; i < result_count; i++) {
        indices[i] = all_indices[i];
        counts[i] = all_counts[i];
    }

    return result_count;
}

/*
 * ============================================================================
 * DUNGEON OVERVIEW API
 * ============================================================================
 *
 * Functions to access dungeon level information for native iOS UI.
 * Exposes the mapseen chain data that NetHack uses for #overview command.
 */

/* Refresh dungeon overview data - calls recalc_mapseen() to ensure up-to-date */
void ios_refresh_dungeon_overview(void) {
    extern struct sinfo program_state;
    if (!program_state.in_moveloop && !program_state.gameover) {
        return;
    }
    /* Call NetHack's internal function to recalculate level data */
    extern void recalc_mapseen(void);
    recalc_mapseen();
}

/* Get total count of visited dungeon levels */
int ios_get_visited_level_count(void) {
    extern struct instance_globals_saved_m svm;
    extern struct sinfo program_state;

    if (!program_state.in_moveloop && !program_state.gameover) {
        return 0;
    }

    int count = 0;
    mapseen *mptr;
    for (mptr = svm.mapseenchn; mptr; mptr = mptr->next) {
        count++;
    }
    return count;
}

/* Get dungeon level info by index */
bool ios_get_dungeon_level_info(int index, DungeonLevelInfo *out) {
    extern struct instance_globals_saved_m svm;
    extern struct instance_globals_saved_d svd;
    extern struct instance_globals_saved_n svn;
    extern struct sinfo program_state;
    extern struct you u;

    if (!out) return false;
    if (!program_state.in_moveloop && !program_state.gameover) {
        return false;
    }

    /* Find the mapseen entry at given index */
    mapseen *mptr = svm.mapseenchn;
    int current = 0;
    while (mptr && current < index) {
        mptr = mptr->next;
        current++;
    }

    if (!mptr) return false;

    /* Zero out the output struct */
    memset(out, 0, sizeof(DungeonLevelInfo));

    /* Basic level info */
    out->dnum = mptr->lev.dnum;
    out->dlevel = mptr->lev.dlevel;

    /* Dungeon name */
    if (mptr->lev.dnum >= 0 && mptr->lev.dnum < svn.n_dgns) {
        strncpy(out->dungeon_name, svd.dungeons[mptr->lev.dnum].dname,
                sizeof(out->dungeon_name) - 1);
    }

    /* Calculate depth - special cases for quest/knox */
    int depthstart;
    /* quest_dnum and knox_level are macros defined in hack.h */
    int qdnum = quest_dnum;  /* macro from hack.h */
    int kdnum = knox_level.dnum;  /* knox_level is a macro expanding to svd.dungeon_topology.d_knox_level */

    if (mptr->lev.dnum == qdnum || mptr->lev.dnum == kdnum) {
        depthstart = 1;
    } else if (mptr->lev.dnum >= 0 && mptr->lev.dnum < svn.n_dgns) {
        depthstart = svd.dungeons[mptr->lev.dnum].depth_start;
    } else {
        depthstart = 1;
    }
    out->depth = depthstart + mptr->lev.dlevel - 1;

    /* Features */
    out->shops = mptr->feat.nshop;
    out->temples = mptr->feat.ntemple;
    out->altars = mptr->feat.naltar;
    out->fountains = mptr->feat.nfount;
    out->thrones = mptr->feat.nthrone;
    out->graves = mptr->feat.ngrave;
    out->sinks = mptr->feat.nsink;
    out->trees = mptr->feat.ntree;
    out->shop_type = mptr->feat.shoptype;

    /* Special location flags */
    unsigned int flags = 0;
    if (mptr->flags.oracle) flags |= DUNGEON_FLAG_ORACLE;
    if (mptr->flags.sokosolved) flags |= DUNGEON_FLAG_SOKOBAN_SOLVED;
    if (mptr->flags.bigroom) flags |= DUNGEON_FLAG_BIGROOM;
    if (mptr->flags.castle) flags |= DUNGEON_FLAG_CASTLE;
    if (mptr->flags.valley) flags |= DUNGEON_FLAG_VALLEY;
    if (mptr->flags.msanctum) flags |= DUNGEON_FLAG_SANCTUM;
    if (mptr->flags.ludios) flags |= DUNGEON_FLAG_LUDIOS;
    if (mptr->flags.roguelevel) flags |= DUNGEON_FLAG_ROGUE;
    if (mptr->flags.vibrating_square) flags |= DUNGEON_FLAG_VIB_SQUARE;
    if (mptr->flags.questing) flags |= DUNGEON_FLAG_QUEST_HOME;
    if (mptr->flags.quest_summons) flags |= DUNGEON_FLAG_QUEST_SUMMONS;
    out->special_flags = flags;

    /* Player annotation */
    if (mptr->custom) {
        strncpy(out->annotation, mptr->custom, sizeof(out->annotation) - 1);
    }

    /* Branch connection */
    if (mptr->br) {
        int end_dnum = mptr->br->end2.dnum;
        if (end_dnum >= 0 && end_dnum < svn.n_dgns) {
            strncpy(out->branch_to, svd.dungeons[end_dnum].dname,
                    sizeof(out->branch_to) - 1);
        }
        /* Determine branch type */
        switch (mptr->br->type) {
            case BR_PORTAL:
                out->branch_type = BRANCH_TYPE_PORTAL;
                break;
            case BR_STAIR:
                out->branch_type = mptr->br->end1_up ? BRANCH_TYPE_STAIRS_UP
                                                      : BRANCH_TYPE_STAIRS_DOWN;
                break;
            default:
                out->branch_type = BRANCH_TYPE_NONE;
                break;
        }
    }

    /* Current level check */
    out->is_current_level = (u.uz.dnum == mptr->lev.dnum &&
                             u.uz.dlevel == mptr->lev.dlevel) ? 1 : 0;

    /* Forgotten flag */
    out->is_forgotten = mptr->flags.forgot ? 1 : 0;

    /* Bones flag */
    out->has_bones = (mptr->final_resting_place != NULL ||
                      mptr->flags.knownbones) ? 1 : 0;

    return true;
}

/* Get count of distinct dungeons visited */
int ios_get_dungeon_count(void) {
    extern struct instance_globals_saved_n svn;
    extern struct sinfo program_state;

    if (!program_state.in_moveloop && !program_state.gameover) {
        return 0;
    }
    return svn.n_dgns;
}

/* Get dungeon name by dungeon number */
const char* ios_get_dungeon_name(int dnum) {
    extern struct instance_globals_saved_d svd;
    extern struct instance_globals_saved_n svn;
    extern struct sinfo program_state;

    if (!program_state.in_moveloop && !program_state.gameover) {
        return "";
    }
    if (dnum < 0 || dnum >= svn.n_dgns) {
        return "";
    }
    return svd.dungeons[dnum].dname;
}

/* Get depth range for a dungeon */
bool ios_get_dungeon_depth_range(int dnum, int *min_depth, int *max_depth) {
    extern struct instance_globals_saved_d svd;
    extern struct instance_globals_saved_n svn;
    extern struct sinfo program_state;

    if (!min_depth || !max_depth) return false;
    if (!program_state.in_moveloop && !program_state.gameover) {
        return false;
    }
    if (dnum < 0 || dnum >= svn.n_dgns) {
        return false;
    }

    *min_depth = svd.dungeons[dnum].depth_start;
    *max_depth = svd.dungeons[dnum].depth_start +
                 svd.dungeons[dnum].dunlev_ureached - 1;
    return true;
}

/* =============================================================================
 * ENVIRONMENT DETECTION (for visual theming)
 * =============================================================================
 */

/*
 * Get current dungeon environment for visual theming.
 * Returns environment type for subtle UI color accents.
 * Uses NetHack's In_* macros from dungeon.h.
 */
DungeonEnvironmentType ios_get_current_environment(void) {
    extern struct sinfo program_state;

    if (!program_state.in_moveloop && !program_state.gameover) {
        return ENV_STANDARD;
    }

    /* Check elemental planes first (most specific) */
    if (Is_astralevel(&u.uz)) return ENV_ASTRAL;
    if (Is_waterlevel(&u.uz)) return ENV_WATER;
    if (Is_firelevel(&u.uz)) return ENV_FIRE;
    if (Is_airlevel(&u.uz)) return ENV_AIR;
    if (Is_earthlevel(&u.uz)) return ENV_EARTH;

    /* Check special branches */
    if (In_V_tower(&u.uz)) return ENV_TOWER;
    if (In_hell(&u.uz)) return ENV_GEHENNOM;  /* Includes Valley, Sanctum, etc. */
    if (In_mines(&u.uz)) return ENV_MINES;
    if (In_sokoban(&u.uz)) return ENV_SOKOBAN;
    if (In_quest(&u.uz)) return ENV_QUEST;
    if (In_tutorial(&u.uz)) return ENV_TUTORIAL;

    /* Check special levels */
    if (Is_knox(&u.uz)) return ENV_LUDIOS;

    return ENV_STANDARD;
}
