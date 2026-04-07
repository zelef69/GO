package com.example.go_play

import com.example.go_play.security.SecurityBridge
import com.example.go_play.update.UpdateBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var securityBridge: SecurityBridge? = null
    private var updateBridge: UpdateBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        securityBridge = SecurityBridge(this)
        updateBridge = UpdateBridge(this)
        configureSecurityChannel(flutterEngine)
        configureUpdateChannel(flutterEngine)
    }

    override fun onDestroy() {
        securityBridge = null
        updateBridge = null
        super.onDestroy()
    }

    private fun configureSecurityChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "go_play/security")
        securityBridge?.attachToChannel(channel)
    }

    private fun configureUpdateChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "go_play/update")
        updateBridge?.attachToChannel(channel)
    }
}
