#pragma once
#import <UIKit/UIKit.h>

typedef void (^HapticTyperCompletion)(void);

/// Simulates human typing into a UITextField/UITextView:
///   - Per-character random delay (60–140 ms base, gaussian-ish jitter)
///   - Occasional "typo + backspace" sequence to look human
///   - CoreHaptics light tap on each keystroke (optional, falls back gracefully)
@interface HapticTyper : NSObject

+ (instancetype)shared;

/// Type `text` into `responder`. Calls `completion` on main thread when done.
- (void)typeText:(NSString *)text
     intoResponder:(UIResponder<UITextInput> *)responder
        completion:(nullable HapticTyperCompletion)completion;

/// Cancel any in-progress typing session
- (void)cancel;

@end
