// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static androidx.media3.common.Player.REPEAT_MODE_ALL;
import static androidx.media3.common.Player.REPEAT_MODE_OFF;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.os.Build;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.Tracks;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.analytics.AnalyticsListener;
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector;
import androidx.media3.exoplayer.source.MediaLoadData;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import io.flutter.view.TextureRegistry.SurfaceProducer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * A class responsible for managing video playback using {@link ExoPlayer}.
 *
 * <p>It provides methods to control playback, adjust volume, and handle seeking.
 */
public abstract class VideoPlayer implements VideoPlayerInstanceApi {
  @NonNull protected final VideoPlayerCallbacks videoPlayerEvents;
  @Nullable protected final SurfaceProducer surfaceProducer;
  @Nullable private DisposeHandler disposeHandler;
  @NonNull protected ExoPlayer exoPlayer;
  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi @Nullable protected DefaultTrackSelector trackSelector;

  // Stored for ExoPlayer rebuild when switching decoders.
  @NonNull protected final MediaItem mediaItem;
  @NonNull protected final VideoPlayerOptions options;

  // Stored listener references for removal during ExoPlayer rebuild.
  @NonNull private ExoPlayerEventListener exoPlayerEventListener;
  @NonNull private AnalyticsListener analyticsListener;

  // Decoder tracking.
  @Nullable protected String currentVideoDecoderName;
  @Nullable protected String forcedDecoderName;
  @Nullable private String lastKnownVideoMimeType;

  /** A closure-compatible signature since {@link java.util.function.Supplier} is API level 24. */
  public interface ExoPlayerProvider {
    /**
     * Returns a new {@link ExoPlayer}.
     *
     * @return new instance.
     */
    @NonNull
    ExoPlayer get();
  }

  /** A handler to run when dispose is called. */
  public interface DisposeHandler {
    void onDispose();
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  // Error thrown for this-escape warning on JDK 21+ due to https://bugs.openjdk.org/browse/JDK-8015831.
  // Keeping behavior as-is and addressing the warning could cause a regression: https://github.com/flutter/packages/pull/10193
  @SuppressWarnings("this-escape")
  public VideoPlayer(
      @NonNull VideoPlayerCallbacks events,
      @NonNull MediaItem mediaItem,
      @NonNull VideoPlayerOptions options,
      @Nullable SurfaceProducer surfaceProducer,
      @NonNull ExoPlayerProvider exoPlayerProvider) {
    this.videoPlayerEvents = events;
    this.surfaceProducer = surfaceProducer;
    this.mediaItem = mediaItem;
    this.options = options;
    this.maxPlayerRecoveryAttempts = options.maxPlayerRecoveryAttempts;
    exoPlayer = exoPlayerProvider.get();

    // Try to get the track selector from the ExoPlayer if it was built with one
    if (exoPlayer.getTrackSelector() instanceof DefaultTrackSelector) {
      trackSelector = (DefaultTrackSelector) exoPlayer.getTrackSelector();
    }

    exoPlayer.setMediaItem(mediaItem);
    exoPlayer.prepare();
    exoPlayerEventListener = createExoPlayerEventListener(exoPlayer, surfaceProducer);
    analyticsListener = createAnalyticsListener();
    exoPlayer.addListener(exoPlayerEventListener);
    exoPlayer.addAnalyticsListener(analyticsListener);
    setAudioAttributes(exoPlayer, options.mixWithOthers);
  }

  public void setDisposeHandler(@Nullable DisposeHandler handler) {
    disposeHandler = handler;
  }

  protected int maxPlayerRecoveryAttempts = 3;

  @NonNull
  protected abstract ExoPlayerEventListener createExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @Nullable SurfaceProducer surfaceProducer);

  private static void setAudioAttributes(ExoPlayer exoPlayer, boolean isMixMode) {
    exoPlayer.setAudioAttributes(
        new AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
        !isMixMode);
  }

  @Override
  public void play() {
    exoPlayer.play();
  }

  @Override
  public void pause() {
    exoPlayer.pause();
  }

  @Override
  public void setLooping(boolean looping) {
    exoPlayer.setRepeatMode(looping ? REPEAT_MODE_ALL : REPEAT_MODE_OFF);
  }

  @Override
  public void setVolume(double volume) {
    float bracketedValue = (float) Math.max(0.0, Math.min(1.0, volume));
    exoPlayer.setVolume(bracketedValue);
  }

  @Override
  public void setPlaybackSpeed(double speed) {
    // We do not need to consider pitch and skipSilence for now as we do not handle them and
    // therefore never diverge from the default values.
    final PlaybackParameters playbackParameters = new PlaybackParameters((float) speed);

    exoPlayer.setPlaybackParameters(playbackParameters);
  }

  @Override
  public long getCurrentPosition() {
    return exoPlayer.getCurrentPosition();
  }

  @Override
  public long getBufferedPosition() {
    return exoPlayer.getBufferedPosition();
  }

  @Override
  public void seekTo(long position) {
    exoPlayer.seekTo(position);
  }

  @NonNull
  public ExoPlayer getExoPlayer() {
    return exoPlayer;
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public @NonNull NativeAudioTrackData getAudioTracks() {
    List<ExoPlayerAudioTrackData> audioTracks = new ArrayList<>();

    // Get the current tracks from ExoPlayer
    Tracks tracks = exoPlayer.getCurrentTracks();

    // Iterate through all track groups
    for (int groupIndex = 0; groupIndex < tracks.getGroups().size(); groupIndex++) {
      Tracks.Group group = tracks.getGroups().get(groupIndex);

      // Only process audio tracks
      if (group.getType() == C.TRACK_TYPE_AUDIO) {
        for (int trackIndex = 0; trackIndex < group.length; trackIndex++) {
          Format format = group.getTrackFormat(trackIndex);
          boolean isSelected = group.isTrackSelected(trackIndex);

          // Create audio track data with metadata
          ExoPlayerAudioTrackData audioTrack =
              new ExoPlayerAudioTrackData(
                  (long) groupIndex,
                  (long) trackIndex,
                  format.label,
                  format.language,
                  isSelected,
                  format.bitrate != Format.NO_VALUE ? (long) format.bitrate : null,
                  format.sampleRate != Format.NO_VALUE ? (long) format.sampleRate : null,
                  format.channelCount != Format.NO_VALUE ? (long) format.channelCount : null,
                  format.codecs != null ? format.codecs : null);

          audioTracks.add(audioTrack);
        }
      }
    }
    return new NativeAudioTrackData(audioTracks);
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public void selectAudioTrack(long groupIndex, long trackIndex) {
    if (trackSelector == null) {
      throw new IllegalStateException("Cannot select audio track: track selector is null");
    }

    // Get current tracks
    Tracks tracks = exoPlayer.getCurrentTracks();

    if (groupIndex < 0 || groupIndex >= tracks.getGroups().size()) {
      throw new IllegalArgumentException(
          "Cannot select audio track: groupIndex "
              + groupIndex
              + " is out of bounds (available groups: "
              + tracks.getGroups().size()
              + ")");
    }

    Tracks.Group group = tracks.getGroups().get((int) groupIndex);

    // Verify it's an audio track
    if (group.getType() != C.TRACK_TYPE_AUDIO) {
      throw new IllegalArgumentException(
          "Cannot select audio track: group at index "
              + groupIndex
              + " is not an audio track (type: "
              + group.getType()
              + ")");
    }

    // Verify the track index is valid
    if (trackIndex < 0 || (int) trackIndex >= group.length) {
      throw new IllegalArgumentException(
          "Cannot select audio track: trackIndex "
              + trackIndex
              + " is out of bounds (available tracks in group: "
              + group.length
              + ")");
    }

    // Get the track group and create a selection override
    TrackGroup trackGroup = group.getMediaTrackGroup();
    TrackSelectionOverride override = new TrackSelectionOverride(trackGroup, (int) trackIndex);

    // Apply the track selection override
    trackSelector.setParameters(
        trackSelector.buildUponParameters().setOverrideForType(override).build());
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public @NonNull List<PlatformVideoQuality> getAvailableQualities() {
    List<PlatformVideoQuality> qualities = new ArrayList<>();
    Tracks tracks = exoPlayer.getCurrentTracks();

    for (int groupIndex = 0; groupIndex < tracks.getGroups().size(); groupIndex++) {
      Tracks.Group group = tracks.getGroups().get(groupIndex);
      if (group.getType() == C.TRACK_TYPE_VIDEO) {
        for (int trackIndex = 0; trackIndex < group.length; trackIndex++) {
          Format format = group.getTrackFormat(trackIndex);
          boolean isSelected = group.isTrackSelected(trackIndex);

          PlatformVideoQuality quality =
              new PlatformVideoQuality(
                  format.width > 0 ? (long) format.width : 0L,
                  format.height > 0 ? (long) format.height : 0L,
                  format.bitrate != Format.NO_VALUE ? (long) format.bitrate : 0L,
                  format.codecs,
                  isSelected);
          qualities.add(quality);
        }
      }
    }
    return qualities;
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public @Nullable PlatformVideoQuality getCurrentQuality() {
    Format format = exoPlayer.getVideoFormat();
    if (format == null) {
      return null;
    }
    PlatformVideoQuality quality =
        new PlatformVideoQuality(
            format.width > 0 ? (long) format.width : 0L,
            format.height > 0 ? (long) format.height : 0L,
            format.bitrate != Format.NO_VALUE ? (long) format.bitrate : 0L,
            format.codecs,
            /* isSelected= */ true);
    return quality;
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public void setMaxBitrate(long maxBitrateBps) {
    if (trackSelector == null) {
      return;
    }
    trackSelector.setParameters(
        trackSelector.buildUponParameters().setMaxVideoBitrate((int) maxBitrateBps).build());
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @Override
  public void setMaxResolution(long width, long height) {
    if (trackSelector == null) {
      return;
    }
    trackSelector.setParameters(
        trackSelector
            .buildUponParameters()
            .setMaxVideoSize((int) width, (int) height)
            .build());
  }

  @UnstableApi
  private AnalyticsListener createAnalyticsListener() {
    return new AnalyticsListener() {
      private int lastReportedWidth = -1;
      private int lastReportedHeight = -1;
      private int lastReportedBitrate = -1;

      @Override
      public void onDownstreamFormatChanged(
          @NonNull EventTime eventTime, @NonNull MediaLoadData mediaLoadData) {
        if (mediaLoadData.trackFormat == null) {
          return;
        }
        // Accept TRACK_TYPE_VIDEO (demuxed) or TRACK_TYPE_DEFAULT (muxed HLS)
        // when the format has video dimensions.
        int trackType = mediaLoadData.trackType;
        Format format = mediaLoadData.trackFormat;
        boolean isVideoFormat = (trackType == C.TRACK_TYPE_VIDEO)
            || (trackType == C.TRACK_TYPE_DEFAULT && format.width > 0 && format.height > 0);
        if (!isVideoFormat) {
          return;
        }
        int width = format.width > 0 ? format.width : 0;
        int height = format.height > 0 ? format.height : 0;
        int bitrate = format.bitrate != Format.NO_VALUE ? format.bitrate : 0;
        // Skip duplicate events
        if (width == lastReportedWidth && height == lastReportedHeight
            && bitrate == lastReportedBitrate) {
          return;
        }
        lastReportedWidth = width;
        lastReportedHeight = height;
        lastReportedBitrate = bitrate;
        videoPlayerEvents.onVideoQualityChanged(width, height, bitrate, format.codecs);
      }

      @Override
      public void onVideoDecoderInitialized(
          @NonNull EventTime eventTime,
          @NonNull String decoderName,
          long initializedTimestampMs,
          long initializationDurationMs) {
        currentVideoDecoderName = decoderName;
        boolean isHw = isHardwareDecoder(decoderName);
        videoPlayerEvents.onDecoderChanged(decoderName, isHw);
      }
    };
  }

  // Decoder selection methods

  /**
   * Returns whether a decoder name indicates hardware acceleration.
   * On API 29+ uses MediaCodecInfo; below that uses name heuristics.
   */
  static boolean isHardwareDecoder(@NonNull String decoderName) {
    // Software decoder name prefixes
    return !decoderName.startsWith("OMX.google.")
        && !decoderName.startsWith("c2.android.")
        && !decoderName.startsWith("c2.google.");
  }

  static boolean isSoftwareDecoder(@NonNull String decoderName) {
    return !isHardwareDecoder(decoderName);
  }

  @Override
  public @NonNull List<PlatformVideoDecoder> getAvailableDecoders() {
    List<PlatformVideoDecoder> decoders = new ArrayList<>();
    Format videoFormat = exoPlayer.getVideoFormat();
    String mimeType = null;
    if (videoFormat != null && videoFormat.sampleMimeType != null) {
      mimeType = videoFormat.sampleMimeType;
      lastKnownVideoMimeType = mimeType;
    } else {
      mimeType = lastKnownVideoMimeType;
    }
    if (mimeType == null) {
      return decoders;
    }

    MediaCodecList codecList = new MediaCodecList(MediaCodecList.ALL_CODECS);
    for (MediaCodecInfo codecInfo : codecList.getCodecInfos()) {
      if (codecInfo.isEncoder()) {
        continue;
      }
      String[] supportedTypes = codecInfo.getSupportedTypes();
      for (String type : supportedTypes) {
        if (type.equalsIgnoreCase(mimeType)) {
          String name = codecInfo.getName();
          boolean isHw;
          boolean isSw;
          if (Build.VERSION.SDK_INT >= 29) {
            isHw = codecInfo.isHardwareAccelerated();
            isSw = codecInfo.isSoftwareOnly();
          } else {
            isHw = isHardwareDecoder(name);
            isSw = isSoftwareDecoder(name);
          }
          boolean isSelected = name.equals(currentVideoDecoderName);
          decoders.add(new PlatformVideoDecoder(name, mimeType, isHw, isSw, isSelected));
          break;
        }
      }
    }
    return decoders;
  }

  @Override
  public @Nullable String getCurrentDecoderName() {
    return currentVideoDecoderName;
  }

  @UnstableApi
  @Override
  public void setVideoDecoder(@Nullable String decoderName) {
    this.forcedDecoderName = decoderName;

    // Capture current playback state before touching the player.
    long position = exoPlayer.getCurrentPosition();
    boolean wasPlaying = exoPlayer.isPlaying();
    boolean isLooping = exoPlayer.getRepeatMode() == REPEAT_MODE_ALL;
    float volume = exoPlayer.getVolume();
    float speed = exoPlayer.getPlaybackParameters().speed;

    // Remove all listeners BEFORE stopping/releasing to prevent stale
    // callbacks (errors, state changes) from reaching Dart during teardown.
    exoPlayer.removeListener(exoPlayerEventListener);
    exoPlayer.removeAnalyticsListener(analyticsListener);

    // Release old player.
    exoPlayer.stop();
    exoPlayer.release();

    // Build new player with forced decoder.
    ExoPlayerProvider provider = createExoPlayerProvider(decoderName);
    exoPlayer = provider.get();

    // Recapture track selector.
    if (exoPlayer.getTrackSelector() instanceof DefaultTrackSelector) {
      trackSelector = (DefaultTrackSelector) exoPlayer.getTrackSelector();
    } else {
      trackSelector = null;
    }

    // Restore state.
    exoPlayer.setMediaItem(mediaItem);
    exoPlayer.prepare();
    exoPlayerEventListener = createExoPlayerEventListener(exoPlayer, surfaceProducer);
    analyticsListener = createAnalyticsListener();
    exoPlayer.addListener(exoPlayerEventListener);
    exoPlayer.addAnalyticsListener(analyticsListener);
    setAudioAttributes(exoPlayer, options.mixWithOthers);
    exoPlayer.setRepeatMode(isLooping ? REPEAT_MODE_ALL : REPEAT_MODE_OFF);
    exoPlayer.setVolume(volume);
    exoPlayer.setPlaybackParameters(new PlaybackParameters(speed));
    exoPlayer.seekTo(position);

    // Re-attach surface for texture-based players (handled by subclass).
    onPlayerRebuilt(exoPlayer);

    if (wasPlaying) {
      exoPlayer.play();
    }
  }

  /**
   * Called after the ExoPlayer is rebuilt (e.g. during decoder switch).
   * Subclasses can override to re-attach surfaces.
   */
  protected void onPlayerRebuilt(@NonNull ExoPlayer newPlayer) {
    // Default: no-op. TextureVideoPlayer overrides to re-attach surface.
  }

  /**
   * Creates an ExoPlayerProvider that optionally forces a specific decoder.
   * Subclasses must implement this to build ExoPlayer with the right context.
   */
  @NonNull
  protected abstract ExoPlayerProvider createExoPlayerProvider(@Nullable String forcedDecoderName);

  /**
   * Creates a MediaCodecSelector that prioritizes the given decoder name.
   * If forcedDecoderName is null, returns the default selector.
   */
  @UnstableApi
  @NonNull
  public static MediaCodecSelector createSelectorForDecoder(@Nullable String forcedDecoderName) {
    if (forcedDecoderName == null) {
      return MediaCodecSelector.DEFAULT;
    }
    return (mimeType, requiresSecureDecoder, requiresTunnelingDecoder) -> {
      List<androidx.media3.exoplayer.mediacodec.MediaCodecInfo> defaultList =
          MediaCodecSelector.DEFAULT.getDecoderInfos(
              mimeType, requiresSecureDecoder, requiresTunnelingDecoder);
      // Put the forced decoder first, keep others as fallback
      List<androidx.media3.exoplayer.mediacodec.MediaCodecInfo> reordered = new ArrayList<>();
      for (androidx.media3.exoplayer.mediacodec.MediaCodecInfo info : defaultList) {
        if (info.name.equals(forcedDecoderName)) {
          reordered.add(0, info);
        } else {
          reordered.add(info);
        }
      }
      return Collections.unmodifiableList(reordered);
    };
  }

  public void notifyPipStateChanged(boolean isInPipMode, boolean wasDismissed, int widthDp, int heightDp) {
    videoPlayerEvents.onPipStateChanged(isInPipMode, wasDismissed, widthDp, heightDp);
  }

  public void dispose() {
    if (disposeHandler != null) {
      disposeHandler.onDispose();
    }
    exoPlayer.release();
  }
}
