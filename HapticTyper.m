#import "HapticTyper.h"
#import <CoreHaptics/CoreHaptics.h>

static NSTimeInterval BCJitterMs(double ms) {
    double u1=(double)arc4random()/(double)UINT32_MAX;
    double u2=(double)arc4random()/(double)UINT32_MAX;
    return ms*(0.6+((u1+u2)/2.0)*0.8)/1000.0;
}

@interface HapticTyper ()
@property (nonatomic, strong, nullable) CHHapticEngine *engine;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation HapticTyper

+ (instancetype)shared {
    static HapticTyper *s; static dispatch_once_t t;
    dispatch_once(&t,^{s=[self new];}); return s;
}
- (instancetype)init { self=[super init]; if(self)[self _setup]; return self; }

- (void)_setup {
    if(![CHHapticEngine capabilitiesForHardware].supportsHaptics) return;
    NSError *e;
    _engine=[[CHHapticEngine alloc] initAndReturnError:&e];
    if(e||!_engine) return;
    __weak typeof(self) w=self;
    _engine.resetHandler=^{ NSError *se; [w.engine startAndReturnError:&se]; };
    _engine.stoppedHandler=^(CHHapticEngineStoppedReason r){};
    [_engine startAndReturnError:&e];
}

- (void)_playTap {
    if(!_engine) return;
    NSError *e;
    CHHapticEventParameter *intensity=[[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticIntensity value:0.3f];
    CHHapticEventParameter *sharpness=[[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticSharpness value:0.5f];
    CHHapticEvent *ev=[[CHHapticEvent alloc]
        initWithEventType:CHHapticEventTypeHapticTransient
               parameters:@[intensity,sharpness] relativeTime:0];
    CHHapticPattern *pat=[[CHHapticPattern alloc] initWithEvents:@[ev] parameters:@[] error:&e];
    if(e||!pat) return;
    id<CHHapticPatternPlayer> p=[_engine createPlayerWithPattern:pat error:&e];
    if(!e) [p startAtTime:0 error:nil];
}

- (void)cancel { self.cancelled=YES; }

- (void)typeText:(NSString *)text
   intoResponder:(UIResponder<UITextInput> *)r
      completion:(nullable HapticTyperCompletion)done {
    self.cancelled=NO;
    NSMutableArray<NSString *> *chars=[NSMutableArray new];
    [text enumerateSubstringsInRange:NSMakeRange(0,text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *_Nullable s,NSRange rr __unused,
                                       NSRange er __unused,BOOL *stop __unused){
        if(s)[chars addObject:s];
    }];
    [self _type:chars index:0 into:r completion:done];
}

- (void)_type:(NSArray<NSString *> *)chars index:(NSUInteger)i
         into:(UIResponder<UITextInput> *)r
   completion:(nullable HapticTyperCompletion)done {
    if(self.cancelled||i>=chars.count){
        dispatch_async(dispatch_get_main_queue(),^{if(done)done();}); return;
    }
    NSString *ch=chars[i];
    BOOL space=[ch isEqualToString:@" "]||[ch isEqualToString:@"\n"];
    BOOL typo=!space&&(arc4random_uniform(100)<4);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(BCJitterMs(90)*NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{
        if(self.cancelled){if(done)done();return;}
        if(typo){
            [r insertText:[self _near:ch]]; [self _playTap];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(BCJitterMs(120)*NSEC_PER_SEC)),
                           dispatch_get_main_queue(),^{
                [r deleteBackward];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(BCJitterMs(70)*NSEC_PER_SEC)),
                               dispatch_get_main_queue(),^{
                    [r insertText:ch];[self _playTap];
                    [self _type:chars index:i+1 into:r completion:done];
                });
            });
        } else {
            [r insertText:ch];[self _playTap];
            [self _type:chars index:i+1 into:r completion:done];
        }
    });
}

- (NSString *)_near:(NSString *)ch {
    static NSDictionary<NSString*,NSString*> *adj; static dispatch_once_t t;
    dispatch_once(&t,^{ adj=@{@"a":@"sq",@"b":@"vn",@"c":@"xv",@"d":@"sf",@"e":@"wr",
        @"f":@"dg",@"g":@"fh",@"h":@"gj",@"i":@"uo",@"j":@"hk",@"k":@"jl",@"l":@"k",
        @"m":@"n",@"n":@"bm",@"o":@"ip",@"p":@"o",@"q":@"w",@"r":@"et",@"s":@"ad",
        @"t":@"ry",@"u":@"yi",@"v":@"cb",@"w":@"qe",@"x":@"zc",@"y":@"tu",@"z":@"x"}; });
    NSString *n=adj[ch.lowercaseString];
    if(!n.length) return ch;
    return [n substringWithRange:NSMakeRange(arc4random_uniform((uint32_t)n.length),1)];
}
@end
