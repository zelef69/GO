package org.chromium.chrome.browser.onetabauth;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.os.Build;
import android.text.TextUtils;

import org.json.JSONObject;

import org.chromium.base.ContextUtils;
import org.chromium.base.Log;
import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.net.ChromiumNetworkAdapter;
import org.chromium.net.NetworkTrafficAnnotationTag;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public final class OneTabDeviceSessionManager {
    public interface DeviceAccessCallback {
        void onResolved(boolean allowed, String message);
    }

    public interface LogoutCallback {
        void onResolved(boolean success, String message);
    }

    private static final String TAG = "OneTabDeviceSession";
    private static final String RESULT_OK = "OK";
    private static final String RESULT_BLOCKED = "BLOCKED";
    private static final String RESULT_EXPIRED = "EXPIRED";
    private static final String RESULT_DEVICE_REVOKED = "DEVICE_REVOKED";
    private static final String RESULT_VERSION_MISMATCH = "VERSION_MISMATCH";
    private static final String RESULT_SESSION_NOT_FOUND = "SESSION_NOT_FOUND";
    private static final String RESULT_DEVICE_LIMIT_EXCEEDED = "DEVICE_LIMIT_EXCEEDED";
    private static final NetworkTrafficAnnotationTag DEVICE_SESSION_TRAFFIC_ANNOTATION =
            NetworkTrafficAnnotationTag.MISSING_TRAFFIC_ANNOTATION;

    private final OneTabDeviceSessionStore mStore = new OneTabDeviceSessionStore();

    public void ensureAccess(DeviceAccessCallback callback) {
        ensureAccess(new OneTabFirebaseSessionStore().read(), callback);
    }

    public void logoutCurrentSession(LogoutCallback callback) {
        logoutCurrentSession(new OneTabFirebaseSessionStore().read(), callback);
    }

    void ensureAccess(
            OneTabFirebaseSessionStore.Session session, DeviceAccessCallback callback) {
        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                () -> {
                    AccessResult result = ensureAccessBlocking(session);
                    PostTask.postTask(
                            TaskTraits.UI_DEFAULT,
                            () -> callback.onResolved(result.allowed, result.message));
                });
    }

    private AccessResult ensureAccessBlocking(OneTabFirebaseSessionStore.Session authSession) {
        if (TextUtils.isEmpty(authSession.uid) || TextUtils.isEmpty(authSession.idToken)) {
            return AccessResult.error("กรุณาเข้าสู่ระบบใหม่ก่อนใช้งาน GO_PLAY");
        }

        String deviceId = mStore.ensureDeviceId();
        OneTabDeviceSessionStore.DeviceSession currentSession = mStore.read();
        String sessionId = currentSession.sessionId;

        if (!TextUtils.isEmpty(sessionId)) {
            AccessResult validateResult = validateExistingSession(authSession, sessionId, deviceId);
            if (validateResult.allowed) {
                heartbeatExistingSession(authSession, sessionId, deviceId);
                return validateResult;
            }
            if (!validateResult.shouldRegister) {
                return validateResult;
            }
            mStore.clearSessionId();
        }

        AccessResult registerResult = registerNewSession(authSession, deviceId);
        if (registerResult.allowed) {
            OneTabDeviceSessionStore.DeviceSession refreshedSession = mStore.read();
            if (refreshedSession.hasSessionId()) {
                heartbeatExistingSession(authSession, refreshedSession.sessionId, deviceId);
            }
        }
        return registerResult;
    }

    void logoutCurrentSession(
            OneTabFirebaseSessionStore.Session authSession, LogoutCallback callback) {
        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                () -> {
                    LogoutResult result = logoutCurrentSessionBlocking(authSession);
                    PostTask.postTask(
                            TaskTraits.UI_DEFAULT,
                            () -> callback.onResolved(result.success, result.message));
                });
    }

    private LogoutResult logoutCurrentSessionBlocking(
            OneTabFirebaseSessionStore.Session authSession) {
        OneTabDeviceSessionStore.DeviceSession currentSession = mStore.read();
        if (TextUtils.isEmpty(currentSession.sessionId)) {
            mStore.clearSessionId();
            return LogoutResult.success();
        }
        if (TextUtils.isEmpty(authSession.uid) || TextUtils.isEmpty(authSession.idToken)) {
            return LogoutResult.error("กรุณาเข้าสู่ระบบใหม่ก่อนออกจากระบบ");
        }

        try {
            JSONObject payload = new JSONObject();
            payload.put("data", buildDevicePayload(currentSession.sessionId, currentSession.deviceId));
            JSONObject response = callCallable("logoutDeviceSession", payload, authSession.idToken);
            JSONObject result = response.optJSONObject("result");
            String resultCode = result == null ? "" : result.optString("resultCode", "");
            if (!TextUtils.isEmpty(resultCode) && !RESULT_OK.equals(resultCode)) {
                return LogoutResult.error(messageForResultCode(resultCode));
            }
            mStore.clearSessionId();
            return LogoutResult.success();
        } catch (DeviceSessionException e) {
            return LogoutResult.error(e.message);
        } catch (Exception e) {
            Log.e(TAG, "logoutCurrentSession error=%s", e.getMessage());
            return LogoutResult.error("Unable to logout this device right now.");
        }
    }

    private AccessResult validateExistingSession(
            OneTabFirebaseSessionStore.Session authSession, String sessionId, String deviceId) {
        try {
            JSONObject payload = new JSONObject();
            payload.put("data", buildDevicePayload(sessionId, deviceId));
            JSONObject response = callCallable("validateDeviceSession", payload, authSession.idToken);
            JSONObject result = response.optJSONObject("result");
            if (result == null) {
                return AccessResult.error("Unable to validate this device session.");
            }

            String resultCode = result.optString("resultCode", "");
            if (RESULT_OK.equals(resultCode)) {
                return AccessResult.success();
            }
            if (shouldRegisterFromResultCode(resultCode)) {
                return AccessResult.reregister();
            }
            return AccessResult.error(messageForResultCode(resultCode));
        } catch (DeviceSessionException e) {
            if (shouldRegisterFromResultCode(e.resultCode)) {
                return AccessResult.reregister();
            }
            return AccessResult.error(e.message);
        } catch (Exception e) {
            Log.e(TAG, "validateExistingSession error=%s", e.getMessage());
            return AccessResult.error("ยังตรวจสอบสิทธิ์อุปกรณ์ไม่ได้ในขณะนี้");
        }
    }

    private AccessResult registerNewSession(
            OneTabFirebaseSessionStore.Session authSession, String deviceId) {
        try {
            JSONObject payload = new JSONObject();
            payload.put("data", buildDevicePayload("", deviceId));
            JSONObject response = callCallable("registerDeviceSession", payload, authSession.idToken);
            JSONObject result = response.optJSONObject("result");
            if (result == null) {
                return AccessResult.error("Unable to register this device.");
            }

            String resultCode = result.optString("resultCode", "");
            if (!RESULT_OK.equals(resultCode)) {
                return AccessResult.error(messageForResultCode(resultCode));
            }

            String sessionId = result.optString("sessionId", "");
            if (TextUtils.isEmpty(sessionId)) {
                return AccessResult.error("The device session response was incomplete.");
            }
            mStore.saveSessionId(sessionId);
            return AccessResult.success();
        } catch (DeviceSessionException e) {
            return AccessResult.error(e.message);
        } catch (Exception e) {
            Log.e(TAG, "registerNewSession error=%s", e.getMessage());
            return AccessResult.error("ยังลงทะเบียนอุปกรณ์นี้ไม่ได้");
        }
    }

    private void heartbeatExistingSession(
            OneTabFirebaseSessionStore.Session authSession, String sessionId, String deviceId) {
        try {
            JSONObject payload = new JSONObject();
            payload.put("data", buildDevicePayload(sessionId, deviceId));
            callCallable("heartbeatDeviceSession", payload, authSession.idToken);
        } catch (Exception e) {
            Log.w(TAG, "heartbeatExistingSession skipped error=%s", e.getMessage());
        }
    }

    private JSONObject buildDevicePayload(String sessionId, String deviceId) throws Exception {
        JSONObject data = new JSONObject();
        data.put("sessionId", sessionId);
        data.put("deviceId", deviceId);
        data.put("deviceName", buildDeviceName());
        data.put("platform", "android");
        data.put("model", TextUtils.isEmpty(Build.MODEL) ? "unknown-model" : Build.MODEL);
        data.put("appVersion", resolveAppVersion());
        return data;
    }

    private static String buildDeviceName() {
        String manufacturer = TextUtils.isEmpty(Build.MANUFACTURER) ? "" : Build.MANUFACTURER.trim();
        String model = TextUtils.isEmpty(Build.MODEL) ? "" : Build.MODEL.trim();
        String combined = (manufacturer + " " + model).trim();
        return combined.isEmpty() ? "Android device" : combined;
    }

    private static String resolveAppVersion() {
        try {
            Context context = ContextUtils.getApplicationContext();
            PackageInfo packageInfo =
                    context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            if (!TextUtils.isEmpty(packageInfo.versionName)) {
                return packageInfo.versionName;
            }
        } catch (Exception e) {
            Log.w(TAG, "resolveAppVersion error=%s", e.getMessage());
        }
        return "unknown";
    }

    private static JSONObject callCallable(String functionName, JSONObject payload, String idToken)
            throws Exception {
        HttpURLConnection connection = null;
        try {
            connection =
                    (HttpURLConnection)
                            ChromiumNetworkAdapter.openConnection(
                                    new URL(
                                            OneTabFirebaseAuthConfig.FUNCTIONS_BASE_URL
                                                    + "/"
                                                    + functionName),
                                    DEVICE_SESSION_TRAFFIC_ANNOTATION);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(30000);
            connection.setDoOutput(true);
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("Authorization", "Bearer " + idToken);
            try (OutputStream outputStream = connection.getOutputStream()) {
                byte[] bytes = payload.toString().getBytes(StandardCharsets.UTF_8);
                outputStream.write(bytes);
                outputStream.flush();
            }

            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw parseCallableError(responseBody, "Unable to reach the device session service.");
            }

            JSONObject response = new JSONObject(responseBody);
            if (response.has("error")) {
                throw parseCallableError(responseBody, "Unable to reach the device session service.");
            }
            return response;
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private static DeviceSessionException parseCallableError(String responseBody, String fallback) {
        try {
            JSONObject root = new JSONObject(responseBody);
            JSONObject error = root.optJSONObject("error");
            if (error == null) {
                return new DeviceSessionException("", fallback);
            }
            String message = error.optString("message", "");
            JSONObject details = error.optJSONObject("details");
            String resultCode = details == null ? "" : details.optString("code", "");
            return new DeviceSessionException(
                    resultCode,
                    !TextUtils.isEmpty(resultCode)
                            ? messageForResultCode(resultCode)
                            : (!TextUtils.isEmpty(message) ? message : fallback));
        } catch (Exception ignored) {
        }
        return new DeviceSessionException("", fallback);
    }

    private static boolean shouldRegisterFromResultCode(String resultCode) {
        return RESULT_SESSION_NOT_FOUND.equals(resultCode)
                || RESULT_VERSION_MISMATCH.equals(resultCode)
                || RESULT_DEVICE_REVOKED.equals(resultCode);
    }

    private static String messageForResultCode(String resultCode) {
        if (RESULT_DEVICE_LIMIT_EXCEEDED.equals(resultCode)) {
            return "Gmail นี้กำลังใช้งานอยู่ครบ 10 อุปกรณ์แล้ว";
        }
        if (RESULT_BLOCKED.equals(resultCode)) {
            return "Gmail นี้ถูกระงับการใช้งาน GO_PLAY";
        }
        if (RESULT_EXPIRED.equals(resultCode)) {
            return "Gmail นี้ไม่สามารถเข้าใช้งาน GO_PLAY ได้แล้ว";
        }
        if (RESULT_DEVICE_REVOKED.equals(resultCode)) {
            return "เซสชันของอุปกรณ์นี้ไม่ถูกต้องแล้ว";
        }
        if (RESULT_VERSION_MISMATCH.equals(resultCode)) {
            return "อุปกรณ์นี้ต้องเข้าสู่ระบบ GO_PLAY ใหม่";
        }
        if (RESULT_SESSION_NOT_FOUND.equals(resultCode)) {
            return "ไม่พบเซสชันของอุปกรณ์นี้";
        }
        return "ยังตรวจสอบสิทธิ์อุปกรณ์ไม่ได้ในขณะนี้";
    }

    private static String readResponse(HttpURLConnection connection) throws Exception {
        if (connection.getErrorStream() == null && connection.getInputStream() == null) {
            return "";
        }
        BufferedReader reader =
                new BufferedReader(
                        new InputStreamReader(
                                connection.getResponseCode() >= 400
                                        ? connection.getErrorStream()
                                        : connection.getInputStream(),
                                StandardCharsets.UTF_8));
        StringBuilder builder = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) {
            builder.append(line);
        }
        reader.close();
        return builder.toString();
    }

    private static final class AccessResult {
        final boolean allowed;
        final boolean shouldRegister;
        final String message;

        private AccessResult(boolean allowed, boolean shouldRegister, String message) {
            this.allowed = allowed;
            this.shouldRegister = shouldRegister;
            this.message = message;
        }

        static AccessResult success() {
            return new AccessResult(true, false, "");
        }

        static AccessResult reregister() {
            return new AccessResult(false, true, "");
        }

        static AccessResult error(String message) {
            return new AccessResult(false, false, message);
        }
    }

    private static final class LogoutResult {
        final boolean success;
        final String message;

        private LogoutResult(boolean success, String message) {
            this.success = success;
            this.message = message;
        }

        static LogoutResult success() {
            return new LogoutResult(true, "");
        }

        static LogoutResult error(String message) {
            return new LogoutResult(false, message);
        }
    }

    private static final class DeviceSessionException extends Exception {
        final String resultCode;
        final String message;

        DeviceSessionException(String resultCode, String message) {
            super(message);
            this.resultCode = resultCode;
            this.message = message;
        }
    }
}
