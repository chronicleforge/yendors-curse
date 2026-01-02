/*
 * ios_container_bridge.h - iOS Bridge for Floor Container Operations
 *
 * Provides functions for transferring items between player inventory
 * and floor containers (bags, boxes, chests on the ground).
 *
 * CRITICAL: This bridges to NetHack's in_container()/out_container()
 * functions in pickup.c. All game logic remains in NetHack.
 */

#ifndef IOS_CONTAINER_BRIDGE_H
#define IOS_CONTAINER_BRIDGE_H

#include <stdbool.h>
#include "nethack_export.h"

/*
 * IOSFloorContainerInfo - Info about a container on the floor
 */
typedef struct {
    unsigned int o_id;      /* Unique object ID */
    char name[256];         /* Container name (from doname) */
    int item_count;         /* Number of items inside */
    bool is_locked;         /* Container is locked */
    bool is_broken;         /* Container is broken (kicked/forced open) */
    bool is_trapped;        /* Container is trapped (if known) */
    int oclass;             /* Object class */
} IOSFloorContainerInfo;

/*
 * IOSContainerItemInfo - Info about an item inside a container
 */
typedef struct {
    unsigned int o_id;      /* Unique object ID */
    char name[256];         /* Item name (from doname) */
    int quantity;           /* Stack quantity */
    int oclass;             /* Object class */
    char buc_status;        /* B=blessed, U=uncursed, C=cursed, ?=unknown */
    bool is_container;      /* Item is also a container */
} IOSContainerItemInfo;

/*
 * ios_get_floor_containers_at_player - Get containers at player position
 *
 * Parameters:
 *   buffer      - Output buffer for container info
 *   max         - Maximum containers to return
 *
 * Returns:
 *   Number of containers found (0 if none)
 */
NETHACK_EXPORT int ios_get_floor_containers_at_player(IOSFloorContainerInfo *buffer, int max);

/*
 * ios_set_current_container - Set the active container by o_id (floor containers)
 *
 * MUST be called before put/take operations.
 *
 * Parameters:
 *   container_o_id - Object ID of the container to use
 *
 * Returns:
 *   1 = success, 0 = container not found or invalid
 */
NETHACK_EXPORT int ios_set_current_container(unsigned int container_o_id);

/*
 * ios_set_inventory_container - Set the active container by inventory letter
 *
 * Use this for containers in the player's inventory (Apply action).
 *
 * Parameters:
 *   invlet - Inventory letter of the container (a-z, A-Z)
 *
 * Returns:
 *   1 = success, 0 = not found, not a container, or locked
 */
NETHACK_EXPORT int ios_set_inventory_container(char invlet);

/*
 * ios_get_inventory_container_id - Get object ID of inventory container
 *
 * Parameters:
 *   invlet - Inventory letter of the container
 *
 * Returns:
 *   Object ID if valid container, 0 otherwise
 */
NETHACK_EXPORT unsigned int ios_get_inventory_container_id(char invlet);

/*
 * ios_put_item_in_container - Put inventory item into current container
 *
 * Parameters:
 *   invlet - Inventory letter of item to put in (a-z, A-Z)
 *
 * Returns:
 *   1 = success, 0 = failed, -1 = Bag of Holding explosion!
 */
NETHACK_EXPORT int ios_put_item_in_container(char invlet);

/*
 * ios_take_item_from_container - Take item from current container
 *
 * Parameters:
 *   item_index - Index in container's item list (0-based)
 *
 * Returns:
 *   1 = success, 0 = failed
 */
NETHACK_EXPORT int ios_take_item_from_container(int item_index);

/*
 * ios_take_all_from_container - Take all items from current container
 *
 * Returns:
 *   Number of items successfully taken
 */
NETHACK_EXPORT int ios_take_all_from_container(void);

/*
 * ios_clear_current_container - Clear the current container reference
 *
 * Call this when closing the container UI.
 */
NETHACK_EXPORT void ios_clear_current_container(void);

/*
 * ios_get_current_container_contents - Get items in current container
 *
 * Parameters:
 *   buffer - Output buffer for item info
 *   max    - Maximum items to return
 *
 * Returns:
 *   Number of items found
 */
NETHACK_EXPORT int ios_get_current_container_contents(IOSContainerItemInfo *buffer, int max);

#endif /* IOS_CONTAINER_BRIDGE_H */
