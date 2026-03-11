package com.example.go_play

object RustAdblockBridge {
    private const val LIB_NAME = "go_play_adblock_jni"

    private val libraryLoaded: Boolean = runCatching {
        System.loadLibrary(LIB_NAME)
        true
    }.getOrElse { false }

    private external fun nativeIsAvailable(): Boolean
    private external fun nativeInitializeEngine(filterText: String): Boolean
    private external fun nativeShouldBlockRequest(
        requestUrl: String,
        sourceUrl: String,
        resourceType: String,
    ): Boolean
    private external fun nativeDisposeEngine()

    fun isAvailable(): Boolean {
        if (!libraryLoaded) {
            return false
        }
        return runCatching { nativeIsAvailable() }.getOrDefault(false)
    }

    fun initializeEngine(filterText: String): Boolean {
        if (!libraryLoaded) {
            return false
        }
        return runCatching { nativeInitializeEngine(filterText) }.getOrDefault(false)
    }

    fun shouldBlockRequest(
        requestUrl: String,
        sourceUrl: String,
        resourceType: String,
    ): Boolean {
        if (!libraryLoaded) {
            return false
        }
        return runCatching {
            nativeShouldBlockRequest(requestUrl, sourceUrl, resourceType)
        }.getOrDefault(false)
    }

    fun disposeEngine() {
        if (!libraryLoaded) {
            return
        }
        runCatching { nativeDisposeEngine() }
    }
}
