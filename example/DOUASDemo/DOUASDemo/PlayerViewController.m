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

#import "PlayerViewController.h"
#import "Track.h"
#import "DOUAudioPlayer.h"
#import "DOUAudioVisualizer.h"
#import "DOUAudioStreamer.h"

static void *kStatusKVOKey = &kStatusKVOKey;
static void *kDurationKVOKey = &kDurationKVOKey;
static void *kBufferingRatioKVOKey = &kBufferingRatioKVOKey;

@interface PlayerViewController () {
@private
  UILabel *_titleLabel;
  UILabel *_statusLabel;
  UILabel *_miscLabel;

  UIButton *_buttonPlayPause;
  UIButton *_buttonNext;
  UIButton *_buttonStop;

    UILabel *_durationLabel;
    
  UISlider *_progressSlider;

  UILabel *_volumeLabel;
  UISlider *_volumeSlider;

    UILabel *_rateLabel;
    UILabel *_rateValLabel;
    UISlider *_rateSlider;
    
  NSUInteger _currentTrackIndex;
  NSTimer *_timer;

  DOUAudioPlayer *_player;
  DOUAudioVisualizer *_audioVisualizer;
}
@end

@implementation PlayerViewController

- (void)loadView
{
  UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  [view setBackgroundColor:[UIColor whiteColor]];

  _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 64.0, CGRectGetWidth([view bounds]), 30.0)];
  [_titleLabel setFont:[UIFont systemFontOfSize:20.0]];
  [_titleLabel setTextColor:[UIColor blackColor]];
  [_titleLabel setTextAlignment:NSTextAlignmentCenter];
  [_titleLabel setLineBreakMode:NSLineBreakByTruncatingTail];
  [view addSubview:_titleLabel];

  _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, CGRectGetMaxY([_titleLabel frame]) + 10.0, CGRectGetWidth([view bounds]), 30.0)];
  [_statusLabel setFont:[UIFont systemFontOfSize:16.0]];
  [_statusLabel setTextColor:[UIColor colorWithWhite:0.4 alpha:1.0]];
  [_statusLabel setTextAlignment:NSTextAlignmentCenter];
  [_statusLabel setLineBreakMode:NSLineBreakByTruncatingTail];
  [view addSubview:_statusLabel];

  _miscLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, CGRectGetMaxY([_statusLabel frame]) + 10.0, CGRectGetWidth([view bounds]), 20.0)];
  [_miscLabel setFont:[UIFont systemFontOfSize:10.0]];
  [_miscLabel setTextColor:[UIColor colorWithWhite:0.5 alpha:1.0]];
  [_miscLabel setTextAlignment:NSTextAlignmentCenter];
  [_miscLabel setLineBreakMode:NSLineBreakByTruncatingTail];
  [view addSubview:_miscLabel];

  _buttonPlayPause = [UIButton buttonWithType:UIButtonTypeSystem];
  [_buttonPlayPause setFrame:CGRectMake(80.0, CGRectGetMaxY([_miscLabel frame]) + 20.0, 60.0, 20.0)];
  [_buttonPlayPause setTitle:@"Play" forState:UIControlStateNormal];
  [_buttonPlayPause addTarget:self action:@selector(_actionPlayPause:) forControlEvents:UIControlEventTouchDown];
  [view addSubview:_buttonPlayPause];

  _buttonNext = [UIButton buttonWithType:UIButtonTypeSystem];
  [_buttonNext setFrame:CGRectMake(CGRectGetWidth([view bounds]) - 80.0 - 60.0, CGRectGetMinY([_buttonPlayPause frame]), 60.0, 20.0)];
  [_buttonNext setTitle:@"Next" forState:UIControlStateNormal];
  [_buttonNext addTarget:self action:@selector(_actionNext:) forControlEvents:UIControlEventTouchDown];
  [view addSubview:_buttonNext];

  _buttonStop = [UIButton buttonWithType:UIButtonTypeSystem];
  [_buttonStop setFrame:CGRectMake(round((CGRectGetWidth([view bounds]) - 60.0) / 2.0), CGRectGetMaxY([_buttonNext frame]) + 20.0, 60.0, 20.0)];
  [_buttonStop setTitle:@"Stop" forState:UIControlStateNormal];
  [_buttonStop addTarget:self action:@selector(_actionStop:) forControlEvents:UIControlEventTouchDown];
  [view addSubview:_buttonStop];

    _durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(round((CGRectGetWidth([view bounds]) - 160.0) / 2.0), CGRectGetMaxY([_buttonStop frame]), 160.0, 40.0)];
    [_durationLabel setText:@"Duration:"];
    [view addSubview:_durationLabel];
    
  _progressSlider = [[UISlider alloc] initWithFrame:CGRectMake(20.0, CGRectGetMaxY([_buttonStop frame]) + 20.0, CGRectGetWidth([view bounds]) - 20.0 * 2.0, 40.0)];
  [_progressSlider addTarget:self action:@selector(_actionSliderProgress:) forControlEvents:UIControlEventValueChanged];
  [view addSubview:_progressSlider];

  _volumeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0, CGRectGetMaxY([_progressSlider frame]) + 20.0, 80.0, 40.0)];
  [_volumeLabel setText:@"Volume:"];
  [view addSubview:_volumeLabel];

  _volumeSlider = [[UISlider alloc] initWithFrame:CGRectMake(CGRectGetMaxX([_volumeLabel frame]) + 10.0, CGRectGetMinY([_volumeLabel frame]), CGRectGetWidth([view bounds]) - CGRectGetMaxX([_volumeLabel frame]) - 10.0 - 20.0, 40.0)];
  [_volumeSlider addTarget:self action:@selector(_actionSliderVolume:) forControlEvents:UIControlEventValueChanged];
  [view addSubview:_volumeSlider];
    
    _rateLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0, CGRectGetMaxY([_volumeSlider frame]) + 10.0, 80.0, 40.0)];
    [_rateLabel setText:@"Rate:"];
    [view addSubview:_rateLabel];
    
    _rateValLabel = [[UILabel alloc] initWithFrame:CGRectMake(160.0, CGRectGetMaxY([_volumeSlider frame]) - 10 , 80.0, 40.0)];
    [_rateValLabel setText:@"1.0"];
    [view addSubview:_rateValLabel];
    
    _rateSlider = [[UISlider alloc] initWithFrame:CGRectMake(CGRectGetMaxX([_rateLabel frame]) + 10.0, CGRectGetMinY([_rateLabel frame]), CGRectGetWidth([view bounds]) - CGRectGetMaxX([_rateLabel frame]) - 10.0 - 20.0, 40.0)];
    _rateSlider.minimumValue = 0.5;
    _rateSlider.maximumValue = 2.0;
    _rateSlider.value = 1.0f;
    [_rateSlider addTarget:self action:@selector(_actionSliderRate:) forControlEvents:UIControlEventValueChanged];
    [view addSubview:_rateSlider];

  _audioVisualizer = [[DOUAudioVisualizer alloc] initWithFrame:CGRectMake(0.0, CGRectGetMaxY([_rateSlider frame]), CGRectGetWidth([view bounds]), CGRectGetHeight([view bounds]) - CGRectGetMaxY([_rateSlider frame]))];
    
  [_audioVisualizer setBackgroundColor:[UIColor colorWithRed:239.0 / 255.0 green:244.0 / 255.0 blue:240.0 / 255.0 alpha:1.0]];
  [view addSubview:_audioVisualizer];

  [self setView:view];
}

- (void)_cancelStreamer
{
//  if (_streamer != nil) {
//    [_streamer pause];
//    [_streamer removeObserver:self forKeyPath:@"status"];
//    [_streamer removeObserver:self forKeyPath:@"duration"];
//    [_streamer removeObserver:self forKeyPath:@"bufferingRatio"];
//    _streamer = nil;
//  }
}

- (void)_resetStreamer
{
  

    if (0 == [_tracks count])
    {
        [_miscLabel setText:@"(No tracks available)"];
    }
    else
    {
        Track *track = [_tracks objectAtIndex:_currentTrackIndex];
        NSString *title = [NSString stringWithFormat:@"%@ - %@", track.artist, track.title];
        [_titleLabel setText:title];
        if (nil == _player) {
            _player = [[DOUAudioPlayer alloc] init];

            [_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kStatusKVOKey];
            [_player addObserver:self forKeyPath:@"duration" options:NSKeyValueObservingOptionNew context:kDurationKVOKey];
            [_player addObserver:self forKeyPath:@"bufferingRatio" options:NSKeyValueObservingOptionNew context:kBufferingRatioKVOKey];
            _audioVisualizer.player = _player;
        }
        [_player setAudioFile:track];
        [_player play];
        
        [self _updateBufferingStatus];
        [self _setupHintForStreamer];
    }
}

- (void)_setupHintForStreamer
{
  NSUInteger nextIndex = _currentTrackIndex + 1;
  if (nextIndex >= [_tracks count]) {
    nextIndex = 0;
  }

  [_player.streamer setHintWithAudioFile:[_tracks objectAtIndex:nextIndex]];
}

- (void)_timerAction:(id)timer
{
  if ([_player duration] == 0.0) {
    [_progressSlider setValue:0.0f animated:NO];
  }
  else {
      _durationLabel.text = [NSString stringWithFormat:@"Duration:%.1f",[_player duration]];
    [_progressSlider setValue:[_player currentTime] / [_player duration] animated:YES];
  }
}

- (void)_updateStatus
{
  switch ([_player status]) {
  case DOUAudioStreamerPlaying:
    [_statusLabel setText:@"playing"];
    [_buttonPlayPause setTitle:@"Pause" forState:UIControlStateNormal];
    break;

  case DOUAudioStreamerPaused:
    [_statusLabel setText:@"paused"];
    [_buttonPlayPause setTitle:@"Play" forState:UIControlStateNormal];
    break;

  case DOUAudioStreamerIdle:
    [_statusLabel setText:@"idle"];
    [_buttonPlayPause setTitle:@"Play" forState:UIControlStateNormal];
    break;

  case DOUAudioStreamerFinished:
    [_statusLabel setText:@"finished"];
    //[self _actionNext:nil];
    break;

  case DOUAudioStreamerBuffering:
    [_statusLabel setText:@"buffering"];
    break;

  case DOUAudioStreamerError:
    [_statusLabel setText:@"error"];
    break;
  }
}

- (void)_updateBufferingStatus
{
  [_miscLabel setText:[NSString stringWithFormat:@"Received %.2f/%.2f MB (%.2f %%), Speed %.2f MB/s", (double)[_player.streamer receivedLength] / 1024 / 1024, (double)[_player.streamer expectedLength] / 1024 / 1024, [_player.streamer bufferingRatio] * 100.0, (double)[_player.streamer downloadSpeed] / 1024 / 1024]];

  if ([_player.streamer bufferingRatio] >= 1.0) {
    NSLog(@"sha256: %@", [_player.streamer sha256]);
  }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if (context == kStatusKVOKey) {
    [self performSelector:@selector(_updateStatus)
                 onThread:[NSThread mainThread]
               withObject:nil
            waitUntilDone:NO];
  }
  else if (context == kDurationKVOKey) {
    [self performSelector:@selector(_timerAction:)
                 onThread:[NSThread mainThread]
               withObject:nil
            waitUntilDone:NO];
  }
  else if (context == kBufferingRatioKVOKey) {
    [self performSelector:@selector(_updateBufferingStatus)
                 onThread:[NSThread mainThread]
               withObject:nil
            waitUntilDone:NO];
  }
  else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];

  [self _resetStreamer];

  _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_timerAction:) userInfo:nil repeats:YES];
  [_volumeSlider setValue:[_player volume]];
}

- (void)viewWillDisappear:(BOOL)animated
{
  [_timer invalidate];
  [_player stop];

  [super viewWillDisappear:animated];
}

- (void)_actionPlayPause:(id)sender
{
  if ([_player status] == DOUAudioStreamerPaused ||
      [_player status] == DOUAudioStreamerIdle) {
    [_player play];
  }
  else {
    [_player pause];
  }
}

- (void)_actionNext:(id)sender
{
  if (++_currentTrackIndex >= [_tracks count]) {
    _currentTrackIndex = 0;
  }

  [self _resetStreamer];
}

- (void)_actionStop:(id)sender
{
  [_player stop];
}

- (void)_actionSliderProgress:(id)sender
{
  [_player setCurrentTime:[_player duration] * [_progressSlider value]];
}

- (void)_actionSliderVolume:(id)sender
{
  [_player setVolume:[_volumeSlider value]];
}

- (void)_actionSliderRate:(id)sender
{
    [_player setRate:[_rateSlider value]];
    _rateValLabel.text = [NSString stringWithFormat:@"%.2f",[_rateSlider value]];
}

@end
