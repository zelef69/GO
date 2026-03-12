package com.example.go_play.security

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import com.example.go_play.BuildConfig
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.X509Certificate
import java.security.spec.X509EncodedKeySpec
import java.util.Locale
import org.json.JSONObject

private const val TAG = "GoPlaySecurity"

class SecurityBridge(
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    private val secureRandom = SecureRandom()
    private val keystoreAlias = "go_play_install_attest_key_v1"

    private var cachedConfig: IntegrityConfig? = null

    data class IntegrityConfig(
        val expectedAppId: String,
        val expectedCertSha256: String,
        val expectedBuildFingerprint: String,
        val expectedManifestSentinel: String,
        val pinSetId: String,
        val certificatePinsSha256: List<String>,
    )

    data class SecurityEvaluation(
        val decision: String,
        val reasonCode: String,
        val highRiskSignals: List<String>,
    )

    fun attachToChannel(channel: MethodChannel) {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initializeSecurity" -> {
                val checkpoint = "startup"
                val evaluation = evaluateSecurity(checkpoint = checkpoint, fullScan = true)
                result.success(
                    mapOf(
                        "decision" to evaluation.decision,
                        "reasonCode" to evaluation.reasonCode,
                        "checkpoint" to checkpoint,
                        "highRiskSignals" to evaluation.highRiskSignals,
                    ),
                )
            }

            "runSecurityCheck" -> {
                val checkpoint =
                    (call.argument<String>("checkpoint") ?: "runtime").ifBlank { "runtime" }
                val evaluation = evaluateSecurity(checkpoint = checkpoint, fullScan = false)
                result.success(
                    mapOf(
                        "decision" to evaluation.decision,
                        "reasonCode" to evaluation.reasonCode,
                        "checkpoint" to checkpoint,
                        "highRiskSignals" to evaluation.highRiskSignals,
                    ),
                )
            }

            "getNativeSecrets" -> {
                val config = loadIntegrityConfig()
                if (config == null) {
                    result.success(
                        mapOf(
                            "pinSetId" to "missing",
                            "certificatePinsSha256" to emptyList<String>(),
                            "expectedAppId" to BuildConfig.APPLICATION_ID,
                        ),
                    )
                    return
                }
                result.success(
                    mapOf(
                        "pinSetId" to config.pinSetId,
                        "certificatePinsSha256" to config.certificatePinsSha256,
                        "expectedAppId" to config.expectedAppId,
                    ),
                )
            }

            "buildTrustSignal" -> {
                val nonce = call.argument<String>("nonce").orEmpty()
                val contextLabel = call.argument<String>("context").orEmpty()
                val signal = buildTrustSignal(nonce = nonce, contextLabel = contextLabel)
                result.success(signal)
            }

            else -> result.notImplemented()
        }
    }

    private fun evaluateSecurity(checkpoint: String, fullScan: Boolean): SecurityEvaluation {
        val highRiskSignals = mutableListOf<String>()
        val criticalSignals = mutableListOf<String>()
        val releaseBuild = !BuildConfig.DEBUG

        val config = loadIntegrityConfig()
        if (config == null) {
            criticalSignals += "integrity_config_missing"
        } else {
            if (context.packageName != config.expectedAppId) {
                criticalSignals += "unexpected_package_name"
            }
            if (BuildConfig.APPLICATION_ID != config.expectedAppId) {
                criticalSignals += "unexpected_build_app_id"
            }
            // The sealed build fingerprint is intended for tamper checks in
            // release artifacts. Debug builds frequently differ (version/build
            // type churn during local iteration), so treat this as release-only
            // to avoid false-positive high-risk loops while developing.
            if (releaseBuild && runtimeBuildFingerprint() != config.expectedBuildFingerprint) {
                criticalSignals += "build_fingerprint_mismatch"
            }
            val manifestSentinel = loadManifestSentinel()
            if (manifestSentinel != config.expectedManifestSentinel) {
                criticalSignals += "manifest_sentinel_mismatch"
            }
            val runtimeCert = signingCertSha256()
            if (runtimeCert.isEmpty()) {
                criticalSignals += "signing_cert_unavailable"
            } else {
                val certMatch =
                    SecurityNativeBridge.constantTimeEquals(
                        runtimeCert,
                        config.expectedCertSha256,
                    )
                if (!certMatch) {
                    criticalSignals += "signing_cert_mismatch"
                }
            }
        }

        if (hasInstallerAnomaly()) {
            highRiskSignals += "installer_anomaly"
        }

        val runDebuggerChecks = fullScan || secureRandom.nextBoolean()
        if (runDebuggerChecks) {
            if (isDebuggerAttached() || hasTracerPid() || SecurityNativeBridge.isTracerAttached()) {
                criticalSignals += "debugger_detected"
            }
            if (hasTimingPauseAnomaly()) {
                highRiskSignals += "timing_pause_anomaly"
            }
        }

        val runHookChecks = fullScan || secureRandom.nextBoolean()
        if (runHookChecks) {
            if (hasSuspiciousHooks() || SecurityNativeBridge.hasSuspiciousMaps()) {
                criticalSignals += "hook_framework_detected"
            }
            if (hasFridaServerProcess() || SecurityNativeBridge.scanFridaPorts()) {
                criticalSignals += "frida_detected"
            }
        }

        val runEmulatorChecks = fullScan || secureRandom.nextBoolean()
        if (runEmulatorChecks && isLikelyEmulator()) {
            criticalSignals += "emulator_detected"
        }

        val runRootChecks = fullScan || secureRandom.nextBoolean()
        if (runRootChecks && isLikelyRooted()) {
            if (BuildConfig.SECURITY_BLOCK_ON_ROOT) {
                criticalSignals += "root_detected"
            } else {
                highRiskSignals += "root_detected"
            }
        }

        val blockSignals = mutableListOf<String>()
        if (containsSignal(criticalSignals, "signing_cert_mismatch", BuildConfig.SECURITY_BLOCK_ON_TAMPER)) {
            blockSignals += "signing_cert_mismatch"
        }
        if (containsAnySignal(criticalSignals, listOf("unexpected_package_name", "unexpected_build_app_id", "build_fingerprint_mismatch", "manifest_sentinel_mismatch"), BuildConfig.SECURITY_BLOCK_ON_TAMPER)) {
            blockSignals += "tamper_detected"
        }
        if (containsSignal(criticalSignals, "debugger_detected", BuildConfig.SECURITY_BLOCK_ON_DEBUGGER)) {
            blockSignals += "debugger_detected"
        }
        if (containsAnySignal(criticalSignals, listOf("hook_framework_detected", "frida_detected"), BuildConfig.SECURITY_BLOCK_ON_HOOK)) {
            blockSignals += "hooking_detected"
        }
        if (containsSignal(criticalSignals, "emulator_detected", BuildConfig.SECURITY_BLOCK_ON_EMULATOR)) {
            blockSignals += "emulator_detected"
        }
        if (containsSignal(criticalSignals, "root_detected", BuildConfig.SECURITY_BLOCK_ON_ROOT)) {
            blockSignals += "root_detected"
        }
        if (containsSignal(criticalSignals, "integrity_config_missing", BuildConfig.SECURITY_BLOCK_ON_TAMPER)) {
            blockSignals += "integrity_config_missing"
        }
        if (containsSignal(criticalSignals, "signing_cert_unavailable", BuildConfig.SECURITY_BLOCK_ON_TAMPER)) {
            blockSignals += "signing_cert_unavailable"
        }

        val decision =
            when {
                releaseBuild && blockSignals.isNotEmpty() -> "block"
                criticalSignals.isNotEmpty() || highRiskSignals.isNotEmpty() -> "high_risk"
                else -> "allow"
            }
        val reasonCode =
            when {
                releaseBuild && blockSignals.isNotEmpty() -> blockSignals.first()
                criticalSignals.isNotEmpty() -> criticalSignals.first()
                highRiskSignals.isNotEmpty() -> highRiskSignals.first()
                else -> "ok"
            }
        val mergedSignals = (criticalSignals + highRiskSignals).distinct()
        debugLog("checkpoint=$checkpoint decision=$decision reason=$reasonCode signals=${mergedSignals.joinToString(",")}")
        return SecurityEvaluation(
            decision = decision,
            reasonCode = reasonCode,
            highRiskSignals = mergedSignals,
        )
    }

    private fun containsSignal(signals: List<String>, signal: String, enabled: Boolean): Boolean {
        return enabled && signals.contains(signal)
    }

    private fun containsAnySignal(signals: List<String>, target: List<String>, enabled: Boolean): Boolean {
        if (!enabled) return false
        return target.any(signals::contains)
    }

    private fun loadIntegrityConfig(): IntegrityConfig? {
        cachedConfig?.let { return it }
        val assetName = BuildConfig.SECURITY_INTEGRITY_ASSET_NAME
        if (assetName.isBlank()) {
            return null
        }
        return runCatching {
            val raw = context.assets.open(assetName).bufferedReader().use { it.readText() }
            val root = JSONObject(raw)
            val payloadB64 = root.optString("payload", "")
            val checksum = root.optString("checksum", "")
            if (payloadB64.isBlank() || checksum.isBlank()) {
                return null
            }
            val payloadChecksum = sha256Hex(payloadB64)
            val expectedChecksum = normalizeHex(checksum)
            val sealedChecksum = normalizeHex(BuildConfig.SECURITY_CONFIG_SHA256)
            val checksumMatches =
                SecurityNativeBridge.constantTimeEquals(payloadChecksum, expectedChecksum) &&
                    SecurityNativeBridge.constantTimeEquals(payloadChecksum, sealedChecksum)
            if (!checksumMatches) {
                return null
            }
            val payloadBytes = Base64.decode(payloadB64, Base64.NO_WRAP)
            val payloadJson = JSONObject(String(payloadBytes, Charsets.UTF_8))
            val pinsJson = payloadJson.optJSONArray("certificatePinsSha256")
            val pins = mutableListOf<String>()
            if (pinsJson != null) {
                for (i in 0 until pinsJson.length()) {
                    val value = normalizeHex(pinsJson.optString(i, ""))
                    if (value.isNotEmpty()) {
                        pins += value
                    }
                }
            }
            IntegrityConfig(
                expectedAppId = payloadJson.optString("expectedAppId", ""),
                expectedCertSha256 = normalizeHex(payloadJson.optString("expectedCertSha256", "")),
                expectedBuildFingerprint =
                    normalizeHex(payloadJson.optString("expectedBuildFingerprint", "")),
                expectedManifestSentinel = payloadJson.optString("expectedManifestSentinel", ""),
                pinSetId = payloadJson.optString("pinSetId", ""),
                certificatePinsSha256 = pins.distinct(),
            )
        }.onFailure {
            debugLog("integrity config load failed: ${it.message}")
        }.getOrNull()?.also {
            cachedConfig = it
        }
    }

    private fun runtimeBuildFingerprint(): String {
        val value =
            "${BuildConfig.APPLICATION_ID}|${BuildConfig.VERSION_NAME}|${BuildConfig.VERSION_CODE}|${BuildConfig.BUILD_TYPE}|"
        return sha256Hex(value)
    }

    private fun loadManifestSentinel(): String {
        return runCatching {
            val appInfo =
                context.packageManager.getApplicationInfo(
                    context.packageName,
                    PackageManager.GET_META_DATA,
                )
            appInfo.metaData?.getString("go_play.security.manifest_sentinel").orEmpty()
        }.getOrDefault("")
    }

    private fun hasInstallerAnomaly(): Boolean {
        val installer =
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
                } else {
                    @Suppress("DEPRECATION")
                    context.packageManager.getInstallerPackageName(context.packageName)
                }
            }.getOrNull()

        if (installer.isNullOrBlank()) {
            // Side-loaded APKs usually have no installer package.
            return false
        }
        val trustedInstallers =
            setOf(
                "com.android.vending",
                "com.google.android.packageinstaller",
                "com.android.packageinstaller",
                "com.miui.packageinstaller",
            )
        return installer !in trustedInstallers
    }

    private fun signingCertSha256(): String {
        val certificate = signingCertificate()
        if (certificate == null) {
            return ""
        }
        return normalizeHex(sha256Hex(certificate.encoded))
    }

    private fun signingCertificate(): X509Certificate? {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo =
                    context.packageManager.getPackageInfo(
                        context.packageName,
                        PackageManager.GET_SIGNING_CERTIFICATES,
                    )
                val signingInfo = packageInfo.signingInfo ?: return null
                val signatures =
                    if (signingInfo.hasMultipleSigners()) {
                        signingInfo.apkContentsSigners
                    } else {
                        signingInfo.signingCertificateHistory
                    }
                val firstSignature = signatures?.firstOrNull() ?: return null
                val certFactory = java.security.cert.CertificateFactory.getInstance("X509")
                certFactory.generateCertificate(firstSignature.toByteArray().inputStream()) as X509Certificate
            } else {
                @Suppress("DEPRECATION")
                val packageInfo =
                    context.packageManager.getPackageInfo(
                        context.packageName,
                        PackageManager.GET_SIGNATURES,
                    )
                @Suppress("DEPRECATION")
                val legacySignatures = packageInfo.signatures ?: return null
                @Suppress("DEPRECATION")
                val firstSignature = legacySignatures.firstOrNull() ?: return null
                val certFactory = java.security.cert.CertificateFactory.getInstance("X509")
                @Suppress("DEPRECATION")
                certFactory.generateCertificate(firstSignature.toByteArray().inputStream()) as X509Certificate
            }
        }.onFailure {
            debugLog("signing certificate read failed: ${it.message}")
        }.getOrNull()
    }

    private fun isDebuggerAttached(): Boolean {
        return Debug.isDebuggerConnected() || Debug.waitingForDebugger()
    }

    private fun hasTracerPid(): Boolean {
        val status = runCatching { File("/proc/self/status").readText() }.getOrNull() ?: return false
        val tracerLine =
            status
                .lineSequence()
                .firstOrNull { it.startsWith("TracerPid:") }
                ?: return false
        val tracerPid = tracerLine.substringAfter(':').trim().toIntOrNull() ?: 0
        return tracerPid > 0
    }

    private fun hasTimingPauseAnomaly(): Boolean {
        val start = SystemClock.elapsedRealtimeNanos()
        Thread.sleep(18)
        val elapsedMs = (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000
        return elapsedMs > 160
    }

    private fun hasSuspiciousHooks(): Boolean {
        if (hasKnownHookClasses()) return true
        if (hasSuspiciousMaps()) return true
        return false
    }

    private fun hasKnownHookClasses(): Boolean {
        val suspiciousClasses =
            listOf(
                "de.robv.android.xposed.XposedBridge",
                "de.robv.android.xposed.XC_MethodHook",
                "org.lsposed.hiddenapibypass.HiddenApiBypass",
                "com.saurik.substrate.MS",
            )
        return suspiciousClasses.any { className ->
            runCatching { Class.forName(className) }.isSuccess
        }
    }

    private fun hasSuspiciousMaps(): Boolean {
        val maps = runCatching { File("/proc/self/maps").readText() }.getOrNull() ?: return false
        val suspiciousTokens =
            listOf(
                "frida",
                "gum-js-loop",
                "gadget",
                "xposed",
                "lsposed",
                "edxp",
                "substrate",
                "riru",
            )
        val lower = maps.lowercase(Locale.US)
        return suspiciousTokens.any(lower::contains)
    }

    private fun hasFridaServerProcess(): Boolean {
        val candidates =
            listOf(
                "frida-server",
                "frida-helper",
                "gum-js-loop",
            )
        val procDir = File("/proc")
        val pids = procDir.listFiles()?.filter { it.name.all(Char::isDigit) } ?: return false
        for (pidDir in pids) {
            val cmdline =
                runCatching { File(pidDir, "cmdline").readText() }
                    .getOrNull()
                    ?.lowercase(Locale.US)
                    ?: continue
            if (candidates.any(cmdline::contains)) {
                return true
            }
        }
        return false
    }

    private fun isLikelyRooted(): Boolean {
        if (hasRootBinary()) return true
        if (hasMagiskIndicator()) return true
        if (hasDangerousProperties()) return true
        if (Build.TAGS?.contains("test-keys") == true) return true
        if (hasWritableSystemPartitions()) return true
        if (hasRootManagementPackages()) return true
        return false
    }

    private fun hasRootBinary(): Boolean {
        val suPaths =
            listOf(
                "/system/bin/su",
                "/system/xbin/su",
                "/sbin/su",
                "/su/bin/su",
                "/system/bin/.ext/.su",
            )
        return suPaths.any { File(it).exists() }
    }

    private fun hasMagiskIndicator(): Boolean {
        val paths =
            listOf(
                "/sbin/.magisk",
                "/data/adb/magisk",
                "/data/adb/modules",
                "/cache/.disable_magisk",
            )
        return paths.any { File(it).exists() }
    }

    private fun hasDangerousProperties(): Boolean {
        val debuggable = systemProperty("ro.debuggable")
        val secure = systemProperty("ro.secure")
        return debuggable == "1" || secure == "0"
    }

    private fun hasWritableSystemPartitions(): Boolean {
        val mounts = runCatching { File("/proc/mounts").readText() }.getOrNull() ?: return false
        val sensitiveMounts = listOf("/system ", "/vendor ", "/product ")
        return mounts
            .lineSequence()
            .any { line ->
                sensitiveMounts.any(line::contains) && line.contains(" rw,")
            }
    }

    private fun hasRootManagementPackages(): Boolean {
        val knownPackages =
            listOf(
                "com.topjohnwu.magisk",
                "eu.chainfire.supersu",
                "com.koushikdutta.superuser",
                "com.thirdparty.superuser",
            )
        return knownPackages.any { packageName ->
            runCatching {
                context.packageManager.getPackageInfo(packageName, 0)
            }.isSuccess
        }
    }

    private fun isLikelyEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase(Locale.US)
        val model = Build.MODEL.lowercase(Locale.US)
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.US)
        val hardware = Build.HARDWARE.lowercase(Locale.US)
        val product = Build.PRODUCT.lowercase(Locale.US)
        val qemu = systemProperty("ro.kernel.qemu")
        val emulatorFiles =
            listOf(
                "/dev/socket/qemud",
                "/dev/qemu_pipe",
                "/system/lib/libc_malloc_debug_qemu.so",
                "/sys/qemu_trace",
            )
        if (fingerprint.contains("generic") || fingerprint.contains("test-keys")) return true
        if (model.contains("sdk_gphone") || model.contains("emulator") || model.contains("android sdk built for x86")) return true
        if (manufacturer.contains("genymotion")) return true
        if (hardware.contains("goldfish") || hardware.contains("ranchu") || hardware.contains("vbox86")) return true
        if (product.contains("sdk") || product.contains("emulator")) return true
        if (qemu == "1") return true
        if (emulatorFiles.any { File(it).exists() }) return true
        return false
    }

    private fun systemProperty(name: String): String {
        return runCatching {
            val clazz = Class.forName("android.os.SystemProperties")
            val getMethod = clazz.getMethod("get", String::class.java)
            (getMethod.invoke(null, name) as? String).orEmpty()
        }.getOrDefault("")
    }

    private fun buildTrustSignal(nonce: String, contextLabel: String): Map<String, Any> {
        val safeNonce = nonce.ifBlank { randomNonce() }
        ensureInstallKey()
        val publicKeyB64 = installationPublicKeyBase64().orEmpty()
        val signatureB64 = signNonceBase64(safeNonce).orEmpty()
        val hardwareBacked = isKeyHardwareBacked()
        val config = loadIntegrityConfig()
        val cert = signingCertSha256()
        return mapOf(
            "nonce" to safeNonce,
            "context" to contextLabel,
            "publicKey" to publicKeyB64,
            "signature" to signatureB64,
            "hardwareBacked" to hardwareBacked,
            "appId" to BuildConfig.APPLICATION_ID,
            "certSha256" to cert,
            "pinSetId" to (config?.pinSetId ?: ""),
            "timestampMs" to System.currentTimeMillis(),
        )
    }

    private fun randomNonce(): String {
        val bytes = ByteArray(24)
        secureRandom.nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    private fun ensureInstallKey() {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(keystoreAlias)) {
            return
        }
        val generator =
            KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                "AndroidKeyStore",
            )
        val spec =
            KeyGenParameterSpec.Builder(
                keystoreAlias,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
            ).setDigests(
                KeyProperties.DIGEST_SHA256,
                KeyProperties.DIGEST_SHA512,
            ).setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
                .setUserAuthenticationRequired(false)
                .build()
        generator.initialize(spec)
        generator.generateKeyPair()
    }

    private fun installationPublicKeyBase64(): String? {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val cert = keyStore.getCertificate(keystoreAlias) ?: return null
        val x509Spec = X509EncodedKeySpec(cert.publicKey.encoded)
        val keyFactory = KeyFactory.getInstance("EC")
        val publicKey = keyFactory.generatePublic(x509Spec)
        return Base64.encodeToString(publicKey.encoded, Base64.NO_WRAP)
    }

    private fun signNonceBase64(nonce: String): String? {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val privateKey = keyStore.getKey(keystoreAlias, null) as? PrivateKey ?: return null
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(privateKey)
        signature.update(nonce.toByteArray(Charsets.UTF_8))
        val signed = signature.sign()
        return Base64.encodeToString(signed, Base64.NO_WRAP)
    }

    private fun isKeyHardwareBacked(): Boolean {
        return runCatching {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val privateKey = keyStore.getKey(keystoreAlias, null) as? PrivateKey ?: return false
            val keyFactory = KeyFactory.getInstance(privateKey.algorithm, "AndroidKeyStore")
            val keyInfo = keyFactory.getKeySpec(privateKey, KeyInfo::class.java)
            keyInfo.isInsideSecureHardware
        }.getOrDefault(false)
    }

    private fun normalizeHex(value: String): String {
        return value.replace(":", "").replace(" ", "").uppercase(Locale.US)
    }

    private fun sha256Hex(input: String): String {
        return sha256Hex(input.toByteArray(Charsets.UTF_8))
    }

    private fun sha256Hex(input: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input)
        return digest.joinToString(separator = "") { byte -> "%02X".format(byte) }
    }

    private fun debugLog(message: String) {
        if (!BuildConfig.DEBUG) {
            return
        }
        Log.d(TAG, message)
    }
}
