package org.chromium.chrome.browser.onetabauth;

import android.text.TextUtils;

import org.chromium.base.shared_preferences.SharedPreferencesManager;
import org.chromium.chrome.browser.preferences.ChromeSharedPreferences;

import java.util.UUID;

final class OneTabDeviceSessionStore {
    private static final String PREF_PREFIX = "onetab.device_session.";
    private static final String PREF_DEVICE_ID = PREF_PREFIX + "device_id";
    private static final String PREF_SESSION_ID = PREF_PREFIX + "session_id";

    static final class DeviceSession {
        final String deviceId;
        final String sessionId;

        DeviceSession(String deviceId, String sessionId) {
            this.deviceId = deviceId;
            this.sessionId = sessionId;
        }

        boolean hasSessionId() {
            return !TextUtils.isEmpty(sessionId);
        }
    }

    DeviceSession read() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        return new DeviceSession(
                prefs.readString(PREF_DEVICE_ID, ""),
                prefs.readString(PREF_SESSION_ID, ""));
    }

    String ensureDeviceId() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        String existing = prefs.readString(PREF_DEVICE_ID, "");
        if (!TextUtils.isEmpty(existing)) {
            return existing;
        }

        String generated = UUID.randomUUID().toString();
        prefs.writeString(PREF_DEVICE_ID, generated);
        return generated;
    }

    void saveSessionId(String sessionId) {
        ChromeSharedPreferences.getInstance().writeString(PREF_SESSION_ID, sessionId);
    }

    void clearSessionId() {
        ChromeSharedPreferences.getInstance().removeKey(PREF_SESSION_ID);
    }

    void clearAll() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        prefs.removeKey(PREF_DEVICE_ID);
        prefs.removeKey(PREF_SESSION_ID);
    }
}
