// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "./include/video_player_avfoundation/FVPBackgroundAudioHandler.h"

#if TARGET_OS_IOS
@import MediaPlayer;
@import UIKit;
#endif

@implementation FVPBackgroundAudioHandler {
  AVPlayer *_player;
  NSString *_title;
  NSString *_artist;
  BOOL _isEnabled;
  id _timeObserver;
  id _playTarget;
  id _pauseTarget;
  id _seekTarget;
  NSNumber *_cachedDuration;
#if TARGET_OS_IOS
  UIBackgroundTaskIdentifier _backgroundTask;
  MPMediaItemArtwork *_cachedArtwork;
  NSString *_artworkUrl;
  // Snapshot of user intent captured just before the app leaves the active
  // state. Used by handleEnterBackground: to decide whether re-asserting
  // playback is actually what the user wanted, instead of force-resuming a
  // video the user had explicitly paused.
  BOOL _wasPlayingBeforeBackground;
#endif
}

- (instancetype)initWithPlayer:(AVPlayer *)player {
  self = [super init];
  if (self) {
    _player = player;
    _isEnabled = NO;
#if TARGET_OS_IOS
    _backgroundTask = UIBackgroundTaskInvalid;
#endif
  }
  return self;
}

- (BOOL)isEnabled {
  return _isEnabled;
}

- (void)enableWithTitle:(nullable NSString *)title
                 artist:(nullable NSString *)artist
             artworkUrl:(nullable NSString *)artworkUrl
             durationMs:(nullable NSNumber *)durationMs {
#if TARGET_OS_IOS
  // Remove any existing handlers first to prevent leaks.
  if (_isEnabled) {
    [self removeCommandTargets];
    [self removeAppLifecycleObservers];
  }

  _isEnabled = YES;
  _title = title ?: @"Video";
  _artist = artist;
  _cachedDuration = nil;
  _cachedArtwork = nil;
  _artworkUrl = artworkUrl;
  _wasPlayingBeforeBackground = NO;

  if (artworkUrl.length > 0) {
    [self loadArtworkFromUrl:artworkUrl];
  }

  NSLog(@"video_player: [BG] enableWithTitle called — title=%@, player.rate=%f", title, _player.rate);

  // Ensure audio session category is Playback (not Ambient/SoloAmbient) so audio
  // continues when the app is backgrounded. Re-set here in case another plugin or
  // player changed the category since initialize was called.
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *categoryError = nil;
  [session setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:0
                 error:&categoryError];
  if (categoryError) {
    NSLog(@"video_player: [BG] Failed to set audio session category: %@", categoryError);
  }

  // Explicitly activate the audio session so playback persists through background transitions.
  NSError *sessionError = nil;
  [session setActive:YES error:&sessionError];
  if (sessionError) {
    NSLog(@"video_player: [BG] Failed to activate audio session: %@", sessionError);
  }

  // Signal to iOS that this app is an active media app.
  [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];

  NSLog(@"video_player: [BG] Audio session ready — category=%@, active=YES, player.rate=%f",
        session.category, _player.rate);

  // Observe app lifecycle to keep playback alive across background transitions.
  // willResignActive fires before didEnterBackground, while the player's rate
  // still reflects the user's intent — we snapshot it there so the
  // background handler can make an informed decision.
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleWillResignActive:)
                                               name:UIApplicationWillResignActiveNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleEnterBackground:)
                                               name:UIApplicationDidEnterBackgroundNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleEnterForeground:)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleInterruption:)
                                               name:AVAudioSessionInterruptionNotification
                                             object:session];

  // Set up remote command center
  MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

  _playTarget = [commandCenter.playCommand
      addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self->_player play];
        return MPRemoteCommandHandlerStatusSuccess;
      }];

  _pauseTarget = [commandCenter.pauseCommand
      addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self->_player pause];
        return MPRemoteCommandHandlerStatusSuccess;
      }];

  _seekTarget = [commandCenter.changePlaybackPositionCommand
      addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        MPChangePlaybackPositionCommandEvent *posEvent =
            (MPChangePlaybackPositionCommandEvent *)event;
        [self->_player seekToTime:CMTimeMakeWithSeconds(posEvent.positionTime, NSEC_PER_SEC)];
        return MPRemoteCommandHandlerStatusSuccess;
      }];

  // Update now playing info periodically
  __weak typeof(self) weakSelf = self;
  _timeObserver =
      [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1)
                                            queue:dispatch_get_main_queue()
                                       usingBlock:^(CMTime time) {
                                         [weakSelf updateNowPlayingInfo];
                                       }];

  [self updateNowPlayingInfo];
#endif
}

- (void)disable {
#if TARGET_OS_IOS
  _isEnabled = NO;

  [self removeAppLifecycleObservers];
  [self removeCommandTargets];
  [self endBackgroundTask];

  if (_timeObserver) {
    [_player removeTimeObserver:_timeObserver];
    _timeObserver = nil;
  }

  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
  [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
#endif
}

#if TARGET_OS_IOS

#pragma mark - App Lifecycle

- (void)handleWillResignActive:(NSNotification *)notification {
  if (!_isEnabled) return;

  // At this point the app is still active, so _player.rate reflects the
  // user's actual intent — not any pause iOS might inject during the
  // transition to background. Snapshot it for handleEnterBackground:.
  _wasPlayingBeforeBackground = (_player.rate > 0);
  NSLog(@"video_player: [BG] willResignActive — wasPlayingBeforeBackground=%@",
        _wasPlayingBeforeBackground ? @"YES" : @"NO");
}

- (void)handleEnterBackground:(NSNotification *)notification {
  if (!_isEnabled) return;

  NSLog(@"video_player: [BG] App entered background — player.rate=%f, wasPlaying=%@",
        _player.rate, _wasPlayingBeforeBackground ? @"YES" : @"NO");

  // If the user had the video paused before the transition, respect that —
  // do not start a background task, do not re-assert playback.
  if (!_wasPlayingBeforeBackground) {
    NSLog(@"video_player: [BG] User had video paused, leaving it paused");
    return;
  }

  // Start a background task to buy time for the audio session to take over.
  // Without this, iOS may suspend the process before AVPlayer establishes
  // its background audio rendering pipeline.
  [self endBackgroundTask];
  _backgroundTask = [[UIApplication sharedApplication]
      beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"video_player: [BG] Background task expired");
        [self endBackgroundTask];
      }];

  // Re-assert playback. When the app transitions to background, the system may
  // momentarily pause the AVPlayer. Calling play again ensures the audio
  // rendering pipeline stays active, which is what tells iOS to keep the app alive.
  if (_player.rate == 0 && _player.currentItem) {
    NSLog(@"video_player: [BG] Player was paused, re-starting playback");
    [_player play];
  }

  // Schedule a follow-up to ensure playback is still active after the transition settles.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (self->_isEnabled && self->_wasPlayingBeforeBackground &&
        self->_player.rate == 0 && self->_player.currentItem) {
      NSLog(@"video_player: [BG] Player still paused after 0.5s, re-starting");
      [self->_player play];
    }
    NSLog(@"video_player: [BG] Background settled — player.rate=%f", self->_player.rate);
  });
}

- (void)handleEnterForeground:(NSNotification *)notification {
  if (!_isEnabled) return;

  NSLog(@"video_player: [BG] App entering foreground — player.rate=%f", _player.rate);
  [self endBackgroundTask];
}

- (void)handleInterruption:(NSNotification *)notification {
  if (!_isEnabled) return;

  NSDictionary *info = notification.userInfo;
  AVAudioSessionInterruptionType type =
      [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

  if (type == AVAudioSessionInterruptionTypeBegan) {
    NSLog(@"video_player: [BG] Audio session interrupted (began)");
  } else if (type == AVAudioSessionInterruptionTypeEnded) {
    NSLog(@"video_player: [BG] Audio session interruption ended, resuming playback");
    AVAudioSessionInterruptionOptions options =
        [info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
    if (options & AVAudioSessionInterruptionOptionShouldResume) {
      [_player play];
    }
  }
}

- (void)endBackgroundTask {
  if (_backgroundTask != UIBackgroundTaskInvalid) {
    [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
    _backgroundTask = UIBackgroundTaskInvalid;
  }
}

- (void)removeAppLifecycleObservers {
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:UIApplicationWillResignActiveNotification
                                                object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:UIApplicationDidEnterBackgroundNotification
                                                object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:UIApplicationWillEnterForegroundNotification
                                                object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAudioSessionInterruptionNotification
                                                object:nil];
}

#pragma mark - Remote Command Targets

- (void)removeCommandTargets {
  MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
  if (_playTarget) {
    [commandCenter.playCommand removeTarget:_playTarget];
    _playTarget = nil;
  }
  if (_pauseTarget) {
    [commandCenter.pauseCommand removeTarget:_pauseTarget];
    _pauseTarget = nil;
  }
  if (_seekTarget) {
    [commandCenter.changePlaybackPositionCommand removeTarget:_seekTarget];
    _seekTarget = nil;
  }
}

- (void)loadArtworkFromUrl:(NSString *)urlString {
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;

  __weak typeof(self) weakSelf = self;
  NSURLSessionDataTask *task = [[NSURLSession sharedSession]
      dataTaskWithURL:url
    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      if (error || !data) {
        NSLog(@"video_player: [BG] Failed to load artwork: %@", error);
        return;
      }
      UIImage *image = [UIImage imageWithData:data];
      if (!image) return;

      dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_isEnabled) return;
        // Only apply if the URL hasn't changed since the request started.
        if (![strongSelf->_artworkUrl isEqualToString:urlString]) return;
        strongSelf->_cachedArtwork = [[MPMediaItemArtwork alloc]
            initWithBoundsSize:image.size
                requestHandler:^UIImage *(CGSize size) {
                  return image;
                }];
        [strongSelf updateNowPlayingInfo];
      });
    }];
  [task resume];
}
#endif

- (void)updateNowPlayingInfo {
#if TARGET_OS_IOS
  if (!_isEnabled) return;
  if (!_player.currentItem) return;

  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  info[MPMediaItemPropertyTitle] = _title ?: @"Video";
  if (_artist) {
    info[MPMediaItemPropertyArtist] = _artist;
  }

  if (!_cachedDuration) {
    CMTime duration = _player.currentItem.asset.duration;
    if (CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration)) {
      _cachedDuration = @(CMTimeGetSeconds(duration));
    }
  }
  if (_cachedDuration) {
    info[MPMediaItemPropertyPlaybackDuration] = _cachedDuration;
  }

  if (_cachedArtwork) {
    info[MPMediaItemPropertyArtwork] = _cachedArtwork;
  }

  info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(_player.currentTime));
  info[MPNowPlayingInfoPropertyPlaybackRate] = @(_player.rate);

  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
#endif
}

- (void)dealloc {
  [self disable];
}

@end
