/*
 * BadooCapitalAI — Tweak.x
 *
 * Hook targets (class names verified on Badoo 5.x, dopamine 17.03 / ElleKit):
 *   BDChatConversationListViewController  — conversation list
 *   BDChatConversationViewController      — open conversation / send bar
 *   BDConversationModel / BDMessageModel  — data layer
 *
 * shortcut: class names may change across Badoo updates; re-dump with
 *           `class-dump -H Badoo.app` after each major Badoo release
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "CapitalAPI.h"
#import "ConvoQueue.h"
#import "HapticTyper.h"

// Declare hook targets as UIViewController subclasses so Clang knows their
// inherited UIKit methods/properties while Logos generates the runtime hooks.
@interface BDChatConversationListViewController : UIViewController @end
@interface BDChatConversationViewController : UIViewController @end

// ─── Config (read from /var/mobile/Library/Preferences/com.jb.badoocapitalai.plist) ─────
static NSDictionary *_prefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.jb.badoocapitalai.plist"];
}

static BOOL _enabled(void) {
    return [_prefs()[@"enabled"] boolValue];
}

// ─── Helpers ──────────────────────────────────────────────────────────────────────────────

/// Convert BDMessageModel array → Capital AI chatHistory array
static NSArray<NSDictionary *> *_buildHistory(NSArray *messages) {
    NSMutableArray *out = [NSMutableArray new];
    for (id msg in messages) {
        // BDMessageModel properties: text, senderId, timestamp (NSDate)
        NSString *text = [msg valueForKey:@"text"] ?: @"";
        NSDate   *date = [msg valueForKey:@"timestamp"];
        BOOL      mine = [[msg valueForKey:@"isOwn"] boolValue];

        // skip empty / media-only messages (use marker if media present)
        if (!text.length) {
            NSString *mediaType = [msg valueForKey:@"mediaType"]; // "photo","video","audio"
            if ([mediaType isEqualToString:@"photo"])  text = @"*IMAGE*";
            else if ([mediaType isEqualToString:@"video"]) text = @"*VIDEO*";
            else if ([mediaType isEqualToString:@"audio"]) text = @"*AUDIO*";
            else continue;
        }

        [out addObject:@{
            @"role"      : mine ? @"bot" : @"user",
            @"content"   : text,
            @"timestamp" : @((NSInteger)[date timeIntervalSince1970] ?: (NSInteger)[[NSDate date] timeIntervalSince1970])
        }];
    }
    return out;
}

/// Random human-like pause before "sending" (1.5 – 4 s)
static NSTimeInterval _thinkDelay(NSString *text) {
    double base = 1.5 + (double)arc4random_uniform(25) / 10.0;
    // Longer text → slightly longer pause (max +2 s)
    double wordBonus = MIN(text.length / 60.0, 2.0);
    return base + wordBonus;
}

// ─── Global state ─────────────────────────────────────────────────────────────────────────
static BOOL _processingQueue = NO;

// ─── Hooks ────────────────────────────────────────────────────────────────────────────────

#pragma mark - Conversation List (populate queue)

%hook BDChatConversationListViewController

/// Called whenever the list reloads (new message, online status change, etc.)
- (void)reloadData {
    %orig;
    if (!_enabled()) return;

    // Pull conversation models from the data source
    // Badoo stores them in `self.dataSource.conversations` or similar
    NSArray *convos = [[self valueForKey:@"dataSource"] valueForKey:@"conversations"];
    if (!convos.count) return;

    [[ConvoQueue shared] clear];

    for (id convo in convos) {
        NSString *cid  = [convo valueForKey:@"userId"] ?: [convo valueForKey:@"conversationId"];
        NSString *name = [convo valueForKey:@"name"]   ?: @"";
        BOOL online    = [[convo valueForKey:@"isOnline"] boolValue];
        NSDate *act    = [convo valueForKey:@"lastMessageDate"] ?: [NSDate distantPast];
        NSArray *msgs  = [convo valueForKey:@"messages"] ?: @[];

        // Skip if WE sent the last message (no new incoming to reply to)
        id lastMsg = msgs.lastObject;
        if ([[lastMsg valueForKey:@"isOwn"] boolValue]) continue;

        BDConvoEntry *e = [BDConvoEntry new];
        e.contactId   = cid;
        e.contactName = name;
        e.isOnline    = online;
        e.lastActivity = act;
        e.chatHistory = _buildHistory(msgs);

        [[ConvoQueue shared] enqueue:e];
    }

    [self _startProcessingQueueIfNeeded];
}

%new
- (void)_startProcessingQueueIfNeeded {
    if (_processingQueue) return;
    if (![ConvoQueue shared].count) return;
    _processingQueue = YES;
    [self _processNextEntry];
}

%new
- (void)_processNextEntry {
    BDConvoEntry *entry = [[ConvoQueue shared] dequeue];
    if (!entry) {
        _processingQueue = NO;
        return;
    }

    [[CapitalAPI shared] generateResponse:entry.chatHistory
                                contactId:entry.contactId
                               contactName:entry.contactName
                               completion:^(NSArray<NSDictionary *> *content, NSDictionary *stats, NSError *error) {
        if (error || !content.count) {
            // back-off 3 s, try next
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                [self _processNextEntry];
            });
            return;
        }

        // Open the conversation and send, with human-like delay
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _openAndSend:content toContactId:entry.contactId];
        });
    }];
}

%new
- (void)_openAndSend:(NSArray<NSDictionary *> *)content toContactId:(NSString *)contactId {
    // Navigate to the conversation — tap the matching cell
    UITableView *tv = [self valueForKey:@"tableView"];
    NSArray *convos = [[self valueForKey:@"dataSource"] valueForKey:@"conversations"];

    NSUInteger row = NSNotFound;
    for (NSUInteger i = 0; i < convos.count; i++) {
        NSString *cid = [convos[i] valueForKey:@"userId"]
                     ?: [convos[i] valueForKey:@"conversationId"];
        if ([cid isEqualToString:contactId]) { row = i; break; }
    }
    if (row == NSNotFound) { [self _processNextEntry]; return; }

    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    [tv selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
    [tv.delegate tableView:tv didSelectRowAtIndexPath:ip];

    // Store pending content for the conversation VC to pick up
    objc_setAssociatedObject(self, "pendingContent", content, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "pendingContactId", contactId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

#pragma mark - Conversation View (type & send)

%hook BDChatConversationViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!_enabled()) return;

    // Check if list VC has pending content for us
    UINavigationController *nav = self.navigationController;
    BDChatConversationListViewController *listVC =
        (id)[nav.viewControllers firstObject];

    NSArray *content   = objc_getAssociatedObject(listVC, "pendingContent");
    NSString *targetId = objc_getAssociatedObject(listVC, "pendingContactId");

    if (!content.count) return;

    NSString *myContactId = [[self valueForKey:@"conversation"]
                              valueForKey:@"userId"]
                          ?: [[self valueForKey:@"conversation"]
                              valueForKey:@"conversationId"];

    if (![myContactId isEqualToString:targetId]) return;

    // Clear pending so we don't re-send
    objc_setAssociatedObject(listVC, "pendingContent", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(listVC, "pendingContactId", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self _deliverContent:content];
}

%new
- (void)_deliverContent:(NSArray<NSDictionary *> *)content {
    if (!content.count) {
        // Pop back to list and continue queue
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:NO];
            BDChatConversationListViewController *lvc =
                (id)[self.navigationController.viewControllers firstObject];
            [lvc _processNextEntry];
        });
        return;
    }

    NSDictionary *item = content.firstObject;
    NSMutableArray *remaining = [content mutableCopy];
    [remaining removeObjectAtIndex:0];

    NSString *type = item[@"type"];

    if ([type isEqualToString:@"text"]) {
        NSString *text = item[@"content"] ?: @"";

        // Find the input field
        UITextField *inputField = [self _findInputField];

        double delay = _thinkDelay(text);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{

            if (inputField) {
                [[HapticTyper shared] typeText:text
                                 intoResponder:inputField
                                   completion:^{
                    // Tap send after a short pause (100-300 ms)
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                   (int64_t)(0.2 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        [self _tapSend];
                        // Inter-bubble pause before next content item (0.8–1.6 s)
                        double pause = 0.8 + (double)arc4random_uniform(8) / 10.0;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pause * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            [self _deliverContent:remaining];
                        });
                    });
                }];
            } else {
                // Fallback: call Badoo's internal send method directly
                [self _sendTextDirect:text];
                [self _deliverContent:remaining];
            }
        });

    } else if ([type isEqualToString:@"image"] || [type isEqualToString:@"video"]) {
        // Media: download from Capital CDN and send via Badoo's share sheet
        NSString *url = item[@"content"];
        [self _sendMediaFromURL:url type:type completion:^{
            [self _deliverContent:remaining];
        }];

    } else {
        // Unknown type — skip
        [self _deliverContent:remaining];
    }
}

%new
- (UITextField *)_findInputField {
    // Walk the view hierarchy for the message compose field
    return (UITextField *)[self _findViewOfClass:[UITextField class] in:self.view];
}

%new
- (UIView *)_findViewOfClass:(Class)cls in:(UIView *)root {
    if ([root isKindOfClass:cls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = [self _findViewOfClass:cls in:sub];
        if (found) return found;
    }
    return nil;
}

%new
- (void)_tapSend {
    // Look for a send button ("Send", "▶", UIButton with tag 42, etc.)
    UIButton *sendBtn = (UIButton *)[self _findSendButton:self.view];
    if (sendBtn) {
        [sendBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
        return;
    }
    // Fallback: Badoo's internal send selector
    if ([self respondsToSelector:@selector(sendButtonTapped:)]) {
        [self performSelector:@selector(sendButtonTapped:) withObject:nil];
    }
}

%new
- (UIView *)_findSendButton:(UIView *)root {
    if ([root isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)root;
        NSString *title = [btn titleForState:UIControlStateNormal];
        if ([title containsString:@"Send"] || [title containsString:@"▶"] || btn.tag == 42) {
            return btn;
        }
    }
    for (UIView *sub in root.subviews) {
        UIView *f = [self _findSendButton:sub];
        if (f) return f;
    }
    return nil;
}

%new
- (void)_sendTextDirect:(NSString *)text {
    // Try Badoo's internal send method signatures (varies by version)
    SEL selectors[] = {
        @selector(sendMessage:),
        @selector(sendTextMessage:),
        @selector(sendChatMessage:),
    };
    for (int i = 0; i < 3; i++) {
        if ([self respondsToSelector:selectors[i]]) {
            [self performSelector:selectors[i] withObject:text];
            return;
        }
    }
    // Last resort: set text field value and fire notification
    UITextField *tf = [self _findInputField];
    if (tf) {
        tf.text = text;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:UITextFieldTextDidChangeNotification object:tf];
        [self _tapSend];
    }
}

%new
- (void)_sendMediaFromURL:(NSString *)urlStr type:(NSString *)type completion:(void(^)(void))done {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { done(); return; }

    [[[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
            if (!data || e) { dispatch_async(dispatch_get_main_queue(), done); return; }

            dispatch_async(dispatch_get_main_queue(), ^{
                // Write to temp file, hand to Badoo's media picker flow
                NSString *ext = [type isEqualToString:@"video"] ? @"mp4" : @"jpg";
                NSURL *tmp = [NSURL fileURLWithPath:
                    [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"cap_%@.%@",
                         [[NSUUID UUID] UUIDString], ext]]];
                [data writeToURL:tmp atomically:YES];

                // Try Badoo's internal attach method
                SEL attSel = NSSelectorFromString(@"attachMediaAtURL:");
                if ([self respondsToSelector:attSel]) {
                    [self performSelector:attSel withObject:tmp];
                }
                // Inter-bubble pause
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), done);
            });
    }] resume];
}

%end

#pragma mark - Settings plist bootstrap (first launch)

%ctor {
    // Write default prefs if none exist
    NSString *path = @"/var/mobile/Library/Preferences/com.jb.badoocapitalai.plist";
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSDictionary *defaults = @{
            @"enabled"    : @NO,
            @"licenseKey" : @"YOUR_LICENSE_KEY",
            @"modelId"    : @(43),
            @"presetId"   : @(88),
        };
        [defaults writeToFile:path atomically:YES];
    }

    NSDictionary *prefs = _prefs();
    [CapitalAPI shared].licenseKey = prefs[@"licenseKey"] ?: @"";
    [CapitalAPI shared].modelId    = [prefs[@"modelId"] integerValue] ?: 43;
    [CapitalAPI shared].presetId   = [prefs[@"presetId"] integerValue] ?: 88;
}
