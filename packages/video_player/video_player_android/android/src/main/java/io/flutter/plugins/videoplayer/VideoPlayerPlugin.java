// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.IBinder;
import android.util.LongSparseArray;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.session.MediaSessionService;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.plugins.videoplayer.pip.PipCallbackHelper;
import io.flutter.FlutterInjector;
import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugins.videoplayer.pip.PipHandler;
import io.flutter.plugins.videoplayer.platformview.PlatformVideoViewFactory;
import io.flutter.plugins.videoplayer.platformview.PlatformViewVideoPlayer;
import io.flutter.plugins.videoplayer.service.PlaybackService;
import io.flutter.plugins.videoplayer.texture.TextureVideoPlayer;
import io.flutter.view.TextureRegistry;
import java.util.HashSet;
import java.util.Set;

/** Android platform implementation of the VideoPlayerPlugin. */
public class VideoPlayerPlugin implements FlutterPlugin, ActivityAware, AndroidVideoPlayerApi {
  private static final String TAG = "VideoPlayerPlugin";
  private final LongSparseArray<VideoPlayer> videoPlayers = new LongSparseArray<>();
  private FlutterState flutterState;
  private final VideoPlayerOptions sharedOptions = new VideoPlayerOptions();
  private long nextPlayerIdentifier = 1;
  @NonNull private final PipHandler pipHandler = new PipHandler(null);
  private final Set<Long> backgroundEnabledPlayers = new HashSet<>();
  @Nullable private ServiceConnection serviceConnection;
  private boolean serviceBound = false;
  @Nullable private ExoPlayer pendingServicePlayer;
  @Nullable private PlatformMediaInfo pendingMediaInfo;
  @Nullable private ActivityPluginBinding activityBinding;
  private final PluginRegistry.UserLeaveHintListener onUserLeaveHintListener =
      () -> pipHandler.onUserLeaveHint();

  /** Register this with the v2 embedding for the plugin to respond to lifecycle callbacks. */
  public VideoPlayerPlugin() {
    pipHandler.setPipStateListener((isInPipMode, wasDismissed, widthDp, heightDp) -> {
      for (int i = 0; i < videoPlayers.size(); i++) {
        videoPlayers.valueAt(i).notifyPipStateChanged(isInPipMode, wasDismissed, widthDp, heightDp);
      }
    });
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    final FlutterInjector injector = FlutterInjector.instance();
    this.flutterState =
        new FlutterState(
            binding.getApplicationContext(),
            binding.getBinaryMessenger(),
            injector.flutterLoader()::getLookupKeyForAsset,
            injector.flutterLoader()::getLookupKeyForAsset,
            binding.getTextureRegistry());
    flutterState.startListening(this, binding.getBinaryMessenger());

    binding
        .getPlatformViewRegistry()
        .registerViewFactory(
            "plugins.flutter.dev/video_player_android",
            new PlatformVideoViewFactory(videoPlayers::get));
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (flutterState == null) {
      Log.wtf(TAG, "Detached from the engine before registering to it.");
    }
    flutterState.stopListening(binding.getBinaryMessenger());
    flutterState = null;
    PipCallbackHelper.setListener(null);
    onDestroy();
    VideoCacheManager.release();
  }

  // ActivityAware implementation
  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    attachToActivity(binding);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    detachFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    attachToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    detachFromActivity();
  }

  private void attachToActivity(@NonNull ActivityPluginBinding binding) {
    activityBinding = binding;
    pipHandler.setActivity(binding.getActivity());
    binding.addOnUserLeaveHintListener(onUserLeaveHintListener);
  }

  private void detachFromActivity() {
    if (activityBinding != null) {
      activityBinding.removeOnUserLeaveHintListener(onUserLeaveHintListener);
      activityBinding = null;
    }
    pipHandler.setActivity(null);
  }

  private void disposeAllPlayers() {
    // Unbind (and release the MediaSession) BEFORE releasing any ExoPlayers.
    // If the session is still alive when the player's thread is killed, queued
    // media-button commands (play/pause from the notification) will try to post
    // to a dead Handler, causing an ANR.
    unbindPlaybackService();

    for (int i = 0; i < videoPlayers.size(); i++) {
      videoPlayers.valueAt(i).dispose();
    }
    videoPlayers.clear();
    backgroundEnabledPlayers.clear();
  }

  private void bindPlaybackService() {
    if (serviceBound || flutterState == null) return;
    Context context = flutterState.applicationContext;
    Intent intent = new Intent(context, PlaybackService.class);
    intent.setAction(MediaSessionService.SERVICE_INTERFACE);
    serviceConnection = new ServiceConnection() {
      @Override
      public void onServiceConnected(ComponentName name, IBinder binder) {
        // Pass the pending ExoPlayer to the service for MediaSession support.
        if (pendingServicePlayer != null) {
          PlaybackService service = PlaybackService.getInstance();
          if (service != null) {
            Log.d(TAG, "Service connected, setting player on PlaybackService");
            service.setPlayer(pendingServicePlayer,
                pendingMediaInfo != null ? pendingMediaInfo.getTitle() : null,
                pendingMediaInfo != null ? pendingMediaInfo.getArtist() : null,
                pendingMediaInfo != null ? pendingMediaInfo.getArtworkUrl() : null);
            pendingServicePlayer = null;
            pendingMediaInfo = null;
          } else {
            Log.w(TAG, "Service connected but getInstance() returned null");
          }
        }
      }

      @Override
      public void onServiceDisconnected(ComponentName name) {
        serviceBound = false;
      }
    };
    // The service must be started (not just bound) to support foreground mode.
    // A bound-only service cannot call startForeground(), so Media3 can't post
    // the media notification. startService() starts it; Media3 then internally
    // calls startForeground() when playback begins.
    context.startService(intent);
    context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
    serviceBound = true;
  }

  private void unbindPlaybackService() {
    // Always release the MediaSession synchronously before stopping the
    // service so that no queued media-button commands reach an
    // already-released player.
    PlaybackService service = PlaybackService.getInstance();
    if (service != null) {
      service.releaseSession();
    }
    pendingServicePlayer = null;
    pendingMediaInfo = null;
    if (!serviceBound || flutterState == null) return;
    Context context = flutterState.applicationContext;
    if (serviceConnection != null) {
      context.unbindService(serviceConnection);
    }
    context.stopService(new Intent(context, PlaybackService.class));
    serviceBound = false;
  }

  public void onDestroy() {
    // The whole FlutterView is being destroyed. Here we release resources acquired for all
    // instances
    // of VideoPlayer. Once https://github.com/flutter/flutter/issues/19358 is resolved this may
    // be replaced with just asserting that videoPlayers.isEmpty().
    // https://github.com/flutter/flutter/issues/20989 tracks this.
    disposeAllPlayers();
  }

  @Override
  public void initialize() {
    disposeAllPlayers();
  }

  private VideoPlayerOptions playerOptionsFromCreationOptions(@NonNull CreationOptions options) {
    VideoPlayerOptions playerOptions = new VideoPlayerOptions();
    playerOptions.mixWithOthers = sharedOptions.mixWithOthers;
    Long maxLoadRetries = options.getMaxLoadRetries();
    if (maxLoadRetries != null) {
      playerOptions.maxLoadRetries = maxLoadRetries.intValue();
    }
    Long maxPlayerRecoveryAttempts = options.getMaxPlayerRecoveryAttempts();
    if (maxPlayerRecoveryAttempts != null) {
      playerOptions.maxPlayerRecoveryAttempts = maxPlayerRecoveryAttempts.intValue();
    }
    return playerOptions;
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  public long createForPlatformView(@NonNull CreationOptions options) {
    final VideoAsset videoAsset = videoAssetWithOptions(options);
    final VideoPlayerOptions playerOptions = playerOptionsFromCreationOptions(options);

    long id = nextPlayerIdentifier++;
    final String streamInstance = Long.toString(id);
    VideoPlayer videoPlayer =
        PlatformViewVideoPlayer.create(
            flutterState.applicationContext,
            VideoPlayerEventCallbacks.bindTo(flutterState.binaryMessenger, streamInstance),
            videoAsset,
            playerOptions);

    registerPlayerInstance(videoPlayer, id);
    return id;
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  public @NonNull TexturePlayerIds createForTextureView(@NonNull CreationOptions options) {
    final VideoAsset videoAsset = videoAssetWithOptions(options);
    final VideoPlayerOptions playerOptions = playerOptionsFromCreationOptions(options);

    long id = nextPlayerIdentifier++;
    final String streamInstance = Long.toString(id);
    TextureRegistry.SurfaceProducer handle = flutterState.textureRegistry.createSurfaceProducer();
    VideoPlayer videoPlayer =
        TextureVideoPlayer.create(
            flutterState.applicationContext,
            VideoPlayerEventCallbacks.bindTo(flutterState.binaryMessenger, streamInstance),
            handle,
            videoAsset,
            playerOptions);

    registerPlayerInstance(videoPlayer, id);
    return new TexturePlayerIds(id, handle.id());
  }

  private @NonNull VideoAsset videoAssetWithOptions(@NonNull CreationOptions options) {
    final @NonNull String uri = options.getUri();
    if (uri.startsWith("asset:")) {
      return VideoAsset.fromAssetUrl(uri);
    } else if (uri.startsWith("rtsp:")) {
      return VideoAsset.fromRtspUrl(uri);
    } else {
      VideoAsset.StreamingFormat streamingFormat = VideoAsset.StreamingFormat.UNKNOWN;
      PlatformVideoFormat formatHint = options.getFormatHint();
      if (formatHint != null) {
        switch (formatHint) {
          case SS:
            streamingFormat = VideoAsset.StreamingFormat.SMOOTH;
            break;
          case DASH:
            streamingFormat = VideoAsset.StreamingFormat.DYNAMIC_ADAPTIVE;
            break;
          case HLS:
            streamingFormat = VideoAsset.StreamingFormat.HTTP_LIVE;
            break;
        }
      }
      return VideoAsset.fromRemoteUrl(
          uri, streamingFormat, options.getHttpHeaders(), options.getUserAgent());
    }
  }

  private void registerPlayerInstance(VideoPlayer player, long id) {
    BinaryMessenger messenger = flutterState.binaryMessenger;
    final String channelSuffix = Long.toString(id);
    VideoPlayerInstanceApi.Companion.setUp(messenger, player, channelSuffix);
    player.setDisposeHandler(
        () -> {
          VideoPlayerInstanceApi.Companion.setUp(messenger, null, channelSuffix);
          removeBackgroundPlayer(id);
        });

    videoPlayers.put(id, player);
  }

  @NonNull
  private VideoPlayer getPlayer(long playerId) {
    VideoPlayer player = videoPlayers.get(playerId);
    if (player == null) {
      String message = "No player found with playerId <" + playerId + ">";
      if (videoPlayers.size() == 0) {
        message += " and no active players created by the plugin.";
      }
      throw new IllegalStateException(message);
    }
    return player;
  }

  @Override
  public void dispose(long playerId) {
    VideoPlayer player = getPlayer(playerId);
    player.dispose();
    videoPlayers.remove(playerId);
    removeBackgroundPlayer(playerId);
  }

  @Override
  public void setMixWithOthers(boolean mixWithOthers) {
    sharedOptions.mixWithOthers = mixWithOthers;
  }

  @Override
  public @NonNull String getLookupKeyForAsset(@NonNull String asset, @Nullable String packageName) {
    return packageName == null
        ? flutterState.keyForAsset.get(asset)
        : flutterState.keyForAssetAndPackageName.get(asset, packageName);
  }

  // Background playback methods
  @Override
  public void enableBackgroundPlayback(long playerId, @Nullable PlatformMediaInfo mediaInfo) {
    VideoPlayer player = getPlayer(playerId);
    ExoPlayer exoPlayer = player.getExoPlayer();
    backgroundEnabledPlayers.add(playerId);

    // Try to set the player on an already-running service first.
    PlaybackService service = PlaybackService.getInstance();
    if (service != null) {
      Log.d(TAG, "Service already running, setting player directly");
      service.setPlayer(exoPlayer,
          mediaInfo != null ? mediaInfo.getTitle() : null,
          mediaInfo != null ? mediaInfo.getArtist() : null,
          mediaInfo != null ? mediaInfo.getArtworkUrl() : null);
    } else {
      // Store references so onServiceConnected can pass them to the service.
      pendingServicePlayer = exoPlayer;
      pendingMediaInfo = mediaInfo;
      Log.d(TAG, "Service not running, starting and storing pending player");
    }
    bindPlaybackService();
  }

  @Override
  public void disableBackgroundPlayback(long playerId) {
    removeBackgroundPlayer(playerId);
  }

  private void removeBackgroundPlayer(long playerId) {
    backgroundEnabledPlayers.remove(playerId);
    if (backgroundEnabledPlayers.isEmpty()) {
      unbindPlaybackService();
    }
  }

  // PiP methods
  @Override
  public boolean isPipSupported() {
    return pipHandler.isPipSupported();
  }

  @Override
  public void enterPip(long playerId) {
    pipHandler.enterPip();
  }

  @Override
  public boolean isPipActive() {
    return pipHandler.isPipActive();
  }

  @Override
  public void setAutoEnterPip(boolean enabled) {
    pipHandler.setAutoEnterPip(enabled);
  }

  // Cache control methods
  @OptIn(markerClass = UnstableApi.class)
  @Override
  public void setCacheMaxSize(long maxSizeBytes) {
    VideoCacheManager.setMaxCacheSize(maxSizeBytes);
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  public void clearCache() {
    if (flutterState != null) {
      VideoCacheManager.clearCache(flutterState.applicationContext);
    }
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  public long getCacheSize() {
    return VideoCacheManager.getCacheSize();
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  public boolean isCacheEnabled() {
    return VideoCacheManager.isEnabled();
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  public void setCacheEnabled(boolean enabled) {
    VideoCacheManager.setEnabled(enabled);
  }

  private interface KeyForAssetFn {
    String get(String asset);
  }

  private interface KeyForAssetAndPackageName {
    String get(String asset, String packageName);
  }

  private static final class FlutterState {
    final Context applicationContext;
    final BinaryMessenger binaryMessenger;
    final KeyForAssetFn keyForAsset;
    final KeyForAssetAndPackageName keyForAssetAndPackageName;
    final TextureRegistry textureRegistry;

    FlutterState(
        Context applicationContext,
        BinaryMessenger messenger,
        KeyForAssetFn keyForAsset,
        KeyForAssetAndPackageName keyForAssetAndPackageName,
        TextureRegistry textureRegistry) {
      this.applicationContext = applicationContext;
      this.binaryMessenger = messenger;
      this.keyForAsset = keyForAsset;
      this.keyForAssetAndPackageName = keyForAssetAndPackageName;
      this.textureRegistry = textureRegistry;
    }

    void startListening(VideoPlayerPlugin methodCallHandler, BinaryMessenger messenger) {
      AndroidVideoPlayerApi.Companion.setUp(messenger, methodCallHandler);
    }

    void stopListening(BinaryMessenger messenger) {
      AndroidVideoPlayerApi.Companion.setUp(messenger, null);
    }
  }
}
