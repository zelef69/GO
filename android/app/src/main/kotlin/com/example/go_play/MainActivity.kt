package com.example.go_play

import com.example.go_play.pip.PipController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pipController: PipController? = null
    private val rustAdblockBridge = RustAdblockBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipController = PipController(this, flutterEngine.dartExecutor.binaryMessenger)
        configureAdblockChannel(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        pipController?.onStart()
    }

    override fun onDestroy() {
        pipController?.onDestroy()
        pipController = null
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
                        result.success(rustAdblockBridge.isAvailable())
                    }
                    "initializeEngine" -> {
                        val rules = call.argument<List<Map<String, Any?>>>("rules") ?: emptyList()
                        val filterText =
                            rules
                                .mapNotNull { it["rawRule"] as? String }
                                .joinToString(separator = "\n")
                        result.success(rustAdblockBridge.initializeEngine(filterText))
                    }
                    "shouldBlockRequest" -> {
                        val requestUrl = call.argument<String>("url")
                        val sourceUrl = call.argument<String>("sourceUrl").orEmpty()
                        val resourceType = call.argument<String>("resourceType") ?: "other"
                        if (requestUrl.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(
                            rustAdblockBridge.shouldBlockRequest(
                                requestUrl = requestUrl,
                                sourceUrl = sourceUrl,
                                resourceType = resourceType,
                            ),
                        )
                    }
                    "disposeEngine" -> {
                        rustAdblockBridge.disposeEngine()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
