//
//  AUiPodTimeProxy.h
//  AudioQualityCheck
//
//  Created by YuArai on 2015/11/22.
//  Copyright © 2015年 tenifre. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AUiPodTimeProxy : NSObject {
    AudioUnit _aUiPodTimeUnit;
    Float32 _playbackRate;
    AudioUnitParameterID _paramId;
}

@property(atomic) Float32 playbackRate;

- (id)initWithAudioUnit:(AudioUnit)aUiPodTimeUnit;

@end
