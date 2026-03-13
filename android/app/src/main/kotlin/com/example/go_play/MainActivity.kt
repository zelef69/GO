package com.example.go_play

import android.Manifest
import android.net.Uri
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.go_play.pip.PipController
import com.example.go_play.security.SecurityBridge
import com.example.go_play.update.UpdateBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        private const val ADBLOCK_TAG = "GO_PLAY-AdblockChannel"
        private const val MAX_ADBLOCK_DEBUG_LOGS = 600
        private const val SLOW_ADBLOCK_CHECK_MS = 40L
    }

    private var pipController: PipController? = null
    private var securityBridge: SecurityBridge? = null
    private var updateBridge: UpdateBridge? = null
    private val rustAdblockBridge = RustAdblockBridge
    private val notificationPermissionRequestCode = 9103
    private var adblockDebugLogCount = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipController = PipController(this, flutterEngine.dartExecutor.binaryMessenger)
        securityBridge = SecurityBridge(this)
        updateBridge = UpdateBridge(this)
        configureSecurityChannel(flutterEngine)
        configureUpdateChannel(flutterEngine)
        configureAdblockChannel(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        requestNotificationPermissionIfNeeded()
        pipController?.onStart()
    }

    override fun onStop() {
        pipController?.onAppForegroundChanged(false)
        super.onStop()
    }

    override fun onDestroy() {
        pipController?.onDestroy()
        pipController = null
        securityBridge = null
        updateBridge = null
        super.onDestroy()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration?,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipController?.onPictureInPictureModeChanged(isInPictureInPictureMode)
    }

    private fun configureAdblockChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "go_play/adblock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isRustEngineAvailable" -> {
                        val available = rustAdblockBridge.isAvailable()
                        logAdblock("method=isRustEngineAvailable result=$available")
                        result.success(available)
                    }
                    "initializeEngine" -> {
                        val rules = call.argument<List<Map<String, Any?>>>("rules") ?: emptyList()
                        val filterTextFromBridge = call.argument<String>("filterText").orEmpty()
                        val filterText =
                            if (filterTextFromBridge.isNotBlank()) {
                                filterTextFromBridge
                            } else {
                                rules
                                    .mapNotNull { it["rawRule"] as? String }
                                    .joinToString(separator = "\n")
                            }
                        val resourcesJson = call.argument<String>("resourcesJson").orEmpty()
                        val catalogSourcesJson =
                            call.argument<String>("catalogSourcesJson").orEmpty()
                        val serializedEngineBase64 =
                            call.argument<String>("serializedEngineBase64").orEmpty()
                        val enabledTags = call.argument<List<String>>("enabledTags") ?: emptyList()
                        logAdblock(
                            "method=initializeEngine start ruleObjects=${rules.size} ruleChars=${filterText.length} resourcesChars=${resourcesJson.length} sourceChars=${catalogSourcesJson.length} snapshotChars=${serializedEngineBase64.length} tags=${enabledTags.size}",
                        )
                        val startedAt = SystemClock.elapsedRealtime()
                        val initialized =
                            rustAdblockBridge.initializeEngine(
                                filterText = filterText,
                                resourcesJson = resourcesJson,
                                catalogSourcesJson = catalogSourcesJson,
                                serializedEngineBase64 = serializedEngineBase64,
                                enabledTags = enabledTags,
                            )
                        val elapsedMs = SystemClock.elapsedRealtime() - startedAt
                        logAdblock(
                            "method=initializeEngine done initialized=$initialized elapsedMs=$elapsedMs",
                        )
                        result.success(initialized)
                    }
                    "getCosmeticResources" -> {
                        val requestUrl = call.argument<String>("url").orEmpty()
                        if (requestUrl.isBlank()) {
                            result.success("")
                            return@setMethodCallHandler
                        }
                        val payload = rustAdblockBridge.getCosmeticResources(requestUrl)
                        result.success(payload)
                    }
                    "getHiddenClassIdSelectors" -> {
                        val requestUrl = call.argument<String>("url").orEmpty()
                        if (requestUrl.isBlank()) {
                            result.success("[]")
                            return@setMethodCallHandler
                        }
                        val classes = call.argument<List<String>>("classes") ?: emptyList()
                        val ids = call.argument<List<String>>("ids") ?: emptyList()
                        val exceptions =
                            call.argument<List<String>>("exceptions") ?: emptyList()
                        val payload =
                            rustAdblockBridge.getHiddenClassIdSelectors(
                                pageUrl = requestUrl,
                                classesJson = org.json.JSONArray(classes).toString(),
                                idsJson = org.json.JSONArray(ids).toString(),
                                exceptionsJson = org.json.JSONArray(exceptions).toString(),
                            )
                        result.success(payload)
                    }
                    "getCspDirectives" -> {
                        val requestUrl = call.argument<String>("url").orEmpty()
                        val sourceUrl = call.argument<String>("sourceUrl").orEmpty()
                        val resourceType = call.argument<String>("resourceType") ?: "document"
                        if (requestUrl.isBlank()) {
                            result.success("")
                            return@setMethodCallHandler
                        }
                        val payload =
                            rustAdblockBridge.getCspDirectives(
                                requestUrl = requestUrl,
                                sourceUrl = sourceUrl,
                                resourceType = resourceType,
                            )
                        result.success(payload)
                    }
                    "serializeEngine" -> {
                        val payload = rustAdblockBridge.serializeEngine()
                        result.success(payload)
                    }
                    "shouldBlockRequest" -> {
                        val requestUrl = call.argument<String>("url")
                        val sourceUrl = call.argument<String>("sourceUrl").orEmpty()
                        val resourceType = call.argument<String>("resourceType") ?: "other"
                        if (requestUrl.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val requestLabel = urlLabel(requestUrl)
                        val sourceLabel = urlLabel(sourceUrl)
                        val startedAt = SystemClock.elapsedRealtime()
                        val blocked =
                            rustAdblockBridge.shouldBlockRequest(
                                requestUrl = requestUrl,
                                sourceUrl = sourceUrl,
                                resourceType = resourceType,
                            )
                        result.success(
                            blocked,
                        )
                        val elapsedMs = SystemClock.elapsedRealtime() - startedAt
                        if (blocked || elapsedMs >= SLOW_ADBLOCK_CHECK_MS) {
                            logAdblock(
                                "method=shouldBlockRequest done blocked=$blocked type=$resourceType url=$requestLabel source=$sourceLabel elapsedMs=$elapsedMs",
                            )
                        }
                    }
                    "evaluateRequestDetailed" -> {
                        val requestUrl = call.argument<String>("url")
                        val sourceUrl = call.argument<String>("sourceUrl").orEmpty()
                        val resourceType = call.argument<String>("resourceType") ?: "other"
                        if (requestUrl.isNullOrBlank()) {
                            result.success("")
                            return@setMethodCallHandler
                        }
                        val payload =
                            rustAdblockBridge.evaluateRequest(
                                requestUrl = requestUrl,
                                sourceUrl = sourceUrl,
                                resourceType = resourceType,
                            )
                        result.success(payload)
                    }
                    "disposeEngine" -> {
                        logAdblock("method=disposeEngine start")
                        rustAdblockBridge.disposeEngine()
                        logAdblock("method=disposeEngine done")
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureSecurityChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "go_play/security")
        securityBridge?.attachToChannel(channel)
    }

    private fun configureUpdateChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "go_play/update")
        updateBridge?.attachToChannel(channel)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        val granted =
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun logAdblock(message: String) {
        if (!BuildConfig.DEBUG || adblockDebugLogCount >= MAX_ADBLOCK_DEBUG_LOGS) {
            return
        }
        adblockDebugLogCount += 1
        Log.d(ADBLOCK_TAG, message)
    }

    private fun urlLabel(raw: String?): String {
        if (raw.isNullOrBlank()) {
            return "none"
        }
        return runCatching {
            val parsed = Uri.parse(raw)
            "${parsed.host ?: "unknown"}${parsed.path ?: ""}"
        }.getOrDefault(raw)
    }
}
