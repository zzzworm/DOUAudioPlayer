//
//  AUiPodTimeProxy.m
//  AudioQualityCheck
//
//  Created by YuArai on 2015/11/22.
//  Copyright © 2015年 tenifre. All rights reserved.
//

#import "AUiPodTimeProxy.h"

@implementation AUiPodTimeProxy

@synthesize playbackRate = _playbackRate;

- (id)initWithAudioUnit:(AudioUnit)aUiPodTimeUnit
{
    self = [super init];
    if (self) {
        _aUiPodTimeUnit = aUiPodTimeUnit;
        _playbackRate = self.playbackRate;
        
        UInt32 size = sizeof(UInt32);
        AudioUnitGetPropertyInfo(_aUiPodTimeUnit,
                                 kAudioUnitProperty_ParameterList,
                                 kAudioUnitScope_Global,
                                 0,
                                 &size,
                                 NULL);
        
        int numOfParams = size / sizeof(AudioUnitParameterID);
        AudioUnitParameterID paramList[numOfParams];
        
        AudioUnitGetProperty(_aUiPodTimeUnit,
                             kAudioUnitProperty_ParameterList,
                             kAudioUnitScope_Global,
                             0,
                             paramList,
                             &size);
        
        for (int i = 0; i < numOfParams; i++) {
            _paramId = paramList[i];
            
            AudioUnitParameterInfo paramInfo;
            size = sizeof(paramInfo);
            AudioUnitGetProperty(_aUiPodTimeUnit,
                                 kAudioUnitProperty_ParameterInfo,
                                 kAudioUnitScope_Global,
                                 paramList[i],
                                 &paramInfo,
                                 &size);
            
            AudioUnitSetParameter(_aUiPodTimeUnit,
                                  paramList[i],
                                  kAudioUnitScope_Global,
                                  kVarispeedParam_PlaybackRate,
                                  _playbackRate,
                                  0);
        }
    }
    return self;
}

- (Float32)playbackRate
{
    Float32 value = 0.0f;
    OSStatus ret = AudioUnitGetParameter(_aUiPodTimeUnit,
                                         _paramId,
                                         kAudioUnitScope_Global,
                                         0,
                                         &value);
    if (ret != noErr) {
        NSLog(@"Error getting parameter(%d)", ret);
    }
    return value;
}

- (void)setPlaybackRate:(Float32)value
{
    // AUiPodTimeOther の場合
    AudioUnitParameterID parameter = 0;
    
    OSStatus ret = AudioUnitSetParameter(_aUiPodTimeUnit,
                                         parameter,
                                         kAudioUnitScope_Global,
                                         kVarispeedParam_PlaybackRate,
                                         value,
                                         0);
    if (ret != noErr) {
        NSLog(@"Error setting parameter(%f)", value);
    }
}

@end
