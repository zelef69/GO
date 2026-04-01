#!/usr/bin/env python3
"""Generate OneTabTube Leo/AI stub sources as a srcjar."""

import argparse
import textwrap
import zipfile


def _stub_sources():
    return {
        "org/chromium/chrome/browser/brave_leo/BraveLeoPrefUtils.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.brave_leo;

            import org.chromium.build.annotations.Nullable;
            import org.chromium.chrome.browser.profiles.Profile;

            public final class BraveLeoPrefUtils {
                private BraveLeoPrefUtils() {}

                public static boolean isLeoDisabledByPolicy(@Nullable Profile profile) {
                    return true;
                }

                public static void setIsSubscriptionActive(boolean value) {}

                public static boolean getIsSubscriptionActive(@Nullable Profile profile) {
                    return false;
                }

                public static void setChatPurchaseToken(String token) {}

                public static boolean getIsHistoryEnabled() {
                    return false;
                }

                public static void setIsHistoryEnabled(boolean isEnabled) {}

                public static void setChatPackageName() {}

                public static void setChatProductId(String productId) {}

                public static boolean isLeoEnabled() {
                    return false;
                }

                public static boolean isSubscriptionLinked() {
                    return false;
                }

                public static boolean shouldShowLeoQuickSearchEngine() {
                    return false;
                }
            }
            """
        ),
        "org/chromium/chrome/browser/brave_leo/BraveLeoUtils.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.brave_leo;

            import android.app.Activity;

            import org.chromium.ai_chat.mojom.ModelWithSubtitle;
            import org.chromium.base.Callback;
            import org.chromium.content_public.browser.WebContents;

            public final class BraveLeoUtils {
                private BraveLeoUtils() {}

                public static void verifySubscription(Callback callback) {
                    if (callback != null) {
                        callback.onResult(null);
                    }
                }

                public static void openLeoQuery(
                        WebContents webContents,
                        String conversationUuid,
                        String query,
                        boolean openLeoChatWindow) {}

                public static void openLeoUrlForTab(WebContents webContents) {}

                public static String getDefaultModelName(
                        ModelWithSubtitle[] models, String defaultModelKey) {
                    return "";
                }

                public static void openManageSubscription() {}

                public static void goPremium(Activity activity) {}

                public static void bringMainActivityOnTop() {}
            }
            """
        ),
        "org/chromium/chrome/browser/brave_leo/BraveLeoVoiceRecognitionHandler.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.brave_leo;

            import org.chromium.content_public.browser.WebContents;
            import org.chromium.ui.base.WindowAndroid;

            public class BraveLeoVoiceRecognitionHandler {
                public BraveLeoVoiceRecognitionHandler(
                        WindowAndroid windowAndroid,
                        WebContents contextWebContents,
                        String conversationUuid) {}

                public void startVoiceRecognition() {}
            }
            """
        ),
        "org/chromium/chrome/browser/brave_leo/BraveLeoMojomHelper.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.brave_leo;

            import org.chromium.ai_chat.mojom.AiChatSettingsHelper;
            import org.chromium.ai_chat.mojom.ModelWithSubtitle;
            import org.chromium.ai_chat.mojom.PremiumStatus;
            import org.chromium.chrome.browser.browsing_data.TimePeriod;
            import org.chromium.content_public.browser.BrowserContextHandle;

            public final class BraveLeoMojomHelper {
                private static final BraveLeoMojomHelper INSTANCE = new BraveLeoMojomHelper();

                private BraveLeoMojomHelper() {}

                public static BraveLeoMojomHelper getInstance(
                        BrowserContextHandle browserContextHandle) {
                    return INSTANCE;
                }

                public void getPremiumStatus(
                        AiChatSettingsHelper.GetPremiumStatus_Response callback) {
                    callback.call(PremiumStatus.INACTIVE, null);
                }

                public void createOrderId(AiChatSettingsHelper.CreateOrderId_Response callback) {
                    callback.call("");
                }

                public void fetchOrderCredentials(
                        String orderId,
                        AiChatSettingsHelper.FetchOrderCredentials_Response callback) {
                    callback.call("{}");
                }

                public void refreshOrder(
                        String orderId, AiChatSettingsHelper.RefreshOrder_Response callback) {
                    callback.call("{}");
                }

                public void getModels(
                        AiChatSettingsHelper.GetModelsWithSubtitles_Response callback) {
                    callback.call(new ModelWithSubtitle[0]);
                }

                public void getDefaultModelKey(
                        AiChatSettingsHelper.GetDefaultModelKey_Response callback) {
                    callback.call("");
                }

                public void setDefaultModelKey(String modelKey) {}

                public void deleteConversations(@TimePeriod int timePeriod) {}
            }
            """
        ),
        "org/chromium/chrome/browser/toolbar/adaptive/BraveLeoButtonController.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.toolbar.adaptive;

            import android.content.Context;
            import android.content.res.Resources;
            import android.graphics.drawable.Drawable;
            import android.view.View;

            import org.chromium.base.supplier.MonotonicObservableSupplier;
            import org.chromium.build.annotations.Nullable;
            import org.chromium.chrome.R;
            import org.chromium.chrome.browser.ActivityTabProvider;
            import org.chromium.chrome.browser.profiles.Profile;
            import org.chromium.chrome.browser.tab.Tab;
            import org.chromium.chrome.browser.toolbar.optional_button.BaseButtonDataProvider;
            import org.chromium.ui.modaldialog.ModalDialogManager;

            public class BraveLeoButtonController extends BaseButtonDataProvider {
                public BraveLeoButtonController(
                        Context context,
                        Drawable buttonDrawable,
                        ActivityTabProvider tabProvider,
                        MonotonicObservableSupplier<Profile> profileSupplier,
                        ModalDialogManager modalDialogManager) {
                    super(
                            tabProvider,
                            modalDialogManager,
                            buttonDrawable,
                            context.getString(R.string.menu_brave_leo),
                            Resources.ID_NULL,
                            true,
                            null,
                            AdaptiveToolbarButtonVariant.LEO,
                            R.string.menu_brave_leo);
                }

                @Override
                public void onClick(View view) {}

                @Override
                protected boolean shouldShowButton(@Nullable Tab tab) {
                    return false;
                }
            }
            """
        ),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-srcjar", required=True)
    args = parser.parse_args()

    with zipfile.ZipFile(args.output_srcjar, "w", zipfile.ZIP_DEFLATED) as out:
        for path, contents in _stub_sources().items():
            out.writestr(path, contents)


if __name__ == "__main__":
    main()
