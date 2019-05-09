//
//  DOUCacheInfo.h
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/11.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DOUAudioFile.h"
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOUCacheInfo : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong) NSString* audioFileURL;
@property (nonatomic, strong) NSString *cacheWritePath;
@property (nonatomic, strong) NSString *cacheWriteTmpPath;
@property (nonatomic, assign) SInt64 expectedLength;
@property (nonatomic, assign) BOOL supportSeek;
@property (nonatomic, assign) AudioFileTypeID audioFileTypeHint;
- (BOOL)isCacheCompleted;

- (BOOL)rangeAvaible:(NSRange)queryRange;

- (NSRange)cachedRangeWithOffset:(NSUInteger)startOffset;

- (void)append:(NSRange)range;

- (NSRange)nextNeedCacheRangeWithStartOffset:(NSUInteger)startOffset;

@end

NS_ASSUME_NONNULL_END
