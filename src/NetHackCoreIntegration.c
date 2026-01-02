/*
 * NetHackCoreIntegration.c - Integration with real NetHack functions
 *
 * This file bridges between Swift and the actual compiled NetHack code.
 * We're using the real NetHack functions from alloc.c, rnd.c etc.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "nethack_bridge_common.h"  // For OUTPUT_BUFFER_SIZE

// From NetHack alloc.c - these are REAL NetHack functions!
extern long *alloc(unsigned int);
extern char *dupstr(const char *);
#define nh_strdup dupstr  // NetHack uses dupstr, not nh_strdup

// From NetHack rnd.c - real random functions!
extern int rn2(int);
extern int rnd(int);
extern int d(int, int);

// output_buffer is accessed via the macro in nethack_bridge_common.h
// (calls nethack_get_output_buffer() which returns pointer to the actual buffer)

// === Integration Functions ===

// Version info
const char* NETHACK_VERSION = "3.7.0";
const char* NETHACK_PORT_VERSION = "1.1.0";  // Increased version!

// Test that we can call real NetHack functions
const char* test_nethack_functions(void) {
    memset(output_buffer, 0, OUTPUT_BUFFER_SIZE);

    strlcat(output_buffer, "=== Testing Real NetHack Functions ===\n\n", OUTPUT_BUFFER_SIZE);

    // Test memory allocation from real alloc.c
    long *test_mem = alloc(100);
    if (test_mem) {
        strlcat(output_buffer, "✓ NetHack alloc() works!\n", OUTPUT_BUFFER_SIZE);
        // NetHack doesn't have a free - it uses its own memory management
    }

    // Test string duplication from real alloc.c
    char *test_str = nh_strdup("Hello from NetHack!");
    if (test_str) {
        strlcat(output_buffer, "✓ NetHack nh_strdup() works: ", OUTPUT_BUFFER_SIZE);
        strlcat(output_buffer, test_str, OUTPUT_BUFFER_SIZE);
        strlcat(output_buffer, "\n", OUTPUT_BUFFER_SIZE);
    }

    // Test random functions from real rnd.c
    strlcat(output_buffer, "\n=== Random Number Tests ===\n", OUTPUT_BUFFER_SIZE);

    // Roll some dice using REAL NetHack functions!
    char dice_result[256];
    snprintf(dice_result, sizeof(dice_result), "Rolling 3d6: %d\n", d(3, 6));
    strlcat(output_buffer, dice_result, OUTPUT_BUFFER_SIZE);

    snprintf(dice_result, sizeof(dice_result), "Random 1-100: %d\n", rnd(100));
    strlcat(output_buffer, dice_result, OUTPUT_BUFFER_SIZE);

    snprintf(dice_result, sizeof(dice_result), "Random 0-9: %d\n", rn2(10));
    strlcat(output_buffer, dice_result, OUTPUT_BUFFER_SIZE);

    strlcat(output_buffer, "\n✓ Real NetHack functions are working!\n", OUTPUT_BUFFER_SIZE);
    strlcat(output_buffer, "Next step: Add more NetHack core files\n", OUTPUT_BUFFER_SIZE);

    return output_buffer;
}

// From allmain.c - critical init function
extern void early_init(int argc, char *argv[]);

// Initialize NetHack subsystems
void init_nethack_core(void) {
    // early_init is already called by ios_early_init()
    // We only need to set the random seed here

    // Set random seed using iOS system random
    extern void reseed_random(unsigned long);
    unsigned long seed = arc4random();
    reseed_random(seed);
}

// Get a random dungeon seed using real NetHack RNG
int get_nethack_seed(void) {
    // Use real NetHack random function!
    return rnd(999999);
}