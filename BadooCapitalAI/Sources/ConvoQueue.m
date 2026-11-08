#import "ConvoQueue.h"

@implementation BDConvoEntry
@end

@implementation ConvoQueue {
    NSMutableArray<BDConvoEntry *> *_queue;
    dispatch_queue_t _lock;
}

+ (instancetype)shared {
    static ConvoQueue *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    _queue = [NSMutableArray new];
    _lock  = dispatch_queue_create("com.jb.badoocapitalai.queue", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)enqueue:(BDConvoEntry *)entry {
    dispatch_sync(_lock, ^{
        // Remove stale entry for same contact before re-inserting
        [_queue filterUsingPredicate:
            [NSPredicate predicateWithFormat:@"contactId != %@", entry.contactId]];
        [_queue addObject:entry];
        [self _sortLocked];
    });
}

- (void)clear {
    dispatch_sync(_lock, ^{ [_queue removeAllObjects]; });
}

- (nullable BDConvoEntry *)dequeue {
    __block BDConvoEntry *entry;
    dispatch_sync(_lock, ^{
        entry = _queue.firstObject;
        if (entry) [_queue removeObjectAtIndex:0];
    });
    return entry;
}

- (NSUInteger)count {
    __block NSUInteger c;
    dispatch_sync(_lock, ^{ c = _queue.count; });
    return c;
}

// Online first → then most recently active
- (void)_sortLocked {
    [_queue sortUsingComparator:^NSComparisonResult(BDConvoEntry *a, BDConvoEntry *b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? NSOrderedAscending : NSOrderedDescending;
        return [b.lastActivity compare:a.lastActivity]; // newer = higher priority
    }];
}

@end
