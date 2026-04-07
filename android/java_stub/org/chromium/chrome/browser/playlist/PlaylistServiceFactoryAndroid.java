package org.chromium.chrome.browser.playlist;

import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.mojo.bindings.ConnectionErrorHandler;
import org.chromium.playlist.mojom.PlaylistService;

public class PlaylistServiceFactoryAndroid {
    private static final PlaylistServiceFactoryAndroid INSTANCE =
            new PlaylistServiceFactoryAndroid();

    public static PlaylistServiceFactoryAndroid getInstance() {
        return INSTANCE;
    }

    private PlaylistServiceFactoryAndroid() {}

    public PlaylistService getPlaylistService(
            Profile profile, ConnectionErrorHandler connectionErrorHandler) {
        return null;
    }
}
