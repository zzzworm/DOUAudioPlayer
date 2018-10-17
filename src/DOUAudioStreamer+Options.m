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
#include <sys/xattr.h>

NSString *const kDOUAudioStreamerVolumeKey = @"DOUAudioStreamerVolume";
const NSUInteger kDOUAudioStreamerBufferTime = 200;

@implementation DOUAudioStreamerConfig

- (instancetype)init
{
    if (self = [super init]) {
        
    }
    return self;
}

- (NSString *)offlinePath
{
    if (nil == _offlinePath) {
        _offlinePath = [[DOUAudioStreamerConfig cacheDataPath] stringByAppendingPathComponent:@"DouCache"];
    }
    return _offlinePath;
}

- (NSString *)downloadedPath
{
    if (nil == _downloadedPath) {
        _downloadedPath = [[DOUAudioStreamerConfig offlineDataPath] stringByAppendingPathComponent:@"DouDownload"];
    }
    return _downloadedPath;
}

+ (NSString *)cacheDataPath
{
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        //cache folder
        path = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject;
        
#if !TARGET_OS_IPHONE
        
        //append application bundle ID on Mac OS
        NSString *identifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleIdentifierKey];
        path = [path stringByAppendingPathComponent:identifier];
        
#endif
        
        //create the folder if it doesn't exist
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        
        //retain path
        path = [[NSString alloc] initWithString:path];
    });
    
    return path;
}

+ (NSString *)privateDataPath
{
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        //application support folder
        path = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).lastObject;
        
#if !TARGET_OS_IPHONE
        
        //append application name on Mac OS
        NSString *identifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
        path = [path stringByAppendingPathComponent:identifier];
        
#endif
        
        //create the folder if it doesn't exist
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        
        //retain path
        path = [[NSString alloc] initWithString:path];
    });
    
    return path;
}


+ (NSString *)offlineDataPath
{
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        //offline data folder
        path = [self.privateDataPath stringByAppendingPathComponent:@"Offline Data"];
        
        //create the folder if it doesn't exist
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        
        if (&NSURLIsExcludedFromBackupKey && [NSURL instancesRespondToSelector:@selector(setResourceValue:forKey:error:)])
        {
            //use iOS 5.1 method to exclude file from backup
            NSURL *URL = [NSURL fileURLWithPath:path isDirectory:YES];
            [URL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
        }
        else
        {
            //use the iOS 5.0.1 mobile backup flag to exclude file from backp
            u_int8_t b = 1;
            setxattr(path.fileSystemRepresentation, "com.apple.MobileBackup", &b, 1, 0, 0);
        }
        
        //retain path
        path = [[NSString alloc] initWithString:path];
    });
    
    return path;
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
        _config.options = DOUAudioStreamerDefaultOptions;
    }
    return _config;
}


@end
