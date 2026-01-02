/*
 * ios_nhlua_config.h - iOS-specific configuration to disable Lua sandbox
 */

#ifndef IOS_NHLUA_CONFIG_H
#define IOS_NHLUA_CONFIG_H

// Disable NetHack's Lua sandbox on iOS - the OS sandbox is sufficient
#ifdef NHL_SANDBOX
#undef NHL_SANDBOX
#endif

// Force simple Lua initialization
#define SIMPLE_LUA_INIT 1

// iOS already limits memory and CPU
#define NO_LUA_MEMORY_LIMIT 1
#define NO_LUA_STEP_LIMIT 1

#endif /* IOS_NHLUA_CONFIG_H */