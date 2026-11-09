#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "CapitalAPI.h"
#import "ConvoQueue.h"
#import "HapticTyper.h"

// ── Jitter (defined here for Tweak.x use; HapticTyper.m has its own copy) ──────────────
static NSTimeInterval TKJitter(double baseMs) {
    double u1 = (double)arc4random() / (double)UINT32_MAX;
    double u2 = (double)arc4random() / (double)UINT32_MAX;
    return baseMs * (0.6 + ((u1 + u2) / 2.0) * 0.8) / 1000.0;
}

// ── Prefs ────────────────────────────────────────────────────────────────────────────────
static NSString *const kPrefPath = @"/var/mobile/Library/Preferences/com.jb.badoocapitalai.plist";

static NSDictionary *BCPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kPrefPath] ?: @{};
}

static BOOL BCEnabled(void) {
    return [BCPrefs()[@"enabled"] boolValue];
}

// ── Chat history builder ─────────────────────────────────────────────────────────────────
static NSArray<NSDictionary *> *BCBuildHistory(NSArray *messages) {
    NSMutableArray *out  = [NSMutableArray new];
    NSTimeInterval  now  = [[NSDate date] timeIntervalSince1970];
    for (id msg in messages) {
        NSString *text      = [msg valueForKey:@"text"] ?: @"";
        NSDate   *date      = [msg valueForKey:@"timestamp"];
        BOOL      mine      = [[msg valueForKey:@"isOwn"] boolValue];
        NSString *mediaType = [msg valueForKey:@"mediaType"];

        if (!text.length) {
            if ([mediaType isEqualToString:@"photo"])       text = @"*IMAGE*";
            else if ([mediaType isEqualToString:@"video"])  text = @"*VIDEO*";
            else if ([mediaType isEqualToString:@"audio"])  text = @"*AUDIO*";
            else continue;
        }

        [out addObject:@{
            @"role"      : mine ? @"bot" : @"user",
            @"content"   : text,
            @"timestamp" : @(date ? (NSInteger)[date timeIntervalSince1970] : (NSInteger)now)
        }];
    }
    return out;
}

// ── Think-delay before typing (scales with message length) ───────────────────────────────
static NSTimeInterval BCThinkDelay(NSString *text) {
    double base  = 1.5 + (double)arc4random_uniform(25) / 10.0;
    double bonus = MIN((double)text.length / 60.0, 2.0);
    return base + bonus;
}

// ── Associated-object keys ───────────────────────────────────────────────────────────────
static const char kPendingContent[]   = "bcai_pending_content";
static const char kPendingContactId[] = "bcai_pending_cid";

// ── Global queue-active flag ─────────────────────────────────────────────────────────────
static BOOL BCQueueActive = NO;

// ─────────────────────────────────────────────────────────────────────────────────────────
#pragma mark - Conversation List hook
// ─────────────────────────────────────────────────────────────────────────────────────────

%hook BDChatConversationListViewController

- (void)reloadData {
    %orig;
    if (!BCEnabled()) return;

    id dataSource  = [self valueForKey:@"dataSource"];
    NSArray *convos = [dataSource valueForKey:@"conversations"];
    if (!convos.count) return;

    [[ConvoQueue shared] clear];

    for (id convo in convos) {
        NSString *cid  = [convo valueForKey:@"userId"]
                      ?: [convo valueForKey:@"conversationId"];
        NSString *name = [convo valueForKey:@"name"] ?: @"";
        BOOL   online  = [[convo valueForKey:@"isOnline"] boolValue];
        NSDate *act    = [convo valueForKey:@"lastMessageDate"] ?: [NSDate distantPast];
        NSArray *msgs  = [convo valueForKey:@"messages"] ?: @[];

        // Skip if WE sent the last message
        id last = msgs.lastObject;
        if ([[last valueForKey:@"isOwn"] boolValue]) continue;

        BDConvoEntry *e = [BDConvoEntry new];
        e.contactId    = cid;
        e.contactName  = name;
        e.isOnline     = online;
        e.lastActivity = act;
        e.chatHistory  = BCBuildHistory(msgs);
        [[ConvoQueue shared] enqueue:e];
    }

    [self bc_startQueue];
}

%new
- (void)bc_startQueue {
    if (BCQueueActive) return;
    if (![ConvoQueue shared].count) return;
    BCQueueActive = YES;
    [self bc_processNext];
}

%new
- (void)bc_processNext {
    BDConvoEntry *entry = [[ConvoQueue shared] dequeue];
    if (!entry) { BCQueueActive = NO; return; }

    [[CapitalAPI shared] generateResponse:entry.chatHistory
                                contactId:entry.contactId
                              contactName:entry.contactName
                               completion:^(NSArray *content, NSDictionary *stats, NSError *err) {

        if (err || !content.count) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ [self bc_processNext]; });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self bc_openAndSend:content contactId:entry.contactId];
        });
    }];
}

%new
- (void)bc_openAndSend:(NSArray *)content contactId:(NSString *)cid {
    UITableView *tv     = [self valueForKey:@"tableView"];
    id dataSource       = [self valueForKey:@"dataSource"];
    NSArray *convos     = [dataSource valueForKey:@"conversations"];

    NSUInteger row = NSNotFound;
    for (NSUInteger i = 0; i < convos.count; i++) {
        NSString *id_ = [convos[i] valueForKey:@"userId"]
                     ?: [convos[i] valueForKey:@"conversationId"];
        if ([id_ isEqualToString:cid]) { row = i; break; }
    }
    if (row == NSNotFound) { [self bc_processNext]; return; }

    // Store for the conversation VC to pick up
    objc_setAssociatedObject(self, kPendingContent,   content, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kPendingContactId, cid,     OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    [tv selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
    [tv.delegate tableView:tv didSelectRowAtIndexPath:ip];
}

%end

// ─────────────────────────────────────────────────────────────────────────────────────────
#pragma mark - Conversation View hook
// ─────────────────────────────────────────────────────────────────────────────────────────

%hook BDChatConversationViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!BCEnabled()) return;

    // Find the list VC in the nav stack
    BDChatConversationListViewController *listVC = nil;
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass:NSClassFromString(@"BDChatConversationListViewController")]) {
            listVC = (id)vc; break;
        }
    }
    if (!listVC) return;

    NSArray  *content = objc_getAssociatedObject(listVC, kPendingContent);
    NSString *target  = objc_getAssociatedObject(listVC, kPendingContactId);
    if (!content.count) return;

    NSString *myCid = [[self valueForKey:@"conversation"] valueForKey:@"userId"]
                   ?: [[self valueForKey:@"conversation"] valueForKey:@"conversationId"];
    if (![myCid isEqualToString:target]) return;

    // Clear pending
    objc_setAssociatedObject(listVC, kPendingContent,   nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(listVC, kPendingContactId, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self bc_deliver:content listVC:listVC];
}

%new
- (void)bc_deliver:(NSArray *)content listVC:(UIViewController *)listVC {
    if (!content.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:NO];
            if ([listVC respondsToSelector:@selector(bc_processNext)])
                [listVC performSelector:@selector(bc_processNext)];
        });
        return;
    }

    NSMutableArray *remaining = [content mutableCopy];
    NSDictionary *item = remaining.firstObject;
    [remaining removeObjectAtIndex:0];

    NSString *type = item[@"type"] ?: @"text";
    NSString *body = item[@"content"] ?: @"";

    if ([type isEqualToString:@"text"]) {
        UITextField *field = [self bc_findInputField];
        NSTimeInterval think = BCThinkDelay(body);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(think * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (field) {
                [[HapticTyper shared] typeText:body intoResponder:field completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                   (int64_t)(TKJitter(200) * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        [self bc_tapSend];
                        double pause = 0.8 + (double)arc4random_uniform(8) / 10.0;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                       (int64_t)(pause * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            [self bc_deliver:remaining listVC:listVC];
                        });
                    });
                }];
            } else {
                [self bc_sendDirect:body];
                [self bc_deliver:remaining listVC:listVC];
            }
        });

    } else if ([type isEqualToString:@"image"] || [type isEqualToString:@"video"]) {
        [self bc_sendMedia:body type:type completion:^{
            [self bc_deliver:remaining listVC:listVC];
        }];

    } else {
        [self bc_deliver:remaining listVC:listVC];
    }
}

%new
- (UITextField *)bc_findInputField {
    return (UITextField *)[self bc_findClass:[UITextField class] in:self.view];
}

%new
- (UIView *)bc_findClass:(Class)cls in:(UIView *)root {
    if ([root isKindOfClass:cls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *f = [self bc_findClass:cls in:sub];
        if (f) return f;
    }
    return nil;
}

%new
- (void)bc_tapSend {
    UIButton *btn = (UIButton *)[self bc_findSend:self.view];
    if (btn) { [btn sendActionsForControlEvents:UIControlEventTouchUpInside]; return; }
    SEL sels[] = {
        @selector(sendButtonTapped:),
        @selector(sendMessage:),
        @selector(didTapSendButton:)
    };
    for (int i = 0; i < 3; i++) {
        if ([self respondsToSelector:sels[i]]) {
            [self performSelector:sels[i] withObject:nil]; return;
        }
    }
}

%new
- (UIView *)bc_findSend:(UIView *)root {
    if ([root isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)root;
        NSString *t = [b titleForState:UIControlStateNormal];
        if ([t containsString:@"Send"] || b.tag == 42) return b;
    }
    for (UIView *sub in root.subviews) {
        UIView *f = [self bc_findSend:sub];
        if (f) return f;
    }
    return nil;
}

%new
- (void)bc_sendDirect:(NSString *)text {
    SEL sels[] = {
        @selector(sendMessage:),
        @selector(sendTextMessage:),
        @selector(sendChatMessage:)
    };
    for (int i = 0; i < 3; i++) {
        if ([self respondsToSelector:sels[i]]) {
            [self performSelector:sels[i] withObject:text]; return;
        }
    }
    UITextField *f = [self bc_findInputField];
    if (f) { f.text = text; [self bc_tapSend]; }
}

%new
- (void)bc_sendMedia:(NSString *)urlStr type:(NSString *)type completion:(void(^)(void))done {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { done(); return; }
    [[[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
            if (!data) { dispatch_async(dispatch_get_main_queue(), done); return; }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *ext = [type isEqualToString:@"video"] ? @"mp4" : @"jpg";
                NSURL *tmp = [NSURL fileURLWithPath:
                    [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [[NSUUID UUID].UUIDString stringByAppendingPathExtension:ext]]];
                [data writeToURL:tmp atomically:YES];
                SEL s = NSSelectorFromString(@"attachMediaAtURL:");
                if ([self respondsToSelector:s]) [self performSelector:s withObject:tmp];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), done);
            });
    }] resume];
}

%end

// ─────────────────────────────────────────────────────────────────────────────────────────
#pragma mark - Constructor
// ─────────────────────────────────────────────────────────────────────────────────────────

%ctor {
    // Write default prefs on first launch
    if (![[NSFileManager defaultManager] fileExistsAtPath:kPrefPath]) {
        [@{ @"enabled"    : @NO,
            @"licenseKey" : @"YOUR_LICENSE_KEY",
            @"modelId"    : @(43),
            @"presetId"   : @(88) }
         writeToFile:kPrefPath atomically:YES];
    }
    NSDictionary *p = BCPrefs();
    [CapitalAPI shared].licenseKey = p[@"licenseKey"] ?: @"";
    [CapitalAPI shared].modelId    = [p[@"modelId"]  integerValue] ?: 43;
    [CapitalAPI shared].presetId   = [p[@"presetId"] integerValue] ?: 88;
}
