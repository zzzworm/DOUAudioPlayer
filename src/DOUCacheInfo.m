//
//  DOUCacheInfo.m
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/11.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#import "DOUCacheInfo.h"

@interface DOUCacheInfo()

@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *>*> *cachedSegment;

@end

@implementation DOUCacheInfo

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super init]) {
        self.audioFileURL = [aDecoder decodeObjectForKey:@"audioFileURL"];
        self.cacheWritePath = [aDecoder decodeObjectForKey:@"cacheWritePath"];
        self.cacheWriteTmpPath = [aDecoder decodeObjectForKey:@"cacheWriteTmpPath"];
        self.expectedLength = [aDecoder decodeInt64ForKey:@"expectedLength"];
        self.cachedSegment = [aDecoder decodeObjectForKey:@"cachedSegment"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.audioFileURL forKey:@"audioFileURL"];
    [aCoder encodeObject:self.cacheWritePath forKey:@"cacheWritePath"];
    [aCoder encodeObject:self.cacheWriteTmpPath forKey:@"cacheWriteTmpPath"];
    [aCoder encodeInt64:self.expectedLength forKey:@"expectedLength"];
    [aCoder encodeObject:self.cachedSegment forKey:@"cachedSegment"];
}

- (instancetype)init
{
    if (self = [super init]) {
        self.cachedSegment = [NSMutableArray array];
    }
    return self;
}


- (BOOL)rangeAvaible:(NSRange)range
{
    if (0 == self.expectedLength) {
        return NO;
    }
    for (NSArray *aRange in self.ranges) {
        NSUInteger startOffset = [aRange[0] unsignedIntegerValue];
        NSUInteger endOffset = [aRange[1] unsignedIntegerValue];
        
        if (range.location >= startOffset && NSMaxRange(range) <= endOffset) {
            return YES;
        }
    }
    return NO;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    DOUCacheInfo *copy = [[[self class] allocWithZone:zone] init];
    copy.audioFileURL = self.audioFileURL;
    copy.cacheWritePath = self.cacheWritePath;
    copy.cacheWriteTmpPath = self.cacheWriteTmpPath;
    copy.expectedLength = self.expectedLength;
    copy.cachedSegment = [self.cachedSegment copy];
    return copy;
}

- (void)append:(NSRange)range
{
    @synchronized (self) {
        BOOL found = NO;
        for (NSUInteger i=0; i<_cachedSegment.count; i++) {
            NSArray *cachedRange = _cachedSegment[i];
            NSUInteger rangeStart = [cachedRange[0] unsignedIntegerValue];
            NSUInteger rangeEnd = [cachedRange[1] unsignedIntegerValue];
            NSUInteger maxEnd = MAX(rangeEnd, NSMaxRange(range));
            NSUInteger minStart = MIN(rangeStart, range.location);
            NSRange range1 = range;
            NSRange range2 = NSMakeRange(rangeStart, rangeEnd - rangeStart);
            if (NSIntersectionRange(range1, range2).length > 0) { // range intersect
                _cachedSegment[i] = @[@(minStart), @(maxEnd)];
                found = YES;
                break;
            }
        }
        if (!found) {
            [_cachedSegment addObject:@[@(range.location), @(NSMaxRange(range))]];
            [self shrinkRangs];
        }
    }
}

- (NSRange)cachedRangeWithOffset:(NSUInteger)startOffset
{
    NSRange cachedRange = NSMakeRange(startOffset, 0);
    if (startOffset >= self.expectedLength) {
        return cachedRange;
    }
    BOOL found = NO;
    NSArray *ranges = self.ranges;
    for (NSUInteger i=0; i<ranges.count; i++) {
        NSArray<NSNumber *>*range = ranges[i];
        NSUInteger rangeStart = [range[0] unsignedIntegerValue];
        NSUInteger rangeEnd = [range[1] unsignedIntegerValue];
        if (startOffset >= rangeStart && startOffset < rangeEnd) {
            found = YES;
            cachedRange = NSMakeRange(startOffset, rangeEnd - startOffset);
            break;
        }
    }

    NSAssert(cachedRange.location == startOffset, @"not equal to startoffset");
    return cachedRange;
}

- (NSRange)nextNeedCacheRangeWithStartOffset:(NSUInteger)startOffset
{
    if (startOffset > self.expectedLength) {
        return NSMakeRange((NSUInteger)self.expectedLength, 0);
    }
    NSRange needRange = NSMakeRange(0, (NSUInteger)(self.expectedLength-1));
    BOOL found = NO;
    NSArray *ranges = self.ranges;
    for (NSUInteger i=0; i<ranges.count; i++) {
        NSArray<NSNumber *>*range = ranges[i];
        NSUInteger rangeStart = [range[0] unsignedIntegerValue];
        NSUInteger rangeEnd = [range[1] unsignedIntegerValue];
        if (i+1 < ranges.count) {
            NSArray *nextRange = ranges[i+1];
            NSUInteger nextRangeStart = [nextRange[0] unsignedIntegerValue];
            
            if (rangeEnd >= startOffset && nextRangeStart > startOffset && nextRangeStart > rangeEnd) { // left
                needRange.location = rangeEnd;
                needRange.length = nextRangeStart - needRange.location;
                found = YES;
                break;
            }
        }
        else{
            if (rangeStart <= startOffset && rangeEnd > startOffset) { // last
                needRange.location = rangeEnd;
                needRange.length = (unsigned long long)self.expectedLength - needRange.location -1;
                found = YES;
                break;
            }
        }
    }
    if (!found) {
        needRange = NSMakeRange(startOffset, (unsigned long long)self.expectedLength - startOffset - 1);
    }
    NSAssert(needRange.location >= startOffset, @"must greater then or equal to startoffset");
    return needRange;
}

- (void)shrinkRangs
{
    NSMutableArray *mutableRangs = nil;
    @synchronized (self) {
        mutableRangs = [_cachedSegment mutableCopy];
    }
    
    [mutableRangs sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSArray *a1 = obj1;
        NSArray *a2 = obj2;
        return [a1[0] compare:a2[0]];
    }];
    NSArray *preRange = nil;
    NSArray *curRange = nil;
    for (NSUInteger i=1; i<mutableRangs.count; ) {
        preRange = mutableRangs[i-1];
        curRange = mutableRangs[i];
        if ([curRange[0] unsignedIntegerValue] >= [preRange[0] unsignedIntegerValue] &&
            [curRange[1] unsignedIntegerValue] >= [preRange[1] unsignedIntegerValue] &&
            [curRange[0] unsignedIntegerValue] <= [preRange[1] unsignedIntegerValue]) {
            [mutableRangs removeObject:preRange];
            [mutableRangs removeObject:curRange];
            [mutableRangs insertObject:@[preRange[0], curRange[1]] atIndex:i-1];
            continue;
        }
        i++;
    }
    @synchronized (self) {
        _cachedSegment = mutableRangs;
    }
}

- (void)writeToFile:(NSString *)filePath
{
    if (!filePath) return;
    
    [self shrinkRangs];
    NSMutableDictionary *dict =
    [NSMutableDictionary dictionaryWithCapacity:2];
    dict[@"Content-Length"] = @(self.expectedLength);
    dict[@"ranges"] = _cachedSegment;
    dict[@"supportSeek"] = @(self.supportSeek);
    dict[@"audioFileTypeHint"] = @(self.audioFileTypeHint);
    [[NSJSONSerialization
      dataWithJSONObject:dict
      options:0
      error:nil]
     writeToFile:filePath atomically:YES];
}

- (void)clear
{
    @synchronized (self) {
        _cachedSegment = [NSMutableArray array];
    }
    self.expectedLength = 0;
    self.audioFileTypeHint = 0;
    self.supportSeek = NO;
}

- (NSArray *)ranges
{
    @synchronized (self) {
        return [_cachedSegment copy];
    }
}

- (void)setRanges:(NSArray *)ranges
{
    @synchronized (self) {
        _cachedSegment = [ranges mutableCopy];
    }
}


- (BOOL)isCacheCompleted
{
    if (self.ranges.count != 1) {
        return NO;
    }
    return [self.ranges[0][1] unsignedIntegerValue] ==
    self.expectedLength;
}
@end
