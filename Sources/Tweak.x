#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "CapitalAPI.h"
#import "ConvoQueue.h"
#import "HapticTyper.h"

// ── Jitter for human-like delays ─────────────────────────────────────────────
static NSTimeInterval TKJitter(double baseMs) {
    double u1 = (double)arc4random() / (double)UINT32_MAX;
    double u2 = (double)arc4random() / (double)UINT32_MAX;
    return baseMs * (0.6 + ((u1 + u2) / 2.0) * 0.8) / 1000.0;
}

// ── Prefs (Using NSUserDefaults for Rootless compatibility) ──────────────────
static NSString *const kPrefSuite = @"com.jb.badoocapitalai";
static NSUserDefaults *BCPrefs(void) { return [[NSUserDefaults alloc] initWithSuiteName:kPrefSuite]; }
static BOOL BCEnabled(void) { return [BCPrefs() boolForKey:@"enabled"]; }

// ── History builder ──────────────────────────────────────────────────────────
static NSArray<NSDictionary *> *BCHistory(NSArray *msgs) {
    NSMutableArray *out = [NSMutableArray new];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    for (id m in msgs) {
        NSString *text = [m valueForKey:@"text"] ?: @"";
        NSDate *date = [m valueForKey:@"timestamp"];
        BOOL mine = [[m valueForKey:@"isOwn"] boolValue];
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

// ── Associated-object keys ───────────────────────────────────────────────────
static const char kBotActive[] = "bcai_active";
static const char kBotQueue[]  = "bcai_queue";

@interface NSObject (BCAIHelpers)
- (void)bc_scanAndStart;
- (void)bc_processNext;
- (void)bc_deliver:(NSArray *)content listVC:(id)listVC;
- (UIView *)bc_findInputField;
- (UIView *)bc_findClass:(Class)cls in:(UIView *)root;
- (void)bc_tapSend;
- (UIView *)bc_findSend:(UIView *)root;
@end

#pragma mark - List VC (Chats Tab Scanning)

%hook BDChatConversationListViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!BCEnabled()) return;
    
    id me = (id)self;
    BOOL isActive = [objc_getAssociatedObject(me, kBotActive) boolValue];
    if (!isActive) [me bc_scanAndStart];
}

%new
- (void)bc_scanAndStart {
    id me = (id)self;
    UITableView *tv = [me valueForKey:@"tableView"];
    if (!tv) tv = (UITableView *)[me bc_findClass:[UITableView class] in:((UIViewController *)me).view];
    if (!tv) return;

    NSMutableArray *newRows = [NSMutableArray array];
    NSInteger rows = [tv numberOfRowsInSection:0];
    
    for (NSInteger i = 0; i < rows; i++) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:i inSection:0];
        UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
        if (!cell) continue;
        
        BOOL isNew = NO;
        BOOL isOnline = NO;
        
        // Scan cell UI for "New message" or Online indicator (green dot)
        for (UIView *v in cell.contentView.subviews) {
            if ([v isKindOfClass:[UILabel class]]) {
                UILabel *l = (UILabel *)v;
                if ([l.text localizedCaseInsensitiveContainsString:@"New message"]) isNew = YES;
            }
            // Check for green dot (online status)
            if ([v isKindOfClass:[UIView class]] && v.backgroundColor && CGColorEqualToColor(v.backgroundColor.CGColor, [UIColor greenColor].CGColor)) {
                isOnline = YES;
            }
        }
        
        // Priority 1: Online + Unread. Priority 2: Unread. Priority 3: Just Online.
        if (isOnline && isNew) {
            [newRows insertObject:ip atIndex:0]; // Highest priority
        } else if (isNew || isOnline) {
            [newRows addObject:ip];
        }
    }
    
    if (newRows.count > 0) {
        objc_setAssociatedObject(me, kBotActive, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(me, kBotQueue, newRows, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [me bc_processNext];
    }
}

%new
- (void)bc_processNext {
    id me = (id)self;
    NSMutableArray *queue = objc_getAssociatedObject(me, kBotQueue);
    
    if (!queue || queue.count == 0) {
        objc_setAssociatedObject(me, kBotActive, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(me, kBotQueue, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    
    NSIndexPath *ip = queue.firstObject;
    [queue removeObjectAtIndex:0];
    
    UITableView *tv = [me valueForKey:@"tableView"];
    if (!tv) tv = (UITableView *)[me bc_findClass:[UITableView class] in:((UIViewController *)me).view];
    
    [tv selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
    [tv.delegate tableView:tv didSelectRowAtIndexPath:ip];
}

%end

#pragma mark - Chat VC (Inside the conversation)

%hook BDChatConversationViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!BCEnabled()) return;
    
    id me = (id)self;
    UIViewController *meVC = (UIViewController *)me;
    
    UIViewController *listVC = nil;
    for (UIViewController *vc in meVC.navigationController.viewControllers) {
        if ([vc isKindOfClass:NSClassFromString(@"BDChatConversationListViewController")]) {
            listVC = vc; break;
        }
    }
    
    if (!listVC) return;
    if (![objc_getAssociatedObject(listVC, kBotActive) boolValue]) return;

    // Extract history from Badoo's internal conversation object
    id conv = [me valueForKey:@"conversation"];
    NSArray *msgs = [conv valueForKey:@"messages"] ?: [conv valueForKey:@"chatHistory"] ?: @[];
    
    NSArray *history = BCHistory(msgs);
    NSString *contactName = [conv valueForKey:@"name"] ?: @"Match";
    NSString *contactId = [conv valueForKey:@"userId"] ?: [conv valueForKey:@"conversationId"] ?: @"unknown";

    // Call the API
    [[CapitalAPI shared] generateResponse:history
                                contactId:contactId
                              contactName:contactName
                               completion:^(NSArray *content, NSDictionary *stats, NSError *err) {
        
        // If error, API skip-flag (converted, ignored), or empty -> go back to list
        if (err || !content.count) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [meVC.navigationController popViewControllerAnimated:YES];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [listVC bc_processNext];
                });
            });
            return;
        }
        
        // Deliver the content array
        dispatch_async(dispatch_get_main_queue(), ^{
            [me bc_deliver:content listVC:listVC];
        });
    }];
}

%new
- (void)bc_deliver:(NSArray *)content listVC:(id)listVC {
    id me = (id)self;
    
    // Done sending messages
    if (!content.count) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *vc = (UIViewController *)me;
            [vc.navigationController popViewControllerAnimated:YES];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [listVC bc_processNext];
            });
        });
        return;
    }

    NSMutableArray *rest = [content mutableCopy];
    NSDictionary *item = rest.firstObject;
    [rest removeObjectAtIndex:0];

    NSString *type = item[@"type"] ?: @"text";
    NSString *body = item[@"content"] ?: @"";

    if ([type isEqualToString:@"text"]) {
        UIView *field = [me bc_findInputField];
        
        // Human thinking delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TKJitter(3500) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (field && [field respondsToSelector:@selector(insertText:)]) {
                [[HapticTyper shared] typeText:body intoResponder:(UIResponder<UITextInput> *)field completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TKJitter(800) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [me bc_tapSend];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TKJitter(1500) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [me bc_deliver:rest listVC:listVC];
                        });
                    });
                }];
            } else {
                // Fallback if text field isn't found
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TKJitter(500) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [me bc_deliver:rest listVC:listVC];
                });
            }
        });
    } else {
        // Skip images/videos for now to keep it undetected (or add media logic later)
        [me bc_deliver:rest listVC:listVC];
    }
}

%new
- (UIView *)bc_findInputField {
    id me = (id)self;
    UIView *root = ((UIViewController *)me).view;
    if (!root) return nil;
    UIView *f = [me bc_findClass:[UITextField class] in:root];
    if (!f) f = [me bc_findClass:[UITextView class] in:root];
    return f;
}

%new
- (UIView *)bc_findClass:(Class)cls in:(UIView *)root {
    if (!root) return nil;
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
    
    SEL sels[] = { @selector(sendButtonTapped:), @selector(sendMessage:), @selector(didTapSendButton:) };
    for (int i = 0; i < 3; i++) {
        if ([me respondsToSelector:sels[i]]) { [me performSelector:sels[i] withObject:nil]; return; }
    }
}

%new
- (UIView *)bc_findSend:(UIView *)root {
    if (!root) return nil;
    if ([root isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)root;
        // Badoo usually uses an arrow or paper plane image for send
        if (b.tag == 42 || b.imageView.image || [[b titleForState:UIControlStateNormal] containsString:@"Send"]) {
            return b;
        }
    }
    for (UIView *s in root.subviews) {
        UIView *f = [(id)self bc_findSend:s];
        if (f) return f;
    }
    return nil;
}

%end

#pragma mark - Constructor

%ctor {
    NSUserDefaults *prefs = BCPrefs();
    if (![prefs objectForKey:@"enabled"]) {
        [prefs setBool:NO forKey:@"enabled"];
        [prefs setObject:@"YOUR_LICENSE_KEY" forKey:@"licenseKey"];
        [prefs setInteger:43 forKey:@"modelId"];
        [prefs setInteger:88 forKey:@"presetId"];
        [prefs synchronize];
    }
    
    [CapitalAPI shared].licenseKey = [prefs stringForKey:@"licenseKey"] ?: @"";
    [CapitalAPI shared].modelId    = [prefs integerForKey:@"modelId"] ?: 43;
    [CapitalAPI shared].presetId   = [prefs integerForKey:@"presetId"] ?: 88;
}

#pragma clang diagnostic pop
