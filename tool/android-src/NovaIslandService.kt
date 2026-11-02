package com.codesoli.nova

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView

class NovaIslandService : Service() {
    private var windowManager: WindowManager? = null
    private var islandView: TextView? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { removeIsland(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY }
            ACTION_SHOW_EVENT -> {
                startAsForeground()
                showEvent(intent.getStringExtra(EXTRA_TITLE) ?: "Notification",
                    intent.getStringExtra(EXTRA_BODY).orEmpty())
            }
            else -> { startAsForeground(); showCompact() }
        }
        return START_STICKY
    }

    private fun startAsForeground() {
        val openApp = packageManager.getLaunchIntentForPackage(packageName)
        val pending = openApp?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val notification = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Nova Island is active")
                .setContentText("Tap to open Nova settings")
                .setOngoing(true).setContentIntent(pending).build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Nova Island is active").setOngoing(true).build()
        }
        startForeground(FOREGROUND_ID, notification)
    }

    private fun showCompact() = showText("Nova", "")
    private fun showEvent(title: String, body: String) = showText(title, body)

    private fun showText(title: String, body: String) {
        if (!SettingsCompat.canDraw(this)) return
        val text = islandView ?: TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(28, 16, 28, 16)
            background = GradientDrawable().apply {
                setColor(Color.BLACK)
                cornerRadius = 100f
                setStroke(1, 0xFF30343B.toInt())
            }
            elevation = 18f
            setOnClickListener { text = "Nova Island • tap Nova to manage" }
        }.also { islandView = it }
        text.text = if (body.isBlank()) "●  $title" else "●  $title\n$body"
        if (text.parent == null) {
            val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; y = 8 }
            try { windowManager?.addView(text, params) } catch (_: Exception) { }
        }
    }

    private fun removeIsland() {
        islandView?.let { try { windowManager?.removeView(it) } catch (_: Exception) { } }
        islandView = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Nova Island", NotificationManager.IMPORTANCE_LOW))
        }
    }

    override fun onDestroy() { removeIsland(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.codesoli.nova.START_ISLAND"
        const val ACTION_STOP = "com.codesoli.nova.STOP_ISLAND"
        const val ACTION_SHOW_EVENT = "com.codesoli.nova.SHOW_EVENT"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        private const val CHANNEL_ID = "nova_island_service"
        private const val FOREGROUND_ID = 7301
    }
}

private object SettingsCompat {
    fun canDraw(context: Context): Boolean =
        Build.VERSION.SDK_INT < 23 || android.provider.Settings.canDrawOverlays(context)
}
