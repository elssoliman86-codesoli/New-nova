package com.codesoli.nova

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.media.AudioManager
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
import java.util.concurrent.atomic.AtomicInteger

object AssistantConfig {
    private const val PREFS = "nova_assistant"

    @Volatile var enabled = false
    @Volatile var apiKey = ""
    @Volatile var model = "meta/llama-3.3-70b-instruct"
    @Volatile var baseUrl = "https://integrate.api.nvidia.com/v1"
    @Volatile var wakeWords = "soli,solly,sully,سولي,سولى"
    @Volatile var language = "auto"
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
        if (wakeWords == "نوفا,nova") wakeWords = "soli,solly,sully,سولي,سولى"
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
    fun chat(messages: JSONArray, maxTokens: Int = 1100): String {
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
 * Soli, the voice assistant. A silent offline detector waits for the wake word;
 * then the speech recogniser takes one command, and the agent loop asks the
 * model what to do, runs the actions (phone, screen, web), feeds the results
 * back and repeats until the task is done or it needs an answer from the user.
 */
class AssistantEngine(private val context: Context, private val ui: Ui) : RecognitionListener {

    interface Ui {
        /** state: off, listening, awake, thinking, speaking, error */
        fun assistantState(state: String, text: String)
        fun mediaControl(action: String)
        fun showAnswer(title: String, text: String)
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val commands = Commands(context)
    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var running = false
    private var paused = false
    @Volatile private var busy = false
    @Volatile private var cancelled = false
    private var dictating = false
    private var awakeUntil = 0L
    private var errorStreak = 0
    @Volatile private var lastUiAt = 0L
    @Volatile private var scriptHint = "ar"

    // Two stages: a silent offline wake-word detector (does not touch audio
    // focus), and the speech recogniser that only runs after the wake word.
    private var detector: WakeWordDetector? = null
    private var passive = false
    private var active = false
    private var activeUntil = 0L
    private var wasPlaying = false
    private var mediaActionTaken = false
    private val history = ArrayList<Pair<String, String>>()

    private val pendingSpeech = AtomicInteger(0)
    @Volatile private var lastSpeakAt = 0L

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
        val configured = AssistantConfig.wakeWords.split(',', ';', '،').map { it.trim().lowercase(Locale.ROOT) }
            .filter { it.isNotEmpty() && it.all { c -> c in 'a'..'z' || c == ' ' } }
        val words = (configured + listOf("soli", "solly", "sully")).toSet()
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
        if (!active) {
            wasPlaying = IslandState.mediaPlaying
            mediaActionTaken = false
        }
        active = true
        activeUntil = System.currentTimeMillis() + durationMs
        awakeUntil = activeUntil
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
        // The recogniser can pause the music or video: bring it back if we caused that.
        if (wasPlaying && !mediaActionTaken) {
            main.postDelayed({ if (!IslandState.mediaPlaying) ui.mediaControl("play") }, 1200)
        }
        wasPlaying = false
    }

    fun stop() {
        running = false
        cancelled = true
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
        pendingSpeech.set(0)
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

    /** Stops the task that is running (tap on the island while it is thinking). */
    fun cancelTask() {
        if (!busy) return
        cancelled = true
        main.post {
            try { tts?.stop() } catch (_: Exception) { }
            pendingSpeech.set(0)
            publish("thinking", t("جاري الإلغاء…", "Cancelling…", "Отмена…"))
        }
    }

    /** Typed or tapped command: runs without needing the wake word. */
    fun submit(text: String) {
        if (text.isBlank()) return
        main.post {
            if (!running) {
                AssistantConfig.load(context)
                initTts()
            }
            runCommand(text.trim(), emptyList())
        }
    }

    /** Mic button: listen for one command without a wake word. */
    fun listenNow() {
        if (running) {
            if (!busy) activate(12_000)
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

    private fun audioActive(): Boolean = try {
        (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager).isMusicActive
    } catch (_: Exception) { false }

    private fun recognizerIntent(): Intent {
        val setting = AssistantConfig.language
        val auto = setting == "auto" || setting.isBlank()
        val primary = if (auto) "ar-EG" else setting
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, primary)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
        }
        if (auto) {
            // Best effort: the speech service picks whichever of the three languages is spoken.
            val languages = arrayListOf("ar-EG", "en-US", "ru-RU")
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, primary)
            intent.putStringArrayListExtra("android.speech.extra.SUPPORTED_LANGUAGES", languages)
            intent.putExtra("android.speech.extra.ENABLE_LANGUAGE_DETECTION", true)
            intent.putStringArrayListExtra("android.speech.extra.LANGUAGE_DETECTION_ALLOWED_LANGUAGES", languages)
            intent.putExtra("android.speech.extra.ENABLE_LANGUAGE_SWITCH", "balanced")
            intent.putStringArrayListExtra("android.speech.extra.LANGUAGE_SWITCH_ALLOWED_LANGUAGES", languages)
        }
        return intent
    }

    private fun listen() {
        if (!running || paused || busy) return
        if (passive && !active) return
        if (pendingSpeech.get() > 0 && System.currentTimeMillis() - lastSpeakAt < 45_000L) {
            scheduleListen(500)
            return
        }
        // Without the offline wake word the system recogniser would grab audio focus
        // and cut music and videos, so it never runs on its own: only after a tap
        // on the island's mic (active) or while dictating.
        if (!passive && !active && !dictating) {
            return
        }
        try {
            recognizer?.startListening(recognizerIntent())
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
        val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty()
        val text = list.firstOrNull().orEmpty()
        if (text.isNotBlank()) {
            val alternatives = list.drop(1).map { it.trim() }.filter { it.isNotBlank() && it != text }.distinct().take(3)
            handleHeard(text.trim(), alternatives)
        }
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
                if (busy) return
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
                if (busy) return
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
            listOf("سولي", "سولى", "سولّي", "soli", "solly", "sully")).filter { it.isNotEmpty() }.distinct()
        val alt = words.joinToString("|") { Regex.escape(it) }
        return Regex("(?:(?:يا|يا |hey |hi |ok |okay |эй |привет )\\s*)?(?:$alt)", RegexOption.IGNORE_CASE)
    }

    /** Text after the wake word, or null when the wake word is absent. */
    private fun findWake(text: String): String? {
        val m = wakeRegex().find(text) ?: return null
        return text.removeRange(m.range).trim().trim(',', '،', '.', '!', '؟', '?', ' ')
    }

    private fun handleHeard(text: String, alternatives: List<String>) {
        IslandState.assistantHeard = text
        if (dictating) { handleDictation(text); return }
        val now = System.currentTimeMillis()
        var afterWake: String? = null
        for (candidate in listOf(text) + alternatives) {
            val found = findWake(candidate)
            if (found != null) { afterWake = found; break }
        }
        val command = when {
            afterWake != null -> afterWake
            passive || now < awakeUntil || !AssistantConfig.requireWake -> text
            else -> return
        }
        if (command.isBlank()) {
            awakeUntil = now + 8000
            activeUntil = awakeUntil
            publish("awake", "")
            if (!passive) speak(t("نعم؟", "Yes?", "Да?"), queue = false, resumeAfter = false)
            return
        }
        runCommand(command, alternatives)
    }

    private fun handleDictation(text: String) {
        val norm = Commands.normalize(text)
        val stops = listOf(
            "خلاص", "وقف", "كفايه", "كفايه كده", "انهي", "تم", "ابطل",
            "stop", "done", "finish", "that's all", "стоп", "хватит", "готово", "всё", "все"
        )
        if (stops.any { norm == it || norm.endsWith(" $it") }) {
            dictating = false
            publish("listening", "")
            speak(t("تمام", "Done", "Готово"), queue = false, resumeAfter = false)
            return
        }
        val ok = NovaAccessibilityService.typeText(text)
        publish("awake", if (ok) "✍ $text" else "Enable Soli accessibility to type")
    }

    // ---------------------------------------------------------------- brain

    private fun script(text: String): String {
        var ar = 0
        var ru = 0
        var latin = 0
        for (c in text) {
            when {
                c in '؀'..'ۿ' -> ar++
                c in 'Ѐ'..'ӿ' -> ru++
                c in 'a'..'z' || c in 'A'..'Z' -> latin++
            }
        }
        val most = maxOf(ar, ru, latin)
        if (most == 0) return scriptHint
        return when (most) {
            ar -> "ar"
            ru -> "ru"
            else -> "en"
        }
    }

    private fun t(ar: String, en: String, ru: String): String = when (scriptHint) {
        "ru" -> ru
        "en" -> en
        else -> ar
    }

    private fun systemPrompt(command: String): String {
        val now = Calendar.getInstance()
        val clock = "%04d-%02d-%02d %02d:%02d".format(
            now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1, now.get(Calendar.DAY_OF_MONTH),
            now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE)
        )
        val facts = MemoryStore.relevant(context, command)
        val memory = if (facts.isEmpty()) "(nothing saved yet)" else facts.joinToString("\n") { "- " + it.text }
        val front = IslandState.foregroundPackage.takeIf { it.isNotBlank() }
            ?.let { SystemData.appLabel(context, it) + " ($it)" } ?: "unknown"
        return """
You are Soli (سولي), a voice assistant living on the user's Android phone. Your name is Soli.
The user speaks Egyptian Arabic, English and Russian, often mixed inside one sentence. Song titles, names and brands may be in any of the three languages: keep them in their original script when you pass them to actions. Speech recognition can garble foreign words, so use the "other guesses" the user message may list to work out what was really said.
Reply in the language the user spoke (Egyptian Arabic by default), short and natural, because "say" is spoken aloud.
Local time now: $clock. App currently on screen: $front.

Things you know about the user (stored only on this phone):
$memory

Answer ONLY with one JSON object, no markdown, no text outside it:
{"say":"spoken reply, one or two short sentences","answer":"optional text to show on screen","actions":[ ... ],"status":"continue|ask|done","remember":["short fact"],"forget":["fact"]}
- status "continue": you ran actions and need their results before deciding the next step. The results arrive in the next message as Observations.
- status "ask": you need something from the user. Put the question in "say" and leave "actions" empty. The user's reply arrives as the next message.
- status "done": the task is finished. Omit status or use done for simple answers.
- "answer" is only for results worth reading (prices, lists, summaries, figures). Plain text, at most 60 words, no markdown, numbers with units. Conversational replies use "say" only. Do not repeat the answer inside "say"; "say" is the short spoken version.
- "remember": durable personal facts the user tells you (name, age, study or job, city, family, preferences) and anything they ask you to save ("احفظ المعلومة", "remember", "запомни"). One short sentence each, in the user's words. Do not save passwords, card numbers, codes or one-off chatter. "forget": facts the user asks you to delete.

Actions (use exactly these types; several can be listed and run in order):
{"type":"call","target":"contact name or phone number"}
{"type":"whatsapp","target":"contact name or number (may be empty)","text":"message to send (may be empty)"}
{"type":"telegram"}
{"type":"youtube","query":"what to play on YouTube"}
{"type":"music","query":"song and artist","app":"auto|spotify|youtube"}
{"type":"search","query":"opens a Google search for the user to look at"}
{"type":"open_app","name":"app name as shown on the phone"}
{"type":"media","action":"play|pause|next|previous"}
{"type":"back"} {"type":"home"}
{"type":"read_screen","mode":"read|translate|summarize","language":"target language"}  (speaks the whole screen)
{"type":"dictate"}  (the user wants everything they say typed into the focused text box; no wake word needed until they say stop)
{"type":"type","text":"text to type now"}
Background tools (nothing opens on the phone; results come back as observations):
{"type":"web_search","query":"search text"}
{"type":"fetch_page","url":"https://..."}
{"type":"currency","amount":100,"from":"USD","to":"EGP"}
{"type":"observe_screen"}  (text on the current screen, which app, lock state)
{"type":"wait_screen_change","seconds":60}  (wait until the screen changes, for example after the user unlocks)
{"type":"click_text","text":"visible label to tap"}
{"type":"scroll","direction":"down|up"}
{"type":"wait","seconds":2}

How to work:
1. Long tasks run one step at a time: act, then observe_screen (or a web tool), read the observation, decide the next step. Use status "continue" until the goal is reached. Never claim something worked unless an observation shows it.
2. Phone screens: after open_app add observe_screen in the same list. If the observation says the phone is locked, or the app shows a lock / fingerprint / password / PIN screen, do NOT give up and never type, guess or read passwords, PINs or codes. Say briefly that you are waiting for the user to unlock, then use wait_screen_change (seconds 60) with status "continue", and observe_screen again once it changes.
3. Showing chats ("اعرضلي رسايل الواتس"): open the app, observe_screen, tell the user the latest chats briefly (who and the last line), then ask which chat to open (status "ask"). When they answer, click_text on that chat name, observe_screen, and read the newest messages aloud in "say" and "answer". "اقرأ الصفحة" or "read this page" means observe_screen (or read_screen) of what is open now.
4. Searching and prices: use web_search, then fetch_page on two to four different, relevant results, one step at a time. Compare the figures, ignore outliers (accessories, used items, spam, wrong models), and give the typical price or range plus the average, with the source names. If the user wants another currency (for example dollars to Egyptian pounds) call currency, and mention that it is the official rate. If something essential is missing (exact model or storage, new or used, which country), ask ONE short clarifying question first (status "ask") unless the saved facts or the conversation already answer it. For laws, rules, dates and other facts that change, verify with web_search before answering, and use the saved facts about the user when they matter (for example a 21-year-old student asking about military service: mention the deferment for students after checking the current rules).
5. If you cannot do something, say so honestly in one short sentence.
""".trim()
    }

    private fun userMessage(command: String, alternatives: List<String>): String {
        if (alternatives.isEmpty()) return command
        return command + "\n(other guesses of the same speech: " + alternatives.joinToString(" | ") { "\"$it\"" } + ")"
    }

    private fun msg(role: String, content: String): JSONObject =
        JSONObject().put("role", role).put("content", content)

    private fun runCommand(command: String, alternatives: List<String>) {
        if (busy) return
        busy = true
        cancelled = false
        dictating = false
        scriptHint = script(command)
        try { recognizer?.cancel() } catch (_: Exception) { }
        main.removeCallbacks(listenRunnable)
        publish("thinking", command)
        if (AssistantConfig.apiKey.isBlank()) {
            finish("Add your NVIDIA API key in Nova > Assistant first.")
            return
        }
        worker.execute { agent(command, alternatives) }
    }

    private fun parse(raw: String): JSONObject {
        val start = raw.indexOf('{')
        val end = raw.lastIndexOf('}')
        if (start >= 0 && end > start) {
            try { return JSONObject(raw.substring(start, end + 1)) } catch (_: Exception) { }
        }
        return JSONObject().put("say", raw.take(400)).put("status", "done")
    }

    /** Shortens old observations so a long task does not overflow the model. */
    private fun compact(messages: JSONArray) {
        for (i in 1 until messages.length() - 1) {
            val m = messages.getJSONObject(i)
            val content = m.optString("content")
            if (m.optString("role") == "user" && content.startsWith("Observations:") && content.length > 1500) {
                m.put("content", content.take(1500) + "\n…(shortened)")
            }
        }
    }

    private fun agent(command: String, alternatives: List<String>) {
        val messages = JSONArray()
        messages.put(msg("system", systemPrompt(command)))
        synchronized(history) {
            history.takeLast(8).forEach { (u, a) ->
                messages.put(msg("user", u))
                messages.put(msg("assistant", a))
            }
        }
        messages.put(msg("user", userMessage(command, alternatives)))

        var lastRaw = ""
        var say = ""
        var answer = ""
        var status = "done"
        val digest = StringBuilder()
        var step = 0
        while (step < MAX_STEPS) {
            step++
            if (cancelled) break
            val raw = try {
                NvidiaClient.chat(messages)
            } catch (e: Exception) {
                val message = "Error: " + (e.message ?: "request failed").take(120)
                main.post { finish(message) }
                return
            }
            if (cancelled) break
            lastRaw = raw
            val parsed = parse(raw)
            say = parsed.optString("say").trim()
            val stepAnswer = parsed.optString("answer").trim()
            if (stepAnswer.isNotBlank()) answer = stepAnswer
            val actions = parsed.optJSONArray("actions") ?: JSONArray()
            status = parsed.optString("status").lowercase(Locale.ROOT).ifBlank {
                if (actions.length() == 0) "done" else "continue"
            }
            if (status != "continue" && status != "ask") status = "done"
            if (actions.length() == 0 && status == "continue") status = "done"
            handleMemory(parsed)

            val last = status != "continue"
            if (say.isNotBlank()) {
                val spoken = say
                main.post { speak(spoken, queue = true, resumeAfter = last) }
            }
            val observations = runActions(actions)
            if (cancelled) break
            if (last) break

            digest.append(observations.joinToString(" ").take(500)).append(' ')
            messages.put(msg("assistant", raw))
            messages.put(msg(
                "user",
                "Observations:\n" + observations.joinToString("\n---\n").ifBlank { "(none)" } +
                    "\nContinue the task. Reply with the JSON object only."
            ))
            compact(messages)
        }

        if (cancelled) {
            main.post { finish(t("تم الإلغاء", "Cancelled", "Отменено"), speakNote = true) }
            return
        }
        if (step >= MAX_STEPS && status == "continue") {
            say = t("المهمة طويلة قوي، وقفت هنا. قولي أكمل لو عايزني أكمل.",
                "This task is long, so I stopped here. Tell me to continue if you want more.",
                "Задача слишком длинная, я остановилась. Скажите продолжить, если нужно.")
            status = "done"
        }
        synchronized(history) {
            history.add(command to (lastRaw.take(700) + if (digest.isNotBlank()) "\n(observed: " + digest.toString().take(600) + ")" else ""))
            if (history.size > 10) history.removeAt(0)
        }
        val finalSay = say
        val finalAnswer = answer
        val ask = status == "ask"
        main.post { complete(finalSay, finalAnswer, ask) }
    }

    private fun handleMemory(parsed: JSONObject) {
        fun items(key: String): List<String> {
            val array = parsed.optJSONArray(key)
            if (array != null) return (0 until array.length()).map { array.optString(it) }.filter { it.isNotBlank() }
            val single = parsed.optString(key)
            return if (single.isBlank() || single == "null") emptyList() else listOf(single)
        }
        items("remember").forEach { MemoryStore.add(context, it) }
        items("forget").forEach { MemoryStore.forget(context, it) }
    }

    private val uiActions = setOf("open_app", "whatsapp", "telegram", "youtube", "music", "search", "call", "back", "home", "click_text", "scroll")

    private fun sleepCancellable(ms: Long) {
        var left = ms
        while (left > 0 && !cancelled) {
            Thread.sleep(minOf(100L, left))
            left -= 100L
        }
    }

    private fun progress(type: String, a: JSONObject) {
        val text = when (type) {
            "web_search" -> t("بدوّر: ", "Searching: ", "Ищу: ") + a.optString("query")
            "fetch_page" -> t("بقرأ صفحة…", "Reading a page…", "Читаю страницу…")
            "currency" -> t("بحسب العملة…", "Converting currency…", "Конвертирую валюту…")
            "observe_screen", "read_screen" -> t("بقرأ الشاشة…", "Reading the screen…", "Читаю экран…")
            "wait_screen_change" -> t("مستنيك… افتح القفل", "Waiting for you…", "Жду вас…")
            "open_app" -> t("بفتح ", "Opening ", "Открываю ") + a.optString("name")
            else -> ""
        }
        if (text.isNotBlank()) main.post { if (busy && !cancelled) publish("thinking", text) }
    }

    /** Runs the actions in order and returns what each one reported. */
    private fun runActions(actions: JSONArray): List<String> {
        val out = ArrayList<String>()
        for (i in 0 until actions.length()) {
            if (cancelled) break
            val a = actions.optJSONObject(i) ?: continue
            val type = a.optString("type")
            if (type in setOf("youtube", "music", "media")) mediaActionTaken = true
            progress(type, a)
            val result: String? = try {
                execute(type, a)
            } catch (e: Exception) {
                "Action failed: " + (e.message ?: "").take(80)
            }
            if (type in uiActions) lastUiAt = System.currentTimeMillis()
            if (result != null) out.add("[$type] $result")
            if (i < actions.length() - 1 && type in uiActions) sleepCancellable(1500)
        }
        return out
    }

    private fun execute(type: String, a: JSONObject): String? = when (type) {
        "call" -> commands.call(a.optString("target"))
        "whatsapp" -> commands.whatsapp(a.optString("target"), a.optString("text"))
        "telegram" -> commands.telegram()
        "youtube" -> commands.playYoutube(a.optString("query"))
        "music" -> commands.playMusic(a.optString("query"), a.optString("app", "auto"))
        "search" -> commands.webSearch(a.optString("query"))
        "open_app" -> commands.openApp(a.optString("name"))?.let { "Opened $it" }
            ?: "App not found: ${a.optString("name")}"
        "media" -> { main.post { ui.mediaControl(a.optString("action")) }; "Media: " + a.optString("action") }
        "type" -> if (NovaAccessibilityService.typeText(a.optString("text"))) "Typed"
            else "Could not type (accessibility off, or no text field is focused)"
        "dictate" -> {
            main.post { dictating = true; publish("awake", "✍ " + t("بكتب وراك… قول خلاص لما تخلص", "Typing what you say… say stop to finish", "Печатаю за вами… скажите стоп")) }
            if (NovaAccessibilityService.instance == null) "Enable Soli accessibility to type" else "Dictation started"
        }
        "back" -> { NovaAccessibilityService.global(AccessibilityService.GLOBAL_ACTION_BACK); "Went back" }
        "home" -> { NovaAccessibilityService.global(AccessibilityService.GLOBAL_ACTION_HOME); "Went home" }
        "read_screen" -> readScreen(a.optString("mode", "read"), a.optString("language", "Arabic"))
        "web_search" -> WebTools.search(a.optString("query"))
        "fetch_page" -> a.optString("url").let { "Page " + it + ":\n" + WebTools.fetchText(it, 4500) }
        "currency" -> WebTools.currency(a.optDouble("amount", 1.0), a.optString("from", "USD"), a.optString("to", "EGP"))
        "observe_screen" -> {
            // Give a freshly opened app time to draw.
            val since = System.currentTimeMillis() - lastUiAt
            if (since < 2300) sleepCancellable(2300 - since)
            NovaAccessibilityService.observe().take(6000)
        }
        "wait_screen_change" -> waitForScreenChange(a.optInt("seconds", 45).coerceIn(3, 120))
        "click_text" -> {
            val label = a.optString("text")
            if (NovaAccessibilityService.click(listOf(label))) "Tapped \"$label\"" else "Could not find \"$label\" on screen"
        }
        "scroll" -> if (NovaAccessibilityService.scroll(a.optString("direction", "down") != "up")) "Scrolled" else "Nothing to scroll"
        "wait" -> { sleepCancellable(a.optInt("seconds", 2).coerceIn(1, 15) * 1000L); "Waited" }
        else -> null
    }

    private fun waitForScreenChange(seconds: Int): String {
        if (NovaAccessibilityService.instance == null) return "Accessibility is off, cannot watch the screen."
        val first = NovaAccessibilityService.fingerprint()
        val deadline = System.currentTimeMillis() + seconds * 1000L
        while (System.currentTimeMillis() < deadline && !cancelled) {
            Thread.sleep(700)
            if (NovaAccessibilityService.fingerprint() != first) {
                sleepCancellable(1400)
                return "The screen changed."
            }
        }
        return if (cancelled) "Cancelled." else "Timed out: the screen did not change in $seconds seconds."
    }

    private fun readScreen(mode: String, language: String): String? {
        val text = NovaAccessibilityService.readScreen()
            ?: return if (NovaAccessibilityService.instance == null) {
                main.post { speak(t("فعّل خدمة إمكانية الوصول لسولي عشان أقدر أقرأ الشاشة", "Enable the Soli accessibility service so I can read the screen", "Включите службу специальных возможностей Soli, чтобы я читала экран"), queue = false, resumeAfter = false) }
                "Enable Soli accessibility to read the screen"
            } else "Nothing readable on screen"
        if (mode == "read") {
            main.post { speakLong(text) }
            return "Reading the screen aloud"
        }
        val task = if (mode == "translate") "Translate this screen text to $language. Output only the translation."
        else "Summarize this screen text briefly in the user's language."
        val messages = JSONArray()
            .put(msg("system", task))
            .put(msg("user", text.take(9000)))
        val answer = NvidiaClient.chat(messages, 1200)
        main.post { speakLong(answer) }
        return answer.take(300)
    }

    /** Task finished normally: show the answer card, keep listening for a follow-up. */
    private fun complete(note: String, answer: String, ask: Boolean) {
        busy = false
        IslandState.assistantReply = if (answer.isNotBlank()) answer else note
        val card = answer.ifBlank { if (note.length > 120) note else "" }
        if (card.isNotBlank()) ui.showAnswer("Soli", card)
        if (note.isBlank() && answer.isNotBlank() && answer.length <= 300) {
            speak(answer, queue = true, resumeAfter = true)
        }
        followUp(if (ask) 25_000L else 7_000L, ask)
        publish("awake", if (note.isBlank()) answer.take(80) else note)
    }

    /** Stays open for the next sentence without needing the wake word. */
    private fun followUp(openMs: Long, force: Boolean) {
        val now = System.currentTimeMillis()
        awakeUntil = now + openMs
        if (passive) {
            if (active) activeUntil = awakeUntil
            else if (force) activate(openMs)
        }
        if (pendingSpeech.get() == 0 && (!passive || active)) scheduleListen(450)
        main.postDelayed({
            if (System.currentTimeMillis() >= awakeUntil - 200 && !dictating && !busy) {
                if (passive && active) deactivate() else publish("listening", "")
            }
        }, openMs + 300)
    }

    private fun finish(note: String, speakNote: Boolean = true) {
        IslandState.assistantReply = note
        busy = false
        if (speakNote && AssistantConfig.speak) speak(note, queue = false, resumeAfter = true)
        followUp(7_000L, false)
        publish("awake", note)
    }

    // ------------------------------------------------------------------ tts

    private fun initTts() {
        if (tts != null) return
        tts = TextToSpeech(context) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) { spoken() }
                override fun onStop(utteranceId: String?, interrupted: Boolean) { spoken() }
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) { spoken() }
            })
        }
    }

    private fun spoken() {
        val left = pendingSpeech.decrementAndGet()
        if (left <= 0) {
            pendingSpeech.set(0)
            main.post { if (running && !busy && (!passive || active)) scheduleListen(350) }
        }
    }

    private fun localeFor(text: String): Locale = when (script(text)) {
        "ru" -> Locale("ru")
        "en" -> Locale.US
        else -> Locale("ar")
    }

    private fun prepareVoice(text: String): TextToSpeech? {
        val engine = tts
        if (engine == null || !ttsReady) return null
        try { engine.setLanguage(localeFor(text)) } catch (_: Exception) { }
        try { recognizer?.cancel() } catch (_: Exception) { }
        main.removeCallbacks(listenRunnable)
        return engine
    }

    private fun speak(text: String, queue: Boolean, resumeAfter: Boolean) {
        if (!AssistantConfig.speak || text.isBlank()) return
        val engine = prepareVoice(text)
        if (engine == null) { scheduleListen(400); return }
        if (!queue) pendingSpeech.set(0)
        pendingSpeech.incrementAndGet()
        lastSpeakAt = System.currentTimeMillis()
        val id = if (resumeAfter) "end" else "say"
        engine.speak(text.take(3500), if (queue) TextToSpeech.QUEUE_ADD else TextToSpeech.QUEUE_FLUSH, null, id)
        publish("speaking", text)
    }

    private fun speakLong(text: String) {
        if (!AssistantConfig.speak) return
        val engine = prepareVoice(text) ?: return
        val chunks = text.chunked(3000)
        pendingSpeech.set(chunks.size)
        lastSpeakAt = System.currentTimeMillis()
        chunks.forEachIndexed { i, chunk ->
            engine.speak(chunk, if (i == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD, null,
                if (i == chunks.lastIndex) "end" else "part$i")
        }
        publish("speaking", text.take(120))
    }

    companion object {
        private const val MAX_STEPS = 14
    }
}
