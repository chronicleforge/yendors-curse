/*
 * fixed_memory.h - Fixed-address memory allocator for NetHack iOS
 *
 * Uses a fixed virtual memory region to preserve pointer validity
 * across saves and restarts
 */

#ifndef FIXED_MEMORY_H
#define FIXED_MEMORY_H

#include <stddef.h>
#include <stdint.h>

// Fixed address in iOS virtual memory space (above 32-bit range, below system)
// iOS apps typically use addresses starting at 0x100000000
// We'll use 0x300000000 to avoid conflicts with system libraries
// Note: This might fail with ASLR or sandbox restrictions
#define NETHACK_FIXED_BASE  0x300000000ULL

// Memory size configuration (adaptive based on device)
#ifdef TARGET_OS_SIMULATOR
  #define NETHACK_MEMORY_SIZE (128 * 1024 * 1024)  // 128MB on simulator
#else
  #define NETHACK_MEMORY_SIZE (96 * 1024 * 1024)   // 96MB on device
#endif

// Minimum size if allocation fails
#define NETHACK_MIN_MEMORY_SIZE (32 * 1024 * 1024)  // 32MB minimum

// Initialize the fixed memory region
int fixed_memory_init(void);

// Allocation functions that replace malloc/free
void* fixed_alloc(size_t size);
void* fixed_calloc(size_t count, size_t size);
void* fixed_realloc(void* ptr, size_t new_size);
void fixed_free(void* ptr);

// Complete memory management
void fixed_memory_restart(void);     // Clear all memory but keep address
int fixed_memory_save(const char* filepath);
int fixed_memory_load(const char* filepath);

// Debug functions
void fixed_memory_stats(size_t* used, size_t* allocations);
int fixed_memory_check_integrity(void);

// For NetHack integration
#ifdef REPLACE_SYSTEM_MALLOC
#define malloc(x) fixed_alloc(x)
#define calloc(x,y) fixed_calloc(x,y)
#define realloc(x,y) fixed_realloc(x,y)
#define free(x) fixed_free(x)
#endif

#endif // FIXED_MEMORY_H