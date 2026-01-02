/*
 * ios_slot_manager.h - Character-based multi-slot save system API
 *
 * Architecture: Each character has up to 3 slots
 *   /Documents/NetHack/characters/
 *     hero_name/
 *       slot_00001/
 *         savegame
 *         metadata.json
 *         map_snapshot.jpg
 */

#ifndef IOS_SLOT_MANAGER_H
#define IOS_SLOT_MANAGER_H

/*
 * Character Management Functions
 */

// Check if a character exists
int ios_character_exists(const char* character_name);

// List all characters - returns array of character names (caller must free array AND strings!)
// count: output parameter for number of characters found
char** ios_list_characters(int *count);

// Delete an entire character (all slots)
int ios_delete_character(const char* character_name);

/*
 * Slot Management Functions (per character)
 */

// Create a new slot for a character - returns slot_id or -1 on failure
// Enforces MAX_SLOTS (3) per character
int ios_create_slot(const char* character_name);

// Check if a slot exists for a character
int ios_slot_exists(const char* character_name, int slot_id);

// Save current game to a slot
int ios_save_to_slot(const char* character_name, int slot_id);

// Load game from a slot
int ios_load_from_slot(const char* character_name, int slot_id);

// Delete a slot
int ios_delete_slot(const char* character_name, int slot_id);

// List all available slots for a character - returns array of slot IDs (caller must free)
// count: output parameter for number of slots found
int* ios_list_slots(const char* character_name, int *count);

/*
 * Active Character/Slot Tracking
 */

// Get currently active character name (returns NULL if none)
const char* ios_get_active_character(void);

// Get currently active slot ID
int ios_get_active_slot(void);

// Set active character and slot
void ios_set_active_slot(const char* character_name, int slot_id);

/*
 * Metadata/Path Helpers
 */

// Get slot metadata.json path
int ios_get_slot_metadata_path(const char* character_name, int slot_id, char *path, size_t path_size);

#endif /* IOS_SLOT_MANAGER_H */
