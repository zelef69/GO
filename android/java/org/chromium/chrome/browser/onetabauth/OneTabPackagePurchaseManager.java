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

final class OneTabPackagePurchaseManager {
    private static final String TAG = "OneTabPurchase";
    static final String PAYMENT_SERVICE_UNAVAILABLE_MESSAGE =
            "Package purchase service is not ready yet. Please contact admin.";
    private static final NetworkTrafficAnnotationTag PURCHASE_TRAFFIC_ANNOTATION =
            NetworkTrafficAnnotationTag.MISSING_TRAFFIC_ANNOTATION;

    ProductSummary fetchProductSummary(String packageId) {
        HttpURLConnection connection = null;
        try {
            connection =
                    (HttpURLConnection)
                            ChromiumNetworkAdapter.openConnection(
                                    new URL(
                                            OneTabFirebaseAuthConfig.FIRESTORE_BASE_URL
                                                    + "/products/"
                                                    + packageId),
                                    PURCHASE_TRAFFIC_ANNOTATION);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Accept", "application/json");

            int responseCode = connection.getResponseCode();
            String responseBody = readResponse(connection);
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "fetchProductSummary failed code=%d body=%s", responseCode, responseBody);
                return ProductSummary.fallback();
            }

            JSONObject fields = new JSONObject(responseBody).optJSONObject("fields");
            if (fields == null) {
                return ProductSummary.fallback();
            }

            return new ProductSummary(
                    readStringField(fields, "name", ProductSummary.DEFAULT_NAME),
                    readLongField(fields, "price", ProductSummary.DEFAULT_PRICE),
                    readStringField(fields, "currency", ProductSummary.DEFAULT_CURRENCY),
                    (int) readLongField(fields, "durationDays", ProductSummary.DEFAULT_DURATION_DAYS));
        } catch (Exception e) {
            Log.e(TAG, "fetchProductSummary exception=%s", e.getMessage());
            return ProductSummary.fallback();
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    CallableResult createPackageOrder(String idToken, String appCheckToken, String packageId) {
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
                return CallableResult.error("Order response was empty.");
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
            return CallableResult.error("Unable to create a package order.");
        }
    }

    String uploadSlipJpeg(String uploadUrl, byte[] jpegBytes) {
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
                return "Unable to upload the slip image.";
            }
            return "";
        } catch (Exception e) {
            Log.e(TAG, "uploadSlipJpeg exception=%s", e.getMessage());
            return "Unable to upload the slip image.";
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    VerifyResult verifyPackageSlip(
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
                return VerifyResult.error("Verification response was empty.");
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
            return VerifyResult.error("Unable to verify the bank slip.");
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
                throw parseCallableError(responseBody, "Request failed.");
            }

            JSONObject response = new JSONObject(responseBody);
            if (response.has("error")) {
                throw parseCallableError(responseBody, "Request failed.");
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
                    return new PurchaseException("Slip verification is pending. Please retry shortly.");
                }
                if ("DUPLICATE_SLIP".equals(code)) {
                    return new PurchaseException("This slip has already been used.");
                }
                if ("AMOUNT_MISMATCH".equals(code)) {
                    return new PurchaseException("Slip amount does not match this package.");
                }
                if ("ACCOUNT_NOT_MATCH".equals(code)) {
                    return new PurchaseException("Slip receiver account does not match the configured account.");
                }
            }
            if (!TextUtils.isEmpty(message)) {
                return new PurchaseException(message);
            }
        } catch (Exception ignored) {
        }
        return new PurchaseException(fallback);
    }

    private static String readStringField(JSONObject fields, String fieldName, String fallback) {
        JSONObject field = fields.optJSONObject(fieldName);
        if (field == null) return fallback;
        return field.optString("stringValue", fallback);
    }

    private static long readLongField(JSONObject fields, String fieldName, long fallback) {
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
        static final String DEFAULT_NAME = "Premium 30 Days";
        static final long DEFAULT_PRICE = 599L;
        static final String DEFAULT_CURRENCY = "THB";
        static final int DEFAULT_DURATION_DAYS = 30;

        final String name;
        final long price;
        final String currency;
        final int durationDays;

        ProductSummary(String name, long price, String currency, int durationDays) {
            this.name = name;
            this.price = price;
            this.currency = currency;
            this.durationDays = durationDays;
        }

        static ProductSummary fallback() {
            return new ProductSummary(DEFAULT_NAME, DEFAULT_PRICE, DEFAULT_CURRENCY, DEFAULT_DURATION_DAYS);
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

    private static final class PurchaseException extends Exception {
        final String message;

        PurchaseException(String message) {
            super(message);
            this.message = message;
        }
    }
}
