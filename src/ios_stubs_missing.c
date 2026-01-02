/*
 * ios_stubs_missing.c - Missing symbol implementations
 */

#include <stdio.h>

/* SAVEF - the save file name, normally in files.c */
char SAVEF[256] = "";

/* File path prefix names - REMOVED: Now in library (decl.o) */
/* const char *fqn_prefix_names[20] - now provided by library */

/* Hangup handler - iOS doesn't use this */
void sethanguphandler(void (*handler)(int)) {
    /* Not needed on iOS */
    (void)handler;
}

/* savegamestate - REMOVED: Now exported from library via patch */
/* void savegamestate(void *nhfp) - now provided by library */