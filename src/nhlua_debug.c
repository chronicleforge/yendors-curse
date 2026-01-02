/*
 * nhlua_debug.c - Debug wrapper for nhl_init to understand why it fails
 */

#include <stdio.h>
#include <stdlib.h>
#include "../NetHack/include/hack.h"
#include "RealNetHackBridge.h"

// External from nhlua.c
extern lua_State* nhl_init(nhl_sandbox_info *sbi);

// Debug wrapper that logs what's happening
lua_State* nhl_init_debug(nhl_sandbox_info *sbi) {
    fprintf(stderr, "[NHL_DEBUG] === nhl_init_debug called ===\n");
    fprintf(stderr, "[NHL_DEBUG] sbi = %p\n", (void*)sbi);
    if (sbi) {
        fprintf(stderr, "[NHL_DEBUG] sbi->flags = 0x%x\n", sbi->flags);
        fprintf(stderr, "[NHL_DEBUG] sbi->memlimit = %u\n", sbi->memlimit);
        fprintf(stderr, "[NHL_DEBUG] sbi->steps = %u\n", sbi->steps);
        fprintf(stderr, "[NHL_DEBUG] sbi->perpcall = %u\n", sbi->perpcall);
    }
    fflush(stderr);

    // Log to our buffer too
    nethack_append_log("[NHL_DEBUG] nhl_init called with sbi=%p", sbi);
    if (sbi) {
        nethack_append_log("[NHL_DEBUG] flags=0x%x memlimit=%u steps=%u perpcall=%u",
                          sbi->flags, sbi->memlimit, sbi->steps, sbi->perpcall);
    }

    fprintf(stderr, "[NHL_DEBUG] Calling real nhl_init...\n");
    fflush(stderr);

    lua_State *L = nhl_init(sbi);

    fprintf(stderr, "[NHL_DEBUG] nhl_init returned: %p\n", (void*)L);
    fflush(stderr);

    nethack_append_log("[NHL_DEBUG] nhl_init returned L=%p", L);

    if (!L) {
        fprintf(stderr, "[NHL_DEBUG] nhl_init FAILED!\n");
        fprintf(stderr, "[NHL_DEBUG] Possible reasons:\n");
        fprintf(stderr, "[NHL_DEBUG] 1. Memory allocation failed in nhlL_newstate\n");
        fprintf(stderr, "[NHL_DEBUG] 2. lua_newstate returned NULL\n");
        fprintf(stderr, "[NHL_DEBUG] 3. Sandbox restrictions too strict\n");

        // Try without sandbox to test
        fprintf(stderr, "[NHL_DEBUG] Testing basic lua_newstate...\n");
        lua_State *test = lua_newstate(NULL, NULL);
        if (test) {
            fprintf(stderr, "[NHL_DEBUG] Basic lua_newstate works! Problem is in nhl_init\n");
            lua_close(test);
        } else {
            fprintf(stderr, "[NHL_DEBUG] Even basic lua_newstate fails!\n");
        }
    }

    fflush(stderr);
    return L;
}

// Override l_nhcore_init to use our debug version
void l_nhcore_init_debug(void) {
    nhl_sandbox_info sbi = {NHL_SB_SAFE, 1*1024*1024, 0, 1*1024*1024};

    fprintf(stderr, "[NHL_DEBUG] l_nhcore_init_debug starting...\n");
    fflush(stderr);

    nethack_append_log("[NHL_DEBUG] l_nhcore_init_debug starting");

    lua_State *L = nhl_init_debug(&sbi);

    if (!L) {
        fprintf(stderr, "[NHL_DEBUG] Failed to create Lua core!\n");

        // Dump all logs
        extern const char* nethack_get_lua_logs(void);
        fprintf(stderr, "[NHL_DEBUG] === ALL LUA LOGS ===\n%s\n=== END LOGS ===\n",
                nethack_get_lua_logs());
        fflush(stderr);
    } else {
        fprintf(stderr, "[NHL_DEBUG] Lua core created successfully!\n");
    }
}