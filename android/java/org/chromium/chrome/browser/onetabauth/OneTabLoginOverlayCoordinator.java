package org.chromium.chrome.browser.onetabauth;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.appcompat.widget.AppCompatButton;

import org.chromium.chrome.R;

public class OneTabLoginOverlayCoordinator {
    public interface Listener {
        void onSignInClicked();
    }

    private FrameLayout mRootView;
    private ProgressBar mProgressBar;
    private TextView mStatusView;
    private AppCompatButton mSignInButton;
    private Listener mListener;

    public void show(Activity activity, Listener listener) {
        mListener = listener;
        ensureView(activity);
        if (mRootView.getParent() == null) {
            ViewGroup container = activity.findViewById(R.id.compositor_view_holder);
            if (container == null) {
                container = activity.findViewById(android.R.id.content);
            }
            container.addView(mRootView);
        }
        mRootView.setVisibility(View.VISIBLE);
        mRootView.bringToFront();
        mRootView.setTranslationZ(dp(activity, 64));
        mRootView.setElevation(dp(activity, 64));
    }

    public void dismiss() {
        if (mRootView != null) {
            mRootView.setVisibility(View.GONE);
        }
    }

    public void setLoading(boolean loading, String message) {
        if (mProgressBar != null) {
            mProgressBar.setVisibility(loading ? View.VISIBLE : View.GONE);
        }
        if (mSignInButton != null) {
            mSignInButton.setEnabled(!loading);
            mSignInButton.setAlpha(loading ? 0.6f : 1f);
        }
        if (mStatusView != null) {
            if (TextUtils.isEmpty(message)) {
                mStatusView.setVisibility(View.GONE);
            } else {
                mStatusView.setVisibility(View.VISIBLE);
                mStatusView.setText(message);
                mStatusView.setTextColor(Color.parseColor("#FFF3B0"));
            }
        }
    }

    public void setPrimaryActionVisible(boolean visible) {
        if (mSignInButton != null) {
            mSignInButton.setVisibility(visible ? View.VISIBLE : View.GONE);
        }
    }

    public void showError(String message) {
        if (mStatusView == null) {
            return;
        }
        if (TextUtils.isEmpty(message)) {
            mStatusView.setVisibility(View.GONE);
            return;
        }
        mStatusView.setVisibility(View.VISIBLE);
        mStatusView.setText(message);
        mStatusView.setTextColor(Color.parseColor("#FFB4AB"));
    }

    private void ensureView(Activity activity) {
        if (mRootView != null) {
            return;
        }

        int padding = dp(activity, 24);
        FrameLayout root = new FrameLayout(activity);
        root.setClickable(true);
        root.setFocusable(true);
        root.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        root.setBackgroundColor(Color.parseColor("#FF121212"));
        root.setLayoutParams(
                new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT));

        LinearLayout card = new LinearLayout(activity);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setGravity(Gravity.CENTER_HORIZONTAL);
        card.setPadding(padding, padding, padding, padding);
        GradientDrawable cardBackground = new GradientDrawable();
        cardBackground.setColor(Color.parseColor("#F0282828"));
        cardBackground.setCornerRadius(dp(activity, 24));
        card.setBackground(cardBackground);

        FrameLayout.LayoutParams cardParams =
                new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT);
        cardParams.gravity = Gravity.CENTER;
        cardParams.leftMargin = dp(activity, 24);
        cardParams.rightMargin = dp(activity, 24);
        root.addView(card, cardParams);

        ImageView logo = new ImageView(activity);
        logo.setImageResource(R.drawable.onetab_fab_logo);
        logo.setAdjustViewBounds(true);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        LinearLayout.LayoutParams logoParams =
                new LinearLayout.LayoutParams(dp(activity, 96), dp(activity, 96));
        card.addView(logo, logoParams);

        TextView title = new TextView(activity);
        title.setText("GO_PLAY");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 28);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(Color.WHITE);
        LinearLayout.LayoutParams titleParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.topMargin = dp(activity, 16);
        card.addView(title, titleParams);

        TextView subtitle = new TextView(activity);
        subtitle.setText(R.string.onetab_login_subtitle);
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        subtitle.setTextColor(Color.parseColor("#D9FFFFFF"));
        subtitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams subtitleParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT);
        subtitleParams.topMargin = dp(activity, 12);
        card.addView(subtitle, subtitleParams);

        AppCompatButton signInButton = new AppCompatButton(activity);
        signInButton.setAllCaps(false);
        signInButton.setText(R.string.onetab_login_continue_with_google);
        signInButton.setTextColor(Color.WHITE);
        signInButton.setTypeface(Typeface.DEFAULT_BOLD);
        GradientDrawable buttonBackground = new GradientDrawable();
        buttonBackground.setColor(Color.parseColor("#FFCC0000"));
        buttonBackground.setCornerRadius(dp(activity, 18));
        signInButton.setBackground(buttonBackground);
        signInButton.setPadding(dp(activity, 18), dp(activity, 14), dp(activity, 18), dp(activity, 14));
        signInButton.setOnClickListener(v -> {
            if (mListener != null) {
                mListener.onSignInClicked();
            }
        });
        LinearLayout.LayoutParams buttonParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT);
        buttonParams.topMargin = dp(activity, 24);
        card.addView(signInButton, buttonParams);

        ProgressBar progressBar = new ProgressBar(activity);
        progressBar.setVisibility(View.GONE);
        LinearLayout.LayoutParams progressParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT);
        progressParams.topMargin = dp(activity, 18);
        card.addView(progressBar, progressParams);

        TextView status = new TextView(activity);
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        status.setGravity(Gravity.CENTER);
        status.setVisibility(View.GONE);
        LinearLayout.LayoutParams statusParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT);
        statusParams.topMargin = dp(activity, 16);
        card.addView(status, statusParams);

        mRootView = root;
        mProgressBar = progressBar;
        mStatusView = status;
        mSignInButton = signInButton;
    }

    private static int dp(Activity activity, int dp) {
        return Math.round(
                dp * activity.getResources().getDisplayMetrics().density);
    }
}
