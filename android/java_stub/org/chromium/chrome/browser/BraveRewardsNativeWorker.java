package org.chromium.chrome.browser;

public class BraveRewardsNativeWorker {
    public interface PublisherObserver {
        void onFrontTabPublisherChanged(boolean verified, String publisherId);
    }

    public static final int REWARDS_NOTIFICATION_INVALID = 0;
    public static final int REWARDS_NOTIFICATION_AUTO_CONTRIBUTE = 1;
    public static final int REWARDS_NOTIFICATION_FAILED_CONTRIBUTION = 4;
    public static final int REWARDS_NOTIFICATION_IMPENDING_CONTRIBUTION = 5;
    public static final int REWARDS_NOTIFICATION_TIPS_PROCESSED = 8;
    public static final int REWARDS_NOTIFICATION_ADS_ONBOARDING = 9;
    public static final int REWARDS_NOTIFICATION_VERIFIED_PUBLISHER = 10;
    public static final int REWARDS_NOTIFICATION_PENDING_NOT_ENOUGH_FUNDS = 11;
    public static final int REWARDS_NOTIFICATION_GENERAL = 12;

    public static final int OK = 0;
    public static final int FAILED = 1;
    public static final int BAT_NOT_ALLOWED = 25;
    public static final int SAFETYNET_ATTESTATION_FAILED = 27;

    private static final BraveRewardsNativeWorker INSTANCE = new BraveRewardsNativeWorker();

    public static BraveRewardsNativeWorker getInstance() {
        return INSTANCE;
    }

    public void addObserver(BraveRewardsObserver observer) {}

    public void removeObserver(BraveRewardsObserver observer) {}

    public void addPublisherObserver(PublisherObserver observer) {}

    public void removePublisherObserver(PublisherObserver observer) {}

    public void onNotifyFrontTabUrlChanged(int tabId, String url) {}

    public void triggerOnNotifyFrontTabUrlChanged() {}

    public boolean isSupported() {
        return false;
    }

    public boolean isSupportedSkipRegionCheck() {
        return false;
    }

    public boolean isRewardsEnabled() {
        return false;
    }

    public boolean shouldShowSelfCustodyInvite() {
        return false;
    }

    public void createRewardsWallet(String countryCode) {}

    public void getRewardsParameters() {}

    public double getVbatDeadline() {
        return 0;
    }

    public void getUserType() {}

    public void fetchBalance() {}

    public BraveRewardsBalance getWalletBalance() {
        return null;
    }

    public String getExternalWalletType() {
        return "";
    }

    public boolean canConnectAccount() {
        return false;
    }

    public double[] getTipChoices() {
        return new double[0];
    }

    public double getWalletRate() {
        return 0;
    }

    public void getPublisherInfo(int tabId, String host) {}

    public String getPublisherURL(int tabId) {
        return "";
    }

    public String getCaptchaSolutionURL(String paymentId, String captchaId) {
        return "";
    }

    public String getAttestationURL() {
        return "";
    }

    public String getAttestationURLWithPaymentId(String paymentId) {
        return "";
    }

    public String getPublisherFavIconURL(int tabId) {
        return "";
    }

    public String getPublisherName(int tabId) {
        return "";
    }

    public String getPublisherId(int tabId) {
        return "";
    }

    public int getPublisherPercent(int tabId) {
        return 0;
    }

    public boolean getPublisherExcluded(int tabId) {
        return false;
    }

    public int getPublisherStatus(int tabId) {
        return 0;
    }

    public void removePublisherFromMap(int tabId) {}

    public void getCurrentBalanceReport() {}

    public void donate(String publisherKey, double amount, boolean recurring) {}

    public void getAllNotifications() {}

    public void deleteNotification(String notificationId) {}

    public void getRecurringDonations() {}

    public boolean isCurrentPublisherInRecurrentDonations(String publisher) {
        return false;
    }

    public double getPublisherRecurrentDonationAmount(String publisher) {
        return 0;
    }

    public void getReconcileStamp() {}

    public void removeRecurring(String publisher) {}

    public void resetTheWholeState() {}

    public int getAdsPerHour() {
        return 0;
    }

    public void setAdsPerHour(int value) {}

    public void getExternalWallet() {}

    public boolean isTermsOfServiceUpdateRequired() {
        return false;
    }

    public void acceptTermsOfServiceUpdate() {}

    public String getCountryCode() {
        return "";
    }

    public void getAvailableCountries() {}

    public void getPublisherBanner(String publisherKey) {}

    public void getPublishersVisitedCount() {}

    public void disconnectWallet() {}

    public void getAdsAccountStatement() {}

    public void refreshPublisher(String publisherKey) {}

    public void recordPanelTrigger() {}

    public String getPayoutStatus() {
        return "";
    }

    public void onGetPublishersVisitedCount(int count) {}

    public void onCreateRewardsWallet(String result) {}

    public void onRefreshPublisher(int status, String publisherKey) {}

    public void onRewardsParameters() {}

    public void onTermsOfServiceUpdateAccepted() {}

    public void onBalance(boolean success) {}

    public void onGetCurrentBalanceReport(double[] report) {}

    public void onPublisherInfo(int tabId, String publisherId) {}

    public void onNotificationAdded(String id, int type, long timestamp, String[] args) {}

    public void onNotificationsCount(int count) {}

    public void onGetLatestNotification(String id, int type, long timestamp, String[] args) {}

    public void onNotificationDeleted(String id) {}

    public void onGetReconcileStamp(long timestamp) {}

    public void onRecurringDonationUpdated() {}

    public void onCompleteReset(boolean success) {}

    public void onResetTheWholeState(boolean success) {}

    public void onGetExternalWallet(String externalWallet) {}

    public void onGetAvailableCountries(String[] countries) {}

    public void onGetAdsAccountStatement(
            boolean success,
            double nextPaymentDate,
            int adsReceivedThisMonth,
            double minEarningsThisMonth,
            double maxEarningsThisMonth,
            double minEarningsLastMonth,
            double maxEarningsLastMonth) {}

    public void onExternalWalletConnected() {}

    public void onExternalWalletLoggedOut() {}

    public void onExternalWalletReconnected() {}

    public void onSendContribution(boolean result) {}

    public void onReconcileComplete(int resultCode, int rewardsType, double amount) {}

    public void onPublisherBanner(String jsonBannerInfo) {}

    public void onGetUserType(int userType) {}
}
