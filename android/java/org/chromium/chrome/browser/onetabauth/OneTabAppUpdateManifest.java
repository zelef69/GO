package org.chromium.chrome.browser.onetabauth;

import android.text.TextUtils;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

final class OneTabAppUpdateManifest {
    static final String DOC_PATH = "app_updates/android";

    final String appId;
    final String releaseChannel;
    final long latestVersionCode;
    final String latestVersionName;
    final long minimumSupportedVersionCode;
    final boolean updaterEnabled;
    final boolean forceUpdate;
    final String apkUrl;
    final String apkSha256;
    final long apkFileSizeBytes;
    final String releaseNotes;
    final long rolloutPercent;

    private OneTabAppUpdateManifest(
            String appId,
            String releaseChannel,
            long latestVersionCode,
            String latestVersionName,
            long minimumSupportedVersionCode,
            boolean updaterEnabled,
            boolean forceUpdate,
            String apkUrl,
            String apkSha256,
            long apkFileSizeBytes,
            String releaseNotes,
            long rolloutPercent) {
        this.appId = appId;
        this.releaseChannel = releaseChannel;
        this.latestVersionCode = latestVersionCode;
        this.latestVersionName = latestVersionName;
        this.minimumSupportedVersionCode = minimumSupportedVersionCode;
        this.updaterEnabled = updaterEnabled;
        this.forceUpdate = forceUpdate;
        this.apkUrl = apkUrl;
        this.apkSha256 = apkSha256;
        this.apkFileSizeBytes = apkFileSizeBytes;
        this.releaseNotes = releaseNotes;
        this.rolloutPercent = rolloutPercent;
    }

    String toDisplayString() {
        if (TextUtils.isEmpty(latestVersionName) || latestVersionCode <= 0L) {
            return "ไม่ทราบเวอร์ชัน";
        }
        return latestVersionName + " (" + latestVersionCode + ")";
    }

    static OneTabAppUpdateManifest fromFirestoreFields(JSONObject fields, String defaultAppId)
            throws ParseException {
        String appId =
                firstNonEmpty(
                        readTextField(fields, "appId"),
                        readTextField(fields, "applicationId"),
                        readTextField(fields, "packageName"),
                        defaultAppId);
        long latestVersionCode =
                firstNonZero(
                        readLongField(fields, "latestVersionCode"),
                        readLongField(fields, "latest_version_code"),
                        readLongField(fields, "versionCode"),
                        readLongField(fields, "buildNumber"));
        String latestVersionName =
                firstNonEmpty(
                        readTextField(fields, "latestVersionName"),
                        readTextField(fields, "latest_version_name"),
                        readTextField(fields, "versionName"),
                        readTextField(fields, "version"));
        long minimumSupportedVersionCode =
                firstNonZero(
                        readLongField(fields, "minimumSupportedVersionCode"),
                        readLongField(fields, "minimum_supported_version_code"),
                        readLongField(fields, "minSupportedVersionCode"));
        boolean updaterEnabled =
                firstBoolean(
                        readBooleanField(fields, "updaterEnabled"),
                        readBooleanField(fields, "updater_enabled"),
                        true);
        boolean forceUpdate =
                firstBoolean(
                        readBooleanField(fields, "forceUpdate"),
                        readBooleanField(fields, "force_update"),
                        false);
        String apkUrl =
                firstNonEmpty(
                        readTextField(fields, "apkUrl"),
                        readTextField(fields, "downloadUrl"),
                        readTextField(fields, "downloadLink"),
                        readTextField(fields, "apkLink"));
        String apkSha256 =
                firstNonEmpty(
                                readTextField(fields, "apkSha256"),
                                readTextField(fields, "apk_sha256"),
                                readTextField(fields, "sha256"))
                        .toLowerCase();
        long apkFileSizeBytes =
                firstNonZero(
                        readLongField(fields, "apkFileSizeBytes"),
                        readLongField(fields, "apk_file_size_bytes"),
                        readLongField(fields, "apkSizeBytes"));
        String releaseNotes =
                firstNonEmpty(
                        readMultilineField(fields, "releaseNotes"),
                        readMultilineField(fields, "release_notes"),
                        readMultilineField(fields, "changelog"));
        long rolloutPercent =
                clampPercent(
                        firstNonZero(
                                readLongField(fields, "rolloutPercent"),
                                readLongField(fields, "rollout_percent"),
                                100L));
        String releaseChannel =
                firstNonEmpty(
                        readTextField(fields, "releaseChannel"),
                        readTextField(fields, "release_channel"),
                        readTextField(fields, "channel"),
                        "stable");

        if (TextUtils.isEmpty(appId)) {
            throw new ParseException("Package ของเอกสารอัปเดตไม่ถูกต้อง");
        }
        if (latestVersionCode <= 0L) {
            throw new ParseException("ยังไม่ได้กำหนด latestVersionCode ที่ถูกต้อง");
        }
        if (TextUtils.isEmpty(latestVersionName)) {
            throw new ParseException("ยังไม่ได้กำหนด latestVersionName");
        }
        if (TextUtils.isEmpty(apkUrl)) {
            throw new ParseException("ยังไม่ได้กำหนด apkUrl");
        }
        if (TextUtils.isEmpty(apkSha256) || apkSha256.length() != 64) {
            throw new ParseException("ยังไม่ได้กำหนด apkSha256 ที่ถูกต้อง");
        }

        return new OneTabAppUpdateManifest(
                appId,
                releaseChannel,
                latestVersionCode,
                latestVersionName,
                minimumSupportedVersionCode,
                updaterEnabled,
                forceUpdate,
                apkUrl,
                apkSha256,
                apkFileSizeBytes,
                releaseNotes,
                rolloutPercent);
    }

    private static long clampPercent(long value) {
        if (value <= 0L) return 0L;
        if (value >= 100L) return 100L;
        return value;
    }

    private static String readTextField(JSONObject fields, String fieldName) {
        if (fields == null) return "";
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return "";
        if (field.has("stringValue")) return field.optString("stringValue", "").trim();
        if (field.has("integerValue")) return field.optString("integerValue", "").trim();
        if (field.has("doubleValue")) return field.optString("doubleValue", "").trim();
        return "";
    }

    private static long readLongField(JSONObject fields, String fieldName) {
        if (fields == null) return 0L;
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return 0L;
        try {
            if (field.has("integerValue")) {
                return Long.parseLong(field.optString("integerValue", "0"));
            }
            if (field.has("doubleValue")) {
                return Math.round(Double.parseDouble(field.optString("doubleValue", "0")));
            }
            if (field.has("stringValue")) {
                return Long.parseLong(field.optString("stringValue", "0").trim());
            }
        } catch (Exception ignored) {
        }
        return 0L;
    }

    private static Boolean readBooleanField(JSONObject fields, String fieldName) {
        if (fields == null) return null;
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return null;
        if (field.has("booleanValue")) return field.optBoolean("booleanValue");
        String stringValue = field.optString("stringValue", "").trim();
        if ("true".equalsIgnoreCase(stringValue) || "1".equals(stringValue)) return true;
        if ("false".equalsIgnoreCase(stringValue) || "0".equals(stringValue)) return false;
        return null;
    }

    private static String readMultilineField(JSONObject fields, String fieldName) {
        if (fields == null) return "";
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return "";
        if (field.has("stringValue")) return field.optString("stringValue", "").trim();
        JSONObject arrayValue = field.optJSONObject("arrayValue");
        if (arrayValue == null) return "";
        JSONArray values = arrayValue.optJSONArray("values");
        if (values == null || values.length() == 0) return "";

        List<String> items = new ArrayList<>();
        for (int i = 0; i < values.length(); i++) {
            JSONObject entry = values.optJSONObject(i);
            if (entry == null) continue;
            String text = entry.optString("stringValue", "").trim();
            if (!TextUtils.isEmpty(text)) items.add(text);
        }
        if (items.isEmpty()) return "";

        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) builder.append("\n");
            builder.append("• ").append(items.get(i));
        }
        return builder.toString();
    }

    private static String firstNonEmpty(String... values) {
        for (String value : values) {
            if (!TextUtils.isEmpty(value)) return value.trim();
        }
        return "";
    }

    private static long firstNonZero(long... values) {
        for (long value : values) {
            if (value > 0L) return value;
        }
        return 0L;
    }

    private static boolean firstBoolean(Boolean primary, Boolean secondary, boolean fallback) {
        if (primary != null) return primary;
        if (secondary != null) return secondary;
        return fallback;
    }

    static final class ParseException extends Exception {
        ParseException(String message) {
            super(message);
        }
    }
}
