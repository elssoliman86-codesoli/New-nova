package com.codesoli.nova

import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NovaNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        sendServiceAction(NovaIslandService.ACTION_MEDIA_REFRESH)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.packageName == packageName) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence("android.title")?.toString()?.take(80) ?: sbn.packageName
        val body = (extras.getCharSequence("android.text")?.toString()
            ?: extras.getCharSequence("android.bigText")?.toString().orEmpty()).take(180)
        val category = sbn.notification.category
        val isNavigation = category == android.app.Notification.CATEGORY_NAVIGATION ||
            sbn.packageName.contains("maps", ignoreCase = true) || sbn.packageName.contains("waze", ignoreCase = true)
        val earbudBattery = parseEarbudBattery(sbn.packageName, title + " " + body)
        if (earbudBattery != null) {
            sendServiceAction(NovaIslandService.ACTION_SHOW_EVENT, "Earbuds battery", earbudBattery)
        } else {
            val displayTitle = if (isNavigation) "Navigation • $title" else title
            sendServiceAction(NovaIslandService.ACTION_SHOW_EVENT, displayTitle, body)
        }
        sendServiceAction(NovaIslandService.ACTION_MEDIA_REFRESH)
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
    }

    private fun sendServiceAction(action: String, title: String? = null, body: String? = null) {
        val event = Intent(this, NovaIslandService::class.java).setAction(action)
        if (title != null) event.putExtra(NovaIslandService.EXTRA_TITLE, title)
        if (body != null) event.putExtra(NovaIslandService.EXTRA_BODY, body)
        try {
            if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(event) else startService(event)
        } catch (_: Exception) { }
    }
}
