package org.chromium.chrome.browser.onetabauth;

final class OneTabFirebaseAuthConfig {
    static final String API_KEY = "AIzaSyA_a-_0x_bevdX6Vj6e-d9yZxSBXeAKQaU";
    static final String PROJECT_NUMBER = "777514708716";
    static final String PROJECT_ID = "go-play-720c1";
    static final String APP_ID = "1:777514708716:android:3dd12e985da0971c7c7fc9";
    static final String STORAGE_BUCKET = "go-play-720c1.firebasestorage.app";
    static final String FUNCTIONS_REGION = "us-central1";
    static final String WEB_CLIENT_ID =
            "777514708716-rfrg1kdgoif473lt91duogfnbhn1ihja.apps.googleusercontent.com";
    static final String SIGN_IN_WITH_IDP_URL =
            "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=" + API_KEY;
    static final String REFRESH_TOKEN_URL =
            "https://securetoken.googleapis.com/v1/token?key=" + API_KEY;
    static final String FUNCTIONS_BASE_URL =
            "https://" + FUNCTIONS_REGION + "-" + PROJECT_ID + ".cloudfunctions.net";
    static final String FIRESTORE_BASE_URL =
            "https://firestore.googleapis.com/v1/projects/"
                    + PROJECT_ID
                    + "/databases/(default)/documents";
    static final String APP_CHECK_EXCHANGE_URL =
            "https://firebaseappcheck.googleapis.com/v1beta/projects/"
                    + PROJECT_NUMBER
                    + "/apps/"
                    + APP_ID
                    + ":exchangePlayIntegrityToken?key="
                    + API_KEY;
    static final String APP_CHECK_DEBUG_EXCHANGE_URL =
            "https://firebaseappcheck.googleapis.com/v1beta/projects/"
                    + PROJECT_NUMBER
                    + "/apps/"
                    + APP_ID
                    + ":exchangeDebugToken?key="
                    + API_KEY;
    static final String APP_CHECK_DEBUG_TOKEN = "f729271b-528c-4a71-a747-3d46ed47430f";
    static final String REQUEST_URI = "http://localhost";

    private OneTabFirebaseAuthConfig() {}
}
