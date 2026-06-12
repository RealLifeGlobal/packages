// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Contains player-instance-level APIs.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/video_player_instance_messages.g.dart',
    objcHeaderOut:
        'darwin/video_player_avfoundation/Sources/video_player_avfoundation_objc/include/video_player_avfoundation_objc/VideoPlayerInstanceMessages.g.h',
    objcSourceOut:
        'darwin/video_player_avfoundation/Sources/video_player_avfoundation_objc/VideoPlayerInstanceMessages.g.m',
    objcOptions: ObjcOptions(
      prefix: 'FVP',
      headerIncludePath: './include/video_player_avfoundation_objc/VideoPlayerInstanceMessages.g.h',
    ),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Raw audio track data from AVMediaSelectionOption (for HLS streams).
class MediaSelectionAudioTrackData {
  MediaSelectionAudioTrackData({
    required this.index,
    this.displayName,
    this.languageCode,
    required this.isSelected,
    this.commonMetadataTitle,
  });

  int index;
  String? displayName;
  String? languageCode;
  bool isSelected;
  String? commonMetadataTitle;
}

/// Represents a video quality variant (resolution/bitrate combination).
class PlatformVideoQuality {
  PlatformVideoQuality({
    required this.width,
    required this.height,
    required this.bitrate,
    required this.isSelected,
  });
  int width;
  int height;
  int bitrate;
  String? codec;
  bool isSelected;
}

@HostApi()
abstract class VideoPlayerInstanceApi {
  @ObjCSelector('setLooping:')
  void setLooping(bool looping);
  @ObjCSelector('setVolume:')
  void setVolume(double volume);
  @ObjCSelector('setPlaybackSpeed:')
  void setPlaybackSpeed(double speed);
  void play();
  @ObjCSelector('position')
  int getPosition();
  @async
  @ObjCSelector('seekTo:')
  void seekTo(int position);
  void pause();
  void dispose();
  @ObjCSelector('getAudioTracks')
  List<MediaSelectionAudioTrackData> getAudioTracks();
  @ObjCSelector('selectAudioTrackAtIndex:')
  void selectAudioTrack(int trackIndex);

  // ABR (Adaptive Bitrate) control methods
  @ObjCSelector('getAvailableQualities')
  List<PlatformVideoQuality> getAvailableQualities();
  @ObjCSelector('getCurrentQuality')
  PlatformVideoQuality? getCurrentQuality();
  @ObjCSelector('setMaxBitrate:')
  void setMaxBitrate(int maxBitrateBps);
  @ObjCSelector('setMaxResolutionWidth:height:')
  void setMaxResolution(int width, int height);
}
