//
//  DOUCacheInfo.h
//  DOUASDemo
//
//  Created by grant.zhou on 2018/10/11.
//  Copyright © 2018 Douban Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DOUAudioFile.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOUCacheInfo : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong) NSString* audioFileURL;
@property (nonatomic, strong) NSString *cacheWritePath;
@property (nonatomic, strong) NSString *cacheWriteTmpPath;
@property (nonatomic, assign) NSInteger expectedLength;
@property (nonatomic, strong) NSDictionary<NSNumber *,NSNumber *> *cachedSegment;
@property (nonatomic, readonly) NSUInteger receivedLength;

- (BOOL)isCacheCompleted;

- (BOOL)isCachedPosition:(NSUInteger)pos;

@end


@interface DOUCacheManager : NSObject

+ (instancetype)defaultManager;

-(DOUCacheInfo *)cacheInfo:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END
