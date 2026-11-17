package com.draborneagle.drabornslot

import android.content.Context
import android.util.Log
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

object EventLog {
    private const val FILE = "drabornslot_log"
    private val formatter = DateTimeFormatter.ofPattern("MM-dd HH:mm:ss")

    @Synchronized
    fun write(context: Context, message: String) {
        val pref = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val line = "${LocalDateTime.now().format(formatter)}  $message"
        val previous = pref.getString("entries", "") ?: ""
        val latest = (listOf(line) + previous.lines().filter { it.isNotBlank() }.take(99)).joinToString("\n")
        pref.edit().putString("entries", latest).apply()
        Log.i("DraBornSlot", message)
    }

    fun read(context: Context): String = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        .getString("entries", "") ?: ""

    data class Entry(val timestamp: String, val label: String, val message: String, val level: Int)

    fun entries(context: Context): List<Entry> = read(context).lines()
        .filter { it.isNotBlank() }
        .take(35)
        .map { line ->
            val timestamp = line.take(14).trim()
            val content = line.drop(14).trim()
            val (label, level) = when {
                content.contains("HATA:", true) || content.contains("başarısız", true) || content.contains("hatası", true) -> "HATA" to 3
                content.contains("ARAYÜZDE SEÇİLDİ", true) -> "SEÇİM GÖRÜLDÜ" to 2
                content.contains("DOKUNMA:", true) || content.contains("dokunuldu", true) -> "DOKUNMA" to 1
                content.contains("hazır", true) || content.contains("tarama", true) || content.contains("kaydır", true) -> "TARAMA" to 1
                else -> "BİLGİ" to 0
            }
            Entry(timestamp, label, content, level)
        }
}
