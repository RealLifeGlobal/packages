// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.pip;

import android.app.Activity;
import android.app.PictureInPictureParams;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;
import android.util.Rational;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

public class PipHandler {
    private static final String TAG = "PipHandler";

    @Nullable
    private Activity activity;
    private boolean autoEnterEnabled = false;
    private Boolean pipSupportedCache = null;

    public PipHandler(@Nullable Activity activity) {
        this.activity = activity;
    }

    /**
     * Sets the listener that receives PiP state changes.
     *
     * <p>Registers the listener with {@link PipCallbackHelper} so the Activity's
     * {@code onPictureInPictureModeChanged} callback reaches the plugin.
     */
    public void setPipStateListener(@NonNull PipCallbackHelper.PipStateListener listener) {
        PipCallbackHelper.setListener(listener);
    }

    /** Returns whether PiP callbacks have been configured by the Activity. */
    public boolean isPipCallbackConfigured() {
        return PipCallbackHelper.isConfigured();
    }

    public void setActivity(@Nullable Activity activity) {
        this.activity = activity;
        // Invalidate cache when activity changes.
        pipSupportedCache = null;
    }

    public boolean isPipSupported() {
        if (activity == null) return false;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false;
        if (pipSupportedCache == null) {
            pipSupportedCache = activity.getPackageManager()
                    .hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE);
        }
        return pipSupportedCache;
    }

    public void enterPip() {
        if (activity == null || !isPipSupported()) return;
        if (!isPipCallbackConfigured()) {
            Log.w(TAG, "PiP callbacks not configured. Extend VideoPlayerActivity or call "
                    + "PipCallbackHelper.onPictureInPictureModeChanged() from your Activity "
                    + "to receive PiP state events in Dart.");
        }
        try {
            PictureInPictureParams.Builder builder = newPipParamsBuilder();
            activity.enterPictureInPictureMode(builder.build());
        } catch (IllegalStateException e) {
            Log.w(TAG, "Failed to enter PiP: " + e.getMessage());
        }
    }

    public boolean isPipActive() {
        if (activity == null) return false;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false;
        return activity.isInPictureInPictureMode();
    }

    public void setAutoEnterPip(boolean enabled) {
        autoEnterEnabled = enabled;
        if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return;
        try {
            PictureInPictureParams.Builder builder = newPipParamsBuilder();
            activity.setPictureInPictureParams(builder.build());
        } catch (IllegalStateException e) {
            Log.w(TAG, "Failed to set auto-enter PiP: " + e.getMessage());
        }
    }

    public boolean isAutoEnterEnabled() {
        return autoEnterEnabled;
    }

    public void onUserLeaveHint() {
        if (autoEnterEnabled && isPipSupported()) {
            enterPip();
        }
    }

    private PictureInPictureParams.Builder newPipParamsBuilder() {
        PictureInPictureParams.Builder builder = new PictureInPictureParams.Builder()
                .setAspectRatio(new Rational(16, 9));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnterEnabled);
            builder.setSeamlessResizeEnabled(true);
        }
        return builder;
    }
}
