package org.chromium.chrome.browser.onetabauth;

import android.text.TextUtils;
import android.util.Base64;

import com.google.android.gms.tasks.Task;
import com.google.android.play.core.integrity.IntegrityManager;
import com.google.android.play.core.integrity.IntegrityManagerFactory;
import com.google.android.play.core.integrity.IntegrityTokenRequest;
import com.google.android.play.core.integrity.IntegrityTokenResponse;

import org.json.JSONObject;

import org.chromium.base.ApkInfo;
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
import java.security.SecureRandom;

public final class OneTabFirebaseAppCheckManager {
    public interface AppCheckCallback {
        void onResolved(boolean success, String token, String message);
    }

    private static final String TAG = "OneTabAppCheck";
    private static final long TOKEN_REFRESH_WINDOW_MS = 60_000L;
    private static final NetworkTrafficAnnotationTag APP_CHECK_TRAFFIC_ANNOTATION =
            NetworkTrafficAnnotationTag.MISSING_TRAFFIC_ANNOTATION;
    private static final long CLOUD_PROJECT_NUMBER = parseCloudProjectNumber();

    private static String sCachedToken;
    private static long sCachedTokenExpiresAtMs;

    public void resolveAppCheckToken(AppCheckCallback callback) {
        long nowMs = System.currentTimeMillis();
        if (!TextUtils.isEmpty(sCachedToken) && sCachedTokenExpiresAtMs > nowMs + TOKEN_REFRESH_WINDOW_MS) {
            callback.onResolved(true, sCachedToken, "");
            return;
        }

        if (shouldUseDebugToken()) {
            PostTask.postTask(
                    TaskTraits.BEST_EFFORT_MAY_BLOCK,
                    () -> {
                        ExchangeResult result =
                                exchangeAppCheckToken(
                                        OneTabFirebaseAuthConfig.APP_CHECK_DEBUG_EXCHANGE_URL,
                                        "debugToken",
                                        OneTabFirebaseAuthConfig.APP_CHECK_DEBUG_TOKEN);
                        PostTask.postTask(
                                TaskTraits.UI_DEFAULT,
                                () -> {
                                    if (result.success) {
                                        sCachedToken = result.token;
                                        sCachedTokenExpiresAtMs = result.expiresAtMs;
                                        callback.onResolved(true, result.token, "");
                                    } else {
                                        callback.onResolved(false, "", result.message);
                                    }
                                });
                    });
            return;
        }

        IntegrityManager integrityManager =
                IntegrityManagerFactory.create(ContextUtils.getApplicationContext());
        String nonce = generateNonce();
        IntegrityTokenRequest.Builder requestBuilder =
                IntegrityTokenRequest.builder().setNonce(nonce);
        if (CLOUD_PROJECT_NUMBER > 0L) {
            requestBuilder.setCloudProjectNumber(CLOUD_PROJECT_NUMBER);
        }
        Task<IntegrityTokenResponse> integrityTask =
                integrityManager.requestIntegrityToken(requestBuilder.build());
        integrityTask.addOnSuccessListener(
                response ->
                        PostTask.postTask(
                                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                                () -> {
                                    ExchangeResult result = exchangePlayIntegrityToken(response.token());
                                    PostTask.postTask(
                                            TaskTraits.UI_DEFAULT,
                                            () -> {
                                                if (result.success) {
                                                    sCachedToken = result.token;
                                                    sCachedTokenExpiresAtMs = result.expiresAtMs;
                                                    callback.onResolved(true, result.token, "");
                                                } else {
                                                    callback.onResolved(false, "", result.message);
                                                }
                                            });
                                }));
        integrityTask.addOnFailureListener(
                error -> {
                    Log.e(TAG, "requestIntegrityToken failed: %s", error.getMessage());
                    callback.onResolved(false, "", "Unable to verify app integrity.");
                });
    }

    private ExchangeResult exchangePlayIntegrityToken(String playIntegrityToken) {
        return exchangeAppCheckToken(
                OneTabFirebaseAuthConfig.APP_CHECK_EXCHANGE_URL,
                "playIntegrityToken",
                playIntegrityToken);
    }

    private ExchangeResult exchangeAppCheckToken(
            String endpoint, String fieldName, String fieldValue) {
        HttpURLConnection connection = null;
        try {
            JSONObject body = new JSONObject();
            body.put(fieldName, fieldValue);
            body.put("limitedUse", false);

            connection =
                    (HttpURLConnection)
                            ChromiumNetworkAdapter.openConnection(
                                    new URL(endpoint),
                                    APP_CHECK_TRAFFIC_ANNOTATION);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            connection.setDoOutput(true);
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            connection.setRequestProperty("X-Goog-Api-Key", OneTabFirebaseAuthConfig.API_KEY);

            try (OutputStream outputStream = connection.getOutputStream()) {
                byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
                outputStream.write(bytes);
                outputStream.flush();
            }

            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "exchangePlayIntegrityToken failed code=%d body=%s", responseCode, responseBody);
                return ExchangeResult.error(extractError(responseBody, "App Check exchange failed."));
            }

            JSONObject response = new JSONObject(responseBody);
            String token = response.optString("token", "");
            long expiresAtMs = System.currentTimeMillis() + parseTtlToMillis(response.optString("ttl", ""));
            if (TextUtils.isEmpty(token)) {
                return ExchangeResult.error("App Check token was missing.");
            }
            if (expiresAtMs <= System.currentTimeMillis()) {
                expiresAtMs = System.currentTimeMillis() + 5 * 60_000L;
            }
            return ExchangeResult.success(token, expiresAtMs);
        } catch (Exception e) {
            Log.e(TAG, "exchangePlayIntegrityToken exception=%s", e.getMessage());
            return ExchangeResult.error("Unable to exchange the integrity token.");
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static String readResponse(HttpURLConnection connection) throws Exception {
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

    private static String extractError(String responseBody, String fallback) {
        try {
            JSONObject root = new JSONObject(responseBody);
            JSONObject error = root.optJSONObject("error");
            if (error != null) {
                String message = error.optString("message", "");
                if (!TextUtils.isEmpty(message)) {
                    return message;
                }
            }
        } catch (Exception ignored) {
        }
        return fallback;
    }

    private static long parseTtlToMillis(String ttl) {
        String trimmed = ttl == null ? "" : ttl.trim();
        if (trimmed.endsWith("s")) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        try {
            double seconds = Double.parseDouble(trimmed);
            return Math.max(60_000L, (long) (seconds * 1000L));
        } catch (Exception ignored) {
            return 60 * 60_000L;
        }
    }

    private static String generateNonce() {
        byte[] bytes = new byte[24];
        new SecureRandom().nextBytes(bytes);
        return Base64.encodeToString(bytes, Base64.NO_WRAP | Base64.NO_PADDING | Base64.URL_SAFE);
    }

    private static boolean shouldUseDebugToken() {
        return ApkInfo.isDebugApp()
                && !TextUtils.isEmpty(OneTabFirebaseAuthConfig.APP_CHECK_DEBUG_TOKEN);
    }

    private static long parseCloudProjectNumber() {
        try {
            return Long.parseLong(OneTabFirebaseAuthConfig.PROJECT_NUMBER);
        } catch (Exception e) {
            Log.e(TAG, "Invalid cloud project number: %s", e.getMessage());
            return 0L;
        }
    }

    private static final class ExchangeResult {
        final boolean success;
        final String token;
        final long expiresAtMs;
        final String message;

        private ExchangeResult(boolean success, String token, long expiresAtMs, String message) {
            this.success = success;
            this.token = token;
            this.expiresAtMs = expiresAtMs;
            this.message = message;
        }

        static ExchangeResult success(String token, long expiresAtMs) {
            return new ExchangeResult(true, token, expiresAtMs, "");
        }

        static ExchangeResult error(String message) {
            return new ExchangeResult(false, "", 0L, message);
        }
    }
}
