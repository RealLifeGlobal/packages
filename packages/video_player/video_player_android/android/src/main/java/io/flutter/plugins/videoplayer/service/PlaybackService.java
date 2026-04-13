// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.service;

import android.content.Intent;
import android.net.Uri;
import android.os.IBinder;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.session.MediaSession;
import androidx.media3.session.MediaSessionService;

public class PlaybackService extends MediaSessionService {
    private static final String TAG = "PlaybackService";
    @Nullable private static PlaybackService instance;
    private MediaSession mediaSession = null;
    private ExoPlayer player = null;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        Log.d(TAG, "PlaybackService created");
    }

    @Nullable
    public static PlaybackService getInstance() {
        return instance;
    }

    public void setPlayer(@NonNull ExoPlayer exoPlayer,
                          @Nullable String title,
                          @Nullable String artist,
                          @Nullable String artworkUrl) {
        // Release any existing session before creating a new one.
        if (mediaSession != null) {
            mediaSession.release();
        }
        this.player = exoPlayer;

        // Set media metadata (title, artist, artwork) on the current MediaItem so
        // Media3's notification provider displays them. replaceMediaItem() updates
        // metadata without interrupting playback.
        if (exoPlayer.getMediaItemCount() > 0) {
            MediaItem currentItem = exoPlayer.getCurrentMediaItem();
            if (currentItem != null) {
                MediaMetadata.Builder metaBuilder = new MediaMetadata.Builder();
                if (title != null) metaBuilder.setTitle(title);
                if (artist != null) metaBuilder.setArtist(artist);
                if (artworkUrl != null) metaBuilder.setArtworkUri(Uri.parse(artworkUrl));
                MediaItem updated = currentItem.buildUpon()
                        .setMediaMetadata(metaBuilder.build())
                        .build();
                exoPlayer.replaceMediaItem(
                        exoPlayer.getCurrentMediaItemIndex(), updated);
            }
        }

        mediaSession = new MediaSession.Builder(this, exoPlayer).build();
        // Explicitly add the session so MediaSessionService manages its notification.
        // Without this, the session created after onCreate() is never discovered by
        // Media3's internal notification manager (onGetSession is only called when a
        // MediaController connects, which may never happen in our flow).
        addSession(mediaSession);
        Log.d(TAG, "MediaSession created and added, player isPlaying=" + exoPlayer.isPlaying()
                + ", hasMediaItems=" + (exoPlayer.getMediaItemCount() > 0));
    }

    @Nullable
    @Override
    public MediaSession onGetSession(@NonNull MediaSession.ControllerInfo controllerInfo) {
        return mediaSession;
    }

    @Override
    public void onTaskRemoved(@Nullable Intent rootIntent) {
        MediaSession session = mediaSession;
        if (session != null) {
            if (session.getPlayer().getPlayWhenReady()) {
                // Keep the service running if the player is playing
                return;
            }
        }
        stopSelf();
    }

    /**
     * Synchronously releases the MediaSession so it can no longer forward
     * commands to the player. Must be called before the ExoPlayer is released
     * to avoid sending messages to a dead thread.
     */
    public void releaseSession() {
        if (mediaSession != null) {
            removeSession(mediaSession);
            mediaSession.release();
            mediaSession = null;
        }
        player = null;
    }

    @Override
    public void onDestroy() {
        releaseSession();
        instance = null;
        super.onDestroy();
    }
}
