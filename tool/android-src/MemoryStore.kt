package com.codesoli.nova

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Facts the assistant learned about the user. Stored only on this phone. */
object MemoryStore {
    class Fact(val id: Long, val text: String, val at: Long)

    private const val FILE = "assistant_memory.json"
    private const val MAX_FACTS = 300

    private fun file(context: Context) = File(context.filesDir, FILE)

    @Synchronized
    fun all(context: Context): List<Fact> {
        val f = file(context)
        if (!f.exists()) return emptyList()
        return try {
            val array = JSONArray(f.readText())
            (0 until array.length()).map {
                val o = array.getJSONObject(it)
                Fact(o.getLong("id"), o.getString("text"), o.optLong("at"))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun save(context: Context, facts: List<Fact>) {
        val array = JSONArray()
        facts.forEach { array.put(JSONObject().put("id", it.id).put("text", it.text).put("at", it.at)) }
        file(context).writeText(array.toString())
    }

    private fun norm(text: String) = Commands.normalize(text).replace(Regex("[^\\p{L}\\p{N} ]"), "").trim()

    /** Adds a fact unless an equal or overlapping one exists. Returns true when stored. */
    @Synchronized
    fun add(context: Context, text: String): Boolean {
        val clean = text.trim().take(240)
        if (clean.length < 3) return false
        val facts = all(context).toMutableList()
        val n = norm(clean)
        val duplicate = facts.any { val o = norm(it.text); o == n || o.contains(n) || n.contains(o) && o.length > 12 }
        if (duplicate) {
            // A longer, newer version replaces the shorter older one.
            val index = facts.indexOfFirst { val o = norm(it.text); n.contains(o) && o.length > 12 && n.length > o.length }
            if (index >= 0) {
                facts[index] = Fact(facts[index].id, clean, System.currentTimeMillis())
                save(context, facts)
                return true
            }
            return false
        }
        facts.add(Fact(System.currentTimeMillis(), clean, System.currentTimeMillis()))
        while (facts.size > MAX_FACTS) facts.removeAt(0)
        save(context, facts)
        return true
    }

    @Synchronized
    fun remove(context: Context, id: Long) {
        save(context, all(context).filter { it.id != id })
    }

    /** Removes facts that contain [text]. */
    @Synchronized
    fun forget(context: Context, text: String): Int {
        val n = norm(text)
        if (n.length < 3) return 0
        val facts = all(context)
        val keep = facts.filter { !norm(it.text).contains(n) }
        save(context, keep)
        return facts.size - keep.size
    }

    @Synchronized
    fun clear(context: Context) {
        file(context).delete()
    }

    /** All facts when there are few, otherwise the ones that overlap with [query] plus the newest. */
    fun relevant(context: Context, query: String, limit: Int = 40): List<Fact> {
        val facts = all(context)
        if (facts.size <= limit) return facts
        val words = norm(query).split(' ').filter { it.length > 2 }.toSet()
        val scored = facts.sortedByDescending { f ->
            norm(f.text).split(' ').count { it in words }
        }
        val top = scored.take(limit - 10)
        val recent = facts.takeLast(10)
        return (top + recent).distinctBy { it.id }
    }
}
