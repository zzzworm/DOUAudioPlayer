//
//  DOUAudioLocalFileProvider.m
//  DOUASDemo
//
//  Created by grant.zhou on 2019/5/5.
//  Copyright © 2019 Douban Inc. All rights reserved.
//

#import "DOUAudioLocalFileProvider.h"
#import "DOUAudioFileProvider_Private.h"
#import "NSData+DOUMappedFile.h"
#include <AudioToolbox/AudioToolbox.h>
#if TARGET_OS_IPHONE
#include <MobileCoreServices/MobileCoreServices.h>
#else /* TARGET_OS_IPHONE */
#include <CoreServices/CoreServices.h>
#endif /* TARGET_OS_IPHONE */
#include <CommonCrypto/CommonDigest.h>


#pragma mark - Concrete Audio Local File Provider

@implementation _DOUAudioLocalFileProvider

- (instancetype)_initWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config
{
    self = [super _initWithAudioFile:audioFile config:config];
    if (self) {
        _cachedURL = [audioFile audioFileURL];
        _cachedPath = [_cachedURL path];
        
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:_cachedPath
                                                  isDirectory:&isDirectory] ||
            isDirectory) {
            return nil;
        }
        
        _mappedData = [NSData dou_dataWithMappedContentsOfFile:_cachedPath];
        _expectedLength = [_mappedData length];
        _receivedLength = [_mappedData length];
    }
    
    return self;
}

- (NSString *)mimeType
{
    if (_mimeType == nil &&
        [self fileExtension] != nil) {
        CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[self fileExtension], NULL);
        if (uti != NULL) {
            _mimeType = CFBridgingRelease(UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType));
            CFRelease(uti);
        }
    }
    
    return _mimeType;
}

- (NSString *)fileExtension
{
    if (_fileExtension == nil) {
        _fileExtension = [[[self audioFile] audioFileURL] pathExtension];
    }
    
    return _fileExtension;
}

- (NSString *)sha256
{
    if (_sha256 == nil &&
        self.config.options & DOUAudioStreamerRequireSHA256 &&
        [self mappedData] != nil) {
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256([[self mappedData] bytes], (CC_LONG)[[self mappedData] length], hash);
        
        NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
        for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) {
            [result appendFormat:@"%02x", hash[i]];
        }
        
        _sha256 = [result copy];
    }
    
    return _sha256;
}

- (BOOL)isReady
{
    return YES;
}

- (BOOL)isFinished
{
    return YES;
}

- (BOOL)rangeAvaiable:(NSRange)range
{
    return range.location >= 0 && NSMaxRange(range) < self.receivedLength;
}

@end

