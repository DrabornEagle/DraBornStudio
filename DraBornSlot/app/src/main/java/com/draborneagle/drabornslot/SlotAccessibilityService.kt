package com.draborneagle.drabornslot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Point
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.time.LocalDate
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.math.abs
import kotlin.math.max

class SlotAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val imageWorker = Executors.newSingleThreadExecutor()
    private val power by lazy { getSystemService(PowerManager::class.java) }
    private val keyguard by lazy { getSystemService(KeyguardManager::class.java) }
    private val runtime by lazy { getSharedPreferences(SettingsStore.RUNTIME, MODE_PRIVATE) }

    private var stopped = true
    private var watching = false
    private var lastTreeAt = 0L
    private var nextCheckAt = Long.MAX_VALUE
    private var connectedAt = 0L
    @Volatile
    private var lastPulseAt = 0L
    @Volatile
    private var currentTrackingState = TrackingState.IDLE
    private var lastErrorAt = -15_000L
    private var settleUntil = 0L
    private var refreshAfter = 0L
    private var captureAfter = 0L
    private var gestureBusy = false
    private var gestureId = 0
    private var captureBusy = false
    private var processingImage = false
    private var captureId = 0
    private var session = 0
    private var windowId = -1
    private var contextPlan: SettingsStore.Config? = null
    private var dayVerified = false
    private var lastDayTap = 0L
    private var allHoursReady = false
    private var nextNavigationAt = 0L
    private var tabSwipes = 0
    private var returnsToTop = false
    private var scrollCount = 0
    private val scrollTries = mutableMapOf<String, Int>()
    private val reviewed = mutableSetOf<String>()
    private val lastAttempt = mutableMapOf<String, Long>()
    private val lastMessage = mutableMapOf<String, Long>()

    private data class Capture(
        val session: Int,
        val layout: String,
        val checkedDay: Boolean,
        val sampledSlots: Set<String>,
        val checkedHoursNavigation: Boolean,
        val result: SlotScreen.ImageResult
    )

    private val scheduledCheck = Runnable {
        nextCheckAt = Long.MAX_VALUE
        safeInspect()
    }

    private val pulse = object : Runnable {
        override fun run() {
            if (stopped || !watching) return
            lastPulseAt = System.currentTimeMillis()
            if (!interactive()) {
                waitForUnlock()
                return
            }
            requestCheck()
            handler.postDelayed(this, WATCH_INTERVAL)
        }
    }

    private val screenEvents = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (stopped || !watching) return
            if (intent.action == Intent.ACTION_SCREEN_OFF) {
                waitForUnlock()
            } else {
                handler.removeCallbacks(pulse)
                handler.post(pulse)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(screenEvents, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenEvents, filter)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        stopped = false
        connectedAt = System.currentTimeMillis()
        loadPlan()
        boundService = this
        BackgroundTrackingService.refresh()
        runCatching {
            runtime.edit().putLong("last_connected_at", connectedAt).apply()
            EventLog.write(this, "Erişilebilirlik servisi bağlandı.")
        }.onFailure { Log.w("DraBornSlot", "Servis bağlantısı kayda yazılamadı", it) }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (stopped || !watching || event == null) return
        val type = event.eventType
        if (event.packageName?.toString() != TARGET_PACKAGE) {
            if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && windowId != -1) resetWindow()
            return
        }
        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || type == AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            if (event.windowId != windowId && windowId != -1) resetWindow()
        }
        if (type == AccessibilityEvent.TYPE_VIEW_CLICKED || type == AccessibilityEvent.TYPE_VIEW_SELECTED) {
            val labels = event.text.orEmpty() + listOfNotNull(event.contentDescription)
            if (labels.any { SlotScreen.dayLabel(it.toString()) != null ||
                    SlotScreen.hoursTab(it.toString()) == SlotScreen.HoursTab.OTHER }) {
                dayVerified = false
                allHoursReady = false
                captureId++
                captureBusy = false
            }
        }
        requestCheck()
    }

    override fun onInterrupt() {
        if (stopped || !watching) return
        resetWindow()
        note("interrupted", "Android erişilebilirlik işlemini kesintiye uğrattı.", 30_000)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        disconnect()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        disconnect()
        unregisterReceiver(screenEvents)
        imageWorker.shutdown()
        super.onDestroy()
    }

    private fun disconnect() {
        if (stopped) return
        stopped = true
        if (boundService === this) boundService = null
        clearTrackingSession()
        BackgroundTrackingService.refresh()
        runCatching { runtime.edit().putLong("last_disconnected_at", System.currentTimeMillis()).apply() }
            .onFailure { Log.w("DraBornSlot", "Servis ayrılması kayda yazılamadı", it) }
    }

    private fun loadPlan(recover: Boolean = false) {
        clearTrackingSession()
        if (recover && Build.VERSION.SDK_INT >= 33) {
            runCatching { clearCache() }
                .onFailure { Log.w("DraBornSlot", "Erişilebilirlik önbelleği temizlenemedi", it) }
        }
        watching = runCatching {
            val plan = SettingsStore.read(this)
            plan.active && (plan.slots.isNotEmpty() || SettingsStore.pendingRemovals(this, plan.date).isNotEmpty())
        }.getOrElse {
            recordError("Plan okunamadı", it)
            false
        }
        if (watching) {
            currentTrackingState = TrackingState.WAITING_FOR_GO
            handler.post(pulse)
        }
    }

    private fun clearTrackingSession() {
        watching = false
        currentTrackingState = TrackingState.IDLE
        handler.removeCallbacks(scheduledCheck)
        handler.removeCallbacks(pulse)
        nextCheckAt = Long.MAX_VALUE
        resetWindow()
        contextPlan = null
        lastPulseAt = 0
        lastTreeAt = 0
        captureAfter = 0
        lastErrorAt = -15_000L
        lastAttempt.clear()
        lastMessage.clear()
    }

    private fun requestCheck(delay: Long = 0L) {
        if (stopped || !watching) return
        val at = max(SystemClock.uptimeMillis() + delay, lastTreeAt + MIN_TREE_INTERVAL)
        if (at >= nextCheckAt) return
        handler.removeCallbacks(scheduledCheck)
        nextCheckAt = at
        handler.postAtTime(scheduledCheck, at)
    }

    private fun waitForUnlock() {
        currentTrackingState = TrackingState.WAITING_FOR_UNLOCK
        handler.removeCallbacks(pulse)
        handler.removeCallbacks(scheduledCheck)
        nextCheckAt = Long.MAX_VALUE
        if (windowId != -1) resetWindow()
    }

    private fun safeInspect(capture: Capture? = null) {
        if (stopped || !watching) return
        try {
            inspect(capture)
        } catch (error: Exception) {
            recordError("Slot ekranı taraması", error)
        }
    }

    private fun recordError(operation: String, error: Throwable) {
        val now = SystemClock.uptimeMillis()
        if (now - lastErrorAt < 15_000L) return
        lastErrorAt = now
        val description = "$operation · ${error.javaClass.simpleName}: ${error.message.orEmpty().take(140)}"
        Log.e("DraBornSlot", operation, error)
        runCatching {
            runtime.edit().putString("last_error", description)
                .putLong("last_error_at", System.currentTimeMillis()).apply()
            note("service-error", "HATA: $description", 15_000)
        }.onFailure { Log.w("DraBornSlot", "Servis hatası kayda yazılamadı", it) }
    }

    private fun inspect(capture: Capture?) {
        val config = SettingsStore.read(this)
        val removals = SettingsStore.pendingRemovals(this, config.date)
        val date = runCatching { LocalDate.parse(config.date) }.getOrNull()
        val today = LocalDate.now()
        if (date == null || date.isBefore(today) || date.isAfter(today.plusDays(6))) {
            finishChecks(config)
            return
        }
        val targetSlots = config.slots.toSet()
        val pending = (targetSlots.filterNot { SettingsStore.isUiConfirmed(this, config.date, it) } + removals).toSet()
        if (!config.active || pending.isEmpty()) {
            finishChecks(config)
            return
        }
        if (!interactive()) {
            waitForUnlock()
            return
        }

        val now = SystemClock.uptimeMillis()
        if (gestureBusy || (capture == null && captureBusy)) return
        if (now < settleUntil) {
            requestCheck(settleUntil - now)
            return
        }
        lastTreeAt = now

        val root = targetRoot() ?: run {
            currentTrackingState = TrackingState.WAITING_FOR_GO
            if (windowId != -1) resetWindow()
            return
        }
        currentTrackingState = TrackingState.TRACKING
        if (windowId != root.windowId || contextPlan != config) {
            resetWindow()
            windowId = root.windowId
            contextPlan = config
        }

        SlotScreen(root, date.dayOfMonth, resources.displayMetrics.density).use { screen ->
            if (screen.temporarilyUnavailable) {
                refreshAfter = max(refreshAfter, now + 12_000)
                note("go-wait", "Trendyol GO geçici hata gösteriyor. Yenileme ertelendi.", 20_000)
                return
            }
            if (screen.loading) return
            val fresh = capture?.takeIf { it.session == session && it.layout == screen.layoutKey }
            if (capture != null && fresh == null) {
                requestCheck()
                return
            }
            if (!config.dryRun && !prepareAllHours(screen, fresh, now)) return
            if (!screen.isSchedule) {
                dayVerified = false
                return
            }
            if (!verifyDay(screen, date.dayOfMonth, config, fresh, now)) return

            val targetRows = screen.rows.filter { it.slot in targetSlots || it.slot in removals }
            val buttons = targetRows.mapNotNull { row ->
                (screen.buttonFor(row) ?: fresh?.result?.buttons?.get(row.slot))?.let { row.slot to it }
            }.toMap()

            if (processButtons(buttons, config, removals, now)) return

            val unknownVisible = targetRows.filter { it.slot in pending && it.slot !in buttons }.map { it.slot }
            val sampled = fresh?.sampledSlots.orEmpty()
            val unresolvedVisible = unknownVisible.filterNot { it in reviewed || it in sampled }
            if (unresolvedVisible.isNotEmpty()) {
                requestImage(screen, false, unresolvedVisible.toSet(), now)
                return
            }
            reviewed.addAll(unknownVisible.filter { it in sampled })
            if (config.dryRun) {
                // The dry run observes rendered controls and never scrolls or clicks.
                reviewed.removeAll(unknownVisible.toSet())
                return
            }

            advance(screen, config, now)
        }
    }

    private fun finishChecks(config: SettingsStore.Config) {
        clearTrackingSession()
        if (config.background) BackgroundTrackingService.refresh()
    }

    private fun prepareAllHours(screen: SlotScreen, capture: Capture?, now: Long): Boolean {
        when (screen.selectedHoursTab) {
            SlotScreen.HoursTab.ALL -> allHoursReady = true
            SlotScreen.HoursTab.OTHER -> allHoursReady = false
            null -> Unit
        }
        if (allHoursReady && screen.isSchedule) return true
        if (!screen.isSchedule) {
            allHoursReady = false
            dayVerified = false
            tabSwipes = 0
        }
        if (now < nextNavigationAt) {
            requestCheck(nextNavigationAt - now)
            return false
        }
        val tab = screen.allHoursTab
        val nearbyTab = screen.otherHoursTab
        val hours = screen.hoursNavigation
        val navIcon = capture?.result?.hoursNavigation

        when {
            tab != null -> {
                nextNavigationAt = now + 950
                click(tab, Point(tab.bounds.centerX(), tab.bounds.centerY())) { accepted ->
                    if (accepted) {
                        // Some GO releases expose the tab caption without a selected flag.
                        allHoursReady = true
                        dayVerified = false
                        reviewed.clear()
                        scrollTries.clear()
                        scrollCount = 0
                        returnsToTop = false
                        note("all-hours", "Tüm Saatler sekmesine geçiliyor.", 6_000)
                    }
                }
            }
            nearbyTab != null && tabSwipes < 2 -> {
                nextNavigationAt = now + 600
                tabSwipes++
                val y = nearbyTab.bounds.centerY().toFloat()
                val path = Path().apply {
                    moveTo(screen.bounds.left + screen.bounds.width() * 0.87f, y)
                    lineTo(screen.bounds.left + screen.bounds.width() * 0.29f, y)
                }
                gesture(path, 220, settleMs = 150)
            }
            screen.isSchedule && nearbyTab == null && screen.rows.isNotEmpty() &&
                scroll(screen, forward = false, seekingRefresh = true) -> nextNavigationAt = now + 360
            !screen.isSchedule && hours != null -> {
                nextNavigationAt = now + 950
                click(hours, Point(hours.bounds.centerX(), hours.bounds.centerY())) { }
            }
            !screen.isSchedule && navIcon != null -> {
                nextNavigationAt = now + 950
                click(null, navIcon) { }
            }
            !screen.isSchedule && capture?.checkedHoursNavigation != true ->
                requestImage(screen, false, emptySet(), now, checkHoursNavigation = true)
            else -> {
                nextNavigationAt = now + 4_000
                note("hours-missing", "Trendyol GO’da Saatler bölümünü ve Tüm Saatler sekmesini aç.", 35_000)
            }
        }
        return false
    }

    private fun verifyDay(
        screen: SlotScreen,
        day: Int,
        config: SettingsStore.Config,
        capture: Capture?,
        now: Long
    ): Boolean {
        if (screen.selectedDay != null) {
            dayVerified = screen.selectedDay == day
        } else if (capture?.checkedDay == true) {
            dayVerified = capture.result.selectedDay
        }
        if (dayVerified) return true

        val candidate = screen.targetDay
        if (candidate == null) {
            note("need-day", "Trendyol GO’da saat ekranını en üstten aç ve hedef günü göster.", 35_000)
            return false
        }
        if (screen.selectedDay == null && capture?.checkedDay != true) {
            val visibleTargets = screen.rows.filter { it.slot in config.slots && screen.buttonFor(it) == null }
            requestImage(screen, true, visibleTargets.map { it.slot }.toSet(), now)
        } else if (!config.dryRun && now - lastDayTap >= 1_250) {
            lastDayTap = now
            click(candidate, Point(candidate.bounds.centerX(), candidate.bounds.centerY())) {
                if (it) {
                    allHoursReady = false
                    nextNavigationAt = 0
                    note("set-day", "Hedef gün seçildi. Saatler yeniden denetleniyor.", 9_000)
                }
            }
        } else if (config.dryRun) {
            note("preview-day", "İzleme için Trendyol GO’da hedef günü aç.", 35_000)
        }
        return false
    }

    private fun processButtons(
        buttons: Map<String, SlotScreen.Button>,
        config: SettingsStore.Config,
        removals: List<String>,
        now: Long
    ): Boolean {
        for (slot in config.slots) {
            val button = buttons[slot] ?: continue
            if (button.type != SlotScreen.ButtonType.REMOVE) continue
            if (!SettingsStore.isUiConfirmed(this, config.date, slot)) {
                SettingsStore.markUiConfirmed(this, config.date, slot)
                EventLog.write(this, "ARAYÜZDE SEÇİLDİ: $slot için kaldırma işareti görüldü.")
            }
        }
        for (slot in removals) {
            if (buttons[slot]?.type != SlotScreen.ButtonType.ADD) continue
            SettingsStore.completeRemoval(this, config.date, slot)
            EventLog.write(this, "KALDIRMA GÖRÜLDÜ: $slot tekrar eklenebilir durumda.")
        }

        for (slot in config.slots + removals) {
            val button = buttons[slot] ?: continue
            val remove = slot in removals && slot !in config.slots
            val expected = if (remove) SlotScreen.ButtonType.REMOVE else SlotScreen.ButtonType.ADD
            if (button.type != expected || (!remove && SettingsStore.isUiConfirmed(this, config.date, slot))) continue

            val key = "${config.date}|$slot|$expected"
            if (config.dryRun) {
                note("preview-$key", "İZLEME: $slot ${if (remove) "kaldırılabilir" else "eklenebilir"}.", 25_000)
                continue
            }
            if (now - (lastAttempt[key] ?: -RETRY_INTERVAL) < RETRY_INTERVAL) continue
            lastAttempt[key] = now
            refreshAfter = max(refreshAfter, now + 650)
            val sameSession = session
            click(button.element, button.point) { accepted ->
                if (sameSession == session && accepted) {
                    if (!remove) SettingsStore.addAttempt(this, config.date, slot)
                    EventLog.write(this, "DOKUNMA: $slot için ${if (remove) "kaldır" else "ekle"} işlemi gönderildi.")
                }
            }
            return true
        }
        return false
    }

    private fun advance(screen: SlotScreen, config: SettingsStore.Config, now: Long) {
        val pending = config.slots.filterNot { SettingsStore.isUiConfirmed(this, config.date, it) } +
            SettingsStore.pendingRemovals(this, config.date)
        if (pending.isEmpty() || screen.rows.isEmpty()) return
        val visibleMinutes = screen.rows.map { SettingsStore.slotMinute(it.slot) }
        val first = visibleMinutes.min()
        val last = visibleMinutes.max()
        val visible = screen.rows.map { it.slot }.toSet()

        if (!returnsToTop) {
            val offscreen = pending.asSequence().filter { it !in visible && it !in reviewed }
                .map(SettingsStore::slotMinute).filter { it < first || it > last }
                .sortedBy { minOf(abs(it - first), abs(it - last)) }.toList()
            for (forward in offscreen.map { it > last }.distinct()) {
                if (scroll(screen, forward, seekingRefresh = false)) return
            }
        }
        if (now < refreshAfter) {
            requestCheck(refreshAfter - now)
            return
        }
        val refresh = screen.refresh
        if (refresh != null && refresh.node.isEnabled) {
            refreshAfter = now + config.refreshSeconds * 1_000L
            returnsToTop = false
            click(refresh, Point(refresh.bounds.centerX(), refresh.bounds.centerY())) { accepted ->
                if (accepted) {
                    reviewed.clear()
                    scrollTries.clear()
                    scrollCount = 0
                    note("refresh", "Saat sayfası yenilendi.", 15_000)
                }
            }
        } else {
            returnsToTop = true
            if (!scroll(screen, forward = false, seekingRefresh = true)) {
                refreshAfter = now + max(config.refreshSeconds * 1_000L, 2_000L)
                returnsToTop = false
                scrollCount = 0
                scrollTries.clear()
                reviewed.clear()
                note("refresh-missing", "Yenileme düğmesi görünmüyor. Saat ekranı izleniyor.", 35_000)
            }
        }
    }

    private fun scroll(screen: SlotScreen, forward: Boolean, seekingRefresh: Boolean): Boolean {
        val page = screen.rows.joinToString(",") { it.slot } +
            "#${screen.rows.firstOrNull()?.bounds?.centerY()?.div(30)}"
        val key = "$seekingRefresh|$forward|$page"
        val tries = scrollTries[key] ?: 0
        if (tries >= 2 || scrollCount >= if (seekingRefresh) 48 else 34) return false
        if (!isTargetActive()) return false
        scrollTries[key] = tries + 1
        scrollCount++

        val list = screen.list
        if (list != null && tries == 0) {
            val preferred = if (forward) AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_DOWN
                else AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_UP
            val standard = if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            val id = if (list.node.actionList.any { it.id == preferred.id }) preferred.id else standard
            if (list.node.performAction(id)) {
                settle(190)
                return true
            }
        }
        val region = list?.bounds ?: Rect(screen.bounds).apply {
            top += (height() * 0.25f).toInt()
            bottom -= (height() * 0.07f).toInt()
        }
        if (region.height() <= 20) return false
        val x = region.centerX().toFloat()
        val upper = (region.top + region.height() * 0.19f)
        val lower = (region.top + region.height() * 0.84f)
        val path = Path().apply {
            moveTo(x, if (forward) lower else upper)
            lineTo(x, if (forward) upper else lower)
        }
        gesture(path, 225L, settleMs = 125L)
        return true
    }

    private fun requestImage(
        screen: SlotScreen,
        date: Boolean,
        slots: Set<String>,
        now: Long,
        checkHoursNavigation: Boolean = false
    ) {
        if (processingImage) return
        if (now < captureAfter) {
            requestCheck(captureAfter - now)
            return
        }
        val density = resources.displayMetrics.density
        val probe = screen.probe(date, slots, checkHoursNavigation)
        val requestedSession = session
        val layout = screen.layoutKey
        val id = ++captureId
        captureBusy = true
        captureAfter = now + IMAGE_INTERVAL

        // A late Android callback cannot hold the scan loop or replace a more recent frame.
        handler.postDelayed({
            if (captureBusy && id == captureId) {
                captureBusy = false
                captureId++
                captureAfter = SystemClock.uptimeMillis() + 400
                requestCheck()
            }
        }, 1_750)

        try {
            takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    if (stopped || !watching || id != captureId || requestedSession != session) {
                        screenshot.hardwareBuffer.close()
                        return
                    }
                    if (!runCatching { isTargetActive() }.getOrDefault(false)) {
                        screenshot.hardwareBuffer.close()
                        captureBusy = false
                        requestCheck()
                        return
                    }
                    processingImage = true
                    try {
                        imageWorker.execute {
                            val result = try {
                                val buffer = screenshot.hardwareBuffer
                                val bitmap = try {
                                    val hardware = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
                                    try { hardware?.copy(Bitmap.Config.ARGB_8888, false) } finally { hardware?.recycle() }
                                } finally {
                                    buffer.close()
                                }
                                if (bitmap == null) null else try {
                                    SlotScreen.inspectImage(bitmap, probe, density)
                                } finally {
                                    bitmap.recycle()
                                }
                            } catch (error: Exception) {
                                Log.w("DraBornSlot", "Slot görüntüsü okunamadı", error)
                                null
                            } catch (error: OutOfMemoryError) {
                                Log.w("DraBornSlot", "Slot görüntüsü için bellek yetersiz", error)
                                null
                            }
                            handler.post {
                                processingImage = false
                                if (!stopped && watching && id == captureId && requestedSession == session) {
                                    captureBusy = false
                                    if (result != null) {
                                        safeInspect(Capture(requestedSession, layout, date, slots, checkHoursNavigation, result))
                                    } else {
                                        captureAfter = SystemClock.uptimeMillis() + 1_100
                                        requestCheck(1_100)
                                    }
                                } else {
                                    requestCheck()
                                }
                            }
                        }
                    } catch (_: RejectedExecutionException) {
                        screenshot.hardwareBuffer.close()
                        processingImage = false
                        captureBusy = false
                    }
                }

                override fun onFailure(errorCode: Int) {
                    if (stopped || !watching || id != captureId) return
                    captureBusy = false
                    val tooSoon = errorCode == ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT
                    captureAfter = SystemClock.uptimeMillis() + if (tooSoon) 450 else 1_100
                    if (!tooSoon) note("capture-$errorCode", "Ekran görüntüsü alınamadı ($errorCode).", 30_000)
                    requestCheck(captureAfter - SystemClock.uptimeMillis())
                }
            })
        } catch (error: RuntimeException) {
            captureBusy = false
            throw error
        }
    }

    private fun click(element: SlotScreen.Element?, point: Point, completed: (Boolean) -> Unit) {
        if (!isTargetActive()) return
        if (element != null && !element.node.isEnabled) return
        if (element != null && element.node.isClickable &&
            element.node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            settle(145)
            completed(true)
            return
        }
        val path = Path().apply { moveTo(point.x.toFloat(), point.y.toFloat()) }
        gesture(path, 55L, settleMs = 110L, completed)
    }

    private fun gesture(path: Path, duration: Long, settleMs: Long, completed: (Boolean) -> Unit = {}) {
        if (!isTargetActive()) return
        val description = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0L, duration)).build()
        gestureBusy = true
        val id = ++gestureId
        fun finish(accepted: Boolean) {
            if (id != gestureId || !gestureBusy || stopped) return
            gestureBusy = false
            settle(settleMs)
            try {
                completed(accepted)
            } catch (error: Exception) {
                recordError("Erişilebilirlik hareketi", error)
            }
        }
        val accepted = try {
            dispatchGesture(description, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) = finish(true)
                override fun onCancelled(gestureDescription: GestureDescription?) = finish(false)
            }, handler)
        } catch (error: RuntimeException) {
            gestureBusy = false
            throw error
        }
        if (!accepted) finish(false)
        else handler.postDelayed({ finish(false) }, duration + 850)
    }

    private fun settle(delay: Long) {
        settleUntil = SystemClock.uptimeMillis() + delay
        requestCheck(delay)
    }

    private fun targetRoot(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        if (root.packageName?.toString() == TARGET_PACKAGE) return root
        SlotScreen.recycle(root)
        return null
    }

    private fun interactive() = power.isInteractive && !keyguard.isKeyguardLocked

    private fun isTargetActive(): Boolean {
        if (stopped || !watching || !interactive()) return false
        val root = targetRoot() ?: return false
        return try { root.windowId == windowId } finally { SlotScreen.recycle(root) }
    }

    private fun resetWindow() {
        windowId = -1
        session++
        captureId++
        captureBusy = false
        gestureId++
        gestureBusy = false
        dayVerified = false
        lastDayTap = 0
        allHoursReady = false
        nextNavigationAt = 0
        tabSwipes = 0
        settleUntil = 0
        refreshAfter = 0
        returnsToTop = false
        reviewed.clear()
        scrollTries.clear()
        scrollCount = 0
        if (lastAttempt.size > 256) lastAttempt.clear()
    }

    private fun note(key: String, message: String, cooldown: Long) {
        val now = SystemClock.uptimeMillis()
        if (now - (lastMessage[key] ?: -cooldown) < cooldown) return
        if (lastMessage.size > 256) lastMessage.clear()
        lastMessage[key] = now
        EventLog.write(this, message)
    }

    companion object {
        const val TARGET_PACKAGE = "com.orangemobile"
        private const val MIN_TREE_INTERVAL = 95L
        private const val WATCH_INTERVAL = 750L
        private const val IMAGE_INTERVAL = 500L
        private const val RETRY_INTERVAL = 3_500L

        @Volatile
        private var boundService: SlotAccessibilityService? = null

        val boundSince get() = boundService?.connectedAt ?: 0L
        val lastHeartbeat get() = boundService?.lastPulseAt ?: 0L
        internal val trackingState get() = boundService?.currentTrackingState ?: TrackingState.IDLE

        internal fun reloadActivePlan(recover: Boolean = false) {
            boundService?.loadPlan(recover)
        }
    }
}
