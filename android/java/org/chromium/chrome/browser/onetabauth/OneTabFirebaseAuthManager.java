package org.chromium.chrome.browser.onetabauth;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.text.TextUtils;

import com.google.android.gms.auth.api.signin.GoogleSignIn;
import com.google.android.gms.auth.api.signin.GoogleSignInAccount;
import com.google.android.gms.auth.api.signin.GoogleSignInClient;
import com.google.android.gms.auth.api.signin.GoogleSignInOptions;
import com.google.android.gms.common.api.ApiException;

import org.json.JSONObject;

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
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

public class OneTabFirebaseAuthManager {
    public interface AuthStateCallback {
        void onResolved(boolean authenticated, String message);
    }

    private static final String TAG = "OneTabFirebaseAuth";
    public static final int REQUEST_CODE_GOOGLE_SIGN_IN = 0x4F47;
    private static final NetworkTrafficAnnotationTag FIREBASE_AUTH_TRAFFIC_ANNOTATION =
            NetworkTrafficAnnotationTag.MISSING_TRAFFIC_ANNOTATION;

    private final OneTabFirebaseSessionStore mSessionStore = new OneTabFirebaseSessionStore();
    private GoogleSignInClient mGoogleSignInClient;
    private AuthStateCallback mPendingSignInCallback;

    public boolean isSignedInFast() {
        return mSessionStore.read().hasUsableIdToken(System.currentTimeMillis());
    }

    public void resolveAuthentication(AuthStateCallback callback) {
        OneTabFirebaseSessionStore.Session session = mSessionStore.read();
        long nowMs = System.currentTimeMillis();
        if (session.hasUsableIdToken(nowMs)) {
            callback.onResolved(true, "");
            return;
        }
        if (!session.hasRefreshToken()) {
            callback.onResolved(false, "");
            return;
        }

        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                () -> {
                    AuthExchangeResult result = refreshSession(session.refreshToken);
                    PostTask.postTask(
                            TaskTraits.UI_DEFAULT,
                            () -> {
                                if (result.success) {
                                    mSessionStore.save(result.session);
                                    callback.onResolved(true, "");
                                } else {
                                    mSessionStore.clear();
                                    callback.onResolved(false, result.message);
                                }
                            });
                });
    }

    public void beginGoogleSignIn(Activity activity, AuthStateCallback callback) {
        mPendingSignInCallback = callback;
        GoogleSignInOptions options =
                new GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
                        .requestEmail()
                        .requestProfile()
                        .requestIdToken(OneTabFirebaseAuthConfig.WEB_CLIENT_ID)
                        .build();
        mGoogleSignInClient = GoogleSignIn.getClient(activity, options);
        Intent signInIntent = mGoogleSignInClient.getSignInIntent();
        String resolvedComponent =
                signInIntent.resolveActivity(activity.getPackageManager()) != null
                        ? signInIntent.resolveActivity(activity.getPackageManager()).flattenToShortString()
                        : "unresolved";
        Log.i(
                TAG,
                "beginGoogleSignIn requestCode=%d webClientId=%s resolved=%s intent=%s",
                REQUEST_CODE_GOOGLE_SIGN_IN,
                OneTabFirebaseAuthConfig.WEB_CLIENT_ID,
                resolvedComponent,
                signInIntent);
        activity.startActivityForResult(signInIntent, REQUEST_CODE_GOOGLE_SIGN_IN);
    }

    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_CODE_GOOGLE_SIGN_IN) {
            return false;
        }

        Log.i(
                TAG,
                "onActivityResult requestCode=%d resultCode=%d hasData=%s action=%s",
                requestCode,
                resultCode,
                data != null,
                data == null ? "<null>" : data.getAction());

        AuthStateCallback callback = mPendingSignInCallback;
        mPendingSignInCallback = null;
        if (callback == null) {
            Log.w(TAG, "onActivityResult missing pending callback");
            return true;
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            Log.w(TAG, "Google sign-in cancelled or missing data resultCode=%d", resultCode);
            callback.onResolved(false, "Sign-in was cancelled.");
            return true;
        }

        GoogleSignInAccount account;
        try {
            account = GoogleSignIn.getSignedInAccountFromIntent(data).getResult(ApiException.class);
        } catch (ApiException e) {
            Log.e(
                    TAG,
                    "Google sign-in failed statusCode=%d message=%s",
                    e.getStatusCode(),
                    e.getMessage());
            callback.onResolved(false, "Google sign-in failed.");
            return true;
        }

        String idToken = account == null ? null : account.getIdToken();
        Log.i(
                TAG,
                "Google sign-in account email=%s hasIdToken=%s",
                account == null ? "<null>" : account.getEmail(),
                !TextUtils.isEmpty(idToken));
        if (TextUtils.isEmpty(idToken)) {
            callback.onResolved(
                    false,
                    "Missing Google ID token. Add Android OAuth SHA to Firebase first.");
            return true;
        }

        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                () -> {
                    AuthExchangeResult result = exchangeGoogleIdToken(idToken);
                    PostTask.postTask(
                            TaskTraits.UI_DEFAULT,
                            () -> {
                                if (result.success) {
                                    mSessionStore.save(result.session);
                                    callback.onResolved(true, "");
                                } else {
                                    callback.onResolved(false, result.message);
                                }
                            });
                });
        return true;
    }

    public void signOut(Activity activity) {
        mSessionStore.clear();
        if (mGoogleSignInClient == null) {
            GoogleSignInOptions options =
                    new GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
                            .requestEmail()
                            .requestProfile()
                            .requestIdToken(OneTabFirebaseAuthConfig.WEB_CLIENT_ID)
                            .build();
            mGoogleSignInClient = GoogleSignIn.getClient(activity, options);
        }
        mGoogleSignInClient.signOut();
    }

    private AuthExchangeResult exchangeGoogleIdToken(String idToken) {
        HttpURLConnection connection = null;
        try {
            JSONObject body = new JSONObject();
            body.put(
                    "postBody",
                    "id_token="
                            + Uri.encode(idToken)
                            + "&providerId="
                            + Uri.encode("google.com"));
            body.put("requestUri", OneTabFirebaseAuthConfig.REQUEST_URI);
            body.put("returnSecureToken", true);
            body.put("returnIdpCredential", true);

            connection = openJsonConnection(OneTabFirebaseAuthConfig.SIGN_IN_WITH_IDP_URL);
            writeRequestOutput(connection, body.toString());
            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode != HttpURLConnection.HTTP_OK) {
                return AuthExchangeResult.error(
                        extractFirebaseError(responseBody, "Firebase sign-in failed."));
            }

            JSONObject response = new JSONObject(responseBody);
            Log.i(
                    TAG,
                    "Firebase exchange success localId=%s email=%s",
                    response.optString("localId", ""),
                    response.optString("email", ""));
            return AuthExchangeResult.success(
                    toSession(
                            response.optString("localId", ""),
                            response.optString("email", ""),
                            response.optString("displayName", ""),
                            response.optString("photoUrl", ""),
                            response.optString("idToken", ""),
                            response.optString("refreshToken", ""),
                            response.optLong("expiresIn", 3600L)));
        } catch (Exception e) {
            Log.e(TAG, "Firebase exchange failed: %s", e.getMessage());
            return AuthExchangeResult.error("Unable to reach Firebase sign-in.");
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private AuthExchangeResult refreshSession(String refreshToken) {
        HttpURLConnection connection = null;
        try {
            String body =
                    "grant_type=refresh_token&refresh_token="
                            + URLEncoder.encode(refreshToken, StandardCharsets.UTF_8.name());
            connection = openFormConnection(OneTabFirebaseAuthConfig.REFRESH_TOKEN_URL);
            writeRequestOutput(connection, body);
            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode != HttpURLConnection.HTTP_OK) {
                return AuthExchangeResult.error(
                        extractFirebaseError(responseBody, "Firebase session refresh failed."));
            }

            JSONObject response = new JSONObject(responseBody);
            Log.i(TAG, "Firebase refresh success userId=%s", response.optString("user_id", ""));
            return AuthExchangeResult.success(
                    toSession(
                            response.optString("user_id", ""),
                            mSessionStore.read().email,
                            mSessionStore.read().displayName,
                            mSessionStore.read().photoUrl,
                            response.optString("id_token", ""),
                            response.optString("refresh_token", refreshToken),
                            response.optLong("expires_in", 3600L)));
        } catch (Exception e) {
            Log.e(TAG, "Firebase refresh failed: %s", e.getMessage());
            return AuthExchangeResult.error("Unable to refresh Firebase session.");
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static OneTabFirebaseSessionStore.Session toSession(
            String uid,
            String email,
            String displayName,
            String photoUrl,
            String idToken,
            String refreshToken,
            long expiresInSeconds) {
        long expiresAtMs = System.currentTimeMillis() + Math.max(60L, expiresInSeconds) * 1000L;
        return new OneTabFirebaseSessionStore.Session(
                uid, email, displayName, photoUrl, idToken, refreshToken, expiresAtMs);
    }

    private static HttpURLConnection openJsonConnection(String urlString) throws Exception {
        HttpURLConnection connection =
                (HttpURLConnection)
                        ChromiumNetworkAdapter.openConnection(
                                new URL(urlString), FIREBASE_AUTH_TRAFFIC_ANNOTATION);
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(15000);
        connection.setDoOutput(true);
        connection.setRequestMethod("POST");
        connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
        return connection;
    }

    private static HttpURLConnection openFormConnection(String urlString) throws Exception {
        HttpURLConnection connection =
                (HttpURLConnection)
                        ChromiumNetworkAdapter.openConnection(
                                new URL(urlString), FIREBASE_AUTH_TRAFFIC_ANNOTATION);
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(15000);
        connection.setDoOutput(true);
        connection.setRequestMethod("POST");
        connection.setRequestProperty(
                "Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
        return connection;
    }

    private static void writeRequestOutput(HttpURLConnection connection, String body)
            throws Exception {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        try (OutputStream outputStream = connection.getOutputStream()) {
            outputStream.write(bytes);
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

    private static String extractFirebaseError(String responseBody, String fallback) {
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

    private static final class AuthExchangeResult {
        final boolean success;
        final OneTabFirebaseSessionStore.Session session;
        final String message;

        private AuthExchangeResult(
                boolean success,
                OneTabFirebaseSessionStore.Session session,
                String message) {
            this.success = success;
            this.session = session;
            this.message = message;
        }

        static AuthExchangeResult success(OneTabFirebaseSessionStore.Session session) {
            return new AuthExchangeResult(true, session, "");
        }

        static AuthExchangeResult error(String message) {
            return new AuthExchangeResult(false, null, message);
        }
    }
}
