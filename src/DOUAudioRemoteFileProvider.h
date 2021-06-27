//
//  DOUAudioRemoteFileProvider.h
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/11.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#import "DOUAudioFileProvider.h"
#import "DOUSimpleHTTPRequest.h"
#include <CommonCrypto/CommonDigest.h>
#include <AudioToolbox/AudioToolbox.h>

#define DOUHTTPRequestMaxLength (15 * 1024 *1024)

#define DOU_DEFAULT_BUFFER_SIZE_REQUIRED_TO_START_PLAYING_AFTER_BUFFER_UNDERRUN (128*1024)

NS_ASSUME_NONNULL_BEGIN

@interface _DOUAudioRemoteFileProvider : DOUAudioFileProvider 

@property (readonly, nonatomic, assign)  AudioFileID audioFileID;

@property (readonly, nonatomic, assign)  AudioFileTypeID audioFileTypeID;

@property (readonly, nonatomic, assign)  SInt64 waitingPosition;


- (NSMutableArray<NSArray<NSNumber *>*> * _Nullable)requringRanges;

- (void)setRequireRanges:(NSMutableArray * _Nullable)ranges;

- (void)requesetNeededRange;

- (void)requireOffset:(SInt64)offset;

- (void)_closeAudioFile;

- (BOOL)_openAudioFileWithFileTypeHint:(AudioFileTypeID)fileTypeHint;

+ (NSString *)_metaPathForAudioFileURL:(NSURL *)audioFileURL;
@end

NS_ASSUME_NONNULL_END
