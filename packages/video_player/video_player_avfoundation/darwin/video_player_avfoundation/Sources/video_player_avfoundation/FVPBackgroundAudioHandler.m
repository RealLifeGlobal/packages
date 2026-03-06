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
}

- (instancetype)initWithPlayer:(AVPlayer *)player {
  self = [super init];
  if (self) {
    _player = player;
    _isEnabled = NO;
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
  }

  _isEnabled = YES;
  _title = title ?: @"Video";
  _artist = artist;

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

  [self removeCommandTargets];

  if (_timeObserver) {
    [_player removeTimeObserver:_timeObserver];
    _timeObserver = nil;
  }

  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
#endif
}

#if TARGET_OS_IOS
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
#endif

- (void)updateNowPlayingInfo {
#if TARGET_OS_IOS
  if (!_isEnabled) return;

  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  info[MPMediaItemPropertyTitle] = _title ?: @"Video";
  if (_artist) {
    info[MPMediaItemPropertyArtist] = _artist;
  }

  CMTime duration = _player.currentItem.asset.duration;
  if (CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration)) {
    info[MPMediaItemPropertyPlaybackDuration] = @(CMTimeGetSeconds(duration));
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
