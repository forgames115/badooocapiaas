#pragma once
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^HapticTyperCompletion)(void);
@interface HapticTyper : NSObject
+ (instancetype)shared;
- (void)typeText:(NSString *)text
   intoResponder:(UIResponder<UITextInput> *)responder
      completion:(nullable HapticTyperCompletion)completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
