/*
 * nethack_zone.c - Zone-based memory management for NetHack iOS
 *
 * Uses Apple's malloc_zone API for efficient memory management.
 * Allows complete memory cleanup with a single zone_destroy call.
 */

#include <malloc/malloc.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/vm_map.h>

// NetHack includes
#define EXTERN_H  // Prevent duplicate declarations
#include "../NetHack/include/hack.h"
#include "nethack_zone.h"  // Include our header for ZoneType

// Forward declarations that NetHack expects
long *alloc(unsigned int) NONNULL;
long *re_alloc(long *, unsigned int) NONNULL;
char *dupstr(const char *);

// Additional functions from alloc.c that NetHack needs
#ifndef LUA_INTEGER
#include "../NetHack/include/nhlua.h"
#endif

ATTRNORETURN extern void panic(const char *, ...) PRINTF_F(1, 2) NORETURN;
extern int FITSint_(LUA_INTEGER, const char *, int) NONNULLARG2;
extern unsigned FITSuint_(unsigned long long, const char *, int) NONNULLARG2;

// Zone pointers
static malloc_zone_t* nethack_zone = NULL;  // Current active zone
static malloc_zone_t* character_zone = NULL;  // Zone for character creation
static malloc_zone_t* game_zone = NULL;       // Zone for actual gameplay
static malloc_zone_t* savegame_zone = NULL;   // Persistent zone for saves
static ZoneType current_zone_type = ZONE_TYPE_CHARACTER_CREATION;

// Statistics tracking
static size_t total_allocated = 0;
static size_t allocation_count = 0;

// Allocation tracking for iOS snapshots
typedef struct allocation_node {
    void* ptr;
    size_t size;
    struct allocation_node* next;
} allocation_node;

static allocation_node* allocation_list = NULL;

// Forward declarations for internal zone functions
static long* zone_alloc(unsigned int lth);
static long* zone_realloc(long* oldptr, unsigned int newlth);
static char* zone_dupstr(const char* string);

// Debug logging
#define ZONE_DEBUG 0
#if ZONE_DEBUG
#define ZONE_LOG(fmt, ...) fprintf(stderr, "[ZONE] " fmt "\n", ##__VA_ARGS__)
#else
#define ZONE_LOG(fmt, ...) ((void)0)
#endif

// Initialize the NetHack memory zone
static void ensure_nethack_zone(void) {
    if (!nethack_zone) {
        // Create initial zone for character creation
        nethack_zone_switch(ZONE_TYPE_CHARACTER_CREATION);
    }
}

// Create a zone for character creation
static void create_character_zone(void) {
    if (character_zone) {
        malloc_destroy_zone(character_zone);
    }
    character_zone = malloc_create_zone(256 * 1024, 0);  // Smaller zone for char creation
    if (!character_zone) {
        panic("Failed to create character creation zone!");
    }
    malloc_set_zone_name(character_zone, "NetHack Character Creation");
    ZONE_LOG("Created character zone at %p", character_zone);
}

// Create a zone for the actual game
static void create_game_zone(void) {
    if (game_zone) {
        malloc_destroy_zone(game_zone);
    }
    game_zone = malloc_create_zone(1024 * 1024, 0);  // Full zone for game
    if (!game_zone) {
        panic("Failed to create game zone!");
    }
    malloc_set_zone_name(game_zone, "NetHack Game");
    ZONE_LOG("Created game zone at %p", game_zone);
}

// Initialize savegame zone (persistent across game restarts)
static void ensure_savegame_zone(void) {
    if (!savegame_zone) {
        savegame_zone = malloc_create_zone(256 * 1024, 0);
        if (!savegame_zone) {
            panic("Failed to create savegame memory zone!");
        }
        malloc_set_zone_name(savegame_zone, "NetHack Saves");
        ZONE_LOG("Created savegame zone at %p", savegame_zone);
    }
}

// NetHack compatibility - these replace the functions from alloc.c
long* alloc(unsigned int lth) {
    return zone_alloc(lth);
}

long* re_alloc(long* oldptr, unsigned int newlth) {
    return zone_realloc(oldptr, newlth);
}

char* dupstr(const char* string) {
    return zone_dupstr(string);
}

// Helper: Track allocation for iOS snapshots
static void track_allocation(void* ptr, size_t size) {
    if (!ptr) return;

    allocation_node* node = (allocation_node*)malloc(sizeof(allocation_node));
    if (!node) return;  // Silent fail, tracking is optional

    node->ptr = ptr;
    node->size = size;
    node->next = allocation_list;
    allocation_list = node;
}

// Helper: Remove allocation from tracking
static void untrack_allocation(void* ptr) {
    if (!ptr) return;

    allocation_node** current = &allocation_list;
    while (*current) {
        if ((*current)->ptr == ptr) {
            allocation_node* to_remove = *current;
            *current = (*current)->next;
            free(to_remove);
            return;
        }
        current = &(*current)->next;
    }
}

// Helper: Clear all allocation tracking
static void clear_allocation_tracking(void) {
    while (allocation_list) {
        allocation_node* next = allocation_list->next;
        free(allocation_list);
        allocation_list = next;
    }
}

// Zone-based allocation functions that replace NetHack's alloc()
static long* zone_alloc(unsigned int lth) {
    ensure_nethack_zone();

    // Force alignment as NetHack expects
    if (!(lth) || (lth) % sizeof(long) != 0)
        lth += sizeof(long) - (lth) % sizeof(long);

    void* ptr = malloc_zone_malloc(nethack_zone, lth);
    if (!ptr) {
        panic("Memory allocation failure; cannot get %u bytes", lth);
    }

    // Track allocation for iOS snapshots
    track_allocation(ptr, lth);

    // Track statistics
    total_allocated += lth;
    allocation_count++;

    ZONE_LOG("Allocated %u bytes at %p (total: %zu, count: %zu)",
             lth, ptr, total_allocated, allocation_count);

    return (long*)ptr;
}

// Zone-based reallocation
static long* zone_realloc(long* oldptr, unsigned int newlth) {
    ensure_nethack_zone();

    // Force alignment
    if (!(newlth) || (newlth) % sizeof(long) != 0)
        newlth += sizeof(long) - (newlth) % sizeof(long);

    void* newptr = malloc_zone_realloc(nethack_zone, oldptr, newlth);
    if (newlth && !newptr) {
        panic("Memory allocation failure; cannot extend to %u bytes", newlth);
    }

    ZONE_LOG("Reallocated %p to %u bytes at %p", oldptr, newlth, newptr);

    return (long*)newptr;
}

// Zone-based free
void zone_free(void* ptr) {
    if (ptr && nethack_zone) {
        // Remove from tracking
        untrack_allocation(ptr);

        malloc_zone_free(nethack_zone, ptr);
        allocation_count--;
        ZONE_LOG("Freed %p (count: %zu)", ptr, allocation_count);
    }
}

// Zone-based calloc
void* zone_calloc(size_t num, size_t size) {
    ensure_nethack_zone();

    void* ptr = malloc_zone_calloc(nethack_zone, num, size);
    if (!ptr) {
        panic("Memory allocation failure; cannot get %zu x %zu bytes", num, size);
    }

    // Track allocation for iOS snapshots
    track_allocation(ptr, num * size);

    total_allocated += (num * size);
    allocation_count++;

    ZONE_LOG("Calloced %zu x %zu bytes at %p", num, size, ptr);

    return ptr;
}

// Zone-based strdup
static char* zone_dupstr(const char* string) {
    if (!string) return NULL;

    size_t len = strlen(string);
    if (len > (unsigned)(~0U - 1U)) {
        panic("dupstr: string length overflow");
    }

    char* copy = (char*)zone_alloc(len + 1);
    strcpy(copy, string);

    return copy;
}

// Switch between different zone types
void nethack_zone_switch(ZoneType type) {
    ZONE_LOG("=== ZONE SWITCH: %s ===",
             type == ZONE_TYPE_CHARACTER_CREATION ? "CHARACTER_CREATION" : "GAME");

    current_zone_type = type;

    switch (type) {
        case ZONE_TYPE_CHARACTER_CREATION:
            create_character_zone();
            nethack_zone = character_zone;
            break;

        case ZONE_TYPE_GAME:
            create_game_zone();
            nethack_zone = game_zone;
            // Destroy character zone if it exists - no longer needed
            if (character_zone) {
                malloc_destroy_zone(character_zone);
                character_zone = NULL;
                ZONE_LOG("Destroyed character creation zone");
            }
            break;
    }

    // Reset tracking for new zone
    clear_allocation_tracking();
    total_allocated = 0;
    allocation_count = 0;

    ZONE_LOG("Switched to zone %p", nethack_zone);
}

// Destroy the current zone
void nethack_zone_destroy_current(void) {
    if (nethack_zone) {
        ZONE_LOG("Destroying current zone %p", nethack_zone);

        // Clear allocation tracking first
        clear_allocation_tracking();

        malloc_destroy_zone(nethack_zone);
        nethack_zone = NULL;

        // Also clear the specific zone pointer
        if (current_zone_type == ZONE_TYPE_CHARACTER_CREATION) {
            character_zone = NULL;
        } else if (current_zone_type == ZONE_TYPE_GAME) {
            game_zone = NULL;
        }

        // Reset statistics
        total_allocated = 0;
        allocation_count = 0;
    }
}

// Complete restart - destroys all game memory but preserves saves
void nethack_zone_restart(void) {
    ZONE_LOG("=== ZONE RESTART BEGIN ===");
    ZONE_LOG("Before: %zu bytes in %zu allocations", total_allocated, allocation_count);

    // Destroy current zone and switch back to character creation
    nethack_zone_destroy_current();
    nethack_zone_switch(ZONE_TYPE_CHARACTER_CREATION);

    ZONE_LOG("=== ZONE RESTART COMPLETE ===");
}

// Complete shutdown - destroys everything
void nethack_zone_shutdown(void) {
    ZONE_LOG("=== ZONE SHUTDOWN BEGIN ===");

    // Clear allocation tracking
    clear_allocation_tracking();

    if (nethack_zone) {
        malloc_destroy_zone(nethack_zone);
        nethack_zone = NULL;
    }

    if (character_zone && character_zone != nethack_zone) {
        malloc_destroy_zone(character_zone);
        character_zone = NULL;
    }

    if (game_zone && game_zone != nethack_zone) {
        malloc_destroy_zone(game_zone);
        game_zone = NULL;
    }

    if (savegame_zone) {
        malloc_destroy_zone(savegame_zone);
        savegame_zone = NULL;
    }

    total_allocated = 0;
    allocation_count = 0;

    ZONE_LOG("=== ZONE SHUTDOWN COMPLETE ===");
}

// Get memory statistics
void nethack_zone_stats(size_t* bytes_allocated, size_t* num_allocations) {
    if (bytes_allocated) *bytes_allocated = total_allocated;
    if (num_allocations) *num_allocations = allocation_count;
}

// Print detailed zone statistics (for debugging)
void nethack_zone_print_stats(void) {
    if (!nethack_zone) {
        fprintf(stderr, "[ZONE] No active NetHack zone\n");
        return;
    }

    malloc_statistics_t stats;
    stats.blocks_in_use = 0;
    stats.size_in_use = 0;
    stats.size_allocated = 0;

    malloc_zone_statistics(nethack_zone, &stats);

    fprintf(stderr, "[ZONE] NetHack Memory Statistics:\n");
    fprintf(stderr, "  Blocks in use: %u\n", stats.blocks_in_use);
    fprintf(stderr, "  Size in use: %zu bytes\n", stats.size_in_use);
    fprintf(stderr, "  Size allocated: %zu bytes\n", stats.size_allocated);
    fprintf(stderr, "  Tracked allocations: %zu\n", allocation_count);
    fprintf(stderr, "  Tracked size: %zu bytes\n", total_allocated);
}

// Savegame-specific allocations (survive restarts)
void* savegame_alloc(size_t size) {
    ensure_savegame_zone();

    void* ptr = malloc_zone_malloc(savegame_zone, size);
    if (!ptr) {
        panic("Savegame allocation failure; cannot get %zu bytes", size);
    }

    ZONE_LOG("Savegame allocated %zu bytes at %p", size, ptr);
    return ptr;
}

void savegame_free(void* ptr) {
    if (ptr && savegame_zone) {
        malloc_zone_free(savegame_zone, ptr);
        ZONE_LOG("Savegame freed %p", ptr);
    }
}

// Check if a pointer belongs to NetHack zone (for debugging)
int nethack_zone_owns(void* ptr) {
    if (!nethack_zone || !ptr) return 0;

    size_t size = malloc_size(ptr);
    if (size == 0) return 0;

    // Check if this pointer's zone matches our zone
    malloc_zone_t* ptr_zone = malloc_zone_from_ptr(ptr);
    return (ptr_zone == nethack_zone);
}

#ifdef MONITOR_HEAP
// Support for NetHack's heap monitoring
long* nhalloc(unsigned int lth, const char* file, int line) {
    long* ptr = zone_alloc(lth);
    ZONE_LOG("nhalloc: %u bytes at %s:%d -> %p", lth, file, line, ptr);
    return ptr;
}

long* nhrealloc(long* oldptr, unsigned int newlth, const char* file, int line) {
    long* ptr = zone_realloc(oldptr, newlth);
    ZONE_LOG("nhrealloc: %p to %u bytes at %s:%d -> %p", oldptr, newlth, file, line, ptr);
    return ptr;
}

void nhfree(genericptr_t ptr, const char* file, int line) {
    ZONE_LOG("nhfree: %p at %s:%d", ptr, file, line);
    zone_free(ptr);
}

char* nhdupstr(const char* string, const char* file, int line) {
    char* copy = zone_dupstr(string);
    ZONE_LOG("nhdupstr: \"%s\" at %s:%d -> %p", string, file, line, copy);
    return copy;
}
#endif // MONITOR_HEAP

// Required utility functions from alloc.c
int FITSint_(LUA_INTEGER i, const char *file, int line) {
    int iret = (int) i;
    if (iret != i)
        panic("Overflow at %s:%d", file, line);
    return iret;
}

unsigned FITSuint_(unsigned long long ull, const char *file, int line) {
    unsigned uret = (unsigned) ull;
    if (uret != ull)
        panic("Overflow at %s:%d", file, line);
    return uret;
}

// Format pointer function that NetHack might expect
char* fmt_ptr(const genericptr ptr) {
    static char buf[32];
    snprintf(buf, sizeof(buf), "%p", ptr);
    return buf;
}

// MARK: - Zone Snapshot Functions

// Structure to hold zone enumeration data
typedef struct {
    FILE* file;
    size_t total_size;
    size_t block_count;
    int error;
} zone_snapshot_context;

// Callback for zone enumeration during save
static void zone_snapshot_enumerator(task_t task, void* context, unsigned type_mask,
                                    vm_range_t *ranges, unsigned range_count) {
    zone_snapshot_context* ctx = (zone_snapshot_context*)context;

    for (unsigned i = 0; i < range_count && !ctx->error; i++) {
        vm_range_t range = ranges[i];

        // Write block header
        if (fwrite(&range.address, sizeof(vm_address_t), 1, ctx->file) != 1 ||
            fwrite(&range.size, sizeof(vm_size_t), 1, ctx->file) != 1) {
            ctx->error = 1;
            break;
        }

        // Write block data
        if (fwrite((void*)range.address, 1, range.size, ctx->file) != range.size) {
            ctx->error = 1;
            break;
        }

        ctx->total_size += range.size;
        ctx->block_count++;
    }
}

// Save zone snapshot to file (iOS version using allocation tracking)
int nethack_zone_snapshot_save(const char* filepath) {
    if (!nethack_zone || !filepath) return -1;

    FILE* file = fopen(filepath, "wb");
    if (!file) {
        ZONE_LOG("Failed to open snapshot file for writing: %s", filepath);
        return -1;
    }

    // Write header
    const char magic[8] = "NHZONE02";  // Magic + version (02 for iOS tracking version)
    fwrite(magic, 1, 8, file);

    // Count allocations
    size_t block_count = 0;
    size_t total_size = 0;
    allocation_node* node = allocation_list;
    while (node) {
        block_count++;
        total_size += node->size;
        node = node->next;
    }

    // Write metadata
    fwrite(&block_count, sizeof(size_t), 1, file);
    fwrite(&total_size, sizeof(size_t), 1, file);

    // Write all allocations
    node = allocation_list;
    while (node) {
        // Write size and data
        fwrite(&node->size, sizeof(size_t), 1, file);
        fwrite(node->ptr, node->size, 1, file);
        node = node->next;
    }

    fclose(file);

    ZONE_LOG("Saved zone snapshot: %zu blocks, %zu bytes to %s",
             block_count, total_size, filepath);

    return 0;
}

// Load zone snapshot from file (iOS version)
int nethack_zone_snapshot_load(const char* filepath) {
    if (!filepath) return -1;

    FILE* file = fopen(filepath, "rb");
    if (!file) {
        ZONE_LOG("Failed to open snapshot file for reading: %s", filepath);
        return -1;
    }

    // Check magic header
    char magic[8];
    if (fread(magic, 1, 8, file) != 8) {
        fclose(file);
        ZONE_LOG("Failed to read magic header");
        return -1;
    }

    // Support both versions
    if (memcmp(magic, "NHZONE02", 8) != 0 && memcmp(magic, "NHZONE01", 8) != 0) {
        fclose(file);
        ZONE_LOG("Invalid snapshot file format");
        return -1;
    }

    // Read metadata
    size_t block_count, total_size;
    fread(&block_count, sizeof(size_t), 1, file);
    fread(&total_size, sizeof(size_t), 1, file);

    ZONE_LOG("Loading snapshot: %zu blocks, %zu bytes", block_count, total_size);

    // Destroy current zone and create new GAME zone for the loaded snapshot
    nethack_zone_destroy_current();

    // Create a new GAME zone for the loaded snapshot
    nethack_zone = malloc_create_zone(0, 0);
    if (!nethack_zone) {
        fclose(file);
        ZONE_LOG("Failed to create zone for snapshot");
        return -1;
    }
    malloc_set_zone_name(nethack_zone, "NetHack Game (Loaded)");

    // Clear allocation tracking for new zone
    clear_allocation_tracking();
    total_allocated = 0;
    allocation_count = 0;

    // Read and restore blocks
    for (size_t i = 0; i < block_count; i++) {
        size_t size;

        if (fread(&size, sizeof(size_t), 1, file) != 1) {
            fclose(file);
            ZONE_LOG("Error reading block size");
            return -1;
        }

        // Allocate memory in zone (will be tracked automatically)
        void* ptr = zone_alloc(size);
        if (!ptr) {
            fclose(file);
            ZONE_LOG("Failed to allocate %zu bytes for snapshot", size);
            return -1;
        }

        // Read block data
        if (fread(ptr, 1, size, file) != size) {
            fclose(file);
            ZONE_LOG("Error reading block data");
            return -1;
        }
    }

    fclose(file);

    // After loading a snapshot, we're in a game state, not character creation
    current_zone_type = ZONE_TYPE_GAME;
    game_zone = nethack_zone;  // Update the game_zone pointer

    ZONE_LOG("Successfully loaded zone snapshot from %s", filepath);
    ZONE_LOG("Zone type set to GAME after snapshot load");
    return 0;
}

// Get current game metadata for snapshot
void nethack_zone_get_metadata(char* buffer, size_t bufsize) {
    if (!buffer || bufsize == 0) return;

    // This will be filled from NetHack game state
    // For now, return basic placeholder info
    snprintf(buffer, bufsize,
             "{\"turn\":%d,\"hp\":%d,\"hpmax\":%d,\"level\":%d}",
             0, 10, 10, 1);  // Placeholder values
}