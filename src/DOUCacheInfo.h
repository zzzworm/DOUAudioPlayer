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

@interface DOUCacheInfo : NSObject

@property (nonatomic, strong) NSString* audioFileURL;
@property (nonatomic, assign) unsigned long long expectedLength;
@property (nonatomic, assign) BOOL supportSeek;
@property (nonatomic, assign) AudioFileTypeID audioFileTypeHint;

- (BOOL)isCacheCompleted;

- (BOOL)rangeAvaible:(NSRange)queryRange;

- (NSRange)cachedRangeWithOffset:(NSUInteger)startOffset;

- (void)append:(NSRange)range;

- (NSRange)nextNeedCacheRangeWithStartOffset:(NSUInteger)startOffset;


+ (instancetype)cacheInfoWithFilePath:(NSString *)filePath;

- (void)writeToFile:(NSString *)filePath;
@end

NS_ASSUME_NONNULL_END
