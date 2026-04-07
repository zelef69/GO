package org.chromium.chrome.browser.onetabauth;

import android.text.TextUtils;

import org.chromium.base.shared_preferences.SharedPreferencesManager;
import org.chromium.chrome.browser.preferences.ChromeSharedPreferences;

import java.util.UUID;

final class OneTabAppUpdateStore {
    private static final String PREF_PREFIX = "onetab.app_update.";
    private static final String PREF_INSTALLATION_ID = PREF_PREFIX + "installation_id";
    private static final String PREF_CACHED_APK_PATH = PREF_PREFIX + "cached_apk_path";
    private static final String PREF_CACHED_VERSION_CODE = PREF_PREFIX + "cached_version_code";
    private static final String PREF_CACHED_SHA256 = PREF_PREFIX + "cached_sha256";
    private static final String PREF_PENDING_APK_PATH = PREF_PREFIX + "pending_apk_path";
    private static final String PREF_PENDING_VERSION_CODE = PREF_PREFIX + "pending_version_code";
    private static final String PREF_PENDING_VERSION_NAME = PREF_PREFIX + "pending_version_name";
    private static final String PREF_PENDING_UNKNOWN_SOURCES =
            PREF_PREFIX + "pending_unknown_sources";

    static final class CachedApk {
        final String apkPath;
        final long versionCode;
        final String sha256;

        CachedApk(String apkPath, long versionCode, String sha256) {
            this.apkPath = apkPath;
            this.versionCode = versionCode;
            this.sha256 = sha256;
        }

        boolean isValid() {
            return !TextUtils.isEmpty(apkPath) && versionCode > 0L && !TextUtils.isEmpty(sha256);
        }
    }

    static final class PendingInstall {
        final String apkPath;
        final long versionCode;
        final String versionName;
        final boolean awaitingUnknownSourcesPermission;

        PendingInstall(
                String apkPath,
                long versionCode,
                String versionName,
                boolean awaitingUnknownSourcesPermission) {
            this.apkPath = apkPath;
            this.versionCode = versionCode;
            this.versionName = versionName;
            this.awaitingUnknownSourcesPermission = awaitingUnknownSourcesPermission;
        }

        boolean isValid() {
            return !TextUtils.isEmpty(apkPath) && versionCode > 0L;
        }
    }

    String getInstallationId() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        String existing = prefs.readString(PREF_INSTALLATION_ID, "");
        if (!TextUtils.isEmpty(existing)) return existing;
        String created = UUID.randomUUID().toString();
        prefs.writeString(PREF_INSTALLATION_ID, created);
        return created;
    }

    void saveCachedApk(String apkPath, long versionCode, String sha256) {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        prefs.writeString(PREF_CACHED_APK_PATH, apkPath);
        prefs.writeLong(PREF_CACHED_VERSION_CODE, versionCode);
        prefs.writeString(PREF_CACHED_SHA256, sha256);
    }

    CachedApk readCachedApk() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        return new CachedApk(
                prefs.readString(PREF_CACHED_APK_PATH, ""),
                prefs.readLong(PREF_CACHED_VERSION_CODE, 0L),
                prefs.readString(PREF_CACHED_SHA256, ""));
    }

    void clearCachedApk() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        prefs.removeKey(PREF_CACHED_APK_PATH);
        prefs.removeKey(PREF_CACHED_VERSION_CODE);
        prefs.removeKey(PREF_CACHED_SHA256);
    }

    void savePendingInstall(
            String apkPath, long versionCode, String versionName, boolean awaitingUnknownSources) {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        prefs.writeString(PREF_PENDING_APK_PATH, apkPath);
        prefs.writeLong(PREF_PENDING_VERSION_CODE, versionCode);
        prefs.writeString(PREF_PENDING_VERSION_NAME, versionName);
        prefs.writeBoolean(PREF_PENDING_UNKNOWN_SOURCES, awaitingUnknownSources);
    }

    PendingInstall readPendingInstall() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        return new PendingInstall(
                prefs.readString(PREF_PENDING_APK_PATH, ""),
                prefs.readLong(PREF_PENDING_VERSION_CODE, 0L),
                prefs.readString(PREF_PENDING_VERSION_NAME, ""),
                prefs.readBoolean(PREF_PENDING_UNKNOWN_SOURCES, false));
    }

    void updatePendingInstallPermissionState(boolean awaitingUnknownSources) {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        if (TextUtils.isEmpty(prefs.readString(PREF_PENDING_APK_PATH, ""))) return;
        prefs.writeBoolean(PREF_PENDING_UNKNOWN_SOURCES, awaitingUnknownSources);
    }

    void clearPendingInstall() {
        SharedPreferencesManager prefs = ChromeSharedPreferences.getInstance();
        prefs.removeKey(PREF_PENDING_APK_PATH);
        prefs.removeKey(PREF_PENDING_VERSION_CODE);
        prefs.removeKey(PREF_PENDING_VERSION_NAME);
        prefs.removeKey(PREF_PENDING_UNKNOWN_SOURCES);
    }
}
