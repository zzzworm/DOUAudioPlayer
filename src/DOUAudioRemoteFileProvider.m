//
//  DOUAudioRemoteFileProvider.m
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/11.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#import "DOUAudioRemoteFileProvider.h"
#import "NSData+DOUMappedFile.h"
#import "DOUAudioFileProvider_Private.h"
#import "DOUCacheInfo.h"
#import "DOUAudioDecoder.h"
#include <CoreAudio/CoreAudioTypes.h>
#include <pthread.h>
#import "DOUAudioRemoteFileProvider_Private.h"


#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50

#pragma mark - Concrete Audio Remote File Provider


@implementation _DOUAudioRemoteFileProvider

- (instancetype)_initWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config
{
    self = [super _initWithAudioFile:audioFile config:config];
    if (self) {
        _audioFileURL = [audioFile audioFileURL];
        if ([audioFile respondsToSelector:@selector(audioFileHost)]) {
            _audioFileHost = [audioFile audioFileHost];
        }
        pthread_mutexattr_t attr;
        
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_dataMutex, &attr);
        
        _metaPath = [self.class _metaPathForAudioFileURL:audioFile.audioFileURL];
        _cacheInfo = [DOUCacheInfo cacheInfoWithFilePath:_metaPath];
        _audioFileTypeID = _cacheInfo.audioFileTypeHint;
        _expectedLength = _cacheInfo.expectedLength;
        
        if (_cacheInfo.audioFileTypeHint > 0) {
            [self createMappedData];
            if([self _openAudioFileWithFileTypeHint:_audioFileTypeID]){
                _readyToProducePackets = YES;
            }
            else{
                _cachedPath = nil;
                _cachedURL = nil;
                _metaPath = nil;
                _mappedData = nil;
                [[NSFileManager defaultManager] removeItemAtPath:_cachedPath error:NULL];
                [[NSFileManager defaultManager] removeItemAtPath:_metaPath error:NULL];
            }
            
        }
        else{
            [self _createRequest];
            [_request start];
        }
    }
    
    return self;
}


- (AudioFileID)audioFileID
{
    return _audioFileID;
}


- (AudioFileTypeID)audioFileTypeID
{
    return _audioFileTypeID;
}

- (void)cancelRequest {
    if(NULL == _request){
        return;
    }
    @synchronized(_request) {
        [_request setCompletedBlock:NULL];
        [_request setProgressBlock:NULL];
        [_request setDidReceiveResponseBlock:NULL];
        [_request setDidReceiveDataBlock:NULL];
        [_request cancel];
        _request = NULL;
    }
}

- (void)dealloc
{
    [self cancelRequest];
    
    if (_sha256Ctx != NULL) {
        free(_sha256Ctx);
    }
    
    [self _closeAudioFile];
    
    if (self.config.options & DOUAudioStreamerRemoveCacheOnDeallocation) {
        [[NSFileManager defaultManager] removeItemAtPath:_cachedPath error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:_metaPath error:NULL];
    }
}

+ (NSString *)_sha256ForAudioFileURL:(NSURL *)audioFileURL
{
    NSString *string = [audioFileURL absoluteString];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([string UTF8String], (CC_LONG)[string lengthOfBytesUsingEncoding:NSUTF8StringEncoding], hash);
    
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) {
        [result appendFormat:@"%02x", hash[i]];
    }
    
    return result;
}

+ (NSString *)_cachedPathForAudioFileURL:(NSURL *)audioFileURL
{
    NSString *filename = [self _sha256ForAudioFileURL:audioFileURL];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
}

+ (NSString *)_metaPathForAudioFileURL:(NSURL *)audioFileURL
{
    NSString *filename = [NSString stringWithFormat:@"%@.meta", [self _sha256ForAudioFileURL:audioFileURL]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
}

- (void)_invokeEventBlock
{
    if (_eventBlock != NULL) {
        _eventBlock();
    }
}

- (void)_requestDidComplete
{
    
    if ([_request isFailed] ||
        !([_request statusCode] >= 200 && [_request statusCode] < 300)) {
        _failed = YES;
    }
    else {
        pthread_mutex_lock(&_dataMutex);
        [_mappedData dou_synchronizeMappedFile];
        [self.cacheInfo writeToFile:[self.class _metaPathForAudioFileURL:self.audioFile.audioFileURL]];
        pthread_mutex_unlock(&_dataMutex);
    }
    [self handleRequestComplete];
}

- (void)handleRequestComplete{
    if (!_failed && self.isFinished && !_audioFileID) {
        _failed = YES;
    }
    if (!_failed &&
        _sha256Ctx != NULL) {
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256_Final(hash, _sha256Ctx);
        
        NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
        for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) {
            [result appendFormat:@"%02x", hash[i]];
        }
        
        _sha256 = [result copy];
    }
    
    if (self.isReady && _request.position + _request.receivedLength == _expectedLength && self.hintFile != nil &&
        self.hintProvider == nil) {
        self.hintProvider = [[[self class] alloc] _initWithAudioFile:self.hintFile config:self.config];
    }
    if (![self checkRequireRangeFullfilledAndRemoveFullfilled:YES]) {
        [self requesetNeededRange];
    }
    else{
        [self _invokeEventBlock];
    }
    
}

- (void)_requestDidReportProgress:(double)progress
{
    //[self _invokeEventBlock];
}

- (void)_requestDidReceiveResponse
{
    if (!([_request statusCode] >= 200 && [_request statusCode] < 300)) {
        return;
    }
    if(0 == _request.length){
        _expectedLength = _request.position + [_request responseContentLength];
    }
    if (nil == _cachedURL) {
        
        [self createMappedData];
        
        _mimeType = [[_request responseHeaders] objectForKey:@"Content-Type"];
        self.cacheInfo.expectedLength = _expectedLength;
        self.cacheInfo.supportSeek = _request.supportsSeek;
        self.cacheInfo.audioFileURL = _audioFileURL.absoluteString;
    }
}

- (void)_requestDidReceiveData:(NSData *)data
{
    if (_mappedData == nil) {
        return;
    }
    pthread_mutex_lock(&_dataMutex);
    NSUInteger availableSpace = _expectedLength - _receivedLength - _request.position;
    NSUInteger bytesToWrite = MIN(availableSpace, [data length]);
    
    memcpy((uint8_t *)[_mappedData bytes] + _receivedLength + _request.position, [data bytes], bytesToWrite);
    
    NSRange currentReceivedRange = NSMakeRange((NSUInteger)_receivedLength + _request.position,bytesToWrite);
    
    _receivedLength += bytesToWrite;
    
    [self.cacheInfo append:currentReceivedRange];
    pthread_mutex_unlock(&_dataMutex);
    if (_sha256Ctx != NULL) {
        CC_SHA256_Update(_sha256Ctx, [data bytes], (CC_LONG)[data length]);
    }
    
    if (!_readyToProducePackets && !_failed) {
        [self tryOpenAudioFile];
    }
    if (_readyToProducePackets) {
        if ([self checkRequireRangeFullfilledAndRemoveFullfilled:YES]) {
            if ([self shouldInvokeDecoder]) {
                [self _invokeEventBlock];
            }
        }
        else{
            [self requesetNeededRange];
        }
    }
}

- (void)createMappedData {
    _cachedPath = [[self class] _cachedPathForAudioFileURL:_audioFileURL];
    _cachedURL = [NSURL fileURLWithPath:_cachedPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:_cachedPath]) {
        
        [[NSFileManager defaultManager] createFileAtPath:_cachedPath contents:nil attributes:nil];
#if TARGET_OS_IPHONE
        [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey: NSFileProtectionNone}
                                         ofItemAtPath:_cachedPath
                                                error:NULL];
#endif /* TARGET_OS_IPHONE */
        [[NSFileHandle fileHandleForWritingAtPath:_cachedPath] truncateFileAtOffset:_expectedLength];
    }
    _mappedData = [NSData dou_modifiableDataWithMappedContentsOfFile:_cachedPath];
}


- (BOOL)checkRequireRangeFullfilledAndRemoveFullfilled:(BOOL)remove {
    BOOL requringRangeFullfilled = YES;
    NSMutableArray *fullfilled = [NSMutableArray arrayWithCapacity:_requringRanges.count];
    for(NSArray<NSNumber *> * _Nonnull wrappedRange in _requringRanges) {
        if ([self.cacheInfo rangeAvaible:NSMakeRange(wrappedRange.firstObject.unsignedIntegerValue, wrappedRange.lastObject.unsignedIntegerValue)]) {
            requringRangeFullfilled &= YES;
            [fullfilled addObject:wrappedRange];
        }
        else{
            requringRangeFullfilled &= NO;
        }
    }
    if (remove) {
        for(NSArray<NSNumber *> * _Nonnull wrappedRange in fullfilled) {
            [_requringRanges removeObject:wrappedRange];
        }
    }
    
    return requringRangeFullfilled;
}

- (BOOL)requireRangeFullfilled {
    return [self checkRequireRangeFullfilledAndRemoveFullfilled:NO];
}

- (void)tryOpenAudioFile
{
    BOOL requringRangeFullfilled = [self checkRequireRangeFullfilledAndRemoveFullfilled:YES];
    if (requringRangeFullfilled ) {
        _requringRanges = nil;
        
        if ([self open]) {
            _readyToProducePackets = YES;
            _requringRanges = nil;
        }
        else{
            [self requesetNeededRange];
        }
    }
    else{
        [self requesetNeededRange];
    }
}

- (BOOL)isOpened
{
    return _audioFileID != NULL;
}

- (BOOL)open
{
    if ([self isOpened]) {
        return YES;
    }
    
    if (![self _openAudioFileWithFileTypeHint:0] &&
        ![self _openWithFallbacks]) {
        _audioFileID = NULL;
        return NO;
    }
    _requringRanges = nil;
    if (![self _fillFileFormat] ||
        ![self _fillMiscProperties]) {
        AudioFileClose(_audioFileID);
        _audioFileID = NULL;
        return NO;
    }
    
    return YES;
}


- (BOOL)_openWithFallbacks
{
    NSArray *fallbackTypeIDs = [self _fallbackTypeIDs];
    for (NSNumber *typeIDNumber in fallbackTypeIDs) {
        AudioFileTypeID typeID = (AudioFileTypeID)[typeIDNumber unsignedLongValue];
        if ([self _openAudioFileWithFileTypeHint:typeID]) {
            return YES;
        }
    }
    
    return NO;
}

- (void)requesetNeededRange
{
    if (0 == _requringRanges.count) {
        return;
    }
    unsigned long long rangeMin = self.expectedLength;
    for(NSArray<NSNumber *> * _Nonnull wrappedRange in _requringRanges) {
        rangeMin = MIN(rangeMin, wrappedRange.firstObject.unsignedIntegerValue);
    };
    [self requireOffset:(SInt64)rangeMin];
    
}

- (void)_createRequest
{
    [self _createRequest:0 length:0];
}

- (void)_createRequest:(SInt64)position length:(NSUInteger)length
{
    _request = [DOUSimpleHTTPRequest requestWithURL:_audioFileURL];
    NSAssert(position <= _expectedLength, @"require position greater then expectedLength");
    _request.position = (unsigned long long)position;
    _request.userAgent = self.config.userAgent;
    if (_expectedLength > 0) {
        _request.length = MIN((NSUInteger)(_expectedLength - _request.position), length);
    }
    _receivedLength = 0;
    if (_audioFileHost != nil) {
        [_request setHost:_audioFileHost];
    }
    __unsafe_unretained _DOUAudioRemoteFileProvider *_self = self;
    
    [_request setCompletedBlock:^{
        [_self _requestDidComplete];
    }];
    
    [_request setProgressBlock:^(double downloadProgress) {
        [_self _requestDidReportProgress:downloadProgress];
    }];
    
    [_request setDidReceiveResponseBlock:^{
        [_self _requestDidReceiveResponse];
    }];
    
    [_request setDidReceiveDataBlock:^(NSData *data) {
        [_self _requestDidReceiveData:data];
    }];
}

- (NSArray *)_fallbackTypeIDs
{
    NSMutableArray *fallbackTypeIDs = [NSMutableArray array];
    NSMutableSet *fallbackTypeIDSet = [NSMutableSet set];
    
    struct {
        CFStringRef specifier;
        AudioFilePropertyID propertyID;
    } properties[] = {
        { (__bridge CFStringRef)[self mimeType], kAudioFileGlobalInfo_TypesForMIMEType },
        { (__bridge CFStringRef)[self fileExtension], kAudioFileGlobalInfo_TypesForExtension }
    };
    
    const size_t numberOfProperties = sizeof(properties) / sizeof(properties[0]);
    
    for (size_t i = 0; i < numberOfProperties; ++i) {
        if (properties[i].specifier == NULL) {
            continue;
        }
        
        UInt32 outSize = 0;
        OSStatus status;
        
        status = AudioFileGetGlobalInfoSize(properties[i].propertyID,
                                            sizeof(properties[i].specifier),
                                            &properties[i].specifier,
                                            &outSize);
        if (status != noErr) {
            continue;
        }
        
        size_t count = outSize / sizeof(AudioFileTypeID);
        AudioFileTypeID *buffer = (AudioFileTypeID *)malloc(outSize);
        if (buffer == NULL) {
            continue;
        }
        
        status = AudioFileGetGlobalInfo(properties[i].propertyID,
                                        sizeof(properties[i].specifier),
                                        &properties[i].specifier,
                                        &outSize,
                                        buffer);
        if (status != noErr) {
            free(buffer);
            continue;
        }
        
        for (size_t j = 0; j < count; ++j) {
            NSNumber *tid = [NSNumber numberWithUnsignedLong:buffer[j]];
            if ([fallbackTypeIDSet containsObject:tid]) {
                continue;
            }
            
            [fallbackTypeIDs addObject:tid];
            [fallbackTypeIDSet addObject:tid];
        }
        
        free(buffer);
    }
    
    return fallbackTypeIDs;
}

- (NSString *)fileExtension
{
    if (_fileExtension == nil) {
        _fileExtension = [[[[self audioFile] audioFileURL] path] pathExtension];
    }
    
    return _fileExtension;
}


static OSStatus audio_file_probe(void *inClientData,
                                 SInt64 inPosition,
                                 UInt32 requestCount,
                                 void *buffer,
                                 UInt32 *actualCount)
{
    __unsafe_unretained _DOUAudioRemoteFileProvider *fileProvider = (__bridge _DOUAudioRemoteFileProvider *)inClientData;
    
    *actualCount = (UInt32)[fileProvider readIntoBuffer:buffer withRange:NSMakeRange((NSUInteger)inPosition, requestCount)];
    if (*actualCount < requestCount){
        //[fileProvider seekToOffset:inPosition + *actualCount];
        NSArray<NSNumber *>* requireRange = @[@(inPosition), @(requestCount)];
        [fileProvider.requringRanges addObject:requireRange];
        return kAudioFileInvalidChunkError;
    }
    else{
        return noErr;
    }
}

static SInt64 audio_file_get_size(void *inClientData)
{
    __unsafe_unretained _DOUAudioRemoteFileProvider *fileProvider = (__bridge _DOUAudioRemoteFileProvider *)inClientData;
    return (SInt64)[fileProvider expectedLength];
}

- (void)lockForRead
{
    pthread_mutex_lock(&_dataMutex);
}
- (void)unlockForRead
{
    pthread_mutex_unlock(&_dataMutex);
}

- (BOOL)rangeAvaiable:(NSRange)range
{
    return [self.cacheInfo rangeAvaible:range];
}

- (void)requireOffset:(SInt64)offset
{
    NSRange range = [self.cacheInfo nextNeedCacheRangeWithStartOffset:(NSUInteger)offset];
    if (0 == range.length) {
        return;
    }
    if (_request && !_request.isFinished && range.location >= _request.position && (0 == _request.length || range.location < _request.length + _request.position)) { //avoid already request
        return;
    }
    [self cancelRequest];
    [self _createRequest:(SInt64)range.location length:0];
    [_request start];
}

- (NSUInteger)readIntoBuffer:(UInt8*)buffer withRange:(NSRange)range
{
    NSRange cachedRange = [self.cacheInfo cachedRangeWithOffset:range.location];
    if(cachedRange.length > 0)
    {
        cachedRange.length = MIN(range.length, cachedRange.length);
        [super readIntoBuffer:buffer withRange:cachedRange];
    }
    
    return cachedRange.length;
}

- (BOOL)_openAudioFileWithFileTypeHint:(AudioFileTypeID)fileTypeHint
{
    
    OSStatus status;
    status = AudioFileOpenWithCallbacks((__bridge void *)self,
                                        audio_file_probe,
                                        NULL,
                                        audio_file_get_size,
                                        NULL,
                                        fileTypeHint,
                                        &_audioFileID);
    if (status == noErr) {
        _audioFileTypeID = fileTypeHint;
        self.cacheInfo.audioFileTypeHint = fileTypeHint;
    }
    return status == noErr;
}


- (BOOL)_fillFileFormat
{
    UInt32 size;
    OSStatus status;
    
    status = AudioFileGetPropertyInfo(_audioFileID, kAudioFilePropertyFormatList, &size, NULL);
    if (status != noErr) {
        return NO;
    }
    
    UInt32 numFormats = size / sizeof(AudioFormatListItem);
    AudioFormatListItem *formatList = (AudioFormatListItem *)malloc(size);
    
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyFormatList, &size, formatList);
    if (status != noErr) {
        free(formatList);
        return NO;
    }
    
    if (numFormats == 1) {
        _fileFormat = formatList[0].mASBD;
    }
    else {
        status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &size);
        if (status != noErr) {
            free(formatList);
            return NO;
        }
        
        UInt32 numDecoders = size / sizeof(OSType);
        OSType *decoderIDS = (OSType *)malloc(size);
        
        status = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &size, decoderIDS);
        if (status != noErr) {
            free(formatList);
            free(decoderIDS);
            return NO;
        }
        
        UInt32 i;
        for (i = 0; i < numFormats; ++i) {
            OSType decoderID = formatList[i].mASBD.mFormatID;
            
            BOOL found = NO;
            for (UInt32 j = 0; j < numDecoders; ++j) {
                if (decoderID == decoderIDS[j]) {
                    found = YES;
                    break;
                }
            }
            
            if (found) {
                break;
            }
        }
        
        free(decoderIDS);
        
        if (i >= numFormats) {
            free(formatList);
            return NO;
        }
        
        _fileFormat = formatList[i].mASBD;
    }
    
    free(formatList);
    return YES;
}

- (BOOL)_fillMiscProperties
{
    UInt32 size;
    OSStatus status;
    
    UInt32 bitRate = 0;
    size = sizeof(bitRate);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyBitRate, &size, &bitRate);
    if (status != noErr) {
        return NO;
    }
    _bitRate = bitRate;
    
    SInt64 dataOffset = 0;
    size = sizeof(dataOffset);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyDataOffset, &size, &dataOffset);
    if (status != noErr) {
        return NO;
    }
    _dataOffset = (NSUInteger)dataOffset;
    
    Float64 estimatedDuration = 0.0;
    size = sizeof(estimatedDuration);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyEstimatedDuration, &size, &estimatedDuration);
    if (status != noErr) {
        return NO;
    }
    _estimatedDuration = estimatedDuration * 1000.0;
    
    SInt64 audioDataByteCount = 0;
    size = sizeof(audioDataByteCount);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyAudioDataByteCount, &size, &audioDataByteCount);
    if (status != noErr) {
        return NO;
    }
    _audioDataByteCount = (NSUInteger)audioDataByteCount;
    
    SInt64 audioDataPacketCount = 0;
    size = sizeof(audioDataPacketCount);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyAudioDataPacketCount, &size, &audioDataPacketCount);
    if (status != noErr) {
        return NO;
    }
    _audioDataPacketCount = (NSUInteger)audioDataPacketCount;
    
    return YES;
}


- (BOOL)shouldInvokeDecoder
{
    return YES;
}

- (void)_closeAudioFile
{
    _requringRanges = nil;
    if (_audioFileID != NULL) {
        AudioFileClose(_audioFileID);
        _audioFileID = NULL;
    }
}

- (BOOL)isReady
{
    return _readyToProducePackets;
}


- (unsigned long long)receivedLength
{
    return self.expectedLength;
}

- (double)bufferingRatio
{
    return 0.0f / [self expectedLength];
}

- (BOOL)isFinished
{
    return [self.cacheInfo isCacheCompleted];
}


- (NSMutableArray<NSArray<NSNumber *>*> *)requringRanges
{
    if (nil == _requringRanges) {
        _requringRanges = [NSMutableArray array];
    }
    return _requringRanges;
}

- (void)setRequireRanges:(NSMutableArray * _Nullable)ranges
{
    _requringRanges = ranges;
}
@end

