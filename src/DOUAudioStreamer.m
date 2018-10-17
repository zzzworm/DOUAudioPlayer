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

#import "DOUAudioStreamer.h"
#import "DOUAudioStreamer_Private.h"
#import "DOUAudioFileProvider.h"
#import "DOUAudioEventLoop.h"
#import "DOUAudioStreamer+Options.h"

NSString *const kDOUAudioStreamerErrorDomain = @"com.douban.audio-streamer.error-domain";

@interface DOUAudioStreamer () {
@private
  id <DOUAudioFile> _audioFile;

  DOUAudioStreamerStatus _status;
  NSError *_error;

  NSTimeInterval _duration;
  NSInteger _timingOffset;

  DOUAudioFileProvider *_fileProvider;
  DOUAudioPlaybackItem *_playbackItem;
  DOUAudioDecoder *_decoder;
    
    
  double _bufferingRatio;

#if TARGET_OS_IPHONE
  BOOL _pausedByInterruption;
#endif /* TARGET_OS_IPHONE */
}
@end

@implementation DOUAudioStreamer

@synthesize status = _status;
@synthesize error = _error;

@synthesize duration = _duration;
@synthesize timingOffset = _timingOffset;

@synthesize fileProvider = _fileProvider;
@synthesize playbackItem = _playbackItem;
@synthesize decoder = _decoder;

@synthesize bufferingRatio = _bufferingRatio;

#if TARGET_OS_IPHONE
@synthesize pausedByInterruption = _pausedByInterruption;
#endif /* TARGET_OS_IPHONE */

+ (instancetype)streamerWithAudioFile:(id <DOUAudioFile>)audioFile
{
  return [[[self class] alloc] initWithAudioFile:audioFile];
}

- (instancetype)initWithAudioFile:(id <DOUAudioFile>)audioFile
{
  self = [super init];
  if (self) {
    _audioFile = audioFile;
    _status = DOUAudioStreamerIdle;

    _fileProvider = [DOUAudioFileProvider fileProviderWithAudioFile:_audioFile config:self.config];
    if (_fileProvider == nil) {
      return nil;
    }

    _bufferingRatio = (double)[_fileProvider receivedLength] / [_fileProvider expectedLength];
    
  }

  return self;
}

- (void)setHintWithAudioFile:(id <DOUAudioFile>)audioFile
{
  [_fileProvider setHintWithAudioFile:audioFile];
}

- (id <DOUAudioFile>)audioFile
{
  return _audioFile;
}

- (NSURL *)url
{
  return [_audioFile audioFileURL];
}

- (NSString *)cachedPath
{
  return [_fileProvider cachedPath];
}

- (NSURL *)cachedURL
{
  return [_fileProvider cachedURL];
}

- (NSString *)sha256
{
  return [_fileProvider sha256];
}

- (NSUInteger)expectedLength
{
  return [_fileProvider expectedLength];
}

- (NSUInteger)receivedLength
{
  return [_fileProvider receivedLength];
}

- (NSUInteger)downloadSpeed
{
  return [_fileProvider downloadSpeed];
}

@end
