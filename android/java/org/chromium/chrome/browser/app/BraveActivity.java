/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.app;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.KeyguardManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PictureInPictureParams;
import android.app.PictureInPictureUiState;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.IntentSender;
import android.content.SharedPreferences;
import android.content.SharedPreferences.OnSharedPreferenceChangeListener;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Rect;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.PowerManager;
import android.os.SystemClock;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.MainThread;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.widget.AppCompatEditText;
import androidx.coordinatorlayout.widget.CoordinatorLayout;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentManager;
import androidx.fragment.app.FragmentTransaction;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.brave.playlist.util.ConstantUtils;
import com.brave.playlist.util.PlaylistPreferenceUtils;
import com.brave.playlist.util.PlaylistUtils;
import com.google.android.gms.tasks.Task;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.play.core.appupdate.AppUpdateInfo;
import com.google.android.play.core.appupdate.AppUpdateManager;
import com.google.android.play.core.appupdate.AppUpdateManagerFactory;
import com.google.android.play.core.install.InstallStateUpdatedListener;
import com.google.android.play.core.install.model.AppUpdateType;
import com.google.android.play.core.install.model.InstallStatus;
import com.google.android.play.core.install.model.UpdateAvailability;
import com.wireguard.android.backend.GoBackend;

import org.jni_zero.JNINamespace;
import org.jni_zero.NativeMethods;

import org.chromium.base.ActivityState;
import org.chromium.base.ApkInfo;
import org.chromium.base.ApplicationState;
import org.chromium.base.ApplicationStatus;
import org.chromium.base.ApplicationStatus.ApplicationStateListener;
import org.chromium.base.BraveFeatureList;
import org.chromium.base.BravePreferenceKeys;
import org.chromium.base.BraveReflectionUtil;
import org.chromium.base.CollectionUtil;
import org.chromium.base.CommandLine;
import org.chromium.base.ContextUtils;
import org.chromium.base.IntentUtils;
import org.chromium.base.Log;
import org.chromium.base.ThreadUtils;
import org.chromium.base.supplier.MonotonicObservableSupplier;
import org.chromium.base.supplier.SettableMonotonicObservableSupplier;
import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.base.ui.KeyboardUtils;
import org.chromium.brave.browser.customize_menu.CustomizeBraveMenu;
import org.chromium.brave.browser.quick_search_engines.settings.QuickSearchEnginesCallback;
import org.chromium.brave.browser.quick_search_engines.settings.QuickSearchEnginesFragment;
import org.chromium.brave.browser.quick_search_engines.settings.QuickSearchEnginesModel;
import org.chromium.brave.browser.quick_search_engines.utils.QuickSearchEnginesUtil;
import org.chromium.brave.browser.quick_search_engines.views.QuickSearchEnginesViewAdapter;
import org.chromium.brave_wallet.mojom.AssetRatioService;
import org.chromium.brave_wallet.mojom.BlockchainRegistry;
import org.chromium.brave_wallet.mojom.BraveWalletService;
import org.chromium.brave_wallet.mojom.CoinType;
import org.chromium.brave_wallet.mojom.EthTxManagerProxy;
import org.chromium.brave_wallet.mojom.JsonRpcService;
import org.chromium.brave_wallet.mojom.KeyringService;
import org.chromium.brave_wallet.mojom.NetworkInfo;
import org.chromium.brave_wallet.mojom.SignDataUnion;
import org.chromium.brave_wallet.mojom.SolanaTxManagerProxy;
import org.chromium.brave_wallet.mojom.SwapService;
import org.chromium.brave_wallet.mojom.TxService;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.BraveAdFreeCalloutDialogFragment;
import org.chromium.chrome.browser.BraveConfig;
import org.chromium.chrome.browser.BraveHelper;
import org.chromium.chrome.browser.BraveIntentHandler;
import org.chromium.chrome.browser.BraveRelaunchUtils;
import org.chromium.chrome.browser.BraveRewardsHelper;
import org.chromium.chrome.browser.BraveSyncWorker;
import org.chromium.chrome.browser.ChromeTabbedActivity;
import org.chromium.chrome.browser.DevToolsServer;
import org.chromium.chrome.browser.DormantUsersEngagementDialogFragment;
import org.chromium.chrome.browser.IntentHandler;
import org.chromium.chrome.browser.InternetConnection;
import org.chromium.chrome.browser.LaunchIntentDispatcher;
import org.chromium.chrome.browser.OneTabYouTubeMode;
import org.chromium.chrome.browser.OpenYtInBraveDialogFragment;
import org.chromium.chrome.browser.app.domain.WalletModel;
import org.chromium.chrome.browser.billing.InAppPurchaseWrapper;
import org.chromium.chrome.browser.billing.PurchaseModel;
import org.chromium.chrome.browser.bookmarks.TabBookmarker;
import org.chromium.chrome.browser.brave_leo.BraveLeoPrefUtils;
import org.chromium.chrome.browser.brave_leo.BraveLeoUtils;
import org.chromium.chrome.browser.brave_leo.BraveLeoVoiceRecognitionHandler;
import org.chromium.chrome.browser.brave_news.BraveNewsUtils;
import org.chromium.chrome.browser.brave_news.models.FeedItemsCard;
import org.chromium.chrome.browser.incognito.IncognitoUtils;
import org.chromium.chrome.browser.brave_origin.BraveOriginSubscriptionPrefs;
import org.chromium.chrome.browser.brave_shields.BraveFirstPartyStorageCleanerUtils;
import org.chromium.chrome.browser.brave_shields.FirstPartyStorageCleanerAnimationFragment;
import org.chromium.chrome.browser.brave_shields.FirstPartyStorageCleanerInterface;
import org.chromium.chrome.browser.brave_stats.BraveStatsBottomSheetDialogFragment;
import org.chromium.chrome.browser.brave_stats.BraveStatsUtil;
import org.chromium.chrome.browser.browsing_data.BrowsingDataBridge;
import org.chromium.chrome.browser.browsing_data.BrowsingDataType;
import org.chromium.chrome.browser.browsing_data.TimePeriod;
import org.chromium.chrome.browser.compositor.layouts.LayoutManagerChrome;
import org.chromium.chrome.browser.crypto_wallet.AssetRatioServiceFactory;
import org.chromium.chrome.browser.crypto_wallet.BlockchainRegistryFactory;
import org.chromium.chrome.browser.crypto_wallet.BraveWalletPolicy;
import org.chromium.chrome.browser.crypto_wallet.BraveWalletServiceFactory;
import org.chromium.chrome.browser.crypto_wallet.SwapServiceFactory;
import org.chromium.chrome.browser.crypto_wallet.activities.AddAccountActivity;
import org.chromium.chrome.browser.crypto_wallet.activities.BraveWalletActivity;
import org.chromium.chrome.browser.crypto_wallet.activities.BraveWalletDAppsActivity;
import org.chromium.chrome.browser.crypto_wallet.model.CryptoAccountTypeInfo;
import org.chromium.chrome.browser.crypto_wallet.util.Utils;
import org.chromium.chrome.browser.customtabs.CustomTabActivity;
import org.chromium.chrome.browser.customtabs.FullScreenCustomTabActivity;
import org.chromium.chrome.browser.flags.ChromeFeatureList;
import org.chromium.chrome.browser.flags.ChromeSwitches;
import org.chromium.chrome.browser.fullscreen.BrowserControlsManager;
import org.chromium.chrome.browser.fullscreen.FullscreenManager;
import org.chromium.chrome.browser.informers.BraveSyncAccountDeletedInformer;
import org.chromium.chrome.browser.lifetime.ApplicationLifetime;
import org.chromium.chrome.browser.misc_metrics.MiscAndroidMetricsConnectionErrorHandler;
import org.chromium.chrome.browser.misc_metrics.MiscAndroidMetricsFactory;
import org.chromium.chrome.browser.media.FullscreenVideoPictureInPictureController;
import org.chromium.chrome.browser.multiwindow.BraveMultiWindowUtils;
import org.chromium.chrome.browser.onetabauth.OneTabFirebaseAuthManager;
import org.chromium.chrome.browser.onetabauth.OneTabFirebaseAppCheckManager;
import org.chromium.chrome.browser.onetabauth.OneTabDeviceSessionManager;
import org.chromium.chrome.browser.onetabauth.OneTabLoginActivity;
import org.chromium.chrome.browser.onetabauth.OneTabLoginOverlayCoordinator;
import org.chromium.chrome.browser.onetabauth.OneTabFirebaseSessionStore;
import org.chromium.chrome.browser.onetabauth.OneTabPackagePurchaseManager;
import org.chromium.chrome.browser.multiwindow.MultiInstanceManager;
import org.chromium.chrome.browser.multiwindow.MultiInstanceManager.PersistedInstanceType;
import org.chromium.chrome.browser.multiwindow.MultiWindowUtils;
import org.chromium.chrome.browser.notifications.permissions.NotificationPermissionController;
import org.chromium.chrome.browser.notifications.retention.RetentionNotificationUtil;
import org.chromium.chrome.browser.ntp.BraveFreshNtpHelper;
import org.chromium.chrome.browser.ntp.NewTabPageManager;
import org.chromium.chrome.browser.onboarding.OnboardingPrefManager;
import org.chromium.chrome.browser.onboarding.v2.HighlightDialogFragment;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.preferences.BravePrefServiceBridge;
import org.chromium.chrome.browser.preferences.ChromePreferenceKeys;
import org.chromium.chrome.browser.preferences.ChromeSharedPreferences;
import org.chromium.chrome.browser.preferences.Pref;
import org.chromium.chrome.browser.preferences.PrefServiceUtil;
import org.chromium.chrome.browser.preferences.website.BraveShieldsContentSettings;
import org.chromium.chrome.browser.prefetch.settings.PreloadPagesSettingsBridge;
import org.chromium.chrome.browser.prefetch.settings.PreloadPagesState;
import org.chromium.chrome.browser.privacy.settings.BravePrivacySettings;
import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.rate.BraveRateDialogLauncher;
import org.chromium.chrome.browser.rate.RateUtils;
import org.chromium.chrome.browser.rewards.adaptive_captcha.AdaptiveCaptchaHelper;
import org.chromium.chrome.browser.safe_browsing.SafeBrowsingBridge;
import org.chromium.chrome.browser.safe_browsing.SafeBrowsingState;
import org.chromium.chrome.browser.search_engines.TemplateUrlServiceFactory;
import org.chromium.chrome.browser.set_default_browser.BraveSetDefaultBrowserUtils;
import org.chromium.chrome.browser.settings.BraveNewsPreferencesV2;
import org.chromium.chrome.browser.settings.BraveSearchEngineUtils;
import org.chromium.chrome.browser.settings.BraveWalletPreferences;
import org.chromium.chrome.browser.settings.SettingsNavigationFactory;
import org.chromium.chrome.browser.settings.developer.BraveQAPreferences;
import org.chromium.chrome.browser.share.ShareDelegate;
import org.chromium.chrome.browser.share.ShareDelegate.ShareOrigin;
import org.chromium.chrome.browser.shields.ContentFilteringFragment;
import org.chromium.chrome.browser.shields.CreateCustomFiltersFragment;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.chrome.browser.tab.TabLaunchType;
import org.chromium.chrome.browser.tab.TabSelectionType;
import org.chromium.chrome.browser.tabbed_mode.BraveTabbedAppMenuPropertiesDelegate;
import org.chromium.chrome.browser.tabmodel.TabClosureParams;
import org.chromium.chrome.browser.tabmodel.TabList;
import org.chromium.chrome.browser.tabmodel.TabModel;
import org.chromium.chrome.browser.tabmodel.TabModelSelector;
import org.chromium.chrome.browser.tabmodel.TabModelSelectorTabObserver;
import org.chromium.chrome.browser.tabmodel.TabModelUtils;
import org.chromium.chrome.browser.toolbar.BraveToolbarManager;
import org.chromium.chrome.browser.toolbar.bottom.BottomToolbarConfiguration;
import org.chromium.chrome.browser.toolbar.top.BraveToolbarLayoutImpl;
import org.chromium.chrome.browser.ui.RootUiCoordinator;
import org.chromium.chrome.browser.ui.appmenu.AppMenuPropertiesDelegate;
import org.chromium.chrome.browser.ui.messages.snackbar.Snackbar;
import org.chromium.chrome.browser.ui.messages.snackbar.SnackbarManager;
import org.chromium.chrome.browser.ui.messages.snackbar.SnackbarManager.SnackbarController;
import org.chromium.chrome.browser.ui.messages.snackbar.SnackbarManagerProvider;
import org.chromium.chrome.browser.util.BraveConstants;
import org.chromium.chrome.browser.util.BraveDbUtil;
import org.chromium.chrome.browser.util.KeyboardVisibilityHelper;
import org.chromium.chrome.browser.util.LiveDataUtil;
import org.chromium.chrome.browser.util.PackageUtils;
import org.chromium.chrome.browser.util.UsageMonitor;
import org.chromium.chrome.browser.vpn.BraveVpnNativeWorker;
import org.chromium.chrome.browser.vpn.BraveVpnObserver;
import org.chromium.chrome.browser.vpn.activities.BraveVpnProfileActivity;
import org.chromium.chrome.browser.vpn.fragments.LinkVpnSubscriptionDialogFragment;
import org.chromium.chrome.browser.vpn.timer.TimerDialogFragment;
import org.chromium.chrome.browser.vpn.utils.BraveVpnApiResponseUtils;
import org.chromium.chrome.browser.vpn.utils.BraveVpnPrefUtils;
import org.chromium.chrome.browser.vpn.utils.BraveVpnProfileUtils;
import org.chromium.chrome.browser.vpn.utils.BraveVpnUtils;
import org.chromium.chrome.browser.vpn.wireguard.WireguardConfigUtils;
import org.chromium.chrome.browser.widget.quickactionsearchandbookmark.promo.SearchWidgetPromoPanel;
import org.chromium.chrome.browser.youtube_script_injector.BraveYouTubeScriptInjectorNativeHelper;
import org.chromium.components.browser_ui.settings.SettingsNavigation;
import org.chromium.components.browser_ui.util.motion.MotionEventInfo;
import org.chromium.components.embedder_support.util.UrlConstants;
import org.chromium.components.embedder_support.util.UrlUtilities;
import org.chromium.components.omnibox.AutocompleteRequestType;
import org.chromium.components.prefs.PrefChangeRegistrar;
import org.chromium.components.prefs.PrefChangeRegistrar.PrefObserver;
import org.chromium.components.safe_browsing.BraveSafeBrowsingApiHandler;
import org.chromium.components.search_engines.TemplateUrl;
import org.chromium.components.search_engines.TemplateUrlService;
import org.chromium.components.user_prefs.UserPrefs;
import org.chromium.content_public.browser.LoadUrlParams;
import org.chromium.content_public.browser.WebContents;
import org.chromium.content_public.browser.MediaSession;
import org.chromium.content_public.browser.NavigationHandle;
import org.chromium.content_public.browser.WebContents;
import org.chromium.misc_metrics.mojom.MiscAndroidMetrics;
import org.chromium.mojo.bindings.ConnectionErrorHandler;
import org.chromium.mojo.system.MojoException;
import org.chromium.ui.widget.Toast;
import org.chromium.url.GURL;

import java.util.Arrays;
import java.util.Calendar;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;

/** Brave's extension for ChromeActivity */
@JNINamespace("chrome::android")
@SuppressWarnings("UseSharedPreferencesManagerFromChromeCheck")
public abstract class BraveActivity extends ChromeActivity
        implements BrowsingDataBridge.OnClearBrowsingDataListener,
                BraveVpnObserver,
                ConnectionErrorHandler,
                PrefObserver,
                BraveSafeBrowsingApiHandler.BraveSafeBrowsingApiHandlerDelegate,
                MiscAndroidMetricsConnectionErrorHandler
                        .MiscAndroidMetricsConnectionErrorHandlerDelegate,
                QuickSearchEnginesCallback,
                KeyboardVisibilityHelper.KeyboardVisibilityListener,
                OnSharedPreferenceChangeListener,
                FirstPartyStorageCleanerInterface {
    public static final String BRAVE_WALLET_HOST = "wallet";
    public static final String BRAVE_WALLET_ORIGIN = "brave://wallet/";
    public static final String BRAVE_WALLET_URL = "brave://wallet/crypto/portfolio/assets";
    public static final String BRAVE_BUY_URL = "brave://wallet/crypto/fund-wallet";
    public static final String BRAVE_SEND_URL = "brave://wallet/send";
    public static final String BRAVE_SWAP_URL = "brave://wallet/swap";
    public static final String BRAVE_DEPOSIT_URL = "brave://wallet/crypto/deposit-funds";
    public static final String BRAVE_REWARDS_SETTINGS_URL = "brave://rewards/";
    public static final String BRAVE_REWARDS_SETTINGS_WALLET_VERIFICATION_URL =
            "brave://rewards/#verify";
    public static final String BRAVE_REWARDS_WALLET_RECONNECT_URL = "brave://rewards/reconnect";
    public static final String BRAVE_REWARDS_SETTINGS_MONTHLY_URL = "brave://rewards/#monthly";
    public static final String REWARDS_AC_SETTINGS_URL = "brave://rewards/contribute";
    public static final String BRAVE_REWARDS_RESET_PAGE = "brave://rewards/#reset";
    public static final String BRAVE_AI_CHAT_URL = "chrome-untrusted://chat/tab";
    public static final String REWARDS_LEARN_MORE_URL =
            "https://brave.com/faq-rewards/#unclaimed-funds";
    public static final String BRAVE_TERMS_PAGE =
            "https://basicattentiontoken.org/user-terms-of-service/";
    public static final String BRAVE_PRIVACY_POLICY = "https://brave.com/privacy/browser/#rewards";
    public static final String OPEN_URL = "open_url";
    public static final String BRAVE_WEBCOMPAT_INFO_WIKI_URL =
            "https://github.com/brave/brave-browser/wiki/Web-compatibility-reports";
    private static final String KEY_RESUME_MEDIA_SESSION =
            "org.chromium.chrome.browser.app.KEY_RESUME_MEDIA_SESSION";
    private static final String OTB_AUTH_LOG_TAG = "OneTabAuth";

    private static final int DAYS_4 = 4;
    private static final int DAYS_7 = 7;

    private static final int MONTH_1 = 1;

    public static final int MAX_FAILED_CAPTCHA_ATTEMPTS = 10;

    public static final int APP_OPEN_COUNT_FOR_WIDGET_PROMO = 25;

    public static final String GOOGLE_SEARCH_ENGINE_KEYWORD = ":g";
    public static final String YOUTUBE_SEARCH_ENGINE_KEYWORD = ":yt";
    public static final String BRAVE_SEARCH_ENGINE_KEYWORD = ":br";
    public static final String BING_SEARCH_ENGINE_KEYWORD = ":b";
    public static final String STARTPAGE_SEARCH_ENGINE_KEYWORD = ":sp";

    /** Settings for sending local notification reminders. */
    public static final String CHANNEL_ID = BraveConstants.BRAVE_BROWSER_CHANNEL_ID;

    // Explicitly declare this variable to avoid build errors.
    // It will be removed in asm and parent variable will be used instead.
    private SettableMonotonicObservableSupplier<BrowserControlsManager>
            mBrowserControlsManagerSupplier;

    private static final List<String> sYandexRegions =
            Arrays.asList("AM", "AZ", "BY", "KG", "KZ", "MD", "RU", "TJ", "TM", "UZ");

    private static final int PIP_UPDATE_DELAY_MS = 500;
    private static final int OTB_PIP_REFRESH_RETRY_DELAY_1_MS = 220;
    private static final int OTB_PIP_REFRESH_RETRY_DELAY_2_MS = 520;
    private static final int OTB_PIP_REFRESH_RETRY_DELAY_3_MS = 900;
    private static final int PIP_EXIT_TO_WATCH_PAGE_DELAY_MS = 250;
    private static final int PIP_EXIT_TO_WATCH_PAGE_MAX_AGE_MS = 3000;
    private static final int PIP_RECENT_WATCH_PAGE_RETURN_GRACE_MS = 5000;
    private static final long OTB_FULLSCREEN_UI_SYNC_INTERVAL_MS = 250L;
    private static final long OTB_DEFERRED_ENTITLEMENT_INIT_DELAY_MS = 2500;
    private static final long OTB_SAFE_BROWSING_INIT_DELAY_MS = 1500;
    private static final boolean OTB_ENABLE_STARTUP_MASK = true;
    private static final long OTB_STARTUP_MASK_TIMEOUT_MS = 15000;
    private static final int OTB_LOGIN_ACTIVITY_REQUEST_CODE = 0x4F48;
    private static final String OTB_PERF_TAG = "OneTabTubePerf";
    private static final String OTB_DEVTOOLS_SOCKET_PREFIX = "chrome";
    private static final String OTB_ENABLE_DEVTOOLS_SWITCH = "onetabtube-enable-devtools";
    private static final String OTB_STARTUP_MASK_TAG_LOGO = "otb_startup_mask_logo";
    private boolean mIsVerification;
    public boolean mIsDeepLink;
    private BraveWalletService mBraveWalletService;
    private KeyringService mKeyringService;
    private JsonRpcService mJsonRpcService;
    private MiscAndroidMetrics mMiscAndroidMetrics;
    private SwapService mSwapService;
    @Nullable private WalletModel mWalletModel;
    private BlockchainRegistry mBlockchainRegistry;
    private TxService mTxService;
    private EthTxManagerProxy mEthTxManagerProxy;
    private SolanaTxManagerProxy mSolanaTxManagerProxy;
    private AssetRatioService mAssetRatioService;
    public boolean mLoadedFeed;
    public boolean mComesFromNewTab;
    public CopyOnWriteArrayList<FeedItemsCard> mNewsItemsFeedCards;
    private boolean mIsProcessingPendingDappsTxRequest;
    private int mLastTabId;
    private boolean mNativeInitialized;
    private boolean mSafeBrowsingFlagEnabled;
    private NewTabPageManager mNewTabPageManager;
    private UsageMonitor mUsageMonitor;
    private NotificationPermissionController mNotificationPermissionController;
    private MiscAndroidMetricsConnectionErrorHandler mMiscAndroidMetricsConnectionErrorHandler;
    private AppUpdateManager mAppUpdateManager;
    private boolean mWalletBadgeVisible;
    private boolean mSpoofCustomTab;
    // Boolean flag that indicates if the media session must be resumed
    // when switching in picture-in-picture mode.
    private boolean mResumeMediaSession;
    private boolean mPendingReturnToWatchPageAfterPictureInPictureExit;
    private long mPendingReturnToWatchPageAfterPictureInPictureExitElapsedMs;
    private long mLastReturnToWatchPageAfterPictureInPictureExitElapsedMs;
    private boolean mOneTabSafeBrowsingInitScheduled;
    private boolean mOneTabDeferredEntitlementInitScheduled;
    private boolean mResetOneTabHomeAfterColdLauncherStart;
    private boolean mShowOneTabStartupMaskAfterColdLauncherStart;
    @Nullable private FrameLayout mOneTabStartupMaskView;
    @Nullable private FrameLayout mOneTabPackageLockedOverlayView;
    @Nullable private TextView mOneTabPackageLockedDetailView;
    @Nullable private OneTabFabMenuCoordinator mOneTabFabMenuCoordinator;
    @Nullable private OneTabFirebaseAuthManager mOneTabFirebaseAuthManager;
    @Nullable private OneTabFirebaseAppCheckManager mOneTabFirebaseAppCheckManager;
    @Nullable private OneTabDeviceSessionManager mOneTabDeviceSessionManager;
    @Nullable private OneTabPackagePurchaseManager mOneTabPackagePurchaseManager;
    @Nullable private OneTabLoginOverlayCoordinator mOneTabLoginOverlayCoordinator;
    @Nullable private TabModelSelectorTabObserver mOneTabStartupMaskObserver;
    private boolean mOneTabAuthResolved;
    private boolean mOneTabAuthCheckInProgress;
    private boolean mOneTabAuthGatePendingNavigation;
    private boolean mOneTabLoginActivityLaunched;
    private boolean mOneTabPackageAccessBlocked;
    private final Runnable mHideOneTabStartupMaskRunnable =
            () -> hideOneTabStartupMask("timeout");
    private final Runnable mOneTabFullscreenUiSyncRunnable =
            new Runnable() {
                @Override
                public void run() {
                    if (!OneTabYouTubeMode.isEnabled() || isFinishing() || isDestroyed()) {
                        return;
                    }
                    syncOneTabCleanModeUi();
                    View decorView = getWindow() != null ? getWindow().getDecorView() : null;
                    if (decorView != null) {
                        decorView.postDelayed(this, OTB_FULLSCREEN_UI_SYNC_INTERVAL_MS);
                    }
                }
            };

    private View mQuickSearchEnginesView;

    private SearchWidgetPromoPanel mSearchWidgetPromoPanel;

    private ApplicationStateListener mApplicationStateListener;
    @Nullable private static DevToolsServer sOneTabDevToolsServer;

    /** Serves as a general exception for failed attempts to get BraveActivity. */
    public static class BraveActivityNotFoundException extends Exception {
        public BraveActivityNotFoundException(String message) {
            super(message);
        }
    }

    public BraveActivity() {}

    @Override
    protected void onPostCreate() {
        super.onPostCreate();
        final Bundle savedInstanceState = getSavedInstanceState();
        if (OneTabYouTubeMode.isEnabled()
                && savedInstanceState == null
                && isLauncherEntryIntent(getIntent())) {
            mShowOneTabStartupMaskAfterColdLauncherStart = true;
            maybeShowOneTabStartupMask();
        }
        if (savedInstanceState != null) {
            mResumeMediaSession = savedInstanceState.getBoolean(KEY_RESUME_MEDIA_SESSION, false);
            mPendingReturnToWatchPageAfterPictureInPictureExit =
                    savedInstanceState.getBoolean(
                            "org.chromium.chrome.browser.app.KEY_PENDING_RETURN_TO_WATCH_PAGE",
                            false);
            mPendingReturnToWatchPageAfterPictureInPictureExitElapsedMs =
                    savedInstanceState.getLong(
                            "org.chromium.chrome.browser.app.KEY_PENDING_RETURN_TO_WATCH_PAGE_TS",
                            0L);
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putBoolean(KEY_RESUME_MEDIA_SESSION, mResumeMediaSession);
        outState.putBoolean(
                "org.chromium.chrome.browser.app.KEY_PENDING_RETURN_TO_WATCH_PAGE",
                mPendingReturnToWatchPageAfterPictureInPictureExit);
        outState.putLong(
                "org.chromium.chrome.browser.app.KEY_PENDING_RETURN_TO_WATCH_PAGE_TS",
                mPendingReturnToWatchPageAfterPictureInPictureExitElapsedMs);
    }

    @Override
    public void onResumeWithNative() {
        super.onResumeWithNative();
        boolean oneTabEnabled = OneTabYouTubeMode.isEnabled();

        BraveActivityJni.get().restartStatsUpdater();
        if (!oneTabEnabled && BraveVpnUtils.isVpnFeatureSupported(BraveActivity.this)) {
            BraveVpnNativeWorker.getInstance().addObserver(this);
            BraveVpnUtils.reportBackgroundUsageP3A();
        }

        // The check on mNativeInitialized is mostly to ensure that mojo
        // services for wallet are initialized.
        // TODO(sergz): verify do we need it in that phase or not.
        if (mNativeInitialized && !oneTabEnabled) {
            BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
            if (layout != null) {
                layout.maybeShowTermsOfServiceUpdateRequiredBadge();
                if (layout.isWalletIconVisible()) {
                    updateWalletBadgeVisibility();
                }
            }

            // If a full screen custom tab was closed and bottom controls are enabled,
            // show the bottom toolbar controls again
            if (FullScreenCustomTabActivity.sIsFullScreenCustomTabActivityClosed
                    && BottomToolbarConfiguration.isBraveBottomControlsEnabled()) {
                layout.onBottomControlsVisibilityChanged(true);
            }
            // Reset the flag tracking whether a full screen custom tab was closed
            FullScreenCustomTabActivity.sIsFullScreenCustomTabActivityClosed = false;
        }

        BraveSafeBrowsingApiHandler.getInstance()
                .setDelegate(BraveActivityJni.get().getSafeBrowsingApiKey(), this);

        // We can store a state of that flag as a browser has to be restarted
        // when the flag state is changed in any case
        mSafeBrowsingFlagEnabled =
                ChromeFeatureList.isEnabled(BraveFeatureList.BRAVE_ANDROID_SAFE_BROWSING);

        if (oneTabEnabled) {
            maybeScheduleOneTabSafeBrowsingInit();
            maybeResolveOneTabAuthentication();
        } else {
            executeInitSafeBrowsing(0);
        }

        if (!BraveConfig.IS_ONETABYT) {
            if (mAppUpdateManager == null) {
                mAppUpdateManager = AppUpdateManagerFactory.create(BraveActivity.this);
            }
            mAppUpdateManager
                    .getAppUpdateInfo()
                    .addOnSuccessListener(
                            appUpdateInfo -> {
                                if (appUpdateInfo.installStatus() == InstallStatus.DOWNLOADED) {
                                    completeUpdateSnackbar();
                                }
                            });
        }
        // Executes Leo voice prompt if it was triggered from quick search app widget
        if (!oneTabEnabled) {
            maybeExecuteLeoVoicePrompt();
        }
        startOneTabFullscreenUiSync();
    }

    @Override
    public void onPauseWithNative() {
        if (mUsageMonitor != null) {
            mUsageMonitor.stop();
        }
        hideOneTabStartupMask("pause");
        if (!OneTabYouTubeMode.isEnabled()
                && BraveVpnUtils.isVpnFeatureSupported(BraveActivity.this)) {
            BraveVpnNativeWorker.getInstance().removeObserver(this);
        }
        stopOneTabFullscreenUiSync();
        super.onPauseWithNative();
    }

    @Override
    public boolean onMenuOrKeyboardAction(
            int id, boolean fromMenu, @Nullable MotionEventInfo triggeringMotion) {
        final Tab currentTab = getActivityTab();
        if (BraveConfig.IS_ONETABYT
                && (id == R.id.brave_playlist_id || id == R.id.add_to_playlist_id)) {
            return true;
        }
        if (OneTabYouTubeMode.shouldBlockMenuAction(id)) {
            if (id == R.id.new_tab_menu_id || id == R.id.new_incognito_tab_menu_id) {
                openNewOrSelectExistingTab(OneTabYouTubeMode.getDefaultHomepageUrl(), false);
            }
            return true;
        }

        // Handle items replaced by Brave.
        if (id == R.id.info_menu_id && currentTab != null) {
            ShareDelegate shareDelegate = (ShareDelegate) getShareDelegateSupplier().get();
            shareDelegate.share(currentTab, false, ShareOrigin.OVERFLOW_MENU);
            return true;
        } else if (id == R.id.reload_menu_id) {
            setComesFromNewTab(true);
        } else if (id == R.id.preferences_id) {
            final AppMenuPropertiesDelegate delegate = createAppMenuPropertiesDelegate();
            assert delegate instanceof BraveTabbedAppMenuPropertiesDelegate;
            final BraveTabbedAppMenuPropertiesDelegate braveTabbedAppMenuPropertiesDelegate =
                    (BraveTabbedAppMenuPropertiesDelegate) delegate;

            final Bundle bundle =
                    CustomizeBraveMenu.populateBundle(
                            getResources(),
                            new Bundle(),
                            braveTabbedAppMenuPropertiesDelegate.buildMainMenuModelListWithPolicy(),
                            braveTabbedAppMenuPropertiesDelegate.buildPageActionsModelList());
            SettingsNavigation settingsNavigation =
                    SettingsNavigationFactory.createSettingsNavigation();
            // Follow upstream code and pass null as fragment to show
            // that defaults to main settings screen.
            settingsNavigation.startSettings(BraveActivity.this, null, bundle);
            return true;
        }

        if (super.onMenuOrKeyboardAction(id, fromMenu, triggeringMotion)) {
            return true;
        }

        // Handle items added by Brave.
        if (currentTab == null) {
            return false;
        } else if (id == R.id.exit_id) {
            exitBrave();
        } else if (id == R.id.set_default_browser) {
            BraveSetDefaultBrowserUtils.openDefaultAppsSettings(BraveActivity.this);
        } else if (id == R.id.brave_rewards_id) {
            showRewardsPage();
        } else if (id == R.id.brave_wallet_id) {
            openBraveWallet(false, false, false);
        } else if (id == R.id.brave_playlist_id) {
            openPlaylist(true);
        } else if (id == R.id.add_to_playlist_id) {
            BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
            layout.addMediaToPlaylist();
        } else if (id == R.id.brave_news_id) {
            openBraveNewsSettings();
        } else if (id == R.id.request_brave_vpn_id || id == R.id.request_brave_vpn_check_id) {
            if (!InternetConnection.isNetworkAvailable(BraveActivity.this)) {
                Toast.makeText(BraveActivity.this, R.string.no_internet, Toast.LENGTH_SHORT).show();
            } else {
                if (BraveVpnProfileUtils.getInstance().isBraveVPNConnected(BraveActivity.this)) {
                    TimerDialogFragment timerDialogFragment = new TimerDialogFragment();
                    timerDialogFragment.show(getSupportFragmentManager(), TimerDialogFragment.TAG);
                } else {
                    if (BraveVpnNativeWorker.getInstance().isPurchasedUser()) {
                        BraveVpnPrefUtils.setSubscriptionPurchase(true);
                        if (WireguardConfigUtils.isConfigExist(BraveActivity.this)) {
                            BraveVpnProfileUtils.getInstance().startVpn(BraveActivity.this);
                        } else {
                            BraveVpnUtils.openBraveVpnProfileActivity(BraveActivity.this);
                        }
                    } else {
                        BraveVpnUtils.showProgressDialog(
                                BraveActivity.this,
                                getResources().getString(R.string.vpn_connect_text));
                        if (BraveVpnPrefUtils.isSubscriptionPurchase()) {
                            verifySubscription();
                        } else {
                            BraveVpnUtils.dismissProgressDialog();
                            BraveVpnUtils.openBraveVpnPlansActivity(BraveActivity.this);
                        }
                    }
                }
            }
        } else if (id == R.id.request_vpn_location_id || id == R.id.request_vpn_location_icon_id) {
            BraveVpnUtils.openVpnServerSelectionActivity(BraveActivity.this);
        } else if (id == R.id.brave_leo_id) {
            openBraveLeo();
        } else if (id == CustomizeBraveMenu.BRAVE_CUSTOMIZE_ITEM_ID) {
            final AppMenuPropertiesDelegate delegate = createAppMenuPropertiesDelegate();
            assert delegate instanceof BraveTabbedAppMenuPropertiesDelegate;
            final BraveTabbedAppMenuPropertiesDelegate braveTabbedAppMenuPropertiesDelegate =
                    (BraveTabbedAppMenuPropertiesDelegate) delegate;
            CustomizeBraveMenu.openCustomizeMenuSettings(
                    BraveActivity.this,
                    braveTabbedAppMenuPropertiesDelegate.buildMainMenuModelListWithPolicy(),
                    braveTabbedAppMenuPropertiesDelegate.buildPageActionsModelList());
        } else if (id == R.id.brave_shred_id) {
            shredData(currentTab);
        } else {
            return false;
        }
        return true;
    }

    // Handles only wallet related mojo failures. Don't add handlers for mojo connections that
    // are not related to wallet functionality.
    @Override
    public void onConnectionError(MojoException e) {
        cleanUpWalletNativeServices();
        initWalletNativeServices();
    }

    @Override
    protected void onDestroyInternal() {
        // If the search widget promo panel is shown, we mark its visibility
        // before the activity is destroyed and recreated (e.g when the night mode state changes).
        // The new search widget promo panel will be recreated with the new appropriate theme and
        // position.
        if (mSearchWidgetPromoPanel != null && mSearchWidgetPromoPanel.isShowing()) {
            ChromeSharedPreferences.getInstance()
                    .writeBoolean(OnboardingPrefManager.SHOULD_SHOW_SEARCH_WIDGET_PROMO, true);
            mSearchWidgetPromoPanel.dismiss();
            mSearchWidgetPromoPanel = null;
        }

        if (mNotificationPermissionController != null) {
            NotificationPermissionController.detach(mNotificationPermissionController);
            mNotificationPermissionController = null;
        }

        // Unregister application state listener
        if (mApplicationStateListener != null) {
            ApplicationStatus.unregisterApplicationStateListener(mApplicationStateListener);
            mApplicationStateListener = null;
        }

        BraveSafeBrowsingApiHandler.getInstance().shutdownSafeBrowsing();
        if (mAppUpdateManager != null) {
            mAppUpdateManager.unregisterListener(mInstallStateUpdatedListener);
        }
        stopOneTabFullscreenUiSync();
        super.onDestroyInternal();
        cleanUpWalletNativeServices();
        cleanUpMiscAndroidMetrics();
    }

    @Override
    public void onPictureInPictureModeChanged(boolean inPicture, Configuration newConfig) {
        super.onPictureInPictureModeChanged(inPicture, newConfig);
        syncOneTabCleanModeUi();
        if (inPicture) {
            clearPendingReturnToWatchPageAfterPictureInPictureExit("entered_pip");
            scheduleOneTabPictureInPictureRefresh("pip_mode_changed_enter");
        }
        WebContents currentWebContents = getCurrentWebContents();
        if (mResumeMediaSession) {
            mResumeMediaSession = false;
            MediaSession mediaSession = MediaSession.fromWebContents(currentWebContents);
            if (mediaSession != null) {
                mediaSession.resume();
            }
            // Adopting the same workaround adopted upstream, to check the full implementation
            // see FullscreenVideoPictureInPictureController class.
            // Post a delayed handler to update the Pip status, once things have had some
            // time to settle. When switching into fullscreen mode sometimes the transition is
            // called before relayout has happened, causing the source rectangle for the Pip
            // transition to be wrong. This causes the Pip window to look like it moves to the
            // wrong part of the screen and partially clipped before snapping to its normal place.
            PostTask.postDelayedTask(
                    TaskTraits.UI_BEST_EFFORT,
                    (Runnable) this::refreshPictureInPictureParamsForCurrentVideo,
                    PIP_UPDATE_DELAY_MS);
        }
        if (!inPicture
                && currentWebContents != null
                && BraveYouTubeScriptInjectorNativeHelper.isPictureInPictureAvailable(
                        currentWebContents)) {
            if (shouldDeferOneTabPictureInPictureExitHandling()) {
                clearPendingReturnToWatchPageAfterPictureInPictureExit(
                        "deferred_device_state_pip_exit");
                Log.i(
                        OTB_PERF_TAG,
                        "event=pip_exit_handling_deferred reason=device_locked_or_non_interactive");
                return;
            }
            boolean activeFullscreen = currentWebContents.hasActiveEffectivelyFullscreenVideo();
            FullscreenManager fullscreenManager = getFullscreenManager();
            if (activeFullscreen && shouldReturnToWatchPageAfterPictureInPictureExit()) {
                Log.i(
                        OTB_PERF_TAG,
                        "event=pip_exit_to_watch_page_armed active_fullscreen=%b state=%d",
                        activeFullscreen,
                        ApplicationStatus.getStateForActivity(this));
                armReturnToWatchPageAfterPictureInPictureExit();
                maybeScheduleReturnToWatchPageAfterPictureInPictureExit("pip_exit_callback");
                return;
            }
            if (activeFullscreen) {
                Log.i(
                        OTB_PERF_TAG,
                        "event=pip_exit_cleanup_skipped active_fullscreen=%b",
                        activeFullscreen);
                return;
            }
            // PiP has been dismissed when watching a YT video, then pause it.
            MediaSession mediaSession = MediaSession.fromWebContents(currentWebContents);
            if (mediaSession != null) {
                mediaSession.suspend();
            }
            if (fullscreenManager.getPersistentFullscreenMode()) {
                fullscreenManager.exitPersistentFullscreenMode();
            }
        }
    }

    @Override
    public void onPictureInPictureUiStateChanged(@NonNull PictureInPictureUiState pipState) {
        super.onPictureInPictureUiStateChanged(pipState);
        if (!OneTabYouTubeMode.isEnabled() || !isInPictureInPictureMode()) {
            return;
        }
        scheduleOneTabPictureInPictureRefresh("pip_ui_state_changed");
    }

    /**
     * Gets Wallet model for Brave activity. It may be {@code null} if native initialization has not
     * completed yet.
     */
    @Nullable
    public WalletModel getWalletModel() {
        return mWalletModel;
    }

    private void setWalletBadgeVisibility(boolean visible) {
        mWalletBadgeVisible = visible;
        BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
        layout.updateWalletBadgeVisibility(visible);
    }

    private void maybeShowPendingTransactions() {
        if (mWalletModel != null) {
            // Trigger observer to refresh the transactions and process any pending request.
            mWalletModel.getCryptoModel().refreshTransactions();
        }
    }

    private void maybeShowSignSolTransactionsRequestLayout(
            @NonNull final Runnable openWalletPanelRunnable) {
        assert mBraveWalletService != null;
        mBraveWalletService.getPendingSignSolTransactionsRequests(
                requests -> {
                    if (requests != null && requests.length != 0) {
                        openBraveWalletDAppsActivity(
                                BraveWalletDAppsActivity.ActivityType.SIGN_SOL_TRANSACTIONS);
                        return;
                    }
                    maybeShowSignMessageErrorsLayout(openWalletPanelRunnable);
                });
    }

    private void maybeShowSignMessageErrorsLayout(@NonNull final Runnable openWalletPanelRunnable) {
        assert mBraveWalletService != null;
        mBraveWalletService.getPendingSignMessageErrors(
                errors -> {
                    if (errors != null && errors.length != 0) {
                        openBraveWalletDAppsActivity(
                                BraveWalletDAppsActivity.ActivityType.SIGN_MESSAGE_ERROR);
                    }
                });
        maybeShowSignMessageRequestLayout(openWalletPanelRunnable);
    }

    private void maybeShowSignMessageRequestLayout(
            @NonNull final Runnable openWalletPanelRunnable) {
        assert mBraveWalletService != null;
        mBraveWalletService.getPendingSignMessageRequests(
                requests -> {
                    if (requests != null && requests.length != 0) {
                        BraveWalletDAppsActivity.ActivityType activityType =
                                (requests[0].signData.which() == SignDataUnion.Tag.EthSiweData)
                                        ? BraveWalletDAppsActivity.ActivityType.SIWE_MESSAGE
                                        : BraveWalletDAppsActivity.ActivityType.SIGN_MESSAGE;
                        openBraveWalletDAppsActivity(activityType);
                        return;
                    }
                    maybeShowChainRequestLayout(openWalletPanelRunnable);
                });
    }

    private void maybeShowChainRequestLayout(@NonNull final Runnable openWalletPanelRunnable) {
        assert mJsonRpcService != null;
        mJsonRpcService.getPendingAddChainRequests(
                networks -> {
                    if (networks != null && networks.length != 0) {
                        openBraveWalletDAppsActivity(
                                BraveWalletDAppsActivity.ActivityType.ADD_ETHEREUM_CHAIN);

                        return;
                    }
                    maybeShowSwitchChainRequestLayout(openWalletPanelRunnable);
                });
    }

    private void maybeShowSwitchChainRequestLayout(
            @NonNull final Runnable openWalletPanelRunnable) {
        assert mJsonRpcService != null;
        mJsonRpcService.getPendingSwitchChainRequests(
                requests -> {
                    if (requests != null && requests.length != 0) {
                        openBraveWalletDAppsActivity(
                                BraveWalletDAppsActivity.ActivityType.SWITCH_ETHEREUM_CHAIN);

                        return;
                    }
                    maybeShowAddSuggestTokenRequestLayout(openWalletPanelRunnable);
                });
    }

    private void maybeShowAddSuggestTokenRequestLayout(
            @NonNull final Runnable openWalletPanelRunnable) {
        assert mBraveWalletService != null;
        mBraveWalletService.getPendingAddSuggestTokenRequests(
                requests -> {
                    if (requests != null && requests.length != 0) {
                        openBraveWalletDAppsActivity(
                                BraveWalletDAppsActivity.ActivityType.ADD_TOKEN);

                        return;
                    }
                    maybeShowGetEncryptionPublicKeyRequestLayout(openWalletPanelRunnable);
                });
    }

    private void maybeShowGetEncryptionPublicKeyRequestLayout(
            @NonNull final Runnable openWalletPanelRunnable) {
        assert mBraveWalletService != null;
        mBraveWalletService.getPendingGetEncryptionPublicKeyRequests(
                requests -> {
                    if (requests != null && requests.length != 0) {
                        openBraveWalletDAppsActivity(
                                BraveWalletDAppsActivity.ActivityType
                                        .GET_ENCRYPTION_PUBLIC_KEY_REQUEST);

                        return;
                    }
                    maybeShowDecryptRequestLayout(openWalletPanelRunnable);
                });
    }

    private void maybeShowDecryptRequestLayout(@NonNull final Runnable openWalletPanelRunnable) {
        assert mBraveWalletService != null;
        mBraveWalletService.getPendingDecryptRequests(
                requests -> {
                    if (requests != null && requests.length != 0) {
                        openBraveWalletDAppsActivity(
                                BraveWalletDAppsActivity.ActivityType.DECRYPT_REQUEST);

                        return;
                    }
                    openWalletPanelRunnable.run();
                });
    }

    public void dismissWalletPanelOrDialog() {
        BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
        layout.dismissWalletPanelOrDialog();
    }

    public void showWalletPanel(final boolean ignoreWeb3NotificationPreference) {
        showWalletPanel(true, ignoreWeb3NotificationPreference);
    }

    public void showWalletPanel(
            final boolean showPendingTransactions, final boolean ignoreWeb3NotificationPreference) {
        // Don't show wallet panel if disabled by policy or services not initialized
        if (mKeyringService == null) {
            return;
        }
        final BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
        layout.showWalletIcon(true);
        if (!ignoreWeb3NotificationPreference
                && !BraveWalletPreferences.getPrefWeb3NotificationsEnabled()) {
            return;
        }
        mKeyringService.isLocked(
                locked -> {
                    if (locked) {
                        if (showPendingTransactions) {
                            layout.showWalletPanel();
                        }
                        return;
                    }
                    mKeyringService.hasPendingUnlockRequest(
                            pending -> {
                                if (pending) {
                                    layout.showWalletPanel();
                                    return;
                                }
                                // Create a runnable that opens the Wallet
                                // if the pending requests reach the end of the chain
                                // without returning earlier.
                                final Runnable openWalletPanelRunnable =
                                        () -> {
                                            if (showPendingTransactions && mWalletBadgeVisible) {
                                                maybeShowPendingTransactions();
                                            } else {
                                                getBraveToolbarLayout().showWalletPanel();
                                            }
                                        };
                                maybeShowSignSolTransactionsRequestLayout(openWalletPanelRunnable);
                            });
                });
    }

    public void showWalletOnboarding() {
        BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
        layout.showWalletIcon(true);
        if (!BraveWalletPreferences.getPrefWeb3NotificationsEnabled()) {
            return;
        }
        layout.showWalletPanel();
    }

    public void walletInteractionDetected(WebContents webContents) {
        Tab tab = getActivityTab();
        if (tab == null
                || !webContents.getLastCommittedUrl().equals(
                        tab.getWebContents().getLastCommittedUrl())) {
            return;
        }
        BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
        layout.showWalletIcon(true);
        updateWalletBadgeVisibility();
    }

    public void showAccountCreation(@CoinType.EnumType int coinType) {
        if (mWalletModel != null) {
            mWalletModel.getDappsModel().addAccountCreationRequest(coinType);
        }
    }

    private void updateWalletBadgeVisibility() {
        if (mWalletModel != null) {
            mWalletModel.getDappsModel().updateWalletBadgeVisibility();
        }
    }

    private void verifySubscription() {
        MutableLiveData<PurchaseModel> _activePurchases = new MutableLiveData();
        LiveData<PurchaseModel> activePurchases = _activePurchases;
        InAppPurchaseWrapper.getInstance()
                .queryPurchases(_activePurchases, InAppPurchaseWrapper.SubscriptionProduct.VPN);
        LiveDataUtil.observeOnce(
                activePurchases,
                activePurchaseModel -> {
                    if (activePurchaseModel != null) {
                        BraveVpnNativeWorker.getInstance()
                                .verifyPurchaseToken(
                                        activePurchaseModel.getPurchaseToken(),
                                        activePurchaseModel.getProductId(),
                                        BraveVpnUtils.SUBSCRIPTION_PARAM_TEXT,
                                        getPackageName());
                    } else {
                        BraveVpnApiResponseUtils.queryPurchaseFailed(BraveActivity.this);
                        if (!mIsVerification) {
                            BraveVpnUtils.openBraveVpnPlansActivity(BraveActivity.this);
                        }
                    }
                });
    }

    @Override
    public boolean onOptionsItemSelected(
            int itemId, @Nullable Bundle menuItemData, @Nullable MotionEventInfo triggeringMotion) {
        if (OneTabYouTubeMode.shouldBlockMenuAction(itemId)) {
            if (itemId == R.id.new_tab_menu_id || itemId == R.id.new_incognito_tab_menu_id) {
                openNewOrSelectExistingTab(OneTabYouTubeMode.getDefaultHomepageUrl(), false);
            }
            return true;
        }

        if (itemId == R.id.new_tab_menu_id) {
            LayoutManagerChrome layoutManager =
                    (LayoutManagerChrome)
                            BraveReflectionUtil.getField(
                                    ChromeTabbedActivity.class, "mLayoutManager", this);
            if (layoutManager != null
                    && layoutManager.getHubLayoutForTesting() != null
                    && !layoutManager.getHubLayoutForTesting().isActive()
                    && mMiscAndroidMetrics != null) {
                mMiscAndroidMetrics.recordAppMenuNewTab();
            }
        } else if (itemId == R.id.home_menu_id) {
            if (getToolbarManager() instanceof BraveToolbarManager) {
                ((BraveToolbarManager) getToolbarManager()).openHomepage();
            }
        }
        return super.onOptionsItemSelected(itemId, menuItemData, triggeringMotion);
    }

    @Override
    public void onVerifyPurchaseToken(
            String jsonResponse, String purchaseToken, String productId, boolean isSuccess) {
        if (isSuccess) {
            Long purchaseExpiry = BraveVpnUtils.getPurchaseExpiryDate(jsonResponse);
            int paymentState = BraveVpnUtils.getPaymentState(jsonResponse);
            if (purchaseExpiry > 0 && purchaseExpiry >= System.currentTimeMillis()) {
                BraveVpnPrefUtils.setPurchaseToken(purchaseToken);
                BraveVpnPrefUtils.setProductId(productId);
                BraveVpnPrefUtils.setPurchaseExpiry(purchaseExpiry);
                BraveVpnPrefUtils.setSubscriptionPurchase(true);
                BraveVpnPrefUtils.setPaymentState(paymentState);
                if (BraveVpnPrefUtils.isResetConfiguration()) {
                    BraveVpnUtils.dismissProgressDialog();
                    BraveVpnUtils.openBraveVpnProfileActivity(BraveActivity.this);
                } else {
                    if (!mIsVerification) {
                        checkForVpn();
                    } else {
                        mIsVerification = false;
                        if (BraveVpnProfileUtils.getInstance().isBraveVPNConnected(
                                    BraveActivity.this)
                                && !TextUtils.isEmpty(BraveVpnPrefUtils.getHostname())
                                && !TextUtils.isEmpty(BraveVpnPrefUtils.getClientId())
                                && !TextUtils.isEmpty(BraveVpnPrefUtils.getSubscriberCredential())
                                && !TextUtils.isEmpty(BraveVpnPrefUtils.getApiAuthToken())) {
                            BraveVpnNativeWorker.getInstance().verifyCredentials(
                                    BraveVpnPrefUtils.getHostname(),
                                    BraveVpnPrefUtils.getClientId(),
                                    BraveVpnPrefUtils.getSubscriberCredential(),
                                    BraveVpnPrefUtils.getApiAuthToken());
                        }
                    }
                    BraveVpnUtils.dismissProgressDialog();
                }
            } else {
                BraveVpnApiResponseUtils.queryPurchaseFailed(BraveActivity.this);
                if (!mIsVerification) {
                    BraveVpnUtils.openBraveVpnPlansActivity(BraveActivity.this);
                }
                mIsVerification = false;
            }
        } else {
            BraveVpnApiResponseUtils.queryPurchaseFailed(BraveActivity.this);
            if (!mIsVerification) {
                BraveVpnUtils.openBraveVpnPlansActivity(BraveActivity.this);
            }
            mIsVerification = false;
        }
    };

    private void checkForVpn() {
        BraveVpnNativeWorker.getInstance().reportForegroundP3A();
        new Thread() {
            @Override
            public void run() {
                Intent intent = GoBackend.VpnService.prepare(BraveActivity.this);
                if (intent != null
                        || !WireguardConfigUtils.isConfigExist(getApplicationContext())) {
                    BraveVpnUtils.dismissProgressDialog();
                    BraveVpnUtils.openBraveVpnProfileActivity(BraveActivity.this);
                    return;
                }
                BraveVpnProfileUtils.getInstance().startVpn(BraveActivity.this);
            }
        }.start();
    }

    @Override
    public void onVerifyCredentials(String jsonVerifyCredentials, boolean isSuccess) {
        if (!isSuccess) {
            if (BraveVpnProfileUtils.getInstance().isBraveVPNConnected(BraveActivity.this)) {
                BraveVpnProfileUtils.getInstance().stopVpn(BraveActivity.this);
            }
            Intent braveVpnProfileIntent =
                    new Intent(BraveActivity.this, BraveVpnProfileActivity.class);
            braveVpnProfileIntent.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
            braveVpnProfileIntent.putExtra(BraveVpnUtils.VERIFY_CREDENTIALS_FAILED, true);
            braveVpnProfileIntent.setAction(Intent.ACTION_VIEW);
            startActivity(braveVpnProfileIntent);
        }
    }

    @Override
    public void initializeState() {
        if (!OneTabYouTubeMode.isEnabled() && BraveFreshNtpHelper.isEnabled()) {
            setForegroundSessionEndsTriggered();
        }
        super.initializeState();
        if (isNoRestoreState()) {
            CommandLine.getInstance().appendSwitch(ChromeSwitches.NO_RESTORE_STATE);
        }

        if (isClearBrowsingDataOnExit()) {
            List<Integer> dataTypes =
                    Arrays.asList(
                            BrowsingDataType.HISTORY,
                            BrowsingDataType.SITE_DATA,
                            BrowsingDataType.CACHE);

            int[] dataTypesArray = CollectionUtil.integerCollectionToIntArray(dataTypes);

            // has onBrowsingDataCleared() as an @Override callback from implementing
            // BrowsingDataBridge.OnClearBrowsingDataListener
            BrowsingDataBridge.getForProfile(getCurrentProfile())
                    .clearBrowsingData(this, dataTypesArray, TimePeriod.ALL_TIME);
        }

        setLoadedFeed(false);
        setComesFromNewTab(false);
        setNewsItemsFeedCards(null);
        BraveSearchEngineUtils.initializeBraveSearchEngineStates(getTabModelSelector());
        Intent intent = getIntent();
        if (intent != null
                && intent.getBooleanExtra(BraveWalletActivity.RESTART_WALLET_ACTIVITY, false)) {
            openBraveWallet(
                    false,
                    intent.getBooleanExtra(
                            BraveWalletActivity.RESTART_WALLET_ACTIVITY_SETUP, false),
                    intent.getBooleanExtra(
                            BraveWalletActivity.RESTART_WALLET_ACTIVITY_RESTORE, false));
        }
    }

    public int getLastTabId() {
        return mLastTabId;
    }

    public void setLastTabId(int lastTabId) {
        this.mLastTabId = lastTabId;
    }

    public boolean isLoadedFeed() {
        return mLoadedFeed;
    }

    public void setLoadedFeed(boolean loadedFeed) {
        this.mLoadedFeed = loadedFeed;
    }

    public CopyOnWriteArrayList<FeedItemsCard> getNewsItemsFeedCards() {
        return mNewsItemsFeedCards;
    }

    public void setNewsItemsFeedCards(CopyOnWriteArrayList<FeedItemsCard> newsItemsFeedCards) {
        this.mNewsItemsFeedCards = newsItemsFeedCards;
    }

    public void setComesFromNewTab(boolean comesFromNewTab) {
        this.mComesFromNewTab = comesFromNewTab;
    }

    public boolean isComesFromNewTab() {
        return mComesFromNewTab;
    }

    @Override
    public void onBrowsingDataCleared() {}

    @Override
    public void onResume() {
        super.onResume();
        mIsProcessingPendingDappsTxRequest = false;

        PostTask.postTask(
                TaskTraits.BEST_EFFORT_MAY_BLOCK, () -> { BraveStatsUtil.removeShareStatsFile(); });

        // We need to enable widget promo for later release
        /* int appOpenCountForWidgetPromo = SharedPreferencesManager.getInstance().readInt(
                BravePreferenceKeys.BRAVE_APP_OPEN_COUNT_FOR_WIDGET_PROMO);
        if (appOpenCountForWidgetPromo < APP_OPEN_COUNT_FOR_WIDGET_PROMO) {
            SharedPreferencesManager.getInstance().writeInt(
                    BravePreferenceKeys.BRAVE_APP_OPEN_COUNT_FOR_WIDGET_PROMO,
                    appOpenCountForWidgetPromo + 1);
        } */
        if (mUsageMonitor != null) {
            mUsageMonitor.start();
        }

        if (OneTabYouTubeMode.isEnabled()) {
            PostTask.postTask(TaskTraits.UI_DEFAULT, this::enforceOneTabYouTubeMode);
            if (mOneTabPackageAccessBlocked
                    && !mOneTabAuthCheckInProgress
                    && !mOneTabLoginActivityLaunched) {
                PostTask.postTask(TaskTraits.UI_DEFAULT, this::resolveOneTabPackageAccess);
            }
            if (isInPictureInPictureMode()) {
                scheduleOneTabPictureInPictureRefresh("on_resume");
            }
        }
        maybeScheduleReturnToWatchPageAfterPictureInPictureExit("on_resume");
        syncOneTabCleanModeUi();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (!hasFocus || !OneTabYouTubeMode.isEnabled()) {
            return;
        }
        if (isInPictureInPictureMode()) {
            scheduleOneTabPictureInPictureRefresh("window_focus_changed");
        }
    }

    @Override
    public void performPostInflationStartup() {
        super.performPostInflationStartup();

        createNotificationChannel();
        syncOneTabCleanModeUi();
    }

    @Override
    public void onStartWithNative() {
        // Register application state listener to detect foreground session end
        if (!OneTabYouTubeMode.isEnabled()
                && BraveFreshNtpHelper.isEnabled()
                && mApplicationStateListener == null) {
            mApplicationStateListener = this::onApplicationStateChange;
            ApplicationStatus.registerApplicationStateListener(mApplicationStateListener);
        }

        super.onStartWithNative();
        if (OneTabYouTubeMode.isEnabled() && !mNativeInitialized) {
            mShowOneTabStartupMaskAfterColdLauncherStart = true;
        }
        ensureOneTabStartupMaskObserver(getTabModelSelector());
        maybeShowOneTabStartupMask();
        if (shouldEnableOneTabDevToolsServer()) {
            ensureOneTabDevToolsServerStarted();
        }
        syncOneTabCleanModeUi();
        maybeResolveOneTabAuthentication();
    }

    private void syncOneTabCleanModeUi() {
        if (!OneTabYouTubeMode.isEnabled()) {
            return;
        }

        enforceOneTabChromeHidden();
        collapseOneTabBrowserControls();
        refreshOneTabFabMenu();
    }

    private void ensureOneTabAuthComponents() {
        if (!OneTabYouTubeMode.isEnabled()) {
            return;
        }
        if (mOneTabFirebaseAuthManager == null) {
            mOneTabFirebaseAuthManager = new OneTabFirebaseAuthManager();
        }
        if (mOneTabFirebaseAppCheckManager == null) {
            mOneTabFirebaseAppCheckManager = new OneTabFirebaseAppCheckManager();
        }
        if (mOneTabDeviceSessionManager == null) {
            mOneTabDeviceSessionManager = new OneTabDeviceSessionManager();
        }
        if (mOneTabPackagePurchaseManager == null) {
            mOneTabPackagePurchaseManager = new OneTabPackagePurchaseManager();
        }
        if (mOneTabLoginOverlayCoordinator == null) {
            mOneTabLoginOverlayCoordinator = new OneTabLoginOverlayCoordinator();
        }
    }

    private boolean isOneTabAuthenticated() {
        if (!OneTabYouTubeMode.isEnabled()) {
            return true;
        }
        ensureOneTabAuthComponents();
        return mOneTabAuthResolved;
    }

    private void maybeResolveOneTabAuthentication() {
        if (!OneTabYouTubeMode.isEnabled() || isFinishing() || isDestroyed()) {
            return;
        }
        ensureOneTabAuthComponents();
        setOneTabContentLocked(true);
        if (mOneTabAuthCheckInProgress) {
            return;
        }
        if (mOneTabLoginActivityLaunched) {
            return;
        }
        if (mOneTabFirebaseAuthManager != null && mOneTabFirebaseAuthManager.isSignedInFast()) {
            mOneTabAuthCheckInProgress = true;
            resolveOneTabDeviceAccess();
            return;
        }

        mOneTabAuthCheckInProgress = true;
        mOneTabFirebaseAuthManager.resolveAuthentication(
                (authenticated, message) -> {
                    if (authenticated) {
                        resolveOneTabDeviceAccess();
                        return;
                    }
                    mOneTabAuthCheckInProgress = false;
                    mOneTabAuthResolved = false;
                    launchOneTabLoginActivity(message);
                });
    }

    private void resolveOneTabDeviceAccess() {
        ensureOneTabAuthComponents();
        if (mOneTabDeviceSessionManager == null) {
            mOneTabAuthCheckInProgress = false;
            mOneTabAuthResolved = false;
            launchOneTabLoginActivity("ยังตรวจสอบสิทธิ์อุปกรณ์ไม่ได้ในขณะนี้");
            return;
        }

        mOneTabDeviceSessionManager.ensureAccess(
                (allowed, message) -> {
                    if (allowed) {
                        resolveOneTabPackageAccess();
                        return;
                    }

                    mOneTabAuthCheckInProgress = false;
                    mOneTabAuthResolved = false;
                    launchOneTabLoginActivity(message);
                });
    }

    private void resolveOneTabPackageAccess() {
        ensureOneTabAuthComponents();
        if (mOneTabFirebaseAppCheckManager == null || mOneTabPackagePurchaseManager == null) {
            Log.w(OTB_AUTH_LOG_TAG, "Package access components unavailable; allowing baseline access");
            handleOneTabAuthenticated();
            return;
        }

        OneTabFirebaseSessionStore.Session session = new OneTabFirebaseSessionStore().read();
        if (TextUtils.isEmpty(session.idToken)) {
            mOneTabAuthCheckInProgress = false;
            mOneTabAuthResolved = false;
            launchOneTabLoginActivity("กรุณาเข้าสู่ระบบใหม่ก่อนใช้งาน GO_PLAY");
            return;
        }

        mOneTabFirebaseAppCheckManager.resolveAppCheckToken(
                (success, token, message) -> {
                    if (!success || TextUtils.isEmpty(token)) {
                        Log.w(
                                OTB_AUTH_LOG_TAG,
                                "Package access App Check unavailable; allowing baseline access message=%s",
                                TextUtils.isEmpty(message) ? "<empty>" : message);
                        handleOneTabAuthenticated();
                        return;
                    }

                    PostTask.postTask(
                            TaskTraits.BEST_EFFORT_MAY_BLOCK,
                            () -> {
                                OneTabPackagePurchaseManager.AccessStateResult result =
                                        mOneTabPackagePurchaseManager.fetchPackageAccessState(
                                                session.idToken, token);
                                PostTask.postTask(
                                        TaskTraits.UI_DEFAULT,
                                        () -> {
                                            if (!result.success) {
                                                Log.w(
                                                        OTB_AUTH_LOG_TAG,
                                                        "Package access unavailable; allowing baseline access message=%s",
                                                        TextUtils.isEmpty(result.message)
                                                                ? "<empty>"
                                                                : result.message);
                                                handleOneTabAuthenticated();
                                                return;
                                            }
                                            if (result.allowed) {
                                                handleOneTabAuthenticated();
                                                return;
                                            }

                                            handleOneTabPackageLocked(result.message);
                                        });
                            });
                });
    }

    private void handleOneTabAuthenticated() {
        mOneTabAuthResolved = true;
        mOneTabAuthCheckInProgress = false;
        mOneTabLoginActivityLaunched = false;
        mOneTabPackageAccessBlocked = false;
        setOneTabContentLocked(false);
        hideOneTabPackageLockedOverlay();
        hideOneTabLoginOverlay();
        if (mOneTabAuthGatePendingNavigation) {
            mOneTabAuthGatePendingNavigation = false;
            PostTask.postTask(TaskTraits.UI_DEFAULT, this::enforceOneTabYouTubeMode);
        }
    }

    private void handleOneTabPackageLocked(@Nullable String message) {
        mOneTabAuthResolved = true;
        mOneTabAuthCheckInProgress = false;
        mOneTabLoginActivityLaunched = false;
        mOneTabPackageAccessBlocked = true;
        setOneTabContentLocked(false);
        showOneTabPackageLockedOverlay(message);
    }

    private void launchOneTabLoginActivity(@Nullable String message) {
        if (!OneTabYouTubeMode.isEnabled() || isFinishing() || isDestroyed()) {
            return;
        }
        if (mOneTabLoginActivityLaunched) {
            return;
        }
        hideOneTabPackageLockedOverlay();
        hideOneTabLoginOverlay();
        mOneTabLoginActivityLaunched = true;
        Intent intent = new Intent(this, OneTabLoginActivity.class);
        if (!TextUtils.isEmpty(message)) {
            intent.putExtra(OneTabLoginActivity.EXTRA_ERROR_MESSAGE, message);
        }
        startActivityForResult(intent, OTB_LOGIN_ACTIVITY_REQUEST_CODE);
    }

    private void showOneTabLoginOverlay(boolean loading, @Nullable String message) {
        if (!OneTabYouTubeMode.isEnabled()) {
            return;
        }
        ensureOneTabAuthComponents();
        hideOneTabPackageLockedOverlay();
        setOneTabContentLocked(true);
        pauseOneTabPlaybackForAuthGate();
        mOneTabLoginOverlayCoordinator.show(
                this,
                () -> {
                    if (mOneTabFirebaseAuthManager == null || mOneTabAuthCheckInProgress) {
                        return;
                    }
                    mOneTabAuthCheckInProgress = true;
                    mOneTabLoginOverlayCoordinator.setPrimaryActionVisible(true);
                    mOneTabLoginOverlayCoordinator.setLoading(true, "กำลังเปิด Google Sign-in…");
                    mOneTabFirebaseAuthManager.beginGoogleSignIn(
                            this,
                            (authenticated, authMessage) -> {
                                if (authenticated) {
                                    resolveOneTabDeviceAccess();
                                } else {
                                    mOneTabAuthCheckInProgress = false;
                                    showOneTabLoginOverlay(false, "");
                                    showOneTabLoginError(authMessage);
                                }
                            });
                });
        mOneTabLoginOverlayCoordinator.setPrimaryActionVisible(true);
        mOneTabLoginOverlayCoordinator.setLoading(loading, message);
    }

    private void showOneTabPackageLockedOverlay(@Nullable String message) {
        if (!OneTabYouTubeMode.isEnabled()) {
            return;
        }
        ensureOneTabAuthComponents();
        pauseOneTabPlaybackForAuthGate();
        hideOneTabLoginOverlay();

        ViewGroup overlayContainer = findViewById(R.id.compositor_view_holder);
        if (overlayContainer == null) {
            overlayContainer = findViewById(android.R.id.content);
        }
        if (overlayContainer == null) {
            return;
        }

        if (mOneTabPackageLockedOverlayView == null) {
            FrameLayout overlay = new FrameLayout(this);
            overlay.setClickable(true);
            overlay.setFocusable(true);
            overlay.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
            overlay.setBackgroundColor(Color.parseColor("#80000000"));

            LinearLayout content = new LinearLayout(this);
            content.setOrientation(LinearLayout.VERTICAL);
            content.setGravity(Gravity.CENTER_HORIZONTAL);
            content.setPadding(dp(24), dp(24), dp(24), dp(24));

            FrameLayout.LayoutParams contentParams =
                    new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT);
            contentParams.gravity = Gravity.CENTER;
            overlay.addView(content, contentParams);

            ImageView lockView = new ImageView(this);
            lockView.setImageResource(android.R.drawable.ic_lock_lock);
            lockView.setAdjustViewBounds(true);
            lockView.setScaleType(ImageView.ScaleType.FIT_CENTER);
            lockView.setAlpha(0.96f);
            LinearLayout.LayoutParams lockParams =
                    new LinearLayout.LayoutParams(dp(112), dp(112));
            content.addView(lockView, lockParams);

            TextView messageView = new TextView(this);
            messageView.setText(R.string.onetab_package_locked_message);
            messageView.setGravity(Gravity.CENTER);
            messageView.setTextColor(Color.WHITE);
            messageView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
            messageView.setPadding(0, dp(20), 0, 0);
            content.addView(
                    messageView,
                    new LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT));

            TextView detailView = new TextView(this);
            detailView.setGravity(Gravity.CENTER);
            detailView.setTextColor(Color.parseColor("#E6FFFFFF"));
            detailView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
            detailView.setPadding(dp(12), dp(12), dp(12), 0);
            detailView.setVisibility(View.GONE);
            content.addView(
                    detailView,
                    new LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT));

            mOneTabPackageLockedOverlayView = overlay;
            mOneTabPackageLockedDetailView = detailView;
        }

        if (mOneTabPackageLockedOverlayView.getParent() == null) {
            overlayContainer.addView(
                    mOneTabPackageLockedOverlayView,
                    new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT));
        }

        if (mOneTabPackageLockedDetailView != null) {
            if (TextUtils.isEmpty(message)) {
                mOneTabPackageLockedDetailView.setVisibility(View.GONE);
            } else {
                mOneTabPackageLockedDetailView.setVisibility(View.VISIBLE);
                mOneTabPackageLockedDetailView.setText(message);
            }
        }

        mOneTabPackageLockedOverlayView.setVisibility(View.VISIBLE);
        mOneTabPackageLockedOverlayView.bringToFront();
        mOneTabPackageLockedOverlayView.setTranslationZ(dp(48));
        mOneTabPackageLockedOverlayView.setElevation(dp(48));
    }

    private void setOneTabContentLocked(boolean locked) {
        View compositorViewHolder = findViewById(R.id.compositor_view_holder);
        if (compositorViewHolder != null) {
            compositorViewHolder.setVisibility(locked ? View.INVISIBLE : View.VISIBLE);
        }
    }

    private void hideOneTabPackageLockedOverlay() {
        if (mOneTabPackageLockedOverlayView != null) {
            mOneTabPackageLockedOverlayView.setVisibility(View.GONE);
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void pauseOneTabPlaybackForAuthGate() {
        Tab currentTab = getActivityTab();
        if (currentTab == null) {
            return;
        }
        currentTab.stopLoading();
        WebContents webContents = currentTab.getWebContents();
        if (webContents == null) {
            return;
        }
        webContents.evaluateJavaScript(
                "(function(){try{document.querySelectorAll('video').forEach(function(v){v.pause();});}catch(e){}return true;})();",
                null);
    }

    private void showOneTabLoginError(@Nullable String message) {
        if (mOneTabLoginOverlayCoordinator != null) {
            mOneTabLoginOverlayCoordinator.showError(message);
        }
    }

    private void hideOneTabLoginOverlay() {
        if (mOneTabLoginOverlayCoordinator != null) {
            mOneTabLoginOverlayCoordinator.dismiss();
        }
    }

    private void enforceOneTabChromeHidden() {
        if (!OneTabYouTubeMode.isEnabled()) {
            return;
        }
        setOneTabViewCollapsed(R.id.toolbar);
        setOneTabViewCollapsed(R.id.toolbar_hairline);
        setOneTabViewCollapsed(R.id.control_container);
        setOneTabViewCollapsed(R.id.toolbar_progress_bar_container);
        setOneTabViewCollapsed(R.id.bottom_controls);
        setOneTabViewCollapsed(R.id.bottom_toolbar);
    }

    private void setOneTabViewCollapsed(int viewId) {
        View view = findViewById(viewId);
        if (view == null) {
            return;
        }

        if (view.getVisibility() != View.GONE) {
            view.setVisibility(View.GONE);
        }
        view.setTranslationY(0f);
        view.setAlpha(0f);

        ViewGroup.LayoutParams layoutParams = view.getLayoutParams();
        if (layoutParams != null && layoutParams.height != 0) {
            layoutParams.height = 0;
            view.setLayoutParams(layoutParams);
        }
    }

    private void collapseOneTabBrowserControls() {
        if (!OneTabYouTubeMode.isEnabled() || mBrowserControlsManagerSupplier == null) {
            return;
        }

        final BrowserControlsManager browserControlsManager = mBrowserControlsManagerSupplier.get();
        if (browserControlsManager == null) {
            return;
        }

        browserControlsManager.setAnimateBrowserControlsHeightChanges(false);
        browserControlsManager.setTopControlsHeight(0, 0);
        browserControlsManager.setBottomControlsHeight(0, 0);
    }

    private void refreshOneTabFabMenu() {
        if (!OneTabYouTubeMode.isEnabled()) {
            return;
        }

        if (mOneTabFabMenuCoordinator == null) {
            mOneTabFabMenuCoordinator = new OneTabFabMenuCoordinator(this);
        }

        Tab activityTab = getActivityTab();
        mOneTabFabMenuCoordinator.setForceHidden(shouldForceHideOneTabFab(activityTab));
        mOneTabFabMenuCoordinator.refresh(activityTab);
    }

    private boolean shouldForceHideOneTabFab(@Nullable Tab tab) {
        if (!OneTabYouTubeMode.isEnabled()) {
            return false;
        }
        if (isInPictureInPictureMode()) {
            return true;
        }
        WebContents webContents = tab != null ? tab.getWebContents() : null;
        if (webContents != null) {
            if (webContents.hasActiveEffectivelyFullscreenVideo()) {
                return true;
            }
            if (BraveYouTubeScriptInjectorNativeHelper.hasFullscreenBeenRequested(webContents)) {
                return true;
            }
        }
        FullscreenManager fullscreenManager = getFullscreenManager();
        return fullscreenManager != null && fullscreenManager.getPersistentFullscreenMode();
    }

    private void startOneTabFullscreenUiSync() {
        if (!OneTabYouTubeMode.isEnabled() || getWindow() == null) {
            return;
        }
        View decorView = getWindow().getDecorView();
        decorView.removeCallbacks(mOneTabFullscreenUiSyncRunnable);
        decorView.post(mOneTabFullscreenUiSyncRunnable);
    }

    private void stopOneTabFullscreenUiSync() {
        if (getWindow() == null) {
            return;
        }
        View decorView = getWindow().getDecorView();
        decorView.removeCallbacks(mOneTabFullscreenUiSyncRunnable);
    }

    private void ensureOneTabDevToolsServerStarted() {
        if (!OneTabYouTubeMode.isEnabled()) {
            return;
        }

        if (sOneTabDevToolsServer == null) {
            sOneTabDevToolsServer = new DevToolsServer(OTB_DEVTOOLS_SOCKET_PREFIX);
        }
        if (!sOneTabDevToolsServer.isRemoteDebuggingEnabled()) {
            sOneTabDevToolsServer.setRemoteDebuggingEnabled(
                    true, DevToolsServer.Security.ALLOW_DEBUG_PERMISSION);
            Log.i(OTB_PERF_TAG, "event=devtools_server enabled=true");
        }
    }

    private boolean shouldEnableOneTabDevToolsServer() {
        if (!OneTabYouTubeMode.isEnabled()) {
            return false;
        }

        // Keep remote debugging available only as an explicit developer opt-in in OneTab builds.
        return ApkInfo.isDebugApp()
                && CommandLine.getInstance().hasSwitch(OTB_ENABLE_DEVTOOLS_SWITCH);
    }

    private void maybeScheduleOneTabSafeBrowsingInit() {
        if (mOneTabSafeBrowsingInitScheduled) {
            return;
        }

        mOneTabSafeBrowsingInitScheduled = true;
        executeInitSafeBrowsing(OTB_SAFE_BROWSING_INIT_DELAY_MS);
    }

    private void maybeScheduleOneTabDeferredEntitlementInit() {
        if (!OneTabYouTubeMode.isEnabled() || mOneTabDeferredEntitlementInitScheduled) {
            return;
        }

        mOneTabDeferredEntitlementInitScheduled = true;
        PostTask.postDelayedTask(
                TaskTraits.UI_DEFAULT,
                () -> {
                    if (isFinishing() || isDestroyed()) {
                        return;
                    }

                    BraveVpnNativeWorker.getInstance().reloadPurchasedState();

                    Profile profile = mTabModelProfileSupplier.get();
                    if (profile != null
                            && ChromeFeatureList.isEnabled(BraveFeatureList.BRAVE_ORIGIN)
                            && !BraveOriginSubscriptionPrefs.getIsSubscriptionActive(profile)) {
                        BraveOriginSubscriptionPrefs.verifyPurchase(profile);
                    }
                },
                OTB_DEFERRED_ENTITLEMENT_INIT_DELAY_MS);
    }

    private void syncScheduledCaptchaPausedState() {
        if (UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getInteger(BravePref.SCHEDULED_CAPTCHA_FAILED_ATTEMPTS)
                >= MAX_FAILED_CAPTCHA_ATTEMPTS) {
            UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                    .setBoolean(BravePref.SCHEDULED_CAPTCHA_PAUSED, true);
        }

        if (BraveQAPreferences.shouldVlogRewards()) {
            Log.e(
                    AdaptiveCaptchaHelper.TAG,
                    "Failed attempts : "
                            + UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                                    .getInteger(BravePref.SCHEDULED_CAPTCHA_FAILED_ATTEMPTS));
        }
    }

    private void maybeRunScheduledCaptchaStartupWork() {
        if (!UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                .getBoolean(BravePref.SCHEDULED_CAPTCHA_PAUSED)) {
            maybeSolveAdaptiveCaptcha();
        }
    }

    private void ensureOneTabStartupMaskObserver(@Nullable TabModelSelector selector) {
        if (!OneTabYouTubeMode.isEnabled() || selector == null || mOneTabStartupMaskObserver != null) {
            return;
        }

        mOneTabStartupMaskObserver =
                new TabModelSelectorTabObserver(selector) {
                    @Override
                    public void onPageLoadStarted(Tab tab, GURL url) {
                        if (shouldTrackOneTabStartupMaskForTab(tab, url)) {
                            maybeShowOneTabStartupMask();
                        }
                        syncOneTabCleanModeUi();
                    }

                    @Override
                    public void onPageLoadFinished(Tab tab, GURL url) {
                        if (shouldTrackOneTabStartupMaskForTab(tab, url)) {
                            hideOneTabStartupMask("page_load_finished");
                        }
                        syncOneTabCleanModeUi();
                    }

                    @Override
                    public void onDidFinishNavigationInPrimaryMainFrame(
                            Tab tab, NavigationHandle navigation) {
                        if (!navigation.isInPrimaryMainFrame() || !navigation.hasCommitted()) {
                            return;
                        }

                        if (shouldTrackOneTabStartupMaskForTab(tab, navigation.getUrl())) {
                            PostTask.postDelayedTask(
                                    TaskTraits.UI_DEFAULT,
                                    () -> hideOneTabStartupMask("main_frame_commit"),
                                    300);
                        }
                        syncOneTabCleanModeUi();
                    }

                    @Override
                    public void onCrash(Tab tab) {
                        if (shouldTrackOneTabStartupMaskForTab(tab, null)) {
                            hideOneTabStartupMask("tab_crash");
                        }
                        syncOneTabCleanModeUi();
                    }
                };
    }

    private boolean shouldTrackOneTabStartupMaskForTab(@Nullable Tab tab, @Nullable GURL url) {
        if (!OneTabYouTubeMode.isEnabled()
                || !OTB_ENABLE_STARTUP_MASK
                || !mShowOneTabStartupMaskAfterColdLauncherStart) {
            return false;
        }

        if (tab == null || tab.isIncognito()) {
            return false;
        }

        Tab currentTab = getActivityTab();
        if (currentTab != null && currentTab.getId() != tab.getId()) {
            return false;
        }

        String urlSpec = url != null ? url.getSpec() : tab.getUrl().getSpec();
        return TextUtils.isEmpty(urlSpec) || OneTabYouTubeMode.isAllowedUrl(urlSpec);
    }

    private void maybeShowOneTabStartupMask() {
        if (!OneTabYouTubeMode.isEnabled()) {
            return;
        }

        if (!OTB_ENABLE_STARTUP_MASK) {
            hideOneTabStartupMask("disabled");
            return;
        }

        if (!mShowOneTabStartupMaskAfterColdLauncherStart) {
            return;
        }

        ViewGroup maskContainer = findViewById(R.id.compositor_view_holder);
        if (maskContainer == null) {
            maskContainer = findViewById(android.R.id.content);
        }
        if (maskContainer == null) {
            return;
        }

        if (mOneTabStartupMaskView != null
                && mOneTabStartupMaskView.getVisibility() == View.VISIBLE
                && mOneTabStartupMaskView.getParent() != null) {
            return;
        }

        if (mOneTabStartupMaskView == null) {
            FrameLayout mask = new FrameLayout(this);
            mask.setClickable(true);
            mask.setBackgroundColor(Color.BLACK);
            mask.setContentDescription("GO_PLAY startup");

            ImageView logoView = new ImageView(this);
            logoView.setTag(OTB_STARTUP_MASK_TAG_LOGO);
            logoView.setImageResource(R.drawable.onetab_fab_logo);
            logoView.setAdjustViewBounds(true);
            logoView.setScaleType(ImageView.ScaleType.FIT_CENTER);
            logoView.setAlpha(1.00f);
            FrameLayout.LayoutParams logoParams =
                    new FrameLayout.LayoutParams(dp(180), dp(180));
            logoParams.gravity = Gravity.CENTER;
            mask.addView(logoView, logoParams);

            mOneTabStartupMaskView = mask;
        }

        if (mOneTabStartupMaskView.getParent() == null) {
            maskContainer.addView(
                    mOneTabStartupMaskView,
                    new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT));
        }
        mOneTabStartupMaskView.setVisibility(View.VISIBLE);
        mOneTabStartupMaskView.bringToFront();
        mOneTabStartupMaskView.setTranslationZ(dp(40));
        mOneTabStartupMaskView.setElevation(dp(40));
        startOneTabStartupMaskAnimations();
        Log.i(OTB_PERF_TAG, "event=startup_mask show=1");
        getWindow().getDecorView().removeCallbacks(mHideOneTabStartupMaskRunnable);
        getWindow()
                .getDecorView()
                .postDelayed(mHideOneTabStartupMaskRunnable, OTB_STARTUP_MASK_TIMEOUT_MS);
    }

    private void hideOneTabStartupMask(String reason) {
        View decorView = getWindow().getDecorView();
        decorView.removeCallbacks(mHideOneTabStartupMaskRunnable);
        mShowOneTabStartupMaskAfterColdLauncherStart = false;

        if (mOneTabStartupMaskView != null && mOneTabStartupMaskView.getVisibility() != View.GONE) {
            stopOneTabStartupMaskAnimations();
            Log.i(OTB_PERF_TAG, "event=startup_mask hide_reason=%s", reason);
            mOneTabStartupMaskView.setVisibility(View.GONE);
        }
    }

    private void startOneTabStartupMaskAnimations() {
        stopOneTabStartupMaskAnimations();
    }

    private void stopOneTabStartupMaskAnimations() {
    }

    /**
     * Called when the application state changes. Similar to ChromeActivitySessionTracker, this
     * detects when the foreground session ends (when all activities are stopped).
     */
    private void onApplicationStateChange(@ApplicationState int newState) {
        if (newState == ApplicationState.HAS_STOPPED_ACTIVITIES) {
            onForegroundSessionEnds();
        }
    }

    /**
     * Marks that the foreground session ends has been triggered. Called when the activity
     * initializes state or when the foreground session ends.
     */
    private void setForegroundSessionEndsTriggered() {
        // Note that the preference is reset to false when the app is foregrounded inside
        // BraveReturnToChromeUtil.shouldShowNtpAsHomeSurfaceAtStartup() in case of always
        // New Tab option is selected.
        ChromeSharedPreferences.getInstance()
                .writeBoolean(BravePreferenceKeys.BRAVE_FOREGROUND_SESSION_ENDS_TRIGGERED, true);
    }

    /**
     * Called when the foreground session ends (when all activities are stopped). Similar to
     * ChromeActivitySessionTracker#onForegroundSessionEnd().
     */
    protected void onForegroundSessionEnds() {
        setForegroundSessionEndsTriggered();
    }

    @Override
    protected void initializeStartupMetrics() {
        super.initializeStartupMetrics();

        // Disable FRE for arm64 builds where ChromeActivity is the one that
        // triggers FRE instead of ChromeLauncherActivity on arm32 build.
        BraveHelper.disableFREDRP();
    }

    @Override
    public void onPreferenceChange() {
        String captchaID =
                UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getString(BravePref.SCHEDULED_CAPTCHA_ID);
        String paymentID =
                UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getString(BravePref.SCHEDULED_CAPTCHA_PAYMENT_ID);
        if (BraveQAPreferences.shouldVlogRewards()) {
            Log.e(
                    AdaptiveCaptchaHelper.TAG,
                    "captchaID : " + captchaID + " Payment ID : " + paymentID);
        }
        maybeSolveAdaptiveCaptcha();
    }

    @Override
    public void turnSafeBrowsingOff() {
        SafeBrowsingBridge safeBrowsingBridge = new SafeBrowsingBridge(getCurrentProfile());
        safeBrowsingBridge.setSafeBrowsingState(SafeBrowsingState.NO_SAFE_BROWSING);
    }

    // Shows SafeBrowsing errors if the switch in Developer Options is on
    @Override
    public void maybeShowSafeBrowsingError(String error) {
        if (ChromeSharedPreferences.getInstance()
                .readBoolean(BravePreferenceKeys.BRAVE_SAFE_BROWSING_ERRORS, false)) {
            Toast.makeText(BraveActivity.this, error, Toast.LENGTH_LONG).show();
        }
    }

    @Override
    public boolean isSafeBrowsingEnabled() {
        return mSafeBrowsingFlagEnabled;
    }

    @Override
    public Activity getActivity() {
        return this;
    }

    public void maybeSolveAdaptiveCaptcha() {
        String captchaID =
                UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getString(BravePref.SCHEDULED_CAPTCHA_ID);
        String paymentID =
                UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getString(BravePref.SCHEDULED_CAPTCHA_PAYMENT_ID);
        if (!TextUtils.isEmpty(captchaID) && !TextUtils.isEmpty(paymentID)) {
            AdaptiveCaptchaHelper.startAttestation(captchaID, paymentID);
        }
    }

    @Override
    public void finishNativeInitialization() {
        super.finishNativeInitialization();

        boolean isFirstInstall = PackageUtils.isFirstInstall(this);
        boolean oneTabEnabled = OneTabYouTubeMode.isEnabled();

        String countryCode = Locale.getDefault().getCountry();

        Profile profile = mTabModelProfileSupplier.get();
        if (oneTabEnabled) {
            maybeScheduleOneTabDeferredEntitlementInit();
        } else {
            BraveVpnNativeWorker.getInstance().reloadPurchasedState();

            // Restore Origin purchase from Google Play if the local pref is not set
            // (e.g. after device change). This ensures prefs are populated before the user
            // taps the Origin menu.
            if (profile != null
                    && ChromeFeatureList.isEnabled(BraveFeatureList.BRAVE_ORIGIN)
                    && !BraveOriginSubscriptionPrefs.getIsSubscriptionActive(profile)) {
                BraveOriginSubscriptionPrefs.verifyPurchase(profile);
            }
        }

        BraveHelper.maybeMigrateSettings();

        PrefChangeRegistrar mPrefChangeRegistrar = PrefServiceUtil.createFor(getCurrentProfile());
        mPrefChangeRegistrar.addObserver(BravePref.SCHEDULED_CAPTCHA_ID, this);
        syncScheduledCaptchaPausedState();
        maybeRunScheduledCaptchaStartupWork();

        if (ChromeSharedPreferences.getInstance()
                .readBoolean(BravePreferenceKeys.BRAVE_DOUBLE_RESTART, false)) {
            ChromeSharedPreferences.getInstance()
                    .writeBoolean(BravePreferenceKeys.BRAVE_DOUBLE_RESTART, false);
            BraveRelaunchUtils.restart();
            return;
        }

        // OneTabTube is intentionally constrained to a single YouTube surface,
        // so the more aggressive Chromium preloading mode is a reasonable
        // trade-off for smoother watch-page transitions.
        @PreloadPagesState
        int desiredPreloadState =
                oneTabEnabled
                        ? PreloadPagesState.EXTENDED_PRELOADING
                        : PreloadPagesState.NO_PRELOADING;
        if (PreloadPagesSettingsBridge.getState(getCurrentProfile()) != desiredPreloadState) {
            PreloadPagesSettingsBridge.setState(getCurrentProfile(), desiredPreloadState);
        }

        if (!oneTabEnabled && BraveRewardsHelper.hasRewardsEnvChange()) {
            BravePrefServiceBridge.getInstance().resetPromotionLastFetchStamp();
            BraveRewardsHelper.setRewardsEnvChange(false);
        }

        int appOpenCount =
                ChromeSharedPreferences.getInstance()
                        .readInt(BravePreferenceKeys.BRAVE_APP_OPEN_COUNT);
        ChromeSharedPreferences.getInstance()
                .writeInt(BravePreferenceKeys.BRAVE_APP_OPEN_COUNT, appOpenCount + 1);

        if (!oneTabEnabled && isFirstInstall && appOpenCount == 0) {
            checkForYandexSE();
            enableSearchSuggestions();
            setBraveAsDefaultPrivateMode();
        }

        if (!oneTabEnabled
                && !isFirstInstall
                && countryCode.equals(BraveConstants.JAPAN_COUNTRY_CODE)
                && !ChromeSharedPreferences.getInstance()
                        .readBoolean(
                                BravePreferenceKeys.BRAVE_DEFAULT_SEARCH_ENGINE_MIGRATED_JP,
                                false)) {
            applyChangesForYahooJp();
        }

        if (!oneTabEnabled) {
            BraveSetDefaultBrowserUtils.checkForBraveSetDefaultBrowser(
                    appOpenCount, BraveActivity.this);
        }

        Context app = ContextUtils.getApplicationContext();
        if (!oneTabEnabled
                && null != app
                && BraveReflectionUtil.equalTypes(this.getClass(), ChromeTabbedActivity.class)) {
            // Trigger BraveSyncWorker CTOR to make migration from sync v1 if sync is enabled
            BraveSyncWorker.get();
        }

        if (!oneTabEnabled) {
            initMiscAndroidMetrics();
            checkForNotificationData();

            if (RateUtils.getInstance().isLastSessionShown()) {
                RateUtils.getInstance().setPrefNextRateDate();
                RateUtils.getInstance().setLastSessionShown(false);
            }

            if (!RateUtils.getInstance().getPrefRateEnabled()) {
                RateUtils.getInstance().setPrefRateEnabled(true);
                RateUtils.getInstance().setPrefNextRateDate();
            }
            RateUtils.getInstance().setTodayDate();

            if (!BraveConfig.IS_ONETABYT && RateUtils.getInstance().shouldShowRateDialog(this)) {
                showBraveRateDialog();
                RateUtils.getInstance().setLastSessionShown(true);
            }
        }

        // TODO commenting out below code as we may use it in next release

        // if (PackageUtils.isFirstInstall(this)
        //         &&
        //
        // SharedPreferencesManager.getInstance().readInt(BravePreferenceKeys.BRAVE_APP_OPEN_COUNT)
        //         == 1) {
        //     Calendar calender = Calendar.getInstance();
        //     calender.setTime(new Date());
        //     calender.add(Calendar.DATE, DAYS_4);
        //     OnboardingPrefManager.getInstance().setNextOnboardingDate(
        //         calender.getTimeInMillis());
        // }

        // OnboardingActivity onboardingActivity = null;
        // for (Activity ref : ApplicationStatus.getRunningActivities()) {
        //     if (!(ref instanceof OnboardingActivity)) continue;

        //     onboardingActivity = (OnboardingActivity) ref;
        // }

        // if (onboardingActivity == null
        //         && OnboardingPrefManager.getInstance().showOnboardingForSkip(this)) {
        //     OnboardingPrefManager.getInstance().showOnboarding(this);
        //     OnboardingPrefManager.getInstance().setOnboardingShownForSkip(true);
        // }

        if (!oneTabEnabled) {
            BraveSyncAccountDeletedInformer.show();

            if (!OnboardingPrefManager.getInstance().isOneTimeNotificationStarted()
                    && isFirstInstall) {
                RetentionNotificationUtil.scheduleNotification(
                        this, RetentionNotificationUtil.HOUR_3);
                RetentionNotificationUtil.scheduleNotification(
                        this, RetentionNotificationUtil.HOUR_24);
                RetentionNotificationUtil.scheduleNotification(
                        this, RetentionNotificationUtil.DAY_6);
                RetentionNotificationUtil.scheduleNotification(
                        this, RetentionNotificationUtil.DAY_10);
                RetentionNotificationUtil.scheduleNotification(
                        this, RetentionNotificationUtil.DAY_30);
                RetentionNotificationUtil.scheduleNotification(
                        this, RetentionNotificationUtil.DAY_35);
                OnboardingPrefManager.getInstance().setOneTimeNotificationStarted(true);
            }

            if (isFirstInstall
                    && ChromeSharedPreferences.getInstance()
                                    .readInt(BravePreferenceKeys.BRAVE_APP_OPEN_COUNT)
                            == 1) {
                Calendar calender = Calendar.getInstance();
                calender.setTime(new Date());
                calender.add(Calendar.DATE, DAYS_4);
                BraveRewardsHelper.setNextRewardsOnboardingModalDate(calender.getTimeInMillis());
            }

            checkFingerPrintingOnUpgrade(isFirstInstall);
            checkForVpnCallout();

            if (ChromeFeatureList.isEnabled(BraveFeatureList.BRAVE_VPN_LINK_SUBSCRIPTION_ANDROID_UI)
                    && BraveVpnPrefUtils.isSubscriptionPurchase()
                    && !BraveVpnPrefUtils.isLinkSubscriptionDialogShown()) {
                showLinkVpnSubscriptionDialog();
            }
            if (isFirstInstall
                    && (OnboardingPrefManager.getInstance().isDormantUsersEngagementEnabled()
                            || getPackageName().equals(
                                    BraveConstants.BRAVE_PRODUCTION_PACKAGE_NAME))) {
                OnboardingPrefManager.getInstance().setDormantUsersPrefs();
                if (!OnboardingPrefManager.getInstance().isDormantUsersNotificationsStarted()) {
                    RetentionNotificationUtil.scheduleDormantUsersNotifications(this);
                    OnboardingPrefManager.getInstance().setDormantUsersNotificationsStarted(true);
                }
            }
            initWalletNativeServices();
        }

        mNativeInitialized = true;

        if (!oneTabEnabled) {
            if (countryCode.equals(BraveConstants.INDIA_COUNTRY_CODE)
                    && ChromeSharedPreferences.getInstance()
                            .readBoolean(BravePreferenceKeys.BRAVE_AD_FREE_CALLOUT_DIALOG, true)
                    && getActivityTab() != null
                    && getActivityTab().getUrl().getSpec() != null
                    && UrlUtilities.isNtpUrl(getActivityTab().getUrl().getSpec())
                    && (ChromeSharedPreferences.getInstance()
                                    .readBoolean(
                                            BravePreferenceKeys.BRAVE_OPENED_YOUTUBE, false)
                            || ChromeSharedPreferences.getInstance()
                                            .readInt(BravePreferenceKeys.BRAVE_APP_OPEN_COUNT)
                                    >= 7)) {
                showAdFreeCalloutDialog();
            }

            initBraveNews();
            if (ChromeSharedPreferences.getInstance()
                    .readBoolean(BravePreferenceKeys.BRAVE_DEFERRED_DEEPLINK_PLAYLIST, false)) {
                ChromeSharedPreferences.getInstance()
                        .writeBoolean(BravePreferenceKeys.BRAVE_DEFERRED_DEEPLINK_PLAYLIST, false);
                openPlaylist(false);
            } else if (ChromeSharedPreferences.getInstance()
                    .readBoolean(BravePreferenceKeys.BRAVE_DEFERRED_DEEPLINK_VPN, false)) {
                ChromeSharedPreferences.getInstance()
                        .writeBoolean(BravePreferenceKeys.BRAVE_DEFERRED_DEEPLINK_VPN, false);
                handleDeepLinkVpn();
            }
        }

        // Added to reset app links settings for upgrade case
        if (!isFirstInstall
                && !ChromeSharedPreferences.getInstance()
                        .readBoolean(BravePrivacySettings.PREF_APP_LINKS, true)
                && ChromeSharedPreferences.getInstance()
                        .readBoolean(BravePrivacySettings.PREF_APP_LINKS_RESET, true)) {
            ChromeSharedPreferences.getInstance()
                    .writeBoolean(BravePrivacySettings.PREF_APP_LINKS, true);
            ChromeSharedPreferences.getInstance()
                    .writeBoolean(BravePrivacySettings.PREF_APP_LINKS_RESET, false);
        }

        if (isFirstInstall
                && ChromeSharedPreferences.getInstance()
                                .readInt(BravePreferenceKeys.BRAVE_APP_OPEN_COUNT)
                        == 1) {
            Calendar calendar = Calendar.getInstance();
            calendar.setTime(new Date());
            calendar.add(Calendar.DATE, DAYS_7);
            BraveRewardsHelper.setRewardsOnboardingIconTiming(calendar.getTimeInMillis());

            if (!BraveConfig.IS_ONETABYT) {
                setInAppUpdateTiming();
            }
        }

        // Check multiwindow toggle for upgrade case
        if (!isFirstInstall
                && !BraveMultiWindowUtils.isCheckUpgradeEnableMultiWindows()
                && MultiWindowUtils.getInstanceCountWithFallback(PersistedInstanceType.ACTIVE) > 1
                && !BraveMultiWindowUtils.shouldEnableMultiWindows()) {
            BraveMultiWindowUtils.setCheckUpgradeEnableMultiWindows(true);
            BraveMultiWindowUtils.updateEnableMultiWindows(true);
        } else if (!BraveMultiWindowUtils.isCheckUpgradeEnableMultiWindows()) {
            BraveMultiWindowUtils.setCheckUpgradeEnableMultiWindows(true);
        }

        if (!BraveConfig.IS_ONETABYT
                && System.currentTimeMillis()
                        > ChromeSharedPreferences.getInstance()
                                .readLong(BravePreferenceKeys.BRAVE_IN_APP_UPDATE_TIMING, 0)) {
            checkAppUpdate();
        }

        if (!isFirstInstall
                && !BravePrefServiceBridge.getInstance().getPlayYTVideoInBrowserEnabled()
                && ChromeSharedPreferences.getInstance()
                        .readBoolean(BravePreferenceKeys.OPEN_YT_IN_BRAVE_DIALOG, true)) {
            openYtInBraveDialog();
            ChromeSharedPreferences.getInstance()
                    .writeBoolean(BravePreferenceKeys.OPEN_YT_IN_BRAVE_DIALOG, false);
        }

        // Quick search engines views changes
        new KeyboardVisibilityHelper(BraveActivity.this, BraveActivity.this);
        AppCompatEditText urlBar = findViewById(R.id.url_bar);
        if (urlBar != null) {
            urlBar.addTextChangedListener(
                    new TextWatcher() {
                        @Override
                        public void beforeTextChanged(
                                CharSequence s, int start, int count, int after) {}

                        @Override
                        public void onTextChanged(
                                CharSequence query, int start, int before, int count) {
                            if (query.toString().isEmpty()) {
                                removeQuickActionSearchEnginesView();
                            } else {
                                if (getBraveToolbarLayout().isUrlBarFocused()
                                        && KeyboardUtils.isAndroidSoftKeyboardShowing(urlBar)) {
                                    View rootView = findViewById(android.R.id.content);
                                    Rect r = new Rect();
                                    rootView.getWindowVisibleDisplayFrame(r);
                                    int screenHeight = rootView.getRootView().getHeight();
                                    int visibleHeight = r.bottom;
                                    int heightDifference = screenHeight - visibleHeight;
                                    showQuickActionSearchEnginesView(heightDifference);
                                } else {
                                    removeQuickActionSearchEnginesView();
                                }
                            }
                        }

                        @Override
                        public void afterTextChanged(Editable s) {}
                    });
            if (ChromeSharedPreferences.getInstance()
                    .readBoolean(OnboardingPrefManager.SHOULD_SHOW_SEARCH_WIDGET_PROMO, false)) {
                mSearchWidgetPromoPanel = new SearchWidgetPromoPanel();
                showWidgetPromoPanel();
                ChromeSharedPreferences.getInstance()
                        .writeBoolean(OnboardingPrefManager.SHOULD_SHOW_SEARCH_WIDGET_PROMO, false);
            }
        }

        ContextUtils.getAppSharedPreferences().registerOnSharedPreferenceChangeListener(this);
    }

    private void applyChangesForYahooJp() {
        boolean isDefaultSearchEngineChanged =
                ChromeSharedPreferences.getInstance()
                        .readBoolean(BravePreferenceKeys.DEFAULT_SEARCH_ENGINE_CHANGED, false);
        TemplateUrlService templateUrlService =
                TemplateUrlServiceFactory.getForProfile(getCurrentProfile());
        Runnable onTemplateUrlServiceReady =
                () -> {
                    if (ChromeSharedPreferences.getInstance()
                            .readBoolean(BravePreferenceKeys.SEARCH_CHOICE_SCREEN_INSTALL, false)) {
                        // If the install originated from the Search Choice Screen, keep Brave as
                        // default
                        return;
                    }
                    if (isActivityFinishingOrDestroyed()) return;
                    TemplateUrl yahooJpTemplateUrl =
                            BraveSearchEngineUtils.getTemplateUrlByShortName(
                                    getCurrentProfile(), OnboardingPrefManager.YAHOO_JP);
                    if (yahooJpTemplateUrl != null
                            && !isDefaultSearchEngineChanged
                            && templateUrlService.isDefaultSearchEngineGoogle()) {
                        BraveSearchEngineUtils.setDSEPrefs(yahooJpTemplateUrl, getCurrentProfile());
                        ChromeSharedPreferences.getInstance()
                                .writeBoolean(
                                        BravePreferenceKeys.BRAVE_DEFAULT_SEARCH_ENGINE_MIGRATED_JP,
                                        true);
                    }
                };
        templateUrlService.runWhenLoaded(onTemplateUrlServiceReady);
    }

    private void setBraveAsDefaultPrivateMode() {
        if (!IncognitoUtils.isIncognitoModeEnabled(getCurrentProfile())) {
            return;
        }

        Runnable onTemplateUrlServiceReady =
                () -> {
                    if (isActivityFinishingOrDestroyed()) return;
                    TemplateUrl braveTemplateUrl =
                            BraveSearchEngineUtils.getTemplateUrlByShortName(
                                    getCurrentProfile(), OnboardingPrefManager.BRAVE);
                    if (braveTemplateUrl != null) {
                        BraveSearchEngineUtils.setDSEPrefs(
                                braveTemplateUrl,
                                getCurrentProfile()
                                        .getPrimaryOtrProfile(/* createIfNeeded= */ true));
                    }
                };
        TemplateUrlServiceFactory.getForProfile(getCurrentProfile())
                .runWhenLoaded(onTemplateUrlServiceReady);
    }

    private void enableSearchSuggestions() {
        TemplateUrl defaultSearchEngineTemplateUrl =
                BraveSearchEngineUtils.getTemplateUrlByShortName(
                        getCurrentProfile(),
                        BraveSearchEngineUtils.getDSEShortName(getCurrentProfile(), false));
        if (defaultSearchEngineTemplateUrl != null
                && BRAVE_SEARCH_ENGINE_KEYWORD.equals(
                        defaultSearchEngineTemplateUrl.getKeyword())) {
            UserPrefs.get(getCurrentProfile()).setBoolean(Pref.SEARCH_SUGGEST_ENABLED, true);
        }
    }

    private void setInAppUpdateTiming() {
        if (BraveConfig.IS_ONETABYT) {
            return;
        }
        Calendar calendar = Calendar.getInstance();
        calendar.setTime(new Date());
        calendar.add(Calendar.MONTH, MONTH_1);
        ChromeSharedPreferences.getInstance()
                .writeLong(
                        BravePreferenceKeys.BRAVE_IN_APP_UPDATE_TIMING, calendar.getTimeInMillis());
    }

    private void completeUpdateSnackbar() {
        if (BraveConfig.IS_ONETABYT) {
            return;
        }
        Snackbar snackbar =
                Snackbar.make(
                                getResources().getString(R.string.in_app_update_text),
                                new SnackbarController() {
                                    @Override
                                    public void onDismissNoAction(Object actionData) {}

                                    @Override
                                    public void onAction(Object actionData) {
                                        if (mAppUpdateManager != null) {
                                            mAppUpdateManager.completeUpdate();
                                            mAppUpdateManager.unregisterListener(
                                                    mInstallStateUpdatedListener);
                                        }
                                    }
                                },
                                Snackbar.TYPE_ACTION,
                                Snackbar.UMA_UNKNOWN)
                        .setAction(getResources().getString(R.string.update), null)
                        .setDefaultLines(false)
                        .setDuration(10000);
        Tab currentTab = getActivityTabProvider().get();
        if (currentTab != null) {
            SnackbarManager snackbarManager =
                    SnackbarManagerProvider.from(currentTab.getWindowAndroid());
            snackbarManager.showSnackbar(snackbar);
        }
    }

    private final InstallStateUpdatedListener mInstallStateUpdatedListener =
            installState -> {
                if (installState.installStatus() == InstallStatus.DOWNLOADED) {
                    completeUpdateSnackbar();
                }
            };

    private void checkAppUpdate() {
        if (BraveConfig.IS_ONETABYT) {
            return;
        }
        mAppUpdateManager = AppUpdateManagerFactory.create(BraveActivity.this);
        mAppUpdateManager.registerListener(mInstallStateUpdatedListener);

        Task<AppUpdateInfo> appUpdateInfoTask = mAppUpdateManager.getAppUpdateInfo();

        appUpdateInfoTask.addOnSuccessListener(
                appUpdateInfo -> {
                    if (appUpdateInfo.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE) {
                        if (appUpdateInfo.updatePriority() >= 4 /* high priority */
                                && appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                            startAppUpdateFlow(appUpdateInfo, AppUpdateType.IMMEDIATE);
                        } else {
                            startAppUpdateFlow(appUpdateInfo, AppUpdateType.FLEXIBLE);
                        }
                    }
                });
    }

    private void startAppUpdateFlow(AppUpdateInfo appUpdateInfo, int appUpdateType) {
        if (BraveConfig.IS_ONETABYT) {
            return;
        }
        try {
            mAppUpdateManager.startUpdateFlowForResult(
                    appUpdateInfo, appUpdateType, BraveActivity.this, 1);
            setInAppUpdateTiming();
        } catch (IntentSender.SendIntentException e) {
            throw new RuntimeException(e);
        }
    }

    private void handleDeepLinkVpn() {
        mIsDeepLink = true;
        BraveVpnUtils.openBraveVpnPlansActivity(this);
    }

    private void checkForVpnCallout() {
        String countryCode = Locale.getDefault().getCountry();

        if (!countryCode.equals(BraveConstants.INDIA_COUNTRY_CODE)
                && BraveVpnUtils.isVpnFeatureSupported(BraveActivity.this)) {
            if (!TextUtils.isEmpty(BraveVpnPrefUtils.getPurchaseToken())
                    && !TextUtils.isEmpty(BraveVpnPrefUtils.getProductId())) {
                mIsVerification = true;
                BraveVpnNativeWorker.getInstance().verifyPurchaseToken(
                        BraveVpnPrefUtils.getPurchaseToken(), BraveVpnPrefUtils.getProductId(),
                        BraveVpnUtils.SUBSCRIPTION_PARAM_TEXT, getPackageName());
            }
        }
    }

    private void initBraveNews() {
        ThreadUtils.assertOnUiThread();
        if (OneTabYouTubeMode.isEnabled()) {
            return;
        }
        if (BravePrefServiceBridge.getInstance().getShowNews()
                && BravePrefServiceBridge.getInstance().getNewsOptIn()) {
            BraveNewsUtils.getBraveNewsSettingsDataPerProfile(mTabModelProfileSupplier.get());
        }
    }

    public void setDormantUsersPrefs() {
        OnboardingPrefManager.getInstance().setDormantUsersPrefs();
        RetentionNotificationUtil.scheduleDormantUsersNotifications(this);
    }

    private void openPlaylist(boolean shouldHandlePlaylistActivity) {
        if (!shouldHandlePlaylistActivity) mIsDeepLink = true;

        if (ChromeSharedPreferences.getInstance()
                .readBoolean(PlaylistPreferenceUtils.SHOULD_SHOW_PLAYLIST_ONBOARDING, true)) {
            PlaylistUtils.openPlaylistMenuOnboardingActivity(BraveActivity.this);
            ChromeSharedPreferences.getInstance()
                    .writeBoolean(PlaylistPreferenceUtils.SHOULD_SHOW_PLAYLIST_ONBOARDING, false);
        } else if (shouldHandlePlaylistActivity) {
            openPlaylistActivity(BraveActivity.this, ConstantUtils.ALL_PLAYLIST);
        }
    }

    public void openPlaylistActivity(Context context, String playlistId) {
        if (OneTabYouTubeMode.isEnabled()) {
            return;
        }

        Intent playlistActivityIntent = new Intent();
        playlistActivityIntent.setClassName(
                context, "org.chromium.chrome.browser.playlist.PlaylistHostActivity");
        playlistActivityIntent.putExtra(ConstantUtils.PLAYLIST_ID, playlistId);
        playlistActivityIntent.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        playlistActivityIntent.setAction(Intent.ACTION_VIEW);
        if (playlistActivityIntent.resolveActivity(context.getPackageManager()) != null) {
            context.startActivity(playlistActivityIntent);
        }
    }

    private void showLinkVpnSubscriptionDialog() {
        LinkVpnSubscriptionDialogFragment linkVpnSubscriptionDialogFragment =
                new LinkVpnSubscriptionDialogFragment();
        linkVpnSubscriptionDialogFragment.setCancelable(false);
        linkVpnSubscriptionDialogFragment.show(
                getSupportFragmentManager(), "LinkVpnSubscriptionDialogFragment");
    }

    private void showAdFreeCalloutDialog() {
        ChromeSharedPreferences.getInstance()
                .writeBoolean(BravePreferenceKeys.BRAVE_AD_FREE_CALLOUT_DIALOG, false);

        BraveAdFreeCalloutDialogFragment braveAdFreeCalloutDialogFragment =
                new BraveAdFreeCalloutDialogFragment();
        braveAdFreeCalloutDialogFragment.show(
                getSupportFragmentManager(), "BraveAdFreeCalloutDialogFragment");
    }

    public void setNewTabPageManager(NewTabPageManager manager) {
        mNewTabPageManager = manager;
    }

    public void focusSearchBox() {
        if (mNewTabPageManager != null) {
            mNewTabPageManager.focusSearchBox(false, AutocompleteRequestType.SEARCH, null);
        }
    }

    private void checkFingerPrintingOnUpgrade(boolean isFirstInstall) {
        if (!isFirstInstall
                && ChromeSharedPreferences.getInstance()
                                .readInt(BravePreferenceKeys.BRAVE_APP_OPEN_COUNT)
                        == 0) {
            boolean value =
                    ChromeSharedPreferences.getInstance()
                            .readBoolean(BravePrivacySettings.PREF_FINGERPRINTING_PROTECTION, true);
            if (value) {
                BraveShieldsContentSettings.setShieldsValue(
                        ProfileManager.getLastUsedRegularProfile(),
                        "",
                        BraveShieldsContentSettings.RESOURCE_IDENTIFIER_FINGERPRINTING,
                        BraveShieldsContentSettings.DEFAULT,
                        false);
            } else {
                BraveShieldsContentSettings.setShieldsValue(
                        ProfileManager.getLastUsedRegularProfile(),
                        "",
                        BraveShieldsContentSettings.RESOURCE_IDENTIFIER_FINGERPRINTING,
                        BraveShieldsContentSettings.ALLOW_RESOURCE,
                        false);
            }
        }
    }

    public void openQuickSearchEnginesSettings() {
        SettingsNavigation settingsLauncher = SettingsNavigationFactory.createSettingsNavigation();
        settingsLauncher.startSettings(this, QuickSearchEnginesFragment.class);
    }

    public void openBravePlaylistSettings() {
        if (BraveConfig.IS_ONETABYT) {
            return;
        }
        if (OneTabYouTubeMode.isEnabled()) {
            return;
        }

        SettingsNavigation settingsLauncher = SettingsNavigationFactory.createSettingsNavigation();
        try {
            @SuppressWarnings("unchecked")
            Class<? extends Fragment> playlistSettingsClass =
                    (Class<? extends Fragment>)
                            Class.forName(
                                    "org.chromium.chrome.browser.playlist.settings.BravePlaylistPreferences");
            settingsLauncher.startSettings(this, playlistSettingsClass);
        } catch (ClassNotFoundException e) {
            Log.w("BraveActivity", "Playlist settings class unavailable: %s", e.getMessage());
        }
    }

    public void openBraveNewsSettings() {
        SettingsNavigation settingsLauncher = SettingsNavigationFactory.createSettingsNavigation();
        settingsLauncher.startSettings(this, BraveNewsPreferencesV2.class);
    }

    public void openBraveContentFilteringSettings() {
        SettingsNavigation settingsLauncher = SettingsNavigationFactory.createSettingsNavigation();
        settingsLauncher.startSettings(this, ContentFilteringFragment.class);
    }

    public int getBraveThemeBackgroundColor() {
        return ContextUtils.getApplicationContext()
                .getColor(R.color.toolbar_background_color_for_ntp);
    }

    public void openBraveCreateCustomFiltersSettings() {
        SettingsNavigation settingsLauncher = SettingsNavigationFactory.createSettingsNavigation();
        settingsLauncher.startSettings(this, CreateCustomFiltersFragment.class);
    }

    public void openBraveWalletSettings() {
        SettingsNavigation settingsLauncher = SettingsNavigationFactory.createSettingsNavigation();
        settingsLauncher.startSettings(this, BraveWalletPreferences.class);
    }

    public void openBraveConnectedSitesSettings() {
        SettingsNavigation settingsLauncher = SettingsNavigationFactory.createSettingsNavigation();
        try {
            Class<?> fragmentClass =
                    Class.forName(
                            "org.chromium.chrome.browser.site_settings"
                                    + ".BraveWalletEthereumConnectedSites");
            if (Fragment.class.isAssignableFrom(fragmentClass)) {
                settingsLauncher.startSettings(this, fragmentClass.asSubclass(Fragment.class));
                return;
            }
        } catch (ClassNotFoundException e) {
            Log.e("BraveActivity", "openBraveConnectedSitesSettings", e);
        }
        settingsLauncher.startSettings(this, BraveWalletPreferences.class);
    }

    public void openBraveWallet(boolean fromDapp, boolean setupAction, boolean restoreAction) {
        Intent braveWalletIntent = new Intent(this, BraveWalletActivity.class);
        braveWalletIntent.putExtra(BraveWalletActivity.IS_FROM_DAPPS, fromDapp);
        braveWalletIntent.putExtra(BraveWalletActivity.RESTART_WALLET_ACTIVITY_SETUP, setupAction);
        braveWalletIntent.putExtra(
                BraveWalletActivity.RESTART_WALLET_ACTIVITY_RESTORE, restoreAction);
        braveWalletIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        braveWalletIntent.setAction(Intent.ACTION_VIEW);
        startActivity(braveWalletIntent);
    }

    public void openBraveWalletBackup() {
        Intent braveWalletIntent = new Intent(this, BraveWalletActivity.class);
        braveWalletIntent.putExtra(BraveWalletActivity.SHOW_WALLET_ACTIVITY_BACKUP, true);
        braveWalletIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        braveWalletIntent.setAction(Intent.ACTION_VIEW);
        startActivity(braveWalletIntent);
    }

    public void viewOnBlockExplorer(
            String address, @CoinType.EnumType int coinType, NetworkInfo networkInfo) {
        Utils.openAddress("/address/" + address, this, coinType, networkInfo);
    }

    public void openBraveWalletDAppsActivity(
            final BraveWalletDAppsActivity.ActivityType activityType) {
        final Intent braveWalletIntent = BraveWalletDAppsActivity.getIntent(this, activityType);
        startActivity(braveWalletIntent);
    }

    public MiscAndroidMetrics getMiscAndroidMetrics() {
        return mMiscAndroidMetrics;
    }

    private void checkForYandexSE() {
        if (ChromeSharedPreferences.getInstance()
                .readBoolean(BravePreferenceKeys.SEARCH_CHOICE_SCREEN_INSTALL, false)) {
            // If the install originated from the Search Choice Screen, keep Brave as default
            return;
        }
        String countryCode = Locale.getDefault().getCountry();
        if (sYandexRegions.contains(countryCode)) {
            Profile lastUsedRegularProfile = ProfileManager.getLastUsedRegularProfile();
            TemplateUrl yandexTemplateUrl =
                    BraveSearchEngineUtils.getTemplateUrlByShortName(
                            lastUsedRegularProfile, OnboardingPrefManager.YANDEX);
            if (yandexTemplateUrl != null) {
                BraveSearchEngineUtils.setDSEPrefs(yandexTemplateUrl, lastUsedRegularProfile);
            }
        }
    }

    private void checkForNotificationData() {
        Intent notifIntent = getIntent();
        if (notifIntent != null && notifIntent.getStringExtra(RetentionNotificationUtil.NOTIFICATION_TYPE) != null) {
            String notificationType = notifIntent.getStringExtra(RetentionNotificationUtil.NOTIFICATION_TYPE);
            switch (notificationType) {
                case RetentionNotificationUtil.HOUR_3:
                case RetentionNotificationUtil.HOUR_24:
                case RetentionNotificationUtil.EVERY_SUNDAY:
                    checkForBraveStats();
                    break;
                case RetentionNotificationUtil.DAY_6:
                    if (getActivityTab() != null
                            && getActivityTab().getUrl().getSpec() != null
                            && !UrlUtilities.isNtpUrl(getActivityTab().getUrl().getSpec())) {
                        getTabCreator(false).launchUrl(
                                UrlConstants.NTP_URL, TabLaunchType.FROM_CHROME_UI);
                    }
                    break;
                case RetentionNotificationUtil.DAY_10:
                case RetentionNotificationUtil.DAY_30:
                case RetentionNotificationUtil.DAY_35:
                    openRewardsPanel();
                    break;
                case RetentionNotificationUtil.DORMANT_USERS_DAY_14:
                case RetentionNotificationUtil.DORMANT_USERS_DAY_25:
                case RetentionNotificationUtil.DORMANT_USERS_DAY_40:
                    showDormantUsersEngagementDialog(notificationType);
                    break;
            }
        }
    }

    public void checkForBraveStats() {
        if (OnboardingPrefManager.getInstance().isBraveStatsEnabled()) {
            BraveStatsUtil.showBraveStats();
        } else {
            if (getActivityTab() != null
                    && getActivityTab().getUrl().getSpec() != null
                    && !UrlUtilities.isNtpUrl(getActivityTab().getUrl().getSpec())) {
                OnboardingPrefManager.getInstance().setFromNotification(true);
                if (getTabCreator(false) != null) {
                    getTabCreator(false).launchUrl(
                            UrlConstants.NTP_URL, TabLaunchType.FROM_CHROME_UI);
                }
            } else {
                showOnboardingV2(false);
            }
        }
    }

    public void showOnboardingV2(boolean fromStats) {
        try {
            OnboardingPrefManager.getInstance().setNewOnboardingShown(true);
            FragmentManager fm = getSupportFragmentManager();
            HighlightDialogFragment fragment = (HighlightDialogFragment) fm.findFragmentByTag(
                    HighlightDialogFragment.TAG_FRAGMENT);
            FragmentTransaction transaction = fm.beginTransaction();

            if (fragment != null) {
                transaction.remove(fragment);
            }

            fragment = new HighlightDialogFragment();
            Bundle fragmentBundle = new Bundle();
            fragmentBundle.putBoolean(OnboardingPrefManager.FROM_STATS, fromStats);
            fragment.setArguments(fragmentBundle);
            transaction.add(fragment, HighlightDialogFragment.TAG_FRAGMENT);
            transaction.commitAllowingStateLoss();
        } catch (IllegalStateException e) {
            Log.e("HighlightDialogFragment", e.getMessage());
        }
    }

    public void hideRewardsOnboardingIcon() {
        BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
        layout.hideRewardsOnboardingIcon();
    }

    private void createNotificationChannel() {
        // Create the NotificationChannel, but only on API 26+ because
        // the NotificationChannel class is new and not in the support library
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            int importance = NotificationManager.IMPORTANCE_DEFAULT;
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, getString(R.string.brave_browser), importance);
            channel.setDescription(
                    getString(R.string.brave_browser_notification_channel_description));
            // Register the channel with the system; you can't change the importance
            // or other notification behaviors after this
            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            notificationManager.createNotificationChannel(channel);
        }
    }

    private boolean isNoRestoreState() {
        return ChromeSharedPreferences.getInstance()
                .readBoolean(BravePreferenceKeys.BRAVE_CLOSE_TABS_ON_EXIT, false);
    }

    private boolean isClearBrowsingDataOnExit() {
        return ChromeSharedPreferences.getInstance()
                .readBoolean(BravePreferenceKeys.BRAVE_CLEAR_ON_EXIT, false);
    }

    public void dismissShieldsTooltip() {
        BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
        layout.dismissShieldsTooltip();
    }

    public void openRewardsPanel() {
        BraveToolbarLayoutImpl layout = getBraveToolbarLayout();
        layout.openRewardsPanel();
    }

    public Profile getCurrentProfile() {
        Tab tab = getActivityTab();
        if (tab == null) {
            return ProfileManager.getLastUsedRegularProfile();
        }

        return Profile.fromWebContents(tab.getWebContents());
    }

    /** Close all tabs (including active tab) whose URL origin matches with a given origin. */
    public void closeAllTabsByOrigin(@NonNull final String origin) {
        final TabModel tabModel = getCurrentTabModel();

        Set<Integer> tabIndexes = getTabIndexesByUrlOrigin(tabModel, origin);
        for (Integer index : tabIndexes) {
            Tab tab = tabModel.getTabAt(index);
            if (tab != null) {
                tab.setClosing(true);
                tabModel.getTabRemover().closeTabs(TabClosureParams.closeTab(tab).build(), false);
            }
        }
    }

    /**
     * Selects an existing tab if it matches a given origin, marks it as active and returns it.
     *
     * @return Active tab if it exists, {@code null} otherwise.
     */
    public Tab selectExistingUrlOriginTab(@NonNull final String origin) {
        TabModel tabModel = getCurrentTabModel();
        Set<Integer> tabIndexes = getTabIndexesByUrlOrigin(tabModel, origin);

        // Find if tab exists, including tab already active.
        if (!tabIndexes.isEmpty()) {
            int index = tabIndexes.iterator().next();
            Tab tab = tabModel.getTabAt(tabIndexes.iterator().next());
            // Set active tab
            tabModel.setIndex(index, TabSelectionType.FROM_USER);
            return tab;
        } else {
            return null;
        }
    }

    /**
     * Find the {@link Tab} indexes whose URL starts with the specified base URL.
     *
     * @param model The {@link TabModel} to act on.
     * @param origin The URL origin to search for.
     * @return A set of indexes pointing to the matching {@link Tab}s or empty set if no matches are
     *     found.
     */
    @NonNull
    private static Set<Integer> getTabIndexesByUrlOrigin(
            @NonNull final TabList model, @NonNull final String origin) {
        final Set<Integer> result = new HashSet<>();
        int count = model.getCount();

        for (int i = 0; i < count; i++) {
            if (model.getTabAt(i).getUrl().getOrigin().getSpec().contentEquals(origin)) {
                result.add(i);
            }
        }
        return result;
    }

    public Tab selectExistingTab(String url) {
        Tab tab = getActivityTab();
        if (tab != null && tab.getUrl().getSpec().equals(url)) {
            return tab;
        }

        TabModel tabModel = getCurrentTabModel();
        int tabIndex = TabModelUtils.getTabIndexByUrl(tabModel, url);

        // Find if tab exists
        if (tabIndex != TabModel.INVALID_TAB_INDEX) {
            tab = tabModel.getTabAt(tabIndex);
            // Set active tab
            tabModel.setIndex(tabIndex, TabSelectionType.FROM_USER);
            return tab;
        } else {
            return null;
        }
    }

    public Tab openNewOrSelectExistingTab(String url, boolean refresh) {
        if (OneTabYouTubeMode.isEnabled()) {
            return loadUrlInSingleTab(url, refresh);
        }

        Tab tab = selectExistingTab(url);
        if (tab != null) {
            if (refresh) {
                tab.reload();
            }
            return tab;
        } else { // Open a new tab
            return getTabCreator(false).launchUrl(url, TabLaunchType.FROM_CHROME_UI);
        }
    }

    public void openNewOrRefreshExistingTab(
            @NonNull final String origin, @NonNull final String url) {
        if (OneTabYouTubeMode.isEnabled()) {
            loadUrlInSingleTab(url, true);
            return;
        }

        Tab tab = selectExistingUrlOriginTab(origin);
        if (tab != null) {
            tab.reload();
        } else {
            // Open a new tab.
            getTabCreator(false).launchUrl(url, TabLaunchType.FROM_CHROME_UI);
        }
    }

    public Tab openNewOrSelectExistingTab(String url) {
        return openNewOrSelectExistingTab(url, false);
    }

    private Tab loadUrlInSingleTab(String url, boolean refresh) {
        String allowedUrl = OneTabYouTubeMode.toAllowedOrFallback(url);
        Tab currentTab = getActivityTab();
        if (currentTab != null && !currentTab.isIncognito()) {
            if (refresh && allowedUrl.equals(currentTab.getUrl().getSpec())) {
                currentTab.reload();
            } else {
                currentTab.loadUrl(new LoadUrlParams(allowedUrl));
            }
            return currentTab;
        }

        return getTabCreator(false).launchUrl(allowedUrl, TabLaunchType.FROM_CHROME_UI);
    }

    private void closeIncognitoTabsForOneTabMode(@Nullable TabModelSelector selector) {
        if (selector == null) {
            return;
        }

        closeAllTabsInModel(selector.getModel(true));
    }

    private void closeAllTabsInModel(@Nullable TabModel tabModel) {
        if (tabModel == null) {
            return;
        }

        for (int i = tabModel.getCount() - 1; i >= 0; i--) {
            Tab tab = tabModel.getTabAt(i);
            if (tab == null) {
                continue;
            }
            tab.setClosing(true);
            tabModel.getTabRemover()
                    .closeTabs(TabClosureParams.closeTab(tab).allowUndo(false).build(), false);
        }
    }

    @Nullable
    private Tab getOneTabKeepCandidate(@Nullable TabModel regularModel) {
        Tab currentTab = getActivityTab();
        if (currentTab != null && !currentTab.isIncognito()) {
            return currentTab;
        }

        if (regularModel == null || regularModel.getCount() == 0) {
            return null;
        }

        return regularModel.getTabAt(0);
    }

    private void closeExtraTabsForOneTabMode(@Nullable TabModel regularModel, int keepTabId) {
        if (regularModel == null) {
            return;
        }

        for (int i = regularModel.getCount() - 1; i >= 0; i--) {
            Tab tab = regularModel.getTabAt(i);
            if (tab == null || tab.getId() == keepTabId) {
                continue;
            }

            tab.setClosing(true);
            regularModel.getTabRemover()
                    .closeTabs(TabClosureParams.closeTab(tab).allowUndo(false).build(), false);
        }
    }

    private int getTabIndexById(@Nullable TabModel tabModel, int tabId) {
        if (tabModel == null) {
            return TabModel.INVALID_TAB_INDEX;
        }

        for (int i = 0; i < tabModel.getCount(); i++) {
            Tab tab = tabModel.getTabAt(i);
            if (tab != null && tab.getId() == tabId) {
                return i;
            }
        }

        return TabModel.INVALID_TAB_INDEX;
    }

    private void resetOneTabHomeAfterColdLauncherStart(@Nullable TabModelSelector selector) {
        mResetOneTabHomeAfterColdLauncherStart = false;

        if (selector == null || isFinishing() || isDestroyed()) {
            return;
        }

        String homepageUrl = OneTabYouTubeMode.getDefaultHomepageUrl();
        TabModel regularModel = selector.getModel(false);
        Tab keepTab = getOneTabKeepCandidate(regularModel);

        if (keepTab == null) {
            Log.i(OTB_PERF_TAG, "event=launcher_cold_start_reset_home_fresh_tab apply=1");
            getTabCreator(false).launchUrl(homepageUrl, TabLaunchType.FROM_CHROME_UI);
            syncOneTabCleanModeUi();
            return;
        }

        int keepTabIndex = getTabIndexById(regularModel, keepTab.getId());
        if (keepTabIndex != TabModel.INVALID_TAB_INDEX) {
            regularModel.setIndex(keepTabIndex, TabSelectionType.FROM_USER);
        }

        closeExtraTabsForOneTabMode(regularModel, keepTab.getId());
        if (!homepageUrl.equals(keepTab.getUrl().getSpec())) {
            Log.i(OTB_PERF_TAG, "event=launcher_cold_start_reset_home_reuse_tab load_home=1");
            keepTab.loadUrl(new LoadUrlParams(homepageUrl));
        } else {
            Log.i(OTB_PERF_TAG, "event=launcher_cold_start_reset_home_reuse_tab skip_reload=1");
        }
        syncOneTabCleanModeUi();
    }

    private void enforceOneTabYouTubeMode() {
        if (!OneTabYouTubeMode.isEnabled() || isFinishing() || isDestroyed()) {
            return;
        }

        TabModelSelector selector = getTabModelSelector();
        if (selector == null) {
            return;
        }

        TabModelUtils.runOnTabStateInitialized(
                selector,
                initializedSelector -> enforceOneTabYouTubeModeOnInitializedState(
                        initializedSelector));
    }

    private void enforceOneTabYouTubeModeOnInitializedState(@Nullable TabModelSelector selector) {
        if (!OneTabYouTubeMode.isEnabled() || isFinishing() || isDestroyed() || selector == null) {
            return;
        }

        ensureOneTabStartupMaskObserver(selector);
        closeIncognitoTabsForOneTabMode(selector);

        if (!isOneTabAuthenticated()) {
            mOneTabAuthGatePendingNavigation = true;
            maybeResolveOneTabAuthentication();
            return;
        }

        if (mResetOneTabHomeAfterColdLauncherStart) {
            resetOneTabHomeAfterColdLauncherStart(selector);
            return;
        }

        TabModel regularModel = selector.getModel(false);
        Tab keepTab = getOneTabKeepCandidate(regularModel);
        if (keepTab == null) {
            loadUrlInSingleTab(OneTabYouTubeMode.getDefaultHomepageUrl(), false);
            return;
        }

        closeExtraTabsForOneTabMode(regularModel, keepTab.getId());

        int keepTabIndex = getTabIndexById(regularModel, keepTab.getId());
        if (keepTabIndex != TabModel.INVALID_TAB_INDEX) {
            regularModel.setIndex(keepTabIndex, TabSelectionType.FROM_USER);
        }

        if (!OneTabYouTubeMode.isAllowedUrl(keepTab.getUrl().getSpec())) {
            keepTab.loadUrl(new LoadUrlParams(OneTabYouTubeMode.getDefaultHomepageUrl()));
        }

        syncOneTabCleanModeUi();
    }

    private void clearWalletModelServices() {
        if (mWalletModel == null) {
            return;
        }

        mWalletModel.resetServices(
                getApplicationContext(), null, null, null, null, null, null, null, null, null);
    }

    public void setupWalletModel() {
        // Don't setup wallet model if disabled by policy
        if (BraveWalletPolicy.isDisabledByPolicy(mTabModelProfileSupplier.get())) {
            return;
        }
        PostTask.postTask(
                TaskTraits.UI_DEFAULT,
                () -> {
                    if (mWalletModel == null) {
                        mWalletModel =
                                new WalletModel(
                                        getApplicationContext(),
                                        mKeyringService,
                                        mBlockchainRegistry,
                                        mJsonRpcService,
                                        mTxService,
                                        mEthTxManagerProxy,
                                        mSolanaTxManagerProxy,
                                        mAssetRatioService,
                                        mBraveWalletService,
                                        mSwapService);
                    } else {
                        mWalletModel.resetServices(
                                getApplicationContext(),
                                mKeyringService,
                                mBlockchainRegistry,
                                mJsonRpcService,
                                mTxService,
                                mEthTxManagerProxy,
                                mSolanaTxManagerProxy,
                                mAssetRatioService,
                                mBraveWalletService,
                                mSwapService);
                    }
                    setupObservers();
                });
    }

    @MainThread
    private void setupObservers() {
        ThreadUtils.assertOnUiThread();
        if (mWalletModel == null) {
            return;
        }
        clearObservers();
        mWalletModel
                .getCryptoModel()
                .getPendingTxHelper()
                .mSelectedPendingRequest
                .observe(
                        this,
                        transactionInfo -> {
                            if (transactionInfo == null) {
                                return;
                            }
                            // don't show dapps panel if the wallet is locked and requests are being
                            // processed by the approve dialog already
                            mKeyringService.isLocked(
                                    locked -> {
                                        if (locked) {
                                            return;
                                        }

                                        if (!mIsProcessingPendingDappsTxRequest) {
                                            mIsProcessingPendingDappsTxRequest = true;
                                            openBraveWalletDAppsActivity(
                                                    BraveWalletDAppsActivity.ActivityType
                                                            .CONFIRM_TRANSACTION);
                                        }

                                        // update badge if there's a pending tx
                                        updateWalletBadgeVisibility();
                                    });
                        });

        mWalletModel
                .getDappsModel()
                .mWalletIconNotificationVisible
                .observe(this, this::setWalletBadgeVisibility);

        mWalletModel
                .getDappsModel()
                .mPendingWalletAccountCreationRequest
                .observe(
                        this,
                        request -> {
                            if (request == null) return;
                            mWalletModel
                                    .getKeyringModel()
                                    .isWalletLocked(
                                            isLocked -> {
                                                if (!BraveWalletPreferences
                                                        .getPrefWeb3NotificationsEnabled()) {
                                                    return;
                                                }
                                                if (isLocked) {
                                                    Tab tab = getActivityTab();
                                                    if (tab != null) {
                                                        walletInteractionDetected(
                                                                tab.getWebContents());
                                                    }
                                                    showWalletPanel(false);
                                                    return;
                                                }
                                                for (CryptoAccountTypeInfo info :
                                                        mWalletModel
                                                                .getCryptoModel()
                                                                .getSupportedCryptoAccountTypes()) {
                                                    if (info.getCoinType()
                                                            == request.getCoinType()) {
                                                        Intent intent =
                                                                AddAccountActivity
                                                                        .createIntentToAddAccount(
                                                                                this,
                                                                                info.getCoinType());
                                                        startActivity(intent);
                                                        mWalletModel
                                                                .getDappsModel()
                                                                .removeProcessedAccountCreationRequest( // presubmit: ignore-long-line
                                                                        request);
                                                        break;
                                                    }
                                                }
                                            });
                        });

        mWalletModel
                .getCryptoModel()
                .getNetworkModel()
                .mNeedToCreateAccountForNetwork
                .observe(
                        this,
                        networkInfo -> {
                            if (networkInfo == null) return;

                            MaterialAlertDialogBuilder builder =
                                    new MaterialAlertDialogBuilder(
                                                    this, R.style.BraveWalletAlertDialogTheme)
                                            .setMessage(
                                                    getString(
                                                            R.string
                                                                    .brave_wallet_create_account_description, // presubmit: ignore-long-line
                                                            networkInfo.symbolName))
                                            .setPositiveButton(
                                                    R.string.brave_action_yes,
                                                    (dialog, which) -> {
                                                        mWalletModel
                                                                .createAccountAndSetDefaultNetwork(
                                                                        networkInfo);
                                                    })
                                            .setNegativeButton(
                                                    R.string.brave_action_no,
                                                    (dialog, which) -> {
                                                        mWalletModel
                                                                .getCryptoModel()
                                                                .getNetworkModel()
                                                                .clearCreateAccountState();
                                                        dialog.dismiss();
                                                    });
                            builder.show();
                        });
    }

    @MainThread
    private void clearObservers() {
        ThreadUtils.assertOnUiThread();
        if (mWalletModel == null) {
            return;
        }
        mWalletModel
                .getCryptoModel()
                .getPendingTxHelper()
                .mSelectedPendingRequest
                .removeObservers(this);
        mWalletModel.getDappsModel().mWalletIconNotificationVisible.removeObservers(this);
        mWalletModel
                .getCryptoModel()
                .getNetworkModel()
                .mNeedToCreateAccountForNetwork
                .removeObservers(this);
    }

    private void showBraveRateDialog() {
        if (BraveConfig.IS_ONETABYT) {
            return;
        }
        BraveRateDialogLauncher.show(getSupportFragmentManager(), false);
    }

    private void openYtInBraveDialog() {
        OpenYtInBraveDialogFragment mOpenYtInBraveDialogFragment =
                new OpenYtInBraveDialogFragment();
        mOpenYtInBraveDialogFragment.show(
                getSupportFragmentManager(), "OpenYtInBraveDialogFragment");
    }

    public void showDormantUsersEngagementDialog(String notificationType) {
        if (!BraveSetDefaultBrowserUtils.isBraveSetAsDefaultBrowser(BraveActivity.this)) {
            DormantUsersEngagementDialogFragment dormantUsersEngagementDialogFragment =
                    new DormantUsersEngagementDialogFragment();
            dormantUsersEngagementDialogFragment.setNotificationType(notificationType);
            dormantUsersEngagementDialogFragment.show(
                    getSupportFragmentManager(), "DormantUsersEngagementDialogFragment");
            setDormantUsersPrefs();
        }
    }

    private static Activity getActivityOfType(Class<?> classOfActivity) {
        for (Activity ref : ApplicationStatus.getRunningActivities()) {
            if (!classOfActivity.isInstance(ref)) continue;

            return ref;
        }

        return null;
    }

    public void openBraveLeo() {
        BraveLeoUtils.verifySubscription(null);
        Tab currentTab = getActivityTabProvider().get();
        if (currentTab != null) {
            BraveLeoUtils.openLeoUrlForTab(currentTab.getWebContents());
        }
    }

    public void showRewardsPage() {
        getBraveToolbarLayout().showRewardsPage();
    }

    /**
     * Sets a flag to resume the currently active media session when entering picture-in-picture
     * mode, so the user won't have to manually resume the video after the transition.
     */
    public void resumeMediaSession(final boolean resume) {
        mResumeMediaSession = resume;
    }

    public void onManualPictureInPictureEntryRequested() {
        clearPendingReturnToWatchPageAfterPictureInPictureExit("manual_pip_entry_requested");
    }

    public boolean wasRecentlyReturnedToWatchPageAfterPictureInPictureExit() {
        if (mLastReturnToWatchPageAfterPictureInPictureExitElapsedMs <= 0L) {
            return false;
        }
        long ageMs =
                SystemClock.elapsedRealtime()
                        - mLastReturnToWatchPageAfterPictureInPictureExitElapsedMs;
        boolean recent = ageMs >= 0L && ageMs <= PIP_RECENT_WATCH_PAGE_RETURN_GRACE_MS;
        Log.i(OTB_PERF_TAG, "event=pip_recent_watch_page_return recent=%b age_ms=%d", recent, ageMs);
        return recent;
    }

    private void armReturnToWatchPageAfterPictureInPictureExit() {
        mPendingReturnToWatchPageAfterPictureInPictureExit = true;
        mPendingReturnToWatchPageAfterPictureInPictureExitElapsedMs = SystemClock.elapsedRealtime();
    }

    private void clearPendingReturnToWatchPageAfterPictureInPictureExit(String reason) {
        if (mPendingReturnToWatchPageAfterPictureInPictureExit) {
            Log.i(OTB_PERF_TAG, "event=pip_exit_to_watch_page_cleared reason=%s", reason);
        }
        mPendingReturnToWatchPageAfterPictureInPictureExit = false;
        mPendingReturnToWatchPageAfterPictureInPictureExitElapsedMs = 0L;
    }

    private void maybeScheduleReturnToWatchPageAfterPictureInPictureExit(String reason) {
        if (!mPendingReturnToWatchPageAfterPictureInPictureExit) {
            return;
        }
        Log.i(OTB_PERF_TAG, "event=pip_exit_to_watch_page_schedule reason=%s", reason);
        PostTask.postDelayedTask(
                TaskTraits.UI_BEST_EFFORT,
                () -> maybeReturnToWatchPageAfterPictureInPictureExit(reason),
                PIP_EXIT_TO_WATCH_PAGE_DELAY_MS);
    }

    private void maybeReturnToWatchPageAfterPictureInPictureExit(String reason) {
        if (!mPendingReturnToWatchPageAfterPictureInPictureExit) {
            return;
        }
        long ageMs =
                SystemClock.elapsedRealtime()
                        - mPendingReturnToWatchPageAfterPictureInPictureExitElapsedMs;
        if (ageMs > PIP_EXIT_TO_WATCH_PAGE_MAX_AGE_MS) {
            clearPendingReturnToWatchPageAfterPictureInPictureExit("stale_" + reason);
            return;
        }
        if (isInPictureInPictureMode()) {
            Log.i(OTB_PERF_TAG, "event=pip_exit_to_watch_page_wait reason=%s state=in_pip", reason);
            return;
        }
        int activityState = ApplicationStatus.getStateForActivity(this);
        if (activityState != ActivityState.RESUMED) {
            Log.i(
                    OTB_PERF_TAG,
                    "event=pip_exit_to_watch_page_wait reason=%s state=%d",
                    reason,
                    activityState);
            return;
        }
        FullscreenManager fullscreenManager = getFullscreenManager();
        if (!fullscreenManager.getPersistentFullscreenMode()) {
            clearPendingReturnToWatchPageAfterPictureInPictureExit("fullscreen_already_cleared");
            return;
        }
        WebContents currentWebContents = getCurrentWebContents();
        if (currentWebContents != null
                && BraveYouTubeScriptInjectorNativeHelper.isPictureInPictureAvailable(
                        currentWebContents)) {
            boolean activeFullscreen = currentWebContents.hasActiveEffectivelyFullscreenVideo();
            if (activeFullscreen) {
                Log.i(
                        OTB_PERF_TAG,
                        "event=pip_exit_to_watch_page_wait_for_page_exit reason=%s active_fullscreen=%b",
                        reason,
                        activeFullscreen);
                BraveYouTubeScriptInjectorNativeHelper.exitFullscreen(currentWebContents);
                maybeScheduleReturnToWatchPageAfterPictureInPictureExit(
                        "await_page_exit_" + reason);
                return;
            }
        }
        clearPendingReturnToWatchPageAfterPictureInPictureExit("apply_" + reason);
        mLastReturnToWatchPageAfterPictureInPictureExitElapsedMs = SystemClock.elapsedRealtime();
        Log.i(OTB_PERF_TAG, "event=pip_exit_to_watch_page_apply reason=%s", reason);
        fullscreenManager.exitPersistentFullscreenMode();
    }

    private boolean shouldDeferOneTabPictureInPictureExitHandling() {
        PowerManager powerManager = getSystemService(PowerManager.class);
        if (powerManager != null && !powerManager.isInteractive()) {
            Log.i(
                    OTB_PERF_TAG,
                    "event=pip_exit_handling_allowed allowed=false reason=screen_not_interactive");
            return true;
        }

        KeyguardManager keyguardManager = getSystemService(KeyguardManager.class);
        if (keyguardManager == null) {
            Log.i(
                    OTB_PERF_TAG,
                    "event=pip_exit_handling_allowed allowed=true reason=no_keyguard");
            return false;
        }

        boolean locked;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            locked = keyguardManager.isDeviceLocked();
        } else {
            locked = keyguardManager.isKeyguardLocked();
        }
        Log.i(
                OTB_PERF_TAG,
                "event=pip_exit_handling_allowed allowed=%b reason=device_lock_check",
                !locked);
        return locked;
    }

    private boolean shouldReturnToWatchPageAfterPictureInPictureExit() {
        if (shouldDeferOneTabPictureInPictureExitHandling()) {
            return false;
        }
        int activityState = ApplicationStatus.getStateForActivity(this);
        return activityState == ActivityState.RESUMED || activityState == ActivityState.PAUSED;
    }

    public boolean shouldPreserveVideoPresentationForPictureInPictureControls() {
        if (!isInPictureInPictureMode()) {
            Log.i(OTB_PERF_TAG, "event=pip_presentation_restore_allowed allowed=false reason=not_in_pip");
            return false;
        }

        int activityState = ApplicationStatus.getStateForActivity(this);
        if (activityState != ActivityState.RESUMED
                && activityState != ActivityState.PAUSED
                && activityState != ActivityState.STOPPED) {
            Log.i(
                    OTB_PERF_TAG,
                    "event=pip_presentation_restore_allowed allowed=false reason=activity_state state=%d",
                    activityState);
            return false;
        }
        Log.i(
                OTB_PERF_TAG,
                "event=pip_presentation_restore_allowed allowed=true reason=keepalive_while_in_pip state=%d",
                activityState);
        return true;
    }

    public void refreshPictureInPictureParamsForCurrentVideo() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;

        Log.i(
                OTB_PERF_TAG,
                "event=pip_refresh_bridge in_pip=%b has_webcontents=%b",
                isInPictureInPictureMode(),
                getCurrentWebContents() != null);

        FullscreenVideoPictureInPictureController controller =
                ensureFullscreenVideoPictureInPictureController();
        if (controller != null) {
            controller.refreshPictureInPictureParamsForCurrentVideo();
        }
    }

    public void attemptPictureInPictureForCurrentVideo() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;

        FullscreenVideoPictureInPictureController controller =
                ensureFullscreenVideoPictureInPictureController();
        if (controller != null) {
            controller.attemptPictureInPicture();
        }
    }

    private void scheduleOneTabPictureInPictureRefresh(@NonNull String reason) {
        if (!OneTabYouTubeMode.isEnabled() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        if (!isInPictureInPictureMode()) {
            return;
        }
        refreshOneTabPictureInPictureParams(reason + "_immediate");
        PostTask.postDelayedTask(
                TaskTraits.UI_BEST_EFFORT,
                () -> refreshOneTabPictureInPictureParams(reason + "_retry1"),
                OTB_PIP_REFRESH_RETRY_DELAY_1_MS);
        PostTask.postDelayedTask(
                TaskTraits.UI_BEST_EFFORT,
                () -> refreshOneTabPictureInPictureParams(reason + "_retry2"),
                OTB_PIP_REFRESH_RETRY_DELAY_2_MS);
        PostTask.postDelayedTask(
                TaskTraits.UI_BEST_EFFORT,
                () -> refreshOneTabPictureInPictureParams(reason + "_retry3"),
                OTB_PIP_REFRESH_RETRY_DELAY_3_MS);
    }

    private void refreshOneTabPictureInPictureParams(@NonNull String reason) {
        if (!isInPictureInPictureMode()) {
            return;
        }
        WebContents currentWebContents = getCurrentWebContents();
        if (currentWebContents == null) {
            Log.i(OTB_PERF_TAG, "event=pip_refocus_skipped reason=%s has_webcontents=false", reason);
            return;
        }
        boolean hasVideoSignal =
                currentWebContents.hasActiveEffectivelyFullscreenVideo()
                        || BraveYouTubeScriptInjectorNativeHelper.hasFullscreenBeenRequested(
                                currentWebContents)
                        || BraveYouTubeScriptInjectorNativeHelper.isPictureInPictureAvailable(
                                currentWebContents);
        if (!hasVideoSignal) {
            Log.i(
                    OTB_PERF_TAG,
                    "event=pip_refocus_skipped reason=%s has_video_signal=false",
                    reason);
            return;
        }
        Log.i(OTB_PERF_TAG, "event=pip_refocus_apply reason=%s", reason);
        refreshPictureInPictureParamsForCurrentVideo();
    }

    public static ChromeTabbedActivity getChromeTabbedActivity() {
        return (ChromeTabbedActivity) getActivityOfType(ChromeTabbedActivity.class);
    }

    public static CustomTabActivity getCustomTabActivity() {
        return (CustomTabActivity) getActivityOfType(CustomTabActivity.class);
    }

    @NonNull
    public static BraveActivity getBraveActivity() throws BraveActivityNotFoundException {
        BraveActivity activity = (BraveActivity) getActivityOfType(BraveActivity.class);
        if (activity != null) {
            return activity;
        }

        throw new BraveActivityNotFoundException("BraveActivity Not Found");
    }

    @NonNull
    public static BraveActivity getBraveActivityFromTaskId(int taskId)
            throws BraveActivityNotFoundException {

        for (Activity ref : ApplicationStatus.getRunningActivities()) {
            if (!BraveActivity.class.isInstance(ref) || ref.getTaskId() != taskId) continue;

            return (BraveActivity) ref;
        }

        throw new BraveActivityNotFoundException("BraveActivity Not Found");
    }

    @Override
    public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (intent != null) {
            String openUrl = intent.getStringExtra(BraveActivity.OPEN_URL);
            if (!TextUtils.isEmpty(openUrl)) {
                try {
                    openNewOrSelectExistingTab(openUrl);
                } catch (NullPointerException e) {
                    Log.e("BraveActivity", "opening new tab " + e.getMessage());
                }
            }
        }
        checkForNotificationData();
        syncOneTabCleanModeUi();
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == OTB_LOGIN_ACTIVITY_REQUEST_CODE) {
            mOneTabLoginActivityLaunched = false;
            if (resultCode == RESULT_OK) {
                resolveOneTabPackageAccess();
            } else {
                mOneTabAuthResolved = false;
                mOneTabPackageAccessBlocked = false;
                setOneTabContentLocked(true);
            }
            return;
        }
        if (OneTabYouTubeMode.isEnabled()
                && mOneTabFirebaseAuthManager != null
                && mOneTabFirebaseAuthManager.onActivityResult(requestCode, resultCode, data)) {
            return;
        }
        if (resultCode == RESULT_OK
                && (requestCode == BraveConstants.VERIFY_WALLET_ACTIVITY_REQUEST_CODE
                        || requestCode == BraveConstants.USER_WALLET_ACTIVITY_REQUEST_CODE
                        || requestCode == BraveConstants.SITE_BANNER_REQUEST_CODE)) {
            if (data != null) {
                String open_url = data.getStringExtra(BraveActivity.OPEN_URL);
                if (!TextUtils.isEmpty(open_url)) {
                    openNewOrSelectExistingTab(open_url);
                }
            }
        } else if (resultCode == RESULT_OK
                && requestCode == BraveConstants.DEFAULT_BROWSER_ROLE_REQUEST_CODE) {
            // We don't need to anything with the result here.
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        FragmentManager fm = getSupportFragmentManager();
        BraveStatsBottomSheetDialogFragment fragment =
                (BraveStatsBottomSheetDialogFragment) fm.findFragmentByTag(
                        BraveStatsUtil.STATS_FRAGMENT_TAG);
        if (fragment != null) {
            fragment.onRequestPermissionsResult(requestCode, permissions, grantResults);
        }

        if (requestCode == BraveStatsUtil.SHARE_STATS_WRITE_EXTERNAL_STORAGE_PERM
                && grantResults.length != 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            BraveStatsUtil.shareStats(R.layout.brave_stats_share_layout);
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
    }

    @Override
    public void performPreInflationStartup() {
        BraveDbUtil dbUtil = BraveDbUtil.getInstance();
        if (dbUtil.dbOperationRequested()) {
            AlertDialog dialog =
                    new AlertDialog.Builder(this)
                            .setMessage(dbUtil.performDbExportOnStart()
                                            ? getString(
                                                    R.string.brave_db_processing_export_alert_info)
                                            : getString(
                                                    R.string.brave_db_processing_import_alert_info))
                            .setCancelable(false)
                            .create();
            dialog.setCanceledOnTouchOutside(false);
            if (dbUtil.performDbExportOnStart()) {
                dbUtil.setPerformDbExportOnStart(false);
                dbUtil.exportRewardsDb(dialog);
            } else if (dbUtil.performDbImportOnStart() && !dbUtil.dbImportFile().isEmpty()) {
                dbUtil.setPerformDbImportOnStart(false);
                dbUtil.importRewardsDb(dialog, dbUtil.dbImportFile());
            }
            dbUtil.cleanUpDbOperationRequest();
        }
        super.performPreInflationStartup();
    }

    @Override
    protected @LaunchIntentDispatcher.Action int maybeDispatchLaunchIntent(
            Intent intent, Bundle savedInstanceState) {
        boolean notificationUpdate = IntentUtils.safeGetBooleanExtra(
                intent, BravePreferenceKeys.BRAVE_UPDATE_EXTRA_PARAM, false);
        if (notificationUpdate) {
            setUpdatePreferences();
        }

        mResetOneTabHomeAfterColdLauncherStart =
                OneTabYouTubeMode.isEnabled()
                        && savedInstanceState == null
                        && isLauncherEntryIntent(intent);
        mShowOneTabStartupMaskAfterColdLauncherStart = mResetOneTabHomeAfterColdLauncherStart;
        if (mResetOneTabHomeAfterColdLauncherStart) {
            Log.i(OTB_PERF_TAG, "event=launcher_cold_start_reset_home armed=1");
        }

        return super.maybeDispatchLaunchIntent(intent, savedInstanceState);
    }

    private boolean isLauncherEntryIntent(@Nullable Intent intent) {
        if (intent == null || !Intent.ACTION_MAIN.equals(intent.getAction())) {
            return false;
        }

        Set<String> categories = intent.getCategories();
        return categories != null && categories.contains(Intent.CATEGORY_LAUNCHER);
    }

    private void setUpdatePreferences() {
        Calendar currentTime = Calendar.getInstance();
        long milliSeconds = currentTime.getTimeInMillis();

        SharedPreferences sharedPref = getApplicationContext().getSharedPreferences(
                BravePreferenceKeys.BRAVE_NOTIFICATION_PREF_NAME, 0);
        SharedPreferences.Editor editor = sharedPref.edit();

        editor.putLong(BravePreferenceKeys.BRAVE_MILLISECONDS_NAME, milliSeconds);
        editor.apply();
    }

    public MonotonicObservableSupplier<BrowserControlsManager> getBrowserControlsManagerSupplier() {
        return mBrowserControlsManagerSupplier;
    }

    @NativeMethods
    interface Natives {
        void restartStatsUpdater();
        String getSafeBrowsingApiKey();
    }

    private void initBraveWalletService() {
        if (mBraveWalletService != null) {
            return;
        }

        mBraveWalletService = BraveWalletServiceFactory.getInstance().getBraveWalletService(this);
    }

    private void initKeyringService() {
        if (mKeyringService != null) {
            return;
        }

        mKeyringService = BraveWalletServiceFactory.getInstance().getKeyringService(this);
    }

    private void initJsonRpcService() {
        if (mJsonRpcService != null) {
            return;
        }

        mJsonRpcService = BraveWalletServiceFactory.getInstance().getJsonRpcService(this);
    }

    private void initTxService() {
        if (mTxService != null) {
            return;
        }

        mTxService = BraveWalletServiceFactory.getInstance().getTxService(this);
    }

    private void initEthTxManagerProxy() {
        if (mEthTxManagerProxy != null) {
            return;
        }

        mEthTxManagerProxy = BraveWalletServiceFactory.getInstance().getEthTxManagerProxy(this);
    }

    private void initSolanaTxManagerProxy() {
        if (mSolanaTxManagerProxy != null) {
            return;
        }

        mSolanaTxManagerProxy =
                BraveWalletServiceFactory.getInstance().getSolanaTxManagerProxy(this);
    }

    private void initBlockchainRegistry() {
        if (mBlockchainRegistry != null) {
            return;
        }

        mBlockchainRegistry = BlockchainRegistryFactory.getInstance().getBlockchainRegistry(this);
    }

    private void initAssetRatioService() {
        if (mAssetRatioService != null) {
            return;
        }

        mAssetRatioService = AssetRatioServiceFactory.getInstance().getAssetRatioService(this);
    }

    @Override
    public void initMiscAndroidMetricsFromAWorkerThread() {
        runOnUiThread(
                () -> {
                    initMiscAndroidMetrics();
                });
    }

    private void initMiscAndroidMetrics() {
        ThreadUtils.assertOnUiThread();
        if (OneTabYouTubeMode.isEnabled()) {
            return;
        }
        if (mMiscAndroidMetrics != null) {
            return;
        }
        if (mMiscAndroidMetricsConnectionErrorHandler == null) {
            mMiscAndroidMetricsConnectionErrorHandler =
                    new MiscAndroidMetricsConnectionErrorHandler(this);
        }

        MiscAndroidMetricsFactory.getInstance()
                .getMetricsService(mMiscAndroidMetricsConnectionErrorHandler)
                .then(
                        miscAndroidMetrics -> {
                            mMiscAndroidMetrics = miscAndroidMetrics;
                            mMiscAndroidMetrics.recordPrivacyHubEnabledStatus(
                                    OnboardingPrefManager.getInstance().isBraveStatsEnabled());
                            mMiscAndroidMetrics.recordSetAsDefault(
                                    BraveSetDefaultBrowserUtils.isAppSetAsDefaultBrowser(
                                            BraveActivity.this));
                            Intent launchIntent = getIntent();
                            if (launchIntent != null
                                    && Intent.ACTION_VIEW.equals(launchIntent.getAction())
                                    && launchIntent.getData() != null) {
                                mMiscAndroidMetrics.recordIntentUrl(
                                        launchIntent.getData().toString());
                            }
                            if (mUsageMonitor == null) {
                                mUsageMonitor = UsageMonitor.getInstance(mMiscAndroidMetrics);
                            }
                            mUsageMonitor.start();
                        });
    }

    private void initSwapService() {
        if (mSwapService != null) {
            return;
        }
        mSwapService = SwapServiceFactory.getInstance().getSwapService(this);
    }

    private void initWalletNativeServices() {
        if (OneTabYouTubeMode.isEnabled()) {
            return;
        }
        // Don't initialize wallet services if disabled by policy
        if (BraveWalletPolicy.isDisabledByPolicy(mTabModelProfileSupplier.get())) {
            return;
        }
        initBlockchainRegistry();
        initTxService();
        initEthTxManagerProxy();
        initSolanaTxManagerProxy();
        initAssetRatioService();
        initBraveWalletService();
        initKeyringService();
        initJsonRpcService();
        initSwapService();
        setupWalletModel();
    }

    private void cleanUpWalletNativeServices() {
        clearWalletModelServices();
        if (mKeyringService != null) mKeyringService.close();
        if (mAssetRatioService != null) mAssetRatioService.close();
        if (mBlockchainRegistry != null) mBlockchainRegistry.close();
        if (mJsonRpcService != null) mJsonRpcService.close();
        if (mTxService != null) mTxService.close();
        if (mEthTxManagerProxy != null) mEthTxManagerProxy.close();
        if (mSolanaTxManagerProxy != null) mSolanaTxManagerProxy.close();
        if (mBraveWalletService != null) mBraveWalletService.close();
        mKeyringService = null;
        mBlockchainRegistry = null;
        mJsonRpcService = null;
        mTxService = null;
        mEthTxManagerProxy = null;
        mSolanaTxManagerProxy = null;
        mAssetRatioService = null;
        mBraveWalletService = null;
    }

    @Override
    public void cleanUpMiscAndroidMetrics() {
        if (mUsageMonitor != null) {
            mUsageMonitor.stop();
        }
        if (mMiscAndroidMetrics != null) mMiscAndroidMetrics.close();
        mMiscAndroidMetrics = null;
    }

    @NonNull
    private BraveToolbarLayoutImpl getBraveToolbarLayout() {
        BraveToolbarLayoutImpl layout = findViewById(R.id.toolbar);
        assert layout != null;
        return layout;
    }

    public void addOrEditBookmark(final Tab tabToBookmark) {
        RateUtils.getInstance().setPrefAddedBookmarkCount();
        ((TabBookmarker) mTabBookmarkerSupplier.get()).addOrEditBookmark(tabToBookmark);
    }

    public void showBookmarkManager(Profile profile, Tab currentTab) {
        if (mBookmarkManagerOpenerSupplier.get() != null) {
            mBookmarkManagerOpenerSupplier.get().showBookmarkManager(this, currentTab, profile);
        }
    }

    // We call that method with an interval
    // BraveSafeBrowsingApiHandler.SAFE_BROWSING_INIT_INTERVAL_MS,
    // as upstream does, to keep the GmsCore process alive.
    private void executeInitSafeBrowsing(long delay) {
        // SafeBrowsingBridge.getSafeBrowsingState() has to be executed on a main thread
        PostTask.postDelayedTask(
                TaskTraits.UI_DEFAULT,
                () -> {
                    SafeBrowsingBridge safeBrowsingBridge =
                            new SafeBrowsingBridge(getCurrentProfile());
                    if (safeBrowsingBridge.getSafeBrowsingState()
                            != SafeBrowsingState.NO_SAFE_BROWSING) {
                        // initSafeBrowsing could be executed on a background thread
                        PostTask.postTask(
                                TaskTraits.USER_VISIBLE_MAY_BLOCK,
                                () -> {
                                    BraveSafeBrowsingApiHandler.getInstance().initSafeBrowsing();
                                });
                    }
                    executeInitSafeBrowsing(
                            BraveSafeBrowsingApiHandler.SAFE_BROWSING_INIT_INTERVAL_MS);
                },
                delay);
    }

    public void updateBottomSheetPosition(int orientation) {
        if (BottomToolbarConfiguration.isBraveBottomControlsEnabled()) {
            // Ensure the bottom sheet's container is adjusted to the height of the bottom toolbar.
            ViewGroup sheetContainer = findViewById(R.id.sheet_container);
            assert sheetContainer != null;

            if (sheetContainer != null) {
                CoordinatorLayout.LayoutParams params =
                        (CoordinatorLayout.LayoutParams) sheetContainer.getLayoutParams();
                params.bottomMargin =
                        orientation == Configuration.ORIENTATION_LANDSCAPE
                                ? 0
                                : getResources()
                                        .getDimensionPixelSize(R.dimen.bottom_controls_height);
                sheetContainer.setLayoutParams(params);
            }
        }
    }

    @Override
    protected void onOrientationChange(int orientation) {
        super.onOrientationChange(orientation);
        syncOneTabCleanModeUi();
        // The activity is not destroyed during orientation changes, but
        // if the search widget promo panel is shown, it's important to recalculate its position
        // as it's different between landscape and portrait.
        if (mSearchWidgetPromoPanel != null && mSearchWidgetPromoPanel.isShowing()) {
            showWidgetPromoPanel();
        }
    }

    private void hideWidgetPromoPanel() {
        if (mSearchWidgetPromoPanel != null) {
            mSearchWidgetPromoPanel.dismiss();
            mSearchWidgetPromoPanel = null;
        }
    }

    private void showWidgetPromoPanel() {
        if (mSearchWidgetPromoPanel != null) {
            final View rootView = requireViewById(android.R.id.content);
            mSearchWidgetPromoPanel.showIfNeeded(rootView, getBottomOffsetForWidgetPromo(), this);
        }
    }

    private int getBottomOffsetForWidgetPromo() {
        if (!BottomToolbarConfiguration.isBraveBottomControlsEnabled()) return 0;

        final BrowserControlsManager browserControlsManager = mBrowserControlsManagerSupplier.get();
        if (browserControlsManager == null) {
            return 0;
        }

        return browserControlsManager.getBottomControlsHeight();
    }

    /**
     * Calls to {@link ChromeTabbedActivity#maybeHandleUrlIntent} will be redirected here via
     * bytecode changes.
     */
    public boolean maybeHandleUrlIntent(Intent intent) {
        String appLinkAction = intent.getAction();
        Uri appLinkData = intent.getData();

        if (Intent.ACTION_VIEW.equals(appLinkAction) && appLinkData != null) {
            String lastPathSegment = appLinkData.getLastPathSegment();
            if (lastPathSegment != null
                    && (lastPathSegment.equalsIgnoreCase(BraveConstants.DEEPLINK_ANDROID_PLAYLIST)
                            || lastPathSegment.equalsIgnoreCase(
                                    BraveConstants.DEEPLINK_ANDROID_VPN))) {
                return false;
            }
        }
        // Call ChromeTabbedActivity's version.
        return (boolean)
                BraveReflectionUtil.invokeMethod(
                        ChromeTabbedActivity.class,
                        this,
                        "maybeHandleUrlIntent",
                        Intent.class,
                        intent);
    }

    public RootUiCoordinator getRootUiCoordinator() {
        return mRootUiCoordinator;
    }

    public MultiInstanceManager getMultiInstanceManager() {
        return (MultiInstanceManager)
                BraveReflectionUtil.getField(
                        ChromeTabbedActivity.class, "mMultiInstanceManager", this);
    }

    private void exitBrave() {
        LayoutInflater inflater =
                (LayoutInflater) getSystemService(Context.LAYOUT_INFLATER_SERVICE);
        View view = inflater.inflate(R.layout.brave_exit_confirmation, null);
        DialogInterface.OnClickListener onClickListener =
                (dialog, button) -> {
                    if (button == AlertDialog.BUTTON_POSITIVE) {
                        ApplicationLifetime.terminate(false);
                    } else {
                        dialog.dismiss();
                    }
                };

        AlertDialog.Builder alert =
                new AlertDialog.Builder(this, R.style.ThemeOverlay_BrowserUI_AlertDialog);
        AlertDialog alertDialog =
                alert.setTitle(R.string.menu_exit)
                        .setView(view)
                        .setPositiveButton(R.string.brave_action_yes, onClickListener)
                        .setNegativeButton(R.string.brave_action_no, onClickListener)
                        .create();
        alertDialog.getDelegate().setHandleNativeActionModesEnabled(false);
        alertDialog.show();
    }

    @Override
    public void shredSiteData() {
        Tab currentTab = getActivityTab();
        if (currentTab != null) {
            shredData(currentTab);
        }
    }

    private void shredData(Tab currentTab) {
        LayoutInflater inflater =
                (LayoutInflater) getSystemService(Context.LAYOUT_INFLATER_SERVICE);
        View view = inflater.inflate(R.layout.brave_shred_data_confirmation, null);
        DialogInterface.OnClickListener onClickListener =
                (dialog, button) -> {
                    if (button == AlertDialog.BUTTON_POSITIVE) {
                        FirstPartyStorageCleanerAnimationFragment.show(BraveActivity.this);
                        BraveFirstPartyStorageCleanerUtils.cleanupTLDFirstPartyStorage(currentTab);
                    } else {
                        dialog.dismiss();
                    }
                };
        GURL lastCommittedUrl = currentTab.getWebContents().getLastCommittedUrl();
        TextView confirmationTextView =
                view.findViewById(R.id.brave_shred_data_confirmation_dialog);
        confirmationTextView.setText(
                getString(
                        R.string.brave_shred_data_confirmation,
                        lastCommittedUrl.getOrigin().getSpec()));

        AlertDialog.Builder alert =
                new AlertDialog.Builder(this, R.style.ThemeOverlay_BrowserUI_AlertDialog);
        AlertDialog alertDialog =
                alert.setTitle(R.string.brave_shred_data_dialog_title)
                        .setView(view)
                        .setPositiveButton(
                                R.string.brave_shred_data_dialog_ok_button_text, onClickListener)
                        .setNegativeButton(R.string.brave_cancel, onClickListener)
                        .create();
        alertDialog.getDelegate().setHandleNativeActionModesEnabled(false);
        alertDialog.show();
    }

    /*
     * Whether we want to pretend to be a custom tab. May be usefull to avoid certain patches,
     * when we want to have the same behaviour as in custom tabs.
     */
    public void spoofCustomTab(boolean spoof) {
        mSpoofCustomTab = spoof;
    }

    @Override
    public boolean isCustomTab() {
        if (mSpoofCustomTab) {
            return true;
        }

        return super.isCustomTab();
    }

    public void showQuickActionSearchEnginesView(int keypadHeight) {
        if (mQuickSearchEnginesView != null
                || !QuickSearchEnginesUtil.getQuickSearchEnginesFeature()) {
            return;
        }
        mQuickSearchEnginesView =
                getLayoutInflater().inflate(R.layout.quick_search_engines_view, null);
        RecyclerView recyclerView =
                (RecyclerView)
                        mQuickSearchEnginesView.findViewById(
                                R.id.quick_search_engines_recyclerview);
        LinearLayoutManager linearLayoutManager =
                new LinearLayoutManager(BraveActivity.this, LinearLayoutManager.HORIZONTAL, false);
        recyclerView.setLayoutManager(linearLayoutManager);

        ImageView quickSearchEnginesSettings =
                (ImageView)
                        mQuickSearchEnginesView.findViewById(R.id.quick_search_engines_settings);
        quickSearchEnginesSettings.setOnClickListener(
                new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        openQuickSearchEnginesSettings();
                    }
                });

        Runnable onQuickSearchEnginesReady =
                () -> {
                    if (isActivityFinishingOrDestroyed()) return;

                    quickSearchEnginesReady(recyclerView, keypadHeight);
                };
        TemplateUrlServiceFactory.getForProfile(getCurrentProfile())
                .runWhenLoaded(onQuickSearchEnginesReady);
    }

    private void quickSearchEnginesReady(RecyclerView recyclerView, int keypadHeight) {
        Profile profile = getCurrentProfile();
        List<QuickSearchEnginesModel> searchEngines =
                QuickSearchEnginesUtil.getQuickSearchEnginesForView(profile);

        QuickSearchEnginesModel defaultQuickSearchEnginesModel =
                QuickSearchEnginesUtil.getDefaultSearchEngine(profile);
        searchEngines.add(0, defaultQuickSearchEnginesModel);

        if (!profile.isOffTheRecord()
                && BraveLeoPrefUtils.shouldShowLeoQuickSearchEngine()
                && !BraveLeoPrefUtils.isLeoDisabledByPolicy(profile)) {
            QuickSearchEnginesModel leoQuickSearchEnginesModel =
                    new QuickSearchEnginesModel(
                            "",
                            "",
                            "",
                            true,
                            QuickSearchEnginesModel.QuickSearchEnginesModelType.AI_ASSISTANT);
            searchEngines.add(0, leoQuickSearchEnginesModel);
        }

        QuickSearchEnginesViewAdapter adapter =
                new QuickSearchEnginesViewAdapter(BraveActivity.this, searchEngines, this);
        recyclerView.setAdapter(adapter);
        if (mQuickSearchEnginesView.getParent() == null) {
            WindowManager.LayoutParams params =
                    new WindowManager.LayoutParams(
                            WindowManager.LayoutParams.MATCH_PARENT,
                            WindowManager.LayoutParams.WRAP_CONTENT,
                            WindowManager.LayoutParams.TYPE_APPLICATION_PANEL,
                            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                            WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
            params.gravity = Gravity.BOTTOM;
            params.y = keypadHeight; // Position the view above the keyboard

            WindowManager windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
            windowManager.addView(mQuickSearchEnginesView, params);
        }
    }

    public void removeQuickActionSearchEnginesView() {
        if (mQuickSearchEnginesView != null && mQuickSearchEnginesView.getParent() != null) {
            WindowManager windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
            windowManager.removeView(mQuickSearchEnginesView);
            mQuickSearchEnginesView = null;
        }
    }

    private void maybeExecuteLeoVoicePrompt() {
        Intent intent = getIntent();
        WebContents webContents = getCurrentWebContents();
        if (intent != null
                && IntentUtils.safeGetBooleanExtra(
                        intent, IntentHandler.EXTRA_INVOKED_FROM_APP_WIDGET, false)
                && IntentUtils.safeGetBooleanExtra(
                        intent, BraveIntentHandler.EXTRA_INVOKED_FROM_APP_WIDGET_LEO, false)
                && !IntentUtils.safeGetBooleanExtra(
                        intent, BraveIntentHandler.EXTRA_LEO_VOICE_PROMPT_INVOKED, false)
                && webContents != null) {
            // Marks that Leo prompt was invoked to avoid re-invoke on resume
            intent.putExtra(BraveIntentHandler.EXTRA_LEO_VOICE_PROMPT_INVOKED, true);
            new BraveLeoVoiceRecognitionHandler(
                            webContents.getTopLevelNativeWindow(), webContents, "")
                    .startVoiceRecognition();
        }
    }

    // QuickSearchCallback
    @Override
    public void onSearchEngineClick(int position, QuickSearchEnginesModel quickSearchEnginesModel) {
        if (mMiscAndroidMetrics != null) {
            mMiscAndroidMetrics.recordQuickSearch(
                    quickSearchEnginesModel.getType()
                            == QuickSearchEnginesModel.QuickSearchEnginesModelType.AI_ASSISTANT,
                    quickSearchEnginesModel.getKeyword());
        }
        if (getActivityTab() == null) {
            return;
        }
        String query = getBraveToolbarLayout().getLocationBarQuery();
        if (position == 0
                && quickSearchEnginesModel.getType()
                        == QuickSearchEnginesModel.QuickSearchEnginesModelType.AI_ASSISTANT) {
            BraveLeoUtils.openLeoQuery(getActivityTab().getWebContents(), "", query, true);
        } else {
            String quickSearchEngineUrl =
                    GOOGLE_SEARCH_ENGINE_KEYWORD.equals(quickSearchEnginesModel.getKeyword())
                            ? QuickSearchEnginesUtil.GOOGLE_SEARCH_ENGINE_URL
                            : quickSearchEnginesModel.getUrl();
            LoadUrlParams loadUrlParams =
                    new LoadUrlParams(
                            quickSearchEngineUrl
                                    .replace("{searchTerms}", query)
                                    .replace("{inputEncoding}", "UTF-8"));
            getActivityTab().loadUrl(loadUrlParams);
        }
        getBraveToolbarLayout().clearOmniboxFocus();
    }

    @Override
    public void loadSearchEngineLogo(
            ImageView logoView, QuickSearchEnginesModel quickSearchEnginesModel) {
        QuickSearchEnginesUtil.loadSearchEngineLogo(
                getCurrentProfile(), logoView, quickSearchEnginesModel.getKeyword());
    }

    @Override
    public void onKeyboardOpened(int keyboardHeight) {
        runOnUiThread(
                () -> {
                    hideWidgetPromoPanel();
                    if (!isFinishing()
                            && !isDestroyed()
                            && getBraveToolbarLayout().isUrlBarFocused()
                            && !getBraveToolbarLayout().getLocationBarQuery().isEmpty()) {
                        showQuickActionSearchEnginesView(keyboardHeight);
                    }
                });
    }

    @Override
    public void onKeyboardClosed() {
        hideWidgetPromoPanel();
        removeQuickActionSearchEnginesView();
    }

    @Override
    public void onSharedPreferenceChanged(
            SharedPreferences sharedPreferences, @Nullable String key) {
        if (ChromePreferenceKeys.TOOLBAR_TOP_ANCHORED.equals(key)) {
            Activity currentActivity = ApplicationStatus.getLastTrackedFocusedActivity();
            if (currentActivity == null) {
                currentActivity = this;
            }
            BraveRelaunchUtils.askForRelaunch(currentActivity);
        }
    }

    @Override
    public void onNewIntentWithNative(Intent intent) {
        // If intent comes from our own package, check if we need to redirect upstream's urls (for
        // help, support, etc.).
        if (intent != null
                && intent.getAction() != null
                && Intent.ACTION_VIEW.equals(intent.getAction())
                && intent.getPackage() != null
                && intent.getPackage().equals(getPackageName())) {
            String url = IntentHandler.getUrlFromIntent(intent);
            if (url != null) {
                if (url.equals(BraveIntentHandler.CONNECTION_INFO_HELP_URL)) {
                    intent.setData(Uri.parse(BraveIntentHandler.BRAVE_CONNECTION_INFO_HELP_URL));
                } else if (url.equals(BraveIntentHandler.FALLBACK_SUPPORT_URL)) {
                    intent.setData(Uri.parse(BraveIntentHandler.BRAVE_FALLBACK_SUPPORT_URL));
                }
            }
        }
        super.onNewIntentWithNative(intent);
    }

    @Override
    public void onTabStateInitializedHandler() {
        Profile profile = getCurrentProfile();
        if (profile != null) {
            // Triggers current app state notification to make sure the first-party storage cleanup
            // is scheduled on startup if needed.
            BraveFirstPartyStorageCleanerUtils.triggerCurrentAppStateNotification(profile);
        }
        syncOneTabCleanModeUi();
    }
}
