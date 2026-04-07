package org.chromium.chrome.browser.onetabauth;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.text.TextUtils;

import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONObject;

import org.chromium.base.Log;
import org.chromium.net.ChromiumNetworkAdapter;
import org.chromium.net.NetworkTrafficAnnotationTag;

import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.HashSet;
import java.util.Set;

final class OneTabAppUpdateManager {
    interface ProgressCallback {
        void onProgress(long bytesDownloaded, long totalBytes);
    }

    static final String INSTALL_STATUS_ACTION =
            "org.chromium.chrome.browser.onetabauth.action.APP_UPDATE_INSTALL_STATUS";

    private static final String TAG = "OneTabUpdater";
    private static final String UPDATES_DIR_NAME = "updates";
    private static final String APK_FILE_NAME = "app-update.apk";
    private static final String APK_PART_SUFFIX = ".part";
    private static final long MIN_FREE_SPACE_BUFFER_BYTES = 32L * 1024L * 1024L;
    private static final int CONNECT_TIMEOUT_MS = 15000;
    private static final int READ_TIMEOUT_MS = 60000;
    private static final NetworkTrafficAnnotationTag UPDATE_TRAFFIC_ANNOTATION =
            NetworkTrafficAnnotationTag.MISSING_TRAFFIC_ANNOTATION;

    private final Context mContext;
    private final PackageManager mPackageManager;
    private final OneTabAppUpdateStore mStore = new OneTabAppUpdateStore();

    OneTabAppUpdateManager(Context context) {
        mContext = context.getApplicationContext();
        mPackageManager = mContext.getPackageManager();
    }

    InstalledVersionInfo readInstalledVersionInfo() {
        try {
            PackageInfo packageInfo = mPackageManager.getPackageInfo(mContext.getPackageName(), 0);
            return new InstalledVersionInfo(
                    mContext.getPackageName(),
                    packageInfo.versionName,
                    getLongVersionCode(packageInfo));
        } catch (Exception e) {
            Log.e(TAG, "readInstalledVersionInfo exception=%s", e.getMessage());
            return new InstalledVersionInfo(mContext.getPackageName(), "", 0L);
        }
    }

    PreparedUpdateState inspectPreparedUpdate(@androidx.annotation.Nullable OneTabAppUpdateManifest manifest) {
        if (manifest == null) {
            return PreparedUpdateState.notReady();
        }

        try {
            OneTabAppUpdateStore.PendingInstall pendingInstall = mStore.readPendingInstall();
            if (pendingInstall.isValid()) {
                if (pendingInstall.versionCode != manifest.latestVersionCode) {
                    mStore.clearPendingInstall();
                } else {
                    File pendingFile = new File(pendingInstall.apkPath);
                    if (!pendingFile.exists()) {
                        mStore.clearPendingInstall();
                    } else {
                        ValidationResult pendingValidation =
                                validateDownloadedApk(pendingFile, manifest);
                        if (pendingValidation.success) {
                            boolean waitingForUnknownSources =
                                    pendingInstall.awaitingUnknownSourcesPermission
                                            && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                                            && !mPackageManager.canRequestPackageInstalls();
                            if (!waitingForUnknownSources
                                    && pendingInstall.awaitingUnknownSourcesPermission) {
                                mStore.updatePendingInstallPermissionState(false);
                            }
                            return PreparedUpdateState.ready(
                                    pendingFile, waitingForUnknownSources);
                        }
                        mStore.clearPendingInstall();
                    }
                }
            }

            OneTabAppUpdateStore.CachedApk cachedApk = mStore.readCachedApk();
            if (!cachedApk.isValid()) {
                return PreparedUpdateState.notReady();
            }
            if (cachedApk.versionCode != manifest.latestVersionCode) {
                mStore.clearCachedApk();
                return PreparedUpdateState.notReady();
            }

            File cachedFile = new File(cachedApk.apkPath);
            if (!cachedFile.exists()) {
                mStore.clearCachedApk();
                return PreparedUpdateState.notReady();
            }

            ValidationResult cachedValidation = validateDownloadedApk(cachedFile, manifest);
            if (!cachedValidation.success
                    || !TextUtils.equals(cachedApk.sha256, cachedValidation.sha256)) {
                mStore.clearCachedApk();
                return PreparedUpdateState.notReady();
            }
            return PreparedUpdateState.ready(cachedFile, false);
        } catch (Exception e) {
            Log.e(TAG, "inspectPreparedUpdate exception=%s", e.getMessage());
            return PreparedUpdateState.notReady();
        }
    }

    UpdateCheckResult fetchUpdateInfo(String idToken, String appCheckToken) {
        InstalledVersionInfo installedVersion = readInstalledVersionInfo();
        try {
            JSONObject fields =
                    fetchDocumentFields(idToken, appCheckToken, OneTabAppUpdateManifest.DOC_PATH);
            if (fields == null) {
                return UpdateCheckResult.error(installedVersion, "ยังไม่พบข้อมูลอัปเดตใน Firestore");
            }

            OneTabAppUpdateManifest manifest =
                    OneTabAppUpdateManifest.fromFirestoreFields(fields, installedVersion.packageName);
            if (!TextUtils.equals(installedVersion.packageName, manifest.appId)) {
                return UpdateCheckResult.error(installedVersion, "การตั้งค่าอัปเดตไม่ตรงกับแอปนี้");
            }
            if (!manifest.updaterEnabled) {
                return UpdateCheckResult.noUpdate(installedVersion, manifest, "ยังไม่เปิดให้อัปเดตในขณะนี้");
            }
            if (installedVersion.versionCode > manifest.latestVersionCode) {
                return UpdateCheckResult.noUpdate(
                        installedVersion, manifest, "เวอร์ชันนี้ใหม่กว่าชุดอัปเดตที่ปล่อยไว้");
            }
            if (installedVersion.versionCode == manifest.latestVersionCode) {
                return UpdateCheckResult.noUpdate(installedVersion, manifest, "แอปเป็นเวอร์ชันล่าสุดแล้ว");
            }
            if (!passesRollout(manifest.rolloutPercent)) {
                return UpdateCheckResult.noUpdate(
                        installedVersion, manifest, "รอบอัปเดตนี้ยังไม่เปิดให้อุปกรณ์นี้");
            }

            boolean minimumUnsupported =
                    manifest.minimumSupportedVersionCode > 0L
                            && installedVersion.versionCode < manifest.minimumSupportedVersionCode;
            String message =
                    minimumUnsupported
                            ? "เวอร์ชันนี้ไม่ได้รับการรองรับแล้ว ต้องอัปเดตก่อนใช้งานต่อ"
                            : (manifest.forceUpdate
                                    ? "มีอัปเดตสำคัญแนะนำให้ติดตั้งทันที"
                                    : "พบเวอร์ชันใหม่พร้อมให้อัปเดต");
            return UpdateCheckResult.available(
                    installedVersion,
                    manifest,
                    manifest.forceUpdate || minimumUnsupported,
                    minimumUnsupported,
                    message);
        } catch (OneTabAppUpdateManifest.ParseException e) {
            return UpdateCheckResult.error(installedVersion, e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "fetchUpdateInfo exception=%s", e.getMessage());
            return UpdateCheckResult.error(installedVersion, "ยังตรวจสอบข้อมูลอัปเดตไม่ได้");
        }
    }

    PreparedUpdateResult prepareUpdate(
            OneTabAppUpdateManifest manifest, ProgressCallback progressCallback) {
        try {
            cleanupUpdateCache(manifest.latestVersionCode);

            OneTabAppUpdateStore.CachedApk cachedApk = mStore.readCachedApk();
            if (cachedApk.isValid() && cachedApk.versionCode == manifest.latestVersionCode) {
                File cachedFile = new File(cachedApk.apkPath);
                ValidationResult cachedValidation = validateDownloadedApk(cachedFile, manifest);
                if (cachedValidation.success) {
                    return PreparedUpdateResult.success(cachedFile, manifest, true);
                }
            }

            File versionDir = resolveVersionDirectory(manifest.latestVersionCode);
            if (!versionDir.exists() && !versionDir.mkdirs()) {
                return PreparedUpdateResult.error("ยังเตรียมพื้นที่อัปเดตไม่ได้");
            }
            File targetFile = new File(versionDir, APK_FILE_NAME);
            File partFile = new File(versionDir, APK_FILE_NAME + APK_PART_SUFFIX);
            ensureEnoughDiskSpace(manifest.apkFileSizeBytes);
            if (partFile.exists()) {
                Files.delete(partFile.toPath());
            }

            HttpURLConnection connection = null;
            try {
                connection =
                        (HttpURLConnection)
                                ChromiumNetworkAdapter.openConnection(
                                        new URL(manifest.apkUrl), UPDATE_TRAFFIC_ANNOTATION);
                connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
                connection.setReadTimeout(READ_TIMEOUT_MS);
                connection.setRequestMethod("GET");
                connection.setRequestProperty("Accept", "application/octet-stream");

                int responseCode = connection.getResponseCode();
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    String responseBody = readResponse(connection);
                    Log.w(TAG, "prepareUpdate download failed code=%d body=%s", responseCode, responseBody);
                    return PreparedUpdateResult.error("ยังดาวน์โหลดไฟล์อัปเดตไม่ได้");
                }

                long totalBytes =
                        manifest.apkFileSizeBytes > 0L
                                ? manifest.apkFileSizeBytes
                                : connection.getContentLengthLong();
                try (BufferedInputStream inputStream =
                                new BufferedInputStream(connection.getInputStream());
                        FileOutputStream outputStream = new FileOutputStream(partFile)) {
                    byte[] buffer = new byte[32 * 1024];
                    long downloadedBytes = 0L;
                    int read;
                    while ((read = inputStream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, read);
                        downloadedBytes += read;
                        if (progressCallback != null) {
                            progressCallback.onProgress(downloadedBytes, totalBytes);
                        }
                    }
                    outputStream.flush();
                }
            } finally {
                if (connection != null) connection.disconnect();
            }

            if (targetFile.exists()) {
                Files.delete(targetFile.toPath());
            }
            Files.move(partFile.toPath(), targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);

            ValidationResult validation = validateDownloadedApk(targetFile, manifest);
            if (!validation.success) {
                if (targetFile.exists()) {
                    Files.delete(targetFile.toPath());
                }
                mStore.clearCachedApk();
                return PreparedUpdateResult.error(validation.message);
            }

            mStore.saveCachedApk(targetFile.getAbsolutePath(), manifest.latestVersionCode, validation.sha256);
            return PreparedUpdateResult.success(targetFile, manifest, false);
        } catch (UpdateException e) {
            return PreparedUpdateResult.error(e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "prepareUpdate exception=%s", e.getMessage());
            return PreparedUpdateResult.error("ยังเตรียมไฟล์อัปเดตไม่ได้");
        }
    }

    InstallRequestResult requestInstall(
            AppCompatActivity activity, File apkFile, long versionCode, String versionName) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    && !mPackageManager.canRequestPackageInstalls()) {
                mStore.savePendingInstall(apkFile.getAbsolutePath(), versionCode, versionName, true);
                Intent intent =
                        new Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:" + mContext.getPackageName()));
                activity.startActivity(intent);
                return InstallRequestResult.permissionRequired(
                        "กรุณาอนุญาตให้ GO_PLAY ติดตั้งแอปจากแหล่งนี้ก่อน");
            }

            streamApkIntoInstaller(activity, apkFile, versionCode, versionName);
            return InstallRequestResult.dispatched("เริ่มส่งไฟล์อัปเดตเข้าสู่ระบบติดตั้งแล้ว");
        } catch (Exception e) {
            Log.e(TAG, "requestInstall exception=%s", e.getMessage());
            return InstallRequestResult.error("ยังเริ่มการติดตั้งอัปเดตไม่ได้");
        }
    }

    ResumeInstallResult resumePendingInstallIfPossible(AppCompatActivity activity) {
        OneTabAppUpdateStore.PendingInstall pendingInstall = mStore.readPendingInstall();
        if (!pendingInstall.isValid()) {
            return ResumeInstallResult.nothingToResume();
        }
        File apkFile = new File(pendingInstall.apkPath);
        if (!apkFile.exists()) {
            mStore.clearPendingInstall();
            return ResumeInstallResult.error("ไฟล์อัปเดตที่รอติดตั้งไม่อยู่แล้ว");
        }
        if (pendingInstall.awaitingUnknownSourcesPermission
                && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !mPackageManager.canRequestPackageInstalls()) {
            return ResumeInstallResult.waitingForPermission(
                    "กรุณาอนุญาตการติดตั้งก่อนจึงจะอัปเดตต่อได้");
        }
        InstallRequestResult result =
                requestInstall(activity, apkFile, pendingInstall.versionCode, pendingInstall.versionName);
        if (result.success) {
            return ResumeInstallResult.resumed(result.message);
        }
        return ResumeInstallResult.error(result.message);
    }

    InstallStatusResult consumeInstallStatusIntent(AppCompatActivity activity, Intent intent) {
        if (!TextUtils.equals(INSTALL_STATUS_ACTION, intent.getAction())) {
            return InstallStatusResult.notHandled();
        }
        int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
        String statusMessage = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            Intent confirmIntent = intent.getParcelableExtra(Intent.EXTRA_INTENT);
            if (confirmIntent != null) {
                activity.startActivity(confirmIntent);
                mStore.updatePendingInstallPermissionState(false);
                return InstallStatusResult.pendingUserAction("ระบบกำลังรอให้ยืนยันการติดตั้ง");
            }
            return InstallStatusResult.error("ยังเปิดหน้ายืนยันการติดตั้งไม่ได้");
        }
        if (status == PackageInstaller.STATUS_SUCCESS) {
            mStore.clearPendingInstall();
            return InstallStatusResult.success("อัปเดตแอปสำเร็จแล้ว");
        }
        if (status == PackageInstaller.STATUS_FAILURE_ABORTED) {
            return InstallStatusResult.error("ยกเลิกการติดตั้งอัปเดตแล้ว");
        }
        if (status == PackageInstaller.STATUS_FAILURE_BLOCKED) {
            return InstallStatusResult.error("ระบบบล็อกการติดตั้ง กรุณาตรวจสอบสิทธิ์การติดตั้ง");
        }
        String message = !TextUtils.isEmpty(statusMessage) ? statusMessage : "ติดตั้งอัปเดตไม่สำเร็จ";
        return InstallStatusResult.error(message);
    }

    private JSONObject fetchDocumentFields(String idToken, String appCheckToken, String documentPath) {
        HttpURLConnection connection = null;
        try {
            connection =
                    (HttpURLConnection)
                            ChromiumNetworkAdapter.openConnection(
                                    new URL(
                                            OneTabFirebaseAuthConfig.FIRESTORE_BASE_URL
                                                    + "/"
                                                    + documentPath),
                                    UPDATE_TRAFFIC_ANNOTATION);
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("Authorization", "Bearer " + idToken);
            if (!TextUtils.isEmpty(appCheckToken)) {
                connection.setRequestProperty("X-Firebase-AppCheck", appCheckToken);
            }

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

    private boolean passesRollout(long rolloutPercent) {
        if (rolloutPercent >= 100L) return true;
        if (rolloutPercent <= 0L) return false;
        String installationId = mStore.getInstallationId();
        long normalizedBucket = Math.abs((long) installationId.hashCode()) % 100L;
        return normalizedBucket < rolloutPercent;
    }

    private File resolveVersionDirectory(long versionCode) {
        return new File(mContext.getCacheDir(), UPDATES_DIR_NAME + File.separator + versionCode);
    }

    private void cleanupUpdateCache(long keepVersionCode) throws Exception {
        File rootDir = new File(mContext.getCacheDir(), UPDATES_DIR_NAME);
        if (!rootDir.exists()) return;
        File[] children = rootDir.listFiles();
        if (children == null) return;
        for (File child : children) {
            if (!child.isDirectory()) {
                Files.deleteIfExists(child.toPath());
                continue;
            }
            if (TextUtils.equals(child.getName(), String.valueOf(keepVersionCode))) {
                continue;
            }
            deleteRecursively(child);
        }
    }

    private void ensureEnoughDiskSpace(long expectedBytes) throws UpdateException {
        long requiredBytes = MIN_FREE_SPACE_BUFFER_BYTES;
        if (expectedBytes > 0L) {
            requiredBytes += expectedBytes;
        }
        long usableBytes = mContext.getCacheDir().getUsableSpace();
        if (usableBytes < requiredBytes) {
            throw new UpdateException("พื้นที่ไม่พอสำหรับอัปเดตแอป");
        }
    }

    private ValidationResult validateDownloadedApk(File apkFile, OneTabAppUpdateManifest manifest) {
        try {
            if (apkFile == null || !apkFile.exists() || apkFile.length() <= 0L) {
                return ValidationResult.error("ไม่พบไฟล์ APK สำหรับติดตั้ง");
            }
            if (manifest.apkFileSizeBytes > 0L && apkFile.length() != manifest.apkFileSizeBytes) {
                return ValidationResult.error("ขนาดไฟล์อัปเดตไม่ตรงกับข้อมูลที่ประกาศไว้");
            }

            String fileSha256 = computeFileSha256(apkFile);
            if (!TextUtils.equals(fileSha256, manifest.apkSha256)) {
                return ValidationResult.error("ค่า SHA-256 ของไฟล์อัปเดตไม่ตรงกับการตั้งค่า");
            }

            int archiveFlags =
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                            ? PackageManager.GET_SIGNING_CERTIFICATES
                            : PackageManager.GET_SIGNATURES;
            PackageInfo archiveInfo =
                    mPackageManager.getPackageArchiveInfo(apkFile.getAbsolutePath(), archiveFlags);
            if (archiveInfo == null) {
                return ValidationResult.error("ไม่สามารถอ่านรายละเอียด APK ที่ดาวน์โหลดได้");
            }
            if (!TextUtils.equals(mContext.getPackageName(), archiveInfo.packageName)) {
                return ValidationResult.error("package ของไฟล์อัปเดตไม่ตรงกับแอปนี้");
            }

            long archiveVersionCode = getLongVersionCode(archiveInfo);
            InstalledVersionInfo installedVersion = readInstalledVersionInfo();
            if (archiveVersionCode <= installedVersion.versionCode) {
                return ValidationResult.error("ไฟล์อัปเดตมีเวอร์ชันไม่ใหม่กว่าที่ติดตั้งอยู่");
            }
            if (archiveVersionCode != manifest.latestVersionCode) {
                return ValidationResult.error("versionCode ของ APK อัปเดตไม่ตรงกับ metadata");
            }

            PackageInfo installedPackageInfo =
                    mPackageManager.getPackageInfo(mContext.getPackageName(), archiveFlags);
            if (!areSigningCertificatesCompatible(installedPackageInfo, archiveInfo)) {
                return ValidationResult.error("ลายเซ็นของ APK อัปเดตไม่ตรงกับแอปปัจจุบัน");
            }

            return ValidationResult.success(fileSha256);
        } catch (Exception e) {
            Log.e(TAG, "validateDownloadedApk exception=%s", e.getMessage());
            return ValidationResult.error("ยังตรวจสอบ APK อัปเดตไม่ได้");
        }
    }

    private boolean areSigningCertificatesCompatible(PackageInfo installedInfo, PackageInfo archiveInfo)
            throws Exception {
        Set<String> installedDigests = extractSignatureDigests(installedInfo);
        Set<String> archiveDigests = extractSignatureDigests(archiveInfo);
        if (installedDigests.isEmpty() || archiveDigests.isEmpty()) return false;
        return installedDigests.equals(archiveDigests);
    }

    private Set<String> extractSignatureDigests(PackageInfo packageInfo) throws Exception {
        Set<String> digests = new HashSet<>();
        if (packageInfo == null) return digests;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            SigningInfo signingInfo = packageInfo.signingInfo;
            if (signingInfo != null) {
                Signature[] signatures = signingInfo.getApkContentsSigners();
                if (signatures == null || signatures.length == 0) {
                    signatures = signingInfo.getSigningCertificateHistory();
                }
                addSignatureDigests(digests, signatures);
                return digests;
            }
        }
        addSignatureDigests(digests, packageInfo.signatures);
        return digests;
    }

    private void addSignatureDigests(Set<String> digests, Signature[] signatures) throws Exception {
        if (signatures == null) return;
        for (Signature signature : signatures) {
            if (signature == null) continue;
            digests.add(computeSha256(signature.toByteArray()));
        }
    }

    private void streamApkIntoInstaller(
            AppCompatActivity activity, File apkFile, long versionCode, String versionName)
            throws Exception {
        PackageInstaller packageInstaller = mPackageManager.getPackageInstaller();
        PackageInstaller.SessionParams params =
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        params.setAppPackageName(mContext.getPackageName());
        params.setSize(apkFile.length());
        int sessionId = packageInstaller.createSession(params);
        PackageInstaller.Session session = null;
        try {
            session = packageInstaller.openSession(sessionId);
            try (OutputStream outputStream = session.openWrite("base.apk", 0, apkFile.length());
                    FileInputStream inputStream = new FileInputStream(apkFile)) {
                byte[] buffer = new byte[32 * 1024];
                int read;
                while ((read = inputStream.read(buffer)) != -1) {
                    outputStream.write(buffer, 0, read);
                }
                session.fsync(outputStream);
            }

            int pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                pendingIntentFlags |= PendingIntent.FLAG_MUTABLE;
            }
            Intent statusIntent =
                    new Intent(activity, OneTabAccountActivity.class)
                            .setAction(INSTALL_STATUS_ACTION)
                            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pendingIntent =
                    PendingIntent.getActivity(
                            activity,
                            (int) (versionCode % Integer.MAX_VALUE),
                            statusIntent,
                            pendingIntentFlags);
            mStore.savePendingInstall(apkFile.getAbsolutePath(), versionCode, versionName, false);
            session.commit(pendingIntent.getIntentSender());
        } catch (Exception e) {
            if (session != null) {
                try {
                    session.abandon();
                } catch (Exception ignored) {
                }
            }
            throw e;
        } finally {
            if (session != null) {
                try {
                    session.close();
                } catch (Exception ignored) {
                }
            }
        }
    }

    private static long getLongVersionCode(PackageInfo packageInfo) {
        if (packageInfo == null) return 0L;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return packageInfo.getLongVersionCode();
        }
        return packageInfo.versionCode;
    }

    private static String computeFileSha256(File file) throws Exception {
        try (FileInputStream inputStream = new FileInputStream(file)) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[32 * 1024];
            int read;
            while ((read = inputStream.read(buffer)) != -1) {
                digest.update(buffer, 0, read);
            }
            return toHexString(digest.digest());
        }
    }

    private static String computeSha256(byte[] bytes) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        digest.update(bytes);
        return toHexString(digest.digest());
    }

    private static String toHexString(byte[] bytes) {
        StringBuilder builder = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            builder.append(String.format("%02x", value));
        }
        return builder.toString();
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

    private static void deleteRecursively(File file) throws Exception {
        if (file == null || !file.exists()) return;
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) {
                deleteRecursively(child);
            }
        }
        Files.deleteIfExists(file.toPath());
    }

    static final class InstalledVersionInfo {
        final String packageName;
        final String versionName;
        final long versionCode;

        InstalledVersionInfo(String packageName, String versionName, long versionCode) {
            this.packageName = packageName;
            this.versionName = versionName;
            this.versionCode = versionCode;
        }

        String toDisplayString() {
            if (TextUtils.isEmpty(versionName) || versionCode <= 0L) {
                return "ไม่ทราบเวอร์ชัน";
            }
            return versionName + " (" + versionCode + ")";
        }
    }

    static final class UpdateCheckResult {
        final boolean success;
        final boolean updateAvailable;
        final boolean forceUpdate;
        final boolean minimumUnsupported;
        final String message;
        final InstalledVersionInfo installedVersion;
        final OneTabAppUpdateManifest manifest;

        private UpdateCheckResult(
                boolean success,
                boolean updateAvailable,
                boolean forceUpdate,
                boolean minimumUnsupported,
                String message,
                InstalledVersionInfo installedVersion,
                OneTabAppUpdateManifest manifest) {
            this.success = success;
            this.updateAvailable = updateAvailable;
            this.forceUpdate = forceUpdate;
            this.minimumUnsupported = minimumUnsupported;
            this.message = message;
            this.installedVersion = installedVersion;
            this.manifest = manifest;
        }

        static UpdateCheckResult available(
                InstalledVersionInfo installedVersion,
                OneTabAppUpdateManifest manifest,
                boolean forceUpdate,
                boolean minimumUnsupported,
                String message) {
            return new UpdateCheckResult(
                    true, true, forceUpdate, minimumUnsupported, message, installedVersion, manifest);
        }

        static UpdateCheckResult noUpdate(
                InstalledVersionInfo installedVersion,
                OneTabAppUpdateManifest manifest,
                String message) {
            return new UpdateCheckResult(
                    true, false, false, false, message, installedVersion, manifest);
        }

        static UpdateCheckResult error(InstalledVersionInfo installedVersion, String message) {
            return new UpdateCheckResult(
                    false, false, false, false, message, installedVersion, null);
        }
    }

    static final class PreparedUpdateResult {
        final boolean success;
        final File apkFile;
        final OneTabAppUpdateManifest manifest;
        final boolean reusedCachedFile;
        final String message;

        private PreparedUpdateResult(
                boolean success,
                File apkFile,
                OneTabAppUpdateManifest manifest,
                boolean reusedCachedFile,
                String message) {
            this.success = success;
            this.apkFile = apkFile;
            this.manifest = manifest;
            this.reusedCachedFile = reusedCachedFile;
            this.message = message;
        }

        static PreparedUpdateResult success(
                File apkFile, OneTabAppUpdateManifest manifest, boolean reusedCachedFile) {
            return new PreparedUpdateResult(true, apkFile, manifest, reusedCachedFile, "");
        }

        static PreparedUpdateResult error(String message) {
            return new PreparedUpdateResult(false, null, null, false, message);
        }
    }

    static final class PreparedUpdateState {
        final boolean readyToInstall;
        final File apkFile;
        final boolean awaitingUnknownSourcesPermission;

        private PreparedUpdateState(
                boolean readyToInstall, File apkFile, boolean awaitingUnknownSourcesPermission) {
            this.readyToInstall = readyToInstall;
            this.apkFile = apkFile;
            this.awaitingUnknownSourcesPermission = awaitingUnknownSourcesPermission;
        }

        static PreparedUpdateState ready(
                File apkFile, boolean awaitingUnknownSourcesPermission) {
            return new PreparedUpdateState(true, apkFile, awaitingUnknownSourcesPermission);
        }

        static PreparedUpdateState notReady() {
            return new PreparedUpdateState(false, null, false);
        }
    }

    static final class InstallRequestResult {
        final boolean success;
        final boolean permissionRequired;
        final String message;

        private InstallRequestResult(boolean success, boolean permissionRequired, String message) {
            this.success = success;
            this.permissionRequired = permissionRequired;
            this.message = message;
        }

        static InstallRequestResult dispatched(String message) {
            return new InstallRequestResult(true, false, message);
        }

        static InstallRequestResult permissionRequired(String message) {
            return new InstallRequestResult(false, true, message);
        }

        static InstallRequestResult error(String message) {
            return new InstallRequestResult(false, false, message);
        }
    }

    static final class ResumeInstallResult {
        final boolean handled;
        final boolean resumedInstall;
        final boolean waitingForPermission;
        final String message;

        private ResumeInstallResult(
                boolean handled, boolean resumedInstall, boolean waitingForPermission, String message) {
            this.handled = handled;
            this.resumedInstall = resumedInstall;
            this.waitingForPermission = waitingForPermission;
            this.message = message;
        }

        static ResumeInstallResult nothingToResume() {
            return new ResumeInstallResult(false, false, false, "");
        }

        static ResumeInstallResult resumed(String message) {
            return new ResumeInstallResult(true, true, false, message);
        }

        static ResumeInstallResult waitingForPermission(String message) {
            return new ResumeInstallResult(true, false, true, message);
        }

        static ResumeInstallResult error(String message) {
            return new ResumeInstallResult(true, false, false, message);
        }
    }

    static final class InstallStatusResult {
        final boolean handled;
        final boolean waitingForUserAction;
        final boolean installSucceeded;
        final String message;

        private InstallStatusResult(
                boolean handled, boolean waitingForUserAction, boolean installSucceeded, String message) {
            this.handled = handled;
            this.waitingForUserAction = waitingForUserAction;
            this.installSucceeded = installSucceeded;
            this.message = message;
        }

        static InstallStatusResult notHandled() {
            return new InstallStatusResult(false, false, false, "");
        }

        static InstallStatusResult pendingUserAction(String message) {
            return new InstallStatusResult(true, true, false, message);
        }

        static InstallStatusResult success(String message) {
            return new InstallStatusResult(true, false, true, message);
        }

        static InstallStatusResult error(String message) {
            return new InstallStatusResult(true, false, false, message);
        }
    }

    private static final class ValidationResult {
        final boolean success;
        final String message;
        final String sha256;

        private ValidationResult(boolean success, String message, String sha256) {
            this.success = success;
            this.message = message;
            this.sha256 = sha256;
        }

        static ValidationResult success(String sha256) {
            return new ValidationResult(true, "", sha256);
        }

        static ValidationResult error(String message) {
            return new ValidationResult(false, message, "");
        }
    }

    private static final class UpdateException extends Exception {
        UpdateException(String message) {
            super(message);
        }
    }
}
