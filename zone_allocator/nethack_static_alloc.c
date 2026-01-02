/*
 * nethack_static_alloc.c - NetHack interface to static array allocator
 *
 * Provides NetHack's expected allocation functions using our static heap
 */

#include "nethack_memory_final.h"
#include "nethack_zone.h"  // For ZoneType
#include <string.h>
#include <stdio.h>

// NetHack includes
#define EXTERN_H
#include "../NetHack/include/hack.h"

// Forward declaration for panic
void panic(const char *, ...) __attribute__((noreturn));

// Undefine macros so we can define the actual functions
#undef alloc
#undef re_alloc
#undef free
#undef dupstr

// NetHack's allocation functions
long* alloc(unsigned int lth) {
    if (lth == 0) return NULL;

    void* ptr = nh_malloc(lth);
    if (!ptr) {
        panic("alloc: out of memory");
    }

    return (long*)ptr;
}

long* re_alloc(long* oldptr, unsigned int newlth) {
    if (!oldptr) {
        /* Initial allocation - use alloc */
        long* result = alloc(newlth);
        if (!result) {
            fprintf(stderr, "[STATIC_ALLOC] re_alloc: alloc(%u) failed\n", newlth);
        }
        return result;
    }
    if (newlth == 0) {
        nh_free(oldptr);
        return NULL;
    }

    void* newptr = nh_realloc(oldptr, newlth);
    if (!newptr) {
        fprintf(stderr, "[STATIC_ALLOC] re_alloc: nh_realloc failed for size %u\n", newlth);
        panic("re_alloc: out of memory");
    }

    return (long*)newptr;
}

void zone_free(void* ptr) {
    nh_free(ptr);
}

// For compatibility
void dealloc(void* ptr) {
    nh_free(ptr);
}

char* dupstr(const char* string) {
    if (!string) return NULL;

    size_t len = strlen(string) + 1;
    char* newstr = (char*)nh_malloc(len);

    if (newstr) {
        memcpy(newstr, string, len);
    } else {
        panic("dupstr: out of memory");
    }

    return newstr;
}

// FITSint/FITSuint for NetHack compatibility
int FITSint_(long long luaint, const char *file, int line) {
    int i = (int) luaint;
    if (i != luaint) {
        panic("FITSint: Integer overflow at %s:%d", file, line);
    }
    return i;
}

unsigned FITSuint_(unsigned long long ulluval, const char *file, int line) {
    unsigned u = (unsigned) ulluval;
    if (u != ulluval) {
        panic("FITSuint: Integer overflow at %s:%d", file, line);
    }
    return u;
}

// Format pointer for display
#define PTRBUFCNT 2
static char ptrbuf[PTRBUFCNT][20];
static int ptrbufidx = 0;

char* fmt_ptr(const void* ptr) {
    char *buf = ptrbuf[ptrbufidx];
    if (++ptrbufidx >= PTRBUFCNT)
        ptrbufidx = 0;

    snprintf(buf, sizeof(ptrbuf[0]), "%p", ptr);
    return buf;
}

// Zone compatibility functions - map to static allocator
void nethack_zone_restart(void) {
    nh_restart();
}

void nethack_zone_shutdown(void) {
    // Nothing to shutdown with static array
    fprintf(stderr, "[STATIC_ALLOC] Shutdown called (no-op for static array)\n");
}

void nethack_zone_stats(size_t* bytes_allocated, size_t* num_allocations) {
    nh_memory_stats(bytes_allocated, num_allocations);
}

void nethack_zone_print_stats(void) {
    size_t bytes, allocations;
    nh_memory_stats(&bytes, &allocations);
    fprintf(stderr, "[STATIC_ALLOC] Stats: %zu bytes used, %zu allocations\n",
            bytes, allocations);
    fprintf(stderr, "[STATIC_ALLOC] Heap at %p (static array)\n", (void*)nethack_heap);
}

void nethack_zone_switch(ZoneType type) {
    // No-op for static allocator - we don't have separate zones
    fprintf(stderr, "[STATIC_ALLOC] Zone switch to type %d (no-op)\n", type);
}

void nethack_zone_get_metadata(char* buffer, size_t bufsize) {
    if (!buffer || bufsize == 0) return;

    size_t bytes, allocations;
    nh_memory_stats(&bytes, &allocations);

    snprintf(buffer, bufsize,
             "Static Memory: %zu bytes, %zu allocations",
             bytes, allocations);
}

int nethack_zone_snapshot_save(const char* filepath) {
    return nh_save_state(filepath);
}

// Memory management functions for NetHack
void nethack_memory_init(void) {
    nh_restart();
    fprintf(stderr, "[STATIC_ALLOC] NetHack memory initialized\n");
    fprintf(stderr, "[STATIC_ALLOC] Static heap at %p (100MB)\n", (void*)nethack_heap);
}

void nethack_memory_shutdown(void) {
    size_t used, allocations;
    nh_memory_stats(&used, &allocations);
    fprintf(stderr, "[STATIC_ALLOC] Shutdown - %zu bytes, %zu allocations\n",
            used, allocations);
}

int nethack_memory_save(const char* filepath) {
    fprintf(stderr, "[STATIC_ALLOC] Saving memory to %s\n", filepath);
    return nh_save_state(filepath);
}

int nethack_memory_load(const char* filepath) {
    fprintf(stderr, "[STATIC_ALLOC] Loading memory from %s\n", filepath);
    return nh_load_state(filepath);
}

void nethack_memory_stats(void) {
    size_t used, allocations;
    nh_memory_stats(&used, &allocations);
    fprintf(stderr, "[STATIC_ALLOC] Stats: %zu bytes used, %zu allocations\n",
            used, allocations);
}

// NetHack monitoring functions - always provide these
// Even without MONITOR_HEAP, NetHack might use these via macros
long* nhalloc(unsigned int lth, const char* file, int line) {
    return alloc(lth);
}

long* nhrealloc(long* oldptr, unsigned int newlth, const char* file, int line) {
    return re_alloc(oldptr, newlth);
}

void nhfree(void* ptr, const char* file, int line) {
    nh_free(ptr);
}

char* nhdupstr(const char* string, const char* file, int line) {
    return dupstr(string);
}