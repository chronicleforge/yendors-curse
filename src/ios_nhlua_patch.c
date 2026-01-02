// iOS patch for nhlua.c - fixes for non-sandbox build
// This file provides missing functions when NHL_SANDBOX is undefined

#include "../NetHack/include/hack.h"
#include "../NetHack/include/nhlua.h"
#include "../zone_allocator/nethack_zone.h"
#include <stdio.h>
#include <stdlib.h>

// Zone-based memory allocator for iOS Lua
void* nhl_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    static int alloc_count = 0;
    (void)ud;    // unused without sandbox
    (void)osize; // unused

    alloc_count++;
    if (alloc_count < 10) {  // Only log first few allocations
        fprintf(stderr, "[NHL_ALLOC] #%d: ptr=%p, osize=%zu, nsize=%zu\n",
                alloc_count, ptr, osize, nsize);
    }

    if (nsize == 0) {
        if (ptr) zone_free(ptr);
        return NULL;
    } else {
        // Use re_alloc from zone allocator
        void *result = re_alloc((long*)ptr, nsize);
        if (alloc_count < 10) {
            fprintf(stderr, "[NHL_ALLOC] #%d: returning %p\n", alloc_count, result);
        }
        return result;
    }
}

// Simple panic handler for iOS
int nhl_panic(lua_State *L) {
    const char *msg = lua_tostring(L, -1);
    if (!msg) msg = "Lua panic (no error message)";

    fprintf(stderr, "[LUA PANIC] %s\n", msg);

    // Don't call NetHack's panic in debug mode - just abort
    abort();
    return 0;
}

#if LUA_VERSION_NUM == 504
// Simple warning handler for Lua 5.4
void nhl_warn(void *ud, const char *msg, int tocont) {
    (void)ud;
    fprintf(stderr, "[LUA WARN] %s%s\n", msg, tocont ? " (continued)" : "");
}
#endif