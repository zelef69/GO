package org.chromium.chrome.browser.bookmarks;

import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.ui.base.WindowAndroid;

class BraveBookmarkBridge extends BookmarkBridge {
    BraveBookmarkBridge(long nativeBookmarkBridge, Profile profile) {
        super(nativeBookmarkBridge, profile);
    }

    public void importBookmarks(WindowAndroid windowAndroid, String importFilePath) {}

    public void exportBookmarks(WindowAndroid windowAndroid, String exportFilePath) {}
}
