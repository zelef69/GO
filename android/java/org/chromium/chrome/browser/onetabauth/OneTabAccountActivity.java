package org.chromium.chrome.browser.onetabauth;

import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatButton;

import org.json.JSONObject;

import org.chromium.base.Log;
import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.chrome.R;
import org.chromium.net.ChromiumNetworkAdapter;
import org.chromium.net.NetworkTrafficAnnotationTag;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

public class OneTabAccountActivity extends AppCompatActivity {
    private static final String TAG = "OneTabAccount";
    private static final String ADMIN_CONTACT_URL = "https://line.me/R/ti/p/%40615yysio";
    private static final String PRIMARY_PACKAGE_ID = "pkg_599";
    private static final NetworkTrafficAnnotationTag ACCOUNT_LOOKUP_TRAFFIC_ANNOTATION =
            NetworkTrafficAnnotationTag.MISSING_TRAFFIC_ANNOTATION;

    private final OneTabFirebaseAuthManager mAuthManager = new OneTabFirebaseAuthManager();

    private TextView mEmailValueView;
    private TextView mRemainingDaysValueView;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(createContentView());
        refreshAccountSummary();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshAccountSummary();
    }

    private View createContentView() {
        int screenPadding = dp(24);

        ScrollView scrollView = new ScrollView(this);
        scrollView.setFillViewport(true);
        scrollView.setBackgroundColor(Color.parseColor("#FF121212"));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(screenPadding, screenPadding, screenPadding, screenPadding);
        scrollView.addView(
                root,
                new ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.onetab_fab_logo);
        logo.setAdjustViewBounds(true);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        root.addView(logo, new LinearLayout.LayoutParams(dp(88), dp(88)));

        TextView title = new TextView(this);
        title.setText(R.string.onetab_account_title);
        title.setTextColor(Color.WHITE);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30);
        LinearLayout.LayoutParams titleParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.topMargin = dp(16);
        root.addView(title, titleParams);

        TextView subtitle = new TextView(this);
        subtitle.setText(R.string.onetab_account_subtitle);
        subtitle.setTextColor(Color.parseColor("#D9FFFFFF"));
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        LinearLayout.LayoutParams subtitleParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        subtitleParams.topMargin = dp(10);
        root.addView(subtitle, subtitleParams);

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(screenPadding, screenPadding, screenPadding, screenPadding);
        GradientDrawable cardBackground = new GradientDrawable();
        cardBackground.setColor(Color.parseColor("#FF1F1F1F"));
        cardBackground.setCornerRadius(dp(24));
        card.setBackground(cardBackground);

        LinearLayout.LayoutParams cardParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cardParams.topMargin = dp(24);
        root.addView(card, cardParams);

        FieldBlock emailBlock =
                createFieldBlock(
                        getString(R.string.onetab_account_email_label),
                        getString(R.string.onetab_account_email_missing));
        mEmailValueView = emailBlock.valueView;
        card.addView(emailBlock.container);

        FieldBlock remainingBlock =
                createFieldBlock(
                        getString(R.string.onetab_account_remaining_days_label),
                        getString(R.string.onetab_account_remaining_days_pending));
        mRemainingDaysValueView = remainingBlock.valueView;
        card.addView(remainingBlock.container);

        AppCompatButton buyPackageButton = new AppCompatButton(this);
        buyPackageButton.setAllCaps(false);
        buyPackageButton.setText(R.string.onetab_account_buy_package);
        buyPackageButton.setTextColor(Color.WHITE);
        buyPackageButton.setTypeface(Typeface.DEFAULT_BOLD);
        buyPackageButton.setBackground(createFilledButtonBackground("#FFCC0000"));
        buyPackageButton.setPadding(dp(18), dp(14), dp(18), dp(14));
        buyPackageButton.setOnClickListener(
                unused -> startActivity(new Intent(this, OneTabBuyPackageActivity.class)));
        LinearLayout.LayoutParams buyParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        buyParams.topMargin = dp(24);
        card.addView(buyPackageButton, buyParams);

        AppCompatButton contactAdminButton = new AppCompatButton(this);
        contactAdminButton.setAllCaps(false);
        contactAdminButton.setText(R.string.onetab_account_contact_admin);
        contactAdminButton.setTextColor(Color.WHITE);
        contactAdminButton.setTypeface(Typeface.DEFAULT_BOLD);
        contactAdminButton.setBackground(createOutlineButtonBackground());
        contactAdminButton.setPadding(dp(18), dp(14), dp(18), dp(14));
        contactAdminButton.setOnClickListener(unused -> openAdminContact());
        LinearLayout.LayoutParams adminParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        adminParams.topMargin = dp(14);
        card.addView(contactAdminButton, adminParams);

        return scrollView;
    }

    private void refreshAccountSummary() {
        OneTabFirebaseSessionStore.Session session = new OneTabFirebaseSessionStore().read();
        updateEmail(session);
        mRemainingDaysValueView.setText(R.string.onetab_account_remaining_days_loading);

        mAuthManager.resolveAuthentication(
                (authenticated, message) -> {
                    if (!authenticated) {
                        mRemainingDaysValueView.setText(R.string.onetab_account_remaining_days_error);
                        if (!TextUtils.isEmpty(message)) {
                            showToastMessage(message);
                        }
                        return;
                    }

                    OneTabFirebaseSessionStore.Session refreshedSession =
                            new OneTabFirebaseSessionStore().read();
                    updateEmail(refreshedSession);
                    fetchRemainingDays(refreshedSession);
                });
    }

    private void updateEmail(OneTabFirebaseSessionStore.Session session) {
        if (mEmailValueView == null) return;
        mEmailValueView.setText(
                !TextUtils.isEmpty(session.email)
                        ? session.email
                        : getString(R.string.onetab_account_email_missing));
    }

    private void fetchRemainingDays(OneTabFirebaseSessionStore.Session session) {
        if (TextUtils.isEmpty(session.uid) || TextUtils.isEmpty(session.idToken)) {
            mRemainingDaysValueView.setText(R.string.onetab_account_remaining_days_error);
            return;
        }

        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                () -> {
                    EntitlementLookupResult result = lookupRemainingDays(session);
                    PostTask.postTask(
                            TaskTraits.UI_DEFAULT,
                            () -> {
                                if (isFinishing() || isDestroyed()) return;
                                mRemainingDaysValueView.setText(result.label);
                            });
                });
    }

    private EntitlementLookupResult lookupRemainingDays(OneTabFirebaseSessionStore.Session session) {
        HttpURLConnection connection = null;
        try {
            String url =
                    OneTabFirebaseAuthConfig.FIRESTORE_BASE_URL
                            + "/users/"
                            + Uri.encode(session.uid)
                            + "/entitlements/"
                            + Uri.encode(PRIMARY_PACKAGE_ID);
            connection =
                    (HttpURLConnection)
                            ChromiumNetworkAdapter.openConnection(
                                    new URL(url), ACCOUNT_LOOKUP_TRAFFIC_ANNOTATION);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Authorization", "Bearer " + session.idToken);
            connection.setRequestProperty("Accept", "application/json");

            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode == HttpURLConnection.HTTP_NOT_FOUND) {
                return EntitlementLookupResult.of(
                        getString(R.string.onetab_account_remaining_days_none));
            }
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "lookupRemainingDays failed code=%d body=%s", responseCode, responseBody);
                return EntitlementLookupResult.of(
                        getString(R.string.onetab_account_remaining_days_error));
            }

            JSONObject root = new JSONObject(responseBody);
            JSONObject fields = root.optJSONObject("fields");
            if (fields == null) {
                return EntitlementLookupResult.of(
                        getString(R.string.onetab_account_remaining_days_none));
            }

            boolean active = readBooleanField(fields, "active", false);
            String expiresAtValue = readTimestampField(fields, "expiresAt");
            Date expiresAt = parseFirestoreTimestamp(expiresAtValue);
            if (!active || expiresAt == null || expiresAt.getTime() <= System.currentTimeMillis()) {
                return EntitlementLookupResult.of(
                        getString(R.string.onetab_account_remaining_days_none));
            }

            long diffMs = expiresAt.getTime() - System.currentTimeMillis();
            long remainingDays = Math.max(1L,
                    (long) Math.ceil(diffMs / (double) TimeUnit.DAYS.toMillis(1)));
            return EntitlementLookupResult.of(
                    getString(R.string.onetab_account_remaining_days_value, remainingDays));
        } catch (Exception e) {
            Log.e(TAG, "lookupRemainingDays error=%s", e.getMessage());
            return EntitlementLookupResult.of(
                    getString(R.string.onetab_account_remaining_days_error));
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private static boolean readBooleanField(JSONObject fields, String fieldName, boolean fallback) {
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return fallback;
        return field.optBoolean("booleanValue", fallback);
    }

    private static String readTimestampField(JSONObject fields, String fieldName) {
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return "";
        return field.optString("timestampValue", "");
    }

    private static Date parseFirestoreTimestamp(String rawValue) {
        if (TextUtils.isEmpty(rawValue)) return null;
        String normalized = rawValue.trim();
        if (normalized.endsWith("Z") && normalized.contains(".")) {
            int dotIndex = normalized.indexOf('.');
            int zIndex = normalized.lastIndexOf('Z');
            String fraction = normalized.substring(dotIndex + 1, zIndex);
            if (fraction.length() > 3) {
                fraction = fraction.substring(0, 3);
            } else {
                while (fraction.length() < 3) {
                    fraction += "0";
                }
            }
            normalized = normalized.substring(0, dotIndex) + "." + fraction + "Z";
        }

        String[] patterns = {
            "yyyy-MM-dd'T'HH:mm:ss.SSSX",
            "yyyy-MM-dd'T'HH:mm:ssX",
        };
        for (String pattern : patterns) {
            try {
                SimpleDateFormat format = new SimpleDateFormat(pattern, Locale.US);
                format.setLenient(false);
                return format.parse(normalized);
            } catch (Exception ignored) {
            }
        }
        return null;
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

    private FieldBlock createFieldBlock(String label, String value) {
        LinearLayout block = new LinearLayout(this);
        block.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.parseColor("#FF2B2B2B"));
        background.setCornerRadius(dp(18));
        block.setBackground(background);
        block.setPadding(dp(18), dp(16), dp(18), dp(16));

        TextView labelView = new TextView(this);
        labelView.setText(label);
        labelView.setTextColor(Color.parseColor("#B3FFFFFF"));
        labelView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        block.addView(labelView);

        TextView valueView = new TextView(this);
        valueView.setText(value);
        valueView.setTextColor(Color.WHITE);
        valueView.setTypeface(Typeface.DEFAULT_BOLD);
        valueView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        LinearLayout.LayoutParams valueParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        valueParams.topMargin = dp(8);
        block.addView(valueView, valueParams);

        LinearLayout.LayoutParams blockParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        blockParams.topMargin = dp(14);
        block.setLayoutParams(blockParams);
        return new FieldBlock(block, valueView);
    }

    private GradientDrawable createFilledButtonBackground(String color) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(Color.parseColor(color));
        drawable.setCornerRadius(dp(18));
        return drawable;
    }

    private GradientDrawable createOutlineButtonBackground() {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(Color.TRANSPARENT);
        drawable.setCornerRadius(dp(18));
        drawable.setStroke(dp(1), Color.parseColor("#66FFFFFF"));
        return drawable;
    }

    private void openAdminContact() {
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(ADMIN_CONTACT_URL));
        intent.addCategory(Intent.CATEGORY_BROWSABLE);
        PackageManager packageManager = getPackageManager();
        if (intent.resolveActivity(packageManager) == null) {
            showToast(R.string.onetab_fab_admin_unavailable);
            return;
        }
        startActivity(intent);
    }

    private void showToast(int messageId) {
        Toast.makeText(this, messageId, Toast.LENGTH_SHORT).show();
    }

    private void showToastMessage(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static final class FieldBlock {
        final View container;
        final TextView valueView;

        FieldBlock(View container, TextView valueView) {
            this.container = container;
            this.valueView = valueView;
        }
    }

    private static final class EntitlementLookupResult {
        final String label;

        private EntitlementLookupResult(String label) {
            this.label = label;
        }

        static EntitlementLookupResult of(String label) {
            return new EntitlementLookupResult(label);
        }
    }
}
