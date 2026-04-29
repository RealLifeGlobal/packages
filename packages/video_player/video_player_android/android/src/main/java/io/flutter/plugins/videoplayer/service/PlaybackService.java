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
import androidx.media3.common.ForwardingPlayer;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.session.CommandButton;
import androidx.media3.session.DefaultMediaNotificationProvider;
import androidx.media3.session.MediaSession;
import androidx.media3.session.MediaSessionService;
import com.google.common.collect.ImmutableList;

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
    // Default skip intervals chosen to match the in-app rewind / fast-forward
    // controls (audio_player_controller.dart: 15s rewind, 30s fast-forward).
    // Used when the Dart side does not specify explicit values.
    private static final long DEFAULT_SKIP_BACKWARD_MS = 15_000L;
    private static final long DEFAULT_SKIP_FORWARD_MS = 30_000L;

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
                          @Nullable String artworkUrl,
                          @Nullable Long skipBackwardIntervalMs,
                          @Nullable Long skipForwardIntervalMs) {
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

        // Wrap the ExoPlayer in a ForwardingPlayer that:
        //   1. Reports the configured seek-back / seek-forward increments so
        //      the rewind / fast-forward custom-layout buttons (below) jump by
        //      the right amount when tapped.
        //   2. Hides COMMAND_SEEK_TO_PREVIOUS / _NEXT (and the MEDIA_ITEM
        //      variants). Media3's DefaultMediaNotificationProvider builds
        //      its prev/next slots from those commands, and with a single-
        //      item queue "previous" maps to seekToDefaultPosition() which
        //      jumps to 0 — the exact regression we are fixing. By dropping
        //      those commands, the prev/next slots are freed for the custom
        //      rewind / fast-forward buttons we add via setCustomLayout.
        long backwardMs = skipBackwardIntervalMs != null
                ? skipBackwardIntervalMs : DEFAULT_SKIP_BACKWARD_MS;
        long forwardMs = skipForwardIntervalMs != null
                ? skipForwardIntervalMs : DEFAULT_SKIP_FORWARD_MS;
        Player sessionPlayer =
                new SkipIntervalForwardingPlayer(exoPlayer, backwardMs, forwardMs);

        // Build explicit rewind / fast-forward CommandButtons. Without this,
        // the default notification provider only renders prev/next slots —
        // which we just removed — and the user is left with play/pause only.
        // Each button references Player.COMMAND_SEEK_BACK / _FORWARD, which
        // route to the ForwardingPlayer's overridden seek increments. The
        // CommandButton.Builder(int icon) constructor takes a predefined
        // CommandButton.ICON_* constant (the no-arg Builder() and
        // setIconResId(int) are deprecated since Media3 1.4 and emit
        // -Werror warnings under the plugin's javac settings).
        CommandButton rewindButton =
                new CommandButton.Builder(pickSkipBackIcon(backwardMs))
                        .setPlayerCommand(Player.COMMAND_SEEK_BACK)
                        .setSlots(CommandButton.SLOT_BACK)
                        .setDisplayName("Rewind")
                        .build();
        CommandButton forwardButton =
                new CommandButton.Builder(pickSkipForwardIcon(forwardMs))
                        .setPlayerCommand(Player.COMMAND_SEEK_FORWARD)
                        .setSlots(CommandButton.SLOT_FORWARD)
                        .setDisplayName("Fast forward")
                        .build();

        // Set the buttons via setMediaButtonPreferences (NOT setCustomLayout).
        // Verified by decompiling Media3 1.9.2's MediaNotificationManager:
        //
        //   updateNotification(...) {
        //     ...
        //     mediaController.getMediaButtonPreferences()  // <-- THIS
        //     provider.createNotification(session, mediaButtonPreferences, ...)
        //   }
        //
        // The DefaultMediaNotificationProvider then runs them through
        // CommandButton.getCustomLayoutFromMediaButtonPreferences(list, true, true)
        // and only the buttons whose slots include SLOT_BACK / SLOT_FORWARD
        // populate the notification's prev/next slots — which is why we set
        // those slots on each button above.
        //
        // setCustomLayout(...) only flows to legacy MediaController integrations
        // and does NOT drive the system media notification, so using it alone
        // would result in the user seeing only play/pause.
        mediaSession = new MediaSession.Builder(this, sessionPlayer)
                .setMediaButtonPreferences(ImmutableList.of(rewindButton, forwardButton))
                .build();
        // Explicitly add the session so MediaSessionService manages its notification.
        // Without this, the session created after onCreate() is never discovered by
        // Media3's internal notification manager (onGetSession is only called when a
        // MediaController connects, which may never happen in our flow).
        addSession(mediaSession);
        Log.d(TAG, "MediaSession created and added, player isPlaying=" + exoPlayer.isPlaying()
                + ", hasMediaItems=" + (exoPlayer.getMediaItemCount() > 0)
                + ", seekBackMs=" + backwardMs + ", seekForwardMs=" + forwardMs);
    }

    /**
     * Picks the closest CommandButton.ICON_SKIP_BACK_* constant. Falls back
     * to the generic ICON_REWIND glyph when the interval doesn't match any
     * badged variant exactly.
     */
    private static int pickSkipBackIcon(long intervalMs) {
        long seconds = Math.round(intervalMs / 1000.0);
        if (seconds <= 5) return CommandButton.ICON_SKIP_BACK_5;
        if (seconds <= 10) return CommandButton.ICON_SKIP_BACK_10;
        if (seconds <= 15) return CommandButton.ICON_SKIP_BACK_15;
        if (seconds <= 30) return CommandButton.ICON_SKIP_BACK_30;
        return CommandButton.ICON_REWIND;
    }

    /**
     * Picks the closest CommandButton.ICON_SKIP_FORWARD_* constant. Falls
     * back to the generic ICON_FAST_FORWARD glyph when the interval doesn't
     * match any badged variant exactly.
     */
    private static int pickSkipForwardIcon(long intervalMs) {
        long seconds = Math.round(intervalMs / 1000.0);
        if (seconds <= 5) return CommandButton.ICON_SKIP_FORWARD_5;
        if (seconds <= 10) return CommandButton.ICON_SKIP_FORWARD_10;
        if (seconds <= 15) return CommandButton.ICON_SKIP_FORWARD_15;
        if (seconds <= 30) return CommandButton.ICON_SKIP_FORWARD_30;
        return CommandButton.ICON_FAST_FORWARD;
    }

    /**
     * ForwardingPlayer that overrides seek increments and trims SEEK_TO_NEXT /
     * SEEK_TO_PREVIOUS commands so the system media notification renders small-
     * jump rewind / fast-forward buttons (rather than prev/next which, for a
     * single-item queue, collapse to "seek to start").
     */
    private static final class SkipIntervalForwardingPlayer extends ForwardingPlayer {
        private final long seekBackMs;
        private final long seekForwardMs;

        SkipIntervalForwardingPlayer(@NonNull Player wrapped,
                                     long seekBackMs,
                                     long seekForwardMs) {
            super(wrapped);
            this.seekBackMs = seekBackMs;
            this.seekForwardMs = seekForwardMs;
        }

        @Override
        public long getSeekBackIncrement() {
            return seekBackMs;
        }

        @Override
        public long getSeekForwardIncrement() {
            return seekForwardMs;
        }

        @Override
        @NonNull
        public Commands getAvailableCommands() {
            Commands base = super.getAvailableCommands();
            return new Commands.Builder()
                    .addAll(base)
                    .remove(COMMAND_SEEK_TO_PREVIOUS)
                    .remove(COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                    .remove(COMMAND_SEEK_TO_NEXT)
                    .remove(COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                    .add(COMMAND_SEEK_BACK)
                    .add(COMMAND_SEEK_FORWARD)
                    .build();
        }

        @Override
        public boolean isCommandAvailable(int command) {
            switch (command) {
                case COMMAND_SEEK_TO_PREVIOUS:
                case COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM:
                case COMMAND_SEEK_TO_NEXT:
                case COMMAND_SEEK_TO_NEXT_MEDIA_ITEM:
                    return false;
                case COMMAND_SEEK_BACK:
                case COMMAND_SEEK_FORWARD:
                    return true;
                default:
                    return super.isCommandAvailable(command);
            }
        }
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
