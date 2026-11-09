#import "BCEngine.h"
#import "CapitalAPI.h"
#import "ConvoQueue.h"
#import "HapticTyper.h"
#import <objc/runtime.h>

static NSString *const kPrefPath =
    @"/var/mobile/Library/Preferences/com.jb.badoocapitalai.plist";
static NSDictionary *BCPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kPrefPath] ?: @{};
}
BOOL BCEnabled(void) { return [BCPrefs()[@"enabled"] boolValue]; }

static const char kContent[] = "bcai_c";
static const char kCid[]     = "bcai_i";
static BOOL BCActive          = NO;
static __weak UIViewController *sListVC = nil;

static NSTimeInterval TKJitter(double ms) {
    double u1=(double)arc4random()/(double)UINT32_MAX;
    double u2=(double)arc4random()/(double)UINT32_MAX;
    return ms*(0.6+((u1+u2)/2.0)*0.8)/1000.0;
}
static NSTimeInterval BCThink(NSString *t) {
    return 1.5+(double)arc4random_uniform(25)/10.0+MIN((double)t.length/60.0,2.0);
}
static NSArray<NSDictionary *> *BCHistory(NSArray *msgs) {
    NSMutableArray *out=[NSMutableArray new];
    NSTimeInterval now=[[NSDate date] timeIntervalSince1970];
    for(id m in msgs){
        NSString *text=[m valueForKey:@"text"]?:@"";
        NSDate *date=[m valueForKey:@"timestamp"];
        BOOL mine=[[m valueForKey:@"isOwn"] boolValue];
        NSString *media=[m valueForKey:@"mediaType"];
        if(!text.length){
            if([media isEqualToString:@"photo"])      text=@"*IMAGE*";
            else if([media isEqualToString:@"video"]) text=@"*VIDEO*";
            else if([media isEqualToString:@"audio"]) text=@"*AUDIO*";
            else continue;
        }
        [out addObject:@{
            @"role":mine?@"bot":@"user",
            @"content":text,
            @"timestamp":@(date?(NSInteger)[date timeIntervalSince1970]:(NSInteger)now)
        }];
    }
    return out;
}

static UIView *BCFindView(Class cls, UIView *root) {
    if([root isKindOfClass:cls]) return root;
    for(UIView *s in root.subviews){ UIView *f=BCFindView(cls,s); if(f) return f; }
    return nil;
}
static UIButton *BCFindSend(UIView *root) {
    if([root isKindOfClass:[UIButton class]]){
        UIButton *b=(UIButton *)root;
        if([[b titleForState:UIControlStateNormal] containsString:@"Send"]||b.tag==42) return b;
    }
    for(UIView *s in root.subviews){ UIButton *f=BCFindSend(s); if(f) return f; }
    return nil;
}
static void BCInvoke(id target, SEL sel, id _Nullable arg) {
    NSMethodSignature *sig=[target methodSignatureForSelector:sel];
    NSInvocation *inv=[NSInvocation invocationWithMethodSignature:sig];
    inv.target=target; inv.selector=sel;
    if(arg) [inv setArgument:&arg atIndex:2];
    [inv invoke];
}
static void BCTapSend(UIViewController *vc) {
    UIButton *btn=BCFindSend(vc.view);
    if(btn){ [btn sendActionsForControlEvents:UIControlEventTouchUpInside]; return; }
    SEL ss[]={NSSelectorFromString(@"sendButtonTapped:"),
               NSSelectorFromString(@"sendMessage:"),
               NSSelectorFromString(@"didTapSendButton:")};
    for(int i=0;i<3;i++) if([vc respondsToSelector:ss[i]]){ BCInvoke(vc,ss[i],nil); return; }
}
static void BCSendText(UIViewController *vc, NSString *text) {
    SEL ss[]={NSSelectorFromString(@"sendMessage:"),
               NSSelectorFromString(@"sendTextMessage:"),
               NSSelectorFromString(@"sendChatMessage:")};
    for(int i=0;i<3;i++) if([vc respondsToSelector:ss[i]]){ BCInvoke(vc,ss[i],text); return; }
    UITextField *f=(UITextField *)BCFindView([UITextField class],vc.view);
    if(f){ f.text=text; BCTapSend(vc); }
}

static void BCDeliver(NSArray *content, UIViewController *convoVC);
static void BCProcessNext(void);

static void BCDeliver(NSArray *content, UIViewController *convoVC) {
    if(!content.count){
        dispatch_async(dispatch_get_main_queue(),^{
            [convoVC.navigationController popViewControllerAnimated:NO];
            BCProcessNext();
        });
        return;
    }
    NSMutableArray *rest=[content mutableCopy];
    NSDictionary *item=rest.firstObject; [rest removeObjectAtIndex:0];
    NSString *type=item[@"type"]?:@"text";
    NSString *body=item[@"content"]?:@"";

    if([type isEqualToString:@"text"]){
        UITextField *field=(UITextField *)BCFindView([UITextField class],convoVC.view);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(BCThink(body)*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{
            if(field){
                [[HapticTyper shared] typeText:body intoResponder:field completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(TKJitter(200)*NSEC_PER_SEC)),
                                   dispatch_get_main_queue(),^{
                        BCTapSend(convoVC);
                        double p=0.8+(double)arc4random_uniform(8)/10.0;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(p*NSEC_PER_SEC)),
                                       dispatch_get_main_queue(),^{ BCDeliver(rest,convoVC); });
                    });
                }];
            } else {
                BCSendText(convoVC,body);
                BCDeliver(rest,convoVC);
            }
        });
    } else if([type isEqualToString:@"image"]||[type isEqualToString:@"video"]){
        NSURL *url=[NSURL URLWithString:body];
        if(!url){ BCDeliver(rest,convoVC); return; }
        [[[NSURLSession sharedSession] dataTaskWithURL:url
            completionHandler:^(NSData *data,NSURLResponse *r,NSError *e){
                if(!data){ dispatch_async(dispatch_get_main_queue(),^{BCDeliver(rest,convoVC);}); return; }
                dispatch_async(dispatch_get_main_queue(),^{
                    NSString *ext=[type isEqualToString:@"video"]?@"mp4":@"jpg";
                    NSURL *tmp=[NSURL fileURLWithPath:
                        [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [[NSUUID UUID].UUIDString stringByAppendingPathExtension:ext]]];
                    [data writeToURL:tmp atomically:YES];
                    SEL s=NSSelectorFromString(@"attachMediaAtURL:");
                    if([convoVC respondsToSelector:s]) BCInvoke(convoVC,s,tmp);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.2*NSEC_PER_SEC)),
                                   dispatch_get_main_queue(),^{BCDeliver(rest,convoVC);});
                });
        }] resume];
    } else {
        BCDeliver(rest,convoVC);
    }
}

static void BCProcessNext(void) {
    BDConvoEntry *e=[[ConvoQueue shared] dequeue];
    if(!e){ BCActive=NO; return; }
    [[CapitalAPI shared] generateResponse:e.chatHistory
                                contactId:e.contactId
                              contactName:e.contactName
                               completion:^(NSArray *content,NSDictionary *stats,NSError *err){
        if(err||!content.count){
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),
                dispatch_get_main_queue(),^{BCProcessNext();});
            return;
        }
        dispatch_async(dispatch_get_main_queue(),^{
            UIViewController *lvc=sListVC;
            if(!lvc){ BCProcessNext(); return; }
            UITableView *tv=[lvc valueForKey:@"tableView"];
            NSArray *convos=[[lvc valueForKey:@"dataSource"] valueForKey:@"conversations"];
            NSUInteger row=NSNotFound;
            for(NSUInteger i=0;i<convos.count;i++){
                NSString *v=[convos[i] valueForKey:@"userId"]?:[convos[i] valueForKey:@"conversationId"];
                if([v isEqualToString:e.contactId]){ row=i; break; }
            }
            if(row==NSNotFound){ BCProcessNext(); return; }
            objc_setAssociatedObject(lvc,kContent,content,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(lvc,kCid,e.contactId,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSIndexPath *ip=[NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
            [tv selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
            [tv.delegate tableView:tv didSelectRowAtIndexPath:ip];
        });
    }];
}

@implementation BCEngine

+ (void)listVCReloaded:(UIViewController *)listVC {
    if(!BCEnabled()) return;
    sListVC=listVC;
    id ds=[listVC valueForKey:@"dataSource"];
    NSArray *c=[ds valueForKey:@"conversations"];
    if(!c.count) return;
    [[ConvoQueue shared] clear];
    for(id cv in c){
        NSString *cid=[cv valueForKey:@"userId"]?:[cv valueForKey:@"conversationId"];
        NSArray *msgs=[cv valueForKey:@"messages"]?:@[];
        if([[msgs.lastObject valueForKey:@"isOwn"] boolValue]) continue;
        BDConvoEntry *e=[BDConvoEntry new];
        e.contactId   =cid;
        e.contactName =[cv valueForKey:@"name"]?:@"";
        e.isOnline    =[[cv valueForKey:@"isOnline"] boolValue];
        e.lastActivity=[cv valueForKey:@"lastMessageDate"]?:[NSDate distantPast];
        e.chatHistory =BCHistory(msgs);
        [[ConvoQueue shared] enqueue:e];
    }
    if(BCActive||![ConvoQueue shared].count) return;
    BCActive=YES;
    BCProcessNext();
}

+ (void)convoVCAppeared:(UIViewController *)convoVC {
    if(!BCEnabled()) return;
    UIViewController *listVC=nil;
    for(UIViewController *vc in convoVC.navigationController.viewControllers)
        if([vc isKindOfClass:NSClassFromString(@"BDChatConversationListViewController")]){
            listVC=vc; break;
        }
    if(!listVC) return;
    NSArray  *content=objc_getAssociatedObject(listVC,kContent);
    NSString *target =objc_getAssociatedObject(listVC,kCid);
    if(!content.count) return;
    id conv=[convoVC valueForKey:@"conversation"];
    NSString *my=[conv valueForKey:@"userId"]?:[conv valueForKey:@"conversationId"];
    if(![my isEqualToString:target]) return;
    objc_setAssociatedObject(listVC,kContent,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(listVC,kCid,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BCDeliver(content,convoVC);
}

@end
