#pragma once
#import <UIKit/UIKit.h>

typedef void (^HapticTyperCompletion)(void);

@interface HapticTyper : NSObject
+ (instancetype)shared;
- (void)typeText:(NSString *)text
   intoResponder:(UIResponder<UITextInput> *)responder
      completion:(nullable HapticTyperCompletion)completion;
- (void)cancel;
@end
