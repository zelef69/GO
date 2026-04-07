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

import org.chromium.chrome.R;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class OneTabPurchaseReceiptActivity extends AppCompatActivity {
    private static final String ADMIN_CONTACT_URL = "https://line.me/R/ti/p/%40615yysio";

    public static final String EXTRA_ORDER_ID =
            "org.chromium.chrome.browser.onetabauth.EXTRA_ORDER_ID";
    public static final String EXTRA_PACKAGE_NAME =
            "org.chromium.chrome.browser.onetabauth.EXTRA_PACKAGE_NAME";
    public static final String EXTRA_PAYMENT_REF =
            "org.chromium.chrome.browser.onetabauth.EXTRA_PAYMENT_REF";
    public static final String EXTRA_AMOUNT =
            "org.chromium.chrome.browser.onetabauth.EXTRA_AMOUNT";
    public static final String EXTRA_CURRENCY =
            "org.chromium.chrome.browser.onetabauth.EXTRA_CURRENCY";
    public static final String EXTRA_DURATION_DAYS =
            "org.chromium.chrome.browser.onetabauth.EXTRA_DURATION_DAYS";
    public static final String EXTRA_EXPIRES_AT =
            "org.chromium.chrome.browser.onetabauth.EXTRA_EXPIRES_AT";
    public static final String EXTRA_ALREADY_PROCESSED =
            "org.chromium.chrome.browser.onetabauth.EXTRA_ALREADY_PROCESSED";

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(createContentView());
    }

    private View createContentView() {
        int screenPadding = dp(24);

        String packageName =
                fallback(
                        getIntent().getStringExtra(EXTRA_PACKAGE_NAME),
                        getString(R.string.onetab_buy_receipt_unknown_value));
        String paymentRef =
                fallback(
                        getIntent().getStringExtra(EXTRA_PAYMENT_REF),
                        getString(R.string.onetab_buy_receipt_unknown_value));
        String orderId =
                fallback(
                        getIntent().getStringExtra(EXTRA_ORDER_ID),
                        getString(R.string.onetab_buy_receipt_unknown_value));
        String currency =
                fallback(
                        getIntent().getStringExtra(EXTRA_CURRENCY),
                        OneTabPackagePurchaseManager.ProductSummary.DEFAULT_CURRENCY);
        long amount = getIntent().getLongExtra(EXTRA_AMOUNT, 0L);
        int durationDays =
                getIntent().getIntExtra(
                        EXTRA_DURATION_DAYS,
                        OneTabPackagePurchaseManager.ProductSummary.DEFAULT_DURATION_DAYS);
        String expiresAtLabel = formatExpiresAt(getIntent().getStringExtra(EXTRA_EXPIRES_AT));
        boolean alreadyProcessed = getIntent().getBooleanExtra(EXTRA_ALREADY_PROCESSED, false);

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
        title.setText(R.string.onetab_buy_receipt_title);
        title.setTextColor(Color.WHITE);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30);
        LinearLayout.LayoutParams titleParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.topMargin = dp(16);
        root.addView(title, titleParams);

        TextView subtitle = new TextView(this);
        subtitle.setText(
                alreadyProcessed
                        ? R.string.onetab_buy_receipt_subtitle_reused
                        : R.string.onetab_buy_receipt_subtitle);
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

        card.addView(createFieldBlock(
                getString(R.string.onetab_buy_receipt_package_label), packageName));
        card.addView(createFieldBlock(
                getString(R.string.onetab_buy_receipt_payment_ref_label), paymentRef));
        card.addView(createFieldBlock(
                getString(R.string.onetab_buy_receipt_order_id_label), orderId));
        card.addView(createFieldBlock(
                getString(R.string.onetab_buy_receipt_amount_label),
                getString(R.string.onetab_buy_receipt_amount_value, amount, currency, durationDays)));
        card.addView(createFieldBlock(
                getString(R.string.onetab_buy_receipt_expires_label), expiresAtLabel));

        AppCompatButton accountButton = new AppCompatButton(this);
        accountButton.setAllCaps(false);
        accountButton.setText(R.string.onetab_buy_receipt_open_account);
        accountButton.setTextColor(Color.WHITE);
        accountButton.setTypeface(Typeface.DEFAULT_BOLD);
        accountButton.setBackground(createFilledButtonBackground("#FFCC0000"));
        accountButton.setPadding(dp(18), dp(14), dp(18), dp(14));
        accountButton.setOnClickListener(
                unused -> {
                    startActivity(new Intent(this, OneTabAccountActivity.class));
                    finish();
                });
        LinearLayout.LayoutParams accountParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        accountParams.topMargin = dp(24);
        card.addView(accountButton, accountParams);

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

    private View createFieldBlock(String label, String value) {
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
        return block;
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

    private String fallback(@Nullable String value, String fallbackValue) {
        return TextUtils.isEmpty(value) ? fallbackValue : value;
    }

    private String formatExpiresAt(@Nullable String rawValue) {
        Date date = parseFirestoreTimestamp(rawValue);
        if (date == null) {
            return getString(R.string.onetab_buy_receipt_unknown_value);
        }
        SimpleDateFormat format = new SimpleDateFormat("dd MMM yyyy, HH:mm", Locale.forLanguageTag("th-TH"));
        return format.format(date);
    }

    @Nullable
    private static Date parseFirestoreTimestamp(@Nullable String rawValue) {
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

    private void showToast(int messageId) {
        Toast.makeText(this, messageId, Toast.LENGTH_SHORT).show();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
