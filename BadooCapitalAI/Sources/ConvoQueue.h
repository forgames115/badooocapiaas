#pragma once
#import <Foundation/Foundation.h>

/// Lightweight wrapper around a Badoo conversation list entry
@interface BDConvoEntry : NSObject
@property (nonatomic, copy) NSString *contactId;
@property (nonatomic, copy) NSString *contactName;
@property (nonatomic, assign) BOOL isOnline;
@property (nonatomic, strong) NSDate *lastActivity;
/// Raw chat history array already built from the Badoo model
@property (nonatomic, strong) NSArray<NSDictionary *> *chatHistory;
@end

/// Sorted queue: online conversations first, then by recency
@interface ConvoQueue : NSObject

+ (instancetype)shared;

- (void)enqueue:(BDConvoEntry *)entry;
- (void)clear;

/// Returns next entry to process (removes from queue)
- (nullable BDConvoEntry *)dequeue;

@property (nonatomic, readonly) NSUInteger count;

@end
