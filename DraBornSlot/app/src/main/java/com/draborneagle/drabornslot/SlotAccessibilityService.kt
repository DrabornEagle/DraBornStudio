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
 * v0.4: selected-row protection, explicit removals and fast on-screen refresh.
 * No private API, cookies, login automation, CAPTCHA/2FA bypass or hidden requests.
 * A red X is only UI-level evidence; not an independently verified booking.
 */
class SlotAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val tickPeriod = 1_000L
    private var lastScreenshot = 0L
    private var refreshSeeking = false
    private var refreshSeekAttempts = 0
    private var lastErrorSignature = ""
    private var lastInspect = 0L
    private var lastRefresh = 0L
    private var lastScroll = 0L
    private var screenshotBusy = false
    private var gestureBusy = false
    private var stopped = false
    private var verifiedDate: String? = null
    private var verifiedAt = 0L
    private var lastSeenSignature = ""
    private var scrollAttempts = 0
    private val lastMessages = mutableMapOf<String, Long>()
    private val lastAttempt = mutableMapOf<String, Long>()
    private val stableGreen = mutableMapOf<String, Int>()
    private var lastSlotMutation = 0L

    private data class FoundRow(val slot: String, val bounds: Rect)
    private data class Tap(val x: Int, val y: Int)
    private val eventInspect = Runnable { safeInspect(SettingsStore.read(this)) }
    private val tick = object : Runnable {
        override fun run() {
            if (stopped) return
            try {
                val config = SettingsStore.read(this@SlotAccessibilityService)
                if (System.currentTimeMillis() - SettingsStore.lastHeartbeat(this@SlotAccessibilityService) > 2_800L)
                    SettingsStore.heartbeat(this@SlotAccessibilityService)
                if (!targetVisible()) { verifiedDate = null; refreshSeeking = false }
                if (config.active) {
                    safeInspect(config)
                }
            } catch (error: Throwable) {
                logError("Periyodik kontrol", error)
            } finally {
                if (!stopped) handler.postDelayed(this, tickPeriod)
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        stopped = false
        SettingsStore.heartbeat(this)
        EventLog.write(this, "DraBornSlot v0.4 erişilebilirlik servisi bağlandı.")
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName?.toString() != TARGET_PACKAGE) return
        if (!SettingsStore.read(this).active) return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            handler.removeCallbacks(eventInspect)
            handler.postDelayed(eventInspect, 300L)
        }
    }

    private fun safeInspect(config: SettingsStore.Config) {
        try { inspect(config) } catch (error: Throwable) { logError("Ekran taraması", error) }
    }

    private fun logError(source: String, error: Throwable) {
        val signature = "${source}: ${error.javaClass.simpleName}: ${error.message?.take(100)}"
        if (signature != lastErrorSignature) {
            lastErrorSignature = signature
            EventLog.write(this, "HATA: $signature")
        }
    }

    override fun onInterrupt() { note("interrupt", "Erişilebilirlik servisi kesintiye uğradı.", 30_000) }
    override fun onDestroy() {
        stopped = true
        SettingsStore.heartbeat(this, 0L)
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun targetVisible(): Boolean = rootInActiveWindow?.packageName?.toString() == TARGET_PACKAGE

    private fun inspect(config: SettingsStore.Config) {
        if (!config.active || gestureBusy || screenshotBusy || !targetVisible()) return
        val now = System.currentTimeMillis()
        if (now - lastInspect < 900L) return
        lastInspect = now
        val chosenDate = runCatching { LocalDate.parse(config.date) }.getOrNull() ?: return
        if (ChronoUnit.DAYS.between(LocalDate.now(), chosenDate) !in 0..6) {
            note("date-invalid", "Hedef tarih görünür 7 günün dışında; ajan durdu.", 300_000)
            return
        }
        if (config.slots.isEmpty() && SettingsStore.pendingRemovals(this, config.date).isEmpty()) return
        if (verifiedDate != config.date) {
            verifiedDate = null
            scrollAttempts = 0
            lastSeenSignature = ""
        }

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
        val requested = (config.slots + SettingsStore.pendingRemovals(this, config.date)).toSet()
        val targetRows = allRows.filter { it.slot in requested }
        if (dateBounds.isEmpty() && verifiedDate != config.date) {
            note("screen-missing", "Hedef gün doğrulanamadı. Trendyol GO'da seçtiğin tarihi en üstten göster.", 30_000)
            return
        }
        if (dateBounds.isEmpty() && allRows.isEmpty()) {
            note("rows-missing", "Saat listesi görünmüyor; işlem yapılmadı.", 90_000)
            return
        }
        if (allRows.isEmpty() && dateBounds.isEmpty()) return

        if (now - lastScreenshot < 950L) return
        lastScreenshot = now
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
                        val fresh = SettingsStore.read(this@SlotAccessibilityService)
                        if (!fresh.active || !targetVisible() || fresh.date != config.date || fresh.slots != config.slots || fresh.dryRun != config.dryRun) return
                        evaluate(bitmap, dateBounds, allRows, targetRows, fresh)
                    } catch (error: Throwable) {
                        logError("Görüntü analizi", error)
                    } finally {
                        bitmap.recycle()
                        // Evaluate first; calling refresh right after safeInspect in the
                        // tick never worked reliably because screenshotBusy was true.
                        if (!gestureBusy) maybeRefresh(SettingsStore.read(this@SlotAccessibilityService))
                    }
                }
                override fun onFailure(errorCode: Int) {
                    screenshotBusy = false
                    if (errorCode == AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT) return
                    note("screenshot-$errorCode", "Ekran okuma hatası $errorCode; dokunulmadı.", 30_000)
                }
            })
        } catch (error: Throwable) {
            screenshotBusy = false
            logError("Ekran görüntüsü", error)
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
                        handler.postDelayed({ safeInspect(SettingsStore.read(this)) }, 1_100L)
                    }
                } else note("date-test", "İZLEME: ${config.date} günü henüz seçili görünmüyor.", 120_000)
                return
            }
            verifiedDate = config.date
            verifiedAt = now
        } else if (verifiedDate != config.date) return

        val date = config.date
        val removalRequests = SettingsStore.pendingRemovals(this, date)
            .filterNot { it in config.slots }

        // CRITICAL: selected X takes precedence, regardless of neighboring green pixels.
        // Never press a red X on a desired slot.
        for (row in targets) {
            val red = findRedRemoveButton(bitmap, row.bounds)
            if (row.slot in config.slots && red != null) {
                stableGreen.remove("$date|${row.slot}")
                if (!SettingsStore.isUiConfirmed(this, date, row.slot)) {
                    SettingsStore.markUiConfirmed(this, date, row.slot)
                    EventLog.write(this, "ARAYÜZDE SEÇİLDİ: ${row.slot} (kırmızı X görüldü; kesin rezervasyon onayı değildir).")
                }
            } else if (row.slot in removalRequests && red == null &&
                findGreenPlus(bitmap, row.bounds) != null) {
                SettingsStore.completeRemoval(this, date, row.slot)
                EventLog.write(this, "KALDIRMA GÖRÜLDÜ: ${row.slot} yeşil + durumunda. İstek tamamlandı.")
            }
        }

        // Only a user's saved, same-day deselection is allowed to press X.
        for (slot in removalRequests) {
            val row = targets.firstOrNull { it.slot == slot } ?: continue
            val red = findRedRemoveButton(bitmap, row.bounds) ?: continue
            val key = "remove-$date|$slot"
            if (now - (lastAttempt[key] ?: 0L) < 7_000L) continue
            if (config.dryRun) {
                note("remove-preview-$key", "İZLEME: $slot kaldırma isteği var; kırmızı X algılandı.", 35_000L)
                continue
            }
            if (!targetVisible()) return
            lastAttempt[key] = now
            lastSlotMutation = now
            gestureBusy = true
            tap(red.x, red.y) { ok ->
                gestureBusy = false
                if (ok) {
                    EventLog.write(this, "KALDIRMA DOKUNUŞU: $slot kırmızı X butonuna dokunuldu; sonuç kontrol edilecek.")
                } else {
                    EventLog.write(this, "HATA: $slot kaldırma dokunuşu başarısız.")
                }
                handler.postDelayed({ safeInspect(SettingsStore.read(this)) }, 1_200L)
            }
            return
        }

        for (slot in config.slots) {
            val row = targets.firstOrNull { it.slot == slot } ?: continue
            val key = "$date|$slot"
            // A red X is a selected state, never a button to tap for this slot.
            if (findRedRemoveButton(bitmap, row.bounds) != null) {
                stableGreen.remove(key)
                continue
            }
            val plus = findGreenPlus(bitmap, row.bounds) ?: continue
            if (SettingsStore.isUiConfirmed(this, date, slot)) {
                val seen = (stableGreen[key] ?: 0) + 1
                stableGreen[key] = seen
                if (seen < 2) continue
                SettingsStore.unmarkUiConfirmed(this, date, slot)
                EventLog.write(this, "BİLGİ: $slot art arda iki taramada yeşil + durumunda; yeniden seçim mümkün.")
            }
            val attemptKey = "select-$key"
            if (now - (lastAttempt[attemptKey] ?: 0L) < 8_000L) continue
            if (config.dryRun) {
                note("test-$key", "İZLEME: $slot yeşil + hazır (${plus.x},${plus.y}).", 90_000L)
                continue
            }
            if (!targetVisible()) return
            gestureBusy = true
            lastAttempt[attemptKey] = now
            lastSlotMutation = now
            tap(plus.x, plus.y) { ok ->
                gestureBusy = false
                if (ok) {
                    SettingsStore.addAttempt(this, date, slot)
                    EventLog.write(this, "DOKUNMA: $slot yeşil + butonuna dokunuldu; kırmızı X kontrol edilecek.")
                } else EventLog.write(this, "HATA: $slot seçim dokunuşu başarısız oldu.")
                handler.postDelayed({ safeInspect(SettingsStore.read(this)) }, 1_200L)
            }
            return
        }

        val pending = (config.slots.filter { !SettingsStore.isUiConfirmed(this, config.date, it) } + SettingsStore.pendingRemovals(this, config.date)).distinct()
        if (pending.isEmpty() || config.dryRun || refreshSeeking) return
        val visibleSlots = allRows.map { it.slot }.distinct()
        if (visibleSlots.isEmpty()) return
        val invisiblePending = pending.filter { it !in visibleSlots }
        if (invisiblePending.isEmpty()) return
        if (now - lastScroll < 2_500 || scrollAttempts >= 24) return
        val wanted = invisiblePending.minOf { slotMinute(it) }
        val earliest = visibleSlots.minOf { slotMinute(it) }
        val latest = visibleSlots.maxOf { slotMinute(it) }
        val forward = if (wanted < earliest) false else wanted > latest || wanted >= earliest
        val signature = visibleSlots.joinToString("|")
        if (signature == lastSeenSignature && scrollAttempts > 2) {
            scrollAttempts = 24
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
            handler.postDelayed({ safeInspect(SettingsStore.read(this)) }, 1_100L)
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
            rect.centerX() to rect.top - m / 2,
            rect.centerX() to rect.bottom + m / 2
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
        // Restrict green detection to the SAME row. Previous v0.2 search area
        // overlapped the next row's + and could lead to a wrong/missed tap.
        val halfHeight = max(22, (30 * d).toInt())
        val top = max(0, row.centerY() - halfHeight)
        val bottom = min(bitmap.height - 1, row.centerY() + halfHeight)
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

    private fun findRedRemoveButton(bitmap: Bitmap, row: Rect): Tap? {
        val d = resources.displayMetrics.density
        val left = (bitmap.width * 0.83f).toInt().coerceIn(0, bitmap.width - 1)
        val right = (bitmap.width * 0.98f).toInt().coerceIn(left, bitmap.width - 1)
        val halfHeight = max(22, (30 * d).toInt())
        val top = max(0, row.centerY() - halfHeight)
        val bottom = min(bitmap.height - 1, row.centerY() + halfHeight)
        if (top >= bottom) return null
        val xs = mutableListOf<Int>()
        val ys = mutableListOf<Int>()
        for (y in top..bottom step 2) for (x in left..right step 2) {
            val p = bitmap.getPixel(x, y)
            if (Color.red(p) > 175 && Color.green(p) < 115 && Color.blue(p) < 150) {
                xs.add(x); ys.add(y)
            }
        }
        if (xs.size < 28) return null
        xs.sort(); ys.sort()
        val x = xs[xs.size / 2]
        val y = ys[ys.size / 2]
        if (kotlin.math.abs(y - row.centerY()) > max(20, (27 * d).toInt())) return null
        return Tap(x, y)
    }

    private fun green(p: Int) = Color.red(p) < 100 && Color.green(p) in 75..185 && Color.blue(p) < 160 && Color.green(p) > Color.red(p) * 1.4 && Color.green(p) > Color.blue(p) * 1.15
    private fun white(p: Int) = Color.red(p) > 195 && Color.green(p) > 195 && Color.blue(p) > 185

    private fun maybeRefresh(config: SettingsStore.Config) {
        if (config.dryRun || gestureBusy || screenshotBusy || !targetVisible()) return
        val now = System.currentTimeMillis()
        if (verifiedDate != config.date) return
        if (now - lastSlotMutation < 2_500L || now - lastScroll < 1_500L) return
        if (now - lastRefresh < config.refreshSeconds.coerceIn(1, 60) * 1_000L) return
        val root = rootInActiveWindow ?: return
        val item = root.findAccessibilityNodeInfosByText("Sayfayı Yenile")
            .firstOrNull { it.isVisibleToUser && it.text?.toString()?.contains("Sayfayı Yenile", true) == true }
        // Do not force scroll to top on every refresh: it hides lower target rows.
        if (item == null) {
            note("refresh-hidden", "Yenileme düğmesi görünmüyor; saniyelik ekran kontrolü sürüyor.", 90_000L)
            return
        }
        val bounds = Rect()
        item.getBoundsInScreen(bounds)
        if (bounds.width() < 1 || bounds.height() < 1) return
        lastRefresh = now
        gestureBusy = true
        tap(bounds.centerX(), bounds.centerY()) { ok ->
            gestureBusy = false
            if (!ok) note("refresh-fail", "HATA: Sayfa yenileme dokunuşu başarısız.", 30_000L)
            else note("refresh-done", "YENİLEME: Trendyol GO sayfası yenilendi.", 45_000L)
            handler.postDelayed({ safeInspect(SettingsStore.read(this)) }, 350L)
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
