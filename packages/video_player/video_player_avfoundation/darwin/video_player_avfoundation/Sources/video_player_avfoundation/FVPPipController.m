// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "./include/video_player_avfoundation/FVPPipController.h"

static void *pipPossibleContext = &pipPossibleContext;

@implementation FVPPipController {
  AVPictureInPictureController *_pipController;
  AVPlayerLayer *_playerLayer;
  BOOL _pendingStart;
  BOOL _observingPossible;
  BOOL _manualStart;
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
      [_pipController addObserver:self
                       forKeyPath:@"pictureInPicturePossible"
                          options:NSKeyValueObservingOptionNew
                          context:pipPossibleContext];
      _observingPossible = YES;
    }
#endif
  }
  return self;
}

- (void)dealloc {
  if (_observingPossible) {
    [_pipController removeObserver:self forKeyPath:@"pictureInPicturePossible" context:pipPossibleContext];
  }
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
    _manualStart = YES;
    if (_pipController.isPictureInPicturePossible) {
      [_pipController startPictureInPicture];
    } else {
      _pendingStart = YES;
    }
  }
#endif
}

- (void)stopPip {
#if TARGET_OS_IOS
  _pendingStart = NO;
  _manualStart = NO;
  if (_pipController && _pipController.isPictureInPictureActive) {
    [_pipController stopPictureInPicture];
  }
#endif
}

- (void)setCanStartAutomatically:(BOOL)canStart {
#if TARGET_OS_IOS
  if (@available(iOS 14.2, *)) {
    _pipController.canStartPictureInPictureAutomaticallyFromInline = canStart;
  }
#endif
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  if (context == pipPossibleContext) {
    if (_pendingStart && _pipController.isPictureInPicturePossible) {
      _pendingStart = NO;
      [_pipController startPictureInPicture];
    }
  }
}

#pragma mark - AVPictureInPictureControllerDelegate

- (void)pictureInPictureControllerWillStartPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController {
  // Will start
}

- (void)pictureInPictureControllerDidStartPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController {
#if TARGET_OS_IOS
  if (_manualStart) {
    _manualStart = NO;
    // Move the app to background so PiP floats over the home screen,
    // matching the Android PiP behavior.
    SEL suspendSel = NSSelectorFromString(@"suspend");
    if ([[UIApplication sharedApplication] respondsToSelector:suspendSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      [[UIApplication sharedApplication] performSelector:suspendSel];
#pragma clang diagnostic pop
    }
  }
#endif
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
  _manualStart = NO;
  [self.delegate pipControllerFailedToStartWithError:error];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:
        (void (^)(BOOL))completionHandler {
  completionHandler(YES);
}

@end
