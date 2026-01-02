/*
 * ios_render_queue.h - Lock-Free SPSC Render Queue for NetHack iOS
 *
 * This implements a Single Producer Single Consumer (SPSC) lock-free queue
 * for passing rendering commands from the NetHack game thread to the Swift UI thread.
 *
 * Design: Based on WINDOWS_C_ARCHITECTURE_DESIGN.md Phase 1
 * Thread Safety: Lock-free atomics (C11) - game thread produces, main thread consumes
 * Performance: Zero-copy for glyphs, strdup for messages
 */

#ifndef IOS_RENDER_QUEUE_H
#define IOS_RENDER_QUEUE_H

#include <stdint.h>
#include <stdatomic.h>
#include <stdbool.h>
#include "nethack_export.h"

/* Forward declarations for NetHack types */
#ifndef COORDXY_DEFINED
typedef short coordxy;
#define COORDXY_DEFINED
#endif

/* Queue size - MUST be power of 2 for efficient masking */
#define RENDER_QUEUE_SIZE 4096

/* === Render Command Types === */

typedef enum {
    UPDATE_GLYPH,      /* Map tile update */
    UPDATE_MESSAGE,    /* Message window */
    UPDATE_STATUS,     /* Status bar */
    CMD_FLUSH_MAP,     /* Display map now */
    CMD_CLEAR_MAP,     /* Clear map buffer */
    CMD_TURN_COMPLETE  /* Turn finished */
} RenderUpdateType;

/* === Command Structures === */

/* Map tile update (zero-copy - integers only) */
typedef struct {
    coordxy x, y;
    int glyph;
    char ch;
    unsigned char color;
    unsigned int glyphflags;  /* MG_PET, MG_RIDDEN, MG_DETECT etc. from display.h */
} MapUpdate;

/* Message update (requires strdup/free) */
typedef struct {
    char *category;    /* MUST BE FREED BY CONSUMER */
    char *text;        /* MUST BE FREED BY CONSUMER */
    int attr;
} MessageUpdate;

/* Status update (value copy - no pointers) */
typedef struct {
    int hp, hpmax;
    int pw, pwmax;
    int level;
    long exp;
    int ac;
    int str, dex, con, intel, wis, cha;
    long gold;
    long moves;
    char align[16];
    int hunger;
    unsigned long conditions; /* BL_CONDITION bitmask (30 flags) */
} StatusUpdate;

/* Command (no data - just signal) */
typedef struct {
    int blocking;
    long turn_number;
} RenderCommand;

/* === Queue Element (Union) === */

typedef struct {
    RenderUpdateType type;
    union {
        MapUpdate map;
        MessageUpdate message;
        StatusUpdate status;
        RenderCommand command;
    } data;
} RenderQueueElement;

/* === SPSC Queue Structure === */

typedef struct {
    /* Atomics for lock-free operation */
    atomic_uint_fast32_t head;  /* Producer writes here */
    atomic_uint_fast32_t tail;  /* Consumer reads here */
    
    /* Queue storage */
    RenderQueueElement elements[RENDER_QUEUE_SIZE];
} RenderQueue;

/* === Queue Operations === */

/* Initialize queue (call once at startup) */
void render_queue_init(RenderQueue *queue);

/* Destroy queue (call at shutdown) */
void render_queue_destroy(RenderQueue *queue);

/* Enqueue element (Producer - Game Thread) */
/* Returns: true if enqueued, false if queue full */
bool render_queue_enqueue(RenderQueue *queue, const RenderQueueElement *elem);

/* Dequeue element (Consumer - Main Thread) */
/* Returns: true if dequeued, false if queue empty */
bool render_queue_dequeue(RenderQueue *queue, RenderQueueElement *elem);

/* Check if queue is empty */
bool render_queue_is_empty(const RenderQueue *queue);

/* Get queue usage stats (for debugging) */
uint32_t render_queue_count(const RenderQueue *queue);

/* === Global Queue Instance === */

/* Global queue pointer (initialized in ios_init_nhwindows) */
extern RenderQueue *g_render_queue;

/* Helper for Swift interop - access global queue pointer */
NETHACK_EXPORT RenderQueue *ios_get_render_queue(void);

/* === Helper Macros === */

/* Mask for power-of-2 wraparound */
#define QUEUE_MASK (RENDER_QUEUE_SIZE - 1)

#endif /* IOS_RENDER_QUEUE_H */
