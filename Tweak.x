// Tweak.x — only %hook stubs, all logic in BCEngine.m
// CapitalAPI imported here so %ctor can configure the shared instance
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

#import <UIKit/UIKit.h>
#import "BCEngine.h"
#import "CapitalAPI.h"

%hook BDChatConversationListViewController
- (void)reloadData {
    %orig;
    [BCEngine listVCReloaded:(UIViewController *)self];
}
%end

%hook BDChatConversationViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [BCEngine convoVCAppeared:(UIViewController *)self];
}
%end

%ctor {
    NSString *path = @"/var/mobile/Library/Preferences/com.jb.badoocapitalai.plist";
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        [@{ @"enabled":@NO, @"licenseKey":@"YOUR_LICENSE_KEY",
            @"modelId":@(43), @"presetId":@(88) } writeToFile:path atomically:YES];
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
    [CapitalAPI shared].licenseKey = p[@"licenseKey"] ?: @"";
    [CapitalAPI shared].modelId    = [p[@"modelId"]  integerValue] ?: 43;
    [CapitalAPI shared].presetId   = [p[@"presetId"] integerValue] ?: 88;
}

#pragma clang diagnostic pop
