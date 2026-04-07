package org.chromium.chrome.browser.onetabauth;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatButton;

import org.chromium.base.Log;
import org.chromium.chrome.R;

public class OneTabLoginActivity extends AppCompatActivity {
    public static final String EXTRA_ERROR_MESSAGE = "org.chromium.chrome.browser.onetabauth.ERROR";
    private static final String TAG = "OneTabLoginActivity";

    private OneTabFirebaseAuthManager mAuthManager;
    private OneTabDeviceSessionManager mDeviceSessionManager;
    private AppCompatButton mSignInButton;
    private AppCompatButton mOpenAccountButton;
    private ProgressBar mProgressBar;
    private TextView mStatusView;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.i(TAG, "onCreate savedState=%s", savedInstanceState != null);
        mAuthManager = new OneTabFirebaseAuthManager();
        mDeviceSessionManager = new OneTabDeviceSessionManager();
        setContentView(createContentView());

        String startupError = getIntent().getStringExtra(EXTRA_ERROR_MESSAGE);
        if (!TextUtils.isEmpty(startupError)) {
            showError(startupError);
        }

        checkSignedInAccess();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (mAuthManager != null && mAuthManager.isSignedInFast()) {
            checkSignedInAccess();
        }
    }

    @Override
    public void onBackPressed() {
        setResult(Activity.RESULT_CANCELED);
        moveTaskToBack(true);
        super.onBackPressed();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        Log.i(
                TAG,
                "activityResult requestCode=%d resultCode=%d hasData=%s",
                requestCode,
                resultCode,
                data != null);
        if (mAuthManager != null && mAuthManager.onActivityResult(requestCode, resultCode, data)) {
            if (resultCode != RESULT_OK) {
                setLoading(false, "");
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    private View createContentView() {
        int padding = dp(24);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setBackgroundColor(Color.parseColor("#FF121212"));
        root.setLayoutParams(
                new ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setGravity(Gravity.CENTER_HORIZONTAL);
        card.setPadding(padding, padding, padding, padding);
        GradientDrawable cardBackground = new GradientDrawable();
        cardBackground.setColor(Color.parseColor("#FF282828"));
        cardBackground.setCornerRadius(dp(24));
        card.setBackground(cardBackground);

        LinearLayout.LayoutParams cardParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cardParams.leftMargin = dp(24);
        cardParams.rightMargin = dp(24);
        root.addView(card, cardParams);

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.onetab_fab_logo);
        logo.setAdjustViewBounds(true);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        card.addView(logo, new LinearLayout.LayoutParams(dp(96), dp(96)));

        TextView title = new TextView(this);
        title.setText("GO_PLAY");
        title.setTextColor(Color.WHITE);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 28);
        LinearLayout.LayoutParams titleParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.topMargin = dp(16);
        card.addView(title, titleParams);

        TextView subtitle = new TextView(this);
        subtitle.setText(R.string.onetab_login_subtitle);
        subtitle.setTextColor(Color.parseColor("#D9FFFFFF"));
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        LinearLayout.LayoutParams subtitleParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        subtitleParams.topMargin = dp(12);
        card.addView(subtitle, subtitleParams);

        mSignInButton = new AppCompatButton(this);
        mSignInButton.setAllCaps(false);
        mSignInButton.setText(R.string.onetab_login_continue_with_google);
        mSignInButton.setTextColor(Color.WHITE);
        mSignInButton.setTypeface(Typeface.DEFAULT_BOLD);
        GradientDrawable buttonBackground = new GradientDrawable();
        buttonBackground.setColor(Color.parseColor("#FFCC0000"));
        buttonBackground.setCornerRadius(dp(18));
        mSignInButton.setBackground(buttonBackground);
        mSignInButton.setPadding(dp(18), dp(14), dp(18), dp(14));
        mSignInButton.setOnClickListener(
                v -> {
                    Log.i(TAG, "Continue with Google clicked");
                    showAccountAction(false);
                    setLoading(true, getString(R.string.onetab_login_loading_signin));
                    mAuthManager.beginGoogleSignIn(
                            this,
                            (authenticated, message) -> {
                                Log.i(
                                        TAG,
                                        "beginGoogleSignIn callback authenticated=%s message=%s",
                                        authenticated,
                                        TextUtils.isEmpty(message) ? "<empty>" : message);
                                if (authenticated) {
                                    resolveDeviceAccess();
                                } else {
                                    setLoading(false, "");
                                    showError(message);
                                }
                            });
                });
        LinearLayout.LayoutParams buttonParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        buttonParams.topMargin = dp(24);
        card.addView(mSignInButton, buttonParams);

        mOpenAccountButton = new AppCompatButton(this);
        mOpenAccountButton.setAllCaps(false);
        mOpenAccountButton.setText(R.string.onetab_login_open_account);
        mOpenAccountButton.setTextColor(Color.WHITE);
        mOpenAccountButton.setTypeface(Typeface.DEFAULT_BOLD);
        GradientDrawable outline = new GradientDrawable();
        outline.setColor(Color.TRANSPARENT);
        outline.setCornerRadius(dp(18));
        outline.setStroke(dp(1), Color.parseColor("#66FFFFFF"));
        mOpenAccountButton.setBackground(outline);
        mOpenAccountButton.setPadding(dp(18), dp(14), dp(18), dp(14));
        mOpenAccountButton.setVisibility(View.GONE);
        mOpenAccountButton.setOnClickListener(
                unused -> startActivity(new Intent(this, OneTabAccountActivity.class)));
        LinearLayout.LayoutParams accountButtonParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        accountButtonParams.topMargin = dp(14);
        card.addView(mOpenAccountButton, accountButtonParams);

        mProgressBar = new ProgressBar(this);
        mProgressBar.setVisibility(View.GONE);
        LinearLayout.LayoutParams progressParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        progressParams.topMargin = dp(18);
        card.addView(mProgressBar, progressParams);

        mStatusView = new TextView(this);
        mStatusView.setGravity(Gravity.CENTER);
        mStatusView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        mStatusView.setVisibility(View.GONE);
        LinearLayout.LayoutParams statusParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        statusParams.topMargin = dp(16);
        card.addView(mStatusView, statusParams);

        return root;
    }

    private void checkSignedInAccess() {
        setLoading(true, getString(R.string.onetab_login_loading_session));
        mAuthManager.resolveAuthentication(
                (authenticated, message) -> {
                    Log.i(
                            TAG,
                            "resolveAuthentication callback authenticated=%s message=%s",
                            authenticated,
                            TextUtils.isEmpty(message) ? "<empty>" : message);
                    if (authenticated) {
                        resolveDeviceAccess();
                    } else {
                        setLoading(false, "");
                        showAccountAction(false);
                        if (!TextUtils.isEmpty(message)) {
                            showError(message);
                        }
                    }
                });
    }

    private void resolveDeviceAccess() {
        setLoading(true, getString(R.string.onetab_login_loading_device_access));
        OneTabFirebaseSessionStore.Session session = new OneTabFirebaseSessionStore().read();
        mDeviceSessionManager.ensureAccess(
                session,
                (allowed, message) -> {
                    Log.i(
                            TAG,
                            "resolveDeviceAccess callback allowed=%s message=%s",
                            allowed,
                            TextUtils.isEmpty(message) ? "<empty>" : message);
                    if (allowed) {
                        finishAuthenticated();
                        return;
                    }
                    setLoading(false, "");
                    showAccountAction(false);
                    showError(message);
                });
    }

    private void setLoading(boolean loading, String message) {
        mProgressBar.setVisibility(loading ? View.VISIBLE : View.GONE);
        mSignInButton.setEnabled(!loading);
        mSignInButton.setAlpha(loading ? 0.6f : 1f);
        if (TextUtils.isEmpty(message)) {
            mStatusView.setVisibility(View.GONE);
        } else {
            mStatusView.setVisibility(View.VISIBLE);
            mStatusView.setText(message);
            mStatusView.setTextColor(Color.parseColor("#FFF3B0"));
        }
    }

    private void showError(@Nullable String message) {
        if (TextUtils.isEmpty(message)) {
            mStatusView.setVisibility(View.GONE);
            return;
        }
        mStatusView.setVisibility(View.VISIBLE);
        mStatusView.setText(message);
        mStatusView.setTextColor(Color.parseColor("#FFB4AB"));
    }

    private void showAccountAction(boolean visible) {
        mOpenAccountButton.setVisibility(visible ? View.VISIBLE : View.GONE);
    }

    private void finishAuthenticated() {
        Log.i(TAG, "finishAuthenticated");
        setResult(Activity.RESULT_OK);
        finish();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
