/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.brave_leo;

import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.browser.profiles.Profile;

// OneTabTube strips Leo/AI surfaces, so these helpers intentionally no-op.
public final class BraveLeoPrefUtils {
    private BraveLeoPrefUtils() {}

    public static boolean isLeoDisabledByPolicy(@Nullable Profile profile) {
        return true;
    }

    public static void setIsSubscriptionActive(boolean value) {}

    public static boolean getIsSubscriptionActive(@Nullable Profile profile) {
        return false;
    }

    public static void setChatPurchaseToken(String token) {}

    public static boolean getIsHistoryEnabled() {
        return false;
    }

    public static void setIsHistoryEnabled(boolean isEnabled) {}

    public static void setChatPackageName() {}

    public static void setChatProductId(String productId) {}

    public static boolean isLeoEnabled() {
        return false;
    }

    public static boolean isSubscriptionLinked() {
        return false;
    }

    public static boolean shouldShowLeoQuickSearchEngine() {
        return false;
    }
}
