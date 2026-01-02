/*
 * ios_trace.h - Tracing utilities for debugging hangs
 */

#ifndef IOS_TRACE_H
#define IOS_TRACE_H

#include <stdio.h>

// Trace point function - implemented in ios_stubs.c
extern void ios_trace_point(const char* msg);

// Macro for easy tracing
#define IOS_TRACE(msg) do { \
    fprintf(stderr, "[TRACE] %s:%d: %s\n", __FILE__, __LINE__, msg); \
    fflush(stderr); \
} while(0)

// Macro for tracing with function name
#define IOS_TRACE_FUNC() do { \
    fprintf(stderr, "[TRACE_FUNC] %s:%d: %s()\n", __FILE__, __LINE__, __func__); \
    fflush(stderr); \
} while(0)

// Macro for tracing with value
#define IOS_TRACE_VAL(msg, val) do { \
    fprintf(stderr, "[TRACE_VAL] %s:%d: %s = %d\n", __FILE__, __LINE__, msg, (int)(val)); \
    fflush(stderr); \
} while(0)

#endif /* IOS_TRACE_H */