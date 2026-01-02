#ifndef REAL_NETHACK_BRIDGE_H
#define REAL_NETHACK_BRIDGE_H

#include <stdbool.h>  // For bool type in C
#include "nethack_export.h"  // Symbol visibility control

// Forward declarations for NetHack types
struct obj;  // NetHack object structure (defined in hack.h)

// Dungeon environment types for visual theming
// Must match DungeonEnvironment enum in EnvironmentTheme.swift
typedef enum {
    ENV_STANDARD = 0,   // Dungeons of Doom (default)
    ENV_MINES = 1,      // Gnomish Mines
    ENV_GEHENNOM = 2,   // Gehennom/Hell
    ENV_SOKOBAN = 3,    // Sokoban
    ENV_QUEST = 4,      // The Quest
    ENV_TOWER = 5,      // Vlad's Tower
    ENV_AIR = 6,        // Plane of Air
    ENV_FIRE = 7,       // Plane of Fire
    ENV_WATER = 8,      // Plane of Water
    ENV_EARTH = 9,      // Plane of Earth
    ENV_ASTRAL = 10,    // Astral Plane
    ENV_LUDIOS = 11,    // Fort Ludios
    ENV_TUTORIAL = 12   // Tutorial
} DungeonEnvironmentType;

// Real NetHack Bridge Functions
// These connect Swift to the actual NetHack C engine

// Version information functions
NETHACK_EXPORT const char* nethack_get_lib_version(void);
NETHACK_EXPORT int nethack_get_api_version(void);
NETHACK_EXPORT const char* nethack_get_build_info(void);
NETHACK_EXPORT int nethack_check_compatibility(int required_api_version);

// Initialization and game start
NETHACK_EXPORT void nethack_real_init(void);
NETHACK_EXPORT void nethack_real_newgame(void);
NETHACK_EXPORT void nethack_real_randomize(void);  // Randomize character for auto-start
NETHACK_EXPORT int nethack_real_is_initialized(void);
NETHACK_EXPORT int nethack_real_is_started(void);

// Input/Output
NETHACK_EXPORT const char* nethack_real_get_output(void);
NETHACK_EXPORT void nethack_real_send_input(const char* cmd);
NETHACK_EXPORT void nethack_real_clear_output(void);
NETHACK_EXPORT void ios_queue_input(char ch);  // Queue single character to input system

// Game loop control
NETHACK_EXPORT int nethack_process_command(void);  // Process one command/turn, returns 1 if game continues
NETHACK_EXPORT void nethack_enable_threaded_mode(void);
NETHACK_EXPORT void nethack_run_game_threaded(void);
NETHACK_EXPORT void nethack_send_input_threaded(const char* cmd);
NETHACK_EXPORT void ios_request_game_exit(void);   // Request clean game exit
NETHACK_EXPORT void ios_reset_game_exit(void);     // Reset exit flag for new game
NETHACK_EXPORT int ios_was_exit_requested(void);   // Check if exit was requested
NETHACK_EXPORT void nethack_reset_memory(void);    // Full memory wipe (memset) for new game - prevents header corruption
NETHACK_EXPORT bool nethack_is_snapshot_loaded(void);  // Check if we're resuming from snapshot (skip reset)

// Game state functions
NETHACK_EXPORT long nethack_get_turn_count(void);  // Get current turn/move counter

// Map functions
NETHACK_EXPORT const char* nethack_get_map(void);
NETHACK_EXPORT int nethack_move_player(int dx, int dy);
NETHACK_EXPORT void nethack_init_dungeon(void);

// Travel and examination functions
NETHACK_EXPORT void nethack_travel_to(int x, int y);  // Travel to specific coordinates
NETHACK_EXPORT int nethack_is_traveling(void);        // Check if travel is in progress (1=yes, 0=no)
NETHACK_EXPORT const char* nethack_examine_tile(int x, int y);  // Look at specific tile (returns description)
NETHACK_EXPORT void nethack_kick_door(int x, int y);  // Kick in direction of tile
NETHACK_EXPORT void nethack_open_door(int x, int y);  // Open door in direction of tile
NETHACK_EXPORT void nethack_close_door(int x, int y);  // Close door in direction of tile
NETHACK_EXPORT void nethack_fire_quiver(int x, int y);  // Fire quiver in direction of tile
NETHACK_EXPORT void nethack_throw_item(int x, int y);  // Throw item in direction of tile
NETHACK_EXPORT void nethack_unlock_door(int x, int y);  // Unlock door in direction of tile
NETHACK_EXPORT void nethack_lock_door(int x, int y);  // Lock door in direction of tile

// Autotravel functions - find and travel to interesting locations
NETHACK_EXPORT int nethack_travel_to_stairs_up(void);     // Travel to upward stairs
NETHACK_EXPORT int nethack_travel_to_stairs_down(void);   // Travel to downward stairs
NETHACK_EXPORT int nethack_travel_to_altar(void);         // Travel to nearest visible altar
NETHACK_EXPORT int nethack_travel_to_fountain(void);      // Travel to nearest visible fountain

// Engraving functions (Phase 1: Quick phrases for combat)
NETHACK_EXPORT bool nethack_can_engrave(void);  // Check if player can engrave at current location
NETHACK_EXPORT const char* nethack_get_engraving_at_player(void);  // Get engraving text at player position (NULL if none)
NETHACK_EXPORT bool nethack_quick_engrave(const char* text);  // Quick engrave with finger (sends E → - → text → \n)
NETHACK_EXPORT bool nethack_engrave_with_tool(const char* text, char tool_invlet);  // Engrave with specific tool

// Character creation functions
NETHACK_EXPORT int nethack_get_available_roles(void);
NETHACK_EXPORT const char* nethack_get_role_name(int rolenum);
NETHACK_EXPORT int nethack_get_available_races_for_role(int rolenum);
NETHACK_EXPORT const char* nethack_get_race_name(int racenum);
NETHACK_EXPORT int nethack_get_available_genders_for_role(int rolenum);
NETHACK_EXPORT const char* nethack_get_gender_name(int gendnum);
NETHACK_EXPORT int nethack_get_available_alignments_for_role(int rolenum);
NETHACK_EXPORT const char* nethack_get_alignment_name(int alignnum);
NETHACK_EXPORT void nethack_set_role(int rolenum);
NETHACK_EXPORT void nethack_set_race(int racenum);
NETHACK_EXPORT void nethack_set_gender(int gendnum);
NETHACK_EXPORT void nethack_set_alignment(int alignnum);
NETHACK_EXPORT void nethack_set_player_name(const char* name);
NETHACK_EXPORT const char* nethack_get_player_name(void);
NETHACK_EXPORT const char* nethack_get_player_class_name(void);
NETHACK_EXPORT const char* nethack_get_player_race_name(void);
NETHACK_EXPORT int nethack_validate_character_selection(void);
NETHACK_EXPORT void nethack_finalize_character(void);
NETHACK_EXPORT void nethack_start_new_game(void);

// Lua debug logging functions
NETHACK_EXPORT void nethack_append_log(const char* format, ...);
NETHACK_EXPORT const char* nethack_get_lua_logs(void);
NETHACK_EXPORT void nethack_clear_lua_logs(void);

// Convenience macro for Lua logging
#define LUA_LOG(fmt, ...) nethack_append_log("[LUA] " fmt, ##__VA_ARGS__)
#define DLB_LOG(fmt, ...) nethack_append_log("[DLB] " fmt, ##__VA_ARGS__)

// Legacy names for compatibility
#define nethack_init nethack_real_init
#define nethack_get_output nethack_real_get_output
#define nethack_send_input nethack_real_send_input
#define nethack_clear_output nethack_real_clear_output

// Auto-play functions for debugging
NETHACK_EXPORT void ios_enable_autoselect(void);
NETHACK_EXPORT void ios_parse_debug_flags(const char *flagstr);
NETHACK_EXPORT int ios_is_auto_mode(void);
NETHACK_EXPORT void ios_debug_autoplay_status(void);

// Wizard mode functions for iOS debug
NETHACK_EXPORT void ios_enable_wizard_mode(void);   // Request wizard mode (call BEFORE game start)
NETHACK_EXPORT void ios_apply_wizard_mode(void);    // Apply wizard mode (call AFTER game init)
NETHACK_EXPORT int ios_is_wizard_mode(void);        // Check if wizard mode is enabled
NETHACK_EXPORT void ios_spawn_test_scenario(void);  // Spawn test items around player

// Command prefix control
// iflags.menu_requested causes issues with #loot (forces direction query)
// Call this before #loot to ensure it works with floor containers
NETHACK_EXPORT void ios_clear_menu_requested(void);

// Message history functions
NETHACK_EXPORT void nethack_add_message(const char* message, const char* category);
NETHACK_EXPORT void nethack_add_message_with_attrs(const char* message, const char* category, int attr);
NETHACK_EXPORT const char* nethack_get_message_history(void);  // Returns JSON array of recent messages
NETHACK_EXPORT int nethack_get_message_count(void);
NETHACK_EXPORT void nethack_clear_message_history(void);

// Save/Load functions
NETHACK_EXPORT int nethack_save_game(const char* filepath);
NETHACK_EXPORT int nethack_load_game_new(const char* filepath);  // Working implementation with ios_restore
NETHACK_EXPORT int nethack_can_save(void);

// Direct save functions (iOS-specific)
NETHACK_EXPORT int ios_direct_save_game(void);  // Save without keyboard input
NETHACK_EXPORT int ios_save_and_exit(void);     // Save and terminate game
NETHACK_EXPORT const char* nethack_get_save_info(void);
NETHACK_EXPORT const char* nethack_list_saves(void);

// Snapshot functions
NETHACK_EXPORT int nethack_save_snapshot(const char* filepath);
NETHACK_EXPORT int nethack_load_snapshot(const char* filepath);

// Restore/Load functions (iOS-specific)
NETHACK_EXPORT int ios_load_saved_game(void);   // Load a saved game, extracts level files
NETHACK_EXPORT int ios_restore_saved_game(void); // Internal restore function
NETHACK_EXPORT const char* ios_get_save_info(void); // Get save info without loading

// Live save functions (non-destructive save)
NETHACK_EXPORT int nethack_live_save(void);     // Save without terminating or freeing memory
NETHACK_EXPORT int ios_can_live_save(void);     // Check if live save is possible

// Save intercept functions
NETHACK_EXPORT int ios_is_save_intercepted(void);
NETHACK_EXPORT void ios_reset_save_intercept(void);

// iOS file system functions
NETHACK_EXPORT void ios_init_file_prefixes(void);
NETHACK_EXPORT void ios_init_savedir(void);
NETHACK_EXPORT int ios_savefile_exists(const char* filename);
NETHACK_EXPORT int ios_delete_savefile(const char* filename);

// YN Callback functions for Swift
NETHACK_EXPORT void nethack_set_yn_auto_yes(void);
NETHACK_EXPORT void nethack_set_yn_auto_no(void);
NETHACK_EXPORT void nethack_set_yn_ask_user(void);
NETHACK_EXPORT void nethack_set_yn_default(void);
NETHACK_EXPORT void nethack_set_next_yn_response(char response);

// Game state getters for metadata
NETHACK_EXPORT int nethack_get_player_level(void);
NETHACK_EXPORT long nethack_get_player_gold(void);
NETHACK_EXPORT int nethack_get_dungeon_level(void);
NETHACK_EXPORT const char* nethack_get_location_name(void);
NETHACK_EXPORT long nethack_get_play_time(void);

// Player stats functions (comprehensive)
NETHACK_EXPORT const char* nethack_get_player_stats_json(void);
NETHACK_EXPORT int nethack_get_player_hp(void);
NETHACK_EXPORT int nethack_get_player_hp_max(void);
NETHACK_EXPORT int nethack_get_player_power(void);
NETHACK_EXPORT int nethack_get_player_power_max(void);
NETHACK_EXPORT long nethack_get_player_exp(void);
NETHACK_EXPORT int nethack_get_player_ac(void);
NETHACK_EXPORT int nethack_get_player_str(void);
NETHACK_EXPORT int nethack_get_player_dex(void);
NETHACK_EXPORT int nethack_get_player_con(void);
NETHACK_EXPORT int nethack_get_player_int(void);
NETHACK_EXPORT int nethack_get_player_wis(void);
NETHACK_EXPORT int nethack_get_player_cha(void);

// Test helper functions
NETHACK_EXPORT const char* nethack_get_savef(void);
NETHACK_EXPORT void nethack_cleanup_game(void);

// State reset functions - CRITICAL for multiple game sessions
NETHACK_EXPORT void ios_reset_all_static_state(void);  // Reset ALL static variables in ios_winprocs.c

// Game lifecycle functions - CRITICAL for multiple game sessions in same process
NETHACK_EXPORT void ios_shutdown_game(void);      // Orderly shutdown: freedynamicdata → dlb_cleanup → l_nhcore_done
NETHACK_EXPORT void ios_wipe_memory(void);        // Memory wipe: nh_restart() - ONLY safe after shutdown!
NETHACK_EXPORT void ios_reinit_subsystems(void);  // Re-initialize: dlb_init → l_nhcore_init → ios_reset_all_static_state

// Complete save/restore system - atomic save with proper NetHack integration
NETHACK_EXPORT int ios_save_complete(const char* save_dir);     // Complete save (game state only, no memory.dat)
NETHACK_EXPORT int ios_restore_complete(const char* save_dir);  // Complete restore with proper initialization
NETHACK_EXPORT int ios_quicksave(void);                         // Quick save to iOS Documents/save
NETHACK_EXPORT int ios_quickrestore(void);                      // Quick restore from iOS Documents/save
NETHACK_EXPORT int ios_save_exists(void);                       // Check if save file exists

// Map dimension control (dynamic sizing)
NETHACK_EXPORT void ios_set_map_dimensions(int width, int height);

// Symbol customization for iOS (better mobile visibility)
NETHACK_EXPORT void ios_setup_default_symbols(void);  // Changes boulder from ` to 0 and refreshes cache

// Death information structure
typedef struct {
    char death_message[512];
    char possessions[8192];
    char attributes[8192];
    char conduct[8192];
    char dungeon_overview[8192];
    int final_level;
    int final_hp;
    int final_maxhp;
    long final_gold;
    long final_score;
    long final_turns;
    int dungeon_level;
    char role_name[64];
    char death_reason[256];
} DeathInfo;

// Get death information after player dies
NETHACK_EXPORT const DeathInfo* nethack_get_death_info(void);
NETHACK_EXPORT int nethack_is_player_dead(void);
NETHACK_EXPORT void nethack_clear_death_info(void);

// Death info accessors - avoid C struct access in Swift completely
NETHACK_EXPORT const char* nethack_get_death_message(void);
NETHACK_EXPORT const char* nethack_get_death_possessions(void);
NETHACK_EXPORT const char* nethack_get_death_attributes(void);
NETHACK_EXPORT const char* nethack_get_death_conduct(void);
NETHACK_EXPORT const char* nethack_get_death_dungeon_overview(void);
NETHACK_EXPORT const char* nethack_get_death_role_name(void);
NETHACK_EXPORT const char* nethack_get_death_reason(void);
NETHACK_EXPORT int nethack_get_death_final_level(void);
NETHACK_EXPORT int nethack_get_death_final_hp(void);
NETHACK_EXPORT int nethack_get_death_final_maxhp(void);
NETHACK_EXPORT long nethack_get_death_final_gold(void);
NETHACK_EXPORT long nethack_get_death_final_score(void);
NETHACK_EXPORT long nethack_get_death_final_turns(void);
NETHACK_EXPORT int nethack_get_death_dungeon_level(void);

// Vanquished monsters API - for death screen kill statistics
NETHACK_EXPORT int ios_get_total_kills(void);           // Total monsters killed
NETHACK_EXPORT int ios_get_unique_kills_count(void);    // Number of unique monster types killed
NETHACK_EXPORT int ios_get_monster_kills(int mndx);     // Kill count for specific monster type
NETHACK_EXPORT const char* ios_get_monster_name(int mndx); // Get monster name by index
NETHACK_EXPORT int ios_get_top_kills(int* indices, int* counts, int max_results); // Top N kills

// Generic yn_function response system
typedef struct {
    const char* query;        // The question being asked
    const char* responses;    // Valid responses (e.g. "ynq")
    char default_response;     // Default if user hits enter
    char user_response;        // What the user selected
    char captured_output[8192]; // Output captured after answering
} YNContext;

// Callback for yn_function - return the character to respond with
typedef char (*YNResponseCallback)(const YNContext* context);

// Register a callback to handle yn_function prompts
NETHACK_EXPORT void nethack_register_yn_callback(YNResponseCallback callback);
NETHACK_EXPORT void nethack_unregister_yn_callback(void);

// Get the current yn context (for debugging)
NETHACK_EXPORT const YNContext* nethack_get_current_yn_context(void);

// =============================================================================
// MENU CALLBACK SYSTEM (C -> Swift menu display)
// =============================================================================

// Menu pick modes (matches NetHack's PICK_* constants)
#define IOS_PICK_NONE 0  // Display only, no selection
#define IOS_PICK_ONE  1  // Select exactly one item
#define IOS_PICK_ANY  2  // Multi-select

// Maximum items in a menu
#define IOS_MAX_MENU_ITEMS 256
#define IOS_MAX_MENU_TEXT  256

// Menu item structure for passing to Swift
typedef struct {
    char selector;              // Selection character ('a'-'z', 'A'-'Z', or 0)
    int glyph;                  // Glyph ID for icon display
    char text[IOS_MAX_MENU_TEXT];  // Display text (copied, not pointer)
    int attributes;             // ATR_* attributes (bold, dim, etc.)
    int identifier;             // NetHack's internal identifier (a_int from ANY_P)
    unsigned int itemflags;     // MENU_ITEMFLAGS_* from NetHack
} IOSMenuItem;

// Menu context for callback
// NOTE: item_count and window_id come BEFORE items array for easier Swift parsing
typedef struct {
    int how;                              // PICK_NONE/PICK_ONE/PICK_ANY
    char prompt[IOS_MAX_MENU_TEXT];       // Menu title/prompt
    int item_count;                        // Number of items
    int window_id;                         // NetHack window ID
    IOSMenuItem items[IOS_MAX_MENU_ITEMS]; // Menu items (at end for variable access)
} IOSMenuContext;

// Menu selection result from Swift
typedef struct {
    int item_index;    // Index into items array
    int count;         // Selection count (-1 = all, 0 = cancelled, >0 = count)
} IOSMenuSelection;

// Callback type: Swift provides this function
// Parameters: context (menu data), selections (output array), max_selections (array size)
// Returns: number of selections made, 0 = cancel, -1 = error
typedef int (*IOSMenuCallback)(const IOSMenuContext* context,
                                IOSMenuSelection* selections,
                                int max_selections);

// Register callback from Swift to display menus
NETHACK_EXPORT void ios_register_menu_callback(IOSMenuCallback callback);
NETHACK_EXPORT void ios_unregister_menu_callback(void);

// Check if menu callback is registered
NETHACK_EXPORT bool ios_has_menu_callback(void);

// Send menu response from Swift back to C (for async flow)
// Called by Swift after user makes selection
NETHACK_EXPORT void ios_menu_response(IOSMenuSelection* selections, int count);

// =============================================================================
// INVENTORY SYSTEM
// =============================================================================

// Inventory item structure - real NetHack inventory data
typedef struct {
    char invlet;              // Inventory letter (a-z, A-Z)
    char *name;               // Full item name from doname() - MUST free() after use!
    int quantity;             // Stack quantity
    char buc_status;          // 'B'=blessed, 'U'=uncursed, 'C'=cursed, '?'=unknown
    bool buc_known;           // Is BUC status known to player?
    int enchantment;          // +/- enchantment value (e.g., +1, -2)
    bool is_equipped;         // Is item worn/wielded?
    char equipped_slot[16];   // "wielded", "worn", "left ring", etc.
    char oclass;              // Object class (weapon/armor/potion/etc.)
    bool is_container;        // Is this item a container (bag, box)?
} InventoryItem;

// Get count of items in player inventory
NETHACK_EXPORT int nethack_get_inventory_count(void);

// Fill array with inventory items
// Returns actual count filled (may be less than max_items)
// IMPORTANT: Caller must call nethack_free_inventory_items() to free allocated names!
NETHACK_EXPORT int nethack_get_inventory_items(InventoryItem *items, int max_items);

// Free allocated memory in inventory items (frees name strings)
NETHACK_EXPORT void nethack_free_inventory_items(InventoryItem *items, int count);

// =============================================================================
// CONTAINER SYSTEM
// =============================================================================

// Container item info structure - for retrieving container contents
typedef struct {
    char invlet;              // Inventory letter (may be 0 if not in inventory)
    char name[256];           // Short name from xname() - BUFSZ compatible
    char fullname[256];       // Full name from doname() - BUFSZ compatible
    int quantity;             // Stack quantity
    int weight;               // Weight in aum
    bool is_container;        // Is this item also a container?
    bool is_equipped;         // Is item worn/wielded?
    char buc_status;          // 'B'=blessed, 'U'=uncursed, 'C'=cursed, '?'=unknown
} ios_item_info;

// Container detection
NETHACK_EXPORT bool ios_is_container(struct obj *obj);
NETHACK_EXPORT int ios_get_container_item_count(struct obj *container);
NETHACK_EXPORT bool ios_container_is_locked(struct obj *container);
NETHACK_EXPORT bool ios_container_is_trapped(struct obj *container);
NETHACK_EXPORT bool ios_container_contents_known(struct obj *container);

// Container contents retrieval
// Returns count of items, allocates array via malloc
// MUST call ios_free_container_contents() to free memory!
NETHACK_EXPORT int ios_get_container_contents(struct obj *container, ios_item_info **items_out);
NETHACK_EXPORT void ios_free_container_contents(ios_item_info *items, int count);

// Item naming functions (thread-safe with immediate copy)
NETHACK_EXPORT const char* ios_get_item_fullname(struct obj *obj);
NETHACK_EXPORT const char* ios_get_item_shortname(struct obj *obj);

// =============================================================================
// FLOOR CONTAINER OPERATIONS (ios_container_bridge.c)
// =============================================================================

// Floor container info structure - for listing containers at player position
typedef struct {
    unsigned int o_id;      // Unique object ID (for selection)
    char name[256];         // Container name from doname() (copied!)
    int item_count;         // Number of items inside
    bool is_locked;         // Container is locked
    bool is_broken;         // Container is broken (kicked/forced open)
    bool is_trapped;        // Container is trapped (if known)
} IOSFloorContainerInfo;

// Container item info structure - for listing items in current container
typedef struct {
    unsigned int o_id;      // Unique object ID
    char name[256];         // Item name from doname() (copied!)
    int index;              // Index in container (for take operations)
    long quantity;          // Stack quantity
    int weight;             // Weight in aum
    char buc_status;        // 'B'=blessed, 'U'=uncursed, 'C'=cursed, '?'=unknown
    bool is_container;      // Is this item also a container?
} IOSContainerItemInfo;

// Get all floor containers at player position
// Returns count, fills buffer with container info
NETHACK_EXPORT int ios_get_floor_containers_at_player(IOSFloorContainerInfo *buffer, int max);

// Set current container by o_id (required before put/take operations)
// Returns: 1 = success, 0 = failed (not found or locked)
NETHACK_EXPORT int ios_set_current_container(unsigned int container_o_id);

// Put item from inventory into current container
// invlet = inventory letter (a-z, A-Z)
// Returns: 1 = success, 0 = failed, -1 = BoH explosion
NETHACK_EXPORT int ios_put_item_in_container(char invlet);

// Take item from current container to inventory
// item_index = index in container's cobj chain
// Returns: 1 = success, 0 = failed
NETHACK_EXPORT int ios_take_item_from_container(int item_index);

// Take all items from current container
// Returns: count of items taken
NETHACK_EXPORT int ios_take_all_from_container(void);

// Clear current container (call when closing UI)
NETHACK_EXPORT void ios_clear_current_container(void);

// Get items from current container
// Returns: count of items written to buffer
NETHACK_EXPORT int ios_get_container_contents_info(IOSContainerItemInfo *buffer, int max);

// Item details structure - comprehensive item information
typedef struct {
    char fullname[256];       // Full description from doname()
    char shortname[256];      // Short name from xname()

    // BUC status
    signed char buc_status;   // -1=cursed, 0=uncursed, 1=blessed
    bool buc_known;           // Is BUC status known?

    // Numeric properties
    short enchantment;        // +/- enchantment (spe for weapons/armor)
    short charges;            // Charges remaining (spe for wands/tools)
    long quantity;            // Stack quantity
    int weight;               // Weight in aum

    // Type-specific properties
    int damage_dice;          // Weapon damage dice (0 if not weapon)
    int damage_sides;         // Weapon damage sides
    int armor_class;          // Armor AC value (0 if not armor)
    int nutrition;            // Food nutrition value (0 if not food)

    // Special properties
    bool is_artifact;         // Is this an artifact?
    char artifact_name[64];   // Artifact name if applicable
    bool is_erodeproof;       // Rustproof/fixed status

    // Equipment status
    bool is_equipped;         // Worn/wielded
    char equipped_slot[32];   // "wielded", "worn", etc.

    // Container properties
    bool is_container;        // Is this a container?
    int container_item_count; // Items inside (if container)
    bool container_locked;    // Is container locked?
    bool container_trapped;   // Is container trapped?
} ios_item_details;

// Get comprehensive item details
NETHACK_EXPORT void ios_get_item_details(struct obj *obj, ios_item_details *out);

// =============================================================================
// CONTAINER OPERATIONS
// =============================================================================

// Get inventory item by invlet character (for drag-and-drop operations)
// Returns NULL if item not found or game not started
NETHACK_EXPORT struct obj* ios_get_inventory_item_by_invlet(char invlet);

// Validate if item can be placed in container (checks BoH->BoH explosion risk)
// Returns true if safe to contain, false if dangerous (will explode)
NETHACK_EXPORT bool ios_can_contain(struct obj *container, struct obj *item);

// =============================================================================
// EVENT-DRIVEN API (non-blocking, SwiftUI integration)
// =============================================================================
// This is the PROPER way to integrate with iOS - no threads, no blocking
// NetHack runs one command at a time from the UI thread

// State machine for event-driven operation
typedef enum {
    NETHACK_STATE_IDLE,           // Waiting for input
    NETHACK_STATE_PROCESSING,     // Processing a command
    NETHACK_STATE_NEEDS_INPUT,    // Needs user input (menu, prompt, etc)
    NETHACK_STATE_GAME_OVER       // Game ended
} NetHackState;

// Initialize NetHack for event-driven operation (called once at app start)
NETHACK_EXPORT int ios_nethack_init_event_driven(void);

// Start a new game (returns immediately after setup)
NETHACK_EXPORT int ios_nethack_start_game(void);

// Process one input character (called from SwiftUI when user taps/types)
// Returns immediately after processing
NETHACK_EXPORT int ios_nethack_process_input(char ch);

// Process pending NetHack events (called from SwiftUI timer, 60Hz or as needed)
// Non-blocking - returns immediately
NETHACK_EXPORT int ios_nethack_tick(void);

// Get current game state for SwiftUI
NetHackState ios_nethack_get_state(void);

// Save game (synchronous, returns when complete)
NETHACK_EXPORT int ios_nethack_save(const char* filepath);

// Load game (synchronous, returns when complete)
NETHACK_EXPORT int ios_nethack_load(const char* filepath);

// Clean shutdown
NETHACK_EXPORT void ios_nethack_cleanup(void);

// =============================================================================
// RENDER QUEUE API (Phase 2 - Swift Consumer)
// =============================================================================

// Access to global render queue for Swift
#include "ios_render_queue.h"
extern RenderQueue *g_render_queue;

// Queue operations exposed to Swift
NETHACK_EXPORT bool render_queue_dequeue(RenderQueue *queue, RenderQueueElement *elem);
NETHACK_EXPORT bool render_queue_is_empty(const RenderQueue *queue);

// =============================================================================
// DISCOVERIES SYSTEM (expose NetHack's discovery tracking)
// =============================================================================

// Forward declaration for objclass (NetHack's object class structure)
struct objclass;

// Get total number of object types in NetHack
NETHACK_EXPORT int ios_get_num_objects(void);

// Get object class definition by type ID (otyp)
// Returns NULL if otyp is out of bounds
// Pointer is to NetHack's internal objects[] array - DO NOT free!
NETHACK_EXPORT struct objclass* ios_get_object_class(int otyp);

// Check if an object type has been discovered by the player
// Returns false if otyp is out of bounds
NETHACK_EXPORT bool ios_is_object_discovered(int otyp);

// Get object properties individually (since struct isn't visible to Swift)
NETHACK_EXPORT const char* ios_get_object_name(int otyp);
NETHACK_EXPORT const char* ios_get_object_description(int otyp);
NETHACK_EXPORT signed char ios_get_object_class_char(int otyp);
NETHACK_EXPORT bool ios_is_object_encountered(int otyp);
NETHACK_EXPORT bool ios_is_object_unique(int otyp);
NETHACK_EXPORT bool ios_has_user_name(int otyp);

// =============================================================================
// SPELL SYSTEM (expose NetHack's spell book for iOS UI)
// =============================================================================

// Constants for spell direction types
#define IOS_SPELL_DIR_UNKNOWN   0
#define IOS_SPELL_DIR_NODIR     1  // Self-cast, no direction needed
#define IOS_SPELL_DIR_IMMEDIATE 2  // Directional, hits first target
#define IOS_SPELL_DIR_RAY       3  // Directional, bounces off walls

// Spell information structure - comprehensive spell data for iOS UI
typedef struct {
    int index;              // spl_book index (0-51)
    char letter;            // 'a'-'z', 'A'-'Z' menu letter
    char name[64];          // Spell name (e.g., "force bolt")
    int level;              // Spell level (1-7)
    int power_cost;         // Power cost (level * 5)
    int success_rate;       // Success rate 0-100%
    int retention;          // Retention 0-100% (sp_know / KEEN * 100)
    int direction_type;     // IOS_SPELL_DIR_* constant
    char skill_type[32];    // "attack", "healing", "divination", etc.
} SpellInfo;

// Get count of known spells
// Returns 0 if game not started or player knows no spells
NETHACK_EXPORT int ios_get_spell_count(void);

// Fill array with spell data
// Returns actual count filled (may be less than max_spells)
// Caller provides array, function fills it with spell information
NETHACK_EXPORT int ios_get_spells(SpellInfo *spells, int max_spells);

// Get success rate for a specific spell (by spl_book index)
// Returns 0-100, or -1 if invalid index or game not started
NETHACK_EXPORT int ios_get_spell_success_rate(int spell_index);

// Get retention for a specific spell (by spl_book index)
// Returns 0-100, or -1 if invalid index or game not started
NETHACK_EXPORT int ios_get_spell_retention(int spell_index);

// =============================================================================
// INTRINSICS SYSTEM (expose player resistances and abilities)
// =============================================================================

// Intrinsics structure - player resistances and special abilities
typedef struct {
    // Resistances (boolean flags)
    bool fire_resistance;
    bool cold_resistance;
    bool sleep_resistance;
    bool disintegration_resistance;
    bool shock_resistance;
    bool poison_resistance;
    bool drain_resistance;
    bool magic_resistance;
    bool acid_resistance;
    bool stone_resistance;
    bool sick_resistance;

    // Vision abilities
    bool see_invisible;
    bool telepathy;
    bool infravision;
    bool warning;
    bool searching;

    // Movement abilities
    bool levitation;
    bool flying;
    bool swimming;
    bool magical_breathing;
    bool passes_walls;
    bool slow_digestion;
    bool regeneration;
    bool teleportation;
    bool teleport_control;
    bool polymorph;
    bool polymorph_control;

    // Combat abilities
    bool stealth;
    bool aggravate_monster;
    bool conflict;
    bool protection;
    bool reflection;
    bool free_action;

    // Status conditions (negative)
    bool hallucinating;
    bool confused;
    bool stunned;
    bool blinded;
    bool deaf;
    bool sick;
    bool stoned;
    bool strangled;
    bool slimed;
    bool wounded_legs;
    bool fumbling;
} PlayerIntrinsics;

// Get all player intrinsics in one call
NETHACK_EXPORT void ios_get_player_intrinsics(PlayerIntrinsics *out);

// Individual intrinsic checks (if needed)
NETHACK_EXPORT bool ios_has_fire_resistance(void);
NETHACK_EXPORT bool ios_has_cold_resistance(void);
NETHACK_EXPORT bool ios_has_poison_resistance(void);
NETHACK_EXPORT bool ios_has_see_invisible(void);
NETHACK_EXPORT bool ios_has_telepathy(void);

// =============================================================================
// MONSTER INFO SYSTEM (expose visible monsters)
// =============================================================================

// Monster info structure for a single visible monster
typedef struct {
    int x, y;               // Position
    char symbol;            // Display symbol
    char name[64];          // Monster name
    int current_hp;         // Current HP (-1 if unknown)
    int max_hp;             // Max HP (-1 if unknown)
    int level;              // Monster level
    bool is_pet;            // Is this a pet?
    bool is_peaceful;       // Is this monster peaceful?
    bool is_hostile;        // Is this monster hostile?
    bool is_invisible;      // Is invisible (detected by other means)
    bool is_fleeing;        // Is fleeing
    bool is_sleeping;       // Is sleeping
    bool is_stunned;        // Is stunned
    bool is_confused;       // Is confused
} MonsterInfo;

// Get count of visible monsters on current level
NETHACK_EXPORT int ios_get_visible_monster_count(void);

// Get info for all visible monsters
// Returns actual count filled (may be less than max_monsters)
NETHACK_EXPORT int ios_get_visible_monsters(MonsterInfo *monsters, int max_monsters);

// Get info for monster at specific coordinates (returns false if no monster)
NETHACK_EXPORT bool ios_get_monster_at(int x, int y, MonsterInfo *out);

// =============================================================================
// DUNGEON OVERVIEW SYSTEM (expose visited dungeon levels)
// =============================================================================

// Special location flags bitmask
#define DUNGEON_FLAG_ORACLE         (1 << 0)
#define DUNGEON_FLAG_SOKOBAN_SOLVED (1 << 1)
#define DUNGEON_FLAG_BIGROOM        (1 << 2)
#define DUNGEON_FLAG_CASTLE         (1 << 3)
#define DUNGEON_FLAG_VALLEY         (1 << 4)
#define DUNGEON_FLAG_SANCTUM        (1 << 5)
#define DUNGEON_FLAG_LUDIOS         (1 << 6)
#define DUNGEON_FLAG_ROGUE          (1 << 7)
#define DUNGEON_FLAG_VIB_SQUARE     (1 << 8)
#define DUNGEON_FLAG_QUEST_HOME     (1 << 9)
#define DUNGEON_FLAG_QUEST_SUMMONS  (1 << 10)
#define DUNGEON_FLAG_MINETOWN       (1 << 11)

// Branch types
#define BRANCH_TYPE_NONE       0
#define BRANCH_TYPE_STAIRS_UP  1
#define BRANCH_TYPE_STAIRS_DOWN 2
#define BRANCH_TYPE_PORTAL     3

// Dungeon level info structure - comprehensive level data for iOS UI
typedef struct {
    int dnum;                   // Dungeon number (0 = main dungeon)
    int dlevel;                 // Level within dungeon
    char dungeon_name[64];      // "The Dungeons of Doom", "The Gnomish Mines", etc.
    int depth;                  // Absolute depth from surface

    // Features (counts, 0-3 each due to 2-bit storage)
    int shops;
    int temples;
    int altars;
    int fountains;
    int thrones;
    int graves;
    int sinks;
    int trees;
    int shop_type;              // Shop type if single shop

    // Special location flags (bitmask of DUNGEON_FLAG_* values)
    unsigned int special_flags;

    // Player annotation (custom note)
    char annotation[128];

    // Branch connection info
    char branch_to[64];         // Name of connected dungeon branch
    int branch_type;            // BRANCH_TYPE_* constant

    // State
    int is_current_level;       // Player is currently here
    int is_forgotten;           // Level has been forgotten (amnesia)
    int has_bones;              // Known bones on this level
} DungeonLevelInfo;

// Refresh dungeon overview data (calls recalc_mapseen internally)
NETHACK_EXPORT void ios_refresh_dungeon_overview(void);

// Get total count of visited dungeon levels
NETHACK_EXPORT int ios_get_visited_level_count(void);

// Get dungeon level info by index
// Index is 0-based, up to ios_get_visited_level_count() - 1
// Returns false if index out of bounds
NETHACK_EXPORT bool ios_get_dungeon_level_info(int index, DungeonLevelInfo *out);

// Get count of distinct dungeons visited
NETHACK_EXPORT int ios_get_dungeon_count(void);

// Get dungeon name by dungeon number
NETHACK_EXPORT const char* ios_get_dungeon_name(int dnum);

// Get depth range for a dungeon (returns false if dnum invalid)
NETHACK_EXPORT bool ios_get_dungeon_depth_range(int dnum, int *min_depth, int *max_depth);

// Get current dungeon environment for visual theming
NETHACK_EXPORT DungeonEnvironmentType ios_get_current_environment(void);

// =============================================================================
// SKILL/ENHANCE SYSTEM (expose NetHack's weapon skill system)
// =============================================================================

// Skill levels (from skills.h)
#define IOS_SKILL_RESTRICTED   0  // Can't advance
#define IOS_SKILL_UNSKILLED    1  // Can be advanced
#define IOS_SKILL_BASIC        2
#define IOS_SKILL_SKILLED      3
#define IOS_SKILL_EXPERT       4
#define IOS_SKILL_MASTER       5  // Martial arts only
#define IOS_SKILL_GRAND_MASTER 6  // Martial arts only

// Skill categories
#define IOS_SKILL_CATEGORY_WEAPON   0
#define IOS_SKILL_CATEGORY_SPELL    1
#define IOS_SKILL_CATEGORY_FIGHTING 2

// Total number of skills in NetHack (P_NUM_SKILLS)
#define IOS_NUM_SKILLS 38

// Skill information structure - comprehensive skill data for iOS UI
typedef struct {
    int skill_id;           // 0-37 (P_DAGGER through P_RIDING)
    char name[64];          // Skill name (e.g., "dagger", "attack spells")
    int current_level;      // 0-6 (IOS_SKILL_*)
    int max_level;          // Maximum achievable level for this character
    int practice_points;    // Current practice points accumulated
    int points_needed;      // Points needed for next level advancement
    int can_advance;        // 1 if can advance now (has points AND slots)
    int could_advance;      // 1 if could advance with more slots (has points, needs slots)
    int is_peaked;          // 1 if at maximum already (no more advancement possible)
    int slots_required;     // Weapon slots required to advance to next level
    int category;           // IOS_SKILL_CATEGORY_* constant
    char level_name[32];    // Human-readable level name ("Unskilled", "Expert", etc.)
} ios_skill_info_t;

// Get total available skill slots
// Returns u.weapon_slots (remaining slots to spend on skill advancement)
NETHACK_EXPORT int ios_get_available_skill_slots(void);

// Get count of non-restricted skills
// Returns count of skills player can potentially train
NETHACK_EXPORT int ios_get_skill_count(void);

// Get skill info at index (iterates through non-restricted skills only)
// index: 0 to ios_get_skill_count()-1
// out: pointer to ios_skill_info_t to fill
// Returns: 1 on success, 0 on failure (invalid index, game not started)
NETHACK_EXPORT int ios_get_skill_info(int index, ios_skill_info_t *out);

// Get all non-restricted skills in one call
// out: pre-allocated array of ios_skill_info_t (should be IOS_NUM_SKILLS size)
// count: pointer to int, filled with actual count
// Returns: actual number of skills filled
NETHACK_EXPORT int ios_get_all_skills(ios_skill_info_t *out, int *count);

// Get skill info by skill ID (0-37)
// skill_id: specific skill ID (P_DAGGER=1, P_RIDING=37, etc.)
// out: pointer to ios_skill_info_t to fill
// Returns: 1 on success, 0 on failure (restricted skill, invalid ID, game not started)
NETHACK_EXPORT int ios_get_skill_by_id(int skill_id, ios_skill_info_t *out);

// Advance a skill (spend skill slot to increase level)
// skill_id: skill ID to advance (0-37)
// Returns: 1 on success, 0 on failure (can't advance, not enough slots, etc.)
NETHACK_EXPORT int ios_advance_skill(int skill_id);

// Get count of skills that can be advanced RIGHT NOW
// Returns: count of skills with can_advance == 1
NETHACK_EXPORT int ios_get_advanceable_skill_count(void);

// Get skill level name string
// level: skill level (0-6)
// Returns: static string ("Restricted", "Unskilled", "Basic", etc.)
NETHACK_EXPORT const char* ios_get_skill_level_name(int level);

// =============================================================================
// AUTOPICKUP SYSTEM (user preference control from Swift)
// =============================================================================

// Set autopickup enabled state
// enabled: 1 = on, 0 = off
NETHACK_EXPORT void ios_set_autopickup_enabled(int enabled);

// Set autopickup item types
// types: String of object class symbols (e.g., "$\"?!/=(+" for gold, amulets, scrolls, etc.)
// Empty string = pickup nothing, even if enabled
NETHACK_EXPORT void ios_set_autopickup_types(const char* types);

// Get current autopickup types string (for debugging)
NETHACK_EXPORT const char* ios_get_autopickup_types(void);

// Check if autopickup is enabled
NETHACK_EXPORT int ios_is_autopickup_enabled(void);

#endif /* REAL_NETHACK_BRIDGE_H */