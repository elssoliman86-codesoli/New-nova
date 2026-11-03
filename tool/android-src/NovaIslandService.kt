package com.codesoli.nova

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.view.Gravity
import android.view.KeyEvent
import android.view.WindowManager
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/** One thing the pill can announce. */
private class IslandEvent(
    val kind: String,
    val key: String,
    val title: String,
    val body: String,
    val icon: String,
    val tint: Int,
    val priority: Int,
    val durationMs: Long,
)

class NovaIslandService : Service(), IslandHost, AssistantEngine.Ui {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var windowManager: WindowManager? = null
    private var view: IslandView? = null
    private var lastSignature = ""

    // events
    private var current: IslandEvent? = null
    private val queue = ArrayList<IslandEvent>()
    private var lastKey = ""
    private var lastBody = ""
    private var lastShownAt = 0L
    private var hiddenUntil = 0L
    private val expireRunnable = Runnable { expireCurrent() }

    // assistant
    private lateinit var assistant: AssistantEngine
    private var assistantStateName = "off"
    private var assistantText = ""

    // media
    private var mediaManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private var sessionsListener: MediaSessionManager.OnActiveSessionsChangedListener? = null

    // system
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var telephonyManager: TelephonyManager? = null
    private var phoneCallback: TelephonyCallback? = null
    private var legacyPhoneListener: PhoneStateListener? = null
    private var receiverRegistered = false
    private var audioCallback: AudioDeviceCallback? = null
    private var lastBattery = -1
    private var lastCharging = false
    private var lastNetwork = ""
    private var callState = TelephonyManager.CALL_STATE_IDLE

    // prayer
    private val prayerRunnable = Runnable { firePrayer() }
    private val firedPrayers = HashSet<Long>()
    private val weatherRunnable = object : Runnable {
        override fun run() {
            fetchWeather()
            main.postDelayed(this, 30 * 60 * 1000L)
        }
    }

    private val systemReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_TIME_TICK, Intent.ACTION_TIMEZONE_CHANGED -> if (current == null) renderCurrent(false)
                Intent.ACTION_BATTERY_CHANGED -> onBattery(intent)
                BluetoothDevice.ACTION_ACL_CONNECTED -> {
                    post("audio", "audio", "Bluetooth connected", btName(intent))
                    readBluetoothBattery(intent)
                }
                "android.bluetooth.device.action.BATTERY_LEVEL_CHANGED" -> readBluetoothBattery(intent)
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> post("audio", "audio", "Bluetooth disconnected", btName(intent))
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                    if (state == BluetoothAdapter.STATE_ON || state == BluetoothAdapter.STATE_OFF) {
                        post("audio", "btstate", "Bluetooth", if (state == BluetoothAdapter.STATE_ON) "Turned on" else "Turned off")
                    }
                }
                AudioManager.ACTION_HEADSET_PLUG -> {
                    val plugged = intent.getIntExtra("state", 0) == 1
                    post("audio", "audio", if (plugged) "Headset connected" else "Headset removed", "Wired")
                }
                ConnectivityManager.CONNECTIVITY_ACTION -> refreshNetwork(false)
            }
        }
    }

    private val mediaCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty()
            val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST).orEmpty()
            if (title.isBlank()) return
            val changed = title != IslandState.mediaTitle
            IslandState.mediaTitle = title
            IslandState.mediaArtist = artist
            IslandState.mediaActive = true
            if (changed) announceMedia("Now playing")
            else renderCurrent(false)
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            val playing = state?.state == PlaybackState.STATE_PLAYING
            val changed = playing != IslandState.mediaPlaying
            IslandState.mediaPlaying = playing
            if (state?.state == PlaybackState.STATE_STOPPED || state?.state == PlaybackState.STATE_NONE) {
                IslandState.mediaActive = false
            }
            if (changed && IslandState.mediaTitle.isNotBlank()) announceMedia(if (playing) "Playing" else "Paused")
            else renderCurrent(false)
        }

        override fun onSessionDestroyed() {
            IslandState.mediaActive = false
            IslandState.mediaPlaying = false
            main.post { refreshMediaSessions() }
        }
    }

    // ------------------------------------------------------------ lifecycle

    override fun onCreate() {
        super.onCreate()
        IslandConfig.load(this)
        AssistantConfig.load(this)
        IslandState.running = true
        createChannel()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        assistant = AssistantEngine(this, this)
        registerSystemReceivers()
        registerAudioCallback()
        registerNetworkCallback()
        registerPhoneState()
        main.post(weatherRunnable)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                IslandConfig.setAutostart(this, false)
                shutdown()
                return START_NOT_STICKY
            }
            ACTION_SHOW_EVENT, ACTION_SHOW_EVENT_FROM_SYSTEM -> {
                startAsForeground()
                post(
                    intent.getStringExtra(EXTRA_KIND) ?: "notification",
                    intent.getStringExtra(EXTRA_KEY) ?: "n",
                    intent.getStringExtra(EXTRA_TITLE) ?: "Notification",
                    intent.getStringExtra(EXTRA_BODY).orEmpty()
                )
            }
            ACTION_MEDIA_REFRESH -> { startAsForeground(); refreshMediaSessions() }
            ACTION_REFRESH_PERMISSIONS -> {
                startAsForeground()
                registerPhoneState()
                refreshMediaSessions()
                syncAssistant()
            }
            ACTION_MEDIA_CONTROL -> handleMediaControl(intent.getStringExtra(EXTRA_CONTROL).orEmpty())
            ACTION_CONFIG -> {
                startAsForeground()
                IslandConfig.load(this)
                syncAssistant()
                schedulePrayers()
                main.post(weatherRunnable.also { main.removeCallbacks(it) })
                renderCurrent(false)
            }
            ACTION_PRAYERS -> { startAsForeground(); schedulePrayers() }
            ACTION_PRAYER_ALARM -> { startAsForeground(); firePrayer() }
            ACTION_ASSISTANT_SUBMIT -> {
                startAsForeground()
                assistant.submit(intent.getStringExtra(EXTRA_BODY).orEmpty())
            }
            ACTION_ASSISTANT_LISTEN -> { startAsForeground(); assistant.listenNow() }
            else -> {
                startAsForeground()
                refreshMediaSessions()
                syncAssistant()
                schedulePrayers()
                renderCurrent(false)
            }
        }
        return START_STICKY
    }

    private fun shutdown() {
        main.removeCallbacksAndMessages(null)
        try { assistant.stop() } catch (_: Exception) { }
        removeView(animated = false)
        stopForegroundCompat()
        stopSelf()
    }

    @Suppress("DEPRECATION")
    private fun startAsForeground() {
        val openApp = packageManager.getLaunchIntentForPackage(packageName)
        val pending = openApp?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val notification = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("Nova Island is active")
                .setContentText("Tap to open Nova")
                .setOngoing(true).setContentIntent(pending).build()
        } else {
            Notification.Builder(this).setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("Nova Island is active").setOngoing(true).build()
        }
        if (Build.VERSION.SDK_INT >= 29) {
            var type = 0
            if (Build.VERSION.SDK_INT >= 34) type = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            if (Build.VERSION.SDK_INT >= 30 && AssistantConfig.enabled &&
                SystemData.granted(this, android.Manifest.permission.RECORD_AUDIO)
            ) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            try {
                startForeground(FOREGROUND_ID, notification, type)
            } catch (_: Exception) {
                try {
                    startForeground(FOREGROUND_ID, notification,
                        if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0)
                } catch (_: Exception) {
                    startForeground(FOREGROUND_ID, notification)
                }
            }
        } else {
            startForeground(FOREGROUND_ID, notification)
        }
    }

    // --------------------------------------------------------------- events

    private fun spec(kind: String): Triple<String, Int, Pair<Int, Long>> = when (kind) {
        "call" -> Triple("📞", 0xFF3DDC97.toInt(), 100 to 30_000L)
        "prayer" -> Triple("🕌", 0xFFFFB84D.toInt(), 80 to 20_000L)
        "test" -> Triple("✨", 0xFF42C8FF.toInt(), 60 to 4_000L)
        "battery" -> Triple("🔋", 0xFFFFB84D.toInt(), 50 to 4_000L)
        "audio" -> Triple("🎧", 0xFF398BFF.toInt(), 45 to 4_000L)
        "media" -> Triple("🎵", 0xFFFF6B9A.toInt(), 40 to 4_500L)
        "notification" -> Triple("🔔", 0xFF42C8FF.toInt(), 35 to 4_500L)
        "network" -> Triple("📶", 0xFF8C9BB5.toInt(), 20 to 3_000L)
        else -> Triple("●", 0xFF398BFF.toInt(), 30 to 4_000L)
    }

    private fun post(
        kind: String,
        key: String,
        title: String,
        body: String = "",
        icon: String? = null,
        durationMs: Long? = null,
    ) {
        if (kind != "test" && !IslandConfig.enabled(kind)) return
        val (defIcon, tint, pd) = spec(kind)
        val event = IslandEvent(kind, key, title, body, icon ?: defIcon, tint, pd.first, durationMs ?: pd.second)
        val now = System.currentTimeMillis()
        val cur = current
        if (cur != null && cur.key == key) { display(event, samePlace = true); return }
        if (cur != null && cur.priority > event.priority) {
            queue.removeAll { it.key == key }
            queue.add(event)
            if (queue.size > 6) queue.minByOrNull { it.priority }?.let { queue.remove(it) }
            return
        }
        if (key == lastKey && body == lastBody && now - lastShownAt < 4000) return
        display(event, samePlace = false)
    }

    private fun display(event: IslandEvent, samePlace: Boolean) {
        current = event
        lastKey = event.key
        lastBody = event.body
        lastShownAt = System.currentTimeMillis()
        IslandState.eventsShown++
        IslandState.lastEventTitle = event.title
        IslandState.lastEventBody = event.body
        IslandState.lastEventAt = lastShownAt
        main.removeCallbacks(expireRunnable)
        main.postDelayed(expireRunnable, event.durationMs)
        hiddenUntil = 0L
        renderCurrent(true)
        if (samePlace) view?.pop()
    }

    private fun expireCurrent() {
        current = null
        val next = queue.maxByOrNull { it.priority }
        if (next != null) {
            queue.remove(next)
            display(next, samePlace = false)
        } else {
            renderCurrent(false)
        }
    }

    private fun announceMedia(label: String) {
        val title = IslandState.mediaTitle
        val body = listOf(title, IslandState.mediaArtist).filter { it.isNotBlank() }.joinToString(" • ")
        post("media", "media", if (IslandState.mediaApp.isBlank()) label else "$label • ${IslandState.mediaApp}", body)
    }

    // -------------------------------------------------------------- display

    private fun idleModel(): IslandModel {
        val now = Date()
        val time = SimpleDateFormat("h:mm a", Locale.getDefault()).format(now)
        val date = SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(now)
        val weather = IslandState.weatherText
        val body = if (weather.isBlank()) date else "$date  ·  $weather"
        return IslandModel(
            icon = if (AssistantConfig.enabled) "🎙" else "🕒",
            title = time,
            body = body,
            tint = if (IslandState.assistantOn) 0xFF3DDC97.toInt() else 0xFF398BFF.toInt(),
            mic = AssistantConfig.enabled && AssistantConfig.apiKey.isNotBlank(),
        )
    }

    private fun assistantModel(): IslandModel? {
        val icon = when (assistantStateName) {
            "awake" -> "🎙"
            "thinking" -> "🧠"
            "speaking" -> "🔊"
            "error" -> "⚠"
            else -> return null
        }
        val tint = when (assistantStateName) {
            "error" -> 0xFFFF6B7A.toInt()
            "thinking" -> 0xFFFFB84D.toInt()
            else -> 0xFF3DDC97.toInt()
        }
        val title = when (assistantStateName) {
            "awake" -> if (assistantText.isBlank()) "Listening…" else assistantText
            "thinking" -> "Thinking…"
            "speaking" -> "Nova"
            else -> "Assistant"
        }
        val body = when (assistantStateName) {
            "thinking" -> assistantText
            "speaking" -> assistantText
            "error" -> assistantText
            else -> ""
        }
        return IslandModel(icon, title.take(60), body.take(90), tint)
    }

    private fun mediaModel(): IslandModel = IslandModel(
        icon = "🎵",
        title = IslandState.mediaTitle,
        body = IslandState.mediaArtist.ifBlank { IslandState.mediaApp },
        tint = 0xFFFF6B9A.toInt(),
        controls = true,
        playing = IslandState.mediaPlaying,
    )

    private fun renderCurrent(pop: Boolean) {
        val event = current
        val assistantModel = assistantModel()
        val model: IslandModel? = when {
            assistantModel != null -> assistantModel
            event != null -> IslandModel(
                icon = event.icon,
                title = event.title,
                body = event.body,
                tint = event.tint,
                controls = event.kind == "media",
                playing = IslandState.mediaPlaying,
            )
            System.currentTimeMillis() < hiddenUntil -> null
            IslandConfig.mediaMini && IslandState.mediaActive && IslandState.mediaTitle.isNotBlank() -> mediaModel()
            IslandConfig.idleEnabled -> idleModel()
            else -> null
        }
        if (model == null) { removeView(animated = true); return }
        show(model, pop)
    }

    private fun show(model: IslandModel, pop: Boolean) {
        if (!SystemData.overlayGranted(this)) {
            IslandState.overlayAttached = false
            return
        }
        val existing = view
        if (existing != null) {
            val signature = model.icon + model.title
            existing.render(model)
            if (pop && signature != lastSignature) existing.pop()
            lastSignature = signature
            return
        }
        val v = IslandView(this, this)
        v.render(model)
        lastSignature = model.icon + model.title
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = (8 * resources.displayMetrics.density).toInt()
            if (Build.VERSION.SDK_INT >= 28) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
        }
        try {
            windowManager?.addView(v, params)
            view = v
            IslandState.overlayAttached = true
            v.post { v.animateIn() }
        } catch (_: Exception) {
            IslandState.overlayAttached = false
        }
    }

    private fun removeView(animated: Boolean) {
        val v = view ?: return
        view = null
        IslandState.overlayAttached = false
        val remove = { try { windowManager?.removeView(v) } catch (_: Exception) { } }
        if (animated) v.animateOut { remove() } else remove()
    }

    // ----------------------------------------------------------- IslandHost

    override fun onControl(action: String) {
        when (action) {
            "mic" -> assistant.listenNow()
            "toggle" -> handleMediaControl(if (IslandState.mediaPlaying) "pause" else "play")
            else -> handleMediaControl(action)
        }
    }

    override fun onTap() {
        when {
            current != null -> { main.removeCallbacks(expireRunnable); expireCurrent() }
            AssistantConfig.enabled && AssistantConfig.apiKey.isNotBlank() -> assistant.listenNow()
            else -> openApp()
        }
    }

    override fun onLongPress() = openApp()

    override fun onDismissSwipe() {
        if (current != null) {
            main.removeCallbacks(expireRunnable)
            expireCurrent()
        } else {
            hiddenUntil = System.currentTimeMillis() + 2 * 60 * 1000L
            renderCurrent(false)
            main.postDelayed({ renderCurrent(false) }, 2 * 60 * 1000L + 200)
        }
    }

    private fun openApp() {
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try { startActivity(it) } catch (_: Exception) { }
        }
    }

    // --------------------------------------------------------- AssistantUi

    override fun assistantState(state: String, text: String) {
        main.post {
            assistantStateName = state
            assistantText = text
            IslandState.assistantState = state
            if (state == "awake" || state == "thinking" || state == "speaking" || state == "error") hiddenUntil = 0L
            renderCurrent(false)
        }
    }

    override fun mediaControl(action: String) = handleMediaControl(action)

    private fun syncAssistant() {
        AssistantConfig.load(this)
        if (AssistantConfig.enabled) {
            if (!assistant.isRunning) assistant.start()
        } else if (assistant.isRunning) {
            assistant.stop()
        }
    }

    // --------------------------------------------------------------- system

    private fun onBattery(intent: Intent) {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100).coerceAtLeast(1)
        val percent = if (level >= 0) level * 100 / scale else -1
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        if (percent < 0) return
        val previous = lastBattery
        val wasCharging = lastCharging
        lastBattery = percent
        lastCharging = charging
        if (previous < 0) return
        when {
            charging != wasCharging ->
                post("battery", "battery", if (charging) "Charging" else "Unplugged", "$percent%", if (charging) "⚡" else "🔌")
            !charging && ((percent <= 20 && previous > 20) || (percent <= 10 && previous > 10) || (percent <= 5 && previous > 5)) ->
                post("battery", "battery", "Battery low", "$percent%", "🪫")
            charging && percent == 100 && previous != 100 ->
                post("battery", "battery", "Fully charged", "100%", "🔋")
        }
        if (current == null) renderCurrent(false)
    }

    @Suppress("DEPRECATION")
    private fun registerSystemReceivers() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_TICK)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
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
            else registerReceiver(systemReceiver, filter)
            receiverRegistered = true
        } catch (_: Exception) { }
    }

    private fun btName(intent: Intent): String {
        val device: BluetoothDevice? = try {
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        } catch (_: Exception) { null }
        return try { device?.name?.take(26) ?: "Device" } catch (_: SecurityException) { "Device" }
    }

    private fun readBluetoothBattery(intent: Intent) {
        val level = intent.getIntExtra("android.bluetooth.device.extra.BATTERY_LEVEL", -1)
        if (level in 0..100) post("audio", "audio", "Headphone battery", btName(intent) + " • " + level + "%", "🎧")
    }

    private fun registerAudioCallback() {
        if (Build.VERSION.SDK_INT < 23) return
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioCallback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                addedDevices.firstNotNullOfOrNull { externalName(it) }?.let { post("audio", "audio", it.first, it.second) }
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                if (removedDevices.any { externalName(it) != null }) post("audio", "audio", "Audio device removed")
            }
        }
        try { audio.registerAudioDeviceCallback(audioCallback, main) } catch (_: Exception) { }
    }

    private fun externalName(device: AudioDeviceInfo): Pair<String, String>? {
        val name = device.productName?.toString().orEmpty()
        return when (device.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth audio connected" to name
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Headset connected" to "Wired"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB headset connected" to name
            else -> if (Build.VERSION.SDK_INT >= 31 &&
                (device.type == AudioDeviceInfo.TYPE_BLE_HEADSET || device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER)
            ) "Bluetooth LE audio connected" to name else null
        }
    }

    private fun registerNetworkCallback() {
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        lastNetwork = SystemData.network(this)
        if (Build.VERSION.SDK_INT >= 24) {
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = refreshNetwork(true)
                override fun onLost(network: Network) = refreshNetwork(true)
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = refreshNetwork(true)
            }
            networkCallback = callback
            try { connectivityManager?.registerDefaultNetworkCallback(callback) } catch (_: Exception) { }
        }
    }

    private fun refreshNetwork(fromCallback: Boolean) {
        main.post {
            val label = SystemData.network(this)
            if (label == lastNetwork) return@post
            lastNetwork = label
            post("network", "network", "Network", if (label == "Offline") "Offline" else "$label connected",
                if (label == "Offline") "📵" else "📶")
        }
    }

    private fun registerPhoneState() {
        if (Build.VERSION.SDK_INT >= 23 &&
            !SystemData.granted(this, android.Manifest.permission.READ_PHONE_STATE)
        ) return
        if (phoneCallback != null || legacyPhoneListener != null) return
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
        val previous = callState
        callState = state
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                assistant.pause()
                post("call", "call", "Incoming call", "Phone is ringing", "📞")
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                assistant.pause()
                post("call", "call", "On call", "Call in progress", "📞", 8_000L)
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (AssistantConfig.enabled) assistant.resume()
                if (previous != TelephonyManager.CALL_STATE_IDLE) post("call", "call", "Call ended", "", "📵", 3_000L)
            }
        }
    }

    // ---------------------------------------------------------------- media

    private fun refreshMediaSessions() {
        try {
            val manager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            mediaManager = manager
            val listener = ComponentName(this, NovaNotificationListener::class.java)
            if (sessionsListener == null) {
                val l = MediaSessionManager.OnActiveSessionsChangedListener { main.post { refreshMediaSessions() } }
                sessionsListener = l
                manager.addOnActiveSessionsChangedListener(l, listener)
            }
            val controllers = manager.getActiveSessions(listener)
            val controller = controllers.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
                ?: controllers.firstOrNull()
            if (controller?.sessionToken != activeController?.sessionToken) {
                try { activeController?.unregisterCallback(mediaCallback) } catch (_: Exception) { }
                activeController = controller
                controller?.registerCallback(mediaCallback)
            }
            if (controller == null) {
                IslandState.mediaActive = false
                IslandState.mediaPlaying = false
            } else {
                IslandState.mediaApp = SystemData.appLabel(this, controller.packageName)
                controller.metadata?.let { mediaCallback.onMetadataChanged(it) }
                controller.playbackState?.let { mediaCallback.onPlaybackStateChanged(it) }
            }
        } catch (_: SecurityException) {
            IslandState.mediaActive = false
        } catch (_: Exception) { }
    }

    private fun handleMediaControl(control: String) {
        val controls = activeController?.transportControls
        if (controls != null) {
            when (control) {
                "play" -> controls.play()
                "pause" -> controls.pause()
                "next" -> controls.skipToNext()
                "previous" -> controls.skipToPrevious()
            }
            return
        }
        // No media session access: send the hardware media key instead.
        val code = when (control) {
            "play", "pause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> return
        }
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
        } catch (_: Exception) { }
    }

    // --------------------------------------------------------------- prayer

    private fun schedulePrayers() {
        main.removeCallbacks(prayerRunnable)
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        IslandState.exactAlarms = SystemData.canScheduleExactAlarms(this)
        val pending = alarmIntent()
        try { alarmManager.cancel(pending) } catch (_: Exception) { }
        val now = System.currentTimeMillis()
        val prayers = IslandConfig.loadPrayers(this)
        IslandState.prayersScheduled = prayers.count { it.at > now }
        val next = if (IslandConfig.prayerAlerts) prayers.firstOrNull { it.at > now - 90_000 && it.at !in firedPrayers } else null
        if (next == null) {
            IslandState.nextPrayerLabel = ""
            IslandState.nextPrayerAt = 0L
            return
        }
        IslandState.nextPrayerLabel = next.label
        IslandState.nextPrayerAt = next.at
        val delay = next.at - now
        if (delay <= 0) { firePrayer(); return }
        main.postDelayed(prayerRunnable, delay)
        try {
            if (Build.VERSION.SDK_INT >= 23) {
                if (SystemData.canScheduleExactAlarms(this)) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at, pending)
                } else {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at, pending)
                }
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, next.at, pending)
            }
        } catch (_: Exception) { }
    }

    private fun alarmIntent(): PendingIntent {
        val intent = Intent(this, NovaIslandService::class.java).setAction(ACTION_PRAYER_ALARM)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= 26) PendingIntent.getForegroundService(this, 9001, intent, flags)
        else PendingIntent.getService(this, 9001, intent, flags)
    }

    private fun firePrayer() {
        val now = System.currentTimeMillis()
        val due = IslandConfig.loadPrayers(this)
            .firstOrNull { it.at <= now + 5_000 && it.at > now - 120_000 && it.at !in firedPrayers }
        if (due != null && IslandConfig.prayerAlerts) {
            firedPrayers.add(due.at)
            post("prayer", "prayer", due.label, due.body, "🕌")
        }
        schedulePrayers()
    }

    // -------------------------------------------------------------- weather

    private fun fetchWeather() {
        val lat = IslandConfig.latitude
        val lon = IslandConfig.longitude
        worker.execute {
            try {
                val url = URL("https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code")
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 8000
                conn.readTimeout = 8000
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                conn.disconnect()
                val reading = JSONObject(body).getJSONObject("current")
                val temp = Math.round(reading.getDouble("temperature_2m")).toInt()
                val code = reading.getInt("weather_code")
                val icon = when (code) {
                    0 -> "☀️"
                    1, 2 -> "🌤"
                    3 -> "☁️"
                    45, 48 -> "🌫"
                    in 51..57 -> "🌦"
                    in 61..67 -> "🌧"
                    in 71..77 -> "❄️"
                    in 80..82 -> "🌦"
                    in 95..99 -> "⛈"
                    else -> "🌡"
                }
                IslandState.weatherText = "$icon $temp°"
                IslandState.weatherAt = System.currentTimeMillis()
                main.post { if (current == null) renderCurrent(false) }
            } catch (_: Exception) {
                // Offline or no INTERNET: keep the previous value.
            }
        }
    }

    // ------------------------------------------------------------- plumbing

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        else stopForeground(true)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Nova Island", NotificationManager.IMPORTANCE_LOW))
        }
    }

    override fun onDestroy() {
        IslandState.running = false
        main.removeCallbacksAndMessages(null)
        try { assistant.stop() } catch (_: Exception) { }
        removeView(animated = false)
        try { if (receiverRegistered) unregisterReceiver(systemReceiver) } catch (_: Exception) { }
        try { audioCallback?.let { (getSystemService(Context.AUDIO_SERVICE) as AudioManager).unregisterAudioDeviceCallback(it) } } catch (_: Exception) { }
        try { networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) } } catch (_: Exception) { }
        try { if (Build.VERSION.SDK_INT >= 31) phoneCallback?.let { telephonyManager?.unregisterTelephonyCallback(it) } } catch (_: Exception) { }
        try {
            @Suppress("DEPRECATION")
            legacyPhoneListener?.let { telephonyManager?.listen(it, PhoneStateListener.LISTEN_NONE) }
        } catch (_: Exception) { }
        try { sessionsListener?.let { mediaManager?.removeOnActiveSessionsChangedListener(it) } } catch (_: Exception) { }
        try { activeController?.unregisterCallback(mediaCallback) } catch (_: Exception) { }
        worker.shutdown()
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
        const val ACTION_CONFIG = "com.codesoli.nova.CONFIG"
        const val ACTION_PRAYERS = "com.codesoli.nova.PRAYERS"
        const val ACTION_PRAYER_ALARM = "com.codesoli.nova.PRAYER_ALARM"
        const val ACTION_ASSISTANT_SUBMIT = "com.codesoli.nova.ASSISTANT_SUBMIT"
        const val ACTION_ASSISTANT_LISTEN = "com.codesoli.nova.ASSISTANT_LISTEN"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_KIND = "kind"
        const val EXTRA_KEY = "key"
        const val EXTRA_CONTROL = "control"
        private const val CHANNEL_ID = "nova_island_service"
        private const val FOREGROUND_ID = 7301
    }
}
