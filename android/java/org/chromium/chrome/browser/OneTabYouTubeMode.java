/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser;

import android.net.Uri;
import android.text.TextUtils;

import org.chromium.base.ContextUtils;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.util.BraveConstants;
import org.chromium.url.GURL;

import java.util.Locale;

@NullMarked
public final class OneTabYouTubeMode {
    private static final String DEFAULT_HOME_URL = "https://m.youtube.com/";
    private static final String PACKAGE_PREFIX = BraveConstants.BRAVE_ANDROID_PACKAGE_PREFIX;
    private static final String[] ALLOWED_YOUTUBE_HOSTS = {
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "youtu.be",
        "consent.youtube.com",
        "accounts.youtube.com",
    };
    private static final String[] ALLOWED_GOOGLE_AUTH_HOSTS = {
        "accounts.google.com",
        "myaccount.google.com",
        "consent.google.com",
        "ogs.google.com",
        "gds.google.com",
    };

    private OneTabYouTubeMode() {}

    public static boolean isEnabled() {
        return ContextUtils.getApplicationContext().getPackageName().startsWith(PACKAGE_PREFIX);
    }

    public static String getDefaultHomepageUrl() {
        return DEFAULT_HOME_URL;
    }

    public static boolean isAllowedUrl(@Nullable String url) {
        if (!isEnabled()) {
            return true;
        }
        if (TextUtils.isEmpty(url)) {
            return false;
        }

        Uri uri = Uri.parse(url.trim());
        String scheme = uri.getScheme();
        if (scheme == null
                || (!"https".equalsIgnoreCase(scheme) && !"http".equalsIgnoreCase(scheme))) {
            return false;
        }

        String host = uri.getHost();
        if (TextUtils.isEmpty(host)) {
            return false;
        }

        String normalizedHost = host.toLowerCase(Locale.US);
        return matchesAllowedHost(normalizedHost, ALLOWED_YOUTUBE_HOSTS)
                || matchesAllowedHost(normalizedHost, ALLOWED_GOOGLE_AUTH_HOSTS);
    }

    public static boolean isYouTubeUrl(@Nullable String url) {
        if (!isEnabled()) {
            return true;
        }
        if (TextUtils.isEmpty(url)) {
            return false;
        }

        Uri uri = Uri.parse(url.trim());
        String scheme = uri.getScheme();
        if (scheme == null
                || (!"https".equalsIgnoreCase(scheme) && !"http".equalsIgnoreCase(scheme))) {
            return false;
        }

        String host = uri.getHost();
        if (TextUtils.isEmpty(host)) {
            return false;
        }

        return matchesAllowedHost(host.toLowerCase(Locale.US), ALLOWED_YOUTUBE_HOSTS);
    }

    private static boolean matchesAllowedHost(String normalizedHost, String[] allowedHosts) {
        for (String allowedHost : allowedHosts) {
            if (normalizedHost.equals(allowedHost)) {
                return true;
            }
        }
        return false;
    }

    public static boolean isAllowedGurl(@Nullable GURL url) {
        return url != null && !url.isEmpty() && isAllowedUrl(url.getSpec());
    }

    public static String toAllowedOrFallback(@Nullable String url) {
        if (!isEnabled()) {
            return url == null ? "" : url;
        }
        if (url == null) {
            return DEFAULT_HOME_URL;
        }
        return isAllowedUrl(url) ? url.trim() : DEFAULT_HOME_URL;
    }

    public static boolean shouldBlockMenuAction(int id) {
        if (!isEnabled()) {
            return false;
        }

        return id == R.id.new_tab_menu_id
                || id == R.id.new_incognito_tab_menu_id
                || id == R.id.add_to_group_menu_id
                || id == R.id.new_window_menu_id
                || id == R.id.new_incognito_window_menu_id
                || id == R.id.open_history_menu_id
                || id == R.id.downloads_menu_id
                || id == R.id.all_bookmarks_menu_id
                || id == R.id.recent_tabs_menu_id
                || id == R.id.brave_rewards_id
                || id == R.id.brave_wallet_id
                || id == R.id.brave_playlist_id
                || id == R.id.brave_news_id
                || id == R.id.request_brave_vpn_id
                || id == R.id.request_brave_vpn_check_id;
    }
}
