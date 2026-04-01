/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.brave_leo;

import android.app.Activity;

import org.chromium.ai_chat.mojom.ModelWithSubtitle;
import org.chromium.base.Callback;
import org.chromium.content_public.browser.WebContents;

// OneTabTube strips Leo/AI surfaces, so these helpers intentionally no-op.
public final class BraveLeoUtils {
    private BraveLeoUtils() {}

    public static void verifySubscription(Callback callback) {
        if (callback != null) {
            callback.onResult(null);
        }
    }

    public static void openLeoQuery(
            WebContents webContents,
            String conversationUuid,
            String query,
            boolean openLeoChatWindow) {}

    public static void openLeoUrlForTab(WebContents webContents) {}

    public static String getDefaultModelName(
            ModelWithSubtitle[] models, String defaultModelKey) {
        return "";
    }

    public static void openManageSubscription() {}

    public static void goPremium(Activity activity) {}

    public static void bringMainActivityOnTop() {}
}
