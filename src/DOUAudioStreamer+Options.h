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

DOUAS_EXTERN NSString *const kDOUAudioStreamerVolumeKey;
DOUAS_EXTERN const NSUInteger kDOUAudioStreamerBufferTime;

@interface DOUAudioStreamer (Options)

- (DOUAudioStreamerOptions)options;
- (void)setOptions:(DOUAudioStreamerOptions)options;

- (DOUAudioStreamerConfig *)config;

@end
