// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FVPTextureBasedVideoPlayer.h"

#if TARGET_OS_OSX
@import FlutterMacOS;
#else
@import Flutter;
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FVPTextureBasedVideoPlayer ()
/// Called when the texture is unregistered.
/// This method is used to clean up resources associated with the texture.
- (void)onTextureUnregistered:(NSObject<FlutterTexture> *)texture;
@end

NS_ASSUME_NONNULL_END
