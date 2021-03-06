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

+ (instancetype)cacheInfoWithFilePath:(NSString *)filePath
{
    if (!filePath) return nil;
    
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) return [[DOUCacheInfo alloc] init];
    NSDictionary *dict = [NSJSONSerialization
                          JSONObjectWithData:data
                          options:0
                          error:nil];
    DOUCacheInfo *meta = [[DOUCacheInfo alloc] init];
    meta.expectedLength = [dict[@"Content-Length"] unsignedLongLongValue];
    meta.ranges = dict[@"ranges"];
    meta.supportSeek = [dict[@"supportSeek"] boolValue];
    meta.audioFileTypeHint = (AudioFileTypeID)[dict[@"audioFileTypeHint"] unsignedIntegerValue];
    meta.audioFileURL = dict[@"audioFileURL"];
    if (!meta.ranges) {
        meta.ranges = [NSMutableArray array];
    }
    return meta;
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
            NSRange range2 = NSMakeRange(rangeStart, rangeEnd - rangeStart);
            NSRange unionRange = NSUnionRange(range, range2);
            if (NSIntersectionRange(range, range2).length > 0 || unionRange.length == range.length + range2.length ) { // range intersect
                _cachedSegment[i] = @[@(unionRange.location), @(NSMaxRange(unionRange))];
                found = YES;
                break;
            }
        }
        if (!found) {
            [_cachedSegment addObject:@[@(range.location), @(NSMaxRange(range))]];
        }
        [self shrinkRangs];
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
        return NSMakeRange((NSUInteger)self.expectedLength-1, 0);
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
    NSArray<NSNumber*> *preRangeArray = nil;
    NSArray<NSNumber*> *curRangeArray = nil;
    for (NSUInteger i=1; i<mutableRangs.count; ) {
        preRangeArray = mutableRangs[i-1];
        curRangeArray = mutableRangs[i];
        NSRange preRange = NSMakeRange(preRangeArray.firstObject.unsignedIntegerValue, preRangeArray.lastObject.unsignedIntegerValue - preRangeArray.firstObject.unsignedIntegerValue);
        NSRange curRange = NSMakeRange(curRangeArray.firstObject.unsignedIntegerValue, curRangeArray.lastObject.unsignedIntegerValue - curRangeArray.firstObject.unsignedIntegerValue);
        NSRange unionRange = NSUnionRange(preRange, curRange);
        if (NSIntersectionRange(preRange, curRange).length > 0  || unionRange.length == curRange.length + preRange.length) {
            [mutableRangs removeObject:preRangeArray];
            [mutableRangs removeObject:curRangeArray];
            [mutableRangs insertObject:@[@(unionRange.location), @(NSMaxRange(unionRange))] atIndex:i-1];
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
    dict[@"audioFileURL"] = _audioFileURL;
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
