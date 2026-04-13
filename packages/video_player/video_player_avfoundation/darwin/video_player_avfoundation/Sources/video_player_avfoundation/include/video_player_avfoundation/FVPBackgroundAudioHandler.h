// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import AVFoundation;

#if TARGET_OS_OSX
@import FlutterMacOS;
#else
@import Flutter;
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FVPBackgroundAudioHandler : NSObject
@property(nonatomic, readonly) BOOL isEnabled;

- (instancetype)initWithPlayer:(AVPlayer *)player;
- (void)enableWithTitle:(nullable NSString *)title
                 artist:(nullable NSString *)artist
             artworkUrl:(nullable NSString *)artworkUrl
             durationMs:(nullable NSNumber *)durationMs;
- (void)disable;
- (void)updateNowPlayingInfo;
@end

NS_ASSUME_NONNULL_END
