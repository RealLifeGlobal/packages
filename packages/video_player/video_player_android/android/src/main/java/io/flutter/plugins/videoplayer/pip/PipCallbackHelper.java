// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.pip;

import androidx.annotation.Nullable;

/**
 * Static bridge for PiP state change callbacks.
 *
 * <p>Activities call {@link #onPictureInPictureModeChanged(boolean, boolean)} from their
 * {@code onPictureInPictureModeChanged} override. The plugin sets a listener via
 * {@link #setListener(PipStateListener)} to receive the events.
 *
 * <p>Users who extend {@code VideoPlayerActivity} get this automatically. Users with custom
 * Activities add one line in their {@code onPictureInPictureModeChanged}:
 * {@code PipCallbackHelper.onPictureInPictureModeChanged(isInPipMode, isFinishing());}
 */
public class PipCallbackHelper {
    /** Listener for PiP state changes. */
    public interface PipStateListener {
        void onPipStateChanged(boolean isInPipMode, boolean wasDismissed, int widthDp, int heightDp);
    }

    @Nullable private static PipStateListener listener;
    private static boolean configured = false;

    /** Sets the listener that receives PiP state changes from the Activity. */
    public static void setListener(@Nullable PipStateListener l) {
        listener = l;
        configured = (l != null);
    }

    /**
     * Call from {@code Activity.onPictureInPictureModeChanged(boolean, Configuration)}.
     *
     * @param isInPipMode whether PiP mode is now active.
     * @param isFinishing whether the Activity is finishing (user dismissed PiP via the X button).
     * @param widthDp the window width in dp from the new Configuration.
     * @param heightDp the window height in dp from the new Configuration.
     */
    public static void onPictureInPictureModeChanged(
            boolean isInPipMode, boolean isFinishing, int widthDp, int heightDp) {
        configured = true;
        if (listener != null) {
            boolean wasDismissed = !isInPipMode && isFinishing;
            listener.onPipStateChanged(isInPipMode, wasDismissed, widthDp, heightDp);
        }
    }

    /** Returns whether PiP callbacks have been configured (Activity is calling the helper). */
    public static boolean isConfigured() {
        return configured;
    }
}
