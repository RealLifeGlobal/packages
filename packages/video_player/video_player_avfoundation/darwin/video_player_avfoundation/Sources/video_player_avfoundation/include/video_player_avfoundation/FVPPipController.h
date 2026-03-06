// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import AVFoundation;
@import AVKit;

#if TARGET_OS_OSX
@import FlutterMacOS;
#else
@import Flutter;
#endif

NS_ASSUME_NONNULL_BEGIN

@protocol FVPPipControllerDelegate <NSObject>
- (void)pipControllerDidStartPip;
- (void)pipControllerDidStopPip;
- (void)pipControllerFailedToStartWithError:(NSError *)error;
@end

@interface FVPPipController : NSObject <AVPictureInPictureControllerDelegate>
@property(nonatomic, weak, nullable) id<FVPPipControllerDelegate> delegate;
@property(nonatomic, readonly) BOOL isPipActive;

+ (BOOL)isPipSupported;
- (instancetype)initWithPlayerLayer:(AVPlayerLayer *)playerLayer;
- (void)startPip;
- (void)stopPip;
@end

NS_ASSUME_NONNULL_END
