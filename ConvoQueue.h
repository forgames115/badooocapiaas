#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface BDConvoEntry : NSObject
@property (nonatomic, copy)   NSString               *contactId;
@property (nonatomic, copy)   NSString               *contactName;
@property (nonatomic, assign) BOOL                    isOnline;
@property (nonatomic, strong) NSDate                 *lastActivity;
@property (nonatomic, strong) NSArray<NSDictionary *> *chatHistory;
@end
@interface ConvoQueue : NSObject
+ (instancetype)shared;
- (void)enqueue:(BDConvoEntry *)entry;
- (void)clear;
- (nullable BDConvoEntry *)dequeue;
@property (nonatomic, readonly) NSUInteger count;
@end
NS_ASSUME_NONNULL_END
