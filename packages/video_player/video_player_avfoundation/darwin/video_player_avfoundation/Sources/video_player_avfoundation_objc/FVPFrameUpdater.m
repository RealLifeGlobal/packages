// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "./include/video_player_avfoundation_objc/FVPFrameUpdater.h"

#if TARGET_OS_IOS
@import UIKit;
#endif

@implementation FVPFrameUpdater
- (FVPFrameUpdater *)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry {
  NSAssert(self, @"super init cannot be nil");
  if (self == nil) return nil;
  _registry = registry;
  return self;
}

- (void)displayLinkFired {
  // Don't message the engine once the owning player has been disposed; a display-link callback can
  // still be in flight or deferred at that point.
  if (_disposed) {
    return;
  }
#if TARGET_OS_IOS
  // Skip frame delivery while backgrounded. The texture has nothing visible to update, and on
  // "Designed for iPad" apps running on Apple Silicon Macs a display-link callback can be flushed
  // during app termination (the AppKit `-[NSApplication terminate:]` run-loop pump) into a
  // FlutterEngine that is already being torn down, causing an EXC_BAD_ACCESS in
  // `-[FlutterEngine textureFrameAvailable:]`. Checking the live application state here is robust to
  // the background lifecycle notification not being delivered, which is unreliable on this platform.
  if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
    return;
  }
#endif
  self.frameDuration = _displayLink.duration;
  [_registry textureFrameAvailable:_textureIdentifier];
}
@end
