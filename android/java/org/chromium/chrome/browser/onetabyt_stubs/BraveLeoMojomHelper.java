/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.brave_leo;

import org.chromium.ai_chat.mojom.AiChatSettingsHelper;
import org.chromium.ai_chat.mojom.ModelWithSubtitle;
import org.chromium.ai_chat.mojom.PremiumStatus;
import org.chromium.chrome.browser.browsing_data.TimePeriod;
import org.chromium.content_public.browser.BrowserContextHandle;

// OneTabTube strips Leo/AI surfaces, so this helper intentionally returns inert values.
public final class BraveLeoMojomHelper {
    private static final BraveLeoMojomHelper INSTANCE = new BraveLeoMojomHelper();

    private BraveLeoMojomHelper() {}

    public static BraveLeoMojomHelper getInstance(BrowserContextHandle browserContextHandle) {
        return INSTANCE;
    }

    public void getPremiumStatus(AiChatSettingsHelper.GetPremiumStatus_Response callback) {
        callback.call(PremiumStatus.INACTIVE, null);
    }

    public void createOrderId(AiChatSettingsHelper.CreateOrderId_Response callback) {
        callback.call("");
    }

    public void fetchOrderCredentials(
            String orderId, AiChatSettingsHelper.FetchOrderCredentials_Response callback) {
        callback.call("{}");
    }

    public void refreshOrder(
            String orderId, AiChatSettingsHelper.RefreshOrder_Response callback) {
        callback.call("{}");
    }

    public void getModels(AiChatSettingsHelper.GetModelsWithSubtitles_Response callback) {
        callback.call(new ModelWithSubtitle[0]);
    }

    public void getDefaultModelKey(AiChatSettingsHelper.GetDefaultModelKey_Response callback) {
        callback.call("");
    }

    public void setDefaultModelKey(String modelKey) {}

    public void deleteConversations(@TimePeriod int timePeriod) {}
}
