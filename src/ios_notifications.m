/*
 * ios_notifications.m - iOS notification posting for Swift UI
 *
 * This Objective-C file handles NSNotificationCenter posting for
 * the message system. Separated from RealNetHackBridge.c to avoid
 * compiling the entire bridge as Objective-C.
 */

#import <Foundation/Foundation.h>

// Post a NetHack message notification to Swift UI
void ios_post_message_notification(const char* message, const char* category, int attr) {
    // Guard 1: NULL pointer check
    if (!message) {
        fprintf(stderr, "[IOS_NOTIF] WARNING: NULL message pointer, skipping\n");
        return;
    }

    // Guard 2: Empty string check
    if (message[0] == '\0') {
        fprintf(stderr, "[IOS_NOTIF] WARNING: Empty message, skipping\n");
        return;
    }

    // CRITICAL FIX: Validate UTF-8 and handle encoding failures
    // NetHack uses extended ASCII (Latin-1) and control codes, not always valid UTF-8!
    NSString *messageCopy = [NSString stringWithUTF8String:message];

    // Guard 3: Handle invalid UTF-8 (root cause of crash)
    if (!messageCopy) {
        // Fallback 1: Try Latin-1 encoding (common for NetHack extended ASCII)
        messageCopy = [NSString stringWithCString:message encoding:NSISOLatin1StringEncoding];

        if (!messageCopy) {
            // Fallback 2: Create placeholder to prevent crash
            messageCopy = [NSString stringWithFormat:@"[Invalid message encoding: %zu bytes]",
                          strlen(message)];
            fprintf(stderr, "[IOS_NOTIF] CRITICAL: Failed to decode message (first 4 bytes: %02X %02X %02X %02X)\n",
                   (unsigned char)message[0], (unsigned char)message[1],
                   (unsigned char)message[2], (unsigned char)message[3]);
        } else {
            fprintf(stderr, "[IOS_NOTIF] WARNING: Invalid UTF-8, used Latin-1 encoding\n");
        }
    }

    // Category handling with fallback
    NSString *categoryCopy = nil;
    if (category) {
        categoryCopy = [NSString stringWithUTF8String:category];
        if (!categoryCopy) {
            categoryCopy = @"MSG";  // Fallback if category encoding fails
        }
    } else {
        categoryCopy = @"MSG";
    }

    // GUARANTEE: Both strings are now non-nil (prevents crash)
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *messageDict = @{
            @"message": messageCopy,      // GUARANTEED non-nil
            @"category": categoryCopy,    // GUARANTEED non-nil
            @"attr": @(attr)
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetHackMessage"
                                                            object:messageDict];
    });
}

// Post hand selection request notification to Swift UI
// Swift should show a left/right hand picker and queue 'l', 'L', 'r', 'R', or ESC
__attribute__((visibility("default")))
void ios_request_hand_selection(void) {
    fprintf(stderr, "[IOS_NOTIF] Requesting hand selection from Swift UI\n");

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetHackHandSelection"
                                                            object:nil];
    });
}

// Post loot options request notification to Swift UI
// Swift should show loot mode picker (:oibrs) and queue the selected character
// Called when NetHack prompts "Do what with container? [:oibrs nq or ?]"
__attribute__((visibility("default")))
void ios_request_loot_options(const char *available_options) {
    fprintf(stderr, "[IOS_NOTIF] Requesting loot options from Swift UI (options: %s)\n",
            available_options ? available_options : "(null)");

    NSString *optionsCopy = nil;
    if (available_options) {
        optionsCopy = [NSString stringWithUTF8String:available_options];
    }
    if (!optionsCopy) {
        optionsCopy = @":oibrsq";  // Default full set
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *optionsDict = @{
            @"options": optionsCopy
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetHackLootOptions"
                                                            object:optionsDict];
    });
}

// Post text input request notification to Swift UI
// Swift should show TextInputSheet with appropriate suggestions and queue the text + newline
// Called for genocide, polymorph, and name prompts
// Type: "genocide", "polymorph", "name"
__attribute__((visibility("default")))
void ios_request_text_input(const char *prompt, const char *input_type) {
    fprintf(stderr, "[IOS_NOTIF] Requesting text input from Swift UI (type: %s, prompt: %s)\n",
            input_type ? input_type : "unknown",
            prompt ? prompt : "(null)");

    NSString *promptCopy = nil;
    if (prompt) {
        promptCopy = [NSString stringWithUTF8String:prompt];
    }
    if (!promptCopy) {
        promptCopy = @"Enter text:";
    }

    NSString *typeCopy = nil;
    if (input_type) {
        typeCopy = [NSString stringWithUTF8String:input_type];
    }
    if (!typeCopy) {
        typeCopy = @"generic";
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *inputDict = @{
            @"prompt": promptCopy,
            @"type": typeCopy
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetHackTextInput"
                                                            object:inputDict];
    });
}
