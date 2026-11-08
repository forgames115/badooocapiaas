#pragma once
#import <Foundation/Foundation.h>

typedef void (^CapitalResponseBlock)(NSArray<NSDictionary *> *content, NSDictionary *stats, NSError *error);

@interface CapitalAPI : NSObject

// licenseKey / modelId / presetId set once at startup from prefs
@property (nonatomic, copy) NSString *licenseKey;
@property (nonatomic, assign) NSInteger modelId;
@property (nonatomic, assign) NSInteger presetId;

+ (instancetype)shared;

/// Fire /generateResponse. chatHistory entries: { role, content, timestamp }
- (void)generateResponse:(NSArray<NSDictionary *> *)chatHistory
             contactId:(NSString *)contactId
            contactName:(NSString *)contactName
             completion:(CapitalResponseBlock)completion;

@end
