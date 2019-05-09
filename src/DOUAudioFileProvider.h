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
#import "DOUAudioFile.h"
#import "DOUAudioStreamer.h"
#include <AudioToolbox/AudioToolbox.h>

@class DOUAudioFileProvider;

typedef void (^DOUAudioFileProviderEventBlock)(void);
extern DOUAudioFileProvider *gHintProvider;

@interface DOUAudioFileProvider : NSObject

+ (instancetype)fileProviderWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)configs;
- (void)setHintWithAudioFile:(id <DOUAudioFile>)audioFile;

@property (nonatomic, readonly) id <DOUAudioFile> audioFile;
@property (nonatomic, copy) DOUAudioFileProviderEventBlock eventBlock;

@property (nonatomic, readonly) NSString *cachedPath;
@property (nonatomic, readonly) NSURL *cachedURL;

@property (nonatomic, readonly) NSString *mimeType;
@property (nonatomic, readonly) NSString *fileExtension;
@property (nonatomic, readonly) NSString *sha256;

@property (nonatomic, readonly) NSData *mappedData;

@property (nonatomic, readonly) unsigned long long expectedLength;
@property (nonatomic, readonly) unsigned long long receivedLength;

@property (nonatomic, readonly, getter=isFailed) BOOL failed;
@property (nonatomic, readonly, getter=isReady) BOOL ready;
@property (nonatomic, readonly, getter=isFinished) BOOL finished;

@property (nonatomic, strong) DOUAudioStreamerConfig *config;

@property (nonatomic, strong) id <DOUAudioFile> hintFile;
@property (nonatomic, strong) DOUAudioFileProvider *hintProvider;
@property (nonatomic, assign) BOOL lastProviderIsFinished;
@property (nonatomic, assign, readonly) double bufferingRatio;

- (BOOL)rangeAvaiable:(NSRange)range;

- (NSUInteger)readIntoBuffer:(UInt8*)buffer withRange:(NSRange)range;

- (void)_closeAudioFile;

- (BOOL)_openAudioFileWithFileTypeHint:(AudioFileTypeID)fileTypeHint;

- (void)lockForRead;
- (void)unlockForRead;

@end
