/* NetHack iOS Port - Symbol Export Control
 *
 * This header defines symbol visibility for the NetHack dylib.
 * Only functions marked with NETHACK_EXPORT are visible to Swift code.
 * All other symbols remain internal to the dylib.
 *
 * With -fvisibility=hidden, only explicitly exported functions are
 * accessible from Swift, reducing the public API surface from 4000+
 * symbols to approximately 125 bridge functions.
 */

#ifndef NETHACK_EXPORT_H
#define NETHACK_EXPORT_H

/* Mark function as publicly visible in dylib */
#define NETHACK_EXPORT __attribute__((visibility("default")))

#endif /* NETHACK_EXPORT_H */
