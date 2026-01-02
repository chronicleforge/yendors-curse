/*
 * fixed_memory.c - Fixed-address memory allocator implementation
 *
 * Guarantees pointer validity across saves/restarts by using fixed addresses
 */

#include "fixed_memory.h"
#include <sys/mman.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

// Memory block header for tracking allocations
typedef struct block_header {
    size_t size;           // Size of this block (including header)
    uint32_t magic;        // Magic number for integrity checking
    uint8_t is_free;       // 0 = allocated, 1 = free
    uint8_t padding[3];    // Alignment padding
} block_header;

#define BLOCK_MAGIC 0xDEADBEEF
#define ALIGN_SIZE 16  // 16-byte alignment for ARM64

// Global state (exported for debugging)
void* memory_base = NULL;  // Removed static to allow access from zone code
static size_t memory_used = 0;
static size_t allocation_count = 0;
static size_t actual_memory_size = NETHACK_MEMORY_SIZE;  // Track actual allocated size

// Align size to boundary
static inline size_t align_up(size_t size, size_t alignment) {
    return (size + alignment - 1) & ~(alignment - 1);
}

// Initialize the fixed memory region
int fixed_memory_init(void) {
    if (memory_base != NULL) {
        fprintf(stderr, "[FIXED_MEM] Already initialized at %p\n", memory_base);
        return 0;
    }

    // First, try to clean up any existing mapping at our preferred address
    munmap((void*)NETHACK_FIXED_BASE, NETHACK_MEMORY_SIZE);

    // Try multiple strategies in order
    void* addr = MAP_FAILED;

    // Strategy 1: Try MAP_FIXED at our preferred address
    addr = mmap((void*)NETHACK_FIXED_BASE,
                NETHACK_MEMORY_SIZE,
                PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANON | MAP_FIXED,
                -1, 0);

    if (addr != MAP_FAILED) {
        fprintf(stderr, "[FIXED_MEM] Success: Got fixed address at %p\n", addr);
    } else {
        // Strategy 2: Try without MAP_FIXED but with hint
        fprintf(stderr, "[FIXED_MEM] MAP_FIXED failed (ASLR?), trying with hint\n");

        addr = mmap((void*)NETHACK_FIXED_BASE,
                    NETHACK_MEMORY_SIZE,
                    PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANON,
                    -1, 0);

        if (addr != MAP_FAILED && addr == (void*)NETHACK_FIXED_BASE) {
            fprintf(stderr, "[FIXED_MEM] Got requested address via hint\n");
        } else if (addr != MAP_FAILED) {
            // Strategy 3: Accept any address but warn about snapshot compatibility
            fprintf(stderr, "[FIXED_MEM] WARNING: Got different address %p (wanted %p)\n",
                    addr, (void*)NETHACK_FIXED_BASE);
            fprintf(stderr, "[FIXED_MEM] NOTE: Snapshots will only work in this session!\n");
        } else {
            // Strategy 4: Last resort - try smaller size
            fprintf(stderr, "[FIXED_MEM] Standard allocation failed, trying smaller size\n");
            size_t smaller_size = 32 * 1024 * 1024; // 32MB

            addr = mmap(NULL,
                        smaller_size,
                        PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANON,
                        -1, 0);

            if (addr == MAP_FAILED) {
                fprintf(stderr, "[FIXED_MEM] CRITICAL: Cannot allocate memory: %s\n",
                        strerror(errno));
                return -1;
            }

            fprintf(stderr, "[FIXED_MEM] Using reduced size: %zu MB at %p\n",
                    smaller_size / (1024*1024), addr);
            actual_memory_size = smaller_size;
        }
    }

    memory_base = addr;
    memory_used = 0;
    allocation_count = 0;

    // Clear the memory
    memset(memory_base, 0, actual_memory_size);

    fprintf(stderr, "[FIXED_MEM] Initialized %zu MB at %p %s\n",
            actual_memory_size / (1024*1024), memory_base,
            (memory_base == (void*)NETHACK_FIXED_BASE) ? "(FIXED ADDRESS!)" : "(dynamic)");

    return 0;
}

// Simple bump allocator with headers
void* fixed_alloc(size_t size) {
    if (!memory_base) {
        if (fixed_memory_init() != 0) {
            return NULL;
        }
    }

    // Calculate total size with header and alignment
    size_t total_size = align_up(sizeof(block_header) + size, ALIGN_SIZE);

    // Check if we have enough space
    if (memory_used + total_size > actual_memory_size) {
        fprintf(stderr, "[FIXED_MEM] Out of memory! Used: %zu, Requested: %zu\n",
                memory_used, total_size);
        return NULL;
    }

    // Get pointer to new block
    block_header* block = (block_header*)((uint8_t*)memory_base + memory_used);

    // Initialize header
    block->size = total_size;
    block->magic = BLOCK_MAGIC;
    block->is_free = 0;

    // Update counters
    memory_used += total_size;
    allocation_count++;

    // Return pointer after header
    return (uint8_t*)block + sizeof(block_header);
}

void* fixed_calloc(size_t count, size_t size) {
    size_t total = count * size;
    void* ptr = fixed_alloc(total);
    if (ptr) {
        memset(ptr, 0, total);
    }
    return ptr;
}

void* fixed_realloc(void* ptr, size_t new_size) {
    if (!ptr) {
        return fixed_alloc(new_size);
    }

    // Get block header
    block_header* block = (block_header*)((uint8_t*)ptr - sizeof(block_header));

    // Check magic
    if (block->magic != BLOCK_MAGIC) {
        fprintf(stderr, "[FIXED_MEM] realloc: Invalid magic at %p\n", ptr);
        return NULL;
    }

    // Get old size
    size_t old_size = block->size - sizeof(block_header);

    // Allocate new block
    void* new_ptr = fixed_alloc(new_size);
    if (new_ptr) {
        // Copy old data
        size_t copy_size = (old_size < new_size) ? old_size : new_size;
        memcpy(new_ptr, ptr, copy_size);

        // Mark old block as free (simple marking, no coalescing)
        block->is_free = 1;
    }

    return new_ptr;
}

void fixed_free(void* ptr) {
    if (!ptr) return;

    // Get block header
    block_header* block = (block_header*)((uint8_t*)ptr - sizeof(block_header));

    // Check magic
    if (block->magic != BLOCK_MAGIC) {
        fprintf(stderr, "[FIXED_MEM] free: Invalid magic at %p\n", ptr);
        return;
    }

    // Mark as free (simple implementation - no actual reclamation)
    block->is_free = 1;
}

// Complete restart - clear everything but keep the address
void fixed_memory_restart(void) {
    if (!memory_base) {
        fprintf(stderr, "[FIXED_MEM] Cannot restart - not initialized\n");
        return;
    }

    fprintf(stderr, "[FIXED_MEM] Restarting - clearing %zu bytes at %p\n",
            memory_used, memory_base);

    // Clear all used memory
    memset(memory_base, 0, actual_memory_size);

    // Reset counters
    memory_used = 0;
    allocation_count = 0;
}

// Save the entire memory region
int fixed_memory_save(const char* filepath) {
    if (!memory_base) {
        fprintf(stderr, "[FIXED_MEM] Cannot save - not initialized\n");
        return -1;
    }

    int fd = open(filepath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        fprintf(stderr, "[FIXED_MEM] Cannot create save file: %s\n", strerror(errno));
        return -1;
    }

    // Enhanced header with version and flags
    struct {
        char magic[8];        // "NHFIXED\0"
        uint32_t version;     // Format version
        uint32_t flags;       // Bit 0: uses_fixed_address
        void* base_addr;
        size_t used;
        size_t count;
        uint64_t checksum;    // Simple checksum for integrity
    } header = {0};

    strcpy(header.magic, "NHFIXED");
    header.version = 1;
    header.flags = (memory_base == (void*)NETHACK_FIXED_BASE) ? 1 : 0;
    header.base_addr = memory_base;
    header.used = memory_used;
    header.count = allocation_count;

    // Calculate simple checksum
    uint64_t checksum = 0;
    uint8_t* data = (uint8_t*)memory_base;
    for (size_t i = 0; i < memory_used; i++) {
        checksum = (checksum << 1) ^ data[i];
    }
    header.checksum = checksum;

    write(fd, &header, sizeof(header));

    // Save the actual memory content (only used portion)
    write(fd, memory_base, memory_used);

    close(fd);

    fprintf(stderr, "[FIXED_MEM] Saved %zu bytes (%zu allocations) to %s\n",
            memory_used, allocation_count, filepath);
    fprintf(stderr, "[FIXED_MEM] Save mode: %s\n",
            header.flags & 1 ? "FIXED ADDRESS" : "DYNAMIC");

    return 0;
}

// Load the memory region
int fixed_memory_load(const char* filepath) {
    if (!memory_base) {
        if (fixed_memory_init() != 0) {
            return -1;
        }
    }

    int fd = open(filepath, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "[FIXED_MEM] Cannot open save file: %s\n", strerror(errno));
        return -1;
    }

    // Read enhanced header
    struct {
        char magic[8];
        uint32_t version;
        uint32_t flags;
        void* base_addr;
        size_t used;
        size_t count;
        uint64_t checksum;
    } header;

    if (read(fd, &header, sizeof(header)) != sizeof(header)) {
        fprintf(stderr, "[FIXED_MEM] Invalid save file header\n");
        close(fd);
        return -1;
    }

    // Check magic and version
    if (strcmp(header.magic, "NHFIXED") != 0) {
        fprintf(stderr, "[FIXED_MEM] Invalid save file format (bad magic)\n");
        close(fd);
        return -1;
    }

    if (header.version != 1) {
        fprintf(stderr, "[FIXED_MEM] Unsupported save file version %u\n", header.version);
        close(fd);
        return -1;
    }

    // Check compatibility based on save mode
    int saved_with_fixed = (header.flags & 1) != 0;
    int current_is_fixed = (memory_base == (void*)NETHACK_FIXED_BASE);

    if (saved_with_fixed && !current_is_fixed) {
        fprintf(stderr, "[FIXED_MEM] ERROR: Save uses fixed address but current session doesn't\n");
        fprintf(stderr, "[FIXED_MEM] Cannot load - pointers would be invalid\n");
        close(fd);
        return -1;
    }

    if (saved_with_fixed && current_is_fixed) {
        // Both use fixed address - best case!
        fprintf(stderr, "[FIXED_MEM] Loading fixed-address save (pointers preserved!)\n");
    } else if (!saved_with_fixed && !current_is_fixed) {
        // Both dynamic - only works if same address
        if (header.base_addr != memory_base) {
            fprintf(stderr, "[FIXED_MEM] ERROR: Dynamic addresses don't match!\n");
            fprintf(stderr, "[FIXED_MEM]   Saved at: %p, Current: %p\n",
                    header.base_addr, memory_base);
            fprintf(stderr, "[FIXED_MEM] Cannot load - pointers would be invalid\n");
            close(fd);
            return -1;
        }
        fprintf(stderr, "[FIXED_MEM] Loading dynamic save (same session)\n");
    } else {
        // Mixed mode - won't work
        fprintf(stderr, "[FIXED_MEM] ERROR: Incompatible save mode\n");
        close(fd);
        return -1;
    }

    // Clear current memory
    memset(memory_base, 0, actual_memory_size);

    // Load the memory content
    if (read(fd, memory_base, header.used) != (ssize_t)header.used) {
        fprintf(stderr, "[FIXED_MEM] Failed to read memory content\n");
        close(fd);
        return -1;
    }

    // Verify checksum
    uint64_t checksum = 0;
    uint8_t* data = (uint8_t*)memory_base;
    for (size_t i = 0; i < header.used; i++) {
        checksum = (checksum << 1) ^ data[i];
    }

    if (checksum != header.checksum) {
        fprintf(stderr, "[FIXED_MEM] WARNING: Checksum mismatch - save might be corrupted\n");
    }

    // Restore counters
    memory_used = header.used;
    allocation_count = header.count;

    close(fd);

    fprintf(stderr, "[FIXED_MEM] Successfully loaded %zu bytes (%zu allocations)\n",
            memory_used, allocation_count);

    return 0;
}

// Get statistics
void fixed_memory_stats(size_t* used, size_t* allocations) {
    if (used) *used = memory_used;
    if (allocations) *allocations = allocation_count;
}

// Check integrity of all blocks
int fixed_memory_check_integrity(void) {
    if (!memory_base) return -1;

    size_t offset = 0;
    size_t blocks_checked = 0;
    size_t blocks_free = 0;

    while (offset < memory_used) {
        block_header* block = (block_header*)((uint8_t*)memory_base + offset);

        if (block->magic != BLOCK_MAGIC) {
            fprintf(stderr, "[FIXED_MEM] Integrity check failed at offset %zu\n", offset);
            return -1;
        }

        if (block->is_free) {
            blocks_free++;
        }

        blocks_checked++;
        offset += block->size;
    }

    fprintf(stderr, "[FIXED_MEM] Integrity OK: %zu blocks (%zu free)\n",
            blocks_checked, blocks_free);

    return 0;
}