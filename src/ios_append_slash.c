/*
 * ios_append_slash.c - iOS version of append_slash function
 *
 * Required when NOCWD_ASSUMPTIONS is defined
 */

#include <string.h>

#ifdef NOCWD_ASSUMPTIONS
/* Append a slash to a path if it doesn't have one - iOS/Unix version */
void append_slash(char *name) {
    char *ptr;

    if (!*name)
        return;

    ptr = name + (strlen(name) - 1);
    if (*ptr != '/' && *ptr != ':') {
        *++ptr = '/';  /* Use Unix slash for iOS */
        *++ptr = '\0';
    }
}
#endif