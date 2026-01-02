/* Minimal config for iOS port */
#ifndef IOS_CONFIG_H
#define IOS_CONFIG_H

/* Platform settings */
#define UNIX
#define BSD
#define NO_SIGNAL

/* Enable Lua support - we have it compiled */
/* Note: CROSSCOMPILE removed to enable Lua */

/* Disable terminal capabilities */
#define NO_TERMS
#define NO_TERMCAP_HEADERS

/* Zone-based memory management */
#ifdef USE_ZONE_ALLOCATOR
#include "nethack_zone.h"
#endif

/* Stubs for missing functions */
#define strcmpi(s1,s2) strcasecmp(s1,s2)
/* strncmpi is already in NetHack's hacklib.h */

#endif
