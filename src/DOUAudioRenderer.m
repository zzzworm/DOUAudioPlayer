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

#import "DOUAudioRenderer.h"
#import "DOUAudioDecoder.h"
#import "DOUAudioAnalyzer.h"
#include <CoreAudio/CoreAudioTypes.h>
#include <AudioUnit/AudioUnit.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/time.h>
#include <mach/mach_time.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AUiPodTimeProxy.h"

#if !TARGET_OS_IPHONE
#include <CoreAudio/CoreAudio.h>
#endif /* !TARGET_OS_IPHONE */

#if TARGET_OS_IPHONE
#include <Accelerate/Accelerate.h>
#endif /* TARGET_OS_IPHONE */

@interface DOUAudioRenderer () {
@private
  pthread_mutex_t _mutex;
  pthread_cond_t _cond;

  uint8_t *_buffer;
  NSUInteger _bufferByteCount;
  NSUInteger _firstValidByteOffset;
  NSUInteger _validByteCount;

  NSUInteger _bufferTime;
  BOOL _started;

  NSArray *_analyzers;

  uint64_t _startedTime;
  uint64_t _interruptedTime;
  uint64_t _totalInterruptedInterval;
  
    AUGraph _graph;
    AudioUnit _remoteIOUnit;
    AudioUnit _converterUnit;
    AudioUnit _aUiPodTimeUnit;
    
    AUiPodTimeProxy *_aUiPodTimeProxy;
    
#if TARGET_OS_IPHONE
  double _volume;
#endif /* TARGET_OS_IPHONE */
}
@end

@implementation DOUAudioRenderer

@synthesize started = _started;
@synthesize analyzers = _analyzers;

+ (instancetype)rendererWithBufferTime:(NSUInteger)bufferTime
{
  return [[[self class] alloc] initWithBufferTime:bufferTime];
}

- (instancetype)initWithBufferTime:(NSUInteger)bufferTime
{
  self = [super init];
  if (self) {
    pthread_mutex_init(&_mutex, NULL);
    pthread_cond_init(&_cond, NULL);

    _bufferTime = bufferTime;
#if TARGET_OS_IPHONE
    _volume = 1.0;
#endif /* TARGET_OS_IPHONE */

#if !TARGET_OS_IPHONE
    [self _setupPropertyListenerForDefaultOutputDevice];
#endif /* !TARGET_OS_IPHONE */
  }

  return self;
}

- (void)dealloc
{
#if !TARGET_OS_IPHONE
  [self _removePropertyListenerForDefaultOutputDevice];
#endif /* !TARGET_OS_IPHONE */

  if (_graph != NULL) {
    [self tearDown];
  }

  if (_buffer != NULL) {
    free(_buffer);
  }

  pthread_mutex_destroy(&_mutex);
  pthread_cond_destroy(&_cond);
}

- (void)_setShouldInterceptTiming:(BOOL)shouldInterceptTiming
{
  if (_startedTime == 0) {
    _startedTime = mach_absolute_time();
  }

  if ((_interruptedTime != 0) == shouldInterceptTiming) {
    return;
  }

  if (shouldInterceptTiming) {
    _interruptedTime = mach_absolute_time();
  }
  else {
    _totalInterruptedInterval += mach_absolute_time() - _interruptedTime;
    _interruptedTime = 0;
  }
}

static OSStatus au_render_callback(void *inRefCon,
                                   AudioUnitRenderActionFlags *inActionFlags,
                                   const AudioTimeStamp *inTimeStamp,
                                   UInt32 inBusNumber,
                                   UInt32 inNumberFrames,
                                   AudioBufferList *ioData)
{
  __unsafe_unretained DOUAudioRenderer *renderer = (__bridge DOUAudioRenderer *)inRefCon;
  pthread_mutex_lock(&renderer->_mutex);

  NSUInteger totalBytesToCopy = ioData->mBuffers[0].mDataByteSize;
  NSUInteger validByteCount = renderer->_validByteCount;

  if (validByteCount < totalBytesToCopy) {
    [renderer->_analyzers makeObjectsPerformSelector:@selector(flush)];
    [renderer _setShouldInterceptTiming:YES];

    *inActionFlags = kAudioUnitRenderAction_OutputIsSilence;
    bzero(ioData->mBuffers[0].mData, ioData->mBuffers[0].mDataByteSize);
    pthread_mutex_unlock(&renderer->_mutex);
    return noErr;
  }
  else {
    [renderer _setShouldInterceptTiming:NO];
  }

  uint8_t *bytes = renderer->_buffer + renderer->_firstValidByteOffset;
  uint8_t *outBuffer = (uint8_t *)ioData->mBuffers[0].mData;
  NSUInteger outBufSize = ioData->mBuffers[0].mDataByteSize;
  NSUInteger bytesToCopy = MIN(outBufSize, validByteCount);
  NSUInteger firstFrag = bytesToCopy;

  if (renderer->_firstValidByteOffset + bytesToCopy > renderer->_bufferByteCount) {
    firstFrag = renderer->_bufferByteCount - renderer->_firstValidByteOffset;
  }

  if (firstFrag < bytesToCopy) {
    memcpy(outBuffer, bytes, firstFrag);
    memcpy(outBuffer + firstFrag, renderer->_buffer, bytesToCopy - firstFrag);
  }
  else {
    memcpy(outBuffer, bytes, bytesToCopy);
  }

  NSArray *analyzers = renderer->_analyzers;
  if (analyzers != nil) {
    for (DOUAudioAnalyzer *analyzer in analyzers) {
      [analyzer handleLPCMSamples:(int16_t *)outBuffer
                            count:bytesToCopy / sizeof(int16_t)];
    }
  }

#if TARGET_OS_IPHONE
  if (renderer->_volume != 1.0) {
    int16_t *samples = (int16_t *)outBuffer;
    size_t samplesCount = bytesToCopy / sizeof(int16_t);

    float floatSamples[samplesCount];
    vDSP_vflt16(samples, 1, floatSamples, 1, samplesCount);

    float volume = renderer->_volume;
    vDSP_vsmul(floatSamples, 1, &volume, floatSamples, 1, samplesCount);

    vDSP_vfix16(floatSamples, 1, samples, 1, samplesCount);
  }
#endif /* TARGET_OS_IPHONE */

  if (bytesToCopy < outBufSize) {
    bzero(outBuffer + bytesToCopy, outBufSize - bytesToCopy);
  }

  renderer->_validByteCount -= bytesToCopy;
  renderer->_firstValidByteOffset = (renderer->_firstValidByteOffset + bytesToCopy) % renderer->_bufferByteCount;

  pthread_mutex_unlock(&renderer->_mutex);
  pthread_cond_signal(&renderer->_cond);

  return noErr;
}

- (AudioStreamBasicDescription) AUCanonicalASBD:(Float64)sampleRate channel:(UInt32)channel {
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate = sampleRate;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    audioFormat.mChannelsPerFrame = channel;
    audioFormat.mBytesPerPacket = sizeof(Float32);
    audioFormat.mBytesPerFrame = sizeof(Float32);
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mBitsPerChannel = 8 * sizeof(Float32);
    audioFormat.mReserved = 0;
    return audioFormat;
}

- (BOOL)setUp
{
  if (_graph != NULL) {
    return YES;
  }

  OSStatus status;

#if !TARGET_OS_IPHONE
  CFRunLoopRef runLoop = NULL;
  AudioObjectPropertyAddress address = {
    kAudioHardwarePropertyRunLoop,
    kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyElementMaster
  };
  status = AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, sizeof(runLoop), &runLoop);
  if (status != noErr) {
    return NO;
  }
#endif /* !TARGET_OS_IPHONE */

    status = NewAUGraph(&_graph);
    if (status != noErr) {
        return NO;
    }
    //............................................................................
    // Open the audio processing graph
    
    // Following this call, the audio units are instantiated but not initialized
    //    (no resource allocation occurs and the audio units are not in a state to
    //    process audio).
    status = AUGraphOpen (_graph);
    
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AUGraphOpen" withStatus: status]; return NO;}
    
    AudioComponentDescription convertDesc;
    
    convertDesc.componentType = kAudioUnitType_FormatConverter;
    convertDesc.componentSubType = kAudioUnitSubType_AUConverter;
    convertDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    convertDesc.componentFlags = 0;
    convertDesc.componentFlagsMask = 0;
    AUNode converterNode;
    status = AUGraphAddNode(_graph, &convertDesc, &converterNode);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AUGraphAddNode failed for convert unit" withStatus:status]; return NO;}
    status = AUGraphNodeInfo(_graph, converterNode, NULL, &_converterUnit);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AUGraphNodeInfo failed for convert unit" withStatus:status]; return NO;}
    
    convertDesc.componentType = kAudioUnitType_FormatConverter;
    convertDesc.componentSubType = kAudioUnitSubType_AUiPodTimeOther;
    convertDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    convertDesc.componentFlags = 0;
    convertDesc.componentFlagsMask = 0;
    AUNode aUiPodTimeNode;
    status = AUGraphAddNode(_graph, &convertDesc, &aUiPodTimeNode);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AUGraphAddNode failed for convert unit" withStatus:status]; return NO;}
    status = AUGraphNodeInfo(_graph, aUiPodTimeNode, NULL, &_aUiPodTimeUnit);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AUGraphNodeInfo failed for convert unit" withStatus:status]; return NO;}
    
  AudioComponentDescription desc;
  desc.componentType = kAudioUnitType_Output;
#if TARGET_OS_IPHONE
  desc.componentSubType = kAudioUnitSubType_RemoteIO;
#else /* TARGET_OS_IPHONE */
  desc.componentSubType = kAudioUnitSubType_HALOutput;
#endif /* TARGET_OS_IPHONE */
  desc.componentManufacturer = kAudioUnitManufacturer_Apple;
  desc.componentFlags = 0;
  desc.componentFlagsMask = 0;

    AUNode remoteIONode;
    status = AUGraphAddNode(_graph, &desc, &remoteIONode);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AUGraphAddNode failed for I/O unit" withStatus:status]; return NO;}
    status = AUGraphNodeInfo(_graph, remoteIONode, NULL, &_remoteIOUnit);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AUGraphNodeInfo failed for I/O unit" withStatus:status]; return NO;}
    
    AURenderCallbackStruct input;
    input.inputProc = au_render_callback;
    input.inputProcRefCon = (__bridge void *)self;
    
    status = AUGraphSetNodeInputCallback(_graph,converterNode, 0, &input);
    if (status != noErr) {
        _graph = NULL;
        return NO;
    }
    
  AudioStreamBasicDescription requestedDesc = [DOUAudioDecoder defaultOutputFormat];

  status = AudioUnitSetProperty(_remoteIOUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &requestedDesc, sizeof(requestedDesc));
  if (status != noErr) {
    _graph = NULL;
    return NO;
  }
    UInt32 size = sizeof(requestedDesc);
    
    status = AudioUnitGetProperty(_remoteIOUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &requestedDesc, &size);
    if (status != noErr) {
        
        _graph = NULL;
        return NO;
    }

   AudioStreamBasicDescription outputFormat = [self AUCanonicalASBD:requestedDesc.mSampleRate channel:requestedDesc.mChannelsPerFrame];
    
    status = AudioUnitSetProperty(_converterUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input, 0,
                         &requestedDesc, size);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AudioUnitSetProperty failed for convert unit" withStatus:status]; return NO;}
    
    status = AudioUnitSetProperty(_converterUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Output, 0,
                         &outputFormat, size);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AudioUnitSetProperty failed for convert unit" withStatus:status]; return NO;}
    
    status = AudioUnitSetProperty(_aUiPodTimeUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input, 0,
                         &outputFormat, size);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AudioUnitSetProperty failed for convert unit" withStatus:status]; return NO;}
    
    status = AudioUnitSetProperty(_aUiPodTimeUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output, 0,
                                  &outputFormat, size);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AudioUnitSetProperty failed for convert unit" withStatus:status]; return NO;}
    
    status = AudioUnitSetProperty(_remoteIOUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input, 0,
                         &outputFormat, size);
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AudioUnitSetProperty failed for I/O unit" withStatus:status]; return NO;}
    
    AUGraphConnectNodeInput(_graph,
                            converterNode, 0,
                            aUiPodTimeNode, 0);
    
    AUGraphConnectNodeInput(_graph,
                            aUiPodTimeNode, 0,
                            remoteIONode, 0);
    
    _aUiPodTimeProxy = [[AUiPodTimeProxy alloc] initWithAudioUnit:_aUiPodTimeUnit];
    
    NSLog (@"Setting kAudioUnitProperty_MaximumFramesPerSlice for mixer unit global scope");
    // Increase the maximum frames per slice allows the mixer unit to accommodate the
    //    larger slice size used when the screen is locked.
    UInt32 maximumFramesPerSlice = 4096;
    
    status = AudioUnitSetProperty (
                                   _remoteIOUnit,
                                   kAudioUnitProperty_MaximumFramesPerSlice,
                                   kAudioUnitScope_Global,
                                   0,
                                   &maximumFramesPerSlice,
                                   sizeof (maximumFramesPerSlice)
                                   );
    
    if (noErr != status) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit input stream format)" withStatus: status]; return NO;}
    
    //............................................................................
    // Initialize audio processing graph
    
    // Diagnostic code
    // Call CAShow if you want to look at the state of the audio processing
    //    graph.
    NSLog (@"Audio processing graph state immediately before initializing it:");
    CAShow (_graph);
    
    NSLog (@"Initializing the audio processing graph");
    // Initialize the audio processing graph, configure audio data stream formats for
    //    each input and output, and validate the connections between audio units.
    status = AUGraphInitialize (_graph);
    
    if (noErr != status) {_graph = NULL;[self printErrorMessage: @"AUGraphInitialize" withStatus: status]; return NO;}

  if (_buffer == NULL) {
    _bufferByteCount = (_bufferTime * requestedDesc.mSampleRate / 1000) * (requestedDesc.mChannelsPerFrame * requestedDesc.mBitsPerChannel / 8);
    _firstValidByteOffset = 0;
    _validByteCount = 0;
    _buffer = (uint8_t *)calloc(1, _bufferByteCount);
  }

  return YES;
}

- (void)tearDown
{
  if (_graph == NULL) {
    return;
  }

  [self stop];
  [self _tearDownWithoutStop];
}

- (void)_tearDownWithoutStop
{
    AUGraphStop(_graph);
    AUGraphClose(_graph);
  AUGraphUninitialize(_graph);
  _graph = NULL;
}

#if !TARGET_OS_IPHONE

+ (const AudioObjectPropertyAddress *)_propertyListenerAddressForDefaultOutputDevice
{
  static AudioObjectPropertyAddress address;

  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    address.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    address.mScope = kAudioObjectPropertyScopeGlobal;
    address.mElement = kAudioObjectPropertyElementMaster;
  });

  return &address;
}

- (void)_handlePropertyListenerForDefaultOutputDevice
{
  if (_remoteIOUnit == NULL) {
    return;
  }

  BOOL started = _started;
  [self stop];

  pthread_mutex_lock(&_mutex);

  [self _tearDownWithoutStop];
  [self setUp];

  if (started) {
    AudioOutputUnitStart(_remoteIOUnit);
    _started = YES;
  }

  pthread_mutex_unlock(&_mutex);
}

static OSStatus property_listener_default_output_device(AudioObjectID inObjectID,
                                                        UInt32 inNumberAddresses,
                                                        const AudioObjectPropertyAddress inAddresses[],
                                                        void *inClientData)
{
  __unsafe_unretained DOUAudioRenderer *renderer = (__bridge DOUAudioRenderer *)inClientData;
  [renderer _handlePropertyListenerForDefaultOutputDevice];
  return noErr;
}

- (void)_setupPropertyListenerForDefaultOutputDevice
{
  AudioObjectAddPropertyListener(kAudioObjectSystemObject,
                                 [[self class] _propertyListenerAddressForDefaultOutputDevice],
                                 property_listener_default_output_device,
                                 (__bridge void *)self);
}

- (void)_removePropertyListenerForDefaultOutputDevice
{
  AudioObjectRemovePropertyListener(kAudioObjectSystemObject,
                                    [[self class] _propertyListenerAddressForDefaultOutputDevice],
                                    property_listener_default_output_device,
                                    (__bridge void *)self);
}

#endif /* !TARGET_OS_IPHONE */

- (void)renderBytes:(const void *)bytes length:(NSUInteger)length
{
  if (_graph == NULL) {
    return;
  }

  while (length > 0) {
    pthread_mutex_lock(&_mutex);

    NSUInteger emptyByteCount = _bufferByteCount - _validByteCount;
    while (emptyByteCount == 0) {
      if (!_started) {
        if (_interrupted) {
          pthread_mutex_unlock(&_mutex);
          return;
        }

        pthread_mutex_unlock(&_mutex);
        AUGraphStart(_graph);
        pthread_mutex_lock(&_mutex);
        _started = YES;
      }

      struct timeval tv;
      struct timespec ts;
      gettimeofday(&tv, NULL);
      ts.tv_sec = tv.tv_sec + 1;
      ts.tv_nsec = 0;
      pthread_cond_timedwait(&_cond, &_mutex, &ts);
      emptyByteCount = _bufferByteCount - _validByteCount;
    }

    NSUInteger firstEmptyByteOffset = (_firstValidByteOffset + _validByteCount) % _bufferByteCount;
    NSUInteger bytesToCopy;
    if (firstEmptyByteOffset + emptyByteCount > _bufferByteCount) {
      bytesToCopy = MIN(length, _bufferByteCount - firstEmptyByteOffset);
    }
    else {
      bytesToCopy = MIN(length, emptyByteCount);
    }

    memcpy(_buffer + firstEmptyByteOffset, bytes, bytesToCopy);

    length -= bytesToCopy;
    bytes = (const uint8_t *)bytes + bytesToCopy;
    _validByteCount += bytesToCopy;

    pthread_mutex_unlock(&_mutex);
  }
}

- (void)stop
{
  [_analyzers makeObjectsPerformSelector:@selector(flush)];

  if (_graph == NULL) {
    return;
  }

  pthread_mutex_lock(&_mutex);
  if (_started) {
    pthread_mutex_unlock(&_mutex);
    AUGraphStop(_graph);
    pthread_mutex_lock(&_mutex);

    [self _setShouldInterceptTiming:YES];
    _started = NO;
  }
  pthread_mutex_unlock(&_mutex);
  pthread_cond_signal(&_cond);
}

- (void)flush
{
  [self flushShouldResetTiming:YES];
}

- (void)flushShouldResetTiming:(BOOL)shouldResetTiming
{
  [_analyzers makeObjectsPerformSelector:@selector(flush)];

  if (_graph == NULL) {
    return;
  }

  pthread_mutex_lock(&_mutex);

  _firstValidByteOffset = 0;
  _validByteCount = 0;
  if (shouldResetTiming) {
    [self _resetTiming];
  }

  pthread_mutex_unlock(&_mutex);
  pthread_cond_signal(&_cond);
}

+ (double)_absoluteTimeConversion
{
  static double conversion;

  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    conversion = 1.0e-9 * info.numer / info.denom;
  });

  return conversion;
}

- (void)_resetTiming
{
  _startedTime = 0;
  _interruptedTime = 0;
  _totalInterruptedInterval = 0;
}

- (NSUInteger)currentTime
{
  if (_startedTime == 0) {
    return 0;
  }

  double base = [[self class] _absoluteTimeConversion] * 1000.0;

  uint64_t interval;
  if (_interruptedTime == 0) {
    interval = mach_absolute_time() - _startedTime - _totalInterruptedInterval;
  }
  else {
    interval = _interruptedTime - _startedTime - _totalInterruptedInterval;
  }

  return base * interval;
}

- (void)setInterrupted:(BOOL)interrupted
{
  pthread_mutex_lock(&_mutex);
  _interrupted = interrupted;
  pthread_mutex_unlock(&_mutex);
}

- (double)volume
{
#if TARGET_OS_IPHONE
  return _volume;
#else /* TARGET_OS_IPHONE */
  if (_remoteIOUnit == NULL) {
    return 0.0;
  }

  AudioUnitParameterValue volume = 0.0;
  AudioUnitGetParameter(_remoteIOUnit, kHALOutputParam_Volume, kAudioUnitScope_Output, 1, &volume);

  return volume;
#endif /* TARGET_OS_IPHONE */
}

- (void)setVolume:(double)volume
{
#if TARGET_OS_IPHONE
  _volume = volume;
#else /* TARGET_OS_IPHONE */
  if (_remoteIOUnit == NULL) {
    return;
  }

  volume = fmin(fmax(volume, 0.0), 1.0);
  AudioUnitSetParameter(_remoteIOUnit, kHALOutputParam_Volume, kAudioUnitScope_Output, 1, volume, 0);
#endif /* TARGET_OS_IPHONE */
}

- (double)rate
{
    return _aUiPodTimeProxy.playbackRate;
}

- (void)setRate:(double)rate
{
    _aUiPodTimeProxy.playbackRate = rate;
}

- (void)printErrorMessage: (NSString *) errorString withStatus: (OSStatus) result {
    
    char resultString[5];
    UInt32 swappedResult = CFSwapInt32HostToBig (result);
    bcopy (&swappedResult, resultString, 4);
    resultString[4] = '\0';
    
    NSLog (
           @"*** %@ error: %d %08X %4.4s\n",
           errorString,
           (char*) &resultString
           );
}

@end
