package com.draborneagle.drabornslot

import android.content.Context
import java.time.LocalDate

object SettingsStore {
    private const val FILE = "drabornslot_preferences"
    const val RUNTIME = "drabornslot_runtime"
    const val MIN_REFRESH_SECONDS = 1
    const val MAX_REFRESH_SECONDS = 60
    const val DEFAULT_DRY_RUN = false

    private val timeRange = Regex("""\b([01]\d|2[0-3]):([0-5]\d)\s*[-–—−]\s*([01]\d|2[0-3]):([0-5]\d)\b""")

    data class Config(
        val active: Boolean,
        val dryRun: Boolean,
        val date: String,
        val slots: List<String>,
        val refreshSeconds: Int,
        val background: Boolean = false
    ) {
        fun isUpcoming(): Boolean {
            val today = LocalDate.now()
            return runCatching { LocalDate.parse(date) in today..today.plusDays(6) }.getOrDefault(false)
        }
    }

    data class SlotGroup(val title: String, val slots: List<String>)

    val slotGroups = listOf(
        SlotGroup("Sabah", slotsFrom(8, 12)),
        SlotGroup("Öğle", slotsFrom(12, 17)),
        SlotGroup("Akşam", slotsFrom(17, 23)),
        SlotGroup("Gece", listOf("23:00-23:30", "23:30-23:59", "00:00-00:30", "00:30-01:00"))
    )
    val displayedSlots = slotGroups.flatMap { it.slots }

    private fun prefs(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private fun connectionPrefs(context: Context) =
        context.getSharedPreferences("drabornslot_connection", Context.MODE_PRIVATE)

    fun connectionProtectionEnabled(context: Context): Boolean =
        connectionPrefs(context).getBoolean("protect_connection", false)

    fun setConnectionProtection(context: Context, enabled: Boolean) {
        connectionPrefs(context).edit().putBoolean("protect_connection", enabled).apply()
    }

    private fun slotsFrom(firstHour: Int, endHour: Int) = (firstHour until endHour).flatMap { hour ->
        val start = hour.toString().padStart(2, '0')
        val end = (hour + 1).toString().padStart(2, '0')
        listOf("$start:00-$start:30", "$start:30-$end:00")
    }

    fun normalizeSlot(value: String): String? {
        // Reject long ranges where a slot picker must match a single half-hour row.
        val match = timeRange.find(value) ?: return null
        val (startHour, startMinute, endHour, endMinute) = match.destructured
        val start = 60 * startHour.toInt() + startMinute.toInt()
        val end = 60 * endHour.toInt() + endMinute.toInt()
        val duration = (end - start + 1440) % 1440
        if (duration != 30 && !(start == 1410 && end == 1439)) return null
        return "$startHour:$startMinute-$endHour:$endMinute"
    }

    fun slotLines(raw: String) = raw.lineSequence().mapNotNull(::normalizeSlot).distinct().toList()

    fun slotMinute(slot: String): Int {
        val hour = slot.substring(0, 2).toInt()
        val minute = slot.substring(3, 5).toInt()
        return (if (hour == 0) 24 else hour) * 60 + minute
    }

    fun defaults() = Config(
        active = false,
        dryRun = DEFAULT_DRY_RUN,
        date = LocalDate.now().toString(),
        slots = emptyList(),
        refreshSeconds = MIN_REFRESH_SECONDS
    )

    fun read(context: Context): Config {
        val prefs = prefs(context)
        val refresh = if (prefs.getBoolean("refresh_v04_migrated", false)) {
            prefs.getInt("refresh_seconds", MIN_REFRESH_SECONDS)
        } else {
            MIN_REFRESH_SECONDS
        }
        return Config(
            active = prefs.getBoolean("active", false),
            dryRun = prefs.getBoolean("dry_run", DEFAULT_DRY_RUN),
            date = prefs.getString("date", null) ?: LocalDate.now().toString(),
            slots = slotLines(prefs.getString("slots", "").orEmpty()),
            refreshSeconds = refresh.coerceIn(MIN_REFRESH_SECONDS, MAX_REFRESH_SECONDS),
            background = prefs.getBoolean("background", false)
        )
    }

    fun pendingRemovals(context: Context, date: String) =
        slotLines(prefs(context).getString("pending-removals-$date", "").orEmpty())

    fun save(context: Context, config: Config, removeFromGo: Collection<String> = emptyList()): Boolean {
        val slots = config.slots.mapNotNull(::normalizeSlot).distinct()
        val pending = (pendingRemovals(context, config.date) + removeFromGo)
            .mapNotNull(::normalizeSlot).distinct() - slots.toSet()
        return prefs(context).edit()
            .putBoolean("active", config.active)
            .putBoolean("background", config.active && config.background)
            .putBoolean("dry_run", config.dryRun)
            .putString("date", config.date)
            .putString("slots", slots.joinToString("\n"))
            .putString("pending-removals-${config.date}", pending.joinToString("\n"))
            .putInt("refresh_seconds", config.refreshSeconds.coerceIn(MIN_REFRESH_SECONDS, MAX_REFRESH_SECONDS))
            .putBoolean("refresh_v04_migrated", true)
            .commit()
    }

    fun reset(context: Context): Boolean {
        val planCleared = prefs(context).edit().clear().commit()
        val runtimeCleared = context.getSharedPreferences(RUNTIME, Context.MODE_PRIVATE).edit().clear().commit()
        return planCleared && runtimeCleared
    }

    fun isUiConfirmed(context: Context, date: String, slot: String) =
        prefs(context).getBoolean("ui-confirmed-$date-$slot", false)

    fun markUiConfirmed(context: Context, date: String, slot: String) {
        prefs(context).edit().putBoolean("ui-confirmed-$date-$slot", true).apply()
    }

    fun addAttempt(context: Context, date: String, slot: String) {
        val prefs = prefs(context)
        val key = "attempt-$date-$slot"
        prefs.edit().putInt(key, prefs.getInt(key, 0) + 1).apply()
    }

    fun completeRemoval(context: Context, date: String, slot: String) {
        val remaining = pendingRemovals(context, date) - slot
        prefs(context).edit()
            .putString("pending-removals-$date", remaining.joinToString("\n"))
            .remove("ui-confirmed-$date-$slot")
            .apply()
    }
}
