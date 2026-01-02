/*
 * ios_character_status.h - Character Status Bridge Functions
 *
 * Provides comprehensive character status information to iOS UI.
 */

#ifndef IOS_CHARACTER_STATUS_H
#define IOS_CHARACTER_STATUS_H

#include "RealNetHackBridge.h"

/* Equipment slot indices */
#define IOS_SLOT_BODY_ARMOR    0
#define IOS_SLOT_CLOAK         1
#define IOS_SLOT_HELMET        2
#define IOS_SLOT_SHIELD        3
#define IOS_SLOT_GLOVES        4
#define IOS_SLOT_BOOTS         5
#define IOS_SLOT_SHIRT         6
#define IOS_SLOT_WEAPON        7
#define IOS_SLOT_SECONDARY     8
#define IOS_SLOT_QUIVER        9
#define IOS_SLOT_AMULET        10
#define IOS_SLOT_LEFT_RING     11
#define IOS_SLOT_RIGHT_RING    12
#define IOS_SLOT_BLINDFOLD     13
#define IOS_SLOT_COUNT         14

/* Equipment functions */
NETHACK_EXPORT const char* ios_get_equipment_slot(int slot);
NETHACK_EXPORT int ios_is_slot_cursed(int slot);
NETHACK_EXPORT int ios_is_slot_blessed(int slot);
NETHACK_EXPORT int ios_is_weapon_welded(void);
NETHACK_EXPORT int ios_is_left_ring_available(void);
NETHACK_EXPORT int ios_is_right_ring_available(void);

/* Character identity functions */
NETHACK_EXPORT const char* ios_get_current_role_name(void);
NETHACK_EXPORT const char* ios_get_current_race_name(void);
NETHACK_EXPORT int ios_get_current_gender(void);
NETHACK_EXPORT const char* ios_get_current_gender_name(void);
NETHACK_EXPORT int ios_get_current_alignment(void);
NETHACK_EXPORT const char* ios_get_current_alignment_name(void);
NETHACK_EXPORT int ios_get_player_level(void);
NETHACK_EXPORT long ios_get_player_experience(void);

/* Encumbrance functions */
NETHACK_EXPORT int ios_get_encumbrance(void);
NETHACK_EXPORT const char* ios_get_encumbrance_name(void);

/* Hunger functions */
NETHACK_EXPORT int ios_get_hunger_state(void);
NETHACK_EXPORT const char* ios_get_hunger_state_name(void);

/* Polymorph functions */
NETHACK_EXPORT int ios_is_polymorphed(void);
NETHACK_EXPORT const char* ios_get_polymorph_form(void);
NETHACK_EXPORT int ios_get_polymorph_turns_left(void);

/* Status conditions (returns bitmask compatible with PlayerCondition.swift) */
NETHACK_EXPORT unsigned long ios_get_condition_mask(void);

/* Comprehensive JSON export */
NETHACK_EXPORT const char* ios_get_character_status_json(void);

/* Ring selection support */
NETHACK_EXPORT int ios_get_ring_slot_availability(void);
NETHACK_EXPORT const char* ios_get_ring_slot_item(int which_hand);

#endif /* IOS_CHARACTER_STATUS_H */
