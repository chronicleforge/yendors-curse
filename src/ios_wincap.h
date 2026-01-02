/*
 * ios_wincap.h - iOS Window Capabilities for 9/10 compliance
 */

#ifndef IOS_WINCAP_H
#define IOS_WINCAP_H

/* iOS Window Port ID */
#define WC_IOS 0x1000

/* === WINDOW CAPABILITIES FOR 9/10 COMPLIANCE === */

/* Display Features */
#define WC2_FULLSTATUSCOLOR     0x0001L /* can show status colors */
#define WC2_HITPOINTBAR         0x0002L /* can show HP as bar */
#define WC2_FLUSH_STATUS        0x0004L /* call status_update(BL_FLUSH) */
#define WC2_RESET_STATUS        0x0008L /* supports status reset */
#define WC2_HILITE_STATUS       0x0010L /* can highlight status changes */
#define WC2_TERM_SIZE           0x0020L /* supports terminal size query */
#define WC2_STATUSLINES         0x0040L /* supports variable status lines */

/* Input/Menu Features */
#define WC2_SELECTSAVED         0x0080L /* can select from saved games */
#define WC2_DARKGRAY            0x0100L /* can display dark gray */
#define WC2_ALPHA_MAP           0x0200L /* can show transparent map */
#define WC2_EIGHT_BIT_IN        0x0400L /* can input 8-bit characters */
#define WC2_PERM_INVENT         0x0800L /* has permanent inventory window */
#define WC2_MOUSE_STATUS        0x1000L /* can click on status */
#define WC2_HOTSPOT_MAP         0x2000L /* can click anywhere on map */
#define WC2_MENU_SHIFT          0x4000L /* menus can shift position */
#define WC2_PETATTR             0x8000L /* can show pet highlighting */

/* iOS Supported Capabilities */
#define IOS_WINCAP2 (WC2_FULLSTATUSCOLOR | WC2_HITPOINTBAR | \
                    WC2_FLUSH_STATUS | WC2_RESET_STATUS | \
                    WC2_HILITE_STATUS | WC2_TERM_SIZE | \
                    WC2_STATUSLINES | WC2_DARKGRAY | \
                    WC2_PERM_INVENT | WC2_MOUSE_STATUS | \
                    WC2_HOTSPOT_MAP | WC2_PETATTR)

/* Message History for iOS */
#define IOS_MSG_HISTORY_SIZE 100

typedef struct ios_message_history {
    char messages[IOS_MSG_HISTORY_SIZE][BUFSZ];
    int head;
    int count;
} ios_message_history;

/* Global message history */
extern ios_message_history ios_msg_hist;

/* Message history functions */
void ios_add_message(const char *msg);
const char* ios_get_message_history(int index);
int ios_message_count(void);
void ios_clear_message_history(void);

#endif /* IOS_WINCAP_H */