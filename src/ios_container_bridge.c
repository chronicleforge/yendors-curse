/*
 * ios_container_bridge.c - iOS Bridge for Floor Container Operations
 *
 * Implements transfer operations between player inventory and floor containers.
 * Uses NetHack's in_container()/out_container() for actual game logic.
 *
 * THREAD SAFETY:
 * All public functions are protected by container_mutex to prevent race
 * conditions between SwiftUI (main thread) and game thread accessing
 * inventory/object lists.
 */

#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include "ios_container_bridge.h"
#include "../NetHack/include/hack.h"

/* External declarations */
extern struct instance_globals_c gc;
extern struct instance_globals_i gi;
extern struct you u;
extern struct sinfo program_state;

/* Forward declarations for NetHack functions (from extern.h) */
extern char *doname(struct obj *);
extern void freeinv(struct obj *);
extern struct obj *addinv(struct obj *);
extern void obj_extract_self(struct obj *);
extern struct obj *add_to_container(struct obj *, struct obj *);
/* Note: Is_container() and Has_contents() are macros from obj.h, included via hack.h */

/*
 * Thread safety mutex for container operations.
 * Protects access to ios_current_container and all NetHack game state
 * accessed by this bridge (gi.invent, svl.level.objects, etc.)
 */
static pthread_mutex_t container_mutex = PTHREAD_MUTEX_INITIALIZER;

/* Static container reference for operations - protected by container_mutex */
static struct obj *ios_current_container = NULL;

/*
 * Find object by o_id in a chain
 */
static struct obj *find_obj_in_chain(struct obj *chain, unsigned int o_id) {
    struct obj *obj;
    for (obj = chain; obj; obj = obj->nobj) {
        if (obj->o_id == o_id) {
            return obj;
        }
    }
    return NULL;
}

/*
 * Find object by o_id on floor at position
 */
static struct obj *find_floor_obj(int x, int y, unsigned int o_id) {
    struct obj *obj;

    if (x < 0 || x >= COLNO || y < 0 || y >= ROWNO) {
        return NULL;
    }

    for (obj = svl.level.objects[x][y]; obj; obj = obj->nexthere) {
        if (obj->o_id == o_id) {
            return obj;
        }
    }
    return NULL;
}

/*
 * Count items in a container
 */
static int count_container_items(struct obj *container) {
    int count = 0;
    struct obj *obj;

    if (!container || !Has_contents(container)) {
        return 0;
    }

    for (obj = container->cobj; obj; obj = obj->nobj) {
        count++;
        if (count > 5000) break; /* Safety limit */
    }
    return count;
}

/*
 * Get BUC status character
 */
static char get_buc_char(struct obj *obj) {
    if (!obj->bknown) return '?';
    if (obj->blessed) return 'B';
    if (obj->cursed) return 'C';
    return 'U';
}

/* ========== Public API ========== */

NETHACK_EXPORT int ios_get_floor_containers_at_player(IOSFloorContainerInfo *buffer, int max) {
    struct obj *obj;
    int count = 0;
    const char *name;

    if (!buffer || max <= 0) {
        return 0;
    }

    pthread_mutex_lock(&container_mutex);

    /* Check game state */
    if (program_state.gameover || !program_state.something_worth_saving) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Iterate floor objects at player position */
    for (obj = svl.level.objects[u.ux][u.uy]; obj && count < max; obj = obj->nexthere) {
        if (!Is_container(obj)) {
            continue;
        }

        /* Fill info struct */
        buffer[count].o_id = obj->o_id;
        buffer[count].item_count = count_container_items(obj);
        buffer[count].is_locked = (obj->olocked != 0);
        buffer[count].is_broken = (obj->obroken != 0);
        buffer[count].is_trapped = (obj->otrapped != 0);
        buffer[count].oclass = obj->oclass;

        /* Copy name immediately (doname uses circular buffer) */
        name = doname(obj);
        if (name) {
            strncpy(buffer[count].name, name, 255);
            buffer[count].name[255] = '\0';
        } else {
            strcpy(buffer[count].name, "container");
        }

        fprintf(stderr, "[IOS_CONTAINER] Scanned: %s (o_id=%u, locked=%d, broken=%d, trapped=%d)\n",
                buffer[count].name, buffer[count].o_id,
                buffer[count].is_locked, buffer[count].is_broken, buffer[count].is_trapped);

        count++;
    }

    fprintf(stderr, "[IOS_CONTAINER] Found %d floor containers at (%d,%d)\n",
            count, u.ux, u.uy);

    pthread_mutex_unlock(&container_mutex);
    return count;
}

NETHACK_EXPORT int ios_set_current_container(unsigned int container_o_id) {
    struct obj *container;

    pthread_mutex_lock(&container_mutex);

    if (program_state.gameover || !program_state.something_worth_saving) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Find container on floor at player position */
    container = find_floor_obj(u.ux, u.uy, container_o_id);

    if (!container) {
        fprintf(stderr, "[IOS_CONTAINER] Container o_id=%u not found at player position\n",
                container_o_id);
        ios_current_container = NULL;
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (!Is_container(container)) {
        fprintf(stderr, "[IOS_CONTAINER] Object o_id=%u is not a container\n",
                container_o_id);
        ios_current_container = NULL;
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (container->olocked) {
        fprintf(stderr, "[IOS_CONTAINER] Container o_id=%u is locked\n",
                container_o_id);
        ios_current_container = NULL;
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    ios_current_container = container;
    gc.current_container = container; /* NetHack global */

    fprintf(stderr, "[IOS_CONTAINER] Set current container: %s (o_id=%u)\n",
            doname(container), container_o_id);

    pthread_mutex_unlock(&container_mutex);
    return 1;
}

/*
 * Set current container from inventory item by invlet
 * This allows opening containers that are in the player's inventory
 */
NETHACK_EXPORT int ios_set_inventory_container(char invlet) {
    struct obj *container;

    pthread_mutex_lock(&container_mutex);

    if (program_state.gameover || !program_state.something_worth_saving) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Find container in inventory */
    for (container = gi.invent; container; container = container->nobj) {
        if (container->invlet == invlet) {
            break;
        }
    }

    if (!container) {
        fprintf(stderr, "[IOS_CONTAINER] Inventory item '%c' not found\n", invlet);
        ios_current_container = NULL;
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (!Is_container(container)) {
        fprintf(stderr, "[IOS_CONTAINER] Inventory item '%c' is not a container\n", invlet);
        ios_current_container = NULL;
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (container->olocked) {
        fprintf(stderr, "[IOS_CONTAINER] Container '%c' is locked\n", invlet);
        ios_current_container = NULL;
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    ios_current_container = container;
    gc.current_container = container; /* NetHack global */

    fprintf(stderr, "[IOS_CONTAINER] Set current inventory container: %s (invlet='%c', o_id=%u)\n",
            doname(container), invlet, container->o_id);

    pthread_mutex_unlock(&container_mutex);
    return 1;
}

/*
 * Get inventory container info by invlet
 * Returns the container's o_id for use with ContainerTransferView
 */
NETHACK_EXPORT unsigned int ios_get_inventory_container_id(char invlet) {
    struct obj *container;
    unsigned int result = 0;

    pthread_mutex_lock(&container_mutex);

    if (program_state.gameover || !program_state.something_worth_saving) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Find container in inventory */
    for (container = gi.invent; container; container = container->nobj) {
        if (container->invlet == invlet) {
            if (Is_container(container)) {
                result = container->o_id;
            }
            break;
        }
    }

    pthread_mutex_unlock(&container_mutex);
    return result;
}

NETHACK_EXPORT int ios_put_item_in_container(char invlet) {
    struct obj *obj;
    struct obj *target_container;

    pthread_mutex_lock(&container_mutex);

    if (program_state.gameover || !program_state.something_worth_saving) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (!ios_current_container) {
        fprintf(stderr, "[IOS_CONTAINER] No current container set\n");
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Cache container pointer before any operations */
    target_container = ios_current_container;

    /* Find item in inventory by letter */
    for (obj = gi.invent; obj; obj = obj->nobj) {
        if (obj->invlet == invlet) {
            break;
        }
    }

    if (!obj) {
        fprintf(stderr, "[IOS_CONTAINER] Item '%c' not found in inventory\n", invlet);
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Can't put container into itself */
    if (obj == target_container) {
        fprintf(stderr, "[IOS_CONTAINER] Cannot put container into itself\n");
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    fprintf(stderr, "[IOS_CONTAINER] Putting %s into container\n", doname(obj));

    /* Remove from inventory */
    freeinv(obj);

    /* Re-verify container is still valid after freeinv() */
    if (!target_container || !Is_container(target_container)) {
        fprintf(stderr, "[IOS_CONTAINER] Container became invalid during transfer\n");
        /* Try to put item back in inventory */
        (void) addinv(obj);
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Add to container */
    (void) add_to_container(target_container, obj);

    fprintf(stderr, "[IOS_CONTAINER] Item transferred to container\n");

    pthread_mutex_unlock(&container_mutex);
    return 1;
}

NETHACK_EXPORT int ios_take_item_from_container(int item_index) {
    struct obj *obj;
    int i;

    pthread_mutex_lock(&container_mutex);

    if (program_state.gameover || !program_state.something_worth_saving) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (!ios_current_container) {
        fprintf(stderr, "[IOS_CONTAINER] No current container set\n");
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (!Has_contents(ios_current_container)) {
        fprintf(stderr, "[IOS_CONTAINER] Container is empty\n");
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Find item by index */
    obj = ios_current_container->cobj;
    for (i = 0; obj && i < item_index; i++) {
        obj = obj->nobj;
    }

    if (!obj) {
        fprintf(stderr, "[IOS_CONTAINER] Item index %d not found\n", item_index);
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    fprintf(stderr, "[IOS_CONTAINER] Taking %s from container\n", doname(obj));

    /* Extract from container and add to inventory */
    obj_extract_self(obj);
    (void) addinv(obj);

    fprintf(stderr, "[IOS_CONTAINER] Item transferred to inventory\n");

    pthread_mutex_unlock(&container_mutex);
    return 1;
}

NETHACK_EXPORT int ios_take_all_from_container(void) {
    struct obj *obj, *next;
    int count = 0;

    pthread_mutex_lock(&container_mutex);

    if (program_state.gameover || !program_state.something_worth_saving) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (!ios_current_container) {
        fprintf(stderr, "[IOS_CONTAINER] No current container set\n");
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    /* Take items one by one (safe iteration since extraction modifies list) */
    obj = ios_current_container->cobj;
    while (obj) {
        next = obj->nobj; /* Save next before modification */

        obj_extract_self(obj);
        (void) addinv(obj);
        count++;

        obj = next;
    }

    fprintf(stderr, "[IOS_CONTAINER] Took %d items from container\n", count);

    pthread_mutex_unlock(&container_mutex);
    return count;
}

NETHACK_EXPORT void ios_clear_current_container(void) {
    pthread_mutex_lock(&container_mutex);
    fprintf(stderr, "[IOS_CONTAINER] Clearing current container\n");
    ios_current_container = NULL;
    gc.current_container = NULL;
    pthread_mutex_unlock(&container_mutex);
}

NETHACK_EXPORT int ios_get_current_container_contents(IOSContainerItemInfo *buffer, int max) {
    struct obj *obj;
    int count = 0;
    const char *name;

    if (!buffer || max <= 0) {
        return 0;
    }

    pthread_mutex_lock(&container_mutex);

    if (program_state.gameover || !program_state.something_worth_saving) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (!ios_current_container) {
        fprintf(stderr, "[IOS_CONTAINER] No current container set\n");
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    if (!Has_contents(ios_current_container)) {
        pthread_mutex_unlock(&container_mutex);
        return 0;
    }

    for (obj = ios_current_container->cobj; obj && count < max; obj = obj->nobj) {
        buffer[count].o_id = obj->o_id;
        buffer[count].quantity = obj->quan;
        buffer[count].oclass = obj->oclass;
        buffer[count].buc_status = get_buc_char(obj);
        buffer[count].is_container = Is_container(obj);

        /* Copy name immediately */
        name = doname(obj);
        if (name) {
            strncpy(buffer[count].name, name, 255);
            buffer[count].name[255] = '\0';
        } else {
            strcpy(buffer[count].name, "item");
        }

        count++;
    }

    pthread_mutex_unlock(&container_mutex);
    return count;
}
