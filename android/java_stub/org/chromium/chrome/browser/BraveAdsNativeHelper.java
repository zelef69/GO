package org.chromium.chrome.browser;

import org.chromium.chrome.browser.profiles.Profile;

public class BraveAdsNativeHelper {
    private BraveAdsNativeHelper() {}

    public static boolean nativeIsOptedInToNotificationAds(Profile profile) {
        return false;
    }

    public static void nativeSetOptedInToNotificationAds(Profile profile, boolean optedIn) {}

    public static boolean nativeIsSupportedRegion(Profile profile) {
        return false;
    }

    public static void nativeClearData(Profile profile) {}

    public static void nativeOnNotificationAdShown(Profile profile, String notificationId) {}

    public static void nativeOnNotificationAdClosed(
            Profile profile, String notificationId, boolean byUser) {}

    public static void nativeOnNotificationAdClicked(Profile profile, String notificationId) {}
}
