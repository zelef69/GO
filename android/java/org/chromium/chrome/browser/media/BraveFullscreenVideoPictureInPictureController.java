/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.media;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.util.Log;

import org.chromium.base.BraveReflectionUtil;
import org.chromium.chrome.browser.app.BraveActivity;
import org.chromium.chrome.browser.youtube_script_injector.BraveYouTubeScriptInjectorNativeHelper;
import org.chromium.content_public.browser.WebContents;

public class BraveFullscreenVideoPictureInPictureController {
    /**
     * This variable will be used instead of {@link FullscreenVideoPictureInPictureController}'s
     * variable, that will be deleted in bytecode.
     */
    protected boolean mDismissPending;

    public void attemptPictureInPicture() {
        Activity activity =
                (Activity)
                        BraveReflectionUtil.getField(
                                FullscreenVideoPictureInPictureController.class,
                                "mActivity",
                                this);
        WebContents webContents =
                (WebContents)
                        BraveReflectionUtil.invokeMethod(
                                FullscreenVideoPictureInPictureController.class,
                                this,
                                "getWebContents");
        boolean hasFeature =
                activity != null
                        && activity.getPackageManager()
                                .hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE);
        boolean hasFullscreenVideo =
                webContents != null && webContents.hasActiveEffectivelyFullscreenVideo();
        boolean recentFullscreenVideo =
                webContents != null
                        && BraveYouTubeScriptInjectorNativeHelper
                                .hasRecentEffectivelyFullscreenVideo(webContents);
        boolean fullscreenRequested =
                webContents != null
                        && BraveYouTubeScriptInjectorNativeHelper.hasFullscreenBeenRequested(
                                webContents);
        boolean pipAllowed =
                webContents != null && webContents.isPictureInPictureAllowedForFullscreenVideo();
        Log.i(
                "OneTabTubePerf",
                "event=pip_attempt_state"
                        + " activity="
                        + (activity != null ? activity.getClass().getSimpleName() : "null")
                        + " feature="
                        + hasFeature
                        + " fullscreen="
                        + hasFullscreenVideo
                        + " recent_fullscreen="
                        + recentFullscreenVideo
                        + " requested="
                        + fullscreenRequested
                        + " allowed="
                        + pipAllowed
                        + " in_pip="
                        + (activity != null && activity.isInPictureInPictureMode())
                        + " changing="
                        + (activity != null && activity.isChangingConfigurations())
                        + " finishing="
                        + (activity != null && activity.isFinishing())
                        + " web_contents="
                        + (webContents != null));
        if (activity instanceof BraveActivity braveActivity
                && hasFeature
                && pipAllowed
                && !hasFullscreenVideo
                && recentFullscreenVideo
                && braveActivity.requestDirectPictureInPictureUsingRecentFullscreen(
                        "controller_recent_fullscreen")) {
            Log.i("OneTabTubePerf", "event=pip_direct_recent_fullscreen_fallback");
            return;
        }
        BraveReflectionUtil.invokeMethod(
                FullscreenVideoPictureInPictureController.class, this, "attemptPictureInPicture");
    }

    void dismissActivityIfNeeded(Activity activity, /*MetricsEndReason*/ int reason) {
        if (reason == 8 /*MetricsEndReason.START*/ || reason == 0 /*MetricsEndReason.RESUME*/) {
            mDismissPending = false;
            return;
        }
        WebContents webContents =
                (WebContents)
                        BraveReflectionUtil.invokeMethod(
                                FullscreenVideoPictureInPictureController.class,
                                this,
                                "getWebContents");
        if (activity instanceof BraveActivity braveActivity
                && (reason == 6 /*MetricsEndReason.LEFT_FULLSCREEN*/
                        || reason == 7 /*MetricsEndReason.WEB_CONTENTS_LEFT_FULLSCREEN*/)
                && braveActivity.shouldTreatPictureInPictureFullscreenLossAsTransient(
                        webContents, reason)) {
            braveActivity.handleTransientPictureInPictureFullscreenLoss(reason);
            mDismissPending = false;
            return;
        }
        if (activity instanceof BraveActivity braveActivity
                && (reason == 6 /*MetricsEndReason.LEFT_FULLSCREEN*/
                        || reason == 7 /*MetricsEndReason.WEB_CONTENTS_LEFT_FULLSCREEN*/)
                && braveActivity.shouldRepairFullscreenAfterPictureInPictureLoss()) {
            Log.i("OneTabTubePerf", "event=pip_fullscreen_lost_detected:" + reason);
            braveActivity.onPictureInPictureFullscreenLost(reason);
            mDismissPending = false;
            return;
        }
        boolean suppressCleanup = BraveActivity.shouldSuppressPictureInPictureStopCleanup(activity);
        Log.i(
                "OneTabTubePerf",
                "event=pip_dismiss_eval reason="
                        + reason
                        + " suppress="
                        + suppressCleanup
                        + " activity="
                        + (activity != null ? activity.getClass().getSimpleName() : "null"));
        if (suppressCleanup) {
            Log.i("OneTabTubePerf", "event=pip_cleanup_suppressed:dismiss reason=" + reason);
            mDismissPending = false;
            return;
        }
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
