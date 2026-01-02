#ifndef IOS_YN_CALLBACK_H
#define IOS_YN_CALLBACK_H

// YN Response modes
typedef enum {
    YN_MODE_AUTO_YES,      // Automatically answer yes
    YN_MODE_AUTO_NO,       // Automatically answer no
    YN_MODE_ASK_USER,      // Forward to UI for user confirmation
    YN_MODE_DEFAULT        // Use NetHack's default answer
} yn_response_mode_t;

// YN callback function type
// Returns the character to respond with ('y', 'n', or other)
typedef char (*yn_callback_func)(const char *query, const char *resp, char def, yn_response_mode_t mode);

// Set the yn callback mode for the next yn_function call
void ios_set_yn_mode(yn_response_mode_t mode);

// Set a custom callback function (for complex logic)
void ios_set_yn_callback(yn_callback_func callback);

// Get the current yn mode
yn_response_mode_t ios_get_yn_mode(void);

// Swift-callable functions
void ios_set_next_yn_response(char response);  // Set specific response for next call
void ios_enable_yn_auto_yes(void);             // Auto-yes mode
void ios_enable_yn_auto_no(void);              // Auto-no mode
void ios_enable_yn_ask_user(void);             // UI mode

#endif /* IOS_YN_CALLBACK_H */