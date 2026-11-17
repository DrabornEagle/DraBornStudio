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
 * v0.2: user-opt-in tap automation; only the foreground Trendyol GO UI is touched.
 * No private API, cookies, login automation, CAPTCHA/2FA bypass or hidden requests.
 * A red X is only UI-level evidence; not an independently verified booking.
 */
class SlotAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val tickPeriod = 2_500L
    private var lastInspect = 0L
    private var lastRefresh = 0L
    private var lastScroll = 0L
    private var lastTimeRowsSeenAt = 0L
    private var screenshotBusy = false
    private var gestureBusy = false
    private var stopped = false
    private var verifiedDate: String? = null
    private var verifiedAt = 0L
    private var lastSeenSignature = ""
    private var scrollAttempts = 0
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
            handler.postDelayed(this, tickPeriod)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        stopped = false
        EventLog.write(this, "DraBornSlot v0.2 erişilebilirlik servisi bağlandı.")
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName?.toString() != TARGET_PACKAGE) return
        if (!SettingsStore.read(this).active) return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            handler.removeCallbacks(eventInspect)
            handler.postDelayed(eventInspect, 950L)
        }
    }

    override fun onInterrupt() { note("interrupt", "Erişilebilirlik servisi kesintiye uğradı.", 30_000) }
    override fun onDestroy() {
        stopped = true
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun targetVisible(): Boolean = rootInActiveWindow?.packageName?.toString() == TARGET_PACKAGE

    private fun inspect(config: SettingsStore.Config) {
        if (!config.active || gestureBusy || screenshotBusy || !targetVisible()) return
        val now = System.currentTimeMillis()
        if (now - lastInspect < 1_650) return
        lastInspect = now
        val chosenDate = runCatching { LocalDate.parse(config.date) }.getOrNull() ?: return
        if (ChronoUnit.DAYS.between(LocalDate.now(), chosenDate) !in 0..6) {
            note("date-invalid", "Hedef tarih görünür 7 günün dışında; ajan durdu.", 300_000)
            return
        }
        if (config.slots.isEmpty()) return
        if (verifiedDate != config.date) { verifiedDate = null; scrollAttempts = 0 }

        val root = rootInActiveWindow ?: return
        val texts = mutableListOf<Pair<String, Rect>>()
        collectVisibleTexts(root, texts, 0)
        val dateLabel = chosenDate.dayOfMonth.toString()
        val dateBounds = texts.filter { (value, bounds) ->
            (value.trim() == dateLabel || Regex("""^${Regex.escape(dateLabel)}\s+\S{2,5}$""").matches(value.trim())) &&
                bounds.top in 0 until (resources.displayMetrics.heightPixels * 0.24f).toInt() && bounds.width() > 0
        }.map { it.second }
        val allRows = texts.mapNotNull { (value, bounds) ->
            val slot = SettingsStore.normalizeSlot(value) ?: return@mapNotNull null
            if (bounds.width() < 1 || bounds.height() < 1) null else FoundRow(slot, bounds)
        }.distinctBy { it.slot }
        val targetRows = allRows.filter { it.slot in config.slots }
        if (allRows.isNotEmpty()) lastTimeRowsSeenAt = now
        if (dateBounds.isEmpty() && !(verifiedDate == config.date && now - verifiedAt < 180_000L)) {
            if (!config.dryRun && allRows.isNotEmpty() && now - lastScroll > 3_000L) {
                lastScroll = now
                gestureBusy = true
                swipe(false) { gestureBusy = false; handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_250L) }
            } else note("screen-missing", "Tarih doğrulanamadı; saat ekranını ve oturumu kontrol et.", 90_000)
            return
        }
        if (dateBounds.isEmpty() && allRows.isEmpty()) {
            note("rows-missing", "Saat listesi görünmüyor; işlem yapılmadı.", 90_000)
            return
        }
        if (allRows.isEmpty() && dateBounds.isEmpty()) return

        screenshotBusy = true
        try {
            takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    screenshotBusy = false
                    val bitmap = try {
                        val buffer = screenshot.hardwareBuffer
                        try {
                            val cs = screenshot.colorSpace ?: ColorSpace.get(ColorSpace.Named.SRGB)
                            Bitmap.wrapHardwareBuffer(buffer, cs)?.copy(Bitmap.Config.ARGB_8888, false)
                        } finally { buffer.close() }
                    } catch (_: Exception) { null }
                    if (bitmap == null) {
                        note("bitmap", "Ekran fotoğrafı alınamadı; güvenlik için dokunulmadı.", 90_000)
                        return
                    }
                    try {
                        if (!config.active || !targetVisible()) return
                        evaluate(bitmap, dateBounds, allRows, targetRows, config)
                    } finally { bitmap.recycle() }
                }
                override fun onFailure(errorCode: Int) {
                    screenshotBusy = false
                    note("screenshot", "Ekran okuma hatası $errorCode; dokunulmadı.", 90_000)
                }
            })
        } catch (_: Exception) {
            screenshotBusy = false
            note("screenshot-exception", "Ekran okumasına Android izin vermedi.", 90_000)
        }
    }

    private fun evaluate(
        bitmap: Bitmap,
        dateBounds: List<Rect>,
        allRows: List<FoundRow>,
        targets: List<FoundRow>,
        config: SettingsStore.Config
    ) {
        val now = System.currentTimeMillis()
        if (dateBounds.isNotEmpty()) {
            val selected = dateBounds.any { isSelectedDate(bitmap, it) }
            if (!selected) {
                verifiedDate = null
                if (!config.dryRun) {
                    val first = dateBounds.first()
                    gestureBusy = true
                    tap(first.centerX(), first.centerY()) { ok ->
                        gestureBusy = false
                        if (ok) note("date-click", "Hedef gün ${config.date} seçildi; yeniden kontrol ediliyor.", 35_000)
                        handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_100)
                    }
                } else note("date-test", "İZLEME: ${config.date} günü henüz seçili görünmüyor.", 120_000)
                return
            }
            verifiedDate = config.date
            verifiedAt = now
        } else if (verifiedDate != config.date || now - verifiedAt > 180_000) return

        // If the UI has a red remove-X, mark the row UI-confirmed even if another device selected it.
        for (row in targets) {
            if (findRedRemoveButton(bitmap, row.bounds)) {
                if (!SettingsStore.isUiConfirmed(this, config.date, row.slot)) {
                    SettingsStore.markUiConfirmed(this, config.date, row.slot)
                    EventLog.write(this, "ARAYÜZDE SEÇİLDİ: ${row.slot} (kırmızı X görüldü; kesin rezervasyon onayı değildir).")
                }
            }
        }
        for (slot in config.slots) {
            val row = targets.firstOrNull { it.slot == slot } ?: continue
            if (SettingsStore.isUiConfirmed(this, config.date, slot)) continue
            if (SettingsStore.attemptCount(this, config.date, slot) >= 2) continue
            val key = "${config.date}|$slot"
            if (now - (lastAttempt[key] ?: 0L) < 45_000) continue
            val plus = findGreenPlus(bitmap, row.bounds) ?: continue
            if (config.dryRun) {
                note("test-$key", "İZLEME: $slot yeşil + hazır (${plus.x},${plus.y}).", 90_000)
                continue
            }
            if (!targetVisible()) return
            gestureBusy = true
            lastAttempt[key] = now
            tap(plus.x, plus.y) { ok ->
                gestureBusy = false
                if (ok) {
                    SettingsStore.addAttempt(this, config.date, slot)
                    EventLog.write(this, "CANLI: $slot + butonuna dokunuldu; seçim göstergesi kontrol edilecek.")
                } else EventLog.write(this, "CANLI: $slot dokunuşu başarısız oldu.")
                handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_500)
            }
            return
        }

        val pending = config.slots.filter { !SettingsStore.isUiConfirmed(this, config.date, it) && SettingsStore.attemptCount(this, config.date, it) < 2 }
        if (pending.isEmpty() || config.dryRun) return
        val visibleSlots = allRows.map { it.slot }.distinct()
        if (visibleSlots.isEmpty()) return
        val invisiblePending = pending.filter { it !in visibleSlots }
        if (invisiblePending.isEmpty()) return
        if (now - lastScroll < 2_900 || scrollAttempts >= 20) return
        val wanted = invisiblePending.minOf { slotMinute(it) }
        val earliest = visibleSlots.minOf { slotMinute(it) }
        val latest = visibleSlots.maxOf { slotMinute(it) }
        val forward = if (wanted < earliest) false else wanted > latest || wanted >= earliest
        val signature = visibleSlots.joinToString("|")
        if (signature == lastSeenSignature && scrollAttempts > 2) {
            scrollAttempts = 20
            note("scroll-limit", "Saat listesinin sonuna gelindi; eksik saat için manuel kaydırma gerekebilir.", 120_000)
            return
        }
        lastSeenSignature = signature
        scrollAttempts += 1
        lastScroll = now
        gestureBusy = true
        swipe(forward) { ok ->
            gestureBusy = false
            if (ok) note("scroll", "Hedef saat ekran dışında; liste ${if (forward) "aşağı" else "yukarı"} kaydırıldı.", 40_000)
            handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_200)
        }
    }

    private fun slotMinute(slot: String): Int {
        val start = slot.substringBefore('-')
        val hour = start.substringBefore(':').toIntOrNull() ?: return 0
        val minute = start.substringAfter(':').toIntOrNull() ?: 0
        return (if (hour == 0) 24 else hour) * 60 + minute
    }

    private fun collectVisibleTexts(node: AccessibilityNodeInfo, out: MutableList<Pair<String, Rect>>, depth: Int) {
        if (depth > 35 || out.size > 1_500) return
        val t = node.text?.toString()?.trim().orEmpty()
        if (node.isVisibleToUser && t.isNotEmpty()) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            out.add(t to rect)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectVisibleTexts(child, out, depth + 1)
        }
    }

    private fun isSelectedDate(bitmap: Bitmap, rect: Rect): Boolean {
        val m = max(6, (8 * resources.displayMetrics.density).toInt())
        val samples = listOf(
            rect.left - m to rect.centerY(), rect.right + m to rect.centerY(),
            rect.left + 6 to rect.top + 4, rect.right - 6 to rect.top + 4
        )
        return samples.count { (x0, y0) ->
            val x = x0.coerceIn(0, bitmap.width - 1)
            val y = y0.coerceIn(0, bitmap.height - 1)
            val p = bitmap.getPixel(x, y)
            Color.red(p) < 75 && Color.green(p) < 75 && Color.blue(p) < 75
        } >= 2
    }

    private fun findGreenPlus(bitmap: Bitmap, row: Rect): Tap? {
        val d = resources.displayMetrics.density
        val left = (bitmap.width * 0.83f).toInt().coerceIn(0, bitmap.width - 1)
        val right = (bitmap.width * 0.98f).toInt().coerceIn(left, bitmap.width - 1)
        val top = max(0, row.centerY() - (32 * d).toInt())
        val bottom = min(bitmap.height - 1, row.centerY() + (65 * d).toInt())
        if (top >= bottom) return null
        val xs = mutableListOf<Int>()
        val ys = mutableListOf<Int>()
        for (y in top..bottom step 3) for (x in left..right step 3) {
            if (green(bitmap.getPixel(x, y))) { xs.add(x); ys.add(y) }
        }
        if (xs.size < 40) return null
        xs.sort(); ys.sort()
        val x = xs[xs.size / 2]
        val y = ys[ys.size / 2]
        val arm = max(6, (9 * d).toInt())
        val shift = max(2, (3 * d).toInt())
        val horiz = (-shift..shift).maxOf { dy ->
            (-arm..arm step max(2, arm / 4)).count { dx ->
                white(bitmap.getPixel((x + dx).coerceIn(0, bitmap.width - 1), (y + dy).coerceIn(0, bitmap.height - 1)))
            }
        }
        val vert = (-shift..shift).maxOf { dx ->
            (-arm..arm step max(2, arm / 4)).count { dy ->
                white(bitmap.getPixel((x + dx).coerceIn(0, bitmap.width - 1), (y + dy).coerceIn(0, bitmap.height - 1)))
            }
        }
        return if (horiz >= 3 && vert >= 3) Tap(x, y) else null
    }

    private fun findRedRemoveButton(bitmap: Bitmap, row: Rect): Boolean {
        val d = resources.displayMetrics.density
        val left = (bitmap.width * 0.83f).toInt().coerceIn(0, bitmap.width - 1)
        val right = (bitmap.width * 0.98f).toInt().coerceIn(left, bitmap.width - 1)
        val top = max(0, row.centerY() - (30 * d).toInt())
        val bottom = min(bitmap.height - 1, row.centerY() + (65 * d).toInt())
        if (top >= bottom) return false
        var redPixels = 0
        for (y in top..bottom step 3) for (x in left..right step 3) {
            val p = bitmap.getPixel(x, y)
            if (Color.red(p) > 180 && Color.green(p) < 105 && Color.blue(p) < 145) redPixels++
        }
        return redPixels >= 35
    }

    private fun green(p: Int) = Color.red(p) < 100 && Color.green(p) in 75..185 && Color.blue(p) < 160 && Color.green(p) > Color.red(p) * 1.4 && Color.green(p) > Color.blue(p) * 1.15
    private fun white(p: Int) = Color.red(p) > 195 && Color.green(p) > 195 && Color.blue(p) > 185

    private fun maybeRefresh(config: SettingsStore.Config) {
        if (config.dryRun || gestureBusy || screenshotBusy || !targetVisible()) return
        val now = System.currentTimeMillis()
        if (now - lastRefresh < config.refreshSeconds * 1_000L) return
        val root = rootInActiveWindow ?: return
        val item = root.findAccessibilityNodeInfosByText("Sayfayı Yenile")
            .firstOrNull { it.isVisibleToUser && it.text?.toString()?.contains("Sayfayı Yenile", true) == true }
        if (item == null) {
            // In a long list the refresh button may be off-screen; safely return to the header.
            if (verifiedDate == config.date && now - lastTimeRowsSeenAt < 15_000L &&
                now - lastScroll > 3_000L && scrollAttempts > 0) {
                lastScroll = now
                gestureBusy = true
                swipe(false) { _ ->
                    gestureBusy = false
                    handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_150L)
                }
            }
            return
        }
        val bounds = Rect()
        item.getBoundsInScreen(bounds)
        if (bounds.width() < 1 || bounds.height() < 1) return
        lastRefresh = now
        scrollAttempts = 0
        lastSeenSignature = ""
        gestureBusy = true
        tap(bounds.centerX(), bounds.centerY()) { ok ->
            gestureBusy = false
            if (!ok) note("refresh-fail", "Yenileme butonuna dokunulamadı.", 90_000)
            handler.postDelayed({ inspect(SettingsStore.read(this)) }, 1_200)
        }
    }

    private fun tap(x: Int, y: Int, callback: (Boolean) -> Unit) {
        val p = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        sendGesture(p, 100L, callback)
    }

    private fun swipe(forward: Boolean, callback: (Boolean) -> Unit) {
        val w = resources.displayMetrics.widthPixels
        val h = resources.displayMetrics.heightPixels
        val x = (w * 0.5f)
        val y0 = if (forward) h * 0.78f else h * 0.28f
        val y1 = if (forward) h * 0.28f else h * 0.78f
        val p = Path().apply { moveTo(x, y0); lineTo(x, y1) }
        sendGesture(p, 460L, callback)
    }

    private fun sendGesture(path: Path, duration: Long, callback: (Boolean) -> Unit) {
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0L, duration)).build()
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) { callback(true) }
            override fun onCancelled(gestureDescription: GestureDescription?) { callback(false) }
        }, handler)
        if (!accepted) callback(false)
    }

    private fun note(key: String, message: String, cooldown: Long) {
        val now = System.currentTimeMillis()
        if (now - (lastMessages[key] ?: 0L) < cooldown) return
        lastMessages[key] = now
        EventLog.write(this, message)
    }

    companion object { private const val TARGET_PACKAGE = "com.orangemobile" }
}
