// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "./include/video_player_avfoundation/FVPVideoPlayer.h"
#import "./include/video_player_avfoundation/FVPVideoPlayer_Internal.h"

#import <GLKit/GLKit.h>

#import "./include/video_player_avfoundation/AVAssetTrackUtils.h"
#import "./include/video_player_avfoundation/FVPBackgroundAudioHandler.h"
#import "./include/video_player_avfoundation/FVPPipController.h"

static void *timeRangeContext = &timeRangeContext;
static void *statusContext = &statusContext;
static void *playbackLikelyToKeepUpContext = &playbackLikelyToKeepUpContext;
static void *rateContext = &rateContext;

/// Registers KVO observers on 'object' for each entry in 'observations', which must be a
/// dictionary mapping KVO keys to NSValue-wrapped context pointers.
///
/// This does not call any methods on 'observer', so is safe to call from 'observer's init.
static void FVPRegisterKeyValueObservers(NSObject *observer,
                                         NSDictionary<NSString *, NSValue *> *observations,
                                         NSObject *target) {
  // It is important not to use NSKeyValueObservingOptionInitial here, because that will cause
  // synchronous calls to 'observer', violating the requirement that this method does not call its
  // methods. If there are use cases for specific pieces of initial state, those should be handled
  // explicitly by the caller, rather than by adding initial-state KVO notifications here.
  for (NSString *key in observations) {
    [target addObserver:observer
             forKeyPath:key
                options:NSKeyValueObservingOptionNew
                context:observations[key].pointerValue];
  }
}

/// Registers KVO observers on 'object' for each entry in 'observations', which must be a
/// dictionary mapping KVO keys to NSValue-wrapped context pointers.
///
/// This should only be called to balance calls to FVPRegisterKeyValueObservers, as it is an
/// error to try to remove observers that are not currently set.
///
/// This does not call any methods on 'observer', so is safe to call from 'observer's dealloc.
static void FVPRemoveKeyValueObservers(NSObject *observer,
                                       NSDictionary<NSString *, NSValue *> *observations,
                                       NSObject *target) {
  for (NSString *key in observations) {
    [target removeObserver:observer forKeyPath:key];
  }
}

/// Returns a mapping of KVO keys to NSValue-wrapped observer context pointers for observations that
/// should be set for AVPlayer instances.
static NSDictionary<NSString *, NSValue *> *FVPGetPlayerObservations(void) {
  return @{
    @"rate" : [NSValue valueWithPointer:rateContext],
  };
}

/// Returns a mapping of KVO keys to NSValue-wrapped observer context pointers for observations that
/// should be set for AVPlayerItem instances.
static NSDictionary<NSString *, NSValue *> *FVPGetPlayerItemObservations(void) {
  return @{
    @"loadedTimeRanges" : [NSValue valueWithPointer:timeRangeContext],
    @"status" : [NSValue valueWithPointer:statusContext],
    @"playbackLikelyToKeepUp" : [NSValue valueWithPointer:playbackLikelyToKeepUpContext],
  };
}

@implementation FVPVideoPlayer {
  // Whether or not player and player item listeners have ever been registered.
  BOOL _listenersRegistered;
  // The last known indicated bitrate from the access log, used to detect ABR quality changes.
  double _lastIndicatedBitrate;
}

@synthesize playerLayer = _playerLayer;

// Lazily create the player layer only when PiP support is actually needed.
- (AVPlayerLayer *)playerLayer {
  if (!_playerLayer) {
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
  }
  return _playerLayer;
}

- (instancetype)initWithPlayerItem:(NSObject<FVPAVPlayerItem> *)item
                         avFactory:(id<FVPAVFactory>)avFactory
                      viewProvider:(NSObject<FVPViewProvider> *)viewProvider {
  self = [super init];
  NSAssert(self, @"super init cannot be nil");

  _viewProvider = viewProvider;

  NSObject<FVPAVAsset> *asset = item.asset;
  void (^assetCompletionHandler)(void) = ^{
    if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
      void (^processVideoTracks)(NSArray<AVAssetTrack *> *) = ^(NSArray<AVAssetTrack *> *tracks) {
        if ([tracks count] > 0) {
          AVAssetTrack *videoTrack = tracks[0];
          void (^trackCompletionHandler)(void) = ^{
            if (self->_disposed) return;
            if ([videoTrack statusOfValueForKey:@"preferredTransform"
                                          error:nil] == AVKeyValueStatusLoaded) {
              // Rotate the video by using a videoComposition and the preferredTransform
              self->_preferredTransform = FVPGetStandardizedTrackTransform(
                  videoTrack.preferredTransform, videoTrack.naturalSize);
              // Do not use video composition when it is not needed.
              if (CGAffineTransformIsIdentity(self->_preferredTransform)) {
                return;
              }
              // Note:
              // https://developer.apple.com/documentation/avfoundation/avplayeritem/1388818-videocomposition
              // Video composition can only be used with file-based media and is not supported for
              // use with media served using HTTP Live Streaming.
              AVMutableVideoComposition *videoComposition =
                  [self videoCompositionWithTransform:self->_preferredTransform
                                                asset:asset
                                           videoTrack:videoTrack];
              item.videoComposition = videoComposition;
            }
          };
          [videoTrack loadValuesAsynchronouslyForKeys:@[ @"preferredTransform" ]
                                    completionHandler:trackCompletionHandler];
        }
      };

      // Use the new async API on iOS 15.0+/macOS 12.0+, fall back to deprecated API on older
      // versions
      if (@available(iOS 15.0, macOS 12.0, *)) {
        [asset loadTracksWithMediaType:AVMediaTypeVideo
                     completionHandler:^(NSArray<AVAssetTrack *> *_Nullable tracks,
                                         NSError *_Nullable error) {
                       if (error == nil && tracks != nil) {
                         processVideoTracks(tracks);
                       } else if (error != nil) {
                         NSLog(@"Error loading tracks: %@", error);
                       }
                     }];
      } else {
        // For older OS versions, use the deprecated API with warning suppression
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
#pragma clang diagnostic pop
        processVideoTracks(tracks);
      }
    }
  };

  _player = [avFactory playerWithPlayerItem:item];
  _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

  // Configure output.
  NSDictionary *pixBuffAttributes = @{
    (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
  };
  _pixelBufferSource = [avFactory videoOutputWithPixelBufferAttributes:pixBuffAttributes];

  [asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ] completionHandler:assetCompletionHandler];

  return self;
}

- (void)dealloc {
  if (_listenersRegistered && !_disposed) {
    // If dispose was never called for some reason, remove observers to prevent crashes.
    FVPRemoveKeyValueObservers(self, FVPGetPlayerItemObservations(), _player.currentItem);
    FVPRemoveKeyValueObservers(self, FVPGetPlayerObservations(), _player);
  }
}

- (void)disposeWithError:(FlutterError *_Nullable *_Nonnull)error {
  // In some hot restart scenarios, dispose can be called twice, so no-op after the first time.
  if (_disposed) {
    return;
  }
  _disposed = YES;

  if (_listenersRegistered) {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    FVPRemoveKeyValueObservers(self, FVPGetPlayerItemObservations(), self.player.currentItem);
    FVPRemoveKeyValueObservers(self, FVPGetPlayerObservations(), self.player);
  }

  // Clean up PiP controller.
  if (_pipController) {
    [_pipController stopPip];
    _pipController = nil;
  }

  // Clean up background audio handler.
  if (_backgroundAudioHandler) {
    [_backgroundAudioHandler disable];
    _backgroundAudioHandler = nil;
  }

  [self.player replaceCurrentItemWithPlayerItem:nil];

  if (_onDisposed) {
    _onDisposed();
  }
  [self.eventListener videoPlayerWasDisposed];
}

- (void)setEventListener:(NSObject<FVPVideoEventListener> *)eventListener {
  _eventListener = eventListener;
  // The first time an event listener is set, set up video event listeners to relay status changes
  // changes to the event listener.
  if (eventListener && !_listenersRegistered) {
    AVPlayerItem *item = self.player.currentItem;
    // If the item is already ready to play, ensure that the intialized event is sent first.
    [self reportStatusForPlayerItem:item];
    // Set up all necessary observers to report video events.
    FVPRegisterKeyValueObservers(self, FVPGetPlayerItemObservations(), item);
    FVPRegisterKeyValueObservers(self, FVPGetPlayerObservations(), _player);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemDidPlayToEndTime:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accessLogEntryAdded:)
                                                 name:AVPlayerItemNewAccessLogEntryNotification
                                               object:item];
    _listenersRegistered = YES;
  }
}

- (void)itemDidPlayToEndTime:(NSNotification *)notification {
  if (_isLooping) {
    AVPlayerItem *p = [notification object];
    [p seekToTime:kCMTimeZero completionHandler:nil];
  } else {
    [self.eventListener videoPlayerDidComplete];
  }
}

- (void)accessLogEntryAdded:(NSNotification *)notification {
  AVPlayerItem *item = (AVPlayerItem *)notification.object;
  AVPlayerItemAccessLog *accessLog = item.accessLog;
  NSArray<AVPlayerItemAccessLogEvent *> *events = accessLog.events;
  AVPlayerItemAccessLogEvent *lastEvent = events.lastObject;

  NSLog(@"[ABR] accessLogEntryAdded: totalEntries=%lu lastEvent=%@",
        (unsigned long)events.count, lastEvent ? @"present" : @"nil");

  if (!lastEvent) {
    return;
  }

  double indicatedBitrate = lastEvent.indicatedBitrate;
  double observedBitrate = lastEvent.observedBitrate;
  NSLog(@"[ABR] indicatedBitrate=%.0f observedBitrate=%.0f lastIndicatedBitrate=%.0f "
        @"switchBitrate=%.0f",
        indicatedBitrate, observedBitrate, _lastIndicatedBitrate,
        lastEvent.switchBitrate);

  // Only emit event when the bitrate actually changes (ABR switch).
  if (indicatedBitrate > 0 && indicatedBitrate != _lastIndicatedBitrate) {
    _lastIndicatedBitrate = indicatedBitrate;

    // Look up the variant resolution by matching indicatedBitrate to asset variants.
    // presentationSize is the render/display size and may not match the variant resolution.
    NSInteger width = 0;
    NSInteger height = 0;
    if (@available(iOS 15.0, macOS 12.0, *)) {
      AVURLAsset *urlAsset = (AVURLAsset *)item.asset;
      if ([urlAsset isKindOfClass:[AVURLAsset class]]) {
        double closestDelta = INFINITY;
        for (AVAssetVariant *variant in urlAsset.variants) {
          if (variant.videoAttributes) {
            double delta = fabs(variant.peakBitRate - indicatedBitrate);
            if (delta < closestDelta) {
              closestDelta = delta;
              CGSize res = variant.videoAttributes.presentationSize;
              width = (NSInteger)res.width;
              height = (NSInteger)res.height;
            }
          }
        }
      }
    }
    // Fallback to presentationSize if variant lookup didn't find a match.
    if (width == 0 || height == 0) {
      width = (NSInteger)item.presentationSize.width;
      height = (NSInteger)item.presentationSize.height;
    }

    NSLog(@"[ABR] Dispatching quality event: %ldx%ld @ %.0f bps",
          (long)width, (long)height, indicatedBitrate);
    [self.eventListener videoPlayerDidChangeQualityWithWidth:width
                                                     height:height
                                                    bitrate:(NSInteger)indicatedBitrate];
  } else {
    NSLog(@"[ABR] Skipped: indicatedBitrate=%.0f (same as last or <= 0)", indicatedBitrate);
  }
}

const int64_t TIME_UNSET = -9223372036854775807;

NS_INLINE int64_t FVPCMTimeToMillis(CMTime time) {
  // When CMTIME_IS_INDEFINITE return a value that matches TIME_UNSET from ExoPlayer2 on Android.
  // Fixes https://github.com/flutter/flutter/issues/48670
  if (CMTIME_IS_INDEFINITE(time)) return TIME_UNSET;
  if (time.timescale == 0) return 0;
  return time.value * 1000 / time.timescale;
}

NS_INLINE CGFloat radiansToDegrees(CGFloat radians) {
  // Input range [-pi, pi] or [-180, 180]
  CGFloat degrees = GLKMathRadiansToDegrees((float)radians);
  if (degrees < 0) {
    // Convert -90 to 270 and -180 to 180
    return degrees + 360;
  }
  // Output degrees in between [0, 360]
  return degrees;
};

- (AVMutableVideoComposition *)videoCompositionWithTransform:(CGAffineTransform)transform
                                                       asset:(NSObject<FVPAVAsset> *)asset
                                                  videoTrack:(AVAssetTrack *)videoTrack {
  AVMutableVideoCompositionInstruction *instruction =
      [AVMutableVideoCompositionInstruction videoCompositionInstruction];
  instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
  AVMutableVideoCompositionLayerInstruction *layerInstruction =
      [AVMutableVideoCompositionLayerInstruction
          videoCompositionLayerInstructionWithAssetTrack:videoTrack];
  [layerInstruction setTransform:_preferredTransform atTime:kCMTimeZero];

  AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
  instruction.layerInstructions = @[ layerInstruction ];
  videoComposition.instructions = @[ instruction ];

  // If in portrait mode, switch the width and height of the video
  CGFloat width = videoTrack.naturalSize.width;
  CGFloat height = videoTrack.naturalSize.height;
  NSInteger rotationDegrees =
      (NSInteger)round(radiansToDegrees(atan2(_preferredTransform.b, _preferredTransform.a)));
  if (rotationDegrees == 90 || rotationDegrees == 270) {
    width = videoTrack.naturalSize.height;
    height = videoTrack.naturalSize.width;
  }
  videoComposition.renderSize = CGSizeMake(width, height);

  videoComposition.sourceTrackIDForFrameTiming = videoTrack.trackID;
  if (CMTIME_IS_VALID(videoTrack.minFrameDuration)) {
    videoComposition.frameDuration = videoTrack.minFrameDuration;
  } else {
    NSLog(@"Warning: videoTrack.minFrameDuration for input video is invalid, please report this to "
          @"https://github.com/flutter/flutter/issues with input video attached.");
    videoComposition.frameDuration = CMTimeMake(1, 30);
  }

  return videoComposition;
}

- (void)observeValueForKeyPath:(NSString *)path
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (context == timeRangeContext) {
    NSMutableArray<NSArray<NSNumber *> *> *values = [[NSMutableArray alloc] init];
    for (NSValue *rangeValue in [object loadedTimeRanges]) {
      CMTimeRange range = [rangeValue CMTimeRangeValue];
      [values addObject:@[
        @(FVPCMTimeToMillis(range.start)),
        @(FVPCMTimeToMillis(range.duration)),
      ]];
    }
    [self.eventListener videoPlayerDidUpdateBufferRegions:values];
  } else if (context == statusContext) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    [self reportStatusForPlayerItem:item];
  } else if (context == playbackLikelyToKeepUpContext) {
    [self updatePlayingState];
    if ([[_player currentItem] isPlaybackLikelyToKeepUp]) {
      [self.eventListener videoPlayerDidEndBuffering];
    } else {
      [self.eventListener videoPlayerDidStartBuffering];
    }
  } else if (context == rateContext) {
    // Important: Make sure to cast the object to AVPlayer when observing the rate property,
    // as it is not available in AVPlayerItem.
    AVPlayer *player = (AVPlayer *)object;
    [self.eventListener videoPlayerDidSetPlaying:(player.rate > 0)];
  }
}

- (void)reportStatusForPlayerItem:(AVPlayerItem *)item {
  NSAssert(self.eventListener,
           @"reportStatusForPlayerItem was called when the event listener was not set.");
  switch (item.status) {
    case AVPlayerItemStatusFailed:
      [self sendFailedToLoadVideoEvent];
      break;
    case AVPlayerItemStatusUnknown:
      break;
    case AVPlayerItemStatusReadyToPlay:
      if (!_isInitialized) {
        [item addOutput:self.pixelBufferSource.videoOutput];
        [self reportInitialized];
        [self updatePlayingState];
      }
      break;
  }
}

- (void)updatePlayingState {
  if (!_isInitialized) {
    return;
  }
  if (_isPlaying) {
    // Calling play is the same as setting the rate to 1.0 (or to defaultRate depending on iOS
    // version) so last set playback speed must be set here if any instead.
    // https://github.com/flutter/flutter/issues/71264
    // https://github.com/flutter/flutter/issues/73643
    if (_targetPlaybackSpeed) {
      [self updateRate];
    } else {
      [_player play];
    }
  } else {
    [_player pause];
  }
}

/// Synchronizes the player's playback rate with targetPlaybackSpeed, constrained by the playback
/// rate capabilities of the player's current item.
- (void)updateRate {
  // See https://developer.apple.com/library/archive/qa/qa1772/_index.html for an explanation of
  // these checks.
  // If status is not AVPlayerItemStatusReadyToPlay then both canPlayFastForward
  // and canPlaySlowForward are always false and it is unknown whether video can
  // be played at these speeds, updatePlayingState will be called again when
  // status changes to AVPlayerItemStatusReadyToPlay.
  float speed = _targetPlaybackSpeed.floatValue;
  BOOL readyToPlay = _player.currentItem.status == AVPlayerItemStatusReadyToPlay;
  if (speed > 2.0 && !_player.currentItem.canPlayFastForward) {
    if (!readyToPlay) {
      return;
    }
    speed = 2.0;
  }
  if (speed < 1.0 && !_player.currentItem.canPlaySlowForward) {
    if (!readyToPlay) {
      return;
    }
    speed = 1.0;
  }
  _player.rate = speed;
}

- (void)sendFailedToLoadVideoEvent {
  // Prefer more detailed error information from tracks loading.
  NSError *error;
  if ([self.player.currentItem.asset statusOfValueForKey:@"tracks"
                                                   error:&error] != AVKeyValueStatusFailed) {
    error = self.player.currentItem.error;
  }
  __block NSMutableOrderedSet<NSString *> *details =
      [NSMutableOrderedSet orderedSetWithObject:@"Failed to load video"];
  void (^add)(NSString *) = ^(NSString *detail) {
    if (detail != nil) {
      [details addObject:detail];
    }
  };
  NSError *underlyingError = error.userInfo[NSUnderlyingErrorKey];
  add(error.localizedDescription);
  add(error.localizedFailureReason);
  add(underlyingError.localizedDescription);
  add(underlyingError.localizedFailureReason);
  NSString *message = [details.array componentsJoinedByString:@": "];
  [self.eventListener videoPlayerDidErrorWithMessage:message];
}

- (void)reportInitialized {
  AVPlayerItem *currentItem = self.player.currentItem;
  NSAssert(currentItem.status == AVPlayerItemStatusReadyToPlay,
           @"reportInitializedIfReadyToPlay was called when the item wasn't ready to play.");
  NSAssert(!_isInitialized, @"reportInitializedIfReadyToPlay should only be called once.");

  _isInitialized = YES;
  [self.eventListener videoPlayerDidInitializeWithDuration:self.duration
                                                      size:currentItem.presentationSize];
}

#pragma mark - FVPVideoPlayerInstanceApi

- (void)playWithError:(FlutterError *_Nullable *_Nonnull)error {
  _isPlaying = YES;
  [self updatePlayingState];
}

- (void)pauseWithError:(FlutterError *_Nullable *_Nonnull)error {
  _isPlaying = NO;
  [self updatePlayingState];
}

- (nullable NSNumber *)position:(FlutterError *_Nullable *_Nonnull)error {
  return @(FVPCMTimeToMillis([_player currentTime]));
}

- (void)seekTo:(NSInteger)position completion:(void (^)(FlutterError *_Nullable))completion {
  CMTime targetCMTime = CMTimeMake(position, 1000);
  CMTimeValue duration = _player.currentItem.asset.duration.value;
  // Without adding tolerance when seeking to duration,
  // seekToTime will never complete, and this call will hang.
  // see issue https://github.com/flutter/flutter/issues/124475.
  CMTime tolerance = position == duration ? CMTimeMake(1, 1000) : kCMTimeZero;
  [_player seekToTime:targetCMTime
        toleranceBefore:tolerance
         toleranceAfter:tolerance
      completionHandler:^(BOOL completed) {
        if (completion) {
          dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
          });
        }
      }];
}

- (void)setLooping:(BOOL)looping error:(FlutterError *_Nullable *_Nonnull)error {
  _isLooping = looping;
}

- (void)setVolume:(double)volume error:(FlutterError *_Nullable *_Nonnull)error {
  _player.volume = (float)((volume < 0.0) ? 0.0 : ((volume > 1.0) ? 1.0 : volume));
}

- (void)setPlaybackSpeed:(double)speed error:(FlutterError *_Nullable *_Nonnull)error {
  _targetPlaybackSpeed = @(speed);
  [self updatePlayingState];
}

- (nullable NSArray<FVPMediaSelectionAudioTrackData *> *)getAudioTracks:
    (FlutterError *_Nullable *_Nonnull)error {
  AVPlayerItem *currentItem = _player.currentItem;
  NSAssert(currentItem, @"currentItem should not be nil");
  AVAsset *asset = currentItem.asset;

  // Get tracks from media selection (for HLS streams)
  AVMediaSelectionGroup *audioGroup =
      [asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];

  NSMutableArray<FVPMediaSelectionAudioTrackData *> *mediaSelectionTracks =
      [[NSMutableArray alloc] init];

  if (audioGroup.options.count > 0) {
    AVMediaSelection *mediaSelection = currentItem.currentMediaSelection;
    AVMediaSelectionOption *currentSelection =
        [mediaSelection selectedMediaOptionInMediaSelectionGroup:audioGroup];

    for (NSInteger i = 0; i < audioGroup.options.count; i++) {
      AVMediaSelectionOption *option = audioGroup.options[i];
      NSString *displayName = option.displayName;

      NSString *languageCode = nil;
      if (option.locale) {
        languageCode = option.locale.languageCode;
      }

      NSArray<AVMetadataItem *> *titleItems =
          [AVMetadataItem metadataItemsFromArray:option.commonMetadata
                                         withKey:AVMetadataCommonKeyTitle
                                        keySpace:AVMetadataKeySpaceCommon];
      NSString *commonMetadataTitle = titleItems.firstObject.stringValue;

      BOOL isSelected = [currentSelection isEqual:option];

      FVPMediaSelectionAudioTrackData *trackData =
          [FVPMediaSelectionAudioTrackData makeWithIndex:i
                                             displayName:displayName
                                            languageCode:languageCode
                                              isSelected:isSelected
                                     commonMetadataTitle:commonMetadataTitle];

      [mediaSelectionTracks addObject:trackData];
    }
  }

  return mediaSelectionTracks;
}

- (void)selectAudioTrackAtIndex:(NSInteger)trackIndex
                          error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  AVPlayerItem *currentItem = _player.currentItem;
  NSAssert(currentItem, @"currentItem should not be nil");
  AVAsset *asset = currentItem.asset;

  AVMediaSelectionGroup *audioGroup =
      [asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];

  if (audioGroup && trackIndex >= 0 && trackIndex < (NSInteger)audioGroup.options.count) {
    AVMediaSelectionOption *option = audioGroup.options[trackIndex];
    [currentItem selectMediaOption:option inMediaSelectionGroup:audioGroup];
  }
}

#pragma mark - ABR (Adaptive Bitrate) Control

- (nullable NSArray<FVPPlatformVideoQuality *> *)getAvailableQualities:
    (FlutterError *_Nullable *_Nonnull)error {
  NSMutableArray<FVPPlatformVideoQuality *> *qualities = [[NSMutableArray alloc] init];

  if (@available(iOS 15.0, macOS 12.0, *)) {
    AVURLAsset *urlAsset = (AVURLAsset *)_player.currentItem.asset;
    if ([urlAsset isKindOfClass:[AVURLAsset class]] &&
        [urlAsset respondsToSelector:@selector(variants)]) {
      NSArray<AVAssetVariant *> *variants = urlAsset.variants;
      for (AVAssetVariant *variant in variants) {
        // Only include variants with video attributes.
        if (variant.videoAttributes) {
          CGSize resolution = variant.videoAttributes.presentationSize;
          double peakBitRate = variant.peakBitRate;
          FVPPlatformVideoQuality *quality = [FVPPlatformVideoQuality
              makeWithWidth:(NSInteger)resolution.width
                     height:(NSInteger)resolution.height
                    bitrate:(NSInteger)peakBitRate
                      codec:nil
                 isSelected:NO];
          [qualities addObject:quality];
        }
      }
    }
  }
  // On older iOS, return empty list — no API to enumerate HLS variants.
  return qualities;
}

- (nullable FVPPlatformVideoQuality *)getCurrentQuality:
    (FlutterError *_Nullable *_Nonnull)error {
  AVPlayerItemAccessLog *accessLog = _player.currentItem.accessLog;
  AVPlayerItemAccessLogEvent *lastEvent = accessLog.events.lastObject;
  if (!lastEvent) {
    return nil;
  }

  double bitrate = lastEvent.indicatedBitrate;
  NSInteger width = 0;
  NSInteger height = 0;

  // Look up the variant resolution by matching indicatedBitrate.
  if (@available(iOS 15.0, macOS 12.0, *)) {
    AVURLAsset *urlAsset = (AVURLAsset *)_player.currentItem.asset;
    if ([urlAsset isKindOfClass:[AVURLAsset class]]) {
      double closestDelta = INFINITY;
      for (AVAssetVariant *variant in urlAsset.variants) {
        if (variant.videoAttributes) {
          double delta = fabs(variant.peakBitRate - bitrate);
          if (delta < closestDelta) {
            closestDelta = delta;
            CGSize res = variant.videoAttributes.presentationSize;
            width = (NSInteger)res.width;
            height = (NSInteger)res.height;
          }
        }
      }
    }
  }
  if (width == 0 || height == 0) {
    width = (NSInteger)_player.currentItem.presentationSize.width;
    height = (NSInteger)_player.currentItem.presentationSize.height;
  }

  FVPPlatformVideoQuality *quality = [FVPPlatformVideoQuality makeWithWidth:width
                                                                     height:height
                                                                    bitrate:(NSInteger)bitrate
                                                                      codec:nil
                                                                 isSelected:YES];
  return quality;
}

- (void)setMaxBitrate:(NSInteger)maxBitrateBps
                error:(FlutterError *_Nullable *_Nonnull)error {
  NSLog(@"[ABR] setMaxBitrate: %ld bps (resetting lastIndicatedBitrate from %.0f)",
        (long)maxBitrateBps, _lastIndicatedBitrate);
  // Reset so the next access log entry always triggers an event,
  // even if the bitrate matches a previously seen value (e.g. A→B→A).
  _lastIndicatedBitrate = 0;
  _player.currentItem.preferredPeakBitRate = (double)maxBitrateBps;
}

- (void)setMaxResolutionWidth:(NSInteger)width
                       height:(NSInteger)height
                        error:(FlutterError *_Nullable *_Nonnull)error {
  NSLog(@"[ABR] setMaxResolution: %ldx%ld (resetting lastIndicatedBitrate from %.0f)",
        (long)width, (long)height, _lastIndicatedBitrate);
  _lastIndicatedBitrate = 0;
  if (@available(iOS 11.0, macOS 10.13, *)) {
    _player.currentItem.preferredMaximumResolution = CGSizeMake(width, height);
  }
}

#pragma mark - FVPPipControllerDelegate

- (void)pipControllerDidStartPip {
  [self.eventListener videoPlayerDidChangePipState:YES];
}

- (void)pipControllerDidStopPip {
  [self.eventListener videoPlayerDidChangePipState:NO];
}

- (void)pipControllerFailedToStartWithError:(NSError *)error {
  NSLog(@"PiP failed to start: %@", error.localizedDescription);
}

#pragma mark - Private

- (int64_t)duration {
  // Note: https://openradar.appspot.com/radar?id=4968600712511488
  // `[AVPlayerItem duration]` can be `kCMTimeIndefinite`,
  // use `[[AVPlayerItem asset] duration]` instead.
  return FVPCMTimeToMillis([[[_player currentItem] asset] duration]);
}

@end
