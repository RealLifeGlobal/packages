// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.platformview;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.MediaItem;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy;
import io.flutter.plugins.videoplayer.ExoPlayerEventListener;
import io.flutter.plugins.videoplayer.VideoAsset;
import io.flutter.plugins.videoplayer.VideoPlayer;
import io.flutter.plugins.videoplayer.VideoPlayerCallbacks;
import io.flutter.plugins.videoplayer.VideoPlayerOptions;
import io.flutter.view.TextureRegistry.SurfaceProducer;

/**
 * A subclass of {@link VideoPlayer} that adds functionality related to platform view as a way of
 * displaying the video in the app.
 */
public class PlatformViewVideoPlayer extends VideoPlayer {
  // Stored for ExoPlayer rebuild (decoder switching).
  @NonNull private final Context context;
  @NonNull private final VideoAsset asset;

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @VisibleForTesting
  public PlatformViewVideoPlayer(
      @NonNull Context context,
      @NonNull VideoAsset asset,
      @NonNull VideoPlayerCallbacks events,
      @NonNull MediaItem mediaItem,
      @NonNull VideoPlayerOptions options,
      @NonNull ExoPlayerProvider exoPlayerProvider) {
    super(events, mediaItem, options, /* surfaceProducer */ null, exoPlayerProvider);
    this.context = context;
    this.asset = asset;
  }

  /**
   * Creates a platform view video player.
   *
   * @param context application context.
   * @param events event callbacks.
   * @param asset asset to play.
   * @param options options for playback.
   * @return a video player instance.
   */
  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @NonNull
  public static PlatformViewVideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull VideoAsset asset,
      @NonNull VideoPlayerOptions options) {
    return new PlatformViewVideoPlayer(
        context,
        asset,
        events,
        asset.getMediaItem(),
        options,
        buildExoPlayerProvider(context, asset, options, null));
  }

  @NonNull
  @Override
  protected ExoPlayerEventListener createExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @Nullable SurfaceProducer surfaceProducer) {
    return new PlatformViewExoPlayerEventListener(exoPlayer, videoPlayerEvents,
        maxPlayerRecoveryAttempts);
  }

  @UnstableApi
  @NonNull
  @Override
  protected ExoPlayerProvider createExoPlayerProvider(@Nullable String forcedDecoderName) {
    return buildExoPlayerProvider(context, asset, options, forcedDecoderName);
  }

  @UnstableApi
  @NonNull
  private static ExoPlayerProvider buildExoPlayerProvider(
      @NonNull Context context,
      @NonNull VideoAsset asset,
      @NonNull VideoPlayerOptions options,
      @Nullable String forcedDecoderName) {
    return () -> {
      androidx.media3.exoplayer.trackselection.DefaultTrackSelector trackSelector =
          new androidx.media3.exoplayer.trackselection.DefaultTrackSelector(context);
      androidx.media3.exoplayer.source.MediaSource.Factory mediaSourceFactory =
          asset.getMediaSourceFactory(context);
      if (mediaSourceFactory
          instanceof androidx.media3.exoplayer.source.DefaultMediaSourceFactory) {
        ((androidx.media3.exoplayer.source.DefaultMediaSourceFactory) mediaSourceFactory)
            .setLoadErrorHandlingPolicy(
                new DefaultLoadErrorHandlingPolicy(options.maxLoadRetries));
      }
      DefaultRenderersFactory renderersFactory =
          new DefaultRenderersFactory(context)
              .setEnableDecoderFallback(true)
              .setMediaCodecSelector(createSelectorForDecoder(forcedDecoderName));
      ExoPlayer.Builder builder =
          new ExoPlayer.Builder(context, renderersFactory)
              .setTrackSelector(trackSelector)
              .setMediaSourceFactory(mediaSourceFactory);
      return builder.build();
    };
  }
}
