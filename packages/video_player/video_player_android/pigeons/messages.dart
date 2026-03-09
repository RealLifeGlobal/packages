// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/io/flutter/plugins/videoplayer/Messages.kt',
    kotlinOptions: KotlinOptions(package: 'io.flutter.plugins.videoplayer'),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Pigeon equivalent of video_platform_interface's VideoFormat.
enum PlatformVideoFormat { dash, hls, ss }

/// Pigeon equivalent of Player's playback state.
/// https://developer.android.com/media/media3/exoplayer/listening-to-player-events#playback-state
enum PlatformPlaybackState { idle, buffering, ready, ended, unknown }

sealed class PlatformVideoEvent {}

/// Sent when the video is initialized and ready to play.
class InitializationEvent extends PlatformVideoEvent {
  /// The video duration in milliseconds.
  late final int duration;

  /// The width of the video in pixels.
  late final int width;

  /// The height of the video in pixels.
  late final int height;

  /// The rotation that should be applied during playback.
  late final int rotationCorrection;
}

/// Sent when the video state changes.
///
/// Corresponds to ExoPlayer's onPlaybackStateChanged.
class PlaybackStateChangeEvent extends PlatformVideoEvent {
  late final PlatformPlaybackState state;
}

/// Sent when the video starts or stops playing.
///
/// Corresponds to ExoPlayer's onIsPlayingChanged.
class IsPlayingStateEvent extends PlatformVideoEvent {
  late final bool isPlaying;
}

/// Sent when audio tracks change.
///
/// This includes when the selected audio track changes after calling selectAudioTrack.
/// Corresponds to ExoPlayer's onTracksChanged.
class AudioTrackChangedEvent extends PlatformVideoEvent {
  /// The ID of the newly selected audio track, if any.
  late final String? selectedTrackId;
}

/// Sent when the video quality changes (ABR switch).
///
/// Corresponds to ExoPlayer's AnalyticsListener.onDownstreamFormatChanged.
class VideoQualityChangedEvent extends PlatformVideoEvent {
  late final int width;
  late final int height;
  late final int bitrate;
  late final String? codec;
}

/// Sent when PiP state changes.
class PipStateEvent extends PlatformVideoEvent {
  late final bool isInPipMode;

  /// Whether PiP was dismissed by the user (X button) as opposed to
  /// expanded back to full screen. Only meaningful when [isInPipMode] is false.
  late final bool wasDismissed;

  /// The window width in dp at the time of the PiP state change.
  late final int windowWidth;

  /// The window height in dp at the time of the PiP state change.
  late final int windowHeight;
}

/// Information passed to the platform view creation.
class PlatformVideoViewCreationParams {
  const PlatformVideoViewCreationParams({required this.playerId});

  final int playerId;
}

class CreationOptions {
  CreationOptions({required this.uri, required this.httpHeaders});
  String uri;
  PlatformVideoFormat? formatHint;
  Map<String, String> httpHeaders;
  String? userAgent;

  /// Max retries per segment/load error before escalating.
  /// Null means use ExoPlayer's default (5).
  int? maxLoadRetries;

  /// Max player-level recovery attempts for fatal network errors.
  /// Null means use the default (3).
  int? maxPlayerRecoveryAttempts;
}

class TexturePlayerIds {
  TexturePlayerIds({required this.playerId, required this.textureId});

  final int playerId;
  final int textureId;
}

class PlaybackState {
  PlaybackState({required this.playPosition, required this.bufferPosition});

  /// The current playback position, in milliseconds.
  final int playPosition;

  /// The current buffer position, in milliseconds.
  final int bufferPosition;
}

/// Represents an audio track in a video.
class AudioTrackMessage {
  AudioTrackMessage({
    required this.id,
    required this.label,
    required this.language,
    required this.isSelected,
    this.bitrate,
    this.sampleRate,
    this.channelCount,
    this.codec,
  });

  String id;
  String label;
  String language;
  bool isSelected;
  int? bitrate;
  int? sampleRate;
  int? channelCount;
  String? codec;
}

/// Raw audio track data from ExoPlayer Format objects.
class ExoPlayerAudioTrackData {
  ExoPlayerAudioTrackData({
    required this.groupIndex,
    required this.trackIndex,
    this.label,
    this.language,
    required this.isSelected,
    this.bitrate,
    this.sampleRate,
    this.channelCount,
    this.codec,
  });

  int groupIndex;
  int trackIndex;
  String? label;
  String? language;
  bool isSelected;
  int? bitrate;
  int? sampleRate;
  int? channelCount;
  String? codec;
}

/// Container for raw audio track data from Android ExoPlayer.
class NativeAudioTrackData {
  NativeAudioTrackData({this.exoPlayerTracks});

  /// ExoPlayer-based tracks
  List<ExoPlayerAudioTrackData>? exoPlayerTracks;
}

class PlatformMediaInfo {
  PlatformMediaInfo({required this.title});
  String title;
  String? artist;
  String? artworkUrl;
  int? durationMs;
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
abstract class AndroidVideoPlayerApi {
  void initialize();
  // Creates a new player using a platform view for rendering and returns its
  // ID.
  int createForPlatformView(CreationOptions options);
  // Creates a new player using a texture for rendering and returns its IDs.
  TexturePlayerIds createForTextureView(CreationOptions options);
  void dispose(int playerId);
  void setMixWithOthers(bool mixWithOthers);
  String getLookupKeyForAsset(String asset, String? packageName);
  void enableBackgroundPlayback(int playerId, PlatformMediaInfo? mediaInfo);
  void disableBackgroundPlayback(int playerId);
  bool isPipSupported();
  void enterPip(int playerId);
  bool isPipActive();
  void setAutoEnterPip(bool enabled);

  // Cache control methods
  void setCacheMaxSize(int maxSizeBytes);
  void clearCache();
  int getCacheSize();
  bool isCacheEnabled();
  void setCacheEnabled(bool enabled);
}

@HostApi()
abstract class VideoPlayerInstanceApi {
  /// Sets whether to automatically loop playback of the video.
  void setLooping(bool looping);

  /// Sets the volume, with 0.0 being muted and 1.0 being full volume.
  void setVolume(double volume);

  /// Sets the playback speed as a multiple of normal speed.
  void setPlaybackSpeed(double speed);

  /// Begins playback if the video is not currently playing.
  void play();

  /// Pauses playback if the video is currently playing.
  void pause();

  /// Seeks to the given playback position, in milliseconds.
  void seekTo(int position);

  /// Returns the current playback position, in milliseconds.
  int getCurrentPosition();

  /// Returns the current buffer position, in milliseconds.
  int getBufferedPosition();

  /// Gets the available audio tracks for the video.
  NativeAudioTrackData getAudioTracks();

  /// Selects which audio track is chosen for playback from its [groupIndex] and [trackIndex]
  void selectAudioTrack(int groupIndex, int trackIndex);

  // ABR (Adaptive Bitrate) control methods

  /// Returns the available video quality variants.
  List<PlatformVideoQuality> getAvailableQualities();

  /// Returns the currently playing video quality, or null if unknown.
  PlatformVideoQuality? getCurrentQuality();

  /// Sets the maximum video bitrate in bits per second.
  void setMaxBitrate(int maxBitrateBps);

  /// Sets the maximum video resolution.
  void setMaxResolution(int width, int height);
}

@EventChannelApi()
abstract class VideoEventChannel {
  PlatformVideoEvent videoEvents();
}
