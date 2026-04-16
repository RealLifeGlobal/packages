// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.service;

import android.app.ForegroundServiceStartNotAllowedException;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.Uri;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.app.ServiceCompat;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.session.DefaultMediaNotificationProvider;
import androidx.media3.session.MediaSession;
import androidx.media3.session.MediaSessionService;

@OptIn(markerClass = UnstableApi.class)
public class PlaybackService extends MediaSessionService {
    private static final String TAG = "PlaybackService";
    // Reuse the notification id and channel id that Media3's
    // DefaultMediaNotificationProvider uses so that when Media3 posts its real
    // media-style notification it replaces our placeholder in place, and only
    // one notification channel appears under the app's notification settings.
    private static final int PLACEHOLDER_NOTIFICATION_ID =
            DefaultMediaNotificationProvider.DEFAULT_NOTIFICATION_ID;
    private static final String PLACEHOLDER_CHANNEL_ID =
            DefaultMediaNotificationProvider.DEFAULT_CHANNEL_ID;
    @Nullable private static PlaybackService instance;
    private MediaSession mediaSession = null;
    private ExoPlayer player = null;
    private boolean placeholderForegroundActive = false;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        createPlaceholderChannel();
        Log.d(TAG, "PlaybackService created");
    }

    @Override
    public int onStartCommand(@Nullable Intent intent, int flags, int startId) {
        // Satisfy the startForegroundService() -> startForeground() 5-second
        // contract immediately. Media3's MediaNotificationManager posts the
        // real media-style notification once a session with a playing player
        // is added, replacing (or superseding) this placeholder. Without this,
        // if setPlayer()/addSession() is delayed or disableBackgroundPlayback()
        // races the start, the kernel kills the app with RemoteServiceException.
        if (!placeholderForegroundActive) {
            Notification placeholder = buildPlaceholderNotification();
            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                    ? ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    : 0;
            try {
                ServiceCompat.startForeground(
                        this, PLACEHOLDER_NOTIFICATION_ID, placeholder, type);
                placeholderForegroundActive = true;
            } catch (Exception e) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                        && e instanceof ForegroundServiceStartNotAllowedException) {
                    Log.w(TAG, "Foreground service start not allowed (app is in background), "
                            + "stopping service gracefully", e);
                    stopSelf();
                    return START_NOT_STICKY;
                }
                throw e;
            }
        }
        return super.onStartCommand(intent, flags, startId);
    }

    private void createPlaceholderChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null
                || manager.getNotificationChannel(PLACEHOLDER_CHANNEL_ID) != null) {
            // Channel already exists (usually because Media3's
            // DefaultMediaNotificationProvider already created it).
            return;
        }
        // Match Media3's default channel name so only one channel appears in
        // the app's notification settings. Media3's provider will reuse this
        // channel if it already exists when it goes to post its notification.
        NotificationChannel channel = new NotificationChannel(
                PLACEHOLDER_CHANNEL_ID,
                "Now playing",
                NotificationManager.IMPORTANCE_LOW);
        channel.setShowBadge(false);
        manager.createNotificationChannel(channel);
    }

    private Notification buildPlaceholderNotification() {
        NotificationCompat.Builder builder =
                new NotificationCompat.Builder(this, PLACEHOLDER_CHANNEL_ID)
                        .setSmallIcon(android.R.drawable.ic_media_play)
                        .setContentTitle(getApplicationInfo()
                                .loadLabel(getPackageManager()).toString())
                        .setOngoing(true)
                        .setPriority(NotificationCompat.PRIORITY_LOW)
                        .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
                        .setShowWhen(false);
        return builder.build();
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
        // Release the session and clear the placeholder notification explicitly
        // before stopSelf() so the user never sees a lingering "Playback"
        // notification after swiping the app from recents.
        releaseSession();
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
        if (placeholderForegroundActive) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE);
            placeholderForegroundActive = false;
        }
        // Belt-and-braces: stopForeground operates on the service's internal
        // "current foreground notification" reference, which can drift after
        // MediaSessionService's own teardown runs. Cancel by id as well so the
        // user never sees a lingering placeholder if the task is swiped away.
        NotificationManagerCompat.from(this).cancel(PLACEHOLDER_NOTIFICATION_ID);
    }

    @Override
    public void onDestroy() {
        releaseSession();
        instance = null;
        super.onDestroy();
    }
}
