package com.codesoli.nova

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

/** Downloads and unpacks the small offline speech model used for the wake word. */
object WakeModel {
    private const val URL_ZIP = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"

    private fun root(context: Context) = File(context.filesDir, "vosk")

    /** Folder that contains the model (has an "am" directory), or null. */
    fun find(context: Context): File? {
        val base = root(context)
        if (!base.exists()) return null
        if (File(base, "am").isDirectory) return base
        return base.listFiles()?.firstOrNull { it.isDirectory && File(it, "am").isDirectory }
    }

    /** Blocking. Returns the model folder or null (status is published in IslandState). */
    fun ensure(context: Context): File? {
        find(context)?.let { return it }
        val base = root(context)
        base.deleteRecursively()
        base.mkdirs()
        val zip = File(context.cacheDir, "vosk-model.zip")
        try {
            IslandState.wakeStatus = "Downloading wake-word model…"
            var conn = URL(URL_ZIP).openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 30000
            conn.instanceFollowRedirects = true
            if (conn.responseCode in 300..399) {
                val next = conn.getHeaderField("Location")
                conn.disconnect()
                conn = URL(next).openConnection() as HttpURLConnection
                conn.connectTimeout = 15000
                conn.readTimeout = 30000
            }
            if (conn.responseCode != 200) throw RuntimeException("HTTP ${conn.responseCode}")
            val total = conn.contentLengthLong
            var done = 0L
            conn.inputStream.use { input ->
                FileOutputStream(zip).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var lastPct = -1
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        done += n
                        if (total > 0) {
                            val pct = (done * 100 / total).toInt()
                            if (pct != lastPct) {
                                lastPct = pct
                                IslandState.wakeStatus = "Downloading wake-word model $pct%"
                            }
                        }
                    }
                }
            }
            conn.disconnect()
            IslandState.wakeStatus = "Unpacking wake-word model…"
            unzip(zip, base)
            zip.delete()
            val found = find(context) ?: throw RuntimeException("model files missing")
            IslandState.wakeStatus = "Wake-word model ready"
            return found
        } catch (e: Exception) {
            base.deleteRecursively()
            zip.delete()
            IslandState.wakeStatus = "Wake-word model failed: " + (e.message ?: "error").take(80)
            return null
        }
    }

    private fun unzip(zip: File, target: File) {
        val canonicalTarget = target.canonicalPath
        ZipInputStream(zip.inputStream().buffered()).use { zis ->
            while (true) {
                val entry = zis.nextEntry ?: break
                val out = File(target, entry.name)
                // Protect against entries that escape the target folder.
                if (!out.canonicalPath.startsWith(canonicalTarget)) continue
                if (entry.isDirectory) {
                    out.mkdirs()
                } else {
                    out.parentFile?.mkdirs()
                    FileOutputStream(out).use { zis.copyTo(it) }
                }
                zis.closeEntry()
            }
        }
    }
}

/**
 * Listens to the microphone with a tiny offline recogniser that only knows the
 * wake words. It does not take audio focus, so music and videos keep playing.
 */
class WakeWordDetector(
    private val context: Context,
    private val words: Set<String>,
    private val onReady: () -> Unit,
    private val onWake: () -> Unit,
) {
    @Volatile private var running = false
    @Volatile private var paused = false
    private var thread: Thread? = null
    private val parts: Set<String> = words.flatMap { it.split(' ') }.toSet()

    private fun hears(text: String): Boolean {
        if (text.isBlank()) return false
        val padded = " $text "
        return words.any { padded.contains(" $it ") }
    }

    fun start() {
        if (running) return
        running = true
        thread = Thread({ loop() }, "nova-wake").also { it.isDaemon = true; it.start() }
    }

    fun stop() {
        running = false
        thread?.interrupt()
        thread = null
    }

    fun pause() { paused = true }
    fun resume() { paused = false }

    private fun createRecord(): AudioRecord? {
        return try {
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            val record = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minBuffer, 16000)
            )
            if (record.state == AudioRecord.STATE_INITIALIZED) record else { record.release(); null }
        } catch (_: Exception) {
            null
        }
    }

    private fun loop() {
        val dir = WakeModel.ensure(context)
        if (dir == null || !running) {
            running = false
            return
        }
        var model: Model? = null
        var recognizer: Recognizer? = null
        var record: AudioRecord? = null
        try {
            model = Model(dir.absolutePath)
            val grammar = words.joinToString(prefix = "[", postfix = ", \"[unk]\"]", separator = ", ") { "\"$it\"" }
            recognizer = Recognizer(model, SAMPLE_RATE.toFloat(), grammar)
            recognizer.setWords(true)
            IslandState.wakeStatus = "Listening for the wake word (offline)"
            onReady()
            val buffer = ShortArray(1600)
            while (running) {
                if (paused || !SystemData.granted(context, android.Manifest.permission.RECORD_AUDIO)) {
                    record?.let { try { it.stop(); it.release() } catch (_: Exception) { } }
                    record = null
                    Thread.sleep(150)
                    continue
                }
                if (record == null) {
                    record = createRecord()
                    if (record == null) { Thread.sleep(1500); continue }
                    try { record.startRecording() } catch (_: Exception) { record.release(); record = null; Thread.sleep(1500); continue }
                    recognizer.reset()
                }
                val n = record.read(buffer, 0, buffer.size)
                if (n <= 0) { Thread.sleep(30); continue }
                val isFinal = recognizer.acceptWaveForm(buffer, n)
                // While something is playing the speaker can fool the detector,
                // so only finished phrases with good confidence count.
                val strict = IslandState.mediaBusy || IslandState.watching
                var hit = false
                try {
                    if (isFinal) {
                        val json = JSONObject(recognizer.result)
                        val text = json.optString("text")
                        if (hears(text)) {
                            val items = json.optJSONArray("result")
                            var sum = 0.0
                            var count = 0
                            if (items != null) {
                                for (k in 0 until items.length()) {
                                    val o = items.getJSONObject(k)
                                    if (o.optString("word") in parts) { sum += o.optDouble("conf", 1.0); count++ }
                                }
                            }
                            val conf = if (count > 0) sum / count else 1.0
                            hit = conf >= (if (strict) 0.9 else 0.6)
                        }
                    } else if (!strict) {
                        hit = hears(JSONObject(recognizer.partialResult).optString("partial"))
                    }
                } catch (_: Exception) { }
                if (hit) {
                    recognizer.reset()
                    paused = true
                    onWake()
                }
            }
        } catch (_: InterruptedException) {
            // stopping
        } catch (e: Throwable) {
            IslandState.wakeStatus = "Wake-word engine failed: " + e.javaClass.simpleName + " " + (e.message ?: "").take(80)
        } finally {
            try { record?.stop() } catch (_: Exception) { }
            try { record?.release() } catch (_: Exception) { }
            try { recognizer?.close() } catch (_: Throwable) { }
            try { model?.close() } catch (_: Throwable) { }
            running = false
        }
    }

    companion object {
        private const val SAMPLE_RATE = 16000
    }
}
