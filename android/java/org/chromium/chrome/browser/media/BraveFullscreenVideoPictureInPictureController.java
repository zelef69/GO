/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.media;

import android.app.Activity;

import org.chromium.base.Log;
import org.chromium.base.BraveReflectionUtil;
import org.chromium.chrome.browser.youtube_script_injector.BraveYouTubeScriptInjectorNativeHelper;
import org.chromium.content_public.browser.WebContents;

public class BraveFullscreenVideoPictureInPictureController {
    private static final String TAG = "BravePipWrapper";
    /**
     * This variable will be used instead of {@link FullscreenVideoPictureInPictureController}'s
     * variable, that will be deleted in bytecode.
     */
    protected boolean mDismissPending;

    void dismissActivityIfNeeded(Activity activity, /*MetricsEndReason*/ int reason) {
        Log.i(
                TAG,
                "dismissActivityIfNeeded reason=%d inPip=%b dismissPending=%b",
                reason,
                activity.isInPictureInPictureMode(),
                mDismissPending);
        if (reason == 8 /*MetricsEndReason.START*/ || reason == 0 /*MetricsEndReason.RESUME*/) {
            Log.i(TAG, "suppress dismiss for startup/resume reason=%d", reason);
            mDismissPending = false;
            return;
        }
        if ((reason == 6 /*MetricsEndReason.LEFT_FULLSCREEN*/
                        || reason == 7 /*MetricsEndReason.WEB_CONTENTS_LEFT_FULLSCREEN*/)
                && activity.isInPictureInPictureMode()) {
            WebContents webContents =
                    (WebContents)
                            BraveReflectionUtil.invokeMethod(
                                    FullscreenVideoPictureInPictureController.class,
                                    this,
                                    "getWebContents");
            Boolean isPlaying =
                    (Boolean)
                            BraveReflectionUtil.getField(
                                    FullscreenVideoPictureInPictureController.class,
                                    "mIsPlaying",
                                    this);
            boolean activeFullscreen =
                    webContents != null && webContents.hasActiveEffectivelyFullscreenVideo();
            boolean fullscreenRequested =
                    webContents != null
                            && BraveYouTubeScriptInjectorNativeHelper.hasFullscreenBeenRequested(
                                    webContents);
            Log.i(
                    TAG,
                    "fullscreen-loss in PiP reason=%d playing=%b activeFullscreen=%b requested=%b",
                    reason,
                    Boolean.TRUE.equals(isPlaying),
                    activeFullscreen,
                    fullscreenRequested);
            if (webContents != null
                    && !activeFullscreen
                    && (Boolean.TRUE.equals(isPlaying) || fullscreenRequested)) {
                Log.i(
                        TAG,
                        "keep PiP alive without forcing fullscreen re-request reason=%d",
                        reason);
                mDismissPending = false;
                return;
            }
        }
        Log.i(TAG, "forward dismiss to chromium controller reason=%d", reason);
        BraveReflectionUtil.invokeMethod(
                FullscreenVideoPictureInPictureController.class,
                this,
                "dismissActivityIfNeeded",
                Activity.class,
                activity,
                int.class,
                reason);
    }
}
