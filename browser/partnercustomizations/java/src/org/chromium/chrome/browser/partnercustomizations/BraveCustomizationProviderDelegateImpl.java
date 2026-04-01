/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.partnercustomizations;

import org.chromium.chrome.browser.OneTabYouTubeMode;

/** Default ContextProviderPackageDelegateImpl implementation. */
public class BraveCustomizationProviderDelegateImpl
        extends CustomizationProviderDelegateUpstreamImpl {
    @Override
    public String getHomepage() {
        return OneTabYouTubeMode.isEnabled() ? OneTabYouTubeMode.getDefaultHomepageUrl() : null;
    }

    @Override
    public boolean isIncognitoModeDisabled() {
        return OneTabYouTubeMode.isEnabled();
    }

    @Override
    public boolean isBookmarksEditingDisabled() {
        return false;
    }
}