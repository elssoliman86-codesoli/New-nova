package com.codesoli.nova

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Live facts the service publishes so the Flutter "Device" screen can show
 * what is really happening (and what is not) instead of guessing.
 */
object IslandState {
    @Volatile var running = false
    @Volatile var overlayAttached = false
    @Volatile var listenerConnected = false

    @Volatile var mediaActive = false
    @Volatile var mediaPlaying = false
    @Volatile var mediaTitle = ""
    @Volatile var mediaArtist = ""
    @Volatile var mediaApp = ""

    @Volatile var eventsShown = 0
    @Volatile var lastEventTitle = ""
    @Volatile var lastEventBody = ""
    @Volatile var lastEventAt = 0L

    @Volatile var notificationsSeen = 0
    @Volatile var lastNotificationApp = ""
    @Volatile var lastNotificationAt = 0L

    @Volatile var nextPrayerLabel = ""
    @Volatile var nextPrayerAt = 0L
    @Volatile var prayersScheduled = 0
    @Volatile var exactAlarms = false

    @Volatile var assistantOn = false
    @Volatile var assistantState = "off"
    @Volatile var assistantHeard = ""
    @Volatile var assistantReply = ""
    @Volatile var assistantError = ""
    @Volatile var a11yConnected = false

    @Volatile var weatherText = ""
    @Volatile var weatherAt = 0L
}

/** User choices that must survive the app being closed (service restarts, reboot). */
object IslandConfig {
    private const val PREFS = "nova_island"
    private const val KEY_DISABLED = "disabled"
    private const val KEY_MEDIA_MINI = "media_mini"
    private const val KEY_AUTOSTART = "autostart"
    private const val KEY_PRAYERS = "prayers"
    private const val KEY_PRAYER_ALERTS = "prayer_alerts"

    @Volatile private var disabled: Set<String> = emptySet()
    @Volatile var mediaMini = false
    @Volatile var idleEnabled = true
    @Volatile var latitude = 30.0444
    @Volatile var longitude = 31.2357
    @Volatile var prayerAlerts = true
    @Volatile private var loaded = false

    fun load(context: Context) {
        if (loaded) return
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        disabled = p.getStringSet(KEY_DISABLED, emptySet())?.toSet() ?: emptySet()
        mediaMini = p.getBoolean(KEY_MEDIA_MINI, false)
        idleEnabled = p.getBoolean("idle", true)
        latitude = p.getFloat("lat", 30.0444f).toDouble()
        longitude = p.getFloat("lon", 31.2357f).toDouble()
        prayerAlerts = p.getBoolean(KEY_PRAYER_ALERTS, true)
        loaded = true
    }

    fun enabled(kind: String): Boolean = !disabled.contains(kind)

    fun update(
        context: Context,
        disabledKinds: Collection<String>,
        mini: Boolean,
        idle: Boolean,
        lat: Double,
        lon: Double,
    ) {
        disabled = disabledKinds.toSet()
        mediaMini = mini
        idleEnabled = idle
        latitude = lat
        longitude = lon
        loaded = true
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putStringSet(KEY_DISABLED, disabled)
            .putBoolean(KEY_MEDIA_MINI, mini)
            .putBoolean("idle", idle)
            .putFloat("lat", lat.toFloat())
            .putFloat("lon", lon.toFloat())
            .apply()
    }

    var autostart: Boolean = false
        get() = field
        private set

    fun loadAutostart(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_AUTOSTART, false)

    fun setAutostart(context: Context, value: Boolean) {
        autostart = value
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_AUTOSTART, value).apply()
    }

    class Prayer(val at: Long, val label: String, val body: String)

    fun savePrayers(context: Context, alerts: Boolean, items: List<Prayer>) {
        prayerAlerts = alerts
        val array = JSONArray()
        items.forEach {
            array.put(JSONObject().put("at", it.at).put("label", it.label).put("body", it.body))
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_PRAYERS, array.toString())
            .putBoolean(KEY_PRAYER_ALERTS, alerts)
            .apply()
    }

    fun loadPrayers(context: Context): List<Prayer> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PRAYERS, null)
            ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map {
                val o = array.getJSONObject(it)
                Prayer(o.getLong("at"), o.optString("label"), o.optString("body"))
            }.sortedBy { it.at }
        } catch (_: Exception) {
            emptyList()
        }
    }
}

object SystemData {
    private const val FG = 1 // ACTIVITY_RESUMED / MOVE_TO_FOREGROUND
    private const val BG = 2 // ACTIVITY_PAUSED / MOVE_TO_BACKGROUND

    private var usageCacheAt = 0L
    private var usageCache: Map<String, Any?> = emptyMap()

    // ------------------------------------------------------- permissions

    fun overlayGranted(context: Context): Boolean =
        Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(context)

    /**
     * The enabled-listeners list holds the listener's own component
     * (package/package.NovaNotificationListener), so compare packages.
     */
    fun notificationAccessGranted(context: Context): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            ?: return false
        return enabled.split(":").any {
            ComponentName.unflattenFromString(it)?.packageName == context.packageName
        }
    }

    fun accessibilityEnabled(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(":").any {
            ComponentName.unflattenFromString(it)?.packageName == context.packageName
        }
    }

    @Suppress("DEPRECATION")
    fun usageAccessGranted(context: Context): Boolean {
        return try {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            } else {
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
    }

    fun ignoringBatteryOptimizations(context: Context): Boolean {
        return try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(context.packageName)
        } catch (_: Exception) {
            false
        }
    }

    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        return try {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()
        } catch (_: Exception) {
            false
        }
    }

    fun granted(context: Context, permission: String): Boolean =
        Build.VERSION.SDK_INT < 23 ||
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    // ----------------------------------------------------------- readings

    fun battery(context: Context): Map<String, Any?> {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return mapOf("level" to -1)
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100).coerceAtLeast(1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val health = intent.getIntExtra(BatteryManager.EXTRA_HEALTH, 0)
        val temp = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) / 10.0
        val source = when (plugged) {
            BatteryManager.BATTERY_PLUGGED_AC -> "AC"
            BatteryManager.BATTERY_PLUGGED_USB -> "USB"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"
            else -> ""
        }
        return mapOf(
            "level" to (if (level >= 0) level * 100 / scale else -1),
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL),
            "full" to (status == BatteryManager.BATTERY_STATUS_FULL),
            "source" to source,
            "temperature" to temp,
            "healthy" to (health == BatteryManager.BATTERY_HEALTH_GOOD)
        )
    }

    fun storage(): Map<String, Any?> {
        return try {
            val stat = StatFs(Environment.getDataDirectory().path)
            mapOf("total" to stat.totalBytes, "free" to stat.availableBytes)
        } catch (_: Exception) {
            mapOf("total" to 0L, "free" to 0L)
        }
    }

    fun memory(context: Context): Map<String, Any?> {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = ActivityManager.MemoryInfo()
            am.getMemoryInfo(info)
            mapOf("total" to info.totalMem, "free" to info.availMem, "low" to info.lowMemory)
        } catch (_: Exception) {
            mapOf("total" to 0L, "free" to 0L, "low" to false)
        }
    }

    fun network(context: Context): String {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) }
            when {
                caps == null -> "Offline"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile data"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
                else -> "Connected"
            }
        } catch (_: Exception) {
            "Unknown"
        }
    }

    /** Headphones, speakers and other outputs that are not the phone itself. */
    fun audioDevices(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < 23) return emptyList()
        return try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .filter { isExternalOutput(it.type) }
                .map {
                    mapOf(
                        "kind" to outputKind(it.type),
                        "name" to (it.productName?.toString().orEmpty())
                    )
                }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun isExternalOutput(type: Int): Boolean = when (type) {
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_HDMI -> true
        else -> if (Build.VERSION.SDK_INT >= 31) {
            type == AudioDeviceInfo.TYPE_BLE_HEADSET || type == AudioDeviceInfo.TYPE_BLE_SPEAKER
        } else {
            false
        }
    }

    private fun outputKind(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headset"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth"
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> "USB audio"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI"
        else -> "Wireless audio"
    }

    // -------------------------------------------------------- usage access

    fun appLabel(context: Context, packageName: String): String {
        return try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        } catch (_: Exception) {
            packageName.substringAfterLast('.')
        }
    }

    /** Package currently in the foreground, from the recent usage events. */
    fun foregroundPackage(context: Context): String? {
        if (!usageAccessGranted(context)) return null
        return try {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val end = System.currentTimeMillis()
            val events = usm.queryEvents(end - 15 * 60 * 1000L, end)
            val event = UsageEvents.Event()
            var current: String? = null
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                when (event.eventType) {
                    FG -> current = event.packageName
                    BG -> if (event.packageName == current) current = null
                }
            }
            current
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Foreground time per app since local midnight, rebuilt from usage events.
     * Cached for 20 seconds because the Device screen polls.
     */
    fun screenTime(context: Context): Map<String, Any?> {
        val now = System.currentTimeMillis()
        if (now - usageCacheAt < 20_000 && usageCache.isNotEmpty()) return usageCache
        if (!usageAccessGranted(context)) return mapOf("available" to false)
        return try {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val midnight = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            val events = usm.queryEvents(midnight, now)
            val event = UsageEvents.Event()
            val started = HashMap<String, Long>()
            val totals = HashMap<String, Long>()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val pkg = event.packageName ?: continue
                when (event.eventType) {
                    FG -> if (!started.containsKey(pkg)) started[pkg] = event.timeStamp
                    BG -> started.remove(pkg)?.let { totals[pkg] = (totals[pkg] ?: 0L) + (event.timeStamp - it) }
                }
            }
            started.forEach { (pkg, start) -> totals[pkg] = (totals[pkg] ?: 0L) + (now - start) }

            val ranked = totals.filter { it.value > 30_000 && it.key != context.packageName }
                .entries.sortedByDescending { it.value }
            val result = mapOf(
                "available" to true,
                "totalMs" to ranked.sumOf { it.value },
                "apps" to ranked.take(6).map {
                    mapOf("package" to it.key, "name" to appLabel(context, it.key), "ms" to it.value)
                }
            )
            usageCache = result
            usageCacheAt = now
            result
        } catch (_: Exception) {
            mapOf("available" to false)
        }
    }

    // ----------------------------------------------------------- snapshot

    fun snapshot(context: Context): Map<String, Any?> {
        val foreground = foregroundPackage(context)
        val usage = usageAccessGranted(context)
        return mapOf(
            "device" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            "sdk" to Build.VERSION.SDK_INT,
            "permissions" to mapOf(
                "overlay" to overlayGranted(context),
                "notificationAccess" to notificationAccessGranted(context),
                "usageAccess" to usage,
                "ignoringBatteryOptimizations" to ignoringBatteryOptimizations(context),
                "exactAlarms" to canScheduleExactAlarms(context),
                "bluetooth" to (Build.VERSION.SDK_INT < 31 ||
                    granted(context, android.Manifest.permission.BLUETOOTH_CONNECT)),
                "phoneState" to granted(context, android.Manifest.permission.READ_PHONE_STATE),
                "postNotifications" to (Build.VERSION.SDK_INT < 33 ||
                    granted(context, android.Manifest.permission.POST_NOTIFICATIONS)),
                "microphone" to granted(context, android.Manifest.permission.RECORD_AUDIO),
                "contacts" to granted(context, android.Manifest.permission.READ_CONTACTS),
                "callPhone" to granted(context, android.Manifest.permission.CALL_PHONE),
                "accessibility" to accessibilityEnabled(context)
            ),
            "assistant" to mapOf(
                "on" to IslandState.assistantOn,
                "state" to IslandState.assistantState,
                "heard" to IslandState.assistantHeard,
                "reply" to IslandState.assistantReply,
                "error" to IslandState.assistantError,
                "accessibilityConnected" to IslandState.a11yConnected,
                "hasKey" to AssistantConfig.apiKey.isNotBlank(),
                "model" to AssistantConfig.model
            ),
            "weather" to mapOf(
                "text" to IslandState.weatherText,
                "at" to IslandState.weatherAt
            ),
            "service" to mapOf(
                "running" to IslandState.running,
                "overlayAttached" to IslandState.overlayAttached,
                "listenerConnected" to IslandState.listenerConnected,
                "autostart" to IslandConfig.loadAutostart(context),
                "eventsShown" to IslandState.eventsShown,
                "lastEventTitle" to IslandState.lastEventTitle,
                "lastEventBody" to IslandState.lastEventBody,
                "lastEventAt" to IslandState.lastEventAt
            ),
            "notifications" to mapOf(
                "seen" to IslandState.notificationsSeen,
                "lastApp" to IslandState.lastNotificationApp,
                "lastAt" to IslandState.lastNotificationAt
            ),
            "media" to mapOf(
                "active" to IslandState.mediaActive,
                "playing" to IslandState.mediaPlaying,
                "title" to IslandState.mediaTitle,
                "artist" to IslandState.mediaArtist,
                "app" to IslandState.mediaApp
            ),
            "battery" to battery(context),
            "storage" to storage(),
            "memory" to memory(context),
            "network" to network(context),
            "audioDevices" to audioDevices(context),
            "foreground" to mapOf(
                "package" to (foreground ?: ""),
                "name" to (foreground?.let { appLabel(context, it) } ?: "")
            ),
            "screenTime" to (if (usage) screenTime(context) else mapOf("available" to false)),
            "prayer" to mapOf(
                "scheduled" to IslandState.prayersScheduled,
                "nextLabel" to IslandState.nextPrayerLabel,
                "nextAt" to IslandState.nextPrayerAt,
                "exactAlarms" to IslandState.exactAlarms
            )
        )
    }
}
