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
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatButton;

import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.chrome.R;

import java.io.File;

public class OneTabAccountActivity extends AppCompatActivity {
    private static final String ADMIN_CONTACT_URL = "https://line.me/R/ti/p/%40615yysio";

    private final OneTabFirebaseAuthManager mAuthManager = new OneTabFirebaseAuthManager();
    private final OneTabFirebaseAppCheckManager mAppCheckManager =
            new OneTabFirebaseAppCheckManager();
    private final OneTabPackagePurchaseManager mPurchaseManager =
            new OneTabPackagePurchaseManager();

    private OneTabAppUpdateManager mAppUpdateManager;

    private TextView mEmailValueView;
    private TextView mRemainingDaysValueView;
    private TextView mCurrentVersionValueView;
    private TextView mLatestVersionValueView;
    private TextView mUpdateNotesValueView;
    private TextView mUpdateStatusValueView;
    private ProgressBar mUpdateProgressBar;
    private AppCompatButton mUpdateButton;

    private boolean mUpdateBusy;
    private boolean mAwaitingInstallerResult;
    @Nullable private OneTabAppUpdateManager.UpdateCheckResult mLatestUpdateCheckResult;
    @Nullable private OneTabAppUpdateManager.PreparedUpdateState mPreparedUpdateState;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mAppUpdateManager = new OneTabAppUpdateManager(this);
        setContentView(createContentView());
        handleInstallStatusIntent(getIntent());
        refreshAccountSummary();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshAccountSummary();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleInstallStatusIntent(intent);
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

        FieldBlock currentVersionBlock =
                createFieldBlock(
                        getString(R.string.onetab_account_current_version_label),
                        getString(R.string.onetab_account_update_loading));
        mCurrentVersionValueView = currentVersionBlock.valueView;
        card.addView(currentVersionBlock.container);

        FieldBlock latestVersionBlock =
                createFieldBlock(
                        getString(R.string.onetab_account_latest_version_label),
                        getString(R.string.onetab_account_update_loading));
        mLatestVersionValueView = latestVersionBlock.valueView;
        card.addView(latestVersionBlock.container);

        FieldBlock releaseNotesBlock =
                createFieldBlock(
                        getString(R.string.onetab_account_release_notes_label),
                        getString(R.string.onetab_account_update_notes_empty));
        mUpdateNotesValueView = releaseNotesBlock.valueView;
        mUpdateNotesValueView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        mUpdateNotesValueView.setLineSpacing(0f, 1.15f);
        card.addView(releaseNotesBlock.container);

        mUpdateStatusValueView = new TextView(this);
        mUpdateStatusValueView.setText(R.string.onetab_account_update_status_idle);
        mUpdateStatusValueView.setTextColor(Color.parseColor("#D9FFFFFF"));
        mUpdateStatusValueView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        mUpdateStatusValueView.setLineSpacing(0f, 1.1f);
        LinearLayout.LayoutParams statusParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        statusParams.topMargin = dp(18);
        card.addView(mUpdateStatusValueView, statusParams);

        mUpdateProgressBar =
                new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        mUpdateProgressBar.setMax(100);
        mUpdateProgressBar.setProgress(0);
        mUpdateProgressBar.setVisibility(View.GONE);
        LinearLayout.LayoutParams progressParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        progressParams.topMargin = dp(14);
        card.addView(mUpdateProgressBar, progressParams);

        mUpdateButton = new AppCompatButton(this);
        mUpdateButton.setAllCaps(false);
        mUpdateButton.setText(R.string.onetab_account_update_button_check);
        mUpdateButton.setTextColor(Color.WHITE);
        mUpdateButton.setTypeface(Typeface.DEFAULT_BOLD);
        mUpdateButton.setBackground(createFilledButtonBackground("#FFCC0000"));
        mUpdateButton.setPadding(dp(18), dp(14), dp(18), dp(14));
        mUpdateButton.setOnClickListener(unused -> handleUpdateButtonClick());
        LinearLayout.LayoutParams updateParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        updateParams.topMargin = dp(20);
        card.addView(mUpdateButton, updateParams);

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
        buyParams.topMargin = dp(14);
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

        applyInstalledVersionInfo(mAppUpdateManager.readInstalledVersionInfo());
        mLatestVersionValueView.setText(R.string.onetab_account_update_unavailable);
        mUpdateNotesValueView.setText(R.string.onetab_account_update_notes_empty);
        mUpdateStatusValueView.setText(R.string.onetab_account_update_status_idle);
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_check), true, false, 0);
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
                        if (!TextUtils.isEmpty(message)) showToastMessage(message);
                        return;
                    }

                    OneTabFirebaseSessionStore.Session refreshedSession =
                            new OneTabFirebaseSessionStore().read();
                    updateEmail(refreshedSession);
                    fetchPackageAccessState(refreshedSession);
                });
    }

    private void fetchPackageAccessState(OneTabFirebaseSessionStore.Session session) {
        if (TextUtils.isEmpty(session.idToken)) {
            mRemainingDaysValueView.setText(R.string.onetab_account_remaining_days_error);
            return;
        }

        mAppCheckManager.resolveAppCheckToken(
                (success, token, message) -> {
                    if (!success || TextUtils.isEmpty(token)) {
                        mRemainingDaysValueView.setText(R.string.onetab_account_remaining_days_error);
                        if (!TextUtils.isEmpty(message)) showToastMessage(message);
                        return;
                    }

                    PostTask.postTask(
                            TaskTraits.BEST_EFFORT_MAY_BLOCK,
                            () -> {
                                OneTabPackagePurchaseManager.AccessStateResult result =
                                        mPurchaseManager.fetchPackageAccessState(
                                                session.idToken, token);
                                PostTask.postTask(
                                        TaskTraits.UI_DEFAULT,
                                        () -> {
                                            if (isFinishing() || isDestroyed()) return;
                                            applyAccessState(result);
                                        });
                            });
                });
    }

    private void refreshUpdateSummary() {
        OneTabAppUpdateManager.InstalledVersionInfo installedVersion =
                mAppUpdateManager.readInstalledVersionInfo();
        applyInstalledVersionInfo(installedVersion);
        mLatestVersionValueView.setText(R.string.onetab_account_update_loading);
        mUpdateNotesValueView.setText(R.string.onetab_account_update_notes_empty);
        mUpdateStatusValueView.setText(R.string.onetab_account_update_status_checking);
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_check), false, true, 0);

        mAuthManager.resolveAuthentication(
                (authenticated, authMessage) -> {
                    if (!authenticated) {
                        mLatestUpdateCheckResult = null;
                        mLatestVersionValueView.setText(R.string.onetab_account_update_unavailable);
                        mUpdateStatusValueView.setText(
                                !TextUtils.isEmpty(authMessage)
                                        ? authMessage
                                        : getString(R.string.onetab_account_update_auth_required));
                        mUpdateNotesValueView.setText(R.string.onetab_account_update_notes_empty);
                        setUpdateButtonState(
                                getString(R.string.onetab_account_update_button_check),
                                true,
                                false,
                                0);
                        return;
                    }

                    OneTabFirebaseSessionStore.Session session =
                            new OneTabFirebaseSessionStore().read();
                    if (TextUtils.isEmpty(session.idToken)) {
                        mLatestUpdateCheckResult = null;
                        mLatestVersionValueView.setText(R.string.onetab_account_update_unavailable);
                        mUpdateStatusValueView.setText(R.string.onetab_account_update_auth_required);
                        setUpdateButtonState(
                                getString(R.string.onetab_account_update_button_check),
                                true,
                                false,
                                0);
                        return;
                    }

                    mAppCheckManager.resolveAppCheckToken(
                            (success, token, tokenMessage) -> {
                                if (!success || TextUtils.isEmpty(token)) {
                                    mLatestUpdateCheckResult = null;
                                    mLatestVersionValueView.setText(
                                            R.string.onetab_account_update_unavailable);
                                    mUpdateStatusValueView.setText(
                                            !TextUtils.isEmpty(tokenMessage)
                                                    ? tokenMessage
                                                    : getString(
                                                            R.string
                                                                    .onetab_account_update_app_check_error));
                                    mUpdateNotesValueView.setText(
                                            R.string.onetab_account_update_notes_empty);
                                    setUpdateButtonState(
                                            getString(R.string.onetab_account_update_button_check),
                                            true,
                                            false,
                                            0);
                                    return;
                                }

                                PostTask.postTask(
                                        TaskTraits.BEST_EFFORT_MAY_BLOCK,
                                        () -> {
                                            OneTabAppUpdateManager.UpdateCheckResult result =
                                                    mAppUpdateManager.fetchUpdateInfo(
                                                            session.idToken, token);
                                            PostTask.postTask(
                                                    TaskTraits.UI_DEFAULT,
                                                    () -> {
                                                        if (isFinishing() || isDestroyed()) return;
                                                        applyUpdateCheckResult(result);
                                                    });
                                        });
                            });
                });
    }

    private void applyUpdateCheckResult(OneTabAppUpdateManager.UpdateCheckResult result) {
        mLatestUpdateCheckResult = result;
        mPreparedUpdateState = null;
        if (result == null) {
            mLatestVersionValueView.setText(R.string.onetab_account_update_unavailable);
            mUpdateNotesValueView.setText(R.string.onetab_account_update_notes_empty);
            mUpdateStatusValueView.setText(R.string.onetab_account_update_unavailable);
            setUpdateButtonState(
                    getString(R.string.onetab_account_update_button_retry), true, false, 0);
            return;
        }

        applyInstalledVersionInfo(result.installedVersion);
        if (result.manifest != null) {
            mLatestVersionValueView.setText(result.manifest.toDisplayString());
            mUpdateNotesValueView.setText(
                    !TextUtils.isEmpty(result.manifest.releaseNotes)
                            ? result.manifest.releaseNotes
                            : getString(R.string.onetab_account_update_notes_empty));
        } else {
            mLatestVersionValueView.setText(R.string.onetab_account_update_unavailable);
            mUpdateNotesValueView.setText(R.string.onetab_account_update_notes_empty);
        }

        mUpdateStatusValueView.setText(result.message);
        if (!result.success) {
            setUpdateButtonState(
                    getString(R.string.onetab_account_update_button_retry), true, false, 0);
            return;
        }

        if (result.updateAvailable) {
            OneTabAppUpdateManager.PreparedUpdateState preparedUpdateState =
                    mAppUpdateManager.inspectPreparedUpdate(result.manifest);
            if (preparedUpdateState.readyToInstall) {
                mPreparedUpdateState = preparedUpdateState;
                mUpdateStatusValueView.setText(
                        preparedUpdateState.awaitingUnknownSourcesPermission
                                ? R.string
                                        .onetab_account_update_status_permission_required_manual
                                : R.string.onetab_account_update_status_cached_ready);
                setUpdateButtonState(
                        getString(R.string.onetab_account_update_button_install), true, false, 100);
                return;
            }
            setUpdateButtonState(
                    getString(R.string.onetab_account_update_button_install), true, false, 0);
            return;
        }

        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_check), true, false, 0);
    }

    private void handleUpdateButtonClick() {
        if (mUpdateBusy) return;
        if (mLatestUpdateCheckResult == null || !mLatestUpdateCheckResult.success) {
            refreshUpdateSummary();
            return;
        }
        if (!mLatestUpdateCheckResult.updateAvailable || mLatestUpdateCheckResult.manifest == null) {
            refreshUpdateSummary();
            return;
        }

        final OneTabAppUpdateManifest manifest = mLatestUpdateCheckResult.manifest;
        OneTabAppUpdateManager.PreparedUpdateState preparedUpdateState =
                mAppUpdateManager.inspectPreparedUpdate(manifest);
        if (preparedUpdateState.readyToInstall && preparedUpdateState.apkFile != null) {
            mPreparedUpdateState = preparedUpdateState;
            dispatchPreparedInstall(preparedUpdateState.apkFile, manifest);
            return;
        }

        mUpdateBusy = true;
        mUpdateStatusValueView.setText(R.string.onetab_account_update_status_preparing);
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_installing), false, true, 0);

        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                () -> {
                    OneTabAppUpdateManager.PreparedUpdateResult result =
                            mAppUpdateManager.prepareUpdate(
                                    manifest,
                                    (downloaded, total) ->
                                            PostTask.postTask(
                                                    TaskTraits.UI_DEFAULT,
                                                    () -> {
                                                        if (isFinishing() || isDestroyed()) return;
                                                        updateDownloadProgress(downloaded, total);
                                                    }));
                    PostTask.postTask(
                            TaskTraits.UI_DEFAULT,
                            () -> {
                                if (isFinishing() || isDestroyed()) return;
                                onPreparedUpdateReady(result);
                            });
                });
    }

    private void onPreparedUpdateReady(OneTabAppUpdateManager.PreparedUpdateResult result) {
        if (!result.success || result.apkFile == null || result.manifest == null) {
            mUpdateBusy = false;
            mAwaitingInstallerResult = false;
            mPreparedUpdateState = null;
            mUpdateStatusValueView.setText(
                    !TextUtils.isEmpty(result.message)
                            ? result.message
                            : getString(R.string.onetab_account_update_prepare_failed));
            setUpdateButtonState(
                    getString(R.string.onetab_account_update_button_retry), true, false, 0);
            return;
        }

        if (result.reusedCachedFile) {
            mUpdateStatusValueView.setText(R.string.onetab_account_update_status_cached_ready);
        } else {
            mUpdateStatusValueView.setText(R.string.onetab_account_update_status_verified);
        }
        mPreparedUpdateState = mAppUpdateManager.inspectPreparedUpdate(result.manifest);
        mUpdateBusy = false;
        mAwaitingInstallerResult = false;
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_install), true, false, 100);
    }

    private void dispatchPreparedInstall(File apkFile, OneTabAppUpdateManifest manifest) {
        mUpdateBusy = true;
        mUpdateStatusValueView.setText(R.string.onetab_account_update_status_preparing);
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_installing), false, true, 100);
        OneTabAppUpdateManager.InstallRequestResult installResult =
                mAppUpdateManager.requestInstall(
                        this,
                        apkFile,
                        manifest.latestVersionCode,
                        manifest.latestVersionName);
        if (installResult.success) {
            mAwaitingInstallerResult = true;
            mUpdateBusy = false;
            mUpdateStatusValueView.setText(installResult.message);
            setUpdateButtonState(
                    getString(R.string.onetab_account_update_button_waiting_install),
                    false,
                    true,
                    100);
            return;
        }

        mUpdateBusy = false;
        if (installResult.permissionRequired) {
            mAwaitingInstallerResult = false;
            mUpdateStatusValueView.setText(installResult.message);
            setUpdateButtonState(
                    getString(R.string.onetab_account_update_button_install),
                    true,
                    false,
                    100);
            return;
        }

        mAwaitingInstallerResult = false;
        mPreparedUpdateState = null;
        mUpdateStatusValueView.setText(installResult.message);
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_retry), true, false, 0);
    }

    private void handleInstallStatusIntent(@Nullable Intent intent) {
        if (intent == null) {
            return;
        }

        OneTabAppUpdateManager.InstallStatusResult result =
                mAppUpdateManager.consumeInstallStatusIntent(this, intent);
        if (!result.handled) {
            return;
        }

        if (result.waitingForUserAction) {
            mAwaitingInstallerResult = true;
            mUpdateBusy = false;
            mUpdateStatusValueView.setText(result.message);
            setUpdateButtonState(
                    getString(R.string.onetab_account_update_button_waiting_install),
                    false,
                    true,
                    100);
            return;
        }

        if (result.installSucceeded) {
            mAwaitingInstallerResult = false;
            mUpdateBusy = false;
            mPreparedUpdateState = null;
            finishUpdateFlowWithMessage(result.message);
            refreshUpdateSummary();
            return;
        }

        mAwaitingInstallerResult = false;
        mUpdateBusy = false;
        mPreparedUpdateState = null;
        mUpdateStatusValueView.setText(result.message);
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_retry), true, false, 0);
        if (!TextUtils.isEmpty(result.message)) {
            showToastMessage(result.message);
        }
    }

    private void finishUpdateFlowWithMessage(String message) {
        mUpdateProgressBar.setProgress(100);
        mUpdateProgressBar.setVisibility(View.VISIBLE);
        mUpdateStatusValueView.setText(message);
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_check), true, false, 100);
        if (!TextUtils.isEmpty(message)) {
            showToastMessage(message);
        }
    }

    private void updateDownloadProgress(long downloadedBytes, long totalBytes) {
        if (totalBytes <= 0L) {
            mUpdateStatusValueView.setText(R.string.onetab_account_update_status_downloading_unknown);
            setUpdateButtonState(
                    getString(R.string.onetab_account_update_button_installing),
                    false,
                    true,
                    0);
            return;
        }

        int progress = (int) Math.max(0L, Math.min(100L, (downloadedBytes * 100L) / totalBytes));
        mUpdateStatusValueView.setText(
                getString(R.string.onetab_account_update_status_downloading_progress, progress));
        setUpdateButtonState(
                getString(R.string.onetab_account_update_button_installing),
                false,
                true,
                progress);
    }

    private void setUpdateButtonState(
            String buttonText, boolean enabled, boolean showProgress, int progressPercent) {
        if (mUpdateButton != null) {
            mUpdateButton.setText(buttonText);
            mUpdateButton.setEnabled(enabled);
            mUpdateButton.setAlpha(enabled ? 1f : 0.6f);
        }
        if (mUpdateProgressBar != null) {
            if (showProgress) {
                mUpdateProgressBar.setVisibility(View.VISIBLE);
                mUpdateProgressBar.setIndeterminate(progressPercent <= 0);
                if (progressPercent > 0) {
                    mUpdateProgressBar.setProgress(progressPercent);
                } else {
                    mUpdateProgressBar.setProgress(0);
                }
            } else {
                mUpdateProgressBar.setIndeterminate(false);
                mUpdateProgressBar.setProgress(Math.max(0, progressPercent));
                mUpdateProgressBar.setVisibility(progressPercent > 0 ? View.VISIBLE : View.GONE);
            }
        }
    }

    private void applyInstalledVersionInfo(OneTabAppUpdateManager.InstalledVersionInfo info) {
        if (mCurrentVersionValueView == null || info == null) {
            return;
        }
        mCurrentVersionValueView.setText(info.toDisplayString());
    }

    private void applyAccessState(OneTabPackagePurchaseManager.AccessStateResult result) {
        if (!result.success) {
            mRemainingDaysValueView.setText(R.string.onetab_account_remaining_days_error);
            if (!TextUtils.isEmpty(result.message)) showToastMessage(result.message);
            return;
        }

        if (result.allowed) {
            mRemainingDaysValueView.setText(
                    getString(
                            R.string.onetab_account_remaining_days_value,
                            Math.max(0, result.remainingDays)));
            return;
        }

        if ("EXPIRED".equals(result.status)) {
            mRemainingDaysValueView.setText(R.string.onetab_account_remaining_days_expired);
            return;
        }

        mRemainingDaysValueView.setText(R.string.onetab_account_remaining_days_none);
    }

    private void updateEmail(OneTabFirebaseSessionStore.Session session) {
        if (mEmailValueView == null) {
            return;
        }
        mEmailValueView.setText(
                !TextUtils.isEmpty(session.email)
                        ? session.email
                        : getString(R.string.onetab_account_email_missing));
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
}
