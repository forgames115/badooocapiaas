#pragma once
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface BCEngine : NSObject
+ (void)listVCReloaded:(UIViewController *)listVC;
+ (void)convoVCAppeared:(UIViewController *)convoVC;
@end
NS_ASSUME_NONNULL_END
