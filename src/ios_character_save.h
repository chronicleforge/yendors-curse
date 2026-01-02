/*
 * ios_character_save.h - SIMPLIFIED character-based save system for NetHack iOS
 *
 * ONE save per character. No slots. Simple.
 *
 * Architecture:
 *   /Documents/NetHack/characters/
 *     hero_name/
 *       savegame        # NetHack save file
 *       metadata.json   # Save metadata
 *     wizard_joe/
 *       savegame
 *       metadata.json
 */

#ifndef IOS_CHARACTER_SAVE_H
#define IOS_CHARACTER_SAVE_H

#include "nethack_export.h"

/* Save current game for a character */
NETHACK_EXPORT int ios_save_character(const char* character_name);

/* Load game for a character */
NETHACK_EXPORT int ios_load_character(const char* character_name);

/* Check if a character has a save */
NETHACK_EXPORT int ios_character_save_exists(const char* character_name);

/* Delete a character's save */
NETHACK_EXPORT int ios_delete_character_save(const char* character_name);

/* List all characters with saves */
NETHACK_EXPORT char** ios_list_saved_characters(int *count);

/* Get metadata path for a character's save */
NETHACK_EXPORT int ios_get_character_metadata_path(const char* character_name, char *path, size_t path_size);

#endif /* IOS_CHARACTER_SAVE_H */
