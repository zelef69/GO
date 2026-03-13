package com.example.go_play.update

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class UpdateBridge(
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    fun attachToChannel(channel: MethodChannel) {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstallPackages" -> {
                val allowed =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                result.success(allowed)
            }

            "openUnknownAppsSettings" -> {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val intent =
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${context.packageName}"),
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        context.startActivity(intent)
                    }
                    result.success(true)
                } catch (error: Exception) {
                    result.error(
                        "UNKNOWN_APPS_SETTINGS_ERROR",
                        error.message ?: "Unable to open unknown apps settings",
                        null,
                    )
                }
            }

            "installApk" -> {
                val apkPath = call.argument<String>("apkPath").orEmpty().trim()
                if (apkPath.isEmpty()) {
                    result.error("APK_PATH_EMPTY", "apkPath is required", null)
                    return
                }
                val apkFile = File(apkPath)
                if (!apkFile.exists()) {
                    result.error("APK_NOT_FOUND", "APK file not found", null)
                    return
                }
                try {
                    val contentUri =
                        FileProvider.getUriForFile(
                            context,
                            "${context.packageName}.fileprovider",
                            apkFile,
                        )
                    val installIntent =
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(contentUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    context.startActivity(installIntent)
                    result.success(true)
                } catch (error: ActivityNotFoundException) {
                    result.error(
                        "INSTALLER_NOT_FOUND",
                        "Package installer not found",
                        null,
                    )
                } catch (error: IllegalArgumentException) {
                    result.error(
                        "APK_URI_ERROR",
                        error.message ?: "Unable to create APK content URI",
                        null,
                    )
                } catch (error: Exception) {
                    result.error(
                        "INSTALL_APK_ERROR",
                        error.message ?: "Unable to launch package installer",
                        null,
                    )
                }
            }

            else -> result.notImplemented()
        }
    }
}
