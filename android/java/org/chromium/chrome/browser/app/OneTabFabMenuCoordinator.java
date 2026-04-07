/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.app;

import android.content.Intent;
import android.os.SystemClock;
import android.view.HapticFeedbackConstants;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.widget.AppCompatImageButton;
import androidx.core.view.ViewCompat;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.OneTabYouTubeMode;
import org.chromium.chrome.browser.media.PictureInPicture;
import org.chromium.chrome.browser.onetabauth.OneTabAccountActivity;
import org.chromium.chrome.browser.onetabauth.OneTabDeviceSessionManager;
import org.chromium.chrome.browser.onetabauth.OneTabFirebaseAuthManager;
import org.chromium.chrome.browser.onetabauth.OneTabLoginActivity;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.chrome.browser.youtube_script_injector.BraveYouTubeScriptInjectorNativeHelper;
import org.chromium.content_public.browser.WebContents;

final class OneTabFabMenuCoordinator {
    private static final long SLEEP_WAKE_DOUBLE_TAP_WINDOW_MS = 450L;
    private static final long MENU_ANIMATION_DURATION_MS = 180L;
    private static final long FAB_PIP_RETRY_1_MS = 220L;
    private static final long FAB_PIP_RETRY_2_MS = 480L;

    private final BraveActivity mActivity;
    private final LayoutInflater mInflater;
    private final int mMenuHiddenTranslationPx;
    private final int mTouchSlopPx;
    private final int mLongPressTimeoutMs;

    @Nullable private View mRootView;
    @Nullable private View mAnchorView;
    @Nullable private View mMenuView;
    @Nullable private AppCompatImageButton mMainFab;
    @Nullable private TextView mPipButton;
    @Nullable private TextView mAccountButton;
    @Nullable private TextView mLogoutButton;

    private boolean mMenuExpanded;
    private boolean mSleepMode;
    private boolean mForceHidden;
    private long mLastSleepTapElapsedMs;
    private float mFabDownRawX;
    private float mFabDownRawY;
    private float mAnchorDownX;
    private float mAnchorDownY;
    private boolean mFabDragging;
    private boolean mFabLongPressHandled;

    @Nullable private Runnable mFabLongPressRunnable;

    OneTabFabMenuCoordinator(@NonNull BraveActivity activity) {
        mActivity = activity;
        mInflater = LayoutInflater.from(activity);
        mMenuHiddenTranslationPx =
                Math.round(activity.getResources().getDisplayMetrics().density * 24f);
        mTouchSlopPx = ViewConfiguration.get(activity).getScaledTouchSlop();
        mLongPressTimeoutMs = ViewConfiguration.getLongPressTimeout();
    }

    void refresh(@Nullable Tab tab) {
        ensureAttached();
        if (mRootView == null) {
            return;
        }

        boolean visible =
                OneTabYouTubeMode.isEnabled()
                        && !mForceHidden
                        && !mActivity.isInPictureInPictureMode()
                        && tab != null
                        && !tab.isIncognito()
                        && OneTabYouTubeMode.isYouTubeUrl(tab.getUrl().getSpec());
        if (!visible) {
            collapseMenu(false);
            mRootView.setVisibility(View.GONE);
            return;
        }

        mRootView.setVisibility(View.VISIBLE);
        promoteOverlayToFront();
        updateSleepUi();
        updatePipAvailability(tab);
    }

    void setForceHidden(boolean forceHidden) {
        if (mForceHidden == forceHidden) {
            return;
        }
        mForceHidden = forceHidden;
        if (mForceHidden) {
            collapseMenu(false);
            if (mRootView != null) {
                mRootView.setVisibility(View.GONE);
            }
        }
    }

    void destroy() {
        if (mRootView == null) {
            return;
        }
        ViewParent parent = mRootView.getParent();
        if (parent instanceof ViewGroup) {
            ((ViewGroup) parent).removeView(mRootView);
        }
        mRootView = null;
        mAnchorView = null;
        mMenuView = null;
        mMainFab = null;
        mPipButton = null;
        mAccountButton = null;
        mLogoutButton = null;
        mFabLongPressRunnable = null;
    }

    private void ensureAttached() {
        if (mRootView != null && mRootView.getParent() != null) {
            promoteOverlayToFront();
            return;
        }

        ViewGroup host = resolveHostView();
        if (host == null) {
            return;
        }

        View root = mInflater.inflate(R.layout.onetab_fab_overlay, host, false);
        mRootView = root;
        mAnchorView = root.findViewById(R.id.onetab_fab_anchor);
        mMenuView = root.findViewById(R.id.onetab_fab_menu);
        mMainFab = root.findViewById(R.id.onetab_fab_main_button);
        mPipButton = root.findViewById(R.id.onetab_fab_pip);
        mAccountButton = root.findViewById(R.id.onetab_fab_account);
        mLogoutButton = root.findViewById(R.id.onetab_fab_logout);

        if (mMainFab != null) {
            mMainFab.setImageTintList(null);
            mMainFab.setOnTouchListener(this::onMainFabTouch);
            ViewCompat.setElevation(mMainFab, 0f);
            ViewCompat.setTranslationZ(mMainFab, 0f);
        }

        bindMenuAction(
                mPipButton,
                () -> {
                    Tab activityTab = mActivity.getActivityTab();
                    if (!canAttemptPictureInPicture(activityTab)) {
                        showToast(R.string.onetab_fab_pip_unavailable);
                        return;
                    }
                    collapseMenu(true);
                    WebContents webContents = activityTab != null ? activityTab.getWebContents() : null;
                    if (webContents == null) {
                        showToast(R.string.onetab_fab_pip_unavailable);
                        return;
                    }
                    triggerPictureInPictureWithRetry(webContents);
                });
        bindMenuAction(
                mAccountButton,
                () -> {
                    collapseMenu(true);
                    Intent intent = new Intent(mActivity, OneTabAccountActivity.class);
                    mActivity.startActivity(intent);
                });
        bindMenuAction(
                mLogoutButton,
                () -> {
                    collapseMenu(true);
                    startLogoutFlow();
                });

        host.addView(
                root,
                new ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        promoteOverlayToFront();
        collapseMenu(false);
        updateSleepUi();
    }

    @Nullable
    private ViewGroup resolveHostView() {
        View contentView = mActivity.findViewById(android.R.id.content);
        if (contentView instanceof ViewGroup) {
            return (ViewGroup) contentView;
        }

        ViewGroup host = mActivity.findViewById(R.id.coordinator);
        if (host != null) {
            return host;
        }

        host = mActivity.findViewById(R.id.compositor_view_holder);
        if (host != null) {
            return host;
        }

        return null;
    }

    private void promoteOverlayToFront() {
        if (mRootView == null) {
            return;
        }

        ViewParent parent = mRootView.getParent();
        if (parent instanceof ViewGroup) {
            ViewGroup host = (ViewGroup) parent;
            host.bringChildToFront(mRootView);
            host.invalidate();
        }

        mRootView.bringToFront();
        ViewCompat.setElevation(mRootView, 0f);
        ViewCompat.setTranslationZ(mRootView, 1000f);
        if (mAnchorView != null) {
            mAnchorView.bringToFront();
            ViewCompat.setElevation(mAnchorView, 0f);
            ViewCompat.setTranslationZ(mAnchorView, 1001f);
        }
        if (mMenuView != null) {
            mMenuView.bringToFront();
            ViewCompat.setElevation(mMenuView, 0f);
            ViewCompat.setTranslationZ(mMenuView, 1002f);
        }
        if (mMainFab != null) {
            mMainFab.bringToFront();
            ViewCompat.setElevation(mMainFab, 0f);
            ViewCompat.setTranslationZ(mMainFab, 0f);
        }
    }

    private void onMainFabClicked() {
        if (mSleepMode) {
            handleSleepingMainFabTap();
            return;
        }

        if (mMenuExpanded) {
            collapseMenu(true);
        } else {
            expandMenu();
        }
    }

    private void handleSleepingMainFabTap() {
        long now = SystemClock.elapsedRealtime();
        if (now - mLastSleepTapElapsedMs <= SLEEP_WAKE_DOUBLE_TAP_WINDOW_MS) {
            wakeFromSleep();
            return;
        }

        mLastSleepTapElapsedMs = now;
        showToast(R.string.onetab_fab_sleep_wake_hint);
    }

    private boolean onMainFabTouch(View view, MotionEvent event) {
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                mFabDragging = false;
                mFabLongPressHandled = false;
                mFabDownRawX = event.getRawX();
                mFabDownRawY = event.getRawY();
                mAnchorDownX = mAnchorView != null ? mAnchorView.getX() : 0f;
                mAnchorDownY = mAnchorView != null ? mAnchorView.getY() : 0f;
                scheduleFabLongPress(view);
                return true;
            case MotionEvent.ACTION_MOVE:
                float deltaX = event.getRawX() - mFabDownRawX;
                float deltaY = event.getRawY() - mFabDownRawY;
                if (!mFabDragging
                        && (Math.abs(deltaX) > mTouchSlopPx || Math.abs(deltaY) > mTouchSlopPx)) {
                    mFabDragging = true;
                    cancelFabLongPress();
                    collapseMenu(false);
                }
                if (mFabDragging) {
                    moveAnchorTo(mAnchorDownX + deltaX, mAnchorDownY + deltaY);
                }
                return true;
            case MotionEvent.ACTION_UP:
                cancelFabLongPress();
                if (mFabLongPressHandled) {
                    return true;
                }
                if (mFabDragging) {
                    mFabDragging = false;
                    return true;
                }
                view.performClick();
                onMainFabClicked();
                return true;
            case MotionEvent.ACTION_CANCEL:
                cancelFabLongPress();
                mFabDragging = false;
                return true;
            default:
                return false;
        }
    }

    private void scheduleFabLongPress(@NonNull View view) {
        cancelFabLongPress();
        mFabLongPressRunnable =
                () -> {
                    if (mFabDragging) {
                        return;
                    }
                    mFabLongPressHandled = true;
                    view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
                    if (mSleepMode) {
                        wakeFromSleep();
                    } else {
                        enterSleepMode();
                    }
                };
        view.postDelayed(mFabLongPressRunnable, mLongPressTimeoutMs);
    }

    private void cancelFabLongPress() {
        if (mMainFab != null && mFabLongPressRunnable != null) {
            mMainFab.removeCallbacks(mFabLongPressRunnable);
        }
        mFabLongPressRunnable = null;
    }

    private void moveAnchorTo(float desiredX, float desiredY) {
        moveAnchorTo(desiredX, desiredY, false);
    }

    private void moveAnchorTo(float desiredX, float desiredY, boolean includeExpandedMenuBounds) {
        if (mRootView == null || mAnchorView == null) {
            return;
        }

        int anchorWidth = mAnchorView.getWidth();
        int anchorHeight = mAnchorView.getHeight();
        if (includeExpandedMenuBounds) {
            anchorWidth = getExpandedAnchorWidth(anchorWidth);
            anchorHeight = getExpandedAnchorHeight(anchorHeight);
        }

        float maxX = Math.max(0f, mRootView.getWidth() - anchorWidth);
        float maxY = Math.max(0f, mRootView.getHeight() - anchorHeight);
        float clampedX = Math.max(0f, Math.min(maxX, desiredX));
        float clampedY = Math.max(0f, Math.min(maxY, desiredY));
        mAnchorView.setX(clampedX);
        mAnchorView.setY(clampedY);
    }

    private int getExpandedAnchorWidth(int fallbackWidth) {
        if (mMainFab == null || mMenuView == null) {
            return fallbackWidth;
        }

        int menuWidth = ensureMeasuredSize(mMenuView, true);
        int fabWidth = mMainFab.getWidth();
        if (menuWidth <= 0 || fabWidth <= 0) {
            return fallbackWidth;
        }
        return menuWidth + fabWidth;
    }

    private int getExpandedAnchorHeight(int fallbackHeight) {
        if (mMainFab == null || mMenuView == null) {
            return fallbackHeight;
        }

        int menuHeight = ensureMeasuredSize(mMenuView, false);
        int fabHeight = mMainFab.getHeight();
        if (menuHeight <= 0 || fabHeight <= 0) {
            return fallbackHeight;
        }
        return Math.max(menuHeight, fabHeight);
    }

    private int ensureMeasuredSize(@NonNull View view, boolean width) {
        int size = width ? view.getWidth() : view.getHeight();
        if (size > 0) {
            return size;
        }

        int unspecified = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED);
        view.measure(unspecified, unspecified);
        return width ? view.getMeasuredWidth() : view.getMeasuredHeight();
    }

    private void enterSleepMode() {
        mSleepMode = true;
        mLastSleepTapElapsedMs = 0L;
        collapseMenu(false);
        updateSleepUi();
        showToast(R.string.onetab_fab_sleep_enabled);
    }

    private void wakeFromSleep() {
        mSleepMode = false;
        mLastSleepTapElapsedMs = 0L;
        updateSleepUi();
        showToast(R.string.onetab_fab_sleep_disabled);
    }

    private void updateSleepUi() {
        if (mMainFab != null) {
            mMainFab.animate().cancel();
            mMainFab.animate()
                    .alpha(mSleepMode ? 0.5f : 1f)
                    .setDuration(MENU_ANIMATION_DURATION_MS)
                    .start();
        }
    }

    private void expandMenu() {
        if (mMenuView == null || mMenuExpanded) {
            return;
        }

        moveAnchorTo(
                mAnchorView != null ? mAnchorView.getX() : 0f,
                mAnchorView != null ? mAnchorView.getY() : 0f,
                true);
        mMenuExpanded = true;
        mMenuView.animate().cancel();
        mMenuView.setVisibility(View.VISIBLE);
        mMenuView.setAlpha(0f);
        mMenuView.setTranslationX(mMenuHiddenTranslationPx);
        mMenuView.animate()
                .alpha(1f)
                .translationX(0f)
                .setDuration(MENU_ANIMATION_DURATION_MS)
                .start();
    }

    private void collapseMenu(boolean animate) {
        if (mMenuView == null) {
            return;
        }

        mMenuExpanded = false;
        mMenuView.animate().cancel();
        if (!animate) {
            mMenuView.setAlpha(0f);
            mMenuView.setTranslationX(mMenuHiddenTranslationPx);
            mMenuView.setVisibility(View.GONE);
            return;
        }

        mMenuView.animate()
                .alpha(0f)
                .translationX(mMenuHiddenTranslationPx)
                .setDuration(MENU_ANIMATION_DURATION_MS)
                .withEndAction(
                        () -> {
                            if (mMenuView != null && !mMenuExpanded) {
                                mMenuView.setVisibility(View.GONE);
                            }
                        })
                .start();
    }

    private void updatePipAvailability(@Nullable Tab tab) {
        boolean available = canAttemptPictureInPicture(tab);
        if (mPipButton != null) {
            mPipButton.setEnabled(available);
            mPipButton.setAlpha(available ? 1f : 0.45f);
        }
    }

    private boolean canAttemptPictureInPicture(@Nullable Tab tab) {
        if (tab == null || !PictureInPicture.isEnabled(mActivity)) {
            return false;
        }

        return tab.getWebContents() != null;
    }

    private void triggerPictureInPictureWithRetry(@NonNull WebContents webContents) {
        // Mark manual PiP intent and request fullscreen-path first for watch-page reliability.
        BraveYouTubeScriptInjectorNativeHelper.setFullscreen(webContents);
        BraveYouTubeScriptInjectorNativeHelper.enterPictureInPicture(webContents);

        if (mRootView == null) {
            return;
        }

        mRootView.postDelayed(
                () -> BraveYouTubeScriptInjectorNativeHelper.enterPictureInPicture(webContents),
                FAB_PIP_RETRY_1_MS);
        mRootView.postDelayed(
                () -> BraveYouTubeScriptInjectorNativeHelper.enterPictureInPicture(webContents),
                FAB_PIP_RETRY_2_MS);
    }

    private void bindMenuAction(@Nullable View view, @NonNull Runnable action) {
        if (view == null) {
            return;
        }
        view.setOnClickListener(
                (unused) -> {
                    if (!view.isEnabled()) {
                        return;
                    }
                    action.run();
                });
    }

    private void showToast(int messageId) {
        Toast.makeText(mActivity, messageId, Toast.LENGTH_SHORT).show();
    }

    private void showToastMessage(@NonNull String message) {
        Toast.makeText(mActivity, message, Toast.LENGTH_SHORT).show();
    }

    private void startLogoutFlow() {
        showToast(R.string.onetab_fab_logout_in_progress);
        OneTabFirebaseAuthManager authManager = new OneTabFirebaseAuthManager();
        OneTabDeviceSessionManager deviceSessionManager = new OneTabDeviceSessionManager();
        authManager.resolveAuthentication(
                (authenticated, message) -> {
                    if (!authenticated) {
                        authManager.signOut(mActivity);
                        launchLoginGate();
                        return;
                    }

                    deviceSessionManager.logoutCurrentSession(
                            (success, logoutMessage) -> {
                                if (!success) {
                                    showToastMessage(logoutMessage);
                                    return;
                                }
                                authManager.signOut(mActivity);
                                showToast(R.string.onetab_fab_logout_success);
                                launchLoginGate();
                            });
                });
    }

    private void launchLoginGate() {
        Intent intent = new Intent(mActivity, OneTabLoginActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        mActivity.startActivity(intent);
        mActivity.finish();
    }
}
