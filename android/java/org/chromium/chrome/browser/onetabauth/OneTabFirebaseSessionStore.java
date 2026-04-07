package org.chromium.chrome.browser.onetabauth;

import android.text.TextUtils;

import org.chromium.base.shared_preferences.SharedPreferencesManager;
import org.chromium.chrome.browser.preferences.ChromeSharedPreferences;

public final class OneTabFirebaseSessionStore {
    private static final String PREF_PREFIX = "onetab.firebase_auth.";
    private static final String PREF_UID = PREF_PREFIX + "uid";
    private static final String PREF_EMAIL = PREF_PREFIX + "email";
    private static final String PREF_DISPLAY_NAME = PREF_PREFIX + "display_name";
    private static final String PREF_PHOTO_URL = PREF_PREFIX + "photo_url";
    private static final String PREF_ID_TOKEN = PREF_PREFIX + "id_token";
    private static final String PREF_REFRESH_TOKEN = PREF_PREFIX + "refresh_token";
    private static final String PREF_EXPIRES_AT_MS = PREF_PREFIX + "expires_at_ms";

    public static final class Session {
        public final String uid;
        public final String email;
        public final String displayName;
        public final String photoUrl;
        public final String idToken;
        public final String refreshToken;
        public final long expiresAtMs;

        Session(
                String uid,
                String email,
                String displayName,
                String photoUrl,
                String idToken,
                String refreshToken,
                long expiresAtMs) {
            this.uid = uid;
            this.email = email;
            this.displayName = displayName;
            this.photoUrl = photoUrl;
            this.idToken = idToken;
            this.refreshToken = refreshToken;
            this.expiresAtMs = expiresAtMs;
        }

        public boolean hasUsableIdToken(long nowMs) {
            return !TextUtils.isEmpty(idToken) && expiresAtMs > nowMs + 60_000L;
        }

        public boolean hasRefreshToken() {
            return !TextUtils.isEmpty(refreshToken);
        }
    }

    public Session read() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        return new Session(
                prefs.readString(PREF_UID, ""),
                prefs.readString(PREF_EMAIL, ""),
                prefs.readString(PREF_DISPLAY_NAME, ""),
                prefs.readString(PREF_PHOTO_URL, ""),
                prefs.readString(PREF_ID_TOKEN, ""),
                prefs.readString(PREF_REFRESH_TOKEN, ""),
                prefs.readLong(PREF_EXPIRES_AT_MS, 0L));
    }

    public void save(Session session) {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        prefs.writeString(PREF_UID, session.uid);
        prefs.writeString(PREF_EMAIL, session.email);
        prefs.writeString(PREF_DISPLAY_NAME, session.displayName);
        prefs.writeString(PREF_PHOTO_URL, session.photoUrl);
        prefs.writeString(PREF_ID_TOKEN, session.idToken);
        prefs.writeString(PREF_REFRESH_TOKEN, session.refreshToken);
        prefs.writeLong(PREF_EXPIRES_AT_MS, session.expiresAtMs);
    }

    public void clear() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        prefs.removeKey(PREF_UID);
        prefs.removeKey(PREF_EMAIL);
        prefs.removeKey(PREF_DISPLAY_NAME);
        prefs.removeKey(PREF_PHOTO_URL);
        prefs.removeKey(PREF_ID_TOKEN);
        prefs.removeKey(PREF_REFRESH_TOKEN);
        prefs.removeKey(PREF_EXPIRES_AT_MS);
    }
}
