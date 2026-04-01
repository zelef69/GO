/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser;

import static org.junit.Assert.assertEquals;

import android.content.Intent;
import android.net.Uri;

import androidx.test.filters.SmallTest;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.annotation.Config;

import org.chromium.base.test.BaseRobolectricTestRunner;
import org.chromium.chrome.browser.searchwidget.SearchWidgetProvider;

@RunWith(BaseRobolectricTestRunner.class)
@Config(manifest = Config.NONE)
public class BraveIntentHandlerUnitTest {
    @Test
    @SmallTest
    public void extractUrlFromIntent_widgetSearch_rewritesSourceToAndroidWidget() {
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setData(Uri.parse("https://www.youtube.com/watch?v=test123"));
        intent.putExtra(SearchWidgetProvider.EXTRA_FROM_SEARCH_WIDGET, true);

        String result = BraveIntentHandler.extractUrlFromIntent(intent);

        assertEquals("https://www.youtube.com/watch?v=test123", result);
    }

    @Test
    @SmallTest
    public void extractUrlFromIntent_nonWidgetSearch_keepsAndroidSource() {
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setData(Uri.parse("https://m.youtube.com/watch?v=test123"));
        intent.putExtra(SearchWidgetProvider.EXTRA_FROM_SEARCH_WIDGET, false);

        String result = BraveIntentHandler.extractUrlFromIntent(intent);

        assertEquals("https://m.youtube.com/watch?v=test123", result);
    }

    @Test
    @SmallTest
    public void extractUrlFromIntent_nonAllowlistedHost_fallsBackToYoutubeHome() {
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setData(Uri.parse("https://example.com/search?q=test&source=android"));
        intent.putExtra(SearchWidgetProvider.EXTRA_FROM_SEARCH_WIDGET, true);

        String result = BraveIntentHandler.extractUrlFromIntent(intent);

        assertEquals(OneTabYouTubeMode.getDefaultHomepageUrl(), result);
    }

    @Test
    @SmallTest
    public void extractUrlFromIntent_googleAccountsHost_isAllowed() {
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setData(Uri.parse("https://accounts.google.com/signin/v2/identifier"));

        String result = BraveIntentHandler.extractUrlFromIntent(intent);

        assertEquals("https://accounts.google.com/signin/v2/identifier", result);
    }
}
