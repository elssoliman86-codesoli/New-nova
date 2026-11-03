package com.codesoli.nova

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.Executors

object AssistantConfig {
    private const val PREFS = "nova_assistant"

    @Volatile var enabled = false
    @Volatile var apiKey = ""
    @Volatile var model = "meta/llama-3.3-70b-instruct"
    @Volatile var baseUrl = "https://integrate.api.nvidia.com/v1"
    @Volatile var wakeWords = "نوفا,nova"
    @Volatile var language = "ar-EG"
    @Volatile var speak = true
    @Volatile var requireWake = true
    @Volatile private var loaded = false

    fun load(context: Context) {
        if (loaded) return
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        enabled = p.getBoolean("enabled", false)
        apiKey = p.getString("key", "") ?: ""
        model = p.getString("model", model) ?: model
        baseUrl = p.getString("base", baseUrl) ?: baseUrl
        wakeWords = p.getString("wake", wakeWords) ?: wakeWords
        language = p.getString("lang", language) ?: language
        speak = p.getBoolean("speak", true)
        requireWake = p.getBoolean("requireWake", true)
        loaded = true
    }

    fun save(context: Context, map: Map<*, *>) {
        load(context)
        (map["enabled"] as? Boolean)?.let { enabled = it }
        (map["apiKey"] as? String)?.let { apiKey = it.trim() }
        (map["model"] as? String)?.takeIf { it.isNotBlank() }?.let { model = it.trim() }
        (map["baseUrl"] as? String)?.takeIf { it.isNotBlank() }?.let { baseUrl = it.trim().trimEnd('/') }
        (map["wakeWords"] as? String)?.takeIf { it.isNotBlank() }?.let { wakeWords = it }
        (map["language"] as? String)?.takeIf { it.isNotBlank() }?.let { language = it }
        (map["speak"] as? Boolean)?.let { speak = it }
        (map["requireWake"] as? Boolean)?.let { requireWake = it }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("enabled", enabled).putString("key", apiKey).putString("model", model)
            .putString("base", baseUrl).putString("wake", wakeWords).putString("lang", language)
            .putBoolean("speak", speak).putBoolean("requireWake", requireWake).apply()
    }
}

/** Minimal OpenAI-compatible chat call (NVIDIA API catalog). */
object NvidiaClient {
    fun chat(messages: JSONArray, maxTokens: Int = 700): String {
        val url = URL(AssistantConfig.baseUrl.trimEnd('/') + "/chat/completions")
        val conn = url.openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 15000
            conn.readTimeout = 60000
            conn.doOutput = true
            conn.setRequestProperty("Authorization", "Bearer " + AssistantConfig.apiKey)
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "application/json")
            val body = JSONObject()
                .put("model", AssistantConfig.model)
                .put("messages", messages)
                .put("temperature", 0.3)
                .put("max_tokens", maxTokens)
                .put("stream", false)
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code !in 200..299) {
                val msg = try {
                    JSONObject(text).optJSONObject("error")?.optString("message")
                        ?: JSONObject(text).optString("detail")
                } catch (_: Exception) { "" }
                throw RuntimeException("HTTP $code ${msg.ifBlank { text.take(120) }}")
            }
            val content = JSONObject(text).getJSONArray("choices").getJSONObject(0)
                .getJSONObject("message").optString("content")
            return content.replace(Regex("(?s)<think>.*?</think>"), "").trim()
        } finally {
            conn.disconnect()
        }
    }
}

/**
 * Voice assistant: keeps the speech recogniser running, waits for the wake
 * word (or reacts to everything when wake word is off), asks the model what
 * to do, then executes the actions and answers by voice.
 */
class AssistantEngine(private val context: Context, private val ui: Ui) : RecognitionListener {

    interface Ui {
        /** state: off, listening, awake, thinking, speaking, error */
        fun assistantState(state: String, text: String)
        fun mediaControl(action: String)
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val commands = Commands(context)
    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var running = false
    private var paused = false
    private var busy = false
    private var dictating = false
    private var awakeUntil = 0L
    private var errorStreak = 0

    // Two stages: a silent offline wake-word detector (does not touch audio
    // focus), and the speech recogniser that only runs after the wake word.
    private var detector: WakeWordDetector? = null
    private var passive = false
    private var active = false
    private var activeUntil = 0L
    private var wasPlaying = false
    private var mediaActionTaken = false
    private val history = ArrayList<Pair<String, String>>()

    private val listenRunnable = Runnable { listen() }

    // ----------------------------------------------------------- lifecycle

    fun start() {
        if (running) return
        AssistantConfig.load(context)
        if (!SystemData.granted(context, android.Manifest.permission.RECORD_AUDIO)) {
            fail("Microphone permission is missing")
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            fail("No speech recognition service. Install or enable the Google app.")
            return
        }
        running = true
        IslandState.assistantOn = true
        initTts()
        createRecognizer()
        publish("listening", "")
        if (AssistantConfig.requireWake) startDetector()
        scheduleListen(200)
    }

    private fun startDetector() {
        val words = AssistantConfig.wakeWords.split(',', ';', '،').map { it.trim().lowercase(Locale.ROOT) }
            .filter { it.isNotEmpty() && it.all { c -> c in 'a'..'z' || c == ' ' } }
            .ifEmpty { listOf("nova") }.toSet()
        val d = WakeWordDetector(
            context, words,
            onReady = { main.post { passive = true; IslandState.wakeOffline = true; cancelRecognizer() } },
            onWake = { main.post { if (running && !busy && !active) activate(10_000) } }
        )
        detector = d
        d.start()
    }

    private fun cancelRecognizer() {
        main.removeCallbacks(listenRunnable)
        try { recognizer?.cancel() } catch (_: Exception) { }
    }

    /** The user said the wake word: listen for one command, then go back to waiting. */
    private fun activate(durationMs: Long) {
        active = true
        activeUntil = System.currentTimeMillis() + durationMs
        awakeUntil = activeUntil
        wasPlaying = IslandState.mediaPlaying
        mediaActionTaken = false
        detector?.pause()
        publish("awake", "")
        scheduleListen(40)
    }

    private fun deactivate() {
        active = false
        main.removeCallbacks(listenRunnable)
        try { recognizer?.cancel() } catch (_: Exception) { }
        if (!dictating) publish("listening", "")
        detector?.resume()
        // The recogniser can pause the music: bring it back if we caused that.
        if (wasPlaying && !mediaActionTaken) {
            val resume = Runnable { if (!IslandState.mediaPlaying) ui.mediaControl("play") }
            main.postDelayed(resume, 1200)
        }
        wasPlaying = false
    }

    fun stop() {
        running = false
        main.removeCallbacks(listenRunnable)
        detector?.stop()
        detector = null
        passive = false
        active = false
        IslandState.wakeOffline = false
        try { recognizer?.cancel(); recognizer?.destroy() } catch (_: Exception) { }
        recognizer = null
        try { tts?.stop(); tts?.shutdown() } catch (_: Exception) { }
        tts = null
        ttsReady = false
        busy = false
        dictating = false
        IslandState.assistantOn = false
        publish("off", "")
    }

    fun pause() {
        paused = true
        detector?.pause()
        main.removeCallbacks(listenRunnable)
        try { recognizer?.cancel() } catch (_: Exception) { }
    }

    fun resume() {
        if (!running) return
        paused = false
        if (passive) { active = false; detector?.resume() } else scheduleListen(500)
    }

    val isRunning: Boolean get() = running

    /** Typed or tapped command: runs without needing the wake word. */
    fun submit(text: String) {
        if (text.isBlank()) return
        main.post {
            if (!running) {
                AssistantConfig.load(context)
                initTts()
            }
            runCommand(text.trim())
        }
    }

    /** Mic button: listen for one command without a wake word. */
    fun listenNow() {
        if (running) {
            if (!busy) activate(10_000)
        } else {
            awakeUntil = System.currentTimeMillis() + 10_000
            start()
        }
    }

    private fun publish(state: String, text: String) {
        IslandState.assistantState = state
        ui.assistantState(state, text)
    }

    private fun fail(message: String) {
        IslandState.assistantError = message
        IslandState.assistantOn = false
        publish("error", message)
    }

    // -------------------------------------------------------------- speech

    private fun createRecognizer() {
        try { recognizer?.destroy() } catch (_: Exception) { }
        recognizer = SpeechRecognizer.createSpeechRecognizer(context).also { it.setRecognitionListener(this) }
    }

    private fun scheduleListen(delayMs: Long) {
        main.removeCallbacks(listenRunnable)
        main.postDelayed(listenRunnable, delayMs)
    }

    private fun listen() {
        if (!running || paused || busy) return
        if (passive && !active) return
        // Without the offline wake word the recogniser would interrupt music
        // and videos, so it only runs while nothing is playing.
        if (!passive && !active && !dictating && IslandState.mediaPlaying) {
            scheduleListen(2500)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, AssistantConfig.language)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1400L)
        }
        try {
            recognizer?.startListening(intent)
        } catch (_: Exception) {
            createRecognizer()
            scheduleListen(1000)
        }
    }

    override fun onReadyForSpeech(params: Bundle?) {
        IslandState.assistantError = ""
    }

    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onEvent(eventType: Int, params: Bundle?) {}

    override fun onPartialResults(partialResults: Bundle?) {
        val text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
        val awake = dictating || System.currentTimeMillis() < awakeUntil || findWake(text) != null
        if (awake) publish("awake", text)
    }

    override fun onResults(results: Bundle?) {
        errorStreak = 0
        val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
        if (text.isNotBlank()) handleHeard(text.trim())
        if (!busy) {
            if (passive) {
                if (System.currentTimeMillis() < activeUntil || dictating) scheduleListen(250) else deactivate()
            } else {
                if (System.currentTimeMillis() >= awakeUntil && !dictating) publish("listening", "")
                scheduleListen(250)
            }
        }
    }

    override fun onError(error: Int) {
        when (error) {
            SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                if (passive) {
                    if (System.currentTimeMillis() < activeUntil || dictating) scheduleListen(200) else deactivate()
                } else {
                    if (!dictating && System.currentTimeMillis() >= awakeUntil) publish("listening", "")
                    scheduleListen(200)
                }
            }
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> { createRecognizer(); scheduleListen(1200) }
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                running = false
                fail("Microphone permission was revoked")
            }
            SpeechRecognizer.ERROR_CLIENT -> scheduleListen(600)
            else -> {
                errorStreak++
                if (errorStreak >= 4) {
                    IslandState.assistantError = "Speech service error $error (check internet / Google app)"
                    publish("error", IslandState.assistantError)
                }
                if (passive) {
                    deactivate()
                } else {
                    val backoff = minOf(30_000L, 1000L shl minOf(errorStreak, 5))
                    scheduleListen(backoff)
                }
            }
        }
    }

    // ------------------------------------------------------------ wake word

    private fun wakeRegex(): Regex {
        val words = (AssistantConfig.wakeWords.split(',', '،', ';').map { it.trim() } +
            listOf("نوفا", "نوڤا", "nova")).filter { it.isNotEmpty() }.distinct()
        val alt = words.joinToString("|") { Regex.escape(it) }
        return Regex("(?:(?:يا|يا |hey |hi |ok |okay )\\s*)?(?:$alt)", RegexOption.IGNORE_CASE)
    }

    /** Text after the wake word, or null when the wake word is absent. */
    private fun findWake(text: String): String? {
        val m = wakeRegex().find(text) ?: return null
        return text.removeRange(m.range).trim().trim(',', '،', '.', '!', '؟', '?', ' ')
    }

    private fun handleHeard(text: String) {
        IslandState.assistantHeard = text
        if (dictating) { handleDictation(text); return }
        val now = System.currentTimeMillis()
        val afterWake = findWake(text)
        val command = when {
            afterWake != null -> afterWake
            passive || now < awakeUntil || !AssistantConfig.requireWake -> text
            else -> return
        }
        if (command.isBlank()) {
            awakeUntil = now + 8000
            activeUntil = awakeUntil
            publish("awake", "")
            if (!passive) speak("نعم؟", flush = true, resumeAfter = false)
            return
        }
        runCommand(command)
    }

    private fun handleDictation(text: String) {
        val norm = Commands.normalize(text)
        val stops = listOf("خلاص", "وقف", "كفايه", "انهي", "تم", "stop", "done", "finish")
        if (stops.any { norm == it || norm.endsWith(" $it") }) {
            dictating = false
            publish("listening", "")
            speak("تمام", flush = true, resumeAfter = false)
            return
        }
        val ok = NovaAccessibilityService.typeText(text)
        publish("awake", if (ok) "✍ $text" else "Enable Nova accessibility to type")
    }

    // ---------------------------------------------------------------- brain

    private fun systemPrompt(): String {
        val now = Calendar.getInstance()
        val clock = "%04d-%02d-%02d %02d:%02d".format(
            now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1, now.get(Calendar.DAY_OF_MONTH),
            now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE)
        )
        return """
You are Nova, a voice assistant living on the user's Android phone. The user usually speaks Egyptian Arabic (sometimes English). Reply in the user's language, short and natural, because your reply is spoken aloud.
Current local time: $clock.
Answer ONLY with one JSON object, no markdown:
{"say":"short spoken reply","actions":[ ... ]}
Use an empty actions list when no phone action is needed (questions, chat, facts).
Allowed actions (use exactly these types):
{"type":"call","target":"contact name or phone number"}
{"type":"whatsapp","target":"contact name or number (may be empty)","text":"message to send (may be empty)"}
{"type":"telegram"}
{"type":"youtube","query":"what to play on YouTube"}
{"type":"music","query":"song and artist","app":"auto|spotify|youtube"}
{"type":"search","query":"google search text"}
{"type":"open_app","name":"app name as shown on the phone"}
{"type":"read_screen","mode":"read|translate|summarize","language":"target language for translate"}
{"type":"dictate"}   (user wants you to type what they say into the focused text field)
{"type":"type","text":"text to type now"}
{"type":"media","action":"play|pause|next|previous"}
{"type":"back"} {"type":"home"}
Rules: put "open_app" before "read_screen" when asked to open something then read it. Never invent contacts. If the request is unclear, ask a short question in "say" with no actions.
""".trim()
    }

    private fun runCommand(command: String) {
        if (busy) return
        busy = true
        dictating = false
        try { recognizer?.cancel() } catch (_: Exception) { }
        main.removeCallbacks(listenRunnable)
        publish("thinking", command)
        if (AssistantConfig.apiKey.isBlank()) {
            finish("Add your NVIDIA API key in Nova > Assistant first.")
            return
        }
        worker.execute {
            try {
                val messages = JSONArray().put(JSONObject().put("role", "system").put("content", systemPrompt()))
                history.takeLast(6).forEach { (u, a) ->
                    messages.put(JSONObject().put("role", "user").put("content", u))
                    messages.put(JSONObject().put("role", "assistant").put("content", a))
                }
                messages.put(JSONObject().put("role", "user").put("content", command))
                val raw = NvidiaClient.chat(messages)
                val parsed = parse(raw)
                val say = parsed.optString("say")
                synchronized(history) {
                    history.add(command to raw.take(600))
                    if (history.size > 10) history.removeAt(0)
                }
                val actions = parsed.optJSONArray("actions") ?: JSONArray()
                main.post { if (say.isNotBlank()) speak(say, flush = true, resumeAfter = false) }
                runActions(actions, say)
            } catch (e: Exception) {
                main.post { finish("Error: " + (e.message ?: "request failed").take(120)) }
            }
        }
    }

    private fun parse(raw: String): JSONObject {
        val start = raw.indexOf('{')
        val end = raw.lastIndexOf('}')
        if (start >= 0 && end > start) {
            try { return JSONObject(raw.substring(start, end + 1)) } catch (_: Exception) { }
        }
        return JSONObject().put("say", raw.take(400))
    }

    private fun runActions(actions: JSONArray, say: String) {
        var note = say
        for (i in 0 until actions.length()) {
            val a = actions.optJSONObject(i) ?: continue
            if (a.optString("type") in setOf("youtube", "music", "media")) mediaActionTaken = true
            val result: String? = try {
                when (a.optString("type")) {
                    "call" -> commands.call(a.optString("target"))
                    "whatsapp" -> commands.whatsapp(a.optString("target"), a.optString("text"))
                    "telegram" -> commands.telegram()
                    "youtube" -> commands.playYoutube(a.optString("query"))
                    "music" -> commands.playMusic(a.optString("query"), a.optString("app", "auto"))
                    "search" -> commands.webSearch(a.optString("query"))
                    "open_app" -> commands.openApp(a.optString("name"))?.let { "Opened $it" }
                        ?: "App not found: ${a.optString("name")}"
                    "media" -> { main.post { ui.mediaControl(a.optString("action")) }; null }
                    "type" -> if (NovaAccessibilityService.typeText(a.optString("text"))) null
                        else "Enable Nova accessibility to type"
                    "dictate" -> {
                        main.post { dictating = true }
                        if (NovaAccessibilityService.instance == null) "Enable Nova accessibility to type" else null
                    }
                    "back" -> { NovaAccessibilityService.global(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK); null }
                    "home" -> { NovaAccessibilityService.global(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME); null }
                    "read_screen" -> readScreen(a.optString("mode", "read"), a.optString("language", "Arabic"))
                    else -> null
                }
            } catch (e: Exception) {
                "Action failed: " + (e.message ?: "").take(80)
            }
            if (result != null) note = result
            if (i < actions.length() - 1) Thread.sleep(1800)
        }
        main.post { finish(note, speakNote = false) }
    }

    private fun readScreen(mode: String, language: String): String? {
        val text = NovaAccessibilityService.readScreen()
            ?: return if (NovaAccessibilityService.instance == null) {
                main.post { speak("فعّل خدمة إمكانية الوصول لنوفا عشان أقدر أقرأ الشاشة", flush = true, resumeAfter = false) }
                "Enable Nova accessibility to read the screen"
            } else "Nothing readable on screen"
        if (mode == "read") {
            main.post { speakLong(text) }
            return "Reading the screen"
        }
        val task = if (mode == "translate") "Translate this screen text to $language. Output only the translation."
        else "Summarize this screen text briefly in the user's language."
        val messages = JSONArray()
            .put(JSONObject().put("role", "system").put("content", task))
            .put(JSONObject().put("role", "user").put("content", text.take(9000)))
        val answer = NvidiaClient.chat(messages, 1200)
        main.post { speakLong(answer) }
        return answer.take(160)
    }

    private fun finish(note: String, speakNote: Boolean = true) {
        IslandState.assistantReply = note
        busy = false
        val followUp = !passive || active
        awakeUntil = System.currentTimeMillis() + 7000
        if (followUp) activeUntil = awakeUntil
        if (speakNote && AssistantConfig.speak) speak(note, flush = true, resumeAfter = followUp)
        else if (!speaking && followUp) scheduleListen(400)
        publish("awake", note)
        main.postDelayed({
            if (System.currentTimeMillis() >= awakeUntil - 200 && !dictating && !busy) {
                if (passive && active) deactivate() else if (!passive) publish("listening", "")
                else publish("listening", "")
            }
        }, 7200)
    }

    // ------------------------------------------------------------------ tts

    @Volatile private var speaking = false

    private fun initTts() {
        if (tts != null) return
        tts = TextToSpeech(context) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) { speaking = true }
                override fun onDone(utteranceId: String?) {
                    speaking = false
                    if (utteranceId == "end") main.post { if (running && !busy) scheduleListen(350) }
                }
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    speaking = false
                    main.post { if (running && !busy) scheduleListen(350) }
                }
            })
        }
    }

    private fun speak(text: String, flush: Boolean, resumeAfter: Boolean) {
        if (!AssistantConfig.speak || text.isBlank()) return
        val engine = tts
        if (engine == null || !ttsReady) { scheduleListen(400); return }
        val arabic = text.any { it in '؀'..'ۿ' }
        try { engine.setLanguage(if (arabic) Locale("ar") else Locale.US) } catch (_: Exception) { }
        try { recognizer?.cancel() } catch (_: Exception) { }
        main.removeCallbacks(listenRunnable)
        val id = if (resumeAfter) "end" else "say"
        engine.speak(text.take(3500), if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD, null, id)
        if (!resumeAfter) scheduleListen(2500)
        publish("speaking", text)
    }

    private fun speakLong(text: String) {
        if (!AssistantConfig.speak) return
        val engine = tts ?: return
        if (!ttsReady) return
        val arabic = text.any { it in '؀'..'ۿ' }
        try { engine.setLanguage(if (arabic) Locale("ar") else Locale.US) } catch (_: Exception) { }
        try { recognizer?.cancel() } catch (_: Exception) { }
        main.removeCallbacks(listenRunnable)
        val chunks = text.chunked(3000)
        chunks.forEachIndexed { i, chunk ->
            engine.speak(chunk, if (i == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD, null,
                if (i == chunks.lastIndex) "end" else "part$i")
        }
        publish("speaking", text.take(120))
    }
}
