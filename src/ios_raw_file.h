#ifndef IOS_RAW_FILE_H
#define IOS_RAW_FILE_H

#include <stddef.h>

/* Structure to pass raw file data between Swift and C
 * This avoids string conversion issues that corrupt Lua files
 */
typedef struct {
    unsigned char* data;  /* Raw bytes from file */
    size_t size;         /* Actual file size in bytes */
} ios_raw_file_data;

/* Swift function declarations */
extern ios_raw_file_data* ios_swift_load_raw_lua_file(const char* filename);
extern void ios_swift_free_raw_file(ios_raw_file_data* file_data);

#endif /* IOS_RAW_FILE_H */