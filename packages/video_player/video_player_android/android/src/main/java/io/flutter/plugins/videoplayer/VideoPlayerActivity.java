// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.res.Configuration;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.plugins.videoplayer.pip.PipCallbackHelper;

/**
 * Convenience Activity that bridges PiP callbacks to the video player plugin.
 *
 * <p>Extend this instead of {@link FlutterActivity} to get automatic PiP state events.
 * If you have a custom Activity, call
 * {@link PipCallbackHelper#onPictureInPictureModeChanged(boolean, boolean, int, int)}
 * from your own {@code onPictureInPictureModeChanged} override instead.
 */
public class VideoPlayerActivity extends FlutterActivity {
    @Override
    public void onPictureInPictureModeChanged(boolean isInPipMode, Configuration newConfig) {
        super.onPictureInPictureModeChanged(isInPipMode, newConfig);
        PipCallbackHelper.onPictureInPictureModeChanged(
                isInPipMode, isFinishing(), newConfig.screenWidthDp, newConfig.screenHeightDp);
    }
}
