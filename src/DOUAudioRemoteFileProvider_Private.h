//
//  _DOUAudioRemoteFileProvider_Private.h
//  DOUAudioPlayerDemo
//
//  Created by grant.zhou on 2019/5/13.
//  Copyright © 2019 Douban Inc. All rights reserved.
//

#ifndef _DOUAudioRemoteFileProvider_Private_h
#define _DOUAudioRemoteFileProvider_Private_h
#import "DOUAudioRemoteFileProvider.h"

@interface _DOUAudioRemoteFileProvider ()
{
@protected
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

@property (nonatomic, strong) DOUCacheInfo *cacheInfo;

- (void)_requestDidReceiveData:(NSData *)data;
- (void)_createRequest:(SInt64)position length:(NSUInteger)length;
- (BOOL)checkRequireRangeFullfilledAndRemoveFullfilled:(BOOL)remove;
- (void)_invokeEventBlock;
- (void)cancelRequest;
- (void)handleRequestComplete;
@end

#endif /* _DOUAudioRemoteFileProvider_Private_h */
