package com.codesoli.nova

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import android.provider.MediaStore
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale

/** Things the assistant can do on the phone. All calls may block: run off the main thread. */
class Commands(private val context: Context) {

    companion object {
        fun normalize(input: String): String {
            val sb = StringBuilder()
            for (c in input.lowercase(Locale.ROOT)) {
                when {
                    c in 'ً'..'ْ' || c == 'ٰ' || c == 'ـ' -> {}
                    c == 'أ' || c == 'إ' || c == 'آ' -> sb.append('ا')
                    c == 'ى' -> sb.append('ي')
                    c == 'ة' -> sb.append('ه')
                    else -> sb.append(c)
                }
            }
            return sb.toString().trim()
        }
    }

    private val aliases = mapOf(
        "واتساب" to "whatsapp", "واتس" to "whatsapp", "تليجرام" to "telegram", "تلجرام" to "telegram",
        "يوتيوب" to "youtube", "كروم" to "chrome", "جوجل" to "google", "الكاميرا" to "camera",
        "كاميرا" to "camera", "الاعدادات" to "settings", "اعدادات" to "settings", "الرسائل" to "messages",
        "رسائل" to "messages", "الصور" to "photos", "المعرض" to "gallery", "الخرائط" to "maps",
        "فيسبوك" to "facebook", "انستجرام" to "instagram", "انستغرام" to "instagram", "سبوتيفاي" to "spotify",
        "الساعه" to "clock", "الحاسبه" to "calculator", "كتاب" to "book", "الكتاب" to "book"
    )

    private fun launch(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun installed(pkg: String): Boolean =
        context.packageManager.getLaunchIntentForPackage(pkg) != null

    fun openApp(name: String): String? {
        val wanted = normalize(name)
        val alias = aliases[wanted]
        val pm = context.packageManager
        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = pm.queryIntentActivities(main, 0)
        var best: Pair<String, String>? = null
        for (info in apps) {
            val label = info.loadLabel(pm).toString()
            val n = normalize(label)
            val pkg = info.activityInfo.packageName
            val hit = n == wanted || n.contains(wanted) || wanted.contains(n) && n.length > 2 ||
                (alias != null && (n.contains(alias) || pkg.contains(alias)))
            if (hit) {
                if (best == null || n == wanted) best = label to pkg
                if (n == wanted) break
            }
        }
        val target = best ?: return null
        val intent = pm.getLaunchIntentForPackage(target.second) ?: return null
        return if (launch(intent)) target.first else null
    }

    /** Returns display name and phone number of the best matching contact. */
    fun findContact(name: String): Pair<String, String>? {
        if (!SystemData.granted(context, android.Manifest.permission.READ_CONTACTS)) return null
        val wanted = normalize(name)
        if (wanted.isEmpty()) return null
        var partial: Pair<String, String>? = null
        context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            ),
            null, null, null
        )?.use { cursor ->
            var count = 0
            while (cursor.moveToNext() && count < 6000) {
                count++
                val display = cursor.getString(0) ?: continue
                val number = cursor.getString(1) ?: continue
                val n = normalize(display)
                if (n == wanted) return display to number
                if (partial == null && (n.contains(wanted) || wanted.contains(n) && n.length > 2)) {
                    partial = display to number
                }
            }
        }
        return partial
    }

    private fun digits(number: String): String = number.filter { it.isDigit() || it == '+' }

    /** Calls a contact name or a number. Falls back to the dialer without permission. */
    fun call(target: String): String {
        val raw = target.trim()
        val isNumber = raw.isNotEmpty() && raw.all { it.isDigit() || it == '+' || it == ' ' || it == '-' }
        val number: String
        val label: String
        if (isNumber) {
            number = digits(raw)
            label = raw
        } else {
            val found = findContact(raw)
                ?: return if (SystemData.granted(context, android.Manifest.permission.READ_CONTACTS))
                    "Contact not found: $raw"
                else "Allow Contacts permission in Nova to call by name"
            number = digits(found.second)
            label = found.first
        }
        val uri = Uri.parse("tel:" + Uri.encode(number))
        val canCall = SystemData.granted(context, android.Manifest.permission.CALL_PHONE)
        val ok = launch(Intent(if (canCall) Intent.ACTION_CALL else Intent.ACTION_DIAL, uri))
        return if (ok) (if (canCall) "Calling $label" else "Dialer opened for $label") else "Could not start the call"
    }

    fun whatsapp(target: String, text: String): String {
        val pkg = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull { installed(it) }
            ?: return "WhatsApp is not installed"
        var number = ""
        val raw = target.trim()
        if (raw.isNotEmpty()) {
            number = if (raw.all { it.isDigit() || it == '+' || it == ' ' || it == '-' }) digits(raw)
            else findContact(raw)?.second?.let { digits(it) }.orEmpty()
        }
        if (number.isEmpty()) {
            val intent = context.packageManager.getLaunchIntentForPackage(pkg) ?: return "WhatsApp is not installed"
            return if (launch(intent)) (if (raw.isEmpty()) "WhatsApp opened" else "WhatsApp opened (contact not found: $raw)")
            else "Could not open WhatsApp"
        }
        val clean = number.removePrefix("+").removePrefix("00")
        val url = "https://wa.me/$clean" + if (text.isNotBlank()) "?text=" + URLEncoder.encode(text, "UTF-8") else ""
        val ok = launch(Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(pkg))
        if (ok && text.isNotBlank()) {
            // Press the send button once the chat is open (needs the accessibility service).
            Thread.sleep(3200)
            NovaAccessibilityService.click(listOf("Send", "إرسال", "ارسال"))
        }
        return if (ok) "WhatsApp chat opened" else "Could not open WhatsApp"
    }

    fun telegram(): String {
        val pkg = listOf("org.telegram.messenger", "org.telegram.messenger.web", "org.thunderdog.challegram")
            .firstOrNull { installed(it) } ?: return "Telegram is not installed"
        val intent = context.packageManager.getLaunchIntentForPackage(pkg) ?: return "Telegram is not installed"
        return if (launch(intent)) "Telegram opened" else "Could not open Telegram"
    }

    fun webSearch(query: String): String {
        val ok = launch(Intent(Intent.ACTION_WEB_SEARCH).putExtra("query", query))
        if (ok) return "Searching Google"
        val url = "https://www.google.com/search?q=" + URLEncoder.encode(query, "UTF-8")
        return if (launch(Intent(Intent.ACTION_VIEW, Uri.parse(url)))) "Searching Google" else "Could not open the browser"
    }

    private fun firstYoutubeId(query: String): String? {
        return try {
            val url = URL("https://www.youtube.com/results?hl=en&search_query=" + URLEncoder.encode(query, "UTF-8"))
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 10000
            conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36")
            conn.setRequestProperty("Accept-Language", "en-US,en;q=0.9")
            val html = conn.inputStream.bufferedReader().use { r ->
                val buf = CharArray(700_000)
                val n = r.read(buf)
                if (n > 0) String(buf, 0, n) else ""
            }
            Regex("\"videoRenderer\":\\{\"videoId\":\"([A-Za-z0-9_-]{11})\"").find(html)?.groupValues?.get(1)
                ?: Regex("\"videoId\":\"([A-Za-z0-9_-]{11})\"").find(html)?.groupValues?.get(1)
        } catch (_: Exception) {
            null
        }
    }

    /** Opens the first YouTube result straight in the video player. */
    fun playYoutube(query: String): String {
        val id = firstYoutubeId(query)
        if (id != null) {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/watch?v=$id"))
            if (installed("com.google.android.youtube")) intent.setPackage("com.google.android.youtube")
            if (launch(intent)) return "Playing on YouTube: $query"
        }
        val search = Intent(Intent.ACTION_SEARCH).setPackage("com.google.android.youtube").putExtra("query", query)
        if (launch(search)) return "YouTube search opened: $query"
        val url = "https://www.youtube.com/results?search_query=" + URLEncoder.encode(query, "UTF-8")
        return if (launch(Intent(Intent.ACTION_VIEW, Uri.parse(url)))) "YouTube search opened: $query" else "Could not open YouTube"
    }

    /** Plays a song: Spotify when installed, otherwise the first YouTube result. */
    fun playMusic(query: String, app: String): String {
        val wantSpotify = app == "spotify" || (app == "auto" && installed("com.spotify.music"))
        if (wantSpotify && installed("com.spotify.music")) {
            val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH)
                .setPackage("com.spotify.music")
                .putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                .putExtra(android.app.SearchManager.QUERY, query)
            if (launch(intent)) return "Playing on Spotify: $query"
        }
        return playYoutube(query)
    }
}
