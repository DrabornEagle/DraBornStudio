package com.draborneagle.drabornslot

import android.content.Context
import java.time.LocalDate
import java.time.LocalTime
import java.time.Duration

/** No personal credentials or session cookies are stored. */
object SettingsStore {
    private const val FILE = "drabornslot_preferences"
    private fun p(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    data class Config(
        val active: Boolean,
        val dryRun: Boolean,
        val date: String,
        val slots: List<String>,
        val refreshSeconds: Int
    )

    fun normalizeSlot(value: String): String? {
        val match = Regex("""\b(\d{2}:\d{2})\s*[-–—]\s*(\d{2}:\d{2})\b""").find(value) ?: return null
        val start = match.groupValues[1]
        val end = match.groupValues[2]
        val valid = Regex("""(?:[01]\d|2[0-3]):[0-5]\d""")
        if (!valid.matches(start) || !valid.matches(end)) return null
        if (start == "23:30" && end == "23:59") return "23:30-23:59"
        if (Duration.between(LocalTime.parse(start), LocalTime.parse(end)).toMinutes().let { if (it < 0) it + 1440L else it } != 30L) return null
        return "$start-$end"
    }

    fun slotLines(raw: String): List<String> = raw.lines().mapNotNull(::normalizeSlot).distinct().take(8)

    fun read(context: Context): Config {
        val pref = p(context)
        return Config(
            pref.getBoolean("active", false),
            pref.getBoolean("dry_run", true),
            pref.getString("date", LocalDate.now().toString()) ?: LocalDate.now().toString(),
            slotLines(pref.getString("slots", "08:00-08:30\n08:30-09:00") ?: ""),
            pref.getInt("refresh_seconds", 10).coerceIn(5, 60)
        )
    }

    fun save(context: Context, config: Config) {
        p(context).edit()
            .putBoolean("active", config.active)
            .putBoolean("dry_run", config.dryRun)
            .putString("date", config.date)
            .putString("slots", config.slots.joinToString("\n"))
            .putInt("refresh_seconds", config.refreshSeconds.coerceIn(5, 60))
            .apply()
    }

    fun heartbeat(context: Context, at: Long = System.currentTimeMillis()) {
        p(context).edit().putLong("agent_heartbeat", at).apply()
    }

    fun lastHeartbeat(context: Context): Long = p(context).getLong("agent_heartbeat", 0L)

    fun unmarkUiConfirmed(context: Context, date: String, slot: String) {
        p(context).edit().remove("ui-confirmed-$date-$slot").apply()
    }

    fun attemptCount(context: Context, date: String, slot: String): Int =
        p(context).getInt("attempt-$date-$slot", 0)

    fun addAttempt(context: Context, date: String, slot: String) {
        val current = attemptCount(context, date, slot)
        p(context).edit().putInt("attempt-$date-$slot", current + 1).apply()
    }

    fun isUiConfirmed(context: Context, date: String, slot: String): Boolean =
        p(context).getBoolean("ui-confirmed-$date-$slot", false)

    fun markUiConfirmed(context: Context, date: String, slot: String) {
        p(context).edit().putBoolean("ui-confirmed-$date-$slot", true).apply()
    }

    fun clearAttempts(context: Context, date: String) {
        val prefs = p(context)
        val edit = prefs.edit()
        prefs.all.keys.filter { it.startsWith("attempt-$date-") || it.startsWith("ui-confirmed-$date-") }
            .forEach { edit.remove(it) }
        edit.apply()
    }
}
