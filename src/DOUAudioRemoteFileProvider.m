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

#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50

#pragma mark - Concrete Audio Remote File Provider

@interface _DOUAudioRemoteFileProvider()

@property (nonatomic, strong) DOUCacheInfo *cacheInfo;

@end

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
        [self _openAudioFileStream];
        [self _createRequest];
        [_request start];
    }
    
    return self;
}

- (AudioFileStreamID)audioFileStreamID
{
    return _audioFileStreamID;
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
    @synchronized(_request) {
        [_request setCompletedBlock:NULL];
        [_request setProgressBlock:NULL];
        [_request setDidReceiveResponseBlock:NULL];
        [_request setDidReceiveDataBlock:NULL];
        
        [_request cancel];
    }
}

- (void)dealloc
{
    [self cancelRequest];
    
    if (_sha256Ctx != NULL) {
        free(_sha256Ctx);
    }
    
    [self _closeAudioFileStream];
    
    [self _closeAudioFile];
    
    if (self.config.options & DOUAudioStreamerRemoveCacheOnDeallocation) {
        [[NSFileManager defaultManager] removeItemAtPath:_cachedPath error:NULL];
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
    NSString *filename = [NSString stringWithFormat:@"douas-%@.tmp", [self _sha256ForAudioFileURL:audioFileURL]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
}

+ (NSString *)_offlinePathForAudioFileURL:(NSURL *)audioFileURL
{
    NSString *filename = [NSString stringWithFormat:@"%@.tmp", [self _sha256ForAudioFileURL:audioFileURL]];
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
    self->_requringRanges = nil;
    if ([_request isFailed] ||
        !([_request statusCode] >= 200 && [_request statusCode] < 300)) {
        _failed = YES;
    }
    else {
        pthread_mutex_lock(&_dataMutex);
        [_mappedData dou_synchronizeMappedFile];
        pthread_mutex_unlock(&_dataMutex);
    }
    if (!_failed && _requireAudioFileAPI && !_audioFileID) {
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
    
    if (self.isFinished && self.hintFile != nil &&
        self.hintProvider == nil) {
        self.hintProvider = [[[self class] alloc] _initWithAudioFile:self.hintFile config:self.config];
    }
    
    [self _invokeEventBlock];
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
        
        _cachedPath = [[self class] _cachedPathForAudioFileURL:_audioFileURL];
        _cachedURL = [NSURL fileURLWithPath:_cachedPath];
        
        [[NSFileManager defaultManager] createFileAtPath:_cachedPath contents:nil attributes:nil];
#if TARGET_OS_IPHONE
        [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey: NSFileProtectionNone}
                                         ofItemAtPath:_cachedPath
                                                error:NULL];
#endif /* TARGET_OS_IPHONE */
        [[NSFileHandle fileHandleForWritingAtPath:_cachedPath] truncateFileAtOffset:_expectedLength];
        
        _mimeType = [[_request responseHeaders] objectForKey:@"Content-Type"];
        
        _mappedData = [NSData dou_modifiableDataWithMappedContentsOfFile:_cachedPath];
        self.cacheInfo.expectedLength = (NSInteger)_expectedLength;
        self.cacheInfo.cacheWriteTmpPath = _cachedPath;
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
    
    _receivedLength += bytesToWrite;
    
    NSRange currentReceivedRange = NSMakeRange(_request.position,_receivedLength);
    
    [self.cacheInfo append:currentReceivedRange];
    pthread_mutex_unlock(&_dataMutex);
    if (_sha256Ctx != NULL) {
        CC_SHA256_Update(_sha256Ctx, [data bytes], (CC_LONG)[data length]);
    }
    
    if (!_readyToProducePackets && !_failed) {
        if(!_requireAudioFileAPI) {
            OSStatus status = kAudioFileStreamError_UnsupportedFileType;
            
            if (_audioFileStreamID != NULL) {
                status = AudioFileStreamParseBytes(_audioFileStreamID,
                                                   (UInt32)[data length],
                                                   [data bytes],
                                                   0);
            }
            
            if (status != noErr && status != kAudioFileStreamError_NotOptimized) {
                NSArray *fallbackTypeIDs = [self _fallbackTypeIDs];
                for (NSNumber *typeIDNumber in fallbackTypeIDs) {
                    AudioFileTypeID typeID = (AudioFileTypeID)[typeIDNumber unsignedLongValue];
                    [self _closeAudioFileStream];
                    [self _openAudioFileStreamWithFileTypeHint:typeID];
                    
                    if (_audioFileStreamID != NULL) {
                        status = AudioFileStreamParseBytes(_audioFileStreamID,
                                                           (UInt32)_receivedLength,
                                                           [_mappedData bytes],
                                                           0);
                        
                        if (status == noErr || status == kAudioFileStreamError_NotOptimized) {
                            break;
                        }
                    }
                }
                
                if (status != noErr && status != kAudioFileStreamError_NotOptimized && status != kAudioFileStreamError_UnsupportedFileType) {
                    _failed = YES;
                }
            }
            
            if (status == kAudioFileStreamError_NotOptimized || status == kAudioFileStreamError_UnsupportedFileType) {
                [self _closeAudioFileStream];
                _requireAudioFileAPI = YES;
            }
        }
        else{
            BOOL requringRangeFullfilled = YES;
            for(NSArray<NSNumber *> * _Nonnull wrappedRange in _requringRanges) {
                requringRangeFullfilled &= [self.cacheInfo rangeAvaible:NSMakeRange(wrappedRange.firstObject.unsignedIntegerValue, wrappedRange.lastObject.unsignedIntegerValue)];
            };
            if (requringRangeFullfilled ) {
                _requringRanges = nil;
                NSArray *fallbackTypeIDs = [self _fallbackTypeIDs];
                for (NSNumber *typeIDNumber in fallbackTypeIDs) {
                    AudioFileTypeID typeID = (AudioFileTypeID)[typeIDNumber unsignedLongValue];
                    [self _openAudioFileWithFileTypeHint:typeID];
                    
                    if (_audioFileID != NULL) {
                        _readyToProducePackets = YES;
                        _requringRanges = nil;
                        break;
                    }
                }
                if (!_audioFileID ) {
                    [self requesetNeededRange];
                }
            }
            
        }
    }
    [self _invokeEventBlock];
}

- (void)requesetNeededRange
{
    if (_requringRanges.count) {
        NSUInteger rangeMin = self.expectedLength;
        for(NSArray<NSNumber *> * _Nonnull wrappedRange in _requringRanges) {
            rangeMin = MIN(rangeMin, wrappedRange.firstObject.unsignedIntegerValue);
        };
        NSRange needRange = [self.cacheInfo nextNeedCacheRangeWithStartOffset:rangeMin];
        [self requireOffset:(SInt64)needRange.location];
    }
}

- (void)_createRequest
{
    [self _createRequest:0];
}

- (void)_createRequest:(SInt64)position
{
    _request = [DOUSimpleHTTPRequest requestWithURL:_audioFileURL];
    NSAssert(position <= _expectedLength, @"require position greater then expectedLength");
    _request.position = (unsigned long long)position;
    //    if (_expectedLength > 0) {
    //        _request.length = _expectedLength - 1 - _request.position;
    //    }
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

- (void)_handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID
{
    if (propertyID == kAudioFileStreamProperty_ReadyToProducePackets) {
        _readyToProducePackets = YES;
    }
}

- (void)_handleAudioFileStreamPackets:(const void *)packets
                        numberOfBytes:(UInt32)numberOfBytes
                      numberOfPackets:(UInt32)numberOfPackets
                   packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins
{
}

static void audio_file_stream_property_listener_proc(void *inClientData,
                                                     AudioFileStreamID inAudioFileStream,
                                                     AudioFileStreamPropertyID inPropertyID,
                                                     UInt32 *ioFlags)
{
    __unsafe_unretained _DOUAudioRemoteFileProvider *fileProvider = (__bridge _DOUAudioRemoteFileProvider *)inClientData;
    [fileProvider _handleAudioFileStreamProperty:inPropertyID];
}

static void audio_file_stream_packets_proc(void *inClientData,
                                           UInt32 inNumberBytes,
                                           UInt32 inNumberPackets,
                                           const void *inInputData,
                                           AudioStreamPacketDescription    *inPacketDescriptions)
{
    __unsafe_unretained _DOUAudioRemoteFileProvider *fileProvider = (__bridge _DOUAudioRemoteFileProvider *)inClientData;
    [fileProvider _handleAudioFileStreamPackets:inInputData
                                  numberOfBytes:inNumberBytes
                                numberOfPackets:inNumberPackets
                             packetDescriptions:inPacketDescriptions];
}

- (void)_openAudioFileStream
{
    [self _openAudioFileStreamWithFileTypeHint:0];
}

- (void)_openAudioFileStreamWithFileTypeHint:(AudioFileTypeID)fileTypeHint
{
    OSStatus status = AudioFileStreamOpen((__bridge void *)self,
                                          audio_file_stream_property_listener_proc,
                                          audio_file_stream_packets_proc,
                                          fileTypeHint,
                                          &_audioFileStreamID);
    
    if (status != noErr) {
        _audioFileStreamID = NULL;
    }
}

- (void)_closeAudioFileStream
{
    if (_audioFileStreamID != NULL) {
        AudioFileStreamClose(_audioFileStreamID);
        _audioFileStreamID = NULL;
    }
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
    }
    return noErr;
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
    if (range.location == _request.position + _request.receivedLength) {
        return;
    }
    [self cancelRequest];
    [self _createRequest:offset];
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
    }
    return status == noErr;
}

- (void)_closeAudioFile
{
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

- (DOUCacheInfo *)cacheInfo
{
    if (nil == _cacheInfo) {
        _cacheInfo = [[DOUCacheInfo alloc] init];
    }
    return _cacheInfo;
}

- (NSMutableArray<NSArray<NSNumber *>*> *)requringRanges
{
    if (nil == _requringRanges) {
        _requringRanges = [NSMutableArray array];
    }
    return _requringRanges;
}

- (void)setRequireRanges:(NSMutableArray *)ranges
{
    _requringRanges = ranges;
}
@end

