/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.brave_leo;

import org.chromium.content_public.browser.WebContents;
import org.chromium.ui.base.WindowAndroid;

// OneTabTube strips Leo/AI surfaces, so this handler intentionally no-ops.
public class BraveLeoVoiceRecognitionHandler {
    public BraveLeoVoiceRecognitionHandler(
            WindowAndroid windowAndroid, WebContents contextWebContents, String conversationUuid) {}

    public void startVoiceRecognition() {}
}
