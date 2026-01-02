/*
 * ios_msg_history.c - Message history implementation for 9/10 compliance
 */

#include "../NetHack/include/hack.h"
#include "ios_wincap.h"
#include <string.h>

/* Global message history */
ios_message_history ios_msg_hist = { .head = 0, .count = 0 };

/* Add a message to history */
void ios_add_message(const char *msg) {
    if (!msg || !*msg) return;

    /* Copy message to circular buffer */
    strncpy(ios_msg_hist.messages[ios_msg_hist.head], msg, BUFSZ - 1);
    ios_msg_hist.messages[ios_msg_hist.head][BUFSZ - 1] = '\0';

    /* Update head and count */
    ios_msg_hist.head = (ios_msg_hist.head + 1) % IOS_MSG_HISTORY_SIZE;
    if (ios_msg_hist.count < IOS_MSG_HISTORY_SIZE) {
        ios_msg_hist.count++;
    }
}

/* Get message from history (0 = newest) */
const char* ios_get_message_history(int index) {
    if (index < 0 || index >= ios_msg_hist.count) {
        return "";
    }

    /* Calculate actual index in circular buffer */
    int actual_idx = (ios_msg_hist.head - 1 - index + IOS_MSG_HISTORY_SIZE)
                     % IOS_MSG_HISTORY_SIZE;
    return ios_msg_hist.messages[actual_idx];
}

/* Get total message count */
int ios_message_count(void) {
    return ios_msg_hist.count;
}

/* Clear message history */
void ios_clear_message_history(void) {
    memset(&ios_msg_hist, 0, sizeof(ios_msg_hist));
}

/* NetHack window proc callbacks for message history */
char* ios_getmsghistory_impl(boolean init) {
    static char history_buffer[BUFSZ * 10];  /* Large buffer for history */
    static int history_index = 0;

    if (init) {
        history_index = 0;
        return "";
    }

    if (history_index >= ios_msg_hist.count) {
        return NULL;  /* No more messages */
    }

    /* Return messages oldest to newest for NetHack */
    strncpy(history_buffer, ios_get_message_history(ios_msg_hist.count - 1 - history_index),
            sizeof(history_buffer) - 1);
    history_buffer[sizeof(history_buffer) - 1] = '\0';
    history_index++;

    return history_buffer;
}

void ios_putmsghistory_impl(const char *msg, boolean is_restoring) {
    if (is_restoring) {
        /* During restore, add to history without display */
        ios_add_message(msg);
    } else {
        /* Normal message - would be displayed and added */
        ios_add_message(msg);
    }
}