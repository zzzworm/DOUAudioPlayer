//
//  DOUAudioPlayer.h
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/12.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DOUAudioStreamer.h"
#import "DOUAudioFile.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOUAudioPlayer : NSObject

@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) double volume;

@property (nonatomic, assign) double rate;

@property (nonatomic, assign, readonly) NSTimeInterval duration;

@property (nonatomic, assign, readonly) double bufferingRatio;

@property (nonatomic, copy) NSArray *analyzers;

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, strong) id <DOUAudioFile> audioFile;

@property (assign, readonly) DOUAudioStreamerStatus status;


- (DOUAudioStreamer *)streamer;

- (void)play;
- (void)pause;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
