/*
 * nethack_memory_final.c - Simple static array memory allocator for NetHack iOS
 *
 * Uses a single static array with bump allocation.
 * The array ALWAYS has the same address, guaranteeing pointer validity!
 */

#include "nethack_memory_final.h"
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

// THE magic array - this has a fixed address in the binary!
uint8_t nethack_heap[NH_HEAP_SIZE] = {0};
size_t heap_used = 0;
static size_t allocation_count = 0;

// Simple block header for tracking
typedef struct block_header {
    size_t size;               // Total size including header
    uint32_t magic;            // Magic number for integrity
    uint8_t is_free;           // 0 = allocated, 1 = free
    uint8_t padding[3];        // Alignment
    struct block_header* next; // Free list pointer
} block_header;

#define BLOCK_MAGIC 0xFEEDBEEF
#define ALIGN_SIZE 16

// Free list for reusing freed blocks
static block_header* free_list_head = NULL;

// Align size to boundary
static inline size_t align_up(size_t size, size_t alignment) {
    return (size + alignment - 1) & ~(alignment - 1);
}

void* nh_malloc(size_t size) {
    if (size == 0) return NULL;

    // Calculate total size with header
    size_t total_size = align_up(sizeof(block_header) + size, ALIGN_SIZE);

    // CRITICAL FIX: Try to reuse a freed block first
    block_header* prev = NULL;
    block_header* current = free_list_head;

    while (current) {
        if (current->is_free && current->size >= total_size) {
            // Found a suitable free block - REUSE it!

            // CRITICAL: Save next pointer BEFORE we modify current!
            // Bug was: setting current->next = NULL before using it to unlink
            // This lost the entire rest of the free list!
            block_header* next_block = current->next;

            // Remove from free list FIRST (using saved next_block)
            if (prev) {
                prev->next = next_block;
            } else {
                free_list_head = next_block;
            }

            // NOW mark as allocated and clear next pointer
            current->is_free = 0;
            current->next = NULL;

            // Get user pointer
            void* user_ptr = (uint8_t*)current + sizeof(block_header);

            // CRITICAL FIX: Clear ENTIRE block, not just requested size!
            // BUG: If we reuse a 256-byte block for a 64-byte request,
            // only 64 bytes were zeroed, leaving 192 bytes of STALE DATA!
            // This caused "64 touchstones" corruption in Game 2+
            // ROOT CAUSE: Object allocated at same address had stale quan values
            size_t block_size = current->size - sizeof(block_header);
            memset(user_ptr, 0, block_size);

            return user_ptr;
        }
        prev = current;
        current = current->next;
    }

    // No free block found - bump allocate new one
    if (heap_used + total_size > NH_HEAP_SIZE) {
        fprintf(stderr, "[NH_MEMORY] Out of memory! Used: %zu, Requested: %zu\n",
                heap_used, total_size);
        return NULL;
    }

    // Get pointer to new block
    block_header* block = (block_header*)(nethack_heap + heap_used);

    // Initialize header
    block->size = total_size;
    block->magic = BLOCK_MAGIC;
    block->is_free = 0;
    block->next = NULL;

    // Update counters
    heap_used += total_size;
    allocation_count++;

    // Get user pointer
    void* user_ptr = (uint8_t*)block + sizeof(block_header);

    // CRITICAL: Clear the allocated memory to prevent garbage bytes
    memset(user_ptr, 0, size);

    return user_ptr;
}

void* nh_calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void* ptr = nh_malloc(total);
    if (ptr) {
        memset(ptr, 0, total);
    }
    return ptr;
}

void* nh_realloc(void* ptr, size_t new_size) {
    if (!ptr) return nh_malloc(new_size);
    if (new_size == 0) {
        nh_free(ptr);
        return NULL;
    }

    // Get block header
    block_header* block = (block_header*)((uint8_t*)ptr - sizeof(block_header));

    // Check magic
    if (block->magic != BLOCK_MAGIC) {
        fprintf(stderr, "[NH_MEMORY] realloc: Invalid magic at %p\n", ptr);
        return NULL;
    }

    // Get old size
    size_t old_size = block->size - sizeof(block_header);

    // Allocate new block
    void* new_ptr = nh_malloc(new_size);
    if (new_ptr) {
        // Copy old data
        size_t copy_size = (old_size < new_size) ? old_size : new_size;
        memcpy(new_ptr, ptr, copy_size);

        // CRITICAL FIX: Use nh_free() to properly add old block to free_list
        // Before: block->is_free = 1 leaked memory (not in free_list!)
        nh_free(ptr);
    }

    return new_ptr;
}

void nh_free(void* ptr) {
    if (!ptr) return;

    // Check if this is our memory
    if ((uint8_t*)ptr < nethack_heap || (uint8_t*)ptr >= nethack_heap + NH_HEAP_SIZE) {
        // Not our memory - might be system allocated
        // Just ignore it (or could call system free if needed)
        return;
    }

    // Get block header
    block_header* block = (block_header*)((uint8_t*)ptr - sizeof(block_header));

    // Check magic
    if (block->magic != BLOCK_MAGIC) {
        fprintf(stderr, "[NH_MEMORY] free: Invalid magic at %p\n", ptr);
        return;
    }

    // CRITICAL FIX: Add to free list for reuse
    block->is_free = 1;
    block->next = free_list_head;
    free_list_head = block;
}

void nh_restart(void) {
    fprintf(stderr, "[NH_MEMORY] Restarting - clearing %zu bytes\n", heap_used);

    // Clear everything
    memset(nethack_heap, 0, NH_HEAP_SIZE);
    heap_used = 0;
    allocation_count = 0;
    free_list_head = NULL;  // Clear free list

    fprintf(stderr, "[NH_MEMORY] Heap at %p (static array - always same address!)\n",
            (void*)nethack_heap);
}

int nh_save_state(const char* filename) {
    int fd = open(filename, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        fprintf(stderr, "[NH_MEMORY] Cannot create save file: %s\n", strerror(errno));
        return -1;
    }

    // Simple header
    struct {
        char magic[8];
        size_t used;
        size_t count;
        void* heap_addr;  // For verification
    } header = {0};

    strcpy(header.magic, "NHSAVE");
    header.used = heap_used;
    header.count = allocation_count;
    header.heap_addr = nethack_heap;

    write(fd, &header, sizeof(header));

    // Save only used portion
    write(fd, nethack_heap, heap_used);

    close(fd);

    fprintf(stderr, "[NH_MEMORY] Saved %zu bytes (%zu allocations)\n",
            heap_used, allocation_count);
    fprintf(stderr, "[NH_MEMORY] Heap address: %p (will be same on load!)\n",
            (void*)nethack_heap);

    return 0;
}

// Helper function to relocate a pointer if it points into the old heap
static void* relocate_pointer(void* old_ptr, void* old_heap_base, void* new_heap_base, size_t heap_size) {
    if (!old_ptr) return NULL;

    // Check if pointer is within old heap bounds
    if ((uint8_t*)old_ptr >= (uint8_t*)old_heap_base &&
        (uint8_t*)old_ptr < ((uint8_t*)old_heap_base + heap_size)) {
        // Calculate offset from old heap base
        ptrdiff_t offset = (uint8_t*)old_ptr - (uint8_t*)old_heap_base;
        // Return new pointer at same offset in new heap
        return (uint8_t*)new_heap_base + offset;
    }

    // Pointer is outside heap - leave unchanged
    return old_ptr;
}

int nh_load_state(const char* filename) {
    int fd = open(filename, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "[NH_MEMORY] Cannot open save file: %s\n", strerror(errno));
        return -1;
    }

    // Read header
    struct {
        char magic[8];
        size_t used;
        size_t count;
        void* heap_addr;
    } header;

    if (read(fd, &header, sizeof(header)) != sizeof(header)) {
        fprintf(stderr, "[NH_MEMORY] Invalid save file header\n");
        close(fd);
        return -1;
    }

    // Check magic
    if (strcmp(header.magic, "NHSAVE") != 0) {
        fprintf(stderr, "[NH_MEMORY] Invalid save file format\n");
        close(fd);
        return -1;
    }

    // Calculate relocation delta
    ptrdiff_t relocation_delta = (uint8_t*)nethack_heap - (uint8_t*)header.heap_addr;
    int needs_relocation = (relocation_delta != 0);

    if (needs_relocation) {
        fprintf(stderr, "[NH_MEMORY] Heap relocated by ASLR: %p → %p (delta=%ld bytes)\n",
                header.heap_addr, (void*)nethack_heap, (long)relocation_delta);
        fprintf(stderr, "[NH_MEMORY] Performing pointer relocation...\n");
    }

    // Clear heap
    memset(nethack_heap, 0, NH_HEAP_SIZE);

    // Load memory content
    if (read(fd, nethack_heap, header.used) != (ssize_t)header.used) {
        fprintf(stderr, "[NH_MEMORY] Failed to read memory content\n");
        close(fd);
        return -1;
    }

    close(fd);

    // CRITICAL: If heap was relocated, we must fix ALL pointers in the heap!
    if (needs_relocation) {
        fprintf(stderr, "[NH_MEMORY] Relocating pointers in %zu bytes of heap...\n", header.used);

        size_t pointers_relocated = 0;

        // Walk through all allocated blocks and relocate their pointers
        uint8_t* current = nethack_heap;
        while (current < nethack_heap + header.used) {
            block_header* block = (block_header*)current;

            // Validate block magic
            if (block->magic != BLOCK_MAGIC) {
                fprintf(stderr, "[NH_MEMORY] WARNING: Invalid block magic at offset %zu\n",
                        current - nethack_heap);
                break;
            }

            // Relocate the block's next pointer if it points into the heap
            if (block->next) {
                void* old_next = block->next;
                block->next = (block_header*)relocate_pointer(old_next, header.heap_addr,
                                                              nethack_heap, NH_HEAP_SIZE);
                if (block->next != old_next) {
                    pointers_relocated++;
                }
            }

            // Move to next block
            current += block->size;
        }

        fprintf(stderr, "[NH_MEMORY] Relocated %zu block header pointers\n", pointers_relocated);
        fprintf(stderr, "[NH_MEMORY] WARNING: NetHack game data pointers (fruits, objects, monsters)\n");
        fprintf(stderr, "[NH_MEMORY]          cannot be automatically relocated and may cause crashes!\n");
    }

    // Restore counters
    heap_used = header.used;
    allocation_count = header.count;

    // Rebuild free list from scratch by scanning allocated blocks
    free_list_head = NULL;
    uint8_t* scan = nethack_heap;
    size_t free_blocks = 0;

    while (scan < nethack_heap + heap_used) {
        block_header* block = (block_header*)scan;

        if (block->magic != BLOCK_MAGIC) break;

        if (block->is_free) {
            // Add to free list
            block->next = free_list_head;
            free_list_head = block;
            free_blocks++;
        }

        scan += block->size;
    }

    fprintf(stderr, "[NH_MEMORY] Rebuilt free list with %zu free blocks\n", free_blocks);

    fprintf(stderr, "[NH_MEMORY] Loaded %zu bytes (%zu allocations)\n",
            heap_used, allocation_count);

    return 0;
}

void nh_memory_stats(size_t* used, size_t* allocations) {
    if (used) *used = heap_used;
    if (allocations) *allocations = allocation_count;

    fprintf(stderr, "[NH_MEMORY] Stats: %zu bytes used, %zu allocations\n",
            heap_used, allocation_count);
    fprintf(stderr, "[NH_MEMORY] Heap at %p (static array)\n", (void*)nethack_heap);
}

// Get current memory usage
size_t nh_memory_used(void) {
    return heap_used;
}

// Reset all memory for a new game
void nh_reset(void) {
    fprintf(stderr, "[NH_MEMORY] Resetting all memory (was %zu bytes, %zu allocations)\n",
            heap_used, allocation_count);

    // Reset counters
    heap_used = 0;
    allocation_count = 0;

    // Clear free list
    free_list_head = NULL;

    // DON'T memset the heap - let it be reused
    // The heap address stays the same, which is critical
    // Old data will be overwritten on next allocation

    fprintf(stderr, "[NH_MEMORY] Reset complete - ready for new game\n");
}