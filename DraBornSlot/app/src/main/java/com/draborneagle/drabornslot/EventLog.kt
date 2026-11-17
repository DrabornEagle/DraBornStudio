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
        .getString("entries", "Henüz kayıt yok.") ?: "Henüz kayıt yok."
}
