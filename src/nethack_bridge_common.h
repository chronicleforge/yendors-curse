/*
 * nethack_bridge_common.h - Common definitions for NetHack bridge
 *
 * CRITICAL: Use preprocessor defines for buffer sizes to enable
 * compile-time buffer overflow detection by __strncat_chk.
 *
 * DO NOT use "extern const int" for buffer sizes - this prevents
 * __builtin_object_size() from determining buffer size at compile time!
 */

#ifndef NETHACK_BRIDGE_COMMON_H
#define NETHACK_BRIDGE_COMMON_H

#include "nethack_export.h"  // Symbol visibility control

/* Buffer size constant - MUST remain a preprocessor define for:
 * 1. Static array initialization in ios_dylib_stubs.c
 * 2. Compile-time buffer overflow detection by __strncat_chk
 */
#define OUTPUT_BUFFER_SIZE 8192

/* Accessor function declarations - functions ALWAYS export from dylib */
NETHACK_EXPORT char* nethack_get_output_buffer(void);
NETHACK_EXPORT void nethack_clear_output_buffer(void);
NETHACK_EXPORT size_t nethack_get_output_buffer_size(void);
NETHACK_EXPORT void nethack_append_output(const char* text);

/* Convenience macro for backward compatibility with existing code  */
#define output_buffer (nethack_get_output_buffer())

#endif /* NETHACK_BRIDGE_COMMON_H */
