/*
 * ios_render_queue.c - Lock-Free SPSC Queue Implementation
 *
 * Memory Ordering:
 * - Producer (game thread): memory_order_release on head update
 * - Consumer (main thread): memory_order_acquire on head read
 * - This ensures element writes happen-before consumer reads
 */

#include "ios_render_queue.h"
#include "nethack_export.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Global queue instance (initialized in ios_init_nhwindows) */
RenderQueue *g_render_queue = NULL;

/* === Initialization === */

void render_queue_init(RenderQueue *queue) {
    /* Guard: NULL pointer */
    if (!queue) {
        fprintf(stderr, "[QUEUE] ERROR: NULL queue pointer in init\n");
        return;
    }
    
    /* Initialize atomics to 0 */
    atomic_init(&queue->head, 0);
    atomic_init(&queue->tail, 0);
    
    /* Zero out elements array */
    memset(queue->elements, 0, sizeof(queue->elements));
    
    fprintf(stderr, "[QUEUE] Initialized (size=%d)\n", RENDER_QUEUE_SIZE);
}

void render_queue_destroy(RenderQueue *queue) {
    /* Guard: NULL pointer */
    if (!queue) {
        return;
    }
    
    /* Drain queue and free any allocated message strings */
    RenderQueueElement elem;
    while (render_queue_dequeue(queue, &elem)) {
        if (elem.type == UPDATE_MESSAGE) {
            /* Free strdup'd strings */
            if (elem.data.message.category) {
                free(elem.data.message.category);
            }
            if (elem.data.message.text) {
                free(elem.data.message.text);
            }
        }
    }
    
    fprintf(stderr, "[QUEUE] Destroyed\n");
}

/* === Producer Operations (Game Thread) === */

bool render_queue_enqueue(RenderQueue *queue, const RenderQueueElement *elem) {
    /* Guard: NULL pointers */
    if (!queue) {
        fprintf(stderr, "[QUEUE] ERROR: NULL queue in enqueue\n");
        return false;
    }
    if (!elem) {
        fprintf(stderr, "[QUEUE] ERROR: NULL element in enqueue\n");
        return false;
    }
    
    /* Load current head (relaxed - we own this) */
    uint32_t current_head = atomic_load_explicit(&queue->head, memory_order_relaxed);
    
    /* Calculate next head position with wraparound */
    uint32_t next_head = (current_head + 1) & QUEUE_MASK;
    
    /* Load current tail (acquire - see consumer's writes) */
    uint32_t current_tail = atomic_load_explicit(&queue->tail, memory_order_acquire);
    
    /* Guard: Queue full? */
    if (next_head == current_tail) {
        static uint32_t drop_count = 0;
        drop_count++;
        if (drop_count % 100 == 1) {
            fprintf(stderr, "[QUEUE] WARNING: Queue full! Dropped %u updates\n", drop_count);
        }
        return false;
    }
    
    /* Write element to queue */
    queue->elements[current_head] = *elem;
    
    /* Commit head update (release - make element visible to consumer) */
    atomic_store_explicit(&queue->head, next_head, memory_order_release);
    
    return true;
}

/* === Consumer Operations (Main Thread) === */

__attribute__((visibility("default")))
bool render_queue_dequeue(RenderQueue *queue, RenderQueueElement *elem) {
    /* Guard: NULL pointers */
    if (!queue) {
        fprintf(stderr, "[QUEUE] ERROR: NULL queue in dequeue\n");
        return false;
    }
    if (!elem) {
        fprintf(stderr, "[QUEUE] ERROR: NULL element output in dequeue\n");
        return false;
    }
    
    /* Load current tail (relaxed - we own this) */
    uint32_t current_tail = atomic_load_explicit(&queue->tail, memory_order_relaxed);
    
    /* Load current head (acquire - see producer's writes) */
    uint32_t current_head = atomic_load_explicit(&queue->head, memory_order_acquire);
    
    /* Guard: Queue empty? */
    if (current_tail == current_head) {
        return false;  /* No data available */
    }
    
    /* Read element from queue */
    *elem = queue->elements[current_tail];
    
    /* Calculate next tail position with wraparound */
    uint32_t next_tail = (current_tail + 1) & QUEUE_MASK;
    
    /* Commit tail update (release - make slot available to producer) */
    atomic_store_explicit(&queue->tail, next_tail, memory_order_release);
    
    return true;
}

/* === Utility Functions === */

bool render_queue_is_empty(const RenderQueue *queue) {
    /* Guard: NULL pointer */
    if (!queue) {
        return true;
    }
    
    uint32_t current_tail = atomic_load_explicit(&queue->tail, memory_order_relaxed);
    uint32_t current_head = atomic_load_explicit(&queue->head, memory_order_acquire);
    
    return current_tail == current_head;
}

uint32_t render_queue_count(const RenderQueue *queue) {
    /* Guard: NULL pointer */
    if (!queue) {
        return 0;
    }

    uint32_t current_tail = atomic_load_explicit(&queue->tail, memory_order_relaxed);
    uint32_t current_head = atomic_load_explicit(&queue->head, memory_order_acquire);

    /* Calculate count with wraparound */
    if (current_head >= current_tail) {
        return current_head - current_tail;
    } else {
        return (RENDER_QUEUE_SIZE - current_tail) + current_head;
    }
}

/* Helper for Swift interop - access global queue pointer */
NETHACK_EXPORT RenderQueue *ios_get_render_queue(void) {
    return g_render_queue;
}
