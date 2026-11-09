#import "CapitalAPI.h"

static NSString *const kBaseURL = @"https://api.capitalbot.ai/generateResponse";

@implementation CapitalAPI

+ (instancetype)shared {
    static CapitalAPI *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; }); return s;
}

- (void)generateResponse:(NSArray<NSDictionary *> *)chatHistory
               contactId:(NSString *)contactId
             contactName:(NSString *)contactName
              completion:(CapitalResponseBlock)completion {

    NSMutableArray *safe = [NSMutableArray new];
    NSTimeInterval now   = [[NSDate date] timeIntervalSince1970];
    for (NSDictionary *m in chatHistory) {
        NSMutableDictionary *c = [m mutableCopy];
        if (!c[@"timestamp"]) c[@"timestamp"] = @((NSInteger)now);
        [safe addObject:c];
    }

    NSDictionary *body = @{
        @"licensekey"  : self.licenseKey ?: @"",
        @"modelId"     : @(self.modelId),
        @"presetId"    : @(self.presetId),
        @"accountId"   : @"badoo_account",
        @"platform"    : @"Badoo",
        @"audio"       : @NO, @"video": @NO, @"image": @YES,
        @"userInfos"   : @{ @"useridentifier": contactId ?: @"", @"name": contactName ?: @"" },
        @"chatHistory" : safe
    };

    NSError *je;
    NSData *bd = [NSJSONSerialization dataWithJSONObject:body options:0 error:&je];
    if (je) { completion(nil, nil, je); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kBaseURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody   = bd;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
            if (err) { completion(nil, nil, err); return; }
            if (!data) { completion(@[], nil, nil); return; }
            NSError *pe;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&pe];
            if (pe || ![json isKindOfClass:[NSDictionary class]]) { completion(nil, nil, pe); return; }
            if ([json[@"underage"] boolValue] || [json[@"aiCreditOver"] boolValue] ||
                [json[@"messagedAlready"] boolValue] || [json[@"internalAccount"] boolValue] ||
                [json[@"ignored"] boolValue]) { completion(@[], json, nil); return; }
            NSArray *c = json[@"content"];
            completion([c isKindOfClass:[NSArray class]] ? c : @[], json[@"statistics"], nil);
    }] resume];
}
@end
