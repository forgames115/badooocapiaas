// Suppress nullability warnings — %hook/%new don't support annotations in logos syntax
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "CapitalAPI.h"
#import "ConvoQueue.h"
#import "HapticTyper.h"

// ── Jitter ───────────────────────────────────────────────────────────────────
static NSTimeInterval TKJitter(double baseMs) {
    double u1 = (double)arc4random() / (double)UINT32_MAX;
    double u2 = (double)arc4random() / (double)UINT32_MAX;
    return baseMs * (0.6 + ((u1 + u2) / 2.0) * 0.8) / 1000.0;
}

// ── Prefs ────────────────────────────────────────────────────────────────────
static NSString *const kPrefPath =
    @"/var/mobile/Library/Preferences/com.jb.badoocapitalai.plist";

static NSDictionary *BCPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kPrefPath] ?: @{};
}
static BOOL BCEnabled(void) { return [BCPrefs()[@"enabled"] boolValue]; }

// ── History builder ──────────────────────────────────────────────────────────
static NSArray<NSDictionary *> *BCHistory(NSArray *msgs) {
    NSMutableArray *out = [NSMutableArray new];
    NSTimeInterval  now = [[NSDate date] timeIntervalSince1970];
    for (id m in msgs) {
        NSString *text  = [m valueForKey:@"text"] ?: @"";
        NSDate   *date  = [m valueForKey:@"timestamp"];
        BOOL      mine  = [[m valueForKey:@"isOwn"] boolValue];
        NSString *media = [m valueForKey:@"mediaType"];
        if (!text.length) {
            if ([media isEqualToString:@"photo"])      text = @"*IMAGE*";
            else if ([media isEqualToString:@"video"]) text = @"*VIDEO*";
            else if ([media isEqualToString:@"audio"]) text = @"*AUDIO*";
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

static NSTimeInterval BCThink(NSString *t) {
    return 1.5 + (double)arc4random_uniform(25)/10.0 + MIN((double)t.length/60.0, 2.0);
}

// ── Associated-object keys ───────────────────────────────────────────────────
static const char kContent[] = "bcai_c";
static const char kCid[]     = "bcai_i";

// ── Queue-active flag ────────────────────────────────────────────────────────
static BOOL BCActive = NO;

// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT: Inside %new methods, `self` has the type of the forward-declared
// hooked class, which the compiler sees as incomplete. Cast to `id` (or the
// appropriate base class) before sending ANY message to avoid "receiver is a
// forward declaration" errors.
// ─────────────────────────────────────────────────────────────────────────────

#pragma mark - List VC

%hook BDChatConversationListViewController

- (void)reloadData {
    %orig;
    if (!BCEnabled()) return;
    // Cast to id — avoids forward-declaration errors throughout
    id me = (id)self;

    id ds      = [me valueForKey:@"dataSource"];
    NSArray *c = [ds valueForKey:@"conversations"];
    if (!c.count) return;

    [[ConvoQueue shared] clear];
    for (id cv in c) {
        NSString *cid  = [cv valueForKey:@"userId"] ?: [cv valueForKey:@"conversationId"];
        BOOL   online  = [[cv valueForKey:@"isOnline"] boolValue];
        NSDate *act    = [cv valueForKey:@"lastMessageDate"] ?: [NSDate distantPast];
        NSArray *msgs  = [cv valueForKey:@"messages"] ?: @[];
        if ([[msgs.lastObject valueForKey:@"isOwn"] boolValue]) continue;

        BDConvoEntry *e = [BDConvoEntry new];
        e.contactId    = cid;
        e.contactName  = [cv valueForKey:@"name"] ?: @"";
        e.isOnline     = online;
        e.lastActivity = act;
        e.chatHistory  = BCHistory(msgs);
        [[ConvoQueue shared] enqueue:e];
    }
    [me bc_startQueue];
}

%new
- (void)bc_startQueue {
    if (BCActive) return;
    if (![ConvoQueue shared].count) return;
    BCActive = YES;
    [(id)self bc_processNext];
}

%new
- (void)bc_processNext {
    BDConvoEntry *e = [[ConvoQueue shared] dequeue];
    if (!e) { BCActive = NO; return; }

    id me = (id)self;
    [[CapitalAPI shared] generateResponse:e.chatHistory
                                contactId:e.contactId
                              contactName:e.contactName
                               completion:^(NSArray *content, NSDictionary *stats, NSError *err) {
        if (err || !content.count) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ [me bc_processNext]; });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [me bc_openAndSend:content contactId:e.contactId];
        });
    }];
}

%new
- (void)bc_openAndSend:(NSArray *)content contactId:(NSString *)cid {
    id me            = (id)self;
    UITableView *tv  = [me valueForKey:@"tableView"];
    id ds            = [me valueForKey:@"dataSource"];
    NSArray *convos  = [ds valueForKey:@"conversations"];

    NSUInteger row = NSNotFound;
    for (NSUInteger i = 0; i < convos.count; i++) {
        NSString *id_ = [convos[i] valueForKey:@"userId"]
                     ?: [convos[i] valueForKey:@"conversationId"];
        if ([id_ isEqualToString:cid]) { row = i; break; }
    }
    if (row == NSNotFound) { [me bc_processNext]; return; }

    objc_setAssociatedObject(me, kContent, content, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(me, kCid,     cid,     OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    [tv selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
    [tv.delegate tableView:tv didSelectRowAtIndexPath:ip];
}

%end

#pragma mark - Conversation VC

%hook BDChatConversationViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!BCEnabled()) return;
    id me = (id)self;

    // Find list VC — cast to UIViewController* so navigationController is accessible
    UIViewController *meVC = (UIViewController *)me;
    id listVC = nil;
    for (UIViewController *vc in meVC.navigationController.viewControllers) {
        if ([vc isKindOfClass:NSClassFromString(@"BDChatConversationListViewController")]) {
            listVC = vc; break;
        }
    }
    if (!listVC) return;

    NSArray  *content = objc_getAssociatedObject(listVC, kContent);
    NSString *target  = objc_getAssociatedObject(listVC, kCid);
    if (!content.count) return;

    id conv   = [me valueForKey:@"conversation"];
    NSString *myCid = [conv valueForKey:@"userId"] ?: [conv valueForKey:@"conversationId"];
    if (![myCid isEqualToString:target]) return;

    objc_setAssociatedObject(listVC, kContent, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(listVC, kCid,     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [me bc_deliver:content listVC:listVC];
}

%new
- (void)bc_deliver:(NSArray *)content listVC:(id)listVC {
    id me = (id)self;
    if (!content.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(UIViewController *)me navigationController].viewControllers; // keep ref
            [((UIViewController *)me).navigationController popViewControllerAnimated:NO];
            [listVC bc_processNext];
        });
        return;
    }

    NSMutableArray *rest = [content mutableCopy];
    NSDictionary *item   = rest.firstObject;
    [rest removeObjectAtIndex:0];

    NSString *type = item[@"type"] ?: @"text";
    NSString *body = item[@"content"] ?: @"";

    if ([type isEqualToString:@"text"]) {
        UITextField *field = [me bc_findInputField];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                       (int64_t)(BCThink(body) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (field) {
                [[HapticTyper shared] typeText:body intoResponder:field completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                   (int64_t)(TKJitter(200) * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        [me bc_tapSend];
                        double p = 0.8 + (double)arc4random_uniform(8)/10.0;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                       (int64_t)(p * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            [me bc_deliver:rest listVC:listVC];
                        });
                    });
                }];
            } else {
                [me bc_sendDirect:body];
                [me bc_deliver:rest listVC:listVC];
            }
        });
    } else if ([type isEqualToString:@"image"] || [type isEqualToString:@"video"]) {
        [me bc_sendMedia:body type:type completion:^{
            [me bc_deliver:rest listVC:listVC];
        }];
    } else {
        [me bc_deliver:rest listVC:listVC];
    }
}

%new
- (UITextField *)bc_findInputField {
    return (UITextField *)[(id)self bc_findClass:[UITextField class] in:((UIViewController *)self).view];
}

%new
- (UIView *)bc_findClass:(Class)cls in:(UIView *)root {
    if ([root isKindOfClass:cls]) return root;
    for (UIView *s in root.subviews) {
        UIView *f = [(id)self bc_findClass:cls in:s];
        if (f) return f;
    }
    return nil;
}

%new
- (void)bc_tapSend {
    id me = (id)self;
    UIView *root = ((UIViewController *)me).view;
    UIButton *btn = (UIButton *)[me bc_findSend:root];
    if (btn) { [btn sendActionsForControlEvents:UIControlEventTouchUpInside]; return; }
    SEL sels[] = {
        @selector(sendButtonTapped:),
        @selector(sendMessage:),
        @selector(didTapSendButton:)
    };
    for (int i = 0; i < 3; i++)
        if ([me respondsToSelector:sels[i]]) { [me performSelector:sels[i] withObject:nil]; return; }
}

%new
- (UIView *)bc_findSend:(UIView *)root {
    if ([root isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)root;
        if ([[b titleForState:UIControlStateNormal] containsString:@"Send"] || b.tag == 42)
            return b;
    }
    for (UIView *s in root.subviews) {
        UIView *f = [(id)self bc_findSend:s];
        if (f) return f;
    }
    return nil;
}

%new
- (void)bc_sendDirect:(NSString *)text {
    id me = (id)self;
    SEL sels[] = {
        @selector(sendMessage:),
        @selector(sendTextMessage:),
        @selector(sendChatMessage:)
    };
    for (int i = 0; i < 3; i++)
        if ([me respondsToSelector:sels[i]]) { [me performSelector:sels[i] withObject:text]; return; }
    UITextField *f = [me bc_findInputField];
    if (f) { f.text = text; [me bc_tapSend]; }
}

%new
- (void)bc_sendMedia:(NSString *)urlStr type:(NSString *)type completion:(void(^)(void))done {
    id me = (id)self;
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
                if ([me respondsToSelector:s]) [me performSelector:s withObject:tmp];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2*NSEC_PER_SEC)),
                               dispatch_get_main_queue(), done);
            });
    }] resume];
}

%end

#pragma mark - Constructor

%ctor {
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

#pragma clang diagnostic pop
