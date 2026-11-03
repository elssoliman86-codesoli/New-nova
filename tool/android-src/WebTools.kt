package com.codesoli.nova

import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder

/** Web access for the assistant: search, read a page, exchange rates. Blocking. */
object WebTools {
    private const val UA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    private fun get(url: String, maxChars: Int = 700_000, timeoutMs: Int = 12_000): String {
        var current = url
        repeat(4) {
            val conn = URL(current).openConnection() as HttpURLConnection
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("User-Agent", UA)
            conn.setRequestProperty("Accept-Language", "en-US,en;q=0.9,ar;q=0.8,ru;q=0.7")
            conn.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.5")
            val code = conn.responseCode
            if (code in 300..399) {
                val next = conn.getHeaderField("Location")
                conn.disconnect()
                if (next.isNullOrBlank()) throw RuntimeException("redirect without target")
                current = URL(URL(current), next).toString()
                return@repeat
            }
            if (code !in 200..299) {
                conn.disconnect()
                throw RuntimeException("HTTP $code")
            }
            val text = conn.inputStream.bufferedReader().use { r ->
                val buf = CharArray(maxChars)
                var total = 0
                while (total < maxChars) {
                    val n = r.read(buf, total, maxChars - total)
                    if (n < 0) break
                    total += n
                }
                String(buf, 0, total)
            }
            conn.disconnect()
            return text
        }
        throw RuntimeException("too many redirects")
    }

    private fun decodeEntities(input: String): String = input
        .replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
        .replace("&quot;", "\"").replace("&#39;", "'").replace("&#x27;", "'")
        .replace("&nbsp;", " ").replace("&#160;", " ")

    fun htmlToText(html: String): String {
        var s = html
        s = Regex("(?is)<(script|style|noscript|svg|head)[^>]*>.*?</\\1>").replace(s, " ")
        s = Regex("(?i)<(br|/p|/div|/li|/h[1-6]|/tr)[^>]*>").replace(s, "\n")
        s = Regex("<[^>]+>").replace(s, " ")
        s = decodeEntities(s)
        s = Regex("[ \\t\\u00A0]+").replace(s, " ")
        s = Regex("\\s*\\n\\s*").replace(s, "\n")
        return s.trim()
    }

    private fun clean(fragment: String): String =
        decodeEntities(Regex("<[^>]+>").replace(fragment, "")).replace(Regex("\\s+"), " ").trim()

    private class Hit(val title: String, val url: String, val snippet: String)

    private fun duckduckgo(query: String): List<Hit> {
        val html = get("https://html.duckduckgo.com/html/?q=" + URLEncoder.encode(query, "UTF-8"))
        val hits = ArrayList<Hit>()
        val link = Regex("(?is)<a[^>]+class=\"result__a\"[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>")
        val snippet = Regex("(?is)class=\"result__snippet\"[^>]*>(.*?)</a>")
        val links = link.findAll(html).toList()
        val snippets = snippet.findAll(html).toList()
        for ((i, m) in links.withIndex()) {
            var href = decodeEntities(m.groupValues[1])
            val uddg = Regex("[?&]uddg=([^&]+)").find(href)?.groupValues?.get(1)
            if (uddg != null) href = URLDecoder.decode(uddg, "UTF-8")
            if (href.startsWith("//")) href = "https:$href"
            if (!href.startsWith("http")) continue
            hits.add(Hit(clean(m.groupValues[2]), href, snippets.getOrNull(i)?.let { clean(it.groupValues[1]) }.orEmpty()))
        }
        return hits
    }

    private fun bing(query: String): List<Hit> {
        val html = get("https://www.bing.com/search?q=" + URLEncoder.encode(query, "UTF-8"))
        val hits = ArrayList<Hit>()
        val block = Regex("(?is)<li class=\"b_algo\".*?</li>")
        for (m in block.findAll(html)) {
            val b = m.value
            val a = Regex("(?is)<h2[^>]*><a[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>").find(b) ?: continue
            val snip = Regex("(?is)<p[^>]*>(.*?)</p>").find(b)?.groupValues?.get(1).orEmpty()
            val href = decodeEntities(a.groupValues[1])
            if (href.startsWith("http")) hits.add(Hit(clean(a.groupValues[2]), href, clean(snip)))
        }
        return hits
    }

    /** Numbered list of results as plain text for the model. */
    fun search(query: String, max: Int = 7): String {
        var hits: List<Hit> = emptyList()
        var failure = ""
        try { hits = duckduckgo(query) } catch (e: Exception) { failure = e.message ?: "error" }
        if (hits.isEmpty()) {
            try { hits = bing(query) } catch (e: Exception) { failure = e.message ?: failure }
        }
        if (hits.isEmpty()) return "No results (search failed: $failure)"
        return hits.take(max).mapIndexed { i, h ->
            "${i + 1}. ${h.title}\n   ${h.url}\n   ${h.snippet.take(220)}"
        }.joinToString("\n")
    }

    /** Readable text of a page (first [maxChars] characters). */
    fun fetchText(url: String, maxChars: Int = 5000): String {
        return try {
            val raw = get(url)
            val text = if (raw.trimStart().startsWith("{") || raw.trimStart().startsWith("[")) raw else htmlToText(raw)
            if (text.isBlank()) "Page had no readable text." else text.take(maxChars)
        } catch (e: Exception) {
            "Could not open the page: " + (e.message ?: "error")
        }
    }

    /** Exchange rate and converted amount using a free public endpoint. */
    fun currency(amount: Double, from: String, to: String): String {
        return try {
            val f = from.trim().uppercase()
            val t = to.trim().uppercase()
            val body = get("https://open.er-api.com/v6/latest/$f", 100_000)
            val rate = Regex("\"$t\"\\s*:\\s*([0-9.]+)").find(body)?.groupValues?.get(1)?.toDoubleOrNull()
                ?: return "No rate found for $f to $t"
            "%.2f %s = %.2f %s (rate %.4f, open.er-api.com, official market rate; local street rates may differ)"
                .format(amount, f, amount * rate, t, rate)
        } catch (e: Exception) {
            "Currency lookup failed: " + (e.message ?: "error")
        }
    }
}
