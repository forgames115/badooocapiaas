#import "CapitalAPI.h"

static NSString *const kBaseURL = @"https://api.capitalbot.ai/generateResponse";

@implementation CapitalAPI

+ (instancetype)shared {
    static CapitalAPI *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (void)generateResponse:(NSArray<NSDictionary *> *)chatHistory
              contactId:(NSString *)contactId
            contactName:(NSString *)contactName
             completion:(CapitalResponseBlock)completion {

    // Validate timestamps — API 400s without them
    for (NSDictionary *msg in chatHistory) {
        if (!msg[@"timestamp"]) {
            NSError *e = [NSError errorWithDomain:@"CapitalAPI"
                                            code:400
                                        userInfo:@{NSLocalizedDescriptionKey: @"msg missing timestamp"}];
            completion(nil, nil, e);
            return;
        }
    }

    NSDictionary *body = @{
        @"licensekey" : self.licenseKey ?: @"",
        @"modelId"    : @(self.modelId),
        @"presetId"   : @(self.presetId),
        @"accountId"  : @"badoo_account",   // shortcut: single account; pass real Badoo user ID here
        @"platform"   : @"Badoo",
        @"audio"      : @NO,
        @"video"      : @NO,
        @"image"      : @YES,
        @"userInfos"  : @{
            @"useridentifier" : contactId,
            @"name"           : contactName ?: @""
        },
        @"chatHistory" : chatHistory
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kBaseURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err) { completion(nil, nil, err); return; }

            NSError *parseErr;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseErr];
            if (parseErr) { completion(nil, nil, parseErr); return; }

            // Guard flags
            if ([json[@"underage"] boolValue] ||
                [json[@"aiCreditOver"] boolValue] ||
                [json[@"messagedAlready"] boolValue] ||
                [json[@"internalAccount"] boolValue] ||
                [json[@"ignored"] boolValue]) {
                completion(@[], json, nil);
                return;
            }

            completion(json[@"content"] ?: @[], json[@"statistics"], nil);
    }] resume];
}

@end
