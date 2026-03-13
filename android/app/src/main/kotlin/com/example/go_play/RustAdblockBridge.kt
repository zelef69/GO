package com.example.go_play

import android.net.Uri
import android.os.SystemClock
import android.util.Log
import org.json.JSONArray

object RustAdblockBridge {
    private const val TAG = "GO_PLAY-AdblockNative"
    private const val LIB_NAME = "go_play_adblock_jni"
    private const val MAX_DEBUG_LOGS = 800
    private const val SLOW_NATIVE_CHECK_MS = 30L

    private var debugLogCount = 0

    private val libraryLoaded: Boolean = runCatching {
        System.loadLibrary(LIB_NAME)
        log("loadLibrary success lib=$LIB_NAME")
        true
    }.getOrElse { error ->
        log("loadLibrary failed lib=$LIB_NAME error=${error.javaClass.simpleName}")
        false
    }

    private external fun nativeIsAvailable(): Boolean
    private external fun nativeInitializeEngine(filterText: String): Boolean
    private external fun nativeInitializeEngineV2(
        filterText: String,
        resourcesJson: String,
        enabledTagsJson: String,
    ): Boolean
    private external fun nativeInitializeEngineV3(
        filterText: String,
        resourcesJson: String,
        enabledTagsJson: String,
        catalogSourcesJson: String,
        serializedEngineBase64: String,
    ): Boolean
    private external fun nativeShouldBlockRequest(
        requestUrl: String,
        sourceUrl: String,
        resourceType: String,
    ): Boolean
    private external fun nativeEvaluateRequest(
        requestUrl: String,
        sourceUrl: String,
        resourceType: String,
    ): String?
    private external fun nativeGetCosmeticResources(pageUrl: String): String?
    private external fun nativeGetHiddenClassIdSelectors(
        pageUrl: String,
        classesJson: String,
        idsJson: String,
        exceptionsJson: String,
    ): String?
    private external fun nativeGetCspDirectives(
        requestUrl: String,
        sourceUrl: String,
        resourceType: String,
    ): String?
    private external fun nativeSerializeEngine(): String?
    private external fun nativeDisposeEngine()

    fun isAvailable(): Boolean {
        if (!libraryLoaded) {
            log("isAvailable result=false reason=library_not_loaded")
            return false
        }
        val startedAt = SystemClock.elapsedRealtime()
        val available =
            runCatching { nativeIsAvailable() }
                .onFailure { error ->
                    log("isAvailable failed error=${error.javaClass.simpleName}")
                }.getOrDefault(false)
        val elapsedMs = SystemClock.elapsedRealtime() - startedAt
        log("isAvailable result=$available elapsedMs=$elapsedMs")
        return available
    }

    fun initializeEngine(
        filterText: String,
        resourcesJson: String = "",
        catalogSourcesJson: String = "[]",
        serializedEngineBase64: String = "",
        enabledTags: List<String> = emptyList(),
    ): Boolean {
        if (!libraryLoaded) {
            log("initializeEngine result=false reason=library_not_loaded")
            return false
        }
        val lineCount = if (filterText.isEmpty()) 0 else filterText.count { it == '\n' } + 1
        val resourcesChars = resourcesJson.length
        val sourceChars = catalogSourcesJson.length
        val snapshotChars = serializedEngineBase64.length
        log(
            "initializeEngine start chars=${filterText.length} lines=$lineCount resourcesChars=$resourcesChars sourceChars=$sourceChars snapshotChars=$snapshotChars tags=${enabledTags.size}",
        )
        val startedAt = SystemClock.elapsedRealtime()
        val initialized =
            runCatching {
                if (resourcesJson.isBlank() &&
                    enabledTags.isEmpty() &&
                    catalogSourcesJson.isBlank() &&
                    serializedEngineBase64.isBlank()
                ) {
                    nativeInitializeEngine(filterText)
                } else if (catalogSourcesJson.isNotBlank() ||
                    serializedEngineBase64.isNotBlank()
                ) {
                    nativeInitializeEngineV3(
                        filterText,
                        resourcesJson,
                        JSONArray(enabledTags).toString(),
                        catalogSourcesJson,
                        serializedEngineBase64,
                    )
                } else {
                    nativeInitializeEngineV2(
                        filterText,
                        resourcesJson,
                        JSONArray(enabledTags).toString(),
                    )
                }
            }
                .onFailure { error ->
                    log("initializeEngine failed error=${error.javaClass.simpleName}")
                }.getOrDefault(false)
        val elapsedMs = SystemClock.elapsedRealtime() - startedAt
        log("initializeEngine result=$initialized elapsedMs=$elapsedMs")
        return initialized
    }

    fun getCosmeticResources(pageUrl: String): String {
        if (!libraryLoaded) {
            return ""
        }
        return runCatching { nativeGetCosmeticResources(pageUrl).orEmpty() }.getOrDefault("")
    }

    fun getHiddenClassIdSelectors(
        pageUrl: String,
        classesJson: String,
        idsJson: String,
        exceptionsJson: String,
    ): String {
        if (!libraryLoaded) {
            return ""
        }
        return runCatching {
            nativeGetHiddenClassIdSelectors(
                pageUrl,
                classesJson,
                idsJson,
                exceptionsJson,
            ).orEmpty()
        }.getOrDefault("")
    }

    fun getCspDirectives(
        requestUrl: String,
        sourceUrl: String,
        resourceType: String,
    ): String {
        if (!libraryLoaded) {
            return ""
        }
        return runCatching {
            nativeGetCspDirectives(requestUrl, sourceUrl, resourceType).orEmpty()
        }.getOrDefault("")
    }

    fun serializeEngine(): String {
        if (!libraryLoaded) {
            return ""
        }
        return runCatching { nativeSerializeEngine().orEmpty() }.getOrDefault("")
    }

    fun shouldBlockRequest(
        requestUrl: String,
        sourceUrl: String,
        resourceType: String,
    ): Boolean {
        if (!libraryLoaded) {
            log("shouldBlockRequest result=false reason=library_not_loaded type=$resourceType")
            return false
        }
        val requestLabel = urlLabel(requestUrl)
        val sourceLabel = urlLabel(sourceUrl)
        val startedAt = SystemClock.elapsedRealtime()
        val blocked =
            runCatching {
                nativeShouldBlockRequest(requestUrl, sourceUrl, resourceType)
            }.onFailure { error ->
                log(
                    "shouldBlockRequest failed type=$resourceType url=$requestLabel source=$sourceLabel error=${error.javaClass.simpleName}",
                )
            }.getOrDefault(false)
        val elapsedMs = SystemClock.elapsedRealtime() - startedAt
        if (blocked || elapsedMs >= SLOW_NATIVE_CHECK_MS) {
            log(
                "shouldBlockRequest result=$blocked type=$resourceType url=$requestLabel source=$sourceLabel elapsedMs=$elapsedMs",
            )
        }
        return blocked
    }

    fun evaluateRequest(
        requestUrl: String,
        sourceUrl: String,
        resourceType: String,
    ): String {
        if (!libraryLoaded) {
            return ""
        }
        return runCatching {
            nativeEvaluateRequest(requestUrl, sourceUrl, resourceType).orEmpty()
        }.getOrDefault("")
    }

    fun disposeEngine() {
        if (!libraryLoaded) {
            log("disposeEngine skipped reason=library_not_loaded")
            return
        }
        val startedAt = SystemClock.elapsedRealtime()
        runCatching { nativeDisposeEngine() }
            .onFailure { error ->
                log("disposeEngine failed error=${error.javaClass.simpleName}")
            }
        val elapsedMs = SystemClock.elapsedRealtime() - startedAt
        log("disposeEngine done elapsedMs=$elapsedMs")
    }

    private fun log(message: String) {
        if (!BuildConfig.DEBUG || debugLogCount >= MAX_DEBUG_LOGS) {
            return
        }
        debugLogCount += 1
        Log.d(TAG, message)
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
