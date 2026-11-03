package com.codesoli.nova

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NovaNotificationListener : NotificationListenerService() {
    private val lastByPackage = HashMap<String, Long>()

    override fun onListenerConnected() {
        super.onListenerConnected()
        IslandState.listenerConnected = true
        if (IslandState.running) sendServiceAction(NovaIslandService.ACTION_MEDIA_REFRESH)
    }

    override fun onListenerDisconnected() {
        IslandState.listenerConnected = false
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.packageName == packageName) return
        val notification = sbn.notification ?: return
        val category = notification.category
        val isNavigation = category == Notification.CATEGORY_NAVIGATION ||
            sbn.packageName.contains("maps", ignoreCase = true) || sbn.packageName.contains("waze", ignoreCase = true)

        // Media notifications are handled through the media session.
        if (category == Notification.CATEGORY_TRANSPORT) {
            if (IslandState.running) sendServiceAction(NovaIslandService.ACTION_MEDIA_REFRESH)
            return
        }
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        if ((notification.flags and Notification.FLAG_ONGOING_EVENT) != 0 && !isNavigation) return

        val extras = notification.extras
        val appName = SystemData.appLabel(this, sbn.packageName)
        val title = extras.getCharSequence("android.title")?.toString()?.take(80).orEmpty()
        val body = (extras.getCharSequence("android.text")?.toString()
            ?: extras.getCharSequence("android.bigText")?.toString().orEmpty()).take(160)

        // Diagnostics: proves on the Device screen that notification access works.
        IslandState.notificationsSeen++
        IslandState.lastNotificationApp = appName
        IslandState.lastNotificationAt = System.currentTimeMillis()

        if (!IslandState.running) return
        val now = System.currentTimeMillis()
        val minGap = if (isNavigation) 30_000L else 2_500L
        if (now - (lastByPackage[sbn.packageName] ?: 0L) < minGap) return
        lastByPackage[sbn.packageName] = now

        val earbudBattery = parseEarbudBattery(sbn.packageName, "$title $body")
        if (earbudBattery != null) {
            sendServiceAction(NovaIslandService.ACTION_SHOW_EVENT, "audio", "audio", "Earbuds battery", earbudBattery)
            return
        }
        val heading = when {
            isNavigation -> "Navigation • $appName"
            title.isBlank() -> appName
            else -> "$appName • $title"
        }
        sendServiceAction(NovaIslandService.ACTION_SHOW_EVENT, "notification", sbn.packageName, heading, body)
    }

    private fun parseEarbudBattery(packageName: String, text: String): String? {
        val vendorApp = listOf("galaxywearable", "wearable", "nothing", "soundcore", "jbl", "sony", "xiaomi", "redmi", "realme", "oneplus", "bose", "huawei").any { packageName.contains(it, ignoreCase = true) }
        if (!vendorApp) return null
        val left = Regex("(?i)(?:left|L)\\s*[:：]?\\s*(\\d{1,3})\\s*%").find(text)?.groupValues?.get(1)
        val right = Regex("(?i)(?:right|R)\\s*[:：]?\\s*(\\d{1,3})\\s*%").find(text)?.groupValues?.get(1)
        val case = Regex("(?i)(?:case|charging case|box)\\s*[:：]?\\s*(\\d{1,3})\\s*%").find(text)?.groupValues?.get(1)
        val generic = Regex("(\\d{1,3})\\s*%").find(text)?.groupValues?.get(1)
        val parts = mutableListOf<String>()
        if (left != null && (left.toIntOrNull() ?: -1) in 0..100) parts.add("L $left%")
        if (right != null && (right.toIntOrNull() ?: -1) in 0..100) parts.add("R $right%")
        if (case != null && (case.toIntOrNull() ?: -1) in 0..100) parts.add("Case $case%")
        if (parts.isEmpty() && generic != null && (generic.toIntOrNull() ?: -1) in 0..100) parts.add("$generic%")
        return if (parts.isEmpty()) null else parts.joinToString(" • ")
    }

    private fun sendServiceAction(
        action: String,
        kind: String? = null,
        key: String? = null,
        title: String? = null,
        body: String? = null,
    ) {
        val event = Intent(this, NovaIslandService::class.java).setAction(action)
        if (kind != null) event.putExtra(NovaIslandService.EXTRA_KIND, kind)
        if (key != null) event.putExtra(NovaIslandService.EXTRA_KEY, key)
        if (title != null) event.putExtra(NovaIslandService.EXTRA_TITLE, title)
        if (body != null) event.putExtra(NovaIslandService.EXTRA_BODY, body)
        try {
            if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(event) else startService(event)
        } catch (_: Exception) { }
    }
}
