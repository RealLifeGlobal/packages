// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface that implementations of video_player must implement.
///
/// Platform implementations should extend this class rather than implement it as `video_player`
/// does not consider newly added methods to be breaking changes. Extending this class
/// (using `extends`) ensures that the subclass will get the default implementation, while
/// platform implementations that `implements` this interface will be broken by newly added
/// [VideoPlayerPlatform] methods.
abstract class VideoPlayerPlatform extends PlatformInterface {
  /// Constructs a VideoPlayerPlatform.
  VideoPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VideoPlayerPlatform _instance = _PlaceholderImplementation();

  /// The instance of [VideoPlayerPlatform] to use.
  ///
  /// Defaults to a placeholder that does not override any methods, and thus
  /// throws `UnimplementedError` in most cases.
  static VideoPlayerPlatform get instance => _instance;

  /// Platform-specific plugins should override this with their own
  /// platform-specific class that extends [VideoPlayerPlatform] when they
  /// register themselves.
  static set instance(VideoPlayerPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Initializes the platform interface and disposes all existing players.
  ///
  /// This method is called when the plugin is first initialized
  /// and on every full restart.
  Future<void> init() {
    throw UnimplementedError('init() has not been implemented.');
  }

  /// Clears one video.
  Future<void> dispose(int playerId) {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  /// Creates an instance of a video player and returns its playerId.
  @Deprecated('Use createWithOptions() instead.')
  Future<int?> create(DataSource dataSource) {
    throw UnimplementedError('create() has not been implemented.');
  }

  /// Creates an instance of a video player based on creation options
  /// and returns its playerId.
  Future<int?> createWithOptions(VideoCreationOptions options) {
    return create(options.dataSource);
  }

  /// Returns a Stream of [VideoEventType]s.
  Stream<VideoEvent> videoEventsFor(int playerId) {
    throw UnimplementedError('videoEventsFor() has not been implemented.');
  }

  /// Sets the looping attribute of the video.
  Future<void> setLooping(int playerId, bool looping) {
    throw UnimplementedError('setLooping() has not been implemented.');
  }

  /// Starts the video playback.
  Future<void> play(int playerId) {
    throw UnimplementedError('play() has not been implemented.');
  }

  /// Stops the video playback.
  Future<void> pause(int playerId) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// Sets the volume to a range between 0.0 and 1.0.
  Future<void> setVolume(int playerId, double volume) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  /// Sets the video position to a [Duration] from the start.
  Future<void> seekTo(int playerId, Duration position) {
    throw UnimplementedError('seekTo() has not been implemented.');
  }

  /// Sets the playback speed to a [speed] value indicating the playback rate.
  Future<void> setPlaybackSpeed(int playerId, double speed) {
    throw UnimplementedError('setPlaybackSpeed() has not been implemented.');
  }

  /// Gets the video position as [Duration] from the start.
  Future<Duration> getPosition(int playerId) {
    throw UnimplementedError('getPosition() has not been implemented.');
  }

  /// Returns a widget displaying the video with a given playerId.
  @Deprecated('Use buildViewWithOptions() instead.')
  Widget buildView(int playerId) {
    throw UnimplementedError('buildView() has not been implemented.');
  }

  /// Returns a widget displaying the video based on given options.
  Widget buildViewWithOptions(VideoViewOptions options) {
    // Default implementation for backwards compatibility.
    return buildView(options.playerId);
  }

  /// Sets the audio mode to mix with other sources.
  Future<void> setMixWithOthers(bool mixWithOthers) {
    throw UnimplementedError('setMixWithOthers() has not been implemented.');
  }

  /// Sets whether the video should continue to play in the background.
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) {
    throw UnimplementedError(
      'setAllowBackgroundPlayback() has not been implemented.',
    );
  }

  /// Sets additional options on web.
  Future<void> setWebOptions(int playerId, VideoPlayerWebOptions options) {
    throw UnimplementedError('setWebOptions() has not been implemented.');
  }

  /// Gets the available audio tracks for the video.
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) {
    throw UnimplementedError('getAudioTracks() has not been implemented.');
  }

  /// Selects which audio track is chosen for playback from its [trackId]
  Future<void> selectAudioTrack(int playerId, String trackId) {
    throw UnimplementedError('selectAudioTrack() has not been implemented.');
  }

  /// Returns whether audio track selection is supported on this platform.
  ///
  /// This method allows developers to query at runtime whether the current
  /// platform supports audio track selection functionality. This is useful
  /// for platforms like web where audio track selection may not be available.
  ///
  /// Returns `true` if [getAudioTracks] and [selectAudioTrack] are supported,
  /// `false` otherwise.
  ///
  /// The default implementation returns `false`. Platform implementations
  /// should override this to return `true` if they support audio track selection.
  bool isAudioTrackSupportAvailable() {
    return false;
  }

  /// Returns whether Picture-in-Picture mode is supported on this device.
  Future<bool> isPipSupported() {
    throw UnimplementedError('isPipSupported() has not been implemented.');
  }

  /// Enters Picture-in-Picture mode for the given player.
  Future<void> enterPip(int playerId) {
    throw UnimplementedError('enterPip() has not been implemented.');
  }

  /// Exits Picture-in-Picture mode for the given player.
  Future<void> exitPip(int playerId) {
    throw UnimplementedError('exitPip() has not been implemented.');
  }

  /// Returns whether Picture-in-Picture mode is currently active.
  Future<bool> isPipActive(int playerId) {
    throw UnimplementedError('isPipActive() has not been implemented.');
  }

  /// Sets whether PiP should be entered automatically when the app
  /// goes to background (Android 12+ only).
  Future<void> setAutoEnterPip(int playerId, bool enabled) {
    throw UnimplementedError('setAutoEnterPip() has not been implemented.');
  }

  /// Enables background playback for the given player.
  ///
  /// When enabled, audio continues playing when the app is backgrounded.
  /// On Android, this starts a foreground service with a media notification.
  /// On iOS, this configures the audio session and sets up lock screen controls.
  Future<void> enableBackgroundPlayback(int playerId, {MediaInfo? mediaInfo}) {
    throw UnimplementedError(
      'enableBackgroundPlayback() has not been implemented.',
    );
  }

  /// Disables background playback for the given player.
  Future<void> disableBackgroundPlayback(int playerId) {
    throw UnimplementedError(
      'disableBackgroundPlayback() has not been implemented.',
    );
  }

  // Cache control methods

  /// Sets the maximum cache size in bytes.
  Future<void> setCacheMaxSize(int maxSizeBytes) {
    throw UnimplementedError(
      'setCacheMaxSize() has not been implemented.',
    );
  }

  /// Clears all cached video data.
  Future<void> clearCache() {
    throw UnimplementedError('clearCache() has not been implemented.');
  }

  /// Returns the current cache size in bytes.
  Future<int> getCacheSize() {
    throw UnimplementedError('getCacheSize() has not been implemented.');
  }

  /// Returns whether caching is enabled.
  Future<bool> isCacheEnabled() {
    throw UnimplementedError('isCacheEnabled() has not been implemented.');
  }

  /// Enables or disables caching.
  Future<void> setCacheEnabled(bool enabled) {
    throw UnimplementedError('setCacheEnabled() has not been implemented.');
  }

  // Adaptive Bitrate control methods

  /// Returns the available video quality variants for the given player.
  Future<List<VideoQuality>> getAvailableQualities(int playerId) {
    throw UnimplementedError(
      'getAvailableQualities() has not been implemented.',
    );
  }

  /// Returns the current video quality for the given player.
  Future<VideoQuality?> getCurrentQuality(int playerId) {
    throw UnimplementedError(
      'getCurrentQuality() has not been implemented.',
    );
  }

  /// Sets the maximum video bitrate in bits per second.
  Future<void> setMaxBitrate(int playerId, int maxBitrateBps) {
    throw UnimplementedError('setMaxBitrate() has not been implemented.');
  }

  /// Sets the maximum video resolution.
  Future<void> setMaxResolution(int playerId, int width, int height) {
    throw UnimplementedError('setMaxResolution() has not been implemented.');
  }
}

class _PlaceholderImplementation extends VideoPlayerPlatform {}

/// Description of the data source used to create an instance of
/// the video player.
class DataSource {
  /// Constructs an instance of [DataSource].
  ///
  /// The [sourceType] is always required.
  ///
  /// The [uri] argument takes the form of `'https://example.com/video.mp4'` or
  /// `'file:///absolute/path/to/local/video.mp4`.
  ///
  /// The [formatHint] argument can be null.
  ///
  /// The [asset] argument takes the form of `'assets/video.mp4'`.
  ///
  /// The [package] argument must be non-null when the asset comes from a
  /// package and null otherwise.
  DataSource({
    required this.sourceType,
    this.uri,
    this.formatHint,
    this.asset,
    this.package,
    this.httpHeaders = const <String, String>{},
  });

  /// The way in which the video was originally loaded.
  ///
  /// This has nothing to do with the video's file type. It's just the place
  /// from which the video is fetched from.
  final DataSourceType sourceType;

  /// The URI to the video file.
  ///
  /// This will be in different formats depending on the [DataSourceType] of
  /// the original video.
  final String? uri;

  /// **Android only**. Will override the platform's generic file format
  /// detection with whatever is set here.
  final VideoFormat? formatHint;

  /// HTTP headers used for the request to the [uri].
  /// Only for [DataSourceType.network] videos.
  /// Always empty for other video types.
  Map<String, String> httpHeaders;

  /// The name of the asset. Only set for [DataSourceType.asset] videos.
  final String? asset;

  /// The package that the asset was loaded from. Only set for
  /// [DataSourceType.asset] videos.
  final String? package;
}

/// The way in which the video was originally loaded.
///
/// This has nothing to do with the video's file type. It's just the place
/// from which the video is fetched from.
enum DataSourceType {
  /// The video was included in the app's asset files.
  asset,

  /// The video was downloaded from the internet.
  network,

  /// The video was loaded off of the local filesystem.
  file,

  /// The video is available via contentUri. Android only.
  contentUri,
}

/// The file format of the given video.
enum VideoFormat {
  /// Dynamic Adaptive Streaming over HTTP, also known as MPEG-DASH.
  dash,

  /// HTTP Live Streaming.
  hls,

  /// Smooth Streaming.
  ss,

  /// Any format other than the other ones defined in this enum.
  other,
}

/// The type of video view to be used.
enum VideoViewType {
  /// Texture will be used to render video.
  textureView,

  /// Platform view will be used to render video.
  platformView,
}

/// Event emitted from the platform implementation.
@immutable
class VideoEvent {
  /// Creates an instance of [VideoEvent].
  ///
  /// The [eventType] argument is required.
  ///
  /// Depending on the [eventType], the [duration], [size],
  /// [rotationCorrection], and [buffered] arguments can be null.
  // TODO(stuartmorgan): Temporarily suppress warnings about not using const
  // in all of the other video player packages, fix this, and then update
  // the other packages to use const.
  // ignore: prefer_const_constructors_in_immutables
  VideoEvent({
    required this.eventType,
    this.duration,
    this.size,
    this.rotationCorrection,
    this.buffered,
    this.isPlaying,
    this.isPipActive,
    this.wasDismissed,
    this.pipWindowSize,
    this.quality,
  });

  /// The type of the event.
  final VideoEventType eventType;

  /// Duration of the video.
  ///
  /// Only used if [eventType] is [VideoEventType.initialized].
  final Duration? duration;

  /// Size of the video.
  ///
  /// Only used if [eventType] is [VideoEventType.initialized].
  final Size? size;

  /// Degrees to rotate the video (clockwise) so it is displayed correctly.
  ///
  /// Only used if [eventType] is [VideoEventType.initialized].
  final int? rotationCorrection;

  /// Buffered parts of the video.
  ///
  /// Only used if [eventType] is [VideoEventType.bufferingUpdate].
  final List<DurationRange>? buffered;

  /// Whether the video is currently playing.
  ///
  /// Only used if [eventType] is [VideoEventType.isPlayingStateUpdate].
  final bool? isPlaying;

  /// Whether Picture-in-Picture mode is currently active.
  ///
  /// Only used if [eventType] is [VideoEventType.pipStateChanged].
  final bool? isPipActive;

  /// Whether PiP was dismissed by the user (e.g. the X button) as opposed to
  /// expanded back to full screen.
  ///
  /// Only used if [eventType] is [VideoEventType.pipStateChanged] and
  /// [isPipActive] is false.
  final bool? wasDismissed;

  /// The window size (in dp) at the time of a PiP state change.
  ///
  /// Only used if [eventType] is [VideoEventType.pipStateChanged].
  /// When [isPipActive] is true, this is the PiP window size.
  /// When [isPipActive] is false, this is the restored window size.
  final Size? pipWindowSize;

  /// The current video quality after an ABR switch.
  ///
  /// Only used if [eventType] is [VideoEventType.qualityChanged].
  final VideoQuality? quality;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VideoEvent &&
            runtimeType == other.runtimeType &&
            eventType == other.eventType &&
            duration == other.duration &&
            size == other.size &&
            rotationCorrection == other.rotationCorrection &&
            listEquals(buffered, other.buffered) &&
            isPlaying == other.isPlaying &&
            isPipActive == other.isPipActive &&
            wasDismissed == other.wasDismissed &&
            pipWindowSize == other.pipWindowSize &&
            quality == other.quality;
  }

  @override
  int get hashCode => Object.hash(
    eventType,
    duration,
    size,
    rotationCorrection,
    buffered,
    isPlaying,
    isPipActive,
    wasDismissed,
    pipWindowSize,
    quality,
  );
}

/// Type of the event.
///
/// Emitted by the platform implementation when the video is initialized or
/// completed or to communicate buffering events or play state changed.
enum VideoEventType {
  /// The video has been initialized.
  ///
  /// A maximum of one event of this type may be emitted per instance.
  initialized,

  /// The playback has ended.
  completed,

  /// Updated information on the buffering state.
  bufferingUpdate,

  /// The video started to buffer.
  bufferingStart,

  /// The video stopped to buffer.
  bufferingEnd,

  /// The playback state of the video has changed.
  ///
  /// This event is fired when the video starts or pauses due to user actions or
  /// phone calls, or other app media such as music players.
  isPlayingStateUpdate,

  /// The PiP state has changed.
  pipStateChanged,

  /// The video quality has changed (ABR switch).
  qualityChanged,

  /// An unknown event has been received.
  unknown,
}

/// Describes a discrete segment of time within a video using a [start] and
/// [end] [Duration].
@immutable
class DurationRange {
  /// Trusts that the given [start] and [end] are actually in order. They should
  /// both be non-null.
  // TODO(stuartmorgan): Temporarily suppress warnings about not using const
  // in all of the other video player packages, fix this, and then update
  // the other packages to use const.
  // ignore: prefer_const_constructors_in_immutables
  DurationRange(this.start, this.end);

  /// The beginning of the segment described relative to the beginning of the
  /// entire video. Should be shorter than or equal to [end].
  ///
  /// For example, if the entire video is 4 minutes long and the range is from
  /// 1:00-2:00, this should be a `Duration` of one minute.
  final Duration start;

  /// The end of the segment described as a duration relative to the beginning of
  /// the entire video. This is expected to be non-null and longer than or equal
  /// to [start].
  ///
  /// For example, if the entire video is 4 minutes long and the range is from
  /// 1:00-2:00, this should be a `Duration` of two minutes.
  final Duration end;

  /// Assumes that [duration] is the total length of the video that this
  /// DurationRange is a segment form. It returns the percentage that [start] is
  /// through the entire video.
  ///
  /// For example, assume that the entire video is 4 minutes long. If [start] has
  /// a duration of one minute, this will return `0.25` since the DurationRange
  /// starts 25% of the way through the video's total length.
  double startFraction(Duration duration) {
    return start.inMilliseconds / duration.inMilliseconds;
  }

  /// Assumes that [duration] is the total length of the video that this
  /// DurationRange is a segment form. It returns the percentage that [start] is
  /// through the entire video.
  ///
  /// For example, assume that the entire video is 4 minutes long. If [end] has a
  /// duration of two minutes, this will return `0.5` since the DurationRange
  /// ends 50% of the way through the video's total length.
  double endFraction(Duration duration) {
    return end.inMilliseconds / duration.inMilliseconds;
  }

  @override
  String toString() =>
      '${objectRuntimeType(this, 'DurationRange')}(start: $start, end: $end)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DurationRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// [VideoPlayerOptions] can be optionally used to set additional player settings
@immutable
class VideoPlayerOptions {
  /// Set additional optional player settings
  // TODO(stuartmorgan): Temporarily suppress warnings about not using const
  // in all of the other video player packages, fix this, and then update
  // the other packages to use const.
  // ignore: prefer_const_constructors_in_immutables
  VideoPlayerOptions({
    this.mixWithOthers = false,
    this.allowBackgroundPlayback = false,
    this.webOptions,
    this.androidOptions,
  });

  /// Set this to true to keep playing video in background, when app goes in background.
  /// The default value is false.
  final bool allowBackgroundPlayback;

  /// Set this to true to mix the video players audio with other audio sources.
  /// The default value is false
  ///
  /// Note: This option will be silently ignored in the web platform (there is
  /// currently no way to implement this feature in this platform).
  final bool mixWithOthers;

  /// Additional web controls
  final VideoPlayerWebOptions? webOptions;

  /// Additional Android controls
  final AndroidVideoPlayerOptions? androidOptions;
}

/// Android-specific video player options for configuring ExoPlayer behavior.
@immutable
class AndroidVideoPlayerOptions {
  /// Creates Android-specific video player options.
  const AndroidVideoPlayerOptions({
    this.maxLoadRetries = 5,
    this.maxPlayerRecoveryAttempts = 3,
  });

  /// Max retries per segment/load error before escalating
  /// (ExoPlayer LoadErrorHandlingPolicy).
  ///
  /// Default 5 matches ExoPlayer's DefaultLoadErrorHandlingPolicy default.
  final int maxLoadRetries;

  /// Max player-level recovery attempts for fatal network errors
  /// (e.g. connection lost).
  ///
  /// After exhausting these, the error is surfaced to the app.
  final int maxPlayerRecoveryAttempts;
}

/// [VideoPlayerWebOptions] can be optionally used to set additional web settings
@immutable
class VideoPlayerWebOptions {
  /// [VideoPlayerWebOptions] can be optionally used to set additional web settings
  const VideoPlayerWebOptions({
    this.controls = const VideoPlayerWebOptionsControls.disabled(),
    this.allowContextMenu = true,
    this.allowRemotePlayback = true,
    this.poster,
  });

  /// Additional settings for how control options are displayed
  final VideoPlayerWebOptionsControls controls;

  /// Whether context menu (right click) is allowed
  final bool allowContextMenu;

  /// Whether remote playback is allowed
  final bool allowRemotePlayback;

  /// The URL of the poster image to be displayed before the video starts
  final Uri? poster;
}

/// [VideoPlayerWebOptions] can be used to set how control options are displayed
@immutable
class VideoPlayerWebOptionsControls {
  /// Enables controls and sets how the options are displayed
  const VideoPlayerWebOptionsControls.enabled({
    this.allowDownload = true,
    this.allowFullscreen = true,
    this.allowPlaybackRate = true,
    this.allowPictureInPicture = true,
  }) : enabled = true;

  /// Disables control options. Default behavior.
  const VideoPlayerWebOptionsControls.disabled()
    : enabled = false,
      allowDownload = false,
      allowFullscreen = false,
      allowPlaybackRate = false,
      allowPictureInPicture = false;

  /// Whether native controls are enabled
  final bool enabled;

  /// Whether downloaded control is displayed
  ///
  /// Only applicable when [controlsEnabled] is true
  final bool allowDownload;

  /// Whether fullscreen control is enabled
  ///
  /// Only applicable when [controlsEnabled] is true
  final bool allowFullscreen;

  /// Whether playback rate control is displayed
  ///
  /// Only applicable when [controlsEnabled] is true
  final bool allowPlaybackRate;

  /// Whether picture in picture control is displayed
  ///
  /// Only applicable when [controlsEnabled] is true
  final bool allowPictureInPicture;

  /// A string representation of disallowed controls
  String get controlsList {
    final controlsList = <String>[];
    if (!allowDownload) {
      controlsList.add('nodownload');
    }
    if (!allowFullscreen) {
      controlsList.add('nofullscreen');
    }
    if (!allowPlaybackRate) {
      controlsList.add('noplaybackrate');
    }

    return controlsList.join(' ');
  }
}

/// [VideoViewOptions] contains configuration options for a video view.
@immutable
class VideoViewOptions {
  /// Constructs an instance of [VideoViewOptions].
  const VideoViewOptions({required this.playerId});

  /// The identifier of the video player.
  final int playerId;
}

/// [VideoCreationOptions] contains creation options for a video player.
@immutable
class VideoCreationOptions {
  /// Constructs an instance of [VideoCreationOptions].
  const VideoCreationOptions({
    required this.dataSource,
    required this.viewType,
    this.androidOptions,
  });

  /// The data source used to create the player.
  final DataSource dataSource;

  /// The type of view to be used for displaying the video player
  final VideoViewType viewType;

  /// Android-specific options for configuring ExoPlayer behavior.
  final AndroidVideoPlayerOptions? androidOptions;
}

/// Represents an audio track in a video with its metadata.
@immutable
class VideoAudioTrack {
  /// Constructs an instance of [VideoAudioTrack].
  const VideoAudioTrack({
    required this.id,
    required this.label,
    required this.language,
    required this.isSelected,
    this.bitrate,
    this.sampleRate,
    this.channelCount,
    this.codec,
  });

  /// Unique identifier for the audio track.
  final String id;

  /// Human-readable label for the track.
  ///
  /// May be null if not available from the platform.
  final String? label;

  /// Language code of the audio track (e.g., 'en', 'es', 'und').
  ///
  /// May be null if not available from the platform.
  final String? language;

  /// Whether this track is currently selected.
  final bool isSelected;

  /// Bitrate of the audio track in bits per second.
  ///
  /// May be null if not available from the platform.
  final int? bitrate;

  /// Sample rate of the audio track in Hz.
  ///
  /// May be null if not available from the platform.
  final int? sampleRate;

  /// Number of audio channels.
  ///
  /// May be null if not available from the platform.
  final int? channelCount;

  /// Audio codec used (e.g., 'aac', 'mp3', 'ac3').
  ///
  /// May be null if not available from the platform.
  final String? codec;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VideoAudioTrack &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            label == other.label &&
            language == other.language &&
            isSelected == other.isSelected &&
            bitrate == other.bitrate &&
            sampleRate == other.sampleRate &&
            channelCount == other.channelCount &&
            codec == other.codec;
  }

  @override
  int get hashCode => Object.hash(
    id,
    label,
    language,
    isSelected,
    bitrate,
    sampleRate,
    channelCount,
    codec,
  );

  @override
  String toString() =>
      'VideoAudioTrack('
      'id: $id, '
      'label: $label, '
      'language: $language, '
      'isSelected: $isSelected, '
      'bitrate: $bitrate, '
      'sampleRate: $sampleRate, '
      'channelCount: $channelCount, '
      'codec: $codec)';
}

/// Represents a video quality variant (resolution/bitrate combination)
/// from an adaptive bitrate stream.
@immutable
class VideoQuality {
  /// Constructs a [VideoQuality].
  const VideoQuality({
    required this.width,
    required this.height,
    required this.bitrate,
    required this.isSelected,
    this.codec,
  });

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Bitrate in bits per second.
  final int bitrate;

  /// Video codec (e.g., 'avc1.64001f', 'hev1.1.6.L93.B0').
  final String? codec;

  /// Whether this quality variant is currently selected.
  final bool isSelected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoQuality &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height &&
          bitrate == other.bitrate &&
          codec == other.codec &&
          isSelected == other.isSelected;

  @override
  int get hashCode => Object.hash(width, height, bitrate, codec, isSelected);

  @override
  String toString() =>
      'VideoQuality(${width}x$height @ ${bitrate}bps, codec: $codec, selected: $isSelected)';
}

/// Media information for lock screen / notification display during
/// background playback.
@immutable
class MediaInfo {
  /// Constructs a [MediaInfo].
  const MediaInfo({
    required this.title,
    this.artist,
    this.artworkUrl,
    this.durationMs,
  });

  /// The title of the media.
  final String title;

  /// The artist of the media.
  final String? artist;

  /// URL to the artwork image.
  final String? artworkUrl;

  /// Duration of the media in milliseconds.
  final int? durationMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaInfo &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          artist == other.artist &&
          artworkUrl == other.artworkUrl &&
          durationMs == other.durationMs;

  @override
  int get hashCode => Object.hash(title, artist, artworkUrl, durationMs);
}
