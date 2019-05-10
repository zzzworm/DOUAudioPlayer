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

NS_ASSUME_NONNULL_BEGIN

@interface _DOUAudioRemoteFileProvider : DOUAudioFileProvider {
@private
    DOUSimpleHTTPRequest *_request;
    NSURL *_audioFileURL;
    NSString *_audioFileHost;
    
    CC_SHA256_CTX *_sha256Ctx;
    
    BOOL _readyToProducePackets;
    
    AudioFileID _audioFileID;
    AudioFileTypeID _audioFileTypeID;
    NSMutableArray<NSArray<NSNumber *>*> *_requringRanges;
    pthread_mutex_t _dataMutex;
}

@property (readonly, nonatomic, assign)  AudioFileID audioFileID;

@property (readonly, nonatomic, assign)  AudioFileTypeID audioFileTypeID;

@property (readonly, nonatomic, assign)  SInt64 waitingPosition;


- (NSMutableArray<NSArray<NSNumber *>*> * _Nullable)requringRanges;

- (void)setRequireRanges:(NSMutableArray * _Nullable)ranges;

- (void)requesetNeededRange;

- (void)requireOffset:(SInt64)offset;

- (void)_closeAudioFile;

- (BOOL)_openAudioFileWithFileTypeHint:(AudioFileTypeID)fileTypeHint;
@end

NS_ASSUME_NONNULL_END
