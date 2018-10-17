//
//  DOUAudioPlayer.m
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/12.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#import "DOUAudioPlayer.h"
#import "DOUAudioStreamer.h"
#import "DOUAudioEventLoop.h"
#import "DOUAudioStreamer_Private.h"
#import "DOUAudioFileProvider.h"

static void *kStatusKVOKey = &kStatusKVOKey;
static void *kDurationKVOKey = &kDurationKVOKey;
static void *kBufferingRatioKVOKey = &kBufferingRatioKVOKey;


@interface _InnerTrack : NSObject <DOUAudioFile>

@property (nonatomic, strong) NSURL *audioFileURL;

- (instancetype)initWithURL:(NSURL *)url;

@end

@implementation _InnerTrack

- (instancetype)initWithURL:(NSURL *)url
{
    if (self = [super init]) {
        self.audioFileURL = url;
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    if([self class] == [object class])
    {
        if(![self.audioFileURL isEqual:[(_InnerTrack *)object audioFileURL]])
        {
            return NO;
        }
        return YES;
    }
    else
    {
        return [super isEqual:object];
    }
}

@end

@interface DOUAudioPlayer () {
@private
    DOUAudioStreamer *_streamer;
    DOUAudioEventLoop *_eventLoop;

}

@property (assign) DOUAudioStreamerStatus status;
@property (strong) NSError *error;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) NSInteger timingOffset;
@property (nonatomic, assign) double bufferingRatio;

@end

@implementation DOUAudioPlayer

@synthesize status = _status;
@synthesize duration = _duration;
@synthesize bufferingRatio = _bufferingRatio;

- (instancetype)init
{
    if (self = [super init]) {
        _eventLoop = [[DOUAudioEventLoop alloc] init];
        _status = DOUAudioStreamerIdle;
    }
    return self;
}

- (DOUAudioStreamer *)streamer
{
    return _streamer;
}


- (void)setUrl:(NSURL *)url
{
    [self setAudioFile:[[_InnerTrack alloc] initWithURL:url]];
}

- (NSURL *)url
{
    return [_streamer url];
}

- (void)setAudioFile:(id)audioFile
{
    _audioFile = audioFile;
    if (nil != _streamer) {
        [self pause];
        [_streamer removeObserver:self forKeyPath:@"status"];
        [_streamer removeObserver:self forKeyPath:@"duration"];
        [_streamer removeObserver:self forKeyPath:@"bufferingRatio"];
        _streamer = nil;
    }
    _streamer = [DOUAudioStreamer streamerWithAudioFile:audioFile];
    [_streamer addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kStatusKVOKey];
    [_streamer addObserver:self forKeyPath:@"duration" options:NSKeyValueObservingOptionNew context:kDurationKVOKey];
    [_streamer addObserver:self forKeyPath:@"bufferingRatio" options:NSKeyValueObservingOptionNew context:kBufferingRatioKVOKey];
    _status = _streamer.status;
    _bufferingRatio = _streamer.bufferingRatio;
    [_eventLoop setCurrentStreamer:_streamer];
}

- (NSTimeInterval)currentTime
{
    if ([_eventLoop currentStreamer] != _streamer) {
        return 0.0;
    }
    
    return [_eventLoop currentTime];
}

- (void)setCurrentTime:(NSTimeInterval)currentTime
{
    if ([_eventLoop currentStreamer] != _streamer) {
        return;
    }
    
    [_eventLoop setCurrentTime:currentTime];
}

- (double)volume
{
    return [_eventLoop volume];
}

- (void)setVolume:(double)volume
{
    [_eventLoop setVolume:volume];
}

- (double)rate
{
    return [_eventLoop rate];
}

- (void)setRate:(double)rate
{
    [_eventLoop setRate:rate];
}

- (NSArray *)analyzers
{
    return [_eventLoop analyzers];
}

- (void)setAnalyzers:(NSArray *)analyzers
{
    [_eventLoop setAnalyzers:analyzers];
}


- (void)play
{
    @synchronized(self) {
        if (self.status != DOUAudioStreamerPaused &&
            self.status != DOUAudioStreamerIdle &&
            self.status != DOUAudioStreamerFinished) {
            return;
        }
        
        if ([_eventLoop currentStreamer] != _streamer) {
            [_eventLoop pause];
            [_eventLoop setCurrentStreamer:_streamer];
        }
        
        [_eventLoop play];
    }
}

- (void)pause
{
    @synchronized(self) {
        if (self.status == DOUAudioStreamerPaused ||
            self.status == DOUAudioStreamerIdle ||
            self.status == DOUAudioStreamerFinished) {
            return;
        }
        
        if ([_eventLoop currentStreamer] != _streamer) {
            return;
        }
        
        [_eventLoop pause];
    }
}

- (void)stop
{
    @synchronized(self) {
        if (self.status == DOUAudioStreamerIdle) {
            return;
        }
        
        if ([_eventLoop currentStreamer] != _streamer) {
            return;
        }
        
        [_eventLoop stop];
        [_eventLoop setCurrentStreamer:nil];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kStatusKVOKey) {
        self.status = _streamer.status;
    }
    else if (context == kDurationKVOKey) {
        self.duration = _streamer.duration;
    }
    else if (context == kBufferingRatioKVOKey) {
        self.bufferingRatio = _streamer.bufferingRatio;
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}
@end
