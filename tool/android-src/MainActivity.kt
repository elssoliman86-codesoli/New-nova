package com.codesoli.nova

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.codesoli.nova/system_island"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> result.success(mapOf(
                        "overlayGranted" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)),
                        "notificationAccessGranted" to isNotificationAccessGranted()
                    ))
                    "openOverlaySettings" -> {
                        if (!(Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this))) {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")))
                        }
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "startIsland" -> {
                        val missing = requiredRuntimePermissions().filter { checkSelfPermission(it) != android.content.pm.PackageManager.PERMISSION_GRANTED }
                        if (missing.isNotEmpty()) {
                            requestPermissions(missing.toTypedArray(), 731)
                            result.success(null)
                        } else if (!(Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this))) {
                            result.error("OVERLAY_PERMISSION_REQUIRED", "Grant display-over-other-apps permission first.", null)
                        } else {
                            val intent = Intent(this, NovaIslandService::class.java).setAction(NovaIslandService.ACTION_START)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                            result.success(null)
                        }
                    }
                    "stopIsland" -> {
                        startService(Intent(this, NovaIslandService::class.java).setAction(NovaIslandService.ACTION_STOP))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requiredRuntimePermissions(): List<String> = buildList {
        if (Build.VERSION.SDK_INT >= 31) add(android.Manifest.permission.BLUETOOTH_CONNECT)
        add(android.Manifest.permission.READ_PHONE_STATE)
    }

    private fun isNotificationAccessGranted(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(":").any { it.equals(componentName.flattenToString(), ignoreCase = true) }
    }
}
