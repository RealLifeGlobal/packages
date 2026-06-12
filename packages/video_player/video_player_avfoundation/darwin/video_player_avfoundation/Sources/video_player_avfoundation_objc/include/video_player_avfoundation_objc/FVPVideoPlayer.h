// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import AVFoundation;

#import "./VideoPlayerInstanceMessages.g.h"
#import "FVPAVFactory.h"
#import "FVPVideoEventListener.h"
#import "FVPViewProvider.h"

#if TARGET_OS_OSX
@import FlutterMacOS;
#else
@import Flutter;
#endif

#import "FVPPipController.h"

@class FVPBackgroundAudioHandler;

NS_ASSUME_NONNULL_BEGIN

/// FVPVideoPlayer manages video playback using AVPlayer.
/// It provides methods for controlling playback, adjusting volume, and handling seeking.
/// This class contains all functionalities needed to manage video playback in platform views and is
/// typically used alongside NativeVideoViewFactory. If you need to display a video using a
/// texture, use FVPTextureBasedVideoPlayer instead.
@interface FVPVideoPlayer : NSObject <FVPVideoPlayerInstanceApi, FVPPipControllerDelegate>
/// The AVPlayer instance used for video playback.
@property(nonatomic, readonly) AVPlayer *player;
/// Indicates whether the video player has been disposed.
@property(nonatomic, readonly) BOOL disposed;
/// Indicates whether the video player is set to loop.
@property(nonatomic) BOOL isLooping;
/// The current playback position of the video, in milliseconds.
@property(nonatomic, readonly) int64_t position;
/// The event listener to report video events to.
@property(nonatomic, nullable) NSObject<FVPVideoEventListener> *eventListener;
/// A block that will be called when dispose is called.
@property(nonatomic, nullable, copy) void (^onDisposed)(void);
/// The PiP controller for Picture-in-Picture support.
@property(nonatomic, strong, nullable) FVPPipController *pipController;
/// The background audio handler for background playback support.
@property(nonatomic, strong, nullable) FVPBackgroundAudioHandler *backgroundAudioHandler;
/// The AVPlayerLayer used for rendering and PiP support. Created lazily on first access.
@property(nonatomic, strong, readonly) AVPlayerLayer *playerLayer;

/// Initializes a new instance of FVPVideoPlayer with the given AVPlayerItem, AV factory, and view
/// provider.
- (instancetype)initWithPlayerItem:(NSObject<FVPAVPlayerItem> *)item
                         avFactory:(id<FVPAVFactory>)avFactory
                      viewProvider:(NSObject<FVPViewProvider> *)viewProvider;

/// Starts Picture-in-Picture for this player, lazily creating the PiP controller if needed.
- (void)enterPip;
/// Stops Picture-in-Picture for this player, if active.
- (void)exitPip;
/// Whether Picture-in-Picture is currently active for this player.
- (BOOL)isPipActive;
/// Enables or disables automatic Picture-in-Picture when the app is backgrounded.
- (void)setAutoPipEnabled:(BOOL)enabled;

/// Enables background playback for this player, configuring the lock-screen / Control Center
/// now-playing info and remote commands.
- (void)enableBackgroundPlaybackWithTitle:(nullable NSString *)title
                                   artist:(nullable NSString *)artist
                               artworkUrl:(nullable NSString *)artworkUrl
                               durationMs:(nullable NSNumber *)durationMs
                   skipBackwardIntervalMs:(nullable NSNumber *)skipBackwardIntervalMs
                    skipForwardIntervalMs:(nullable NSNumber *)skipForwardIntervalMs;
/// Disables background playback for this player.
- (void)disableBackgroundPlayback;

@end

NS_ASSUME_NONNULL_END
