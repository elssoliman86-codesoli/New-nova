package com.codesoli.nova

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import java.util.concurrent.Executor

class NovaIslandService : Service() {
    private var windowManager: WindowManager? = null
    private var islandView: TextView? = null
    private var mediaManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var telephonyManager: TelephonyManager? = null
    private var phoneCallback: TelephonyCallback? = null
    private var legacyPhoneListener: PhoneStateListener? = null
    private var batteryReceiverRegistered = false
    private var deviceReceiverRegistered = false
    private var audioCallback: AudioDeviceCallback? = null
    private var lastBattery = -1
    private var lastCharging = false
    private var lastMediaTitle = ""
    private var mediaPlaying = false
    private var lastEventAt = 0L

    private val systemReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_BATTERY_CHANGED -> {
                    val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                    val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100).coerceAtLeast(1)
                    val percent = if (level >= 0) (level * 100 / scale) else -1
                    val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                    val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL
                    if (percent >= 0 && (percent != lastBattery || charging != lastCharging)) {
                        lastBattery = percent
                        lastCharging = charging
                        showText(if (charging) "Charging" else "Battery", "$percent%")
                    }
                }
                BluetoothDevice.ACTION_ACL_CONNECTED -> {
                    showText("Bluetooth", "Device connected")
                    readBluetoothBattery(intent)
                }
                "android.bluetooth.device.action.BATTERY_LEVEL_CHANGED" -> readBluetoothBattery(intent)
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> showText("Bluetooth", "Device disconnected")
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                    showText("Bluetooth", if (state == BluetoothAdapter.STATE_ON) "On" else "Off")
                }
                AudioManager.ACTION_HEADSET_PLUG -> {
                    val plugged = intent.getIntExtra("state", 0) == 1
                    showText("Headset", if (plugged) "Wired headset connected" else "Disconnected")
                }
                ConnectivityManager.CONNECTIVITY_ACTION -> refreshNetwork()
            }
        }
    }

    private val mediaCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty()
            val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST).orEmpty()
            if (title.isNotBlank()) {
                lastMediaTitle = title
                showText("Now Playing", listOf(title, artist).filter { it.isNotBlank() }.joinToString(" • "))
            }
        }
        override fun onPlaybackStateChanged(state: android.media.session.PlaybackState?) {
            if (lastMediaTitle.isNotBlank()) {
                mediaPlaying = state?.state == android.media.session.PlaybackState.STATE_PLAYING
                showText(if (mediaPlaying) "Playing" else "Paused", lastMediaTitle)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        registerSystemReceivers()
        registerAudioCallback()
        registerNetworkCallback()
        registerPhoneState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                removeIsland()
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SHOW_EVENT -> {
                startAsForeground()
                showEvent(intent.getStringExtra(EXTRA_TITLE) ?: "Notification",
                    intent.getStringExtra(EXTRA_BODY).orEmpty())
            }
            ACTION_MEDIA_REFRESH -> {
                startAsForeground()
                refreshMediaSessions()
            }
            ACTION_REFRESH_PERMISSIONS -> {
                startAsForeground()
                registerPhoneState()
                refreshMediaSessions()
            }
            ACTION_MEDIA_CONTROL -> handleMediaControl(intent.getStringExtra(EXTRA_CONTROL).orEmpty())
            ACTION_SHOW_EVENT_FROM_SYSTEM -> {
                startAsForeground()
                showText(intent.getStringExtra(EXTRA_TITLE) ?: "Nova", intent.getStringExtra(EXTRA_BODY).orEmpty())
            }
            else -> { startAsForeground(); showCompact(); refreshMediaSessions() }
        }
        return START_STICKY
    }

    private fun startAsForeground() {
        val openApp = packageManager.getLaunchIntentForPackage(packageName)
        val pending = openApp?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val notification = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("Nova Island is active")
                .setContentText("System events and supported media controls")
                .setOngoing(true).setContentIntent(pending).build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("Nova Island is active").setOngoing(true).build()
        }
        startForeground(FOREGROUND_ID, notification)
    }

    private fun showCompact() = showText("Nova", "System Island active")
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
            setOnClickListener { handleMediaControl(if (mediaPlaying) "pause" else "play") }
            setOnLongClickListener { handleMediaControl("next"); true }
        }.also { islandView = it }
        text.text = if (body.isBlank()) "●  $title" else "●  $title\n$body"
        if (text.parent == null) {
            @Suppress("DEPRECATION")
            val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else WindowManager.LayoutParams.TYPE_PHONE
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

    private fun registerSystemReceivers() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED)
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction("android.bluetooth.device.action.BATTERY_LEVEL_CHANGED")
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(AudioManager.ACTION_HEADSET_PLUG)
            addAction(ConnectivityManager.CONNECTIVITY_ACTION)
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(systemReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            else @Suppress("DEPRECATION") registerReceiver(systemReceiver, filter)
            batteryReceiverRegistered = true
            deviceReceiverRegistered = true
        } catch (_: Exception) { }
    }

    private fun registerAudioCallback() {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioCallback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                addedDevices.firstOrNull()?.let { showText("Audio device", deviceName(it)) }
            }
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                if (removedDevices.isNotEmpty()) showText("Audio device", "Disconnected")
            }
        }
        audio.registerAudioDeviceCallback(audioCallback, null)
    }

    private fun deviceName(device: AudioDeviceInfo): String = when (device.type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth headset connected"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headset connected"
        else -> "Audio device connected"
    }

    private fun registerNetworkCallback() {
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        if (Build.VERSION.SDK_INT >= 24) {
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = refreshNetwork()
                override fun onLost(network: Network) = refreshNetwork()
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = refreshNetwork()
            }
            networkCallback = callback
            try { connectivityManager?.registerDefaultNetworkCallback(callback) } catch (_: Exception) { }
        }
    }

    private fun refreshNetwork() {
        val cm = connectivityManager ?: return
        val network = cm.activeNetwork
        val caps = network?.let { cm.getNetworkCapabilities(it) }
        val label = when {
            caps == null -> "Offline"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi connected"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile data connected"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet connected"
            else -> "Network connected"
        }
        showText("Network", label)
    }

    private fun registerPhoneState() {
        if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) != android.content.pm.PackageManager.PERMISSION_GRANTED) return
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                val executor: Executor = mainExecutor
                val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) = onPhoneState(state)
                }
                phoneCallback = callback
                telephonyManager?.registerTelephonyCallback(executor, callback)
            } else {
                @Suppress("DEPRECATION")
                val listener = object : PhoneStateListener() {
                    @Suppress("DEPRECATION")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) = onPhoneState(state)
                }
                legacyPhoneListener = listener
                @Suppress("DEPRECATION")
                telephonyManager?.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            }
        } catch (_: SecurityException) { }
    }

    private fun onPhoneState(state: Int) {
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> showText("Incoming call", "Phone is ringing")
            TelephonyManager.CALL_STATE_OFFHOOK -> showText("Call", "Call in progress")
            TelephonyManager.CALL_STATE_IDLE -> showText("Call", "Call ended")
        }
    }

    private fun readBluetoothBattery(intent: Intent) {
        val device: BluetoothDevice? = try {
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        } catch (_: Exception) { null }
        var level = intent.getIntExtra("android.bluetooth.device.extra.BATTERY_LEVEL", -1)

        val name = try { device?.name?.take(24) } catch (_: SecurityException) { null }
        if (level in 0..100) showText("Headphone battery", (name ?: "Bluetooth device") + " • " + level + "%")
        else showText("Headphones", (name ?: "Bluetooth device") + " connected • battery unavailable")
    }

    private fun refreshMediaSessions() {
        try {
            mediaManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val listener = componentName
            val controllers = mediaManager?.getActiveSessions(listener).orEmpty()
            val controller = controllers.firstOrNull()
            if (controller !== activeController) {
                activeController?.unregisterCallback(mediaCallback)
                activeController = controller
                controller?.registerCallback(mediaCallback)
            }
            controller?.metadata?.let { mediaCallback.onMetadataChanged(it) }
            controller?.playbackState?.let { mediaCallback.onPlaybackStateChanged(it) }
        } catch (_: SecurityException) {
            showText("Media", "Enable Nova notification access")
        } catch (_: Exception) { }
    }

    private fun handleMediaControl(control: String) {
        val controls = activeController?.transportControls ?: return
        when (control) {
            "play" -> controls.play()
            "pause" -> controls.pause()
            "next" -> controls.skipToNext()
            "previous" -> controls.skipToPrevious()
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
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

    override fun onDestroy() {
        removeIsland()
        try { if (batteryReceiverRegistered) unregisterReceiver(systemReceiver) } catch (_: Exception) { }
        try { audioCallback?.let { (getSystemService(Context.AUDIO_SERVICE) as AudioManager).unregisterAudioDeviceCallback(it) } } catch (_: Exception) { }
        try { networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) } } catch (_: Exception) { }
        try { if (Build.VERSION.SDK_INT >= 31) phoneCallback?.let { telephonyManager?.unregisterTelephonyCallback(it) } } catch (_: Exception) { }
        try {
            @Suppress("DEPRECATION")
            legacyPhoneListener?.let { telephonyManager?.listen(it, PhoneStateListener.LISTEN_NONE) }
        } catch (_: Exception) { }
        try { activeController?.unregisterCallback(mediaCallback) } catch (_: Exception) { }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.codesoli.nova.START_ISLAND"
        const val ACTION_STOP = "com.codesoli.nova.STOP_ISLAND"
        const val ACTION_SHOW_EVENT = "com.codesoli.nova.SHOW_EVENT"
        const val ACTION_MEDIA_REFRESH = "com.codesoli.nova.MEDIA_REFRESH"
        const val ACTION_REFRESH_PERMISSIONS = "com.codesoli.nova.REFRESH_PERMISSIONS"
        const val ACTION_MEDIA_CONTROL = "com.codesoli.nova.MEDIA_CONTROL"
        const val ACTION_SHOW_EVENT_FROM_SYSTEM = "com.codesoli.nova.SYSTEM_EVENT"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_CONTROL = "control"
        private const val CHANNEL_ID = "nova_island_service"
        private const val FOREGROUND_ID = 7301
    }
}

private object SettingsCompat {
    fun canDraw(context: Context): Boolean =
        Build.VERSION.SDK_INT < 23 || android.provider.Settings.canDrawOverlays(context)
}
