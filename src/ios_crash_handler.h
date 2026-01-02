#ifndef IOS_CRASH_HANDLER_H
#define IOS_CRASH_HANDLER_H

void ios_install_crash_handler(void);
void ios_crash_checkpoint(const char* operation, const char* file, int line);

#define CRASH_CHECKPOINT(op) ios_crash_checkpoint(op, __FILE__, __LINE__)

#endif
