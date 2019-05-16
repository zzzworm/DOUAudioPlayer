//
//  _DOUAudioAutoRecoverRemoteFileProvider.h
//  DOUAudioPlayerDemo
//
//  Created by grant.zhou on 2019/5/10.
//  Copyright © 2019 Douban Inc. All rights reserved.
//

#import "DOUAudioRemoteFileProvider.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct
{
    int watchdogPeriodSeconds;
    int inactivePeriodBeforeReconnectSeconds;
}
DOUAutoRecoveringOptions;

@interface _DOUAudioAutoRecoverRemoteFileProvider : _DOUAudioRemoteFileProvider

@end

NS_ASSUME_NONNULL_END
