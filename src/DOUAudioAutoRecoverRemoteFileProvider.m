//
//  _DOUAudioAutoRecoverRemoteFileProvider.m
//  DOUAudioPlayerDemo
//
//  Created by grant.zhou on 2019/5/10.
//  Copyright © 2019 Douban Inc. All rights reserved.
//

#import "DOUAudioAutoRecoverRemoteFileProvider.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>
#import "mach/mach_time.h"
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "DOUAudioFileProvider_Private.h"
#include <pthread.h>
#import "DOUCacheInfo.h"
#import "NSData+DOUMappedFile.h"
#import "DOUAudioRemoteFileProvider_Private.h"


#define DEFAULT_WATCHDOG_PERIOD_SECONDS (8)
#define DEFAULT_INACTIVE_PERIOD_BEFORE_RECONNECT_SECONDS (15)

#define DOUHTTPRequestMaxLength (15 * 1024 *1024)

#define DOU_DEFAULT_BUFFER_SIZE_REQUIRED_TO_START_PLAYING_AFTER_BUFFER_UNDERRUN (128*1024)


@interface _DOUAudioAutoRecoverRemoteFileProvider ()
{
    int serial;
    int waitSeconds;
    NSTimer* timeoutTimer;
    BOOL waitingForNetwork;
    uint64_t ticksWhenLastDataReceived;
    SCNetworkReachabilityRef reachabilityRef;
    DOUAutoRecoveringOptions options;
    BOOL _httpRequestFailed;
    SInt64 _requireOffset;
}

-(void) reachabilityChanged;

@end

static uint64_t GetTickCount(void)
{
    static mach_timebase_info_data_t sTimebaseInfo;
    uint64_t machTime = mach_absolute_time();
    
    if (sTimebaseInfo.denom == 0 )
    {
        (void) mach_timebase_info(&sTimebaseInfo);
    }
    
    uint64_t millis = ((machTime / 1000000) * sTimebaseInfo.numer) / sTimebaseInfo.denom;
    
    return millis;
}

static void PopulateOptionsWithDefault(DOUAutoRecoveringOptions* options)
{
    if (options->watchdogPeriodSeconds == 0)
    {
        options->watchdogPeriodSeconds = DEFAULT_WATCHDOG_PERIOD_SECONDS;
    }
    
    if (options->inactivePeriodBeforeReconnectSeconds == 0)
    {
        options->inactivePeriodBeforeReconnectSeconds = DEFAULT_INACTIVE_PERIOD_BEFORE_RECONNECT_SECONDS;
    }
}

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info)
{
    @autoreleasepool
    {
        _DOUAudioAutoRecoverRemoteFileProvider* dataSource = (__bridge _DOUAudioAutoRecoverRemoteFileProvider*)info;
        
        [dataSource reachabilityChanged];
    }
}

@implementation _DOUAudioAutoRecoverRemoteFileProvider


- (instancetype)_initWithAudioFile:(id <DOUAudioFile>)audioFile config:(DOUAudioStreamerConfig *)config
{
    self = [super _initWithAudioFile:audioFile config:config];
    if (self) {
        PopulateOptionsWithDefault(&self->options);
        NSString* hostname = audioFile.audioFileURL.host;
        if (hostname.length) {
            reachabilityRef = SCNetworkReachabilityCreateWithName(NULL, [hostname UTF8String]);
        }
        [self startObserver];
    }
    return self;
}
-(void) dealloc
{
    
    [self stopNotifier];
    [self destroyTimeoutTimer];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    if (reachabilityRef!= NULL)
    {
        CFRelease(reachabilityRef);
    }
}

-(void) startObserver
{
    [self startNotifierOnRunLoop:[NSRunLoop mainRunLoop]];
    
    if (timeoutTimer)
    {
        [timeoutTimer invalidate];
        timeoutTimer = nil;
    }
    
    ticksWhenLastDataReceived = GetTickCount();
    
    [self createTimeoutTimer:[NSRunLoop mainRunLoop]];

}

-(BOOL) startNotifierOnRunLoop:(NSRunLoop*)runLoop
{
    if (reachabilityRef) {
        SCNetworkReachabilityContext context = { 0, (__bridge void*)self, NULL, NULL, NULL };
        if (SCNetworkReachabilitySetCallback(reachabilityRef, ReachabilityCallback, &context)) {
            if(SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef, runLoop.getCFRunLoop, kCFRunLoopDefaultMode))
            {
                return YES;
            }
        }
    }
    return NO;
}

-(void) reachabilityChanged
{
    if (waitingForNetwork)
    {
        waitingForNetwork = NO;
        
        //NSLog(@"reachabilityChanged %lld/%lld", self.position, self.length);
        
        serial++;
        
        [self attemptReconnectWithSerial:@(serial)];
    }
}


- (void)_requestDidComplete
{
    
    if ([_request isFailed] ||
        !([_request statusCode] >= 200 && [_request statusCode] < 300)) {
        _httpRequestFailed = YES;
    }
    else {
        _httpRequestFailed = NO;
        pthread_mutex_lock(&_dataMutex);
        [_mappedData dou_synchronizeMappedFile];
        pthread_mutex_unlock(&_dataMutex);
        if (![self checkRequireRangeFullfilledAndRemoveFullfilled:YES]) {
            [self requesetNeededRange];
        }
        [self.cacheInfo writeToFile:[self.class _metaPathForAudioFileURL:self.audioFile.audioFileURL]];
    }
    [self handleRequestComplete];
}

- (void)_requestDidReceiveData:(NSData *)data
{
    serial++;
    waitSeconds = 1;
    ticksWhenLastDataReceived = GetTickCount();
    
    [super _requestDidReceiveData:data];
}


-(void) timeoutTimerTick:(NSTimer*)timer
{
    if (_httpRequestFailed)
    {
        if ([self hasGotNetworkConnection])
        {
            uint64_t currentTicks = GetTickCount();
            
            if (((currentTicks - ticksWhenLastDataReceived) / 1000) >= options.inactivePeriodBeforeReconnectSeconds)
            {
                serial++;
                
                NSLog(@"timeoutTimerTick %lld/%lu", _request.position, (unsigned long)_request.length);
                
                [self attemptReconnectWithSerial:@(serial)];
            }
        }
    }
}

-(void) createTimeoutTimer:(NSRunLoop *)runloop
{
    [self destroyTimeoutTimer];
    
    timeoutTimer = [NSTimer timerWithTimeInterval:options.watchdogPeriodSeconds target:self selector:@selector(timeoutTimerTick:) userInfo:@(serial) repeats:YES];
    
    [runloop addTimer:timeoutTimer forMode:NSRunLoopCommonModes];
}

-(void) destroyTimeoutTimer
{
    if (timeoutTimer)
    {
        [timeoutTimer invalidate];
        timeoutTimer = nil;
    }
}

-(void) stopNotifier
{
    if (reachabilityRef != NULL)
    {
        SCNetworkReachabilitySetCallback(reachabilityRef, NULL, NULL);
        SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef, [NSRunLoop.mainRunLoop getCFRunLoop], kCFRunLoopDefaultMode);
    }
}

-(BOOL) hasGotNetworkConnection
{
    SCNetworkReachabilityFlags flags;
    
    if (! reachabilityRef) return YES; // Assume reachability, if unknown
    
    if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags))
    {
        return ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    }
    
    return NO;
}

-(void) attemptReconnectWithSerial:(NSNumber*)serialIn
{
    if (serialIn.intValue != self->serial)
    {
        return;
    }
    
    NSLog(@"attemptReconnect %lld/%lu", _request.position, (unsigned long)_request.length);
    [_request start];
}

-(void) attemptReconnectWithTimer:(NSTimer*)timer
{
    [self attemptReconnectWithSerial:(NSNumber*)timer.userInfo];
}

- (void)requireOffset:(SInt64)offset
{
    NSRange range = [self.cacheInfo nextNeedCacheRangeWithStartOffset:(NSUInteger)offset];
    if (0 == range.length) {
        return;
    }
    if (_request && !_request.isFinished && range.location == _request.position + _request.receivedLength) {
        return;
    }
    _requireOffset = offset;
    [self cancelRequest];
    [self _createRequest:(SInt64)range.location length:DOUHTTPRequestMaxLength-range.location-offset];
    [_request start];
}

- (void)_createRequest
{
    [self _createRequest:0 length:DOUHTTPRequestMaxLength];
}

- (void)_createRequest:(SInt64)position length:(NSUInteger)length
{
    length = MIN(DOUHTTPRequestMaxLength,length);

    [super _createRequest:position length:length];
    ticksWhenLastDataReceived = GetTickCount();
}

- (BOOL)shouldInvokeDecoder
{
    BOOL shouldInvokeDecoder = _requireOffset >= _request.position ? _request.position + _request.receivedLength - _requireOffset > DOU_DEFAULT_BUFFER_SIZE_REQUIRED_TO_START_PLAYING_AFTER_BUFFER_UNDERRUN : _request.receivedLength > DOU_DEFAULT_BUFFER_SIZE_REQUIRED_TO_START_PLAYING_AFTER_BUFFER_UNDERRUN;
    return shouldInvokeDecoder;
}

- (void)_invokeEventBlock
{
    _requireOffset = 0;
    [super _invokeEventBlock];
}
@end
