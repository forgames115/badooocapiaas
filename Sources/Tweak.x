// Suppress nullability warnings
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

// ── Jitter ───────────────────────────────────────────────────────────────────
static NSTimeInterval TKJitter(double baseMs) {
    double u1 = (double)arc4random() / (double)UINT32_MAX;
    double u2 = (double)arc4random() / (double)UINT32_MAX;
    return baseMs * (0.6 + ((u1 + u2) / 2.0) * 0.8) / 1000.0;
}

// ── Prefs ────────────────────────────────────────────────────────────────────
static NSString *const kPrefPath = @"/var/mobile/Library/Preferences/com.jb.badoocapitalai.plist";
static NSDictionary *BCPrefs(void) { return [NSDictionary dictionaryWithContentsOfFile:kPrefPath] ?: @{}; }
static BOOL BCEnabled(void) { return [BCPrefs()[@"enabled"] boolValue]; }

// ── History builder ──────────────────────────────────────────────────────────
static NSArray<NSDictionary *> *BCHistory(NSArray *msgs) {
    NSMutableArray *out = [NSMutableArray new];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    for (id m in msgs) {
        NSString *text  = [m valueForKey:@"text"] ?: @"";
        NSDate   *date  = [m valueForKey:@"timestamp"];
        BOOL      mine  = [[m valueForKey:@"isOwn"] boolValue] || [[m valueForKey:@"isOutgoing"] boolValue];
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
static const char kBotActive[] = "bcai_active";
static const char kBotQueue[]  = "bcai_queue";

// ─────────────────────────────────────────────────────────────────────────────
@interface NSObject (BCAIHelpers)
- (void)bc_scanAndStart;
- (void)bc_processNext;
- (void)bc_deliver:(NSArray *)content;
- (UIView *)bc_findInputField;
- (UIView *)bc_findClass:(Class)cls in:(UIView *)root;
- (void)bc_tapSend;
- (UIView *)bc_findSend:(UIView *)root;
- (void)bc_sendDirect:(NSString *)text;
- (void)bc_sendMedia:(NSString *)urlStr type:(NSString *)type completion:(void (^)(void))done;
@end

#pragma mark - List VC (Chats Tab)

%hook BDChatConversationListViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!BCEnabled()) return;
    
    id me = (id)self;
    BOOL isActive = [objc_getAssociatedObject(me, kBotActive) boolValue];
    if (!isActive) {
        [me bc_scanAndStart];
    }
}

%new
- (void)bc_scanAndStart {
    id me = (id)self;
    UITableView *tv = [me valueForKey:@"tableView"];
    if (!tv) {
        // Fallback: find tableview in view hierarchy
        tv = (UITableView *)[me bc_findClass:[UITableView class] in:((UIViewController *)me).view];
    }
    if (!tv) return;

    NSMutableArray *newRows = [NSMutableArray array];
    NSInteger rows = [tv numberOfRowsInSection:0];
    
    for (NSInteger i = 0; i < rows; i++) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:i inSection:0];
        UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
        if (!cell) continue;
        
        // Scan the cell's UI for the "New message" text or unread badge
        BOOL isNew = NO;
        for (UIView *v in cell.contentView.subviews) {
            if ([v isKindOfClass:[UILabel class]]) {
                UILabel *l = (UILabel *)v;
                if ([l.text localizedCaseInsensitiveContainsString:@"New message"] || [l.text isEqualToString:@"Unread"]) {
                    isNew = YES; break;
                }
            }
        }
        
        if (isNew) {
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
    
    // Check if we were opened by the bot
    UIViewController *listVC = nil;
    for (UIViewController *vc in meVC.navigationController.viewControllers) {
        if ([vc isKindOfClass:NSClassFromString(@"BDChatConversationListViewController")]) {
            listVC = vc; break;
        }
    }
    
    if (!listVC) return;
    BOOL isActive = [objc_getAssociatedObject(listVC, kBotActive) boolValue];
    if (!isActive) return;

    // Grab the conversation object to get history
    id conv = [me valueForKey:@"conversation"];
    NSArray *msgs = [conv valueForKey:@"messages"] ?: [conv valueForKey:@"chatHistory"];
    
    // If KVC fails to find messages, try to scrape the chat UI (fallback)
    if (!msgs) {
        msgs = @[]; // Badoo might not expose history via KVC directly
    }
    
    NSArray *history = BCHistory(msgs);
    NSString *contactName = [conv valueForKey:@"name"] ?: @"Match";
    NSString *contactId = [conv valueForKey:@"userId"] ?: [conv valueForKey:@"conversationId"] ?: @"unknown";

    // Call the API
    [[CapitalAPI shared] generateResponse:history
                                contactId:contactId
                              contactName:contactName
                               completion:^(NSArray *content, NSDictionary *stats, NSError *err) {
        if (err || !content.count) {
            // If AI fails or no response, skip to next
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [meVC.navigationController popViewControllerAnimated:YES];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [listVC bc_processNext];
                });
            });
            return;
        }
        
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *vc = (UIViewController *)me;
            [vc.navigationController popViewControllerAnimated:YES];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
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
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BCThink(body) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (field && [field respondsToSelector:@selector(insertText:)]) {
                [[HapticTyper shared] typeText:body intoResponder:(UIResponder<UITextInput> *)field completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TKJitter(200) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [me bc_tapSend];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [me bc_deliver:rest listVC:listVC];
                        });
                    });
                }];
            } else {
                [me bc_sendDirect:body];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TKJitter(700) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [me bc_deliver:rest listVC:listVC];
                });
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
        // Badoo send button might have an image or text
        if ([[b titleForState:UIControlStateNormal] containsString:@"Send"] || b.tag == 42 || b.imageView.image) {
            return b;
        }
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
    SEL sels[] = { @selector(sendMessage:), @selector(sendTextMessage:), @selector(sendChatMessage:) };
    for (int i = 0; i < 3; i++) {
        if ([me respondsToSelector:sels[i]]) { [me performSelector:sels[i] withObject:text]; return; }
    }
    UIView *f = [me bc_findInputField];
    if (f) {
        if ([f isKindOfClass:[UITextField class]]) ((UITextField *)f).text = text;
        else if ([f isKindOfClass:[UITextView class]]) ((UITextView *)f).text = text;
        [me bc_tapSend];
    }
}

%new
- (void)bc_sendMedia:(NSString *)urlStr type:(NSString *)type completion:(void (^)(void))done {
    // ... [Keep your existing media code] ...
    done(); 
}

%end

#pragma mark - Constructor

%ctor {
    if (![[NSFileManager defaultManager] fileExistsAtPath:kPrefPath]) {
        [@{ @"enabled" : @NO, @"licenseKey" : @"YOUR_LICENSE_KEY", @"modelId" : @(43), @"presetId" : @(88) }
         writeToFile:kPrefPath atomically:YES];
    }
    NSDictionary *p = BCPrefs();
    [CapitalAPI shared].licenseKey = p[@"licenseKey"] ?: @"";
    [CapitalAPI shared].modelId    = [p[@"modelId"]  integerValue] ?: 43;
    [CapitalAPI shared].presetId   = [p[@"presetId"] integerValue] ?: 88;
}

#pragma clang diagnostic pop
