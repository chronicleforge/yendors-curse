/*
 * nethack_memory_final.h - Simple static array memory allocator for NetHack iOS
 *
 * Uses a single static array that ALWAYS has the same address!
 * This guarantees pointer validity across saves/restarts.
 */

#ifndef NH_MEMORY_FINAL_H
#define NH_MEMORY_FINAL_H

#include <stddef.h>
#include <stdint.h>

// 128MB heap size - reasonable size with working free list allocator
// Previous bugs (linked list corruption, realloc leak, tile reuse, dispatch throttle) are now fixed
// Memory now properly reuses freed blocks instead of only growing
#define NH_HEAP_SIZE (128 * 1024 * 1024)

// Global array - ALWAYS has the same address!
extern uint8_t nethack_heap[NH_HEAP_SIZE];
extern size_t heap_used;

// Our allocation functions
void* nh_malloc(size_t size);
void nh_free(void* ptr);
void* nh_calloc(size_t nmemb, size_t size);
void* nh_realloc(void* ptr, size_t size);
void nh_restart(void);
int nh_save_state(const char* filename);
int nh_load_state(const char* filename);

// Debug functions
void nh_memory_stats(size_t* used, size_t* allocations);

// Reset function for new games
void nh_reset(void);

#endif // NH_MEMORY_FINAL_H