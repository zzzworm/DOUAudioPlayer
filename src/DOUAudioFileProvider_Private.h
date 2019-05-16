//
//  DOUAudioFileProvider_Private.h
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/12.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#ifndef DOUAudioFileProvider_Private_h
#define DOUAudioFileProvider_Private_h

#import "DOUAudioFileProvider.h"

@interface DOUAudioFileProvider () {
@public
    id <DOUAudioFile> _audioFile;
    DOUAudioFileProviderEventBlock _eventBlock;
    NSString *_cachedPath;
    NSString *_metaPath;
    NSURL *_cachedURL;
    NSString *_mimeType;
    NSString *_fileExtension;
    NSString *_sha256;
    NSData *_mappedData;
    unsigned long long _expectedLength;
    unsigned long long _receivedLength;
    BOOL _failed;
}

- (instancetype)_initWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config;

@end

#endif /* DOUAudioFileProvider_Private_h */
