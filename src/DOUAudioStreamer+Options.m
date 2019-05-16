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

#import "DOUAudioStreamer+Options.h"
#import "DOUAudioStreamer_Private.h"
#include <CommonCrypto/CommonDigest.h>
#import "DOUAudioFileProvider.h"
#include <sys/xattr.h>

NSString *const kDOUAudioStreamerVolumeKey = @"DOUAudioStreamerVolume";
const NSUInteger kDOUAudioStreamerBufferTime = 500;

@implementation DOUAudioStreamerConfig

- (instancetype)init
{
    if (self = [super init]) {
        
    }
    return self;
}

@end

@implementation DOUAudioStreamer (Options)

- (DOUAudioStreamerOptions)options
{
    return self.config.options;
}

- (void)setOptions:(DOUAudioStreamerOptions)options
{
  if (!!((self.options ^ options) & DOUAudioStreamerKeepPersistentVolume) &&
      !(options & DOUAudioStreamerKeepPersistentVolume)) {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDOUAudioStreamerVolumeKey];
  }

  self.config.options = options;
}


- (DOUAudioStreamerConfig *)config
{
    if (nil == _config) {
        _config = [[DOUAudioStreamerConfig alloc] init];
        _config.metaDataPath = NSTemporaryDirectory();
        _config.cachePath = NSTemporaryDirectory();
        _config.options = DOUAudioStreamerDefaultOptions;
    }
    return _config;
}

- (void)setConfig:(DOUAudioStreamerConfig *)config
{
    _config = config;
}

- (instancetype)initWithAudioFile:(id<DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config
{
    self = [super init];
    if (self) {
        _audioFile = audioFile;
        _status = DOUAudioStreamerIdle;
        _config = config;
        _fileProvider = [DOUAudioFileProvider fileProviderWithAudioFile:_audioFile config:self.config];
        if (_fileProvider == nil) {
            return nil;
        }
        if([_fileProvider expectedLength] > 0){
        _bufferingRatio = (double)[_fileProvider receivedLength] / [_fileProvider expectedLength];
        }
        
    }
    
    return self;
}

@end
