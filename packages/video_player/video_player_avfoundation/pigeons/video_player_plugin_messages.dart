// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Contains plugin-class-level APIs.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/video_player_plugin_messages.g.dart',
    swiftOut:
        'darwin/video_player_avfoundation/Sources/video_player_avfoundation/VideoPlayerPluginMessages.g.swift',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Information passed to the platform view creation.
class PlatformVideoViewCreationParams {
  const PlatformVideoViewCreationParams({required this.playerId});

  final int playerId;
}

class CreationOptions {
  CreationOptions({required this.uri, required this.httpHeaders});

  String uri;
  Map<String, String> httpHeaders;
}

class TexturePlayerIds {
  TexturePlayerIds({required this.playerId, required this.textureId});

  final int playerId;
  final int textureId;
}

/// Metadata shown on the lock screen / Control Center while background
/// playback is enabled for a player.
class PlatformMediaInfo {
  PlatformMediaInfo({required this.title});
  String title;
  String? artist;
  String? artworkUrl;
  int? durationMs;

  /// Interval (in milliseconds) used by the lock-screen / Control Center
  /// "skip backward" button. When null, the platform falls back to a default
  /// (15s) chosen to match the in-app rewind control.
  int? skipBackwardIntervalMs;

  /// Interval (in milliseconds) used by the lock-screen / Control Center
  /// "skip forward" button. When null, the platform falls back to a default
  /// (30s) chosen to match the in-app fast-forward control.
  int? skipForwardIntervalMs;
}

@HostApi()
abstract class AVFoundationVideoPlayerApi {
  void initialize();
  // Creates a new player using a platform view for rendering and returns its
  // ID.
  @SwiftFunction('createPlatformViewPlayer(options:)')
  int createForPlatformView(CreationOptions params);
  // Creates a new player using a texture for rendering and returns its IDs.
  @SwiftFunction('createTexturePlayer(options:)')
  TexturePlayerIds createForTextureView(CreationOptions creationOptions);
  @SwiftFunction('setMixWithOthers(_:)')
  void setMixWithOthers(bool mixWithOthers);
  @SwiftFunction('fileURLForAsset(name:package:)')
  String? getAssetUrl(String asset, String? package);

  // Picture-in-Picture control. Keyed by player ID and delegated to the
  // matching player instance.
  @SwiftFunction('isPipSupported()')
  bool isPipSupported();
  @SwiftFunction('enterPip(playerId:)')
  void enterPip(int playerId);
  @SwiftFunction('exitPip(playerId:)')
  void exitPip(int playerId);
  @SwiftFunction('isPipActive(playerId:)')
  bool isPipActive(int playerId);
  @SwiftFunction('setAutoPip(playerId:enabled:)')
  void setAutoPip(int playerId, bool enabled);

  // Background playback control, keyed by player ID.
  @SwiftFunction('enableBackgroundPlayback(playerId:mediaInfo:)')
  void enableBackgroundPlayback(int playerId, PlatformMediaInfo? mediaInfo);
  @SwiftFunction('disableBackgroundPlayback(playerId:)')
  void disableBackgroundPlayback(int playerId);

  // Cache control methods (no-ops on iOS until a future HLS cache phase).
  @SwiftFunction('setCacheMaxSize(_:)')
  void setCacheMaxSize(int maxSizeBytes);
  @SwiftFunction('clearCache()')
  void clearCache();
  @SwiftFunction('getCacheSize()')
  int getCacheSize();
  @SwiftFunction('isCacheEnabled()')
  bool isCacheEnabled();
  @SwiftFunction('setCacheEnabled(_:)')
  void setCacheEnabled(bool enabled);
}
