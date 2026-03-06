// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "./include/video_player_avfoundation/FVPPipController.h"

@implementation FVPPipController {
  AVPictureInPictureController *_pipController;
  AVPlayerLayer *_playerLayer;
}

+ (BOOL)isPipSupported {
#if TARGET_OS_IOS
  if (@available(iOS 15.0, *)) {
    return [AVPictureInPictureController isPictureInPictureSupported];
  }
  return NO;
#elif TARGET_OS_OSX
  return NO;
#else
  return NO;
#endif
}

- (instancetype)initWithPlayerLayer:(AVPlayerLayer *)playerLayer {
  self = [super init];
  if (self) {
    _playerLayer = playerLayer;
#if TARGET_OS_IOS
    if ([AVPictureInPictureController isPictureInPictureSupported]) {
      _pipController = [[AVPictureInPictureController alloc] initWithPlayerLayer:playerLayer];
      _pipController.delegate = self;
    }
#endif
  }
  return self;
}

- (BOOL)isPipActive {
#if TARGET_OS_IOS
  return _pipController.isPictureInPictureActive;
#else
  return NO;
#endif
}

- (void)startPip {
#if TARGET_OS_IOS
  if (_pipController && !_pipController.isPictureInPictureActive) {
    [_pipController startPictureInPicture];
  }
#endif
}

- (void)stopPip {
#if TARGET_OS_IOS
  if (_pipController && _pipController.isPictureInPictureActive) {
    [_pipController stopPictureInPicture];
  }
#endif
}

#pragma mark - AVPictureInPictureControllerDelegate

- (void)pictureInPictureControllerWillStartPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController {
  // Will start
}

- (void)pictureInPictureControllerDidStartPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController {
  [self.delegate pipControllerDidStartPip];
}

- (void)pictureInPictureControllerWillStopPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController {
  // Will stop
}

- (void)pictureInPictureControllerDidStopPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController {
  [self.delegate pipControllerDidStopPip];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
    failedToStartPictureInPictureWithError:(NSError *)error {
  [self.delegate pipControllerFailedToStartWithError:error];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:
        (void (^)(BOOL))completionHandler {
  completionHandler(YES);
}

@end
