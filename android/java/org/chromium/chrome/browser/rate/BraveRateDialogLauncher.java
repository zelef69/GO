/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.rate;

import androidx.fragment.app.FragmentManager;

import org.chromium.base.Log;

public final class BraveRateDialogLauncher {
    private static final String TAG = "RateDialogLauncher";
    private static final String RATE_DIALOG_CLASS_NAME =
            "org.chromium.chrome.browser.rate.BraveRateDialogFragment";

    private BraveRateDialogLauncher() {}

    public static void show(FragmentManager manager, boolean isFromSettings) {
        try {
            Class<?> clazz = Class.forName(RATE_DIALOG_CLASS_NAME);
            var newInstanceMethod = clazz.getDeclaredMethod("newInstance", boolean.class);
            newInstanceMethod.setAccessible(true);
            Object fragment = newInstanceMethod.invoke(null, isFromSettings);
            var tagField = clazz.getDeclaredField("TAG_FRAGMENT");
            tagField.setAccessible(true);
            String tag = (String) tagField.get(null);
            var showMethod = clazz.getDeclaredMethod("show", FragmentManager.class, String.class);
            showMethod.setAccessible(true);
            showMethod.invoke(fragment, manager, tag);
        } catch (ReflectiveOperationException e) {
            Log.e(TAG, "Unable to launch Brave rate dialog", e);
        }
    }
}
