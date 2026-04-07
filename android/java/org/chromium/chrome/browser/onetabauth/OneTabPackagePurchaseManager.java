package org.chromium.chrome.browser.onetabauth;

import android.text.TextUtils;

import org.json.JSONObject;

import org.chromium.base.Log;
import org.chromium.net.ChromiumNetworkAdapter;
import org.chromium.net.NetworkTrafficAnnotationTag;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

public final class OneTabPackagePurchaseManager {
    private static final String TAG = "OneTabPurchase";
    private static final String PRODUCT_DOC_PATH_PREFIX = "products/";
    private static final String PAYMENT_ACCOUNT_DOC_PATH = "settings/payment_account";
    public static final String[] SUPPORTED_PACKAGE_IDS = {"pkg_01", "pkg_02", "pkg_03"};
    public static final String PAYMENT_SERVICE_UNAVAILABLE_MESSAGE =
            "ระบบซื้อแพ็กเกจยังไม่พร้อมใช้งาน โปรดติดต่อแอดมิน";
    public static final String PACKAGE_ACCESS_UNAVAILABLE_MESSAGE =
            "ไม่สามารถตรวจสอบสิทธิ์แพ็กเกจได้ในขณะนี้";
    private static final NetworkTrafficAnnotationTag PURCHASE_TRAFFIC_ANNOTATION =
            NetworkTrafficAnnotationTag.MISSING_TRAFFIC_ANNOTATION;

    public ProductSummary fetchProductSummary(String packageId) {
        try {
            JSONObject fields = fetchDocumentFields(PRODUCT_DOC_PATH_PREFIX + packageId);
            if (fields == null) {
                return ProductSummary.fallback(packageId);
            }
            JSONObject paymentAccountFields = fetchDocumentFields(PAYMENT_ACCOUNT_DOC_PATH);

            return new ProductSummary(
                    packageId,
                    readTextField(fields, "name", ProductSummary.DEFAULT_NAME),
                    readLongField(fields, "price", ProductSummary.DEFAULT_PRICE),
                    readTextField(fields, "currency", ProductSummary.DEFAULT_CURRENCY),
                    (int) readLongField(fields, "durationDays", ProductSummary.DEFAULT_DURATION_DAYS),
                    readPreferredBankDisplayField(paymentAccountFields, fields),
                    readTextField(
                            paymentAccountFields,
                            "accountNameEn",
                            readTextField(
                                    fields,
                                    "accountNameEn",
                                    ProductSummary.DEFAULT_ACCOUNT_NAME_EN)),
                    readTextField(
                            paymentAccountFields,
                            "accountNameTh",
                            readTextField(
                                    fields,
                                    "accountNameTh",
                                    ProductSummary.DEFAULT_ACCOUNT_NAME_TH)),
                    readTextField(
                            paymentAccountFields,
                            "accountNumber",
                            readTextField(
                                    fields,
                                    "accountNumber",
                                    ProductSummary.DEFAULT_ACCOUNT_NUMBER)),
                    readBooleanField(fields, "active", true));
        } catch (Exception e) {
            Log.e(TAG, "fetchProductSummary exception=%s", e.getMessage());
            return ProductSummary.fallback(packageId);
        }
    }

    public List<ProductSummary> fetchProductOptions() {
        List<ProductSummary> products = new ArrayList<>();
        for (String packageId : SUPPORTED_PACKAGE_IDS) {
            products.add(fetchProductSummary(packageId));
        }
        return products;
    }

    public AccessStateResult fetchPackageAccessState(String idToken, String appCheckToken) {
        try {
            JSONObject payload = new JSONObject();
            payload.put("data", new JSONObject());
            JSONObject response =
                    callCallable("getPackageAccessState", payload, idToken, appCheckToken);
            JSONObject result = response.optJSONObject("result");
            if (result == null) {
                return AccessStateResult.unavailable(PACKAGE_ACCESS_UNAVAILABLE_MESSAGE);
            }
            return AccessStateResult.success(
                    result.optBoolean("allowed", false),
                    result.optString("status", ""),
                    (int) result.optLong("remainingDays", -1),
                    result.optString("packageId", ""),
                    result.optString("expiresAt", ""),
                    result.optString("message", ""));
        } catch (PurchaseException e) {
            if (TextUtils.equals(e.message, PAYMENT_SERVICE_UNAVAILABLE_MESSAGE)
                    || TextUtils.equals(e.message, PACKAGE_ACCESS_UNAVAILABLE_MESSAGE)) {
                return AccessStateResult.unavailable(PACKAGE_ACCESS_UNAVAILABLE_MESSAGE);
            }
            return AccessStateResult.error(e.message);
        } catch (Exception e) {
            Log.e(TAG, "fetchPackageAccessState exception=%s", e.getMessage());
            return AccessStateResult.unavailable(PACKAGE_ACCESS_UNAVAILABLE_MESSAGE);
        }
    }

    private JSONObject fetchDocumentFields(String documentPath) {
        HttpURLConnection connection = null;
        try {
            connection =
                    (HttpURLConnection)
                            ChromiumNetworkAdapter.openConnection(
                                    new URL(
                                            OneTabFirebaseAuthConfig.FIRESTORE_BASE_URL
                                                    + "/"
                                                    + documentPath),
                                    PURCHASE_TRAFFIC_ANNOTATION);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Accept", "application/json");

            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(
                        TAG,
                        "fetchDocumentFields failed path=%s code=%d body=%s",
                        documentPath,
                        responseCode,
                        responseBody);
                return null;
            }
            return new JSONObject(responseBody).optJSONObject("fields");
        } catch (Exception e) {
            Log.e(TAG, "fetchDocumentFields exception path=%s error=%s", documentPath, e.getMessage());
            return null;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    public CallableResult createPackageOrder(String idToken, String appCheckToken, String packageId) {
        try {
            JSONObject data = new JSONObject();
            data.put("packageId", packageId);
            JSONObject payload = new JSONObject();
            payload.put("data", data);
            JSONObject response =
                    callCallable(
                            "createPackageOrder",
                            payload,
                            idToken,
                            appCheckToken);
            JSONObject result = response.optJSONObject("result");
            if (result == null) {
                return CallableResult.error("ข้อมูลคำสั่งซื้อที่ตอบกลับมาว่างเปล่า");
            }
            return CallableResult.success(
                    new OrderResult(
                            result.optString("orderId", ""),
                            result.optString("storagePath", ""),
                            result.optString("uploadUrl", ""),
                            result.optString("currency", ProductSummary.DEFAULT_CURRENCY),
                            result.optLong("expectedAmount", ProductSummary.DEFAULT_PRICE),
                            (int) result.optLong("durationDays", ProductSummary.DEFAULT_DURATION_DAYS),
                            result.optString("expiresAt", "")));
        } catch (PurchaseException e) {
            return CallableResult.error(e.message);
        } catch (Exception e) {
            Log.e(TAG, "createPackageOrder exception=%s", e.getMessage());
            return CallableResult.error("ยังสร้างคำสั่งซื้อแพ็กเกจไม่ได้");
        }
    }

    public String uploadSlipJpeg(String uploadUrl, byte[] jpegBytes) {
        HttpURLConnection connection = null;
        try {
            connection =
                    (HttpURLConnection)
                            ChromiumNetworkAdapter.openConnection(
                                    new URL(uploadUrl), PURCHASE_TRAFFIC_ANNOTATION);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(30000);
            connection.setDoOutput(true);
            connection.setRequestMethod("PUT");
            connection.setRequestProperty("Content-Type", "image/jpeg");
            connection.setFixedLengthStreamingMode(jpegBytes.length);
            try (OutputStream outputStream = connection.getOutputStream()) {
                outputStream.write(jpegBytes);
                outputStream.flush();
            }

            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode != HttpURLConnection.HTTP_OK
                    && responseCode != HttpURLConnection.HTTP_CREATED) {
                Log.w(TAG, "uploadSlipJpeg failed code=%d body=%s", responseCode, responseBody);
                return "ยังอัปโหลดรูปสลิปไม่ได้";
            }
            return "";
        } catch (Exception e) {
            Log.e(TAG, "uploadSlipJpeg exception=%s", e.getMessage());
            return "ยังอัปโหลดรูปสลิปไม่ได้";
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    public VerifyResult verifyPackageSlip(
            String idToken, String appCheckToken, String orderId, String storagePath) {
        try {
            JSONObject data = new JSONObject();
            data.put("orderId", orderId);
            data.put("storagePath", storagePath);
            JSONObject payload = new JSONObject();
            payload.put("data", data);
            JSONObject response =
                    callCallable(
                            "verifyPackageSlip",
                            payload,
                            idToken,
                            appCheckToken);
            JSONObject result = response.optJSONObject("result");
            if (result == null) {
                return VerifyResult.error("ข้อมูลผลตรวจสลิปที่ตอบกลับมาว่างเปล่า");
            }
            return VerifyResult.success(
                    result.optString("status", ""),
                    result.optString("orderId", orderId),
                    result.optString("packageId", ""),
                    result.optString("paymentRef", ""),
                    result.optString("currency", ProductSummary.DEFAULT_CURRENCY),
                    result.optLong("expectedAmount", ProductSummary.DEFAULT_PRICE),
                    result.optLong("amountInSlip", 0L),
                    (int) result.optLong("durationDays", ProductSummary.DEFAULT_DURATION_DAYS),
                    result.optBoolean("alreadyProcessed", false),
                    result.optJSONObject("entitlement") != null
                            ? result.optJSONObject("entitlement").optString("expiresAt", "")
                            : "");
        } catch (PurchaseException e) {
            return VerifyResult.error(e.message);
        } catch (Exception e) {
            Log.e(TAG, "verifyPackageSlip exception=%s", e.getMessage());
            return VerifyResult.error("ยังตรวจสอบสลิปธนาคารไม่ได้");
        }
    }

    private JSONObject callCallable(
            String functionName, JSONObject payload, String idToken, String appCheckToken)
            throws Exception {
        HttpURLConnection connection = null;
        try {
            connection =
                    (HttpURLConnection)
                            ChromiumNetworkAdapter.openConnection(
                                    new URL(
                                            OneTabFirebaseAuthConfig.FUNCTIONS_BASE_URL
                                                    + "/"
                                                    + functionName),
                                    PURCHASE_TRAFFIC_ANNOTATION);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(30000);
            connection.setDoOutput(true);
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("Authorization", "Bearer " + idToken);
            connection.setRequestProperty("X-Firebase-AppCheck", appCheckToken);
            try (OutputStream outputStream = connection.getOutputStream()) {
                byte[] bytes = payload.toString().getBytes(StandardCharsets.UTF_8);
                outputStream.write(bytes);
                outputStream.flush();
            }

            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode != HttpURLConnection.HTTP_OK) {
                if (responseCode == HttpURLConnection.HTTP_NOT_FOUND) {
                    throw new PurchaseException(PAYMENT_SERVICE_UNAVAILABLE_MESSAGE);
                }
                throw parseCallableError(responseBody, "คำขอไม่สำเร็จ");
            }

            JSONObject response = new JSONObject(responseBody);
            if (response.has("error")) {
                throw parseCallableError(responseBody, "คำขอไม่สำเร็จ");
            }
            return response;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static PurchaseException parseCallableError(String responseBody, String fallback) {
        try {
            JSONObject root = new JSONObject(responseBody);
            JSONObject error = root.optJSONObject("error");
            if (error == null) {
                return new PurchaseException(fallback);
            }
            String message = error.optString("message", "");
            JSONObject details = error.optJSONObject("details");
            if (details != null) {
                String code = details.optString("code", "");
                if ("SLIP_PENDING".equals(code)) {
                    return new PurchaseException("สลิปกำลังอยู่ระหว่างตรวจสอบ กรุณาลองใหม่อีกครั้ง");
                }
                if ("DUPLICATE_SLIP".equals(code)) {
                    return new PurchaseException("สลิปนี้ถูกใช้งานไปแล้ว");
                }
                if ("AMOUNT_MISMATCH".equals(code)) {
                    return new PurchaseException("ยอดเงินในสลิปไม่ตรงกับแพ็กเกจนี้");
                }
                if ("ACCOUNT_NOT_MATCH".equals(code)) {
                    return new PurchaseException("บัญชีปลายทางในสลิปไม่ตรงกับบัญชีที่ตั้งไว้");
                }
                if ("ORDER_EXPIRED".equals(code)) {
                    return new PurchaseException("คำสั่งซื้อหมดเวลาแล้ว กรุณาสร้างรายการใหม่");
                }
                if ("ORDER_NOT_PENDING".equals(code)) {
                    return new PurchaseException("คำสั่งซื้อนี้ไม่อยู่ในสถานะที่ตรวจสอบสลิปได้แล้ว");
                }
                if ("THUNDER_UNAVAILABLE".equals(code)) {
                    return new PurchaseException("ระบบตรวจสอบสลิปของ Thunder ยังไม่พร้อมใช้งาน");
                }
            }
            if (!TextUtils.isEmpty(message)) {
                return new PurchaseException(message);
            }
        } catch (Exception ignored) {
        }
        return new PurchaseException(fallback);
    }

    private static String readTextField(JSONObject fields, String fieldName, String fallback) {
        if (fields == null) return fallback;
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return fallback;
        String stringValue = field.optString("stringValue", "");
        if (!TextUtils.isEmpty(stringValue)) return stringValue;
        String integerValue = field.optString("integerValue", "");
        if (!TextUtils.isEmpty(integerValue)) return integerValue;
        String doubleValue = field.optString("doubleValue", "");
        if (!TextUtils.isEmpty(doubleValue)) return doubleValue;
        return fallback;
    }

    private static String readBankDisplayField(JSONObject fields) {
        if (fields == null) return ProductSummary.DEFAULT_BANK_DISPLAY_NAME;
        String direct =
                readTextField(fields, "bankDisplayName", ProductSummary.DEFAULT_BANK_DISPLAY_NAME);
        String bankNameTh = readTextField(fields, "bankNameTh", "");
        String bankNameEn = readTextField(fields, "bankNameEn", "");
        if (!TextUtils.isEmpty(bankNameTh) && !TextUtils.isEmpty(bankNameEn)) {
            return bankNameTh + " ( " + bankNameEn + " )";
        }
        if (!TextUtils.isEmpty(bankNameTh)) {
            return bankNameTh;
        }
        if (!TextUtils.isEmpty(bankNameEn)) {
            return bankNameEn;
        }
        return direct;
    }

    private static String readPreferredBankDisplayField(
            JSONObject preferredFields, JSONObject fallbackFields) {
        if (preferredFields != null) {
            String preferredDirect = readTextField(preferredFields, "bankDisplayName", "");
            String preferredTh = readTextField(preferredFields, "bankNameTh", "");
            String preferredEn = readTextField(preferredFields, "bankNameEn", "");
            if (!TextUtils.isEmpty(preferredDirect)
                    || !TextUtils.isEmpty(preferredTh)
                    || !TextUtils.isEmpty(preferredEn)) {
                return readBankDisplayField(preferredFields);
            }
        }
        return readBankDisplayField(fallbackFields);
    }

    private static long readLongField(JSONObject fields, String fieldName, long fallback) {
        if (fields == null) return fallback;
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return fallback;
        String integerValue = field.optString("integerValue", "");
        if (!TextUtils.isEmpty(integerValue)) {
            try {
                return Long.parseLong(integerValue);
            } catch (Exception ignored) {
            }
        }
        String doubleValue = field.optString("doubleValue", "");
        if (!TextUtils.isEmpty(doubleValue)) {
            try {
                return Math.round(Double.parseDouble(doubleValue));
            } catch (Exception ignored) {
            }
        }
        return fallback;
    }

    private static boolean readBooleanField(JSONObject fields, String fieldName, boolean fallback) {
        if (fields == null) return fallback;
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return fallback;
        if (field.has("booleanValue")) {
            return field.optBoolean("booleanValue", fallback);
        }
        String stringValue = field.optString("stringValue", "");
        if (!TextUtils.isEmpty(stringValue)) {
            if ("true".equalsIgnoreCase(stringValue)) return true;
            if ("false".equalsIgnoreCase(stringValue)) return false;
        }
        return fallback;
    }

    private static String readResponse(HttpURLConnection connection) throws Exception {
        if (connection.getErrorStream() == null && connection.getInputStream() == null) {
            return "";
        }
        BufferedReader reader =
                new BufferedReader(
                        new InputStreamReader(
                                connection.getResponseCode() >= 400
                                        ? connection.getErrorStream()
                                        : connection.getInputStream(),
                                StandardCharsets.UTF_8));
        StringBuilder builder = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) {
            builder.append(line);
        }
        reader.close();
        return builder.toString();
    }

    static final class ProductSummary {
        static final String DEFAULT_NAME = "แพ็กเกจ GO_PLAY 30 วัน";
        static final long DEFAULT_PRICE = 599L;
        static final String DEFAULT_CURRENCY = "THB";
        static final int DEFAULT_DURATION_DAYS = 30;
        static final String DEFAULT_BANK_DISPLAY_NAME = "กสิกรไทย ( K BANK )";
        static final String DEFAULT_ACCOUNT_NAME_EN = "YAKSA TRADING LIMITED";
        static final String DEFAULT_ACCOUNT_NAME_TH = "บจก. ยักษ์ษา เทรดดิ้ง";
        static final String DEFAULT_ACCOUNT_NUMBER = "2008395414";

        final String packageId;
        final String name;
        final long price;
        final String currency;
        final int durationDays;
        final String bankDisplayName;
        final String accountNameEn;
        final String accountNameTh;
        final String accountNumber;
        final boolean available;

        ProductSummary(
                String packageId,
                String name,
                long price,
                String currency,
                int durationDays,
                String bankDisplayName,
                String accountNameEn,
                String accountNameTh,
                String accountNumber,
                boolean available) {
            this.packageId = packageId;
            this.name = name;
            this.price = price;
            this.currency = currency;
            this.durationDays = durationDays;
            this.bankDisplayName = bankDisplayName;
            this.accountNameEn = accountNameEn;
            this.accountNameTh = accountNameTh;
            this.accountNumber = accountNumber;
            this.available = available;
        }

        static ProductSummary fallback(String packageId) {
            long price = DEFAULT_PRICE;
            int durationDays = DEFAULT_DURATION_DAYS;
            String name = DEFAULT_NAME;
            if ("pkg_01".equals(packageId)) {
                price = 99L;
                durationDays = 30;
                name = "แพ็กเกจ GO_PLAY 30 วัน";
            } else if ("pkg_02".equals(packageId)) {
                price = 199L;
                durationDays = 90;
                name = "แพ็กเกจ GO_PLAY 90 วัน";
            } else if ("pkg_03".equals(packageId)) {
                price = 599L;
                durationDays = 365;
                name = "แพ็กเกจ GO_PLAY 365 วัน";
            }
            return new ProductSummary(
                    packageId,
                    name,
                    price,
                    DEFAULT_CURRENCY,
                    durationDays,
                    DEFAULT_BANK_DISPLAY_NAME,
                    DEFAULT_ACCOUNT_NAME_EN,
                    DEFAULT_ACCOUNT_NAME_TH,
                    DEFAULT_ACCOUNT_NUMBER,
                    true);
        }
    }

    static final class OrderResult {
        final String orderId;
        final String storagePath;
        final String uploadUrl;
        final String currency;
        final long expectedAmount;
        final int durationDays;
        final String expiresAt;

        OrderResult(
                String orderId,
                String storagePath,
                String uploadUrl,
                String currency,
                long expectedAmount,
                int durationDays,
                String expiresAt) {
            this.orderId = orderId;
            this.storagePath = storagePath;
            this.uploadUrl = uploadUrl;
            this.currency = currency;
            this.expectedAmount = expectedAmount;
            this.durationDays = durationDays;
            this.expiresAt = expiresAt;
        }
    }

    static final class CallableResult {
        final boolean success;
        final OrderResult orderResult;
        final String message;

        private CallableResult(boolean success, OrderResult orderResult, String message) {
            this.success = success;
            this.orderResult = orderResult;
            this.message = message;
        }

        static CallableResult success(OrderResult orderResult) {
            return new CallableResult(true, orderResult, "");
        }

        static CallableResult error(String message) {
            return new CallableResult(false, null, message);
        }
    }

    static final class VerifyResult {
        final boolean success;
        final String status;
        final String orderId;
        final String packageId;
        final String paymentRef;
        final String currency;
        final long expectedAmount;
        final long amountInSlip;
        final int durationDays;
        final boolean alreadyProcessed;
        final String expiresAt;
        final String message;

        private VerifyResult(
                boolean success,
                String status,
                String orderId,
                String packageId,
                String paymentRef,
                String currency,
                long expectedAmount,
                long amountInSlip,
                int durationDays,
                boolean alreadyProcessed,
                String expiresAt,
                String message) {
            this.success = success;
            this.status = status;
            this.orderId = orderId;
            this.packageId = packageId;
            this.paymentRef = paymentRef;
            this.currency = currency;
            this.expectedAmount = expectedAmount;
            this.amountInSlip = amountInSlip;
            this.durationDays = durationDays;
            this.alreadyProcessed = alreadyProcessed;
            this.expiresAt = expiresAt;
            this.message = message;
        }

        static VerifyResult success(
                String status,
                String orderId,
                String packageId,
                String paymentRef,
                String currency,
                long expectedAmount,
                long amountInSlip,
                int durationDays,
                boolean alreadyProcessed,
                String expiresAt) {
            return new VerifyResult(
                    true,
                    status,
                    orderId,
                    packageId,
                    paymentRef,
                    currency,
                    expectedAmount,
                    amountInSlip,
                    durationDays,
                    alreadyProcessed,
                    expiresAt,
                    "");
        }

        static VerifyResult error(String message) {
            return new VerifyResult(false, "", "", "", "", "", 0L, 0L, 0, false, "", message);
        }
    }

    public static final class AccessStateResult {
        public final boolean success;
        public final boolean allowed;
        public final boolean serviceUnavailable;
        public final String status;
        public final int remainingDays;
        public final String packageId;
        public final String expiresAt;
        public final String message;

        private AccessStateResult(
                boolean success,
                boolean allowed,
                boolean serviceUnavailable,
                String status,
                int remainingDays,
                String packageId,
                String expiresAt,
                String message) {
            this.success = success;
            this.allowed = allowed;
            this.serviceUnavailable = serviceUnavailable;
            this.status = status;
            this.remainingDays = remainingDays;
            this.packageId = packageId;
            this.expiresAt = expiresAt;
            this.message = message;
        }

        public static AccessStateResult success(
                boolean allowed,
                String status,
                int remainingDays,
                String packageId,
                String expiresAt,
                String message) {
            return new AccessStateResult(
                    true,
                    allowed,
                    false,
                    status,
                    remainingDays,
                    packageId,
                    expiresAt,
                    message);
        }

        public static AccessStateResult error(String message) {
            return new AccessStateResult(false, false, false, "", -1, "", "", message);
        }

        public static AccessStateResult unavailable(String message) {
            return new AccessStateResult(false, false, true, "", -1, "", "", message);
        }
    }

    private static final class PurchaseException extends Exception {
        final String message;

        PurchaseException(String message) {
            super(message);
            this.message = message;
        }
    }
}
