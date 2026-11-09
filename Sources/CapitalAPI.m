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

    // Ensure every message has a timestamp — API rejects without it
    NSMutableArray *safeHistory = [NSMutableArray new];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    for (NSDictionary *msg in chatHistory) {
        NSMutableDictionary *m = [msg mutableCopy];
        if (!m[@"timestamp"]) m[@"timestamp"] = @((NSInteger)now);
        [safeHistory addObject:m];
    }

    NSDictionary *body = @{
        @"licensekey"  : self.licenseKey ?: @"",
        @"modelId"     : @(self.modelId),
        @"presetId"    : @(self.presetId),
        @"accountId"   : @"badoo_account",
        @"platform"    : @"Badoo",
        @"audio"       : @NO,
        @"video"       : @NO,
        @"image"       : @YES,
        @"userInfos"   : @{
            @"useridentifier" : contactId ?: @"",
            @"name"           : contactName ?: @""
        },
        @"chatHistory" : safeHistory
    };

    NSError *jsonErr;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (jsonErr) { completion(nil, nil, jsonErr); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kBaseURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = bodyData;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err) { completion(nil, nil, err); return; }
            if (!data) { completion(@[], nil, nil); return; }

            NSError *parseErr;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0
                                                                   error:&parseErr];
            if (parseErr || ![json isKindOfClass:[NSDictionary class]]) {
                completion(nil, nil, parseErr);
                return;
            }

            // Skip-flags from Capital AI
            if ([json[@"underage"]        boolValue] ||
                [json[@"aiCreditOver"]    boolValue] ||
                [json[@"messagedAlready"] boolValue] ||
                [json[@"internalAccount"] boolValue] ||
                [json[@"ignored"]         boolValue]) {
                completion(@[], json, nil);
                return;
            }

            NSArray *content = json[@"content"];
            completion([content isKindOfClass:[NSArray class]] ? content : @[],
                       json[@"statistics"],
                       nil);
    }] resume];
}

@end
