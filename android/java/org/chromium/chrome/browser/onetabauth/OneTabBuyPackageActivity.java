package org.chromium.chrome.browser.onetabauth;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
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

import org.chromium.base.Log;
import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.chrome.R;

import java.util.ArrayList;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.List;

public class OneTabBuyPackageActivity extends AppCompatActivity {
    private static final String TAG = "OneTabBuyPackage";
    private static final String ADMIN_CONTACT_URL = "https://line.me/R/ti/p/%40615yysio";
    private static final String DEFAULT_SELECTED_PACKAGE_ID = "pkg_03";
    private static final int REQUEST_CODE_PICK_SLIP = 0x6259;
    private static final int MAX_IMAGE_BYTES = 5 * 1024 * 1024;
    private static final int MAX_IMAGE_DIMENSION = 2048;

    private final OneTabFirebaseAuthManager mAuthManager = new OneTabFirebaseAuthManager();
    private final OneTabFirebaseAppCheckManager mAppCheckManager = new OneTabFirebaseAppCheckManager();
    private final OneTabPackagePurchaseManager mPurchaseManager = new OneTabPackagePurchaseManager();

    private TextView mPackageNameView;
    private TextView mPriceValueView;
    private TextView mStatusView;
    private TextView mBankValueView;
    private TextView mAccountNameEnValueView;
    private TextView mAccountNameThValueView;
    private TextView mAccountNumberValueView;
    private LinearLayout mPackageOptionsContainer;
    private ProgressBar mProgressBar;
    private AppCompatButton mSelectSlipButton;
    private AppCompatButton mContactAdminButton;

    @Nullable private OneTabPackagePurchaseManager.ProductSummary mProductSummary;
    @Nullable private PendingOrder mPendingOrder;
    private final List<OneTabPackagePurchaseManager.ProductSummary> mProductOptions = new ArrayList<>();
    private String mSelectedPackageId = DEFAULT_SELECTED_PACKAGE_ID;
    private boolean mBusy;
    private boolean mLoadingProductOptions;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(createContentView());
        loadProductOptions();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_CODE_PICK_SLIP) return;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            setBusy(false);
            setStatus(getString(R.string.onetab_buy_status_pick_cancelled), false);
            mPendingOrder = null;
            return;
        }
        if (mPendingOrder == null) {
            setBusy(false);
            setStatus(getString(R.string.onetab_buy_status_missing_order), true);
            return;
        }
        processSlipSelection(data.getData(), mPendingOrder);
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
        title.setText(R.string.onetab_buy_title);
        title.setTextColor(Color.WHITE);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30);
        LinearLayout.LayoutParams titleParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.topMargin = dp(16);
        root.addView(title, titleParams);

        TextView subtitle = new TextView(this);
        subtitle.setText(R.string.onetab_buy_subtitle);
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

        TextView packageLabel = new TextView(this);
        packageLabel.setText(R.string.onetab_buy_package_label);
        packageLabel.setTextColor(Color.parseColor("#B3FFFFFF"));
        packageLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        card.addView(packageLabel);

        mPackageOptionsContainer = new LinearLayout(this);
        mPackageOptionsContainer.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams packageOptionsParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        packageOptionsParams.topMargin = dp(12);
        card.addView(mPackageOptionsContainer, packageOptionsParams);

        mPackageNameView = new TextView(this);
        mPackageNameView.setTextColor(Color.WHITE);
        mPackageNameView.setTypeface(Typeface.DEFAULT_BOLD);
        mPackageNameView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        LinearLayout.LayoutParams packageNameParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        packageNameParams.topMargin = dp(8);
        card.addView(mPackageNameView, packageNameParams);

        TextView priceLabel = new TextView(this);
        priceLabel.setText(R.string.onetab_buy_price_label);
        priceLabel.setTextColor(Color.parseColor("#B3FFFFFF"));
        priceLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        LinearLayout.LayoutParams priceLabelParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        priceLabelParams.topMargin = dp(18);
        card.addView(priceLabel, priceLabelParams);

        mPriceValueView = new TextView(this);
        mPriceValueView.setTextColor(Color.WHITE);
        mPriceValueView.setTypeface(Typeface.DEFAULT_BOLD);
        mPriceValueView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        LinearLayout.LayoutParams priceValueParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        priceValueParams.topMargin = dp(8);
        card.addView(mPriceValueView, priceValueParams);

        ValueBlock bankBlock = createBankInfoBlock(getString(R.string.onetab_buy_bank_label));
        mBankValueView = bankBlock.valueView;
        card.addView(bankBlock.container);

        ValueBlock accountNameEnBlock =
                createBankInfoBlock(getString(R.string.onetab_buy_account_name_en_label));
        mAccountNameEnValueView = accountNameEnBlock.valueView;
        card.addView(accountNameEnBlock.container);

        ValueBlock accountNameThBlock =
                createBankInfoBlock(getString(R.string.onetab_buy_account_name_th_label));
        mAccountNameThValueView = accountNameThBlock.valueView;
        card.addView(accountNameThBlock.container);
        card.addView(createCopyAccountNumberBlock());

        mStatusView = new TextView(this);
        mStatusView.setTextColor(Color.parseColor("#D9FFFFFF"));
        mStatusView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        mStatusView.setGravity(Gravity.START);
        LinearLayout.LayoutParams statusParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        statusParams.topMargin = dp(18);
        card.addView(mStatusView, statusParams);

        mProgressBar = new ProgressBar(this);
        mProgressBar.setVisibility(View.GONE);
        LinearLayout.LayoutParams progressParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        progressParams.gravity = Gravity.CENTER_HORIZONTAL;
        progressParams.topMargin = dp(18);
        card.addView(mProgressBar, progressParams);

        mSelectSlipButton = new AppCompatButton(this);
        mSelectSlipButton.setAllCaps(false);
        mSelectSlipButton.setText(R.string.onetab_buy_select_slip);
        mSelectSlipButton.setTextColor(Color.WHITE);
        mSelectSlipButton.setTypeface(Typeface.DEFAULT_BOLD);
        mSelectSlipButton.setBackground(createFilledButtonBackground("#FFCC0000"));
        mSelectSlipButton.setPadding(dp(18), dp(14), dp(18), dp(14));
        mSelectSlipButton.setOnClickListener(unused -> startPurchaseFlow());
        LinearLayout.LayoutParams buyParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        buyParams.topMargin = dp(24);
        card.addView(mSelectSlipButton, buyParams);

        mContactAdminButton = new AppCompatButton(this);
        mContactAdminButton.setAllCaps(false);
        mContactAdminButton.setText(R.string.onetab_account_contact_admin);
        mContactAdminButton.setTextColor(Color.WHITE);
        mContactAdminButton.setTypeface(Typeface.DEFAULT_BOLD);
        mContactAdminButton.setBackground(createOutlineButtonBackground());
        mContactAdminButton.setPadding(dp(18), dp(14), dp(18), dp(14));
        mContactAdminButton.setOnClickListener(unused -> openAdminContact());
        LinearLayout.LayoutParams adminParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        adminParams.topMargin = dp(14);
        card.addView(mContactAdminButton, adminParams);

        applyLoadingProductOptionsState(true);
        clearProductSummary();
        renderPackageOptions();
        setStatus(getString(R.string.onetab_buy_status_loading), false);

        return scrollView;
    }

    private void loadProductOptions() {
        applyLoadingProductOptionsState(true);
        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                () -> {
                    List<OneTabPackagePurchaseManager.ProductSummary> options =
                            mPurchaseManager.fetchProductOptions();
                    PostTask.postTask(
                            TaskTraits.UI_DEFAULT,
                            () -> {
                                if (isFinishing() || isDestroyed()) return;
                                setProductOptions(options);
                                applyLoadingProductOptionsState(false);
                                setStatus(getString(R.string.onetab_buy_status_ready), false);
                            });
                });
    }

    private List<OneTabPackagePurchaseManager.ProductSummary> buildFallbackPackageOptions() {
        List<OneTabPackagePurchaseManager.ProductSummary> options = new ArrayList<>();
        for (String packageId : OneTabPackagePurchaseManager.SUPPORTED_PACKAGE_IDS) {
            options.add(OneTabPackagePurchaseManager.ProductSummary.fallback(packageId));
        }
        return options;
    }

    private void setProductOptions(List<OneTabPackagePurchaseManager.ProductSummary> options) {
        mProductOptions.clear();
        if (options != null && !options.isEmpty()) {
            mProductOptions.addAll(options);
        } else {
            mProductOptions.addAll(buildFallbackPackageOptions());
        }

        OneTabPackagePurchaseManager.ProductSummary selected = null;
        for (OneTabPackagePurchaseManager.ProductSummary option : mProductOptions) {
            if (TextUtils.equals(option.packageId, mSelectedPackageId)) {
                selected = option;
                break;
            }
        }
        if (selected == null) {
            for (OneTabPackagePurchaseManager.ProductSummary option : mProductOptions) {
                if (option.available) {
                    selected = option;
                    break;
                }
            }
        }
        if (selected == null && !mProductOptions.isEmpty()) {
            selected = mProductOptions.get(0);
        }
        if (selected != null) {
            mSelectedPackageId = selected.packageId;
            setProductSummary(selected);
        } else {
            clearProductSummary();
        }
        renderPackageOptions();
    }

    private void renderPackageOptions() {
        if (mPackageOptionsContainer == null) return;
        mPackageOptionsContainer.removeAllViews();
        for (OneTabPackagePurchaseManager.ProductSummary option : mProductOptions) {
            AppCompatButton optionButton = new AppCompatButton(this);
            optionButton.setAllCaps(false);
            optionButton.setText(option.name + "\n"
                    + getString(
                            R.string.onetab_buy_price_value,
                            option.price,
                            option.currency,
                            option.durationDays));
            optionButton.setTextColor(Color.WHITE);
            optionButton.setTypeface(Typeface.DEFAULT_BOLD);
            optionButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
            optionButton.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
            optionButton.setPadding(dp(16), dp(14), dp(16), dp(14));
            boolean selected = TextUtils.equals(option.packageId, mSelectedPackageId);
            optionButton.setBackground(
                    selected
                            ? createFilledButtonBackground("#FFCC0000")
                            : createOutlineButtonBackground());
            boolean enabled = option.available && !mBusy && !mLoadingProductOptions;
            optionButton.setEnabled(enabled);
            optionButton.setAlpha(option.available && !mLoadingProductOptions ? 1f : 0.5f);
            optionButton.setOnClickListener(
                    unused -> {
                        mSelectedPackageId = option.packageId;
                        setProductSummary(option);
                        renderPackageOptions();
                    });
            LinearLayout.LayoutParams optionParams =
                    new LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            if (mPackageOptionsContainer.getChildCount() > 0) {
                optionParams.topMargin = dp(10);
            }
            mPackageOptionsContainer.addView(optionButton, optionParams);
        }
    }

    private void setProductSummary(OneTabPackagePurchaseManager.ProductSummary summary) {
        mProductSummary = summary;
        mPackageNameView.setText(summary.name);
        mPriceValueView.setText(
                getString(
                        R.string.onetab_buy_price_value,
                        summary.price,
                        summary.currency,
                        summary.durationDays));
        if (mBankValueView != null) {
            mBankValueView.setText(summary.bankDisplayName);
        }
        if (mAccountNameEnValueView != null) {
            mAccountNameEnValueView.setText(summary.accountNameEn);
        }
        if (mAccountNameThValueView != null) {
            mAccountNameThValueView.setText(summary.accountNameTh);
        }
        if (mAccountNumberValueView != null) {
            mAccountNumberValueView.setText(summary.accountNumber);
        }
    }

    private void clearProductSummary() {
        mProductSummary = null;
        if (mPackageNameView != null) {
            mPackageNameView.setText("");
        }
        if (mPriceValueView != null) {
            mPriceValueView.setText("");
        }
        if (mBankValueView != null) {
            mBankValueView.setText("");
        }
        if (mAccountNameEnValueView != null) {
            mAccountNameEnValueView.setText("");
        }
        if (mAccountNameThValueView != null) {
            mAccountNameThValueView.setText("");
        }
        if (mAccountNumberValueView != null) {
            mAccountNumberValueView.setText("");
        }
    }

    private void applyLoadingProductOptionsState(boolean loading) {
        mLoadingProductOptions = loading;
        if (mSelectSlipButton != null) {
            boolean enabled = !loading && !mBusy && mProductSummary != null;
            mSelectSlipButton.setEnabled(enabled);
            mSelectSlipButton.setAlpha(enabled ? 1f : 0.6f);
        }
        renderPackageOptions();
    }

    private void startPurchaseFlow() {
        if (mBusy) return;
        if (mProductSummary == null) {
            setStatus(getString(R.string.onetab_buy_status_loading), true);
            return;
        }
        if (!mProductSummary.available) {
            setStatus(getString(R.string.onetab_buy_status_package_unavailable), true);
            return;
        }
        setBusy(true);
        setStatus(getString(R.string.onetab_buy_status_creating_order), false);
        mAuthManager.resolveAuthentication(
                (authenticated, message) -> {
                    if (!authenticated) {
                        setBusy(false);
                        setStatus(
                                !TextUtils.isEmpty(message)
                                        ? message
                                        : getString(R.string.onetab_buy_status_auth_error),
                                true);
                        return;
                    }

                    OneTabFirebaseSessionStore.Session session =
                            new OneTabFirebaseSessionStore().read();
                    if (TextUtils.isEmpty(session.idToken)) {
                        setBusy(false);
                        setStatus(getString(R.string.onetab_buy_status_auth_error), true);
                        return;
                    }

                    mAppCheckManager.resolveAppCheckToken(
                            (success, token, tokenMessage) -> {
                                if (!success || TextUtils.isEmpty(token)) {
                                    setBusy(false);
                                    setStatus(
                                            !TextUtils.isEmpty(tokenMessage)
                                                    ? tokenMessage
                                                    : getString(R.string.onetab_buy_status_app_check_error),
                                            true);
                                    return;
                                }

                                PostTask.postTask(
                                        TaskTraits.BEST_EFFORT_MAY_BLOCK,
                                        () -> {
                                            OneTabPackagePurchaseManager.CallableResult result =
                                                    mPurchaseManager.createPackageOrder(
                                                            session.idToken,
                                                            token,
                                                            mProductSummary.packageId);
                                            PostTask.postTask(
                                                    TaskTraits.UI_DEFAULT,
                                                    () -> {
                                                        if (isFinishing() || isDestroyed()) return;
                                                        if (!result.success || result.orderResult == null) {
                                                            setBusy(false);
                                                            setStatus(result.message, true);
                                                            return;
                                                        }

                                                        mPendingOrder =
                                                                new PendingOrder(
                                                                        result.orderResult.orderId,
                                                                        result.orderResult.storagePath,
                                                                        result.orderResult.uploadUrl);
                                                        if (TextUtils.isEmpty(result.orderResult.uploadUrl)) {
                                                            setBusy(false);
                                                            setStatus(
                                                                    getString(
                                                                            R.string.onetab_buy_status_backend_update_required),
                                                                    true);
                                                            return;
                                                        }

                                                        setStatus(
                                                                getString(
                                                                        R.string.onetab_buy_status_pick_slip),
                                                                false);
                                                        launchSlipPicker();
                                                    });
                                        });
                            });
                });
    }

    private void launchSlipPicker() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("image/*");
        startActivityForResult(intent, REQUEST_CODE_PICK_SLIP);
    }

    private void processSlipSelection(Uri slipUri, PendingOrder pendingOrder) {
        setBusy(true);
        setStatus(getString(R.string.onetab_buy_status_uploading), false);
        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK,
                () -> {
                    SlipBytes slipBytes = buildSlipBytes(slipUri);
                    if (!slipBytes.success) {
                        PostTask.postTask(
                                TaskTraits.UI_DEFAULT,
                                () -> {
                                    if (isFinishing() || isDestroyed()) return;
                                    setBusy(false);
                                    setStatus(slipBytes.message, true);
                                });
                        return;
                    }

                    String uploadMessage =
                            mPurchaseManager.uploadSlipJpeg(pendingOrder.uploadUrl, slipBytes.jpegBytes);
                    if (!TextUtils.isEmpty(uploadMessage)) {
                        PostTask.postTask(
                                TaskTraits.UI_DEFAULT,
                                () -> {
                                    if (isFinishing() || isDestroyed()) return;
                                    setBusy(false);
                                    setStatus(uploadMessage, true);
                                });
                        return;
                    }

                    PostTask.postTask(
                            TaskTraits.UI_DEFAULT,
                            () -> verifyUploadedSlip(pendingOrder));
                });
    }

    private void verifyUploadedSlip(PendingOrder pendingOrder) {
        setStatus(getString(R.string.onetab_buy_status_verifying), false);
        mAuthManager.resolveAuthentication(
                (authenticated, message) -> {
                    if (!authenticated) {
                        setBusy(false);
                        setStatus(
                                !TextUtils.isEmpty(message)
                                        ? message
                                        : getString(R.string.onetab_buy_status_auth_error),
                                true);
                        return;
                    }

                    OneTabFirebaseSessionStore.Session session =
                            new OneTabFirebaseSessionStore().read();
                    if (TextUtils.isEmpty(session.idToken)) {
                        setBusy(false);
                        setStatus(getString(R.string.onetab_buy_status_auth_error), true);
                        return;
                    }

                    mAppCheckManager.resolveAppCheckToken(
                            (success, token, tokenMessage) -> {
                                if (!success || TextUtils.isEmpty(token)) {
                                    setBusy(false);
                                    setStatus(
                                            !TextUtils.isEmpty(tokenMessage)
                                                    ? tokenMessage
                                                    : getString(R.string.onetab_buy_status_app_check_error),
                                            true);
                                    return;
                                }

                                PostTask.postTask(
                                        TaskTraits.BEST_EFFORT_MAY_BLOCK,
                                        () -> {
                                            OneTabPackagePurchaseManager.VerifyResult result =
                                                    mPurchaseManager.verifyPackageSlip(
                                                            session.idToken,
                                                            token,
                                                            pendingOrder.orderId,
                                                            pendingOrder.storagePath);
                                            PostTask.postTask(
                                                    TaskTraits.UI_DEFAULT,
                                                    () -> {
                                                        if (isFinishing() || isDestroyed()) return;
                                                        if (!result.success) {
                                                            setBusy(false);
                                                            setStatus(result.message, true);
                                                            return;
                                                        }

                                                        setBusy(false);
                                                        setStatus(
                                                                getString(
                                                                        R.string.onetab_buy_status_success),
                                                                false);
                                                        showToast(R.string.onetab_buy_status_success);
                                                        setResult(RESULT_OK);
                                                        launchReceipt(result);
                                                        finish();
                                                    });
                                        });
                            });
                });
    }

    private void launchReceipt(OneTabPackagePurchaseManager.VerifyResult result) {
        Intent intent = new Intent(this, OneTabPurchaseReceiptActivity.class);
        intent.putExtra(
                OneTabPurchaseReceiptActivity.EXTRA_ORDER_ID,
                !TextUtils.isEmpty(result.orderId)
                        ? result.orderId
                        : (mPendingOrder != null ? mPendingOrder.orderId : ""));
        intent.putExtra(
                OneTabPurchaseReceiptActivity.EXTRA_PACKAGE_NAME,
                mProductSummary != null
                        ? mProductSummary.name
                        : OneTabPackagePurchaseManager.ProductSummary.DEFAULT_NAME);
        intent.putExtra(
                OneTabPurchaseReceiptActivity.EXTRA_PAYMENT_REF, result.paymentRef);
        intent.putExtra(
                OneTabPurchaseReceiptActivity.EXTRA_AMOUNT,
                result.expectedAmount > 0L
                        ? result.expectedAmount
                        : (mProductSummary != null
                                ? mProductSummary.price
                                : OneTabPackagePurchaseManager.ProductSummary.DEFAULT_PRICE));
        intent.putExtra(
                OneTabPurchaseReceiptActivity.EXTRA_CURRENCY,
                !TextUtils.isEmpty(result.currency)
                        ? result.currency
                        : (mProductSummary != null
                                ? mProductSummary.currency
                                : OneTabPackagePurchaseManager.ProductSummary.DEFAULT_CURRENCY));
        intent.putExtra(
                OneTabPurchaseReceiptActivity.EXTRA_DURATION_DAYS,
                result.durationDays > 0
                        ? result.durationDays
                        : (mProductSummary != null
                                ? mProductSummary.durationDays
                                : OneTabPackagePurchaseManager.ProductSummary.DEFAULT_DURATION_DAYS));
        intent.putExtra(
                OneTabPurchaseReceiptActivity.EXTRA_EXPIRES_AT, result.expiresAt);
        intent.putExtra(
                OneTabPurchaseReceiptActivity.EXTRA_ALREADY_PROCESSED, result.alreadyProcessed);
        startActivity(intent);
    }

    private SlipBytes buildSlipBytes(Uri slipUri) {
        try {
            BitmapFactory.Options boundsOptions = new BitmapFactory.Options();
            boundsOptions.inJustDecodeBounds = true;
            try (InputStream boundsStream = getContentResolver().openInputStream(slipUri)) {
                BitmapFactory.decodeStream(boundsStream, null, boundsOptions);
            }

            BitmapFactory.Options decodeOptions = new BitmapFactory.Options();
            decodeOptions.inSampleSize = computeInSampleSize(boundsOptions, MAX_IMAGE_DIMENSION, MAX_IMAGE_DIMENSION);
            Bitmap bitmap;
            try (InputStream decodeStream = getContentResolver().openInputStream(slipUri)) {
                bitmap = BitmapFactory.decodeStream(decodeStream, null, decodeOptions);
            }
            if (bitmap == null) {
                return SlipBytes.error(getString(R.string.onetab_buy_status_invalid_image));
            }

            byte[] bestBytes = null;
            int[] qualities = {90, 80, 70, 60};
            for (int quality : qualities) {
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, output);
                byte[] bytes = output.toByteArray();
                if (bytes.length <= MAX_IMAGE_BYTES) {
                    bestBytes = bytes;
                    break;
                }
            }
            bitmap.recycle();

            if (bestBytes == null) {
                return SlipBytes.error(getString(R.string.onetab_buy_status_large_image));
            }
            return SlipBytes.success(bestBytes);
        } catch (Exception e) {
            Log.e(TAG, "buildSlipBytes uri=%s error=%s", slipUri, e.getMessage());
            return SlipBytes.error(getString(R.string.onetab_buy_status_invalid_image));
        }
    }

    private static int computeInSampleSize(
            BitmapFactory.Options options, int reqWidth, int reqHeight) {
        int height = Math.max(options.outHeight, 1);
        int width = Math.max(options.outWidth, 1);
        int inSampleSize = 1;
        while ((height / inSampleSize) > reqHeight || (width / inSampleSize) > reqWidth) {
            inSampleSize *= 2;
        }
        return Math.max(1, inSampleSize);
    }

    private void setBusy(boolean busy) {
        mBusy = busy;
        mProgressBar.setVisibility(busy ? View.VISIBLE : View.GONE);
        renderPackageOptions();
        boolean buyEnabled = !busy && !mLoadingProductOptions && mProductSummary != null;
        mSelectSlipButton.setEnabled(buyEnabled);
        mSelectSlipButton.setAlpha(buyEnabled ? 1f : 0.6f);
        mContactAdminButton.setEnabled(!busy);
        mContactAdminButton.setAlpha(busy ? 0.6f : 1f);
    }

    private void setStatus(String message, boolean error) {
        mStatusView.setText(message);
        mStatusView.setTextColor(error ? Color.parseColor("#FFFF8A80") : Color.parseColor("#D9FFFFFF"));
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

    private ValueBlock createBankInfoBlock(String label) {
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
        valueView.setTextColor(Color.WHITE);
        valueView.setTypeface(Typeface.DEFAULT_BOLD);
        valueView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        valueView.setLineSpacing(0f, 1.1f);
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
        return new ValueBlock(block, valueView);
    }

    private View createCopyAccountNumberBlock() {
        LinearLayout block = new LinearLayout(this);
        block.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.parseColor("#FF2B2B2B"));
        background.setCornerRadius(dp(18));
        block.setBackground(background);
        block.setPadding(dp(18), dp(16), dp(18), dp(16));

        TextView labelView = new TextView(this);
        labelView.setText(R.string.onetab_buy_account_number_label);
        labelView.setTextColor(Color.parseColor("#B3FFFFFF"));
        labelView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        block.addView(labelView);

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams rowParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rowParams.topMargin = dp(8);
        block.addView(row, rowParams);

        mAccountNumberValueView = new TextView(this);
        mAccountNumberValueView.setTextColor(Color.WHITE);
        mAccountNumberValueView.setTypeface(Typeface.DEFAULT_BOLD);
        mAccountNumberValueView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        LinearLayout.LayoutParams valueParams =
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        row.addView(mAccountNumberValueView, valueParams);

        AppCompatButton copyButton = new AppCompatButton(this);
        copyButton.setAllCaps(false);
        copyButton.setText(R.string.onetab_buy_account_number_copy);
        copyButton.setTextColor(Color.WHITE);
        copyButton.setTypeface(Typeface.DEFAULT_BOLD);
        copyButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        copyButton.setMinWidth(0);
        copyButton.setMinimumWidth(0);
        copyButton.setBackground(createOutlineButtonBackground());
        copyButton.setPadding(dp(14), dp(10), dp(14), dp(10));
        copyButton.setOnClickListener(
                unused ->
                        copyTextToClipboard(
                                getCurrentAccountNumber(),
                                getString(R.string.onetab_buy_account_number_copied)));
        row.addView(
                copyButton,
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout.LayoutParams blockParams =
                new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        blockParams.topMargin = dp(14);
        block.setLayoutParams(blockParams);
        return block;
    }

    private String getCurrentAccountNumber() {
        if (mProductSummary != null && !TextUtils.isEmpty(mProductSummary.accountNumber)) {
            return mProductSummary.accountNumber;
        }
        if (mAccountNumberValueView != null
                && !TextUtils.isEmpty(mAccountNumberValueView.getText())) {
            return mAccountNumberValueView.getText().toString();
        }
        return OneTabPackagePurchaseManager.ProductSummary.DEFAULT_ACCOUNT_NUMBER;
    }

    private void copyTextToClipboard(String value, String copiedMessage) {
        ClipboardManager clipboard =
                (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard == null) {
            showToastMessage(getString(R.string.onetab_buy_account_number_copy_failed));
            return;
        }
        clipboard.setPrimaryClip(ClipData.newPlainText("GO_PLAY account number", value));
        showToastMessage(copiedMessage);
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

    private static final class PendingOrder {
        final String orderId;
        final String storagePath;
        final String uploadUrl;

        PendingOrder(String orderId, String storagePath, String uploadUrl) {
            this.orderId = orderId;
            this.storagePath = storagePath;
            this.uploadUrl = uploadUrl;
        }
    }

    private static final class ValueBlock {
        final View container;
        final TextView valueView;

        ValueBlock(View container, TextView valueView) {
            this.container = container;
            this.valueView = valueView;
        }
    }

    private static final class SlipBytes {
        final boolean success;
        final byte[] jpegBytes;
        final String message;

        private SlipBytes(boolean success, byte[] jpegBytes, String message) {
            this.success = success;
            this.jpegBytes = jpegBytes;
            this.message = message;
        }

        static SlipBytes success(byte[] jpegBytes) {
            return new SlipBytes(true, jpegBytes, "");
        }

        static SlipBytes error(String message) {
            return new SlipBytes(false, null, message);
        }
    }
}
