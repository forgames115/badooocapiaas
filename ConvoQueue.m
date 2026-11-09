#import "ConvoQueue.h"
@implementation BDConvoEntry @end
@implementation ConvoQueue {
    NSMutableArray<BDConvoEntry *> *_items;
    dispatch_queue_t                _lock;
}
+ (instancetype)shared {
    static ConvoQueue *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; }); return s;
}
- (instancetype)init {
    self = [super init];
    _items = [NSMutableArray new];
    _lock  = dispatch_queue_create("com.jb.bcai.q", DISPATCH_QUEUE_SERIAL);
    return self;
}
- (void)enqueue:(BDConvoEntry *)entry {
    dispatch_sync(_lock, ^{
        NSMutableIndexSet *ix = [NSMutableIndexSet new];
        [_items enumerateObjectsUsingBlock:^(BDConvoEntry *e, NSUInteger i, BOOL *s) {
            if ([e.contactId isEqualToString:entry.contactId]) [ix addIndex:i];
        }];
        [_items removeObjectsAtIndexes:ix];
        [_items addObject:entry];
        [_items sortUsingComparator:^NSComparisonResult(BDConvoEntry *a, BDConvoEntry *b) {
            if (a.isOnline != b.isOnline) return a.isOnline ? NSOrderedAscending : NSOrderedDescending;
            return [b.lastActivity compare:a.lastActivity];
        }];
    });
}
- (void)clear { dispatch_sync(_lock, ^{ [_items removeAllObjects]; }); }
- (nullable BDConvoEntry *)dequeue {
    __block BDConvoEntry *e = nil;
    dispatch_sync(_lock, ^{ e = _items.firstObject; if (e) [_items removeObjectAtIndex:0]; });
    return e;
}
- (NSUInteger)count { __block NSUInteger c=0; dispatch_sync(_lock,^{c=_items.count;}); return c; }
@end
