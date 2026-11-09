#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CapitalResponseBlock)(NSArray<NSDictionary *> * _Nullable content,
                                     NSDictionary * _Nullable stats,
                                     NSError * _Nullable error);

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

NS_ASSUME_NONNULL_END
