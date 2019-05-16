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

#import "DOUAudioFileProvider.h"
#import "DOUSimpleHTTPRequest.h"
#import "NSData+DOUMappedFile.h"
#include <CommonCrypto/CommonDigest.h>
#import "DOUAudioAutoRecoverRemoteFileProvider.h"
#import "DOUAudioLocalFileProvider.h"
#import "DOUAudioFileProvider_Private.h"

#if TARGET_OS_IPHONE
#include <MobileCoreServices/MobileCoreServices.h>
#else /* TARGET_OS_IPHONE */
#include <CoreServices/CoreServices.h>
#endif /* TARGET_OS_IPHONE */

#if TARGET_OS_IPHONE
#import "DOUMPMediaLibraryAssetLoader.h"
#endif /* TARGET_OS_IPHONE */



#if TARGET_OS_IPHONE
@interface _DOUAudioMediaLibraryFileProvider : DOUAudioFileProvider {
@private
    DOUMPMediaLibraryAssetLoader *_assetLoader;
    BOOL _loaderCompleted;
}
@end
#endif /* TARGET_OS_IPHONE */


#pragma mark - Concrete Audio Media Library File Provider

#if TARGET_OS_IPHONE
@implementation _DOUAudioMediaLibraryFileProvider

- (instancetype)_initWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config
{
    self = [super _initWithAudioFile:audioFile config:config];
    if (self) {
        [self _createAssetLoader];
        [_assetLoader start];
    }
    
    return self;
}

- (void)dealloc
{
    @synchronized(_assetLoader) {
        [_assetLoader setCompletedBlock:NULL];
        [_assetLoader cancel];
    }
    
    [[NSFileManager defaultManager] removeItemAtPath:[_assetLoader cachedPath]
                                               error:NULL];
}

- (void)_invokeEventBlock
{
    if (_eventBlock != NULL) {
        _eventBlock();
    }
}

- (void)_assetLoaderDidComplete
{
    if ([_assetLoader isFailed]) {
        _failed = YES;
        [self _invokeEventBlock];
        return;
    }
    
    _mimeType = [_assetLoader mimeType];
    _fileExtension = [_assetLoader fileExtension];
    
    _cachedPath = [_assetLoader cachedPath];
    _cachedURL = [NSURL fileURLWithPath:_cachedPath];
    
    _mappedData = [NSData dou_dataWithMappedContentsOfFile:_cachedPath];
    _expectedLength = [_mappedData length];
    _receivedLength = [_mappedData length];
    
    _loaderCompleted = YES;
    [self _invokeEventBlock];
}

- (void)_createAssetLoader
{
    _assetLoader = [DOUMPMediaLibraryAssetLoader loaderWithURL:[_audioFile audioFileURL]];
    
    __weak typeof(self) weakSelf = self;
    [_assetLoader setCompletedBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf _assetLoaderDidComplete];
    }];
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
    return _loaderCompleted;
}

- (BOOL)isFinished
{
    return _loaderCompleted;
}

- (BOOL)rangeAvaiable:(NSRange)range
{
    return range.location >= 0 && NSMaxRange(range) < self.expectedLength;
}

@end
#endif /* TARGET_OS_IPHONE */

#pragma mark - Abstract Audio File Provider

@implementation DOUAudioFileProvider

@synthesize audioFile = _audioFile;
@synthesize eventBlock = _eventBlock;
@synthesize cachedPath = _cachedPath;
@synthesize cachedURL = _cachedURL;
@synthesize mimeType = _mimeType;
@synthesize fileExtension = _fileExtension;
@synthesize sha256 = _sha256;
@synthesize mappedData = _mappedData;
@synthesize expectedLength = _expectedLength;
@synthesize receivedLength = _receivedLength;
@synthesize failed = _failed;
@synthesize hintFile = _hintFile;
@synthesize hintProvider = _hintProvider;
@synthesize lastProviderIsFinished = _lastProviderIsFinished;

+ (instancetype)_fileProviderWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config
{
    if (audioFile == nil) {
        return nil;
    }
    
    NSURL *audioFileURL = [audioFile audioFileURL];
    if (audioFileURL == nil) {
        return nil;
    }
    
    if ([audioFileURL isFileURL]) {
        return [[_DOUAudioLocalFileProvider alloc] _initWithAudioFile:audioFile config:config];
    }
#if TARGET_OS_IPHONE
    else if ([[audioFileURL scheme] isEqualToString:@"ipod-library"]) {
        return [[_DOUAudioMediaLibraryFileProvider alloc] _initWithAudioFile:audioFile config:config];
    }
#endif /* TARGET_OS_IPHONE */
    else {
        return [[_DOUAudioAutoRecoverRemoteFileProvider alloc] _initWithAudioFile:audioFile config:config];
    }
}

+ (instancetype)fileProviderWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config
{
    
    return [self _fileProviderWithAudioFile:audioFile config:config];
}

- (void)setHintWithAudioFile:(id <DOUAudioFile>)audioFile
{
    if (audioFile == _hintFile ||
        [audioFile isEqual:_hintFile]) {
        return;
    }
    
    _hintFile = nil;
    _hintProvider = nil;
    
    if (audioFile == nil) {
        return;
    }
    
    NSURL *audioFileURL = [audioFile audioFileURL];
    if (audioFileURL == nil ||
#if TARGET_OS_IPHONE
        [[audioFileURL scheme] isEqualToString:@"ipod-library"] ||
#endif /* TARGET_OS_IPHONE */
        [audioFileURL isFileURL]) {
        return;
    }
    
    _hintFile = audioFile;
    
    if (_lastProviderIsFinished) {
        _hintProvider = [self.class _fileProviderWithAudioFile:_hintFile config:self.config];
    }
}

- (instancetype)_initWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config
{
    self = [super init];
    if (self) {
        _audioFile = audioFile;
        _config = config;
    }
    
    return self;
}

- (BOOL)isReady
{
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (BOOL)isFinished
{
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}


- (double)bufferingRatio
{
    return 1.0f;
}

- (void)dealloc
{
    self.eventBlock = nil;
}

- (BOOL)rangeAvaiable:(NSRange)range
{
    return NO;
}

- (NSUInteger)readIntoBuffer:(UInt8*)buffer withRange:(NSRange)range
{
    NSUInteger actualCount = 0;
    NSUInteger inPosition = range.location;
    NSUInteger requestCount = range.length;
    if (inPosition + requestCount > [[self mappedData] length]) {
        if (inPosition >= [[self mappedData] length]) {
            actualCount = 0;
        }
        else {
            actualCount = (UInt32)([[self mappedData] length] - inPosition);
        }
    }
    else {
        actualCount = requestCount;
    }
    memcpy(buffer, (uint8_t *)[[self mappedData] bytes] + inPosition, actualCount);

    return actualCount;
}

- (void)lockForRead
{
    
}
- (void)unlockForRead
{
    
}
@end
