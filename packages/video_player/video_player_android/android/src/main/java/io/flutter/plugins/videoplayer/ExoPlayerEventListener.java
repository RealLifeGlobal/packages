// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.C;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.Tracks;
import androidx.media3.exoplayer.ExoPlayer;

public abstract class ExoPlayerEventListener implements Player.Listener {
  private boolean isInitialized = false;
  protected final ExoPlayer exoPlayer;
  protected final VideoPlayerCallbacks events;
  private final int maxPlayerRecoveryAttempts;
  private int recoveryAttemptCount = 0;

  protected enum RotationDegrees {
    ROTATE_0(0),
    ROTATE_90(90),
    ROTATE_180(180),
    ROTATE_270(270);

    private final int degrees;

    RotationDegrees(int degrees) {
      this.degrees = degrees;
    }

    public static RotationDegrees fromDegrees(int degrees) {
      for (RotationDegrees rotationDegrees : RotationDegrees.values()) {
        if (rotationDegrees.degrees == degrees) {
          return rotationDegrees;
        }
      }
      throw new IllegalArgumentException("Invalid rotation degrees specified: " + degrees);
    }

    public int getDegrees() {
      return this.degrees;
    }
  }

  public ExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer,
      @NonNull VideoPlayerCallbacks events,
      int maxPlayerRecoveryAttempts) {
    this.exoPlayer = exoPlayer;
    this.events = events;
    this.maxPlayerRecoveryAttempts = maxPlayerRecoveryAttempts;
  }

  protected abstract void sendInitialized();

  @Override
  public void onPlaybackStateChanged(final int playbackState) {
    PlatformPlaybackState platformState = PlatformPlaybackState.UNKNOWN;
    switch (playbackState) {
      case Player.STATE_BUFFERING:
        platformState = PlatformPlaybackState.BUFFERING;
        break;
      case Player.STATE_READY:
        platformState = PlatformPlaybackState.READY;
        recoveryAttemptCount = 0;
        if (!isInitialized) {
          isInitialized = true;
          sendInitialized();
        }
        break;
      case Player.STATE_ENDED:
        platformState = PlatformPlaybackState.ENDED;
        break;
      case Player.STATE_IDLE:
        platformState = PlatformPlaybackState.IDLE;
        break;
    }
    events.onPlaybackStateChanged(platformState);
  }

  @Override
  public void onPlayerError(@NonNull final PlaybackException error) {
    if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
      // See
      // https://exoplayer.dev/live-streaming.html#behindlivewindowexception-and-error_code_behind_live_window
      exoPlayer.seekToDefaultPosition();
      exoPlayer.prepare();
    } else if (isTransientNetworkError(error)) {
      recoveryAttemptCount++;
      if (recoveryAttemptCount <= maxPlayerRecoveryAttempts) {
        // Transient network errors (e.g. airplane mode, connection timeout) are
        // recoverable. Re-prepare the player so it retries when network returns.
        exoPlayer.prepare();
      } else {
        events.onError("VideoError", "Video player had error " + error, null);
      }
    } else {
      events.onError("VideoError", "Video player had error " + error, null);
    }
  }

  private boolean isTransientNetworkError(@NonNull PlaybackException error) {
    int code = error.errorCode;
    return code == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED
        || code == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT
        || code == PlaybackException.ERROR_CODE_IO_UNSPECIFIED;
  }

  @Override
  public void onIsPlayingChanged(boolean isPlaying) {
    events.onIsPlayingStateUpdate(isPlaying);
  }

  @Override
  public void onTracksChanged(@NonNull Tracks tracks) {
    // Find the currently selected audio track and notify
    String selectedTrackId = findSelectedAudioTrackId(tracks);
    events.onAudioTrackChanged(selectedTrackId);
  }

  /**
   * Finds the ID of the currently selected audio track.
   *
   * @param tracks The current tracks
   * @return The track ID in format "groupIndex_trackIndex", or null if no audio track is selected
   */
  @Nullable
  private String findSelectedAudioTrackId(@NonNull Tracks tracks) {
    int groupIndex = 0;
    for (Tracks.Group group : tracks.getGroups()) {
      if (group.getType() == C.TRACK_TYPE_AUDIO && group.isSelected()) {
        // Find the selected track within this group
        for (int i = 0; i < group.length; i++) {
          if (group.isTrackSelected(i)) {
            return groupIndex + "_" + i;
          }
        }
      }
      groupIndex++;
    }
    return null;
  }
}
