package com.codesoli.nova

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Brings the island back after a reboot or an app update when the user had it on. */
class NovaBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!IslandConfig.loadAutostart(context)) return
        if (!SystemData.overlayGranted(context)) return
        val start = Intent(context, NovaIslandService::class.java).setAction(NovaIslandService.ACTION_START)
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(start) else context.startService(start)
        } catch (_: Exception) {
            // Android may refuse a background start; the user can reopen Nova.
        }
    }
}
