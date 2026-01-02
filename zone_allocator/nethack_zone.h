/*
 * nethack_zone.h - Fixed-address memory management for NetHack iOS
 *
 * Uses fixed memory addresses to preserve pointer validity across restarts
 */

#ifndef NETHACK_ZONE_H
#define NETHACK_ZONE_H

#include <stddef.h>

// Core allocation functions (replace NetHack's alloc.c)
// These are the actual functions NetHack calls
// NOTE: When MONITOR_HEAP is defined, global.h defines these as macros
// that expand to nhalloc/nhrealloc/nhdupstr, so skip these declarations
#if !defined(SKIP_ALLOC_DECLARATIONS) && !defined(MONITOR_HEAP)
long* alloc(unsigned int lth);
long* re_alloc(long* oldptr, unsigned int newlth);
char* dupstr(const char* string);
#endif

// Free function
void zone_free(void* ptr);

// Memory management - Exported for Swift NetHackMemoryManager
#include "../src/nethack_export.h"
NETHACK_EXPORT void nethack_zone_restart(void);    // Restart game, clear all allocations but keep address
NETHACK_EXPORT void nethack_zone_shutdown(void);   // Complete shutdown
NETHACK_EXPORT void nethack_zone_stats(size_t* bytes_allocated, size_t* num_allocations);
NETHACK_EXPORT void nethack_zone_print_stats(void);

// Zone types (kept for compatibility but uses fixed memory)
typedef enum {
    ZONE_TYPE_CHARACTER_CREATION,  // Character creation phase
    ZONE_TYPE_GAME                  // Main game
} ZoneType;

void nethack_zone_switch(ZoneType type);  // Switch phase (just a marker now)
void nethack_zone_destroy_current(void);  // Clear memory

// Snapshot Functions (now work correctly with pointers!)
int nethack_zone_snapshot_save(const char* filepath);
int nethack_zone_snapshot_load(const char* filepath);
void nethack_zone_get_metadata(char* buffer, size_t bufsize);

// Debugging
int nethack_zone_owns(void* ptr);

#ifdef MONITOR_HEAP
// When heap monitoring is enabled, use tracking versions
long* nhalloc(unsigned int lth, const char* file, int line);
long* nhrealloc(long* oldptr, unsigned int newlth, const char* file, int line);
void nhfree(void* ptr, const char* file, int line);
char* nhdupstr(const char* string, const char* file, int line);
#endif

#endif // NETHACK_ZONE_H