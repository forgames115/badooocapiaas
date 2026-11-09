#pragma once
#import <Foundation/Foundation.h>

typedef void (^CapitalResponseBlock)(NSArray<NSDictionary *> *content, NSDictionary *stats, NSError *error);

@interface CapitalAPI : NSObject
@property (nonatomic, copy)   NSString  *licenseKey;
@property (nonatomic, assign) NSInteger  modelId;
@property (nonatomic, assign) NSInteger  presetId;
+ (instancetype)shared;
- (void)generateResponse:(NSArray<NSDictionary *> *)chatHistory
               contactId:(NSString *)contactId
             contactName:(NSString *)contactName
              completion:(CapitalResponseBlock)completion;
@end
