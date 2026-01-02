/*
 * nethack_safe.h - Safe utility functions for NetHack iOS port
 *
 * Provides defensive programming utilities:
 * - Safe buffer operations
 * - Coordinate validation
 * - Path length checking
 */

#ifndef NETHACK_SAFE_H
#define NETHACK_SAFE_H

#include <stdio.h>
#include <string.h>
#include <stdbool.h>

/* ============================================================================
 * SAFE BUFFER OPERATIONS
 * ============================================================================ */

/**
 * Safe append to buffer with overflow protection
 * Returns: true if appended successfully, false if truncated
 */
static inline bool safe_buffer_append(char *buffer, size_t buffer_size, const char *str) {
    if (!buffer || !str || buffer_size == 0) return false;

    size_t current_len = strlen(buffer);
    size_t str_len = strlen(str);
    size_t available = buffer_size - current_len - 1; /* -1 for null terminator */

    if (str_len >= available) {
        /* Would overflow - truncate safely */
        if (available > 0) {
            strncat(buffer, str, available);
        }
        return false; /* Indicate truncation occurred */
    }

    strcat(buffer, str);
    return true;
}

/**
 * Safe snprintf with validation
 * Returns: true if successful, false if truncated or error
 */
static inline bool safe_snprintf(char *buffer, size_t size, const char *format, ...) {
    if (!buffer || !format || size == 0) return false;

    va_list args;
    va_start(args, format);
    int result = vsnprintf(buffer, size, format, args);
    va_end(args);

    /* Check for error or truncation */
    return (result >= 0 && result < (int)size);
}

/* ============================================================================
 * COORDINATE VALIDATION
 * ============================================================================ */

/* NetHack map dimensions */
#ifndef COLNO
#define COLNO 80  /* Number of columns */
#endif
#ifndef ROWNO
#define ROWNO 21  /* Number of rows */
#endif
#ifndef MAP_Y_OFFSET
#define MAP_Y_OFFSET 2  /* Message lines at top */
#endif

/**
 * Validate map coordinates
 * Returns: true if valid, false otherwise
 */
static inline bool validate_map_coords(int x, int y) {
    return (x >= 0 && x < COLNO && y >= 0 && y < ROWNO);
}

/**
 * Validate buffer coordinates
 * Returns: true if valid, false otherwise
 */
static inline bool validate_buffer_coords(int buffer_x, int buffer_y) {
    /* Buffer includes message area at top */
    return (buffer_x >= 0 && buffer_x < COLNO &&
            buffer_y >= 0 && buffer_y < ROWNO + MAP_Y_OFFSET);
}

/**
 * Convert buffer to map coordinates with validation
 * Returns: true if conversion valid, false otherwise
 */
static inline bool buffer_to_map_coords(int buffer_x, int buffer_y,
                                        int *map_x, int *map_y) {
    if (!map_x || !map_y) return false;

    /* Validate buffer coordinates first */
    if (!validate_buffer_coords(buffer_x, buffer_y)) {
        return false;
    }

    /* Convert */
    *map_x = buffer_x;
    *map_y = buffer_y - MAP_Y_OFFSET;

    /* Validate result */
    return validate_map_coords(*map_x, *map_y);
}

/* ============================================================================
 * PATH VALIDATION
 * ============================================================================ */

/**
 * Build path safely with validation
 * Returns: true if successful, false if path too long
 */
static inline bool safe_build_path(char *dest, size_t dest_size,
                                   const char *dir, const char *file) {
    if (!dest || !dir || !file || dest_size == 0) return false;

    int len = snprintf(dest, dest_size, "%s/%s", dir, file);

    /* Check for error or truncation */
    if (len < 0 || len >= (int)dest_size) {
        /* Clear buffer on failure */
        dest[0] = '\0';
        return false;
    }

    return true;
}

/**
 * Validate path is not NULL or empty
 * Returns: true if valid, false otherwise
 */
static inline bool validate_path(const char *path) {
    return (path != NULL && path[0] != '\0');
}

/* ============================================================================
 * DEFENSIVE MACROS
 * ============================================================================ */

/**
 * Guard clause helper - return on NULL
 */
#define GUARD_NULL(ptr, retval) \
    do { \
        if (!(ptr)) { \
            fprintf(stderr, "[GUARD] NULL pointer at %s:%d\n", __FILE__, __LINE__); \
            return (retval); \
        } \
    } while(0)

/**
 * Guard clause helper - return on false condition
 */
#define GUARD_FALSE(condition, retval, msg) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "[GUARD] %s at %s:%d\n", (msg), __FILE__, __LINE__); \
            return (retval); \
        } \
    } while(0)

/**
 * Safe free and NULL
 */
#define SAFE_FREE(ptr) \
    do { \
        if (ptr) { \
            free(ptr); \
            (ptr) = NULL; \
        } \
    } while(0)

/**
 * Safe file close
 */
#define SAFE_FCLOSE(fp) \
    do { \
        if (fp) { \
            fclose(fp); \
            (fp) = NULL; \
        } \
    } while(0)

#endif /* NETHACK_SAFE_H */