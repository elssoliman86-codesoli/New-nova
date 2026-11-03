package com.codesoli.nova

import android.content.Intent
import android.content.pm.PackageManager
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
        IslandConfig.load(this)
        AssistantConfig.load(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    handle(call.method, call.arguments, result)
                } catch (e: Exception) {
                    result.error("NATIVE_ERROR", e.message ?: e.toString(), null)
                }
            }
    }

    private fun handle(method: String, arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        when (method) {
            "getStatus" -> result.success(mapOf(
                "overlayGranted" to SystemData.overlayGranted(this),
                "notificationAccessGranted" to SystemData.notificationAccessGranted(this)
            ))
            "snapshot" -> result.success(SystemData.snapshot(this))
            "openOverlaySettings" -> {
                if (!SystemData.overlayGranted(this)) {
                    open(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                }
                result.success(null)
            }
            "openNotificationSettings" -> { open(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(null) }
            "openUsageSettings" -> { open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)); result.success(null) }
            "openAccessibilitySettings" -> { open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); result.success(null) }
            "openAppSettings" -> {
                open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                result.success(null)
            }
            "requestIgnoreBattery" -> {
                val ok = open(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                if (!ok) open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                result.success(null)
            }
            "openExactAlarmSettings" -> {
                if (Build.VERSION.SDK_INT >= 31) {
                    open(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                }
                result.success(null)
            }
            "requestPermissions" -> {
                val wanted = (args["groups"] as? List<*>)?.filterIsInstance<String>() ?: listOf("island")
                val missing = permissionsFor(wanted).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 731)
                result.success(missing.size)
            }
            "startIsland" -> {
                val missing = permissionsFor(listOf("island")).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 731)
                if (!SystemData.overlayGranted(this)) {
                    result.error("OVERLAY_PERMISSION_REQUIRED", "Grant display-over-other-apps permission first.", null)
                } else {
                    IslandConfig.setAutostart(this, true)
                    sendService(NovaIslandService.ACTION_START)
                    result.success(null)
                }
            }
            "stopIsland" -> {
                startService(Intent(this, NovaIslandService::class.java).setAction(NovaIslandService.ACTION_STOP))
                result.success(null)
            }
            "setConfig" -> {
                val disabled = (args["disabled"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                IslandConfig.update(
                    this,
                    disabled,
                    args["mediaMini"] as? Boolean ?: false,
                    args["idle"] as? Boolean ?: true,
                    (args["latitude"] as? Number)?.toDouble() ?: IslandConfig.latitude,
                    (args["longitude"] as? Number)?.toDouble() ?: IslandConfig.longitude,
                    args["city"] as? String ?: IslandConfig.cityName,
                    (args["tasksToday"] as? Number)?.toInt() ?: IslandConfig.tasksToday,
                    args["nextTask"] as? String ?: IslandConfig.nextTask,
                    args["quiet"] as? Boolean ?: IslandConfig.quietWhileWatching,
                )
                AssistantConfig.save(this, args)
                if (IslandState.running) sendService(NovaIslandService.ACTION_CONFIG)
                result.success(null)
            }
            "schedulePrayers" -> {
                val items = (args["items"] as? List<*>)?.mapNotNull { raw ->
                    val m = raw as? Map<*, *> ?: return@mapNotNull null
                    val at = (m["at"] as? Number)?.toLong() ?: return@mapNotNull null
                    IslandConfig.Prayer(at, m["label"] as? String ?: "", m["body"] as? String ?: "")
                } ?: emptyList()
                IslandConfig.savePrayers(this, args["alerts"] as? Boolean ?: true, items)
                if (IslandState.running) sendService(NovaIslandService.ACTION_PRAYERS)
                result.success(items.size)
            }
            "testEvent" -> {
                if (!SystemData.overlayGranted(this)) {
                    result.error("OVERLAY_PERMISSION_REQUIRED", "Grant display-over-other-apps permission first.", null)
                } else {
                    val intent = Intent(this, NovaIslandService::class.java)
                        .setAction(NovaIslandService.ACTION_SHOW_EVENT)
                        .putExtra(NovaIslandService.EXTRA_KIND, args["kind"] as? String ?: "test")
                        .putExtra(NovaIslandService.EXTRA_KEY, "test")
                        .putExtra(NovaIslandService.EXTRA_TITLE, args["title"] as? String ?: "Nova Island")
                        .putExtra(NovaIslandService.EXTRA_BODY, args["body"] as? String ?: "This is a test event")
                    startServiceCompat(intent)
                    result.success(null)
                }
            }
            "mediaControl" -> {
                startServiceCompat(Intent(this, NovaIslandService::class.java)
                    .setAction(NovaIslandService.ACTION_MEDIA_CONTROL)
                    .putExtra(NovaIslandService.EXTRA_CONTROL, args["action"] as? String ?: ""))
                result.success(null)
            }
            "assistantSubmit" -> {
                startServiceCompat(Intent(this, NovaIslandService::class.java)
                    .setAction(NovaIslandService.ACTION_ASSISTANT_SUBMIT)
                    .putExtra(NovaIslandService.EXTRA_BODY, args["text"] as? String ?: ""))
                result.success(null)
            }
            "assistantListen" -> {
                startServiceCompat(Intent(this, NovaIslandService::class.java)
                    .setAction(NovaIslandService.ACTION_ASSISTANT_LISTEN))
                result.success(null)
            }
            "memoryList" -> result.success(MemoryStore.all(this).reversed().map {
                mapOf("id" to it.id, "text" to it.text, "at" to it.at)
            })
            "memoryAdd" -> result.success(MemoryStore.add(this, args["text"] as? String ?: ""))
            "memoryDelete" -> {
                (args["id"] as? Number)?.toLong()?.let { MemoryStore.remove(this, it) }
                result.success(null)
            }
            "memoryClear" -> { MemoryStore.clear(this); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun open(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun sendService(action: String) = startServiceCompat(Intent(this, NovaIslandService::class.java).setAction(action))

    private fun startServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
    }

    private fun permissionsFor(groups: List<String>): List<String> = buildList {
        if ("island" in groups) {
            if (Build.VERSION.SDK_INT >= 31) add(android.Manifest.permission.BLUETOOTH_CONNECT)
            add(android.Manifest.permission.READ_PHONE_STATE)
            if (Build.VERSION.SDK_INT >= 33) add(android.Manifest.permission.POST_NOTIFICATIONS)
        }
        if ("calendar" in groups) add(android.Manifest.permission.READ_CALENDAR)
        if ("assistant" in groups) {
            add(android.Manifest.permission.RECORD_AUDIO)
            add(android.Manifest.permission.READ_CONTACTS)
            add(android.Manifest.permission.CALL_PHONE)
            if (Build.VERSION.SDK_INT >= 33) add(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }.distinct()

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 731 && IslandState.running && grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            sendService(NovaIslandService.ACTION_REFRESH_PERMISSIONS)
        }
    }
}
