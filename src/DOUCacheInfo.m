//
//  DOUCacheInfo.m
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/11.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#import "DOUCacheInfo.h"

@implementation DOUCacheInfo

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super init]) {
        self.audioFileURL = [aDecoder decodeObjectForKey:@"audioFileURL"];
        self.cacheWritePath = [aDecoder decodeObjectForKey:@"cacheWritePath"];
        self.cacheWriteTmpPath = [aDecoder decodeObjectForKey:@"cacheWriteTmpPath"];
        self.expectedLength = [aDecoder decodeIntegerForKey:@"expectedLength"];
        self.cachedSegment = [aDecoder decodeObjectForKey:@"cachedSegment"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.audioFileURL forKey:@"audioFileURL"];
    [aCoder encodeObject:self.cacheWritePath forKey:@"cacheWritePath"];
    [aCoder encodeObject:self.cacheWriteTmpPath forKey:@"cacheWriteTmpPath"];
    [aCoder encodeInteger:self.expectedLength forKey:@"expectedLength"];
    [aCoder encodeObject:self.cachedSegment forKey:@"cachedSegment"];
}

- (NSUInteger)receivedLength
{
    __block NSUInteger receivedLength = 0;
    [self.cachedSegment enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
        receivedLength += obj.unsignedIntegerValue;
    }];
    return receivedLength;
}

- (BOOL)isCacheCompleted
{
    if (0 == self.expectedLength) {
        return NO;
    }
    return (self.receivedLength == self.expectedLength);
}

- (BOOL)isCachedPosition:(NSUInteger)pos
{
    __block BOOL cached = NO;
    [self.cachedSegment enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
        cached = key.unsignedIntegerValue <= pos && (key.unsignedIntegerValue + obj.unsignedIntegerValue > pos);
        *stop = cached;
    }];
    return cached;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    DOUCacheInfo *copy = [[[self class] allocWithZone:zone] init];
    copy.audioFileURL = self.audioFileURL;
    copy.cacheWritePath = self.cacheWritePath;
    copy.cacheWriteTmpPath = self.cacheWriteTmpPath;
    copy.expectedLength = self.expectedLength;
    copy.cachedSegment = self.cachedSegment;
    return copy;
}

- (NSDictionary<NSNumber *,NSNumber *> *)cachedSegment
{
    if (nil == _cachedSegment) {
        _cachedSegment = @{};
    }
    return _cachedSegment;
}
@end
