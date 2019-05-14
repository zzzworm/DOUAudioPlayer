/* vim: set ft=objc fenc=utf-8 sw=2 ts=2 et: */
/*
 *  DOUAudioStreamer - A Core Audio based streaming audio player for iOS/Mac:
 *
 *      https://github.com/douban/DOUAudioStreamer
 *
 *  Copyright 2013-2016 Douban Inc.  All rights reserved.
 *
 *  Use and distribution licensed under the BSD license.  See
 *  the LICENSE file for full text.
 *
 *  Authors:
 *      Chongyu Zhu <i@lembacon.com>
 *
 */

#import <Foundation/Foundation.h>
#import "DOUAudioBase.h"
#import "DOUAudioFile.h"
#import "DOUAudioFilePreprocessor.h"
#import "DOUAudioAnalyzer+Default.h"

DOUAS_EXTERN NSString *const kDOUAudioStreamerErrorDomain;

typedef NS_ENUM(NSUInteger, DOUAudioStreamerStatus) {
    DOUAudioStreamerIdle,
    DOUAudioStreamerPlaying,
    DOUAudioStreamerPaused,
    DOUAudioStreamerFinished,
    DOUAudioStreamerBuffering,
    DOUAudioStreamerError
};

typedef NS_ENUM(NSInteger, DOUAudioStreamerErrorCode) {
  DOUAudioStreamerNetworkError,
  DOUAudioStreamerDecodingError
};

typedef NS_OPTIONS(NSUInteger, DOUAudioStreamerOptions) {
    DOUAudioStreamerKeepPersistentVolume = 1 << 0,
    DOUAudioStreamerRemoveCacheOnDeallocation = 1 << 1,
    DOUAudioStreamerRequireSHA256 = 1 << 2,
    
    DOUAudioStreamerDefaultOptions = DOUAudioStreamerKeepPersistentVolume | DOUAudioStreamerRemoveCacheOnDeallocation
};

@interface DOUAudioStreamerConfig : NSObject

@property (nonatomic, strong) NSString* cachePath;
@property (nonatomic, strong) NSString* downloadedPath;
@property (nonatomic, strong) NSString* metaDataPath;
@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic, assign) DOUAudioStreamerOptions options;
@end

@interface DOUAudioStreamer : NSObject

+ (instancetype)streamerWithAudioFile:(id <DOUAudioFile>)audioFile;
- (instancetype)initWithAudioFile:(id <DOUAudioFile>)audioFile;

- (void)setHintWithAudioFile:(id <DOUAudioFile>)audioFile;

@property (assign, readonly) DOUAudioStreamerStatus status;
@property (strong, readonly) NSError *error;

@property (nonatomic, readonly) id <DOUAudioFile> audioFile;
@property (nonatomic, readonly) NSURL *url;

@property (nonatomic, assign, readonly) NSTimeInterval duration;

@property (nonatomic, readonly) NSString *cachedPath;
@property (nonatomic, readonly) NSURL *cachedURL;

@property (nonatomic, readonly) NSString *sha256;

@property (nonatomic, readonly) NSUInteger expectedLength;
@property (nonatomic, readonly) NSUInteger receivedLength;
@property (nonatomic, assign, readonly) double bufferingRatio;


@end
