/*
 * nethack_version.h - Version information for NetHack iOS Library
 *
 * This file defines version constants for the NetHack bridge library
 * to ensure compatibility between Swift UI and C library.
 */

#ifndef NETHACK_VERSION_H
#define NETHACK_VERSION_H

// Library version - increment for releases
#define NETHACK_LIB_VERSION_MAJOR 1
#define NETHACK_LIB_VERSION_MINOR 4
#define NETHACK_LIB_VERSION_PATCH 4

// Full version string
#define NETHACK_LIB_VERSION "1.4.4-BOULDER-CACHE-REFRESH"

// API version - increment when breaking changes occur
#define NETHACK_LIB_API_VERSION 1

// Build information
#define NETHACK_LIB_BUILD_DATE __DATE__
#define NETHACK_LIB_BUILD_TIME __TIME__

// Feature flags
#define NETHACK_HAS_CHARACTER_CREATION 1
#define NETHACK_HAS_3D_PREVIEW 1
#define NETHACK_HAS_TOUCH_CONTROLS 1

// Platform info
#define NETHACK_TARGET_PLATFORM "iOS"
#define NETHACK_TARGET_ARCH "arm64"

#endif /* NETHACK_VERSION_H */