package com.codesoli.nova

import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NovaNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.packageName == packageName) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence("android.title")?.toString()?.take(80) ?: sbn.packageName
        val body = (extras.getCharSequence("android.text")?.toString()
            ?: extras.getCharSequence("android.bigText")?.toString().orEmpty()).take(180)
        val event = Intent(this, NovaIslandService::class.java)
            .setAction(NovaIslandService.ACTION_SHOW_EVENT)
            .putExtra(NovaIslandService.EXTRA_TITLE, title)
            .putExtra(NovaIslandService.EXTRA_BODY, body)
        try {
            if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(event) else startService(event)
        } catch (_: Exception) { }
    }
}
