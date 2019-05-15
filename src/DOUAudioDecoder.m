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

#import "DOUAudioDecoder.h"
#import "DOUAudioFileProvider.h"
#import "DOUAudioPlaybackItem.h"
#import "DOUAudioLPCM.h"
#include <AudioToolbox/AudioToolbox.h>
#include <pthread.h>
#import "DOUAudioRemoteFileProvider.h"

#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50

typedef struct {
    AudioFileID afid;
    SInt64 pos;
    void *srcBuffer;
    UInt32 srcBufferSize;
    AudioStreamBasicDescription srcFormat;
    UInt32 srcSizePerPacket;
    UInt32 numPacketsPerRead;
    AudioStreamPacketDescription *pktDescs;
} AudioFileIO;

typedef struct {
    AudioStreamBasicDescription inputFormat;
    AudioStreamBasicDescription outputFormat;
    
    AudioFileIO afio;
    
    SInt64 decodeValidFrames;
    AudioStreamPacketDescription *outputPktDescs;
    
    UInt32 outputBufferSize;
    void *outputBuffer;
    
    UInt32 numOutputPackets;
    SInt64 outputPos;
    
    pthread_mutex_t mutex;
} DecodingContext;

@interface DOUAudioDecoder () {
@private
    DOUAudioPlaybackItem *_playbackItem;
    DOUAudioLPCM *_lpcm;
    
    AudioStreamBasicDescription _outputFormat;
    AudioConverterRef _audioConverter;
    
    NSUInteger _bufferSize;
    DecodingContext _decodingContext;
    BOOL _decodingContextInitialized;
    BOOL _setupBeforeFinished;
    
}
@end

@implementation DOUAudioDecoder

@synthesize playbackItem = _playbackItem;
@synthesize lpcm = _lpcm;

+ (AudioStreamBasicDescription)defaultOutputFormat
{
    static AudioStreamBasicDescription defaultOutputFormat;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultOutputFormat.mFormatID = kAudioFormatLinearPCM;
        defaultOutputFormat.mSampleRate = 44100;
        
        defaultOutputFormat.mBitsPerChannel = 16;
        defaultOutputFormat.mChannelsPerFrame = 2;
        defaultOutputFormat.mBytesPerFrame = defaultOutputFormat.mChannelsPerFrame * (defaultOutputFormat.mBitsPerChannel / 8);
        
        defaultOutputFormat.mFramesPerPacket = 1;
        defaultOutputFormat.mBytesPerPacket = defaultOutputFormat.mFramesPerPacket * defaultOutputFormat.mBytesPerFrame;
        
        defaultOutputFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    });
    
    return defaultOutputFormat;
}

+ (instancetype)decoderWithPlaybackItem:(DOUAudioPlaybackItem *)playbackItem
                             bufferSize:(NSUInteger)bufferSize
{
    return [[[self class] alloc] initWithPlaybackItem:playbackItem
                                           bufferSize:bufferSize];
}

- (instancetype)initWithPlaybackItem:(DOUAudioPlaybackItem *)playbackItem
                          bufferSize:(NSUInteger)bufferSize
{
    self = [super init];
    if (self) {
        _playbackItem = playbackItem;
        _bufferSize = bufferSize;
        _lpcm = [[DOUAudioLPCM alloc] init];
        
        _outputFormat = [[self class] defaultOutputFormat];
        [self _createAudioConverter];
        
        if (_audioConverter == NULL) {
            return nil;
        }
    }
    
    return self;
}

- (void)dealloc
{
    if (_decodingContextInitialized) {
        [self tearDown];
    }
    
    if (_audioConverter != NULL) {
        AudioConverterDispose(_audioConverter);
        _audioConverter = NULL;
    }
}

- (void)_createAudioConverter
{
    AudioStreamBasicDescription inputFormat = [_playbackItem fileFormat];
    
    OSStatus status = AudioConverterNew(&inputFormat, &_outputFormat, &_audioConverter);
    if (status != noErr) {
        _audioConverter = NULL;
    }
}

- (void)_fillMagicCookieForAudioFileID:(AudioFileID)inputFile
{
    UInt32 cookieSize = 0;
    OSStatus status = AudioFileGetPropertyInfo(inputFile, kAudioFilePropertyMagicCookieData, &cookieSize, NULL);
    
    if (status == noErr && cookieSize > 0) {
        void *cookie = malloc(cookieSize);
        
        status = AudioFileGetProperty(inputFile, kAudioFilePropertyMagicCookieData, &cookieSize, cookie);
        if (status != noErr) {
            free(cookie);
            return;
        }
        
        status = AudioConverterSetProperty(_audioConverter, kAudioConverterDecompressionMagicCookie, cookieSize, cookie);
        free(cookie);
        if (status != noErr) {
            return;
        }
    }
}

- (BOOL)refreshDecodingContext
{
    AudioFileID inputFile = [_playbackItem fileID];
    if (inputFile == NULL) {
        return NO;
    }
    
    _decodingContext.inputFormat = [_playbackItem fileFormat];
    _decodingContext.outputFormat = _outputFormat;
    [self _fillMagicCookieForAudioFileID:inputFile];
    
    _decodingContext.afio.afid = inputFile;
    return YES;
}

- (BOOL)setUp
{
    if (_decodingContextInitialized) {
        return YES;
    }
    
    if(![self refreshDecodingContext]){
        return NO;
    }
    
    AudioFileID inputFile = [_playbackItem fileID];
    
    UInt32 size;
    OSStatus status;
    
    size = sizeof(_decodingContext.inputFormat);
    status = AudioConverterGetProperty(_audioConverter, kAudioConverterCurrentInputStreamDescription, &size, &_decodingContext.inputFormat);
    if (status != noErr) {
        return NO;
    }
    
    size = sizeof(_decodingContext.outputFormat);
    status = AudioConverterGetProperty(_audioConverter, kAudioConverterCurrentOutputStreamDescription, &size, &_decodingContext.outputFormat);
    if (status != noErr) {
        return NO;
    }
    
    AudioStreamBasicDescription baseFormat;
    UInt32 propertySize = sizeof(baseFormat);
    AudioFileGetProperty(inputFile, kAudioFilePropertyDataFormat, &propertySize, &baseFormat);
    
    double actualToBaseSampleRateRatio = 1.0;
    if (_decodingContext.inputFormat.mSampleRate != baseFormat.mSampleRate &&
        _decodingContext.inputFormat.mSampleRate != 0.0 &&
        baseFormat.mSampleRate != 0.0) {
        actualToBaseSampleRateRatio = _decodingContext.inputFormat.mSampleRate / baseFormat.mSampleRate;
    }
    
    double srcRatio = 1.0;
    if (_decodingContext.outputFormat.mSampleRate != 0.0 &&
        _decodingContext.inputFormat.mSampleRate != 0.0) {
        srcRatio = _decodingContext.outputFormat.mSampleRate / _decodingContext.inputFormat.mSampleRate;
    }
    
    _decodingContext.decodeValidFrames = 0;
    AudioFilePacketTableInfo srcPti;
    if (_decodingContext.inputFormat.mBitsPerChannel == 0) {
        size = sizeof(srcPti);
        status = AudioFileGetProperty(inputFile, kAudioFilePropertyPacketTableInfo, &size, &srcPti);
        if (status == noErr) {
            _decodingContext.decodeValidFrames = (SInt64)(actualToBaseSampleRateRatio * srcRatio * srcPti.mNumberValidFrames + 0.5);
            
            AudioConverterPrimeInfo primeInfo;
            primeInfo.leadingFrames = (UInt32)(srcPti.mPrimingFrames * actualToBaseSampleRateRatio + 0.5);
            primeInfo.trailingFrames = 0;
            
            status = AudioConverterSetProperty(_audioConverter, kAudioConverterPrimeInfo, sizeof(primeInfo), &primeInfo);
            if (status != noErr) {
                return NO;
            }
        }
    }
    
    _decodingContext.afio.afid = inputFile;
    _decodingContext.afio.srcBufferSize = (UInt32)_bufferSize;
    _decodingContext.afio.srcBuffer = malloc(_decodingContext.afio.srcBufferSize);
    _decodingContext.afio.pos = 0;
    _decodingContext.afio.srcFormat = _decodingContext.inputFormat;
    
    if (_decodingContext.inputFormat.mBytesPerPacket == 0) {
        size = sizeof(_decodingContext.afio.srcSizePerPacket);
        status = AudioFileGetProperty(inputFile, kAudioFilePropertyPacketSizeUpperBound, &size, &_decodingContext.afio.srcSizePerPacket);
        if (status != noErr) {
            free(_decodingContext.afio.srcBuffer);
            return NO;
        }
        
        _decodingContext.afio.numPacketsPerRead = _decodingContext.afio.srcBufferSize / _decodingContext.afio.srcSizePerPacket;
        _decodingContext.afio.pktDescs = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * _decodingContext.afio.numPacketsPerRead);
    }
    else {
        _decodingContext.afio.srcSizePerPacket = _decodingContext.inputFormat.mBytesPerPacket;
        _decodingContext.afio.numPacketsPerRead = _decodingContext.afio.srcBufferSize / _decodingContext.afio.srcSizePerPacket;
        _decodingContext.afio.pktDescs = NULL;
    }
    
    _decodingContext.outputPktDescs = NULL;
    UInt32 outputSizePerPacket = _decodingContext.outputFormat.mBytesPerPacket;
    
    _decodingContext.outputBufferSize = (UInt32)_bufferSize;
    _decodingContext.outputBuffer = malloc(_decodingContext.outputBufferSize);
    
    if (outputSizePerPacket == 0) {
        size = sizeof(outputSizePerPacket);
        status = AudioConverterGetProperty(_audioConverter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket);
        if (status != noErr) {
            free(_decodingContext.afio.srcBuffer);
            free(_decodingContext.outputBuffer);
            if (_decodingContext.afio.pktDescs != NULL) {
                free(_decodingContext.afio.pktDescs);
            }
            return NO;
        }
        
        _decodingContext.outputPktDescs = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * _decodingContext.outputBufferSize / outputSizePerPacket);
    }
    
    _decodingContext.numOutputPackets = _decodingContext.outputBufferSize / outputSizePerPacket;
    _decodingContext.outputPos = 0;
    
    pthread_mutex_init(&_decodingContext.mutex, NULL);
    _decodingContextInitialized = YES;
    _setupBeforeFinished = ![[_playbackItem fileProvider] isFinished];
    return YES;
}

- (void)tearDown
{
    if (!_decodingContextInitialized) {
        return;
    }
    
    free(_decodingContext.afio.srcBuffer);
    free(_decodingContext.outputBuffer);
    
    if (_decodingContext.afio.pktDescs != NULL) {
        free(_decodingContext.afio.pktDescs);
    }
    
    if (_decodingContext.outputPktDescs != NULL) {
        free(_decodingContext.outputPktDescs);
    }
    
    pthread_mutex_destroy(&_decodingContext.mutex);
    _decodingContextInitialized = NO;
}

static OSStatus decoder_data_proc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AudioFileIO *afio = (AudioFileIO *)inUserData;
    
    if (*ioNumberDataPackets > afio->numPacketsPerRead) {
        *ioNumberDataPackets = afio->numPacketsPerRead;
    }
    
    UInt32 outNumBytes = afio->srcBufferSize;
    OSStatus status = AudioFileReadPacketData(afio->afid, YES, &outNumBytes, afio->pktDescs, afio->pos, ioNumberDataPackets, afio->srcBuffer);
    if (status != noErr) {
        return status;
    }
    
    afio->pos += *ioNumberDataPackets;
    
    ioData->mBuffers[0].mData = afio->srcBuffer;
    ioData->mBuffers[0].mDataByteSize = outNumBytes;
    ioData->mBuffers[0].mNumberChannels = afio->srcFormat.mChannelsPerFrame;
    
    if (outDataPacketDescription != NULL) {
        *outDataPacketDescription = afio->pktDescs;
    }
    
    return noErr;
}

- (BOOL)refershAudioFile {
    _playbackItem.requringRanges = nil;
    [_playbackItem close];
    _decodingContext.afio.afid = NULL;
    if (![_playbackItem open]) {
        return NO;
    }
    _decodingContext.afio.afid = [_playbackItem fileID];
    SInt64 pos = _decodingContext.afio.pos;
    AudioConverterReset(_audioConverter);
    _decodingContext.afio.pos = pos;
    return YES;
}

- (DOUAudioDecoderStatus)handleNoMorePacketsWhenUnFinshed:(_DOUAudioRemoteFileProvider *)remoteProvider {
    
    if (_playbackItem.requringRanges.count) {
        return DOUAudioDecoderWaiting;
    }
    else{
        if (![self refershAudioFile]) {
            return DOUAudioDecoderFailed;
        }
        else if ([_playbackItem audioDataPacketCount] > _decodingContext.afio.pos) {
            return DOUAudioDecoderRefreshing;
        }
        else if(_playbackItem.requringRanges.count){
//            AudioFileIO afio;
//            memcpy(&afio,&_decodingContext.afio,sizeof(AudioFileIO));
//            afio.pos += 1;
//            UInt32 ioNumBytes = afio.srcBufferSize;
//            UInt32 ioNumberDataPackets = 1;
//            _playbackItem.requringRanges = nil;
//
//            OSStatus status = AudioFileReadPackets(_playbackItem.fileID, FALSE, &ioNumBytes, afio.pktDescs, afio.pos, &ioNumberDataPackets, afio.srcBuffer);
//            if (_playbackItem.requringRanges.count > 0){
                return DOUAudioDecoderWaiting;
//            }
//            else {
//                if(_playbackItem.audioDataPacketCount == _decodingContext.afio.pos){
//                    return DOUAudioDecoderEndEncountered;
//                }
//                else{
//                    return DOUAudioDecoderFailed;
//                }
//            }
        }
        else{
            if(_playbackItem.audioDataPacketCount == _decodingContext.afio.pos){
                return DOUAudioDecoderEndEncountered;
            }
            else{
                return DOUAudioDecoderFailed;
            }
        }
    }
}

- (DOUAudioDecoderStatus)decodeOnce
{
    if (!_decodingContextInitialized) {
        return DOUAudioDecoderFailed;
    }
    
    pthread_mutex_lock(&_decodingContext.mutex);
    DOUAudioFileProvider *provider = [_playbackItem fileProvider];
    [provider lockForRead];
    if ([provider isFailed]) {
        [_lpcm setEnd:YES];
        [provider unlockForRead];
        pthread_mutex_unlock(&_decodingContext.mutex);
        return DOUAudioDecoderFailed;
    }
    if (_playbackItem.requringRanges.count) {
        [self refershAudioFile];
        if ([_playbackItem audioDataPacketCount] < _decodingContext.afio.pos) {
            [provider unlockForRead];
            pthread_mutex_unlock(&_decodingContext.mutex);
            return DOUAudioDecoderWaiting;
        }
    }
    _playbackItem.requringRanges = nil;
    AudioBufferList fillBufList;
    fillBufList.mNumberBuffers = 1;
    fillBufList.mBuffers[0].mNumberChannels = _decodingContext.inputFormat.mChannelsPerFrame;
    fillBufList.mBuffers[0].mDataByteSize = _decodingContext.outputBufferSize;
    fillBufList.mBuffers[0].mData = _decodingContext.outputBuffer;
    
    OSStatus status;
    
    UInt32 ioOutputDataPackets = _decodingContext.numOutputPackets;
    status = AudioConverterFillComplexBuffer(_audioConverter, decoder_data_proc, &_decodingContext.afio, &ioOutputDataPackets, &fillBufList, _decodingContext.outputPktDescs);
    if (status != noErr) {
        if (!_setupBeforeFinished) {
            [provider unlockForRead];
            pthread_mutex_unlock(&_decodingContext.mutex);
            return DOUAudioDecoderFailed;
        }
        else {
            
            _DOUAudioRemoteFileProvider *remoteProvider = (_DOUAudioRemoteFileProvider *)provider;
            if (_playbackItem.requringRanges.count) {
                [provider unlockForRead];
                [remoteProvider setRequireRanges:_playbackItem.requringRanges];
                [remoteProvider requesetNeededRange];
                pthread_mutex_unlock(&_decodingContext.mutex);
                return DOUAudioDecoderWaiting;
            }
            else{
                [provider unlockForRead];
                pthread_mutex_unlock(&_decodingContext.mutex);
                return DOUAudioDecoderFailed;
            }
        }
    }
    
    if (ioOutputDataPackets == 0) {
        if (!_setupBeforeFinished ) {
            [_lpcm setEnd:YES];
            [provider unlockForRead];
            pthread_mutex_unlock(&_decodingContext.mutex);
            return DOUAudioDecoderEndEncountered;
        }
        else {
            _DOUAudioRemoteFileProvider *remoteProvider = (_DOUAudioRemoteFileProvider *)provider;
            DOUAudioDecoderStatus status = [self handleNoMorePacketsWhenUnFinshed:remoteProvider];
            switch (status) {
                case DOUAudioDecoderSucceeded:
                case DOUAudioDecoderRefreshing:
                case DOUAudioDecoderFailed:
                    [provider unlockForRead];
                    pthread_mutex_unlock(&_decodingContext.mutex);
                    return status;
                    break;
                case DOUAudioDecoderWaiting:
                    NSAssert(_playbackItem.requringRanges.count, @"not handle correctly");
                {
                    [provider unlockForRead];
                    
                    if (_playbackItem.requringRanges.count > 0){
                        
                        [remoteProvider setRequireRanges:_playbackItem.requringRanges];
                        [remoteProvider requesetNeededRange];
                    }
                    pthread_mutex_unlock(&_decodingContext.mutex);
                    return status;
                }
                    break;
                case DOUAudioDecoderEndEncountered:
                    [_lpcm setEnd:YES];
                    [provider unlockForRead];
                    pthread_mutex_unlock(&_decodingContext.mutex);
                    return status;
            }
            
        }
        
        SInt64 frame1 = _decodingContext.outputPos + ioOutputDataPackets;
        if (_decodingContext.decodeValidFrames != 0 &&
            frame1 > _decodingContext.decodeValidFrames) {
            SInt64 framesToTrim64 = frame1 - _decodingContext.decodeValidFrames;
            UInt32 framesToTrim = (framesToTrim64 > ioOutputDataPackets) ? ioOutputDataPackets : (UInt32)framesToTrim64;
            int bytesToTrim = (int)(framesToTrim * _decodingContext.outputFormat.mBytesPerFrame);
            
            fillBufList.mBuffers[0].mDataByteSize -= (unsigned long)bytesToTrim;
            ioOutputDataPackets -= framesToTrim;
            
            if (ioOutputDataPackets == 0) {
                if (!_setupBeforeFinished ) {
                    [_lpcm setEnd:YES];
                    [provider unlockForRead];
                    pthread_mutex_unlock(&_decodingContext.mutex);
                    return DOUAudioDecoderEndEncountered;
                }
                else{
                    
                    _DOUAudioRemoteFileProvider *remoteProvider = (_DOUAudioRemoteFileProvider *)provider;
                    DOUAudioDecoderStatus status = [self handleNoMorePacketsWhenUnFinshed:remoteProvider];
                    switch (status) {
                        case DOUAudioDecoderSucceeded:
                        case DOUAudioDecoderRefreshing:
                        case DOUAudioDecoderFailed:
                            [provider unlockForRead];
                            pthread_mutex_unlock(&_decodingContext.mutex);
                            return status;
                            break;
                        case DOUAudioDecoderWaiting:
                            NSAssert(_playbackItem.requringRanges.count, @"not handle correctly");
                        {
                            [provider unlockForRead];
                            
                            if (_playbackItem.requringRanges.count > 0){
                                
                                [remoteProvider setRequireRanges:_playbackItem.requringRanges];
                                [remoteProvider requesetNeededRange];
                            }
                            pthread_mutex_unlock(&_decodingContext.mutex);
                            return status;
                        }
                            break;
                        case DOUAudioDecoderEndEncountered:
                            [_lpcm setEnd:YES];
                            [provider unlockForRead];
                            pthread_mutex_unlock(&_decodingContext.mutex);
                            return status;
                    }
                    
                }
            }
        }
    }
    
    UInt32 inNumBytes = fillBufList.mBuffers[0].mDataByteSize;
    [_lpcm writeBytes:_decodingContext.outputBuffer length:inNumBytes];
    _decodingContext.outputPos += ioOutputDataPackets;
    [provider unlockForRead];
    pthread_mutex_unlock(&_decodingContext.mutex);
    return DOUAudioDecoderSucceeded;
}


- (void)seekToTime:(NSUInteger)milliseconds
{
    if (!_decodingContextInitialized) {
        return;
    }
    
    pthread_mutex_lock(&_decodingContext.mutex);
    
    double frames = (double)milliseconds * _decodingContext.inputFormat.mSampleRate / 1000.0;
    double packets = frames / _decodingContext.inputFormat.mFramesPerPacket;
    SInt64 packetNumebr = (SInt64)lrint(floor(packets));
    
    _decodingContext.afio.pos = packetNumebr;
    _decodingContext.outputPos = packetNumebr * _decodingContext.inputFormat.mFramesPerPacket / _decodingContext.outputFormat.mFramesPerPacket;
    
    OSStatus status;
    
    status = AudioConverterReset(_audioConverter);
    if (status != noErr) {
        
    }
    pthread_mutex_unlock(&_decodingContext.mutex);
}

@end
