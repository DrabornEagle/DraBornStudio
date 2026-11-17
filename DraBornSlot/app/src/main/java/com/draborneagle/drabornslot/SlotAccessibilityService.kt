package com.draborneagle.drabornslot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.ColorSpace
import android.graphics.Path
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.max
import kotlin.math.min

/**
 * DraBornSlot Agent v0.1
 *
 * Explicitly opt-in UI automation. It only operates in the visible com.orangemobile
 * slot screen. It never reads tokens, enters passwords, bypasses CAPTCHAs, or invokes
 * undocumented APIs. Confirmation of an actual booking is NOT available in v0.1.
 */
class SlotAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val mainPeriodMs = 2_500L
    private var lastInspectMs = 0L
    private var lastRefreshMs = 0L
    private var screenshotBusy = false
    private var gestureBusy = false
    private var stopped = false
    private val lastMessages = mutableMapOf<String, Long>()
    private val lastAttempt = mutableMapOf<String, Long>()

    private data class FoundRow(val slot: String, val bounds: Rect)
    private data class Tap(val x: Int, val y: Int)

    private val eventInspect = Runnable { inspect(SettingsStore.read(this)) }

    private val tick = object : Runnable {
        override fun run() {
            if (stopped) return
            val config = SettingsStore.read(this@SlotAccessibilityService)
            if (config.active) {
                maybeRefresh(config)
                inspect(config)
            }
            handler.postDelayed(this, mainPeriodMs)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        stopped = false
        EventLog.write(this, "Erişilebilirlik servisi bağlandı.")
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName?.toString() != TARGET_PACKAGE) return
        if (!SettingsStore.read(this).active) return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        ) {
            // Debounced inspection; repeated React Native accessibility events are common.
            handler.removeCallbacks(eventInspect)
            handler.postDelayed(eventInspect, 900L)
        }
    }

    override fun onInterrupt() {
        note("interrupt", "Android erişilebilirlik servisini kesintiye uğrattı.", 30_000L)
    }

    override fun onDestroy() {
        stopped = true
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun isTargetVisible(): Boolean =
        rootInActiveWindow?.packageName?.toString() == TARGET_PACKAGE

    private fun inspect(config: SettingsStore.Config) {
        if (!config.active || gestureBusy || screenshotBusy || !isTargetVisible()) return
        val now = System.currentTimeMillis()
        if (now - lastInspectMs < 1_750L) return
        lastInspectMs = now

        val date = runCatching { LocalDate.parse(config.date) }.getOrNull() ?: return
        if (ChronoUnit.DAYS.between(LocalDate.now(), date) !in 0..6) {
            note("invalid-date", "Tarih görünür 7 günlük aralığın dışında; işlem durduruldu.", 300_000L)
            return
        }
        if (config.slots.isEmpty()) return

        val root = rootInActiveWindow ?: return
        val items = mutableListOf<Pair<String, Rect>>()
        collectVisibleTexts(root, items, 0)
        val dateLabel = date.dayOfMonth.toString()
        val dateCandidates = items.filter { (value, r) ->
            (value.trim() == dateLabel || Regex("""^${Regex.escape(dateLabel)}\s+\S{2,5}$""").matches(value.trim())) &&
                r.top >= 0 && r.top < resources.displayMetrics.heightPixels * 0.24f && r.width() > 0
        }
        val timeRows = items.mapNotNull { (value, bounds) ->
            val slot = SettingsStore.normalizeSlot(value) ?: return@mapNotNull null
            if (slot !in config.slots || bounds.width() <= 0 || bounds.height() <= 0) null
            else FoundRow(slot, bounds)
        }.distinctBy { it.slot }

        if (dateCandidates.isEmpty() || timeRows.isEmpty()) {
            note("missing-screen", "Saat seçimi ekranı / hedef tarih görünmüyor. Oturum ve sayfayı kontrol et.", 90_000L)
            return
        }

        screenshotBusy = true
        try {
            takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
            override fun onSuccess(screenshot: ScreenshotResult) {
                screenshotBusy = false
                val bitmap = try {
                    // HardwareBuffer is closed after copying pixels to software memory.
                    val buffer = screenshot.hardwareBuffer
                    try {
                        val cs = screenshot.colorSpace ?: ColorSpace.get(ColorSpace.Named.SRGB)
                        Bitmap.wrapHardwareBuffer(buffer, cs)?.copy(Bitmap.Config.ARGB_8888, false)
                    } finally {
                        buffer.close()
                    }
                } catch (_: Exception) {
                    null
                }
                if (bitmap == null) {
                    note("bitmap-fail", "Ekran görüntüsü çözülemedi; güvenlik için tıklama yapılmadı.", 90_000L)
                    return
                }
                try {
                    if (!config.active || !isTargetVisible()) return
                    evaluate(bitmap, dateCandidates.map { it.second }, date, timeRows, config)
                } finally {
                    bitmap.recycle()
                }
            }

            override fun onFailure(errorCode: Int) {
                screenshotBusy = false
                note("screenshot-fail", "Ekran doğrulanamadı (hata $errorCode); tıklama yapılmadı.", 90_000L)
            }
            })
        } catch (_: Exception) {
            screenshotBusy = false
            note("screenshot-exception", "Android ekran görüntüsüne izin vermedi; tıklama yapılmadı.", 90_000L)
        }
    }

    private fun evaluate(
        bitmap: Bitmap,
        dateBounds: List<Rect>,
        date: LocalDate,
        rows: List<FoundRow>,
        config: SettingsStore.Config
    ) {
        val selected = dateBounds.any { isSelectedDateCell(bitmap, it) }
        if (!selected) {
            val rect = dateBounds.first()
            if (config.dryRun) {
                note("date-preview", "TEST: ${config.date} günü seçili görünmüyor; seçilmesi gerekecek.", 120_000L)
            } else {
                gestureBusy = true
                tap(rect.centerX(), rect.centerY()) { ok ->
                    gestureBusy = false
                    if (ok) note("date-tap", "${config.date} tarih sekmesine dokunuldu.", 40_000L)
                    handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_300L)
                }
            }
            return
        }

        for (row in rows) {
            if (SettingsStore.attemptCount(this, config.date, row.slot) >= 2) continue
            val key = "${config.date}|${row.slot}"
            val last = lastAttempt[key] ?: 0L
            if (System.currentTimeMillis() - last < 90_000L) continue
            val target = findVerifiedGreenPlus(bitmap, row.bounds) ?: continue
            if (config.dryRun) {
                note("test-$key", "TEST: ${row.slot} için yeşil + algılandı (x=${target.x},y=${target.y}).", 120_000L)
                continue
            }
            // Re-check the original app remains foreground before each irreversible action.
            if (!isTargetVisible()) return
            gestureBusy = true
            lastAttempt[key] = System.currentTimeMillis()
            tap(target.x, target.y) { ok ->
                gestureBusy = false
                if (ok) {
                    SettingsStore.addAttempt(this, config.date, row.slot)
                    EventLog.write(this, "SEÇİM DENEMESİ: ${row.slot} (+ tıklandı). Rezervasyon henüz doğrulanmadı.")
                } else {
                    EventLog.write(this, "Tıklama başarısız: ${row.slot}")
                }
                handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_800L)
            }
            return // only one gesture per screenshot: rescan before doing another
        }
    }

    private fun collectVisibleTexts(node: AccessibilityNodeInfo, out: MutableList<Pair<String, Rect>>, depth: Int) {
        if (depth > 35 || out.size > 1_500) return
        val text = node.text?.toString()?.trim().orEmpty()
        if (text.isNotEmpty() && node.isVisibleToUser) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            out.add(text to rect)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectVisibleTexts(child, out, depth + 1)
        }
    }

    private fun isSelectedDateCell(bitmap: Bitmap, label: Rect): Boolean {
        // The provided UI uses a solid black background for the selected date.
        // Accept either tight text bounds or a merged entire-card text node.
        val margin = max(6, (8 * resources.displayMetrics.density).toInt())
        val points = listOf(
            Pair(label.left - margin, label.centerY()),
            Pair(label.right + margin, label.centerY()),
            Pair(label.left + 6, label.top + 4),
            Pair(label.right - 6, label.top + 4)
        )
        val dark = points.count { (px, py) ->
            val x = px.coerceIn(0, bitmap.width - 1)
            val y = py.coerceIn(0, bitmap.height - 1)
            val pixel = bitmap.getPixel(x, y)
            Color.red(pixel) < 75 && Color.green(pixel) < 75 && Color.blue(pixel) < 75
        }
        return dark >= 2
    }

    private fun findVerifiedGreenPlus(bitmap: Bitmap, row: Rect): Tap? {
        val density = resources.displayMetrics.density
        val x0 = (bitmap.width * 0.83f).toInt().coerceIn(0, bitmap.width - 1)
        val x1 = (bitmap.width * 0.98f).toInt().coerceIn(x0, bitmap.width - 1)
        val y0 = max(0, row.centerY() - (32 * density).toInt())
        val y1 = min(bitmap.height - 1, row.centerY() + (65 * density).toInt())
        if (y0 >= y1) return null

        val xs = mutableListOf<Int>()
        val ys = mutableListOf<Int>()
        for (y in y0..y1 step 3) {
            for (x in x0..x1 step 3) {
                if (isDeepGreen(bitmap.getPixel(x, y))) {
                    xs.add(x)
                    ys.add(y)
                }
            }
        }
        if (xs.size < 40) return null
        xs.sort()
        ys.sort()
        val x = xs[xs.size / 2]
        val y = ys[ys.size / 2]

        // The button in the supplied UI is a white plus on a green rounded square.
        // Both horizontal and vertical arms must exist at the computed center.
        val arm = max(6, (9 * density).toInt())
        // The median of green pixels is not necessarily the exact center of the
        // white plus. Probe a few neighboring scanlines to tolerate JPEG scaling,
        // different DPIs, and the rounded corners of the button.
        val shift = max(2, (3 * density).toInt())
        val whiteHorizontal = (-shift..shift).maxOf { yShift ->
            (-arm..arm step max(2, arm / 4)).count { delta ->
                val px = (x + delta).coerceIn(0, bitmap.width - 1)
                val py = (y + yShift).coerceIn(0, bitmap.height - 1)
                isNearlyWhite(bitmap.getPixel(px, py))
            }
        }
        val whiteVertical = (-shift..shift).maxOf { xShift ->
            (-arm..arm step max(2, arm / 4)).count { delta ->
                val px = (x + xShift).coerceIn(0, bitmap.width - 1)
                val py = (y + delta).coerceIn(0, bitmap.height - 1)
                isNearlyWhite(bitmap.getPixel(px, py))
            }
        }
        if (whiteHorizontal < 3 || whiteVertical < 3) return null
        return Tap(x, y)
    }

    private fun isDeepGreen(color: Int): Boolean {
        val r = Color.red(color)
        val g = Color.green(color)
        val b = Color.blue(color)
        return r < 100 && g in 75..185 && b < 160 && g > r * 1.4 && g > b * 1.15
    }

    private fun isNearlyWhite(color: Int): Boolean =
        Color.red(color) > 195 && Color.green(color) > 195 && Color.blue(color) > 185

    private fun maybeRefresh(config: SettingsStore.Config) {
        if (config.dryRun || gestureBusy || screenshotBusy || !isTargetVisible()) return
        val now = System.currentTimeMillis()
        if (now - lastRefreshMs < config.refreshSeconds * 1_000L) return
        val root = rootInActiveWindow ?: return
        val refreshNodes = root.findAccessibilityNodeInfosByText("Sayfayı Yenile")
        val match = refreshNodes.firstOrNull { it.isVisibleToUser && it.text?.toString()?.contains("Sayfayı Yenile", true) == true }
            ?: return
        val rect = Rect()
        match.getBoundsInScreen(rect)
        if (rect.width() <= 0 || rect.height() <= 0) return
        lastRefreshMs = now
        gestureBusy = true
        tap(rect.centerX(), rect.centerY()) { ok ->
            gestureBusy = false
            if (!ok) note("refresh-fail", "Sayfayı Yenile tıklaması başarısız.", 60_000L)
            handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_250L)
        }
    }

    private fun tap(x: Int, y: Int, callback: (Boolean) -> Unit) {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 85L))
            .build()
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                callback(true)
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                callback(false)
            }
        }, handler)
        if (!accepted) callback(false)
    }

    private fun note(key: String, message: String, throttleMs: Long) {
        val now = System.currentTimeMillis()
        if (now - (lastMessages[key] ?: 0L) < throttleMs) return
        lastMessages[key] = now
        EventLog.write(this, message)
    }

    companion object {
        private const val TARGET_PACKAGE = "com.orangemobile"
    }
}
