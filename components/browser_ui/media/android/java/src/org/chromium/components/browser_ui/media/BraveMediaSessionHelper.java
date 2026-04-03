/* Copyright (c) 2024 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.components.browser_ui.media;

import android.graphics.Bitmap;

import androidx.annotation.Nullable;

import org.chromium.base.BraveReflectionUtil;
import org.chromium.base.CommandLine;
import org.chromium.components.embedder_support.util.UrlConstants;
import org.chromium.content_public.browser.MediaSession;
import org.chromium.content_public.browser.MediaSessionObserver;
import org.chromium.content_public.browser.WebContents;
import org.chromium.media_session.mojom.MediaSessionAction;
import org.chromium.services.media_session.MediaImage;
import org.chromium.services.media_session.MediaMetadata;
import org.chromium.services.media_session.MediaPosition;
import org.chromium.url.GURL;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class BraveMediaSessionHelper implements MediaImageCallback {
    private static final List<String> sBraveTalkHosts =
            Arrays.asList("talk.brave.com", "talk.bravesoftware.com", "talk.brave.software");
    private static final List<String> sYouTubeHosts =
            Arrays.asList("music.youtube.com", "www.youtube.com", "m.youtube.com", "youtube.com");

    public static boolean isBraveTalk(WebContents webContents) {
        if (webContents == null) {
            return false;
        }
        GURL pageUrl = webContents.getLastCommittedUrl();
        if (pageUrl.isValid()
                && pageUrl.getScheme().equals(UrlConstants.HTTPS_SCHEME)
                && sBraveTalkHosts.contains(pageUrl.getHost())) {
            return true;
        }

        return false;
    }

    private boolean shouldSuppressMediaNotificationActions() {
        WebContents webContents =
                (WebContents)
                        BraveReflectionUtil.getField(
                                MediaSessionHelper.class, "mWebContents", this);

        return isBraveTalk(webContents);
    }

    private boolean shouldSuppressMediaPause() {
        WebContents webContents =
                (WebContents)
                        BraveReflectionUtil.getField(
                                MediaSessionHelper.class, "mWebContents", this);

        return isBraveTalk(webContents) || isBackgroundVideo(webContents);
    }

    private boolean isYouTube(WebContents webContents) {
        if (webContents == null) return false;
        GURL pageUrl = webContents.getLastCommittedUrl();
        return pageUrl.isValid()
                && pageUrl.getScheme().equals(UrlConstants.HTTPS_SCHEME)
                && sYouTubeHosts.contains(pageUrl.getHost());
    }

    private boolean isBackgroundVideo(WebContents webContents) {
        // We check the command line switch rather than reading the preference directly because
        // this class is in the components layer and cannot access Profile or UserPrefs (chrome
        // layer) without causing R8 module boundary violations in the AAB build. The switch is
        // set by BraveBrowserMainParts::PostProfileInit() when the background video playback
        // feature and preference are both enabled, and the app restarts whenever the preference
        // changes, so the switch reliably reflects the current preference state.
        // In C++ this switch is defined as switches::kDisableBackgroundMediaSuspend.
        boolean enabled =
                CommandLine.getInstance().hasSwitch("disable-background-media-suspend")
                        && isYouTube(webContents);
        return enabled;
    }

    private boolean shouldFilterMediaSessionActions() {
        WebContents webContents =
                (WebContents)
                        BraveReflectionUtil.getField(
                                MediaSessionHelper.class, "mWebContents", this);
        return isYouTube(webContents);
    }

    private boolean shouldAdvertiseYouTubeTransportControls(@Nullable Set<Integer> actions) {
        if (!shouldFilterMediaSessionActions()) return false;
        if (actions == null || actions.isEmpty()) {
            return true;
        }

        return actions.contains(MediaSessionAction.PLAY)
                || actions.contains(MediaSessionAction.PAUSE)
                || actions.contains(MediaSessionAction.SEEK_FORWARD)
                || actions.contains(MediaSessionAction.SEEK_BACKWARD)
                || actions.contains(MediaSessionAction.SEEK_TO)
                || actions.contains(MediaSessionAction.NEXT_TRACK)
                || actions.contains(MediaSessionAction.PREVIOUS_TRACK);
    }

    private @Nullable Set<Integer> filterSupportedMediaSessionActions(
            @Nullable Set<Integer> actions) {
        if (!shouldFilterMediaSessionActions()) {
            return actions;
        }

        HashSet<Integer> filtered = new HashSet<Integer>();
        if (actions != null && actions.contains(MediaSessionAction.PREVIOUS_TRACK)) {
            filtered.add(MediaSessionAction.PREVIOUS_TRACK);
        }
        if (actions != null && actions.contains(MediaSessionAction.PLAY)) {
            filtered.add(MediaSessionAction.PLAY);
        }
        if (actions != null && actions.contains(MediaSessionAction.PAUSE)) {
            filtered.add(MediaSessionAction.PAUSE);
        }
        if (actions != null && actions.contains(MediaSessionAction.SEEK_BACKWARD)) {
            filtered.add(MediaSessionAction.SEEK_BACKWARD);
        }
        if (actions != null && actions.contains(MediaSessionAction.SEEK_FORWARD)) {
            filtered.add(MediaSessionAction.SEEK_FORWARD);
        }
        if (actions != null && actions.contains(MediaSessionAction.NEXT_TRACK)) {
            filtered.add(MediaSessionAction.NEXT_TRACK);
        }
        if (actions != null && actions.contains(MediaSessionAction.SEEK_TO)) {
            filtered.add(MediaSessionAction.SEEK_TO);
        }
        if (actions != null && actions.contains(MediaSessionAction.STOP)) {
            filtered.add(MediaSessionAction.STOP);
        }

        // Keep Android transport surfaces stable for YouTube browser-tabs.
        // The native bridge can handle next/previous directly even when the page
        // does not reliably re-advertise those actions on every state change.
        if (shouldAdvertiseYouTubeTransportControls(actions)) {
            filtered.add(MediaSessionAction.PLAY);
            filtered.add(MediaSessionAction.PAUSE);
            filtered.add(MediaSessionAction.PREVIOUS_TRACK);
            filtered.add(MediaSessionAction.NEXT_TRACK);
        }

        return Collections.unmodifiableSet(filtered);
    }

    @Override
    public void onImageDownloaded(Bitmap image) {}

    public void showNotification() {
        MediaNotificationInfo.Builder notificationInfoBuilder =
                (MediaNotificationInfo.Builder)
                        BraveReflectionUtil.getField(
                                MediaSessionHelper.class, "mNotificationInfoBuilder", this);
        if (notificationInfoBuilder != null) {
            if (shouldSuppressMediaNotificationActions()) {
                notificationInfoBuilder.setActions(0);
                HashSet<Integer> actionSet = new HashSet<Integer>();
                actionSet.add(0);
                notificationInfoBuilder.setMediaSessionActions(actionSet);
                BraveReflectionUtil.setField(
                        MediaSessionHelper.class, "mMediaSessionActions", this, actionSet);
            } else {
                Set<Integer> mediaSessionActions =
                        (Set<Integer>)
                                BraveReflectionUtil.getField(
                                        MediaSessionHelper.class, "mMediaSessionActions", this);
                Set<Integer> filteredActions = filterSupportedMediaSessionActions(mediaSessionActions);
                if (filteredActions != null) {
                    notificationInfoBuilder.setMediaSessionActions(filteredActions);
                    BraveReflectionUtil.setField(
                            MediaSessionHelper.class, "mMediaSessionActions", this, filteredActions);
                }
            }
        }
        BraveReflectionUtil.invokeMethod(MediaSessionHelper.class, this, "showNotification");
    }

    protected MediaSessionObserver createMediaSessionObserver(MediaSession mediaSession) {
        MediaSessionObserver mediaSessionObserver =
                (MediaSessionObserver)
                        BraveReflectionUtil.invokeMethod(
                                MediaSessionHelper.class,
                                this,
                                "createMediaSessionObserver",
                                MediaSession.class,
                                mediaSession);
        assert mediaSessionObserver != null;

        if (!shouldSuppressMediaPause() && !shouldFilterMediaSessionActions()) {
            return mediaSessionObserver;
        }
        return new MediaSessionObserver(mediaSession) {
            @Override
            public void mediaSessionDestroyed() {
                mediaSessionObserver.mediaSessionDestroyed();
            }

            @Override
            public void mediaSessionStateChanged(boolean isControllable, boolean isPaused) {
                if (shouldSuppressMediaPause() && !isControllable) {
                    isControllable = true;
                    isPaused = false;
                }
                mediaSessionObserver.mediaSessionStateChanged(isControllable, isPaused);
            }

            @Override
            public void mediaSessionMetadataChanged(MediaMetadata metadata) {
                mediaSessionObserver.mediaSessionMetadataChanged(metadata);
            }

            @Override
            public void mediaSessionActionsChanged(Set<Integer> actions) {
                Set<Integer> filteredActions = filterSupportedMediaSessionActions(actions);
                if (filteredActions != null) {
                    BraveReflectionUtil.setField(
                            MediaSessionHelper.class,
                            "mMediaSessionActions",
                            BraveMediaSessionHelper.this,
                            filteredActions);
                    mediaSessionObserver.mediaSessionActionsChanged(filteredActions);
                    return;
                }
                mediaSessionObserver.mediaSessionActionsChanged(actions);
            }

            @Override
            public void mediaSessionArtworkChanged(List<MediaImage> images) {
                mediaSessionObserver.mediaSessionArtworkChanged(images);
            }

            @Override
            public void mediaSessionPositionChanged(@Nullable MediaPosition position) {
                mediaSessionObserver.mediaSessionPositionChanged(position);
            }
        };
    }
}
