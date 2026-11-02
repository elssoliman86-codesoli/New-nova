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
        val displayTitle = if (isNavigation) "Navigation • $title" else title
        sendServiceAction(NovaIslandService.ACTION_SHOW_EVENT, displayTitle, body)
        sendServiceAction(NovaIslandService.ACTION_MEDIA_REFRESH)
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
