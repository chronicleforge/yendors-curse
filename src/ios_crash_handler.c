#include "ios_crash_handler.h"
#include <signal.h>
#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char* last_operation = "unknown";
static const char* last_file = "unknown";
static int last_line = 0;

void ios_crash_checkpoint(const char* operation, const char* file, int line) {
    if (!operation) operation = "NULL";
    if (!file) file = "NULL";

    last_operation = operation;
    last_file = file;
    last_line = line;
    fprintf(stderr, "[CHECKPOINT] %s at %s:%d\n", operation, file, line);
    fflush(stderr);
}

static void crash_handler(int sig) {
    const char* sig_name = "UNKNOWN";
    switch(sig) {
        case SIGSEGV: sig_name = "SIGSEGV"; break;
        case SIGABRT: sig_name = "SIGABRT"; break;
        case SIGBUS:  sig_name = "SIGBUS"; break;
        case SIGFPE:  sig_name = "SIGFPE"; break;
    }

    fprintf(stderr, "\n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "          CRASH DETECTED                \n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "Signal: %s\n", sig_name);
    fprintf(stderr, "Last operation: %s\n", last_operation);
    fprintf(stderr, "File: %s\n", last_file);
    fprintf(stderr, "Line: %d\n", last_line);
    fprintf(stderr, "========================================\n");

    void* callstack[128];
    int frames = backtrace(callstack, 128);
    char** symbols = backtrace_symbols(callstack, frames);

    if (symbols) {
        fprintf(stderr, "\nStack trace (%d frames):\n", frames);
        for (int i = 0; i < frames; i++) {
            fprintf(stderr, "  %d: %s\n", i, symbols[i]);
        }
        free(symbols);
    }

    fflush(stderr);

    signal(sig, SIG_DFL);
    raise(sig);
}

void ios_install_crash_handler(void) {
    fprintf(stderr, "[CRASH_HANDLER] Installing signal handlers...\n");
    signal(SIGSEGV, crash_handler);
    signal(SIGABRT, crash_handler);
    signal(SIGBUS, crash_handler);
    signal(SIGFPE, crash_handler);
    fprintf(stderr, "[CRASH_HANDLER] Handlers installed for SIGSEGV, SIGABRT, SIGBUS, SIGFPE\n");
    fflush(stderr);
}
