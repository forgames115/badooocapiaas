#import "HapticTyper.h"
#import <CoreHaptics/CoreHaptics.h>

// Gaussian-ish jitter: average two uniforms (Box-Muller lite)
static double jitteredDelay(double baseMs) {
    double u1 = (double)arc4random() / UINT32_MAX;
    double u2 = (double)arc4random() / UINT32_MAX;
    double gauss = (u1 + u2) / 2.0; // 0..1, bell-ish
    // Map to base ± 40%
    return baseMs * (0.6 + gauss * 0.8) / 1000.0;
}

@interface HapticTyper () <CHHapticEngineDelegate>
@property (nonatomic, strong) CHHapticEngine *hapticEngine;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation HapticTyper

+ (instancetype)shared {
    static HapticTyper *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    [self _setupHaptics];
    return self;
}

- (void)_setupHaptics {
    if (!CHHapticEngine.capabilitiesForHardware.supportsHaptics) return;
    NSError *err;
    _hapticEngine = [[CHHapticEngine alloc] initAndReturnError:&err];
    if (!err) {
        _hapticEngine.delegate = self;
        [_hapticEngine startWithCompletionHandler:nil];
    }
}

- (void)_playKeystroke {
    if (!_hapticEngine) return;
    CHHapticEventParameter *intensity =
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                      value:0.35f];
    CHHapticEventParameter *sharpness =
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness
                                                      value:0.6f];
    CHHapticEvent *event =
        [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient
                                      parameters:@[intensity, sharpness]
                                    relativeTime:0];
    NSError *err;
    id<CHHapticPatternPlayer> player =
        [_hapticEngine createPlayerWithPattern:
            [[CHHapticPattern alloc] initWithEvents:@[event] parameters:@[] error:&err]
                                         error:&err];
    [player startAtTime:0 error:&err];
}

- (void)cancel {
    self.cancelled = YES;
}

- (void)typeText:(NSString *)text
   intoResponder:(UIResponder<UITextInput> *)responder
      completion:(nullable HapticTyperCompletion)completion {

    self.cancelled = NO;
    NSArray<NSString *> *chars = [self _splitChars:text];
    [self _typeChars:chars
               index:0
          responder:responder
         completion:completion];
}

- (void)_typeChars:(NSArray<NSString *> *)chars
             index:(NSUInteger)i
         responder:(UIResponder<UITextInput> *)responder
        completion:(nullable HapticTyperCompletion)completion {

    if (self.cancelled || i >= chars.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion();
        });
        return;
    }

    NSString *ch = chars[i];

    // 4% chance of a typo-then-backspace sequence (skip on spaces/newlines)
    BOOL doTypo = (arc4random_uniform(100) < 4) && ![ch isEqualToString:@" "] && ![ch isEqualToString:@"\n"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                   (int64_t)(jitteredDelay(90) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{

        if (self.cancelled) { if (completion) completion(); return; }

        if (doTypo) {
            // Insert a random adjacent key
            NSString *typo = [self _nearbyKey:ch];
            [self _insertChar:typo into:responder];
            [self _playKeystroke];

            // Short pause, then delete
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                           (int64_t)(jitteredDelay(120) * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self _deleteCharFrom:responder];
                // Then type the real char
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                               (int64_t)(jitteredDelay(80) * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [self _insertChar:ch into:responder];
                    [self _playKeystroke];
                    [self _typeChars:chars index:i+1 responder:responder completion:completion];
                });
            });
        } else {
            [self _insertChar:ch into:responder];
            [self _playKeystroke];
            [self _typeChars:chars index:i+1 responder:responder completion:completion];
        }
    });
}

- (void)_insertChar:(NSString *)ch into:(UIResponder<UITextInput> *)responder {
    UITextRange *sel = responder.selectedTextRange;
    if (!sel) return;
    [responder insertText:ch];
}

- (void)_deleteCharFrom:(UIResponder<UITextInput> *)responder {
    [responder deleteBackward];
}

- (NSString *)_nearbyKey:(NSString *)ch {
    // Minimal QWERTY adjacency map — just enough to look plausible
    NSDictionary *adj = @{
        @"a":@"sq", @"b":@"vn", @"c":@"xv", @"d":@"sf", @"e":@"wr",
        @"f":@"dg", @"g":@"fh", @"h":@"gj", @"i":@"uo", @"j":@"hk",
        @"k":@"jl", @"l":@"k",  @"m":@"n",  @"n":@"bm", @"o":@"ip",
        @"p":@"o",  @"q":@"w",  @"r":@"et", @"s":@"ad", @"t":@"ry",
        @"u":@"yi", @"v":@"cb", @"w":@"qe", @"x":@"zc", @"y":@"tu",
        @"z":@"x"
    };
    NSString *lower = ch.lowercaseString;
    NSString *neighbors = adj[lower];
    if (!neighbors.length) return ch;
    NSUInteger pick = arc4random_uniform((uint32_t)neighbors.length);
    return [neighbors substringWithRange:NSMakeRange(pick, 1)];
}

- (NSArray<NSString *> *)_splitChars:(NSString *)str {
    NSMutableArray *arr = [NSMutableArray new];
    [str enumerateSubstringsInRange:NSMakeRange(0, str.length)
                            options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString *sub, NSRange r, NSRange er, BOOL *stop) {
        [arr addObject:sub];
    }];
    return arr;
}

#pragma mark - CHHapticEngineDelegate

- (void)hapticEngineDidStop:(CHHapticEngine *)engine withStoppedReason:(NSError *)error {
    // silent — haptics are optional
}

- (void)hapticEngineReset:(CHHapticEngine *)engine {
    [engine startWithCompletionHandler:nil];
}

@end
