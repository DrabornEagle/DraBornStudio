package com.draborneagle.drabornslot

import android.content.Context
import android.content.ComponentName
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityManager
import java.util.concurrent.FutureTask

internal fun Context.isSlotAccessibilityEnabled(): Boolean {
    val component = ComponentName(this, SlotAccessibilityService::class.java)
    val enabled = runCatching {
        Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
    }.getOrNull()
    if (enabled != null) return enabled.split(':').any { ComponentName.unflattenFromString(it) == component }
    if (SlotAccessibilityService.boundSince > 0) return true
    return runCatching {
        getSystemService(AccessibilityManager::class.java)
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { ComponentName.unflattenFromString(it.id) == component }
    }.getOrDefault(false)
}

internal enum class TrackingState {
    IDLE, WAITING_FOR_GO, WAITING_FOR_UNLOCK, TRACKING
}

internal data class SlotState(
    val plan: SettingsStore.Config,
    val pendingRemovals: Int,
    val confirmedSlots: Int,
    val history: String,
    val boundSince: Long,
    val lastConnection: Long,
    val lastCheck: Long,
    val lastDisconnection: Long,
    val lastError: String?,
    val trackingState: TrackingState,
    val backgroundRunning: Boolean
) {
    val isBound get() = boundSince > 0
    val shouldRunInBackground get() = plan.active && plan.background && plan.isUpcoming() &&
        (pendingRemovals > 0 || confirmedSlots < plan.slots.size)
}

internal class SlotStateClient(context: Context) {
    private val owner = context.applicationContext
    private val main = Handler(Looper.getMainLooper())

    fun read(): SlotState? = runCatching {
        val plan = SettingsStore.read(owner)
        val runtime = owner.getSharedPreferences(SettingsStore.RUNTIME, Context.MODE_PRIVATE)
        val boundSince = SlotAccessibilityService.boundSince
        SlotState(
            plan = plan,
            pendingRemovals = SettingsStore.pendingRemovals(owner, plan.date).size,
            confirmedSlots = plan.slots.count { SettingsStore.isUiConfirmed(owner, plan.date, it) },
            history = EventLog.read(owner),
            boundSince = boundSince,
            lastConnection = maxOf(boundSince, runtime.getLong("last_connected_at", 0L)),
            lastCheck = SlotAccessibilityService.lastHeartbeat,
            lastDisconnection = runtime.getLong("last_disconnected_at", 0L),
            lastError = runtime.getString("last_error", null),
            trackingState = SlotAccessibilityService.trackingState,
            backgroundRunning = BackgroundTrackingService.isRunning
        )
    }.onFailure { Log.w("DraBornSlot", "Plan durumu okunamadı", it) }.getOrNull()

    fun recover(): SlotState? = onMain {
        SlotAccessibilityService.reloadActivePlan(recover = true)
        read()
    }

    fun save(draft: SettingsStore.Config, removals: List<String>): Boolean = onMain {
        val pending = SettingsStore.pendingRemovals(owner, draft.date)
        val active = draft.active && (draft.slots.isNotEmpty() || removals.isNotEmpty() || pending.isNotEmpty())
        val plan = draft.copy(active = active, background = active && draft.background)
        val saved = SettingsStore.save(owner, plan, removals)
        SlotAccessibilityService.reloadActivePlan()
        BackgroundTrackingService.refresh()
        if (saved) {
            val mode = if (plan.dryRun) "izleme" else "canlı seçim"
            EventLog.write(owner, "Plan kaydedildi. ${plan.slots.size} saat, $mode, ${plan.refreshSeconds} sn yenileme.")
            if (removals.isNotEmpty()) EventLog.write(owner, "${removals.size} saat için kaldırma isteği kaydedildi.")
        }
        saved
    } == true

    fun pause(): Boolean = onMain {
        val saved = SettingsStore.save(owner, SettingsStore.read(owner).copy(active = false, background = false))
        SlotAccessibilityService.reloadActivePlan()
        BackgroundTrackingService.refresh()
        if (saved) EventLog.write(owner, "Takip durduruldu.")
        saved
    } == true

    fun reset(): Boolean = onMain {
        val cleared = SettingsStore.reset(owner)
        SlotAccessibilityService.reloadActivePlan(recover = true)
        BackgroundTrackingService.refresh()
        val historyCleared = EventLog.clear(owner)
        cleared && historyCleared
    } == true

    private fun <T> onMain(operation: () -> T): T? {
        // Plan writes and accessibility callbacks share one ordering.
        return try {
            if (Looper.myLooper() == main.looper) return operation()
            val task = FutureTask(operation)
            check(main.post(task))
            task.get()
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            null
        } catch (error: Exception) {
            Log.w("DraBornSlot", "Plan değişikliği uygulanamadı", error)
            null
        }
    }
}
