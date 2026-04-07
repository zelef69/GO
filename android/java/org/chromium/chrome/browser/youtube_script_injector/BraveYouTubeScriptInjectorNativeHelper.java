/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.youtube_script_injector;

import android.app.Activity;
import org.jni_zero.CalledByNative;
import org.jni_zero.JNINamespace;
import org.jni_zero.NativeMethods;

import org.chromium.base.Log;
import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.browser.app.BraveActivity;
import org.chromium.content_public.browser.WebContents;
import org.chromium.ui.base.WindowAndroid;

/**
 * Helper to interact with native methods. Check brave_youtube_script_injector_native_helper.{h|cc}.
 */
@JNINamespace("youtube_script_injector")
@NullMarked
public class BraveYouTubeScriptInjectorNativeHelper {
    private static final String TAG = "YouTubeNativeHelper";
    private static final long INITIAL_PIP_RETRY_MS = 150L;
    private static final long REENTRY_PIP_RETRY_MS = 250L;
    private static final int INITIAL_PIP_RETRY_COUNT = 1;
    private static final int REENTRY_PIP_RETRY_COUNT = 4;

    public static void setFullscreen(WebContents webContents) {
        final WindowAndroid windowAndroid = webContents.getTopLevelNativeWindow();
        if (windowAndroid != null) {
            final Activity activity = windowAndroid.getActivity().get();
            if (activity instanceof BraveActivity braveActivity) {
                braveActivity.onManualPictureInPictureEntryRequested();
            }
        }
        BraveYouTubeScriptInjectorNativeHelperJni.get().setFullscreen(webContents);
    }

    public static void exitFullscreen(WebContents webContents) {
        BraveYouTubeScriptInjectorNativeHelperJni.get().exitFullscreen(webContents);
    }

    public static boolean hasFullscreenBeenRequested(WebContents webContents) {
        return BraveYouTubeScriptInjectorNativeHelperJni.get()
                .hasFullscreenBeenRequested(webContents);
    }

    public static boolean isPictureInPictureAvailable(WebContents webContents) {
        return BraveYouTubeScriptInjectorNativeHelperJni.get()
                .isPictureInPictureAvailable(webContents);
    }

    public static boolean play(WebContents webContents) {
        return BraveYouTubeScriptInjectorNativeHelperJni.get().play(webContents);
    }

    public static boolean pause(WebContents webContents) {
        return BraveYouTubeScriptInjectorNativeHelperJni.get().pause(webContents);
    }

    public static boolean seekBy(WebContents webContents, int offsetSeconds) {
        return BraveYouTubeScriptInjectorNativeHelperJni.get()
                .seekBy(webContents, offsetSeconds);
    }

    public static boolean next(WebContents webContents) {
        return BraveYouTubeScriptInjectorNativeHelperJni.get()
                .next(webContents, shouldPreserveVideoPresentation(webContents));
    }

    public static boolean previous(WebContents webContents) {
        return BraveYouTubeScriptInjectorNativeHelperJni.get()
                .previous(webContents, shouldPreserveVideoPresentation(webContents));
    }

    private static boolean shouldPreserveVideoPresentation(WebContents webContents) {
        final WindowAndroid windowAndroid = webContents.getTopLevelNativeWindow();
        if (windowAndroid == null) return false;

        final Activity activity = windowAndroid.getActivity().get();
        if (!(activity instanceof BraveActivity braveActivity)) return false;

        return braveActivity.isInPictureInPictureMode();
    }

    private static void attemptPictureInPictureWhenFullscreenReady(
            WebContents webContents,
            Activity activity,
            BraveActivity braveActivity,
            long retryDelayMs,
            int remainingRetries) {
        if (activity.isChangingConfigurations() || activity.isFinishing()) return;

        if (braveActivity.isInPictureInPictureMode()) {
            braveActivity.refreshPictureInPictureParamsForCurrentVideo();
            Log.i(TAG, "Skip delayed enterPictureInPicture because activity is already in PiP.");
            return;
        }

        final boolean activeFullscreen = webContents.hasActiveEffectivelyFullscreenVideo();
        if (!activeFullscreen) {
            if (remainingRetries <= 0) {
                Log.i(
                        TAG,
                        "Proceed enterPictureInPicture without fullscreen lock after retries are exhausted.");
                braveActivity.refreshPictureInPictureParamsForCurrentVideo();
                braveActivity.attemptPictureInPictureForCurrentVideo();
                return;
            }

            Log.i(
                    TAG,
                    "Delay enterPictureInPicture retry because fullscreen state is not visible to Java yet. remaining_retries=%d",
                    remainingRetries);
            PostTask.postDelayedTask(
                    TaskTraits.UI_BEST_EFFORT,
                    () ->
                            attemptPictureInPictureWhenFullscreenReady(
                                    webContents,
                                    activity,
                                    braveActivity,
                                    retryDelayMs,
                                    remainingRetries - 1),
                    retryDelayMs);
            return;
        }

        Log.i(
                TAG,
                "Proceed enterPictureInPicture with fullscreen visible to Java. remaining_retries=%d",
                remainingRetries);
        braveActivity.refreshPictureInPictureParamsForCurrentVideo();
        braveActivity.attemptPictureInPictureForCurrentVideo();
    }

    /**
     * @noinspection unused
     */
    @CalledByNative
    public static void enterPictureInPicture(WebContents webContents) {
        final WindowAndroid windowAndroid = webContents.getTopLevelNativeWindow();
        if (windowAndroid != null) {
            final Activity activity = windowAndroid.getActivity().get();
            // Don't PiP if the activity is going to be restarted,
            // or if the activity is finishing.
            if (activity == null || activity.isChangingConfigurations() || activity.isFinishing()) {
                return;
            }
            if (activity instanceof final BraveActivity braveActivity) {
                // Resume the media session when the transition completes.
                final boolean activeFullscreen = webContents.hasActiveEffectivelyFullscreenVideo();
                Log.i(
                        TAG,
                        "enterPictureInPicture helper available=%b requested=%b active_fullscreen=%b in_pip=%b",
                        isPictureInPictureAvailable(webContents),
                        hasFullscreenBeenRequested(webContents),
                        activeFullscreen,
                        braveActivity.isInPictureInPictureMode());
                if (braveActivity.isInPictureInPictureMode()) {
                    braveActivity.refreshPictureInPictureParamsForCurrentVideo();
                    Log.i(TAG, "Skip enterPictureInPicture because activity is already in PiP.");
                    return;
                }
                braveActivity.resumeMediaSession(true);
                final boolean recentWatchPageReturn =
                        braveActivity.wasRecentlyReturnedToWatchPageAfterPictureInPictureExit();
                final long retryDelayMs =
                        recentWatchPageReturn ? REENTRY_PIP_RETRY_MS : INITIAL_PIP_RETRY_MS;
                final int retryCount =
                        activeFullscreen
                                ? 0
                                : (recentWatchPageReturn
                                        ? REENTRY_PIP_RETRY_COUNT
                                        : INITIAL_PIP_RETRY_COUNT);
                Log.i(
                        TAG,
                        "enterPictureInPicture strategy recent_watch_page_return=%b retry_delay_ms=%d retry_count=%d",
                        recentWatchPageReturn,
                        retryDelayMs,
                        retryCount);
                attemptPictureInPictureWhenFullscreenReady(
                        webContents, activity, braveActivity, retryDelayMs, retryCount);
            }
        }
    }

    /**
     * @noinspection unused
     */
    @NativeMethods
    interface Natives {
        void setFullscreen(WebContents webContents);

        void exitFullscreen(WebContents webContents);

        boolean hasFullscreenBeenRequested(WebContents webContents);

        boolean isPictureInPictureAvailable(WebContents webContents);

        boolean play(WebContents webContents);

        boolean pause(WebContents webContents);

        boolean seekBy(WebContents webContents, int offsetSeconds);

        boolean next(WebContents webContents, boolean preserveVideoPresentation);

        boolean previous(WebContents webContents, boolean preserveVideoPresentation);

    }
}
