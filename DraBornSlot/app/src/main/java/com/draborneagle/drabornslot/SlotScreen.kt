package com.draborneagle.drabornslot

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Point
import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

internal class SlotScreen(
    root: AccessibilityNodeInfo,
    day: Int,
    private val density: Float
) : AutoCloseable {
    data class Element(val node: AccessibilityNodeInfo, val bounds: Rect, val caption: String)
    data class Row(val slot: String, val bounds: Rect)
    enum class ButtonType { ADD, REMOVE }
    data class Button(val type: ButtonType, val point: Point, val element: Element? = null)
    data class Probe(val day: Rect?, val rows: Map<String, Rect>, val navigationArea: Rect?)
    data class ImageResult(val selectedDay: Boolean, val buttons: Map<String, Button>, val hoursNavigation: Point?)
    enum class HoursTab { ALL, OTHER }

    val windowId: Int = root.windowId
    val bounds = Rect().also(root::getBoundsInScreen)
    private val visitedNodes = mutableListOf<AccessibilityNodeInfo>()
    private val elements = mutableListOf<Element>()
    private val scrollables = mutableListOf<Element>()

    val rows: List<Row>
    val targetDay: Element?
    val selectedDay: Int?
    val refresh: Element?
    val allHoursTab: Element?
    val otherHoursTab: Element?
    val selectedHoursTab: HoursTab?
    val hoursNavigation: Element?
    val loading: Boolean
    val temporarilyUnavailable: Boolean
    val list: Element?
    val layoutKey: String
    val isSchedule: Boolean
        get() = rows.isNotEmpty() || (targetDay != null && refresh != null) || allHoursTab != null || otherHoursTab != null

    init {
        collect(root, 0)
        rows = elements.mapNotNull { element ->
            SettingsStore.normalizeSlot(element.caption)?.let { Row(it, element.bounds) }
        }.sortedBy { it.bounds.width() }.distinctBy(Row::slot).sortedBy { it.bounds.centerY() }
        val days = elements.mapNotNull { element ->
            if (element.bounds.top > bounds.top + bounds.height() * 0.28f) return@mapNotNull null
            val number = dayLabel(element.caption) ?: return@mapNotNull null
            number to element
        }
        targetDay = days.firstOrNull { it.first == day }?.second
        selectedDay = days.firstOrNull { (_, el) -> isSelected(el.node) }?.first
        refresh = elements.firstOrNull { it.caption.lowercase(TURKISH) in REFRESH_LABELS }
        val visibleTabs = elements.mapNotNull { element ->
            if (element.bounds.centerY() > bounds.top + bounds.height() / 2) return@mapNotNull null
            hoursTab(element.caption)?.let { it to element }
        }
        allHoursTab = visibleTabs.firstOrNull { (kind, _) -> kind == HoursTab.ALL }?.second
        otherHoursTab = visibleTabs.firstOrNull { (kind, _) -> kind == HoursTab.OTHER }?.second
        selectedHoursTab = visibleTabs.filter { (_, element) -> isSelected(element.node) }
            .map { (kind, _) -> kind }.distinct().singleOrNull()
        hoursNavigation = elements.firstOrNull { element ->
            element.node.isEnabled && element.bounds.centerY() >= bounds.top + bounds.height() * 0.84f &&
                compactLabel(element.caption) in HOURS_NAVIGATION_LABELS
        }
        loading = elements.any { it.caption.lowercase(TURKISH) in LOADING_LABELS }
        temporarilyUnavailable = elements.any {
            val caption = it.caption.lowercase(TURKISH)
            caption.contains("çok fazla istek") || caption.contains("servis yanıt vermiyor")
        }
        list = scrollables.maxByOrNull { candidate ->
            rows.count { candidate.bounds.contains(it.bounds.centerX(), it.bounds.centerY()) } *
                bounds.height() + candidate.bounds.height()
        }?.takeIf { candidate -> rows.any { candidate.bounds.contains(it.bounds.centerX(), it.bounds.centerY()) } }
        layoutKey = rows.joinToString("|") { "${it.slot}@${it.bounds.centerY()}" } +
            "#${targetDay?.bounds}#${refresh?.bounds}#${allHoursTab?.bounds}#${hoursNavigation?.bounds}"
    }

    private fun collect(node: AccessibilityNodeInfo, depth: Int) {
        visitedNodes.add(node)
        if (depth >= 32 || visitedNodes.size >= 850 || !node.isVisibleToUser) return

        val rect = Rect().also(node::getBoundsInScreen)
        if (!rect.isEmpty && rect.intersect(bounds)) {
            val rawText = node.text?.toString()?.trim().orEmpty()
            val description = node.contentDescription?.toString()?.trim().orEmpty()
            if (rawText.isNotEmpty()) elements.add(Element(node, rect, rawText))
            if (description.isNotEmpty() && description != rawText) elements.add(Element(node, rect, description))
            if (node.isScrollable && rect.height() >= bounds.height() / 4) {
                scrollables.add(Element(node, rect, ""))
            }
        }

        for (index in 0 until node.childCount) {
            if (visitedNodes.size >= 850) break
            node.getChild(index)?.let { collect(it, depth + 1) }
        }
    }

    fun buttonFor(row: Row): Button? {
        val band = rowBand(row)
        val candidates = elements.asSequence()
            .filter { element ->
                element.node.isEnabled && element.node.isClickable &&
                    band.contains(element.bounds.centerX(), element.bounds.centerY())
            }
            .mapNotNull { element ->
                val label = element.caption.lowercase(TURKISH)
                val type = when (label) {
                    in ADD_LABELS -> ButtonType.ADD
                    in REMOVE_LABELS -> ButtonType.REMOVE
                    else -> return@mapNotNull null
                }
                Button(type, Point(element.bounds.centerX(), element.bounds.centerY()), element)
            }
        return candidates.minByOrNull { abs(it.point.y - row.bounds.centerY()) }
    }

    fun probe(checkDay: Boolean, slots: Set<String>, checkHoursNavigation: Boolean) = Probe(
        day = if (checkDay) targetDay?.let { Rect(it.bounds) } else null,
        rows = rows.filter { it.slot in slots }.associate { it.slot to rowBand(it) },
        navigationArea = if (checkHoursNavigation) Rect(bounds) else null
    )

    private fun rowBand(row: Row): Rect {
        val index = rows.indexOf(row)
        val center = row.bounds.centerY()
        val previousEdge = rows.getOrNull(index - 1)?.let { (it.bounds.centerY() + center) / 2 } ?: bounds.top
        val nextEdge = rows.getOrNull(index + 1)?.let { (it.bounds.centerY() + center) / 2 } ?: bounds.bottom
        return Rect(
            bounds.left + (bounds.width() * 0.80f).toInt(),
            max(previousEdge, row.bounds.top - (12 * density).toInt()),
            bounds.right - (bounds.width() * 0.015f).toInt(),
            min(nextEdge, row.bounds.bottom + (26 * density).toInt())
        )
    }

    override fun close() {
        visitedNodes.asReversed().forEach(::recycle)
    }

    companion object {
        private val TURKISH = Locale.forLanguageTag("tr-TR")
        private val DATE_LABEL = Regex("""^(0?[1-9]|[12]\d|3[01])(?:\s+[\p{L}.]{2,6})?$""")
        private val REFRESH_LABELS = setOf("sayfayı yenile", "yenile")
        private val LOADING_LABELS = setOf("yükleniyor", "yükleniyor...", "yükleniyor…", "lütfen bekleyin")
        private val HOURS_NAVIGATION_LABELS = setOf("saatler", "çalışma saatleri", "çalışma saatlerim", "slotlar", "vardiyalar")
        private val SPACE = Regex("""\s+""")
        private val ADD_LABELS = setOf("+", "ekle", "slot ekle", "saat ekle", "saati ekle", "zaman aralığı ekle")
        private val REMOVE_LABELS = setOf("×", "✕", "x", "kaldır", "slotu kaldır", "saati kaldır", "saat sil", "slot sil")

        fun dayLabel(value: String): Int? = DATE_LABEL.matchEntire(value.trim())?.groupValues?.get(1)?.toInt()

        private fun compactLabel(value: String) = value.substringBefore(',').trim().lowercase(TURKISH)
            .replace(SPACE, " ")

        fun hoursTab(value: String) = when (compactLabel(value)) {
            "tüm saatler", "tum saatler" -> HoursTab.ALL
            "alevli saatler", "diğer saatler", "diger saatler" -> HoursTab.OTHER
            else -> null
        }

        private fun isSelected(node: AccessibilityNodeInfo): Boolean {
            if (node.isSelected || node.collectionItemInfo?.isSelected == true || (node.isCheckable && node.isChecked)) return true
            val parent = node.parent ?: return false
            return try { parent.isSelected || (parent.isCheckable && parent.isChecked) } finally { recycle(parent) }
        }

        @Suppress("DEPRECATION")
        fun recycle(node: AccessibilityNodeInfo) = node.recycle()

        fun inspectImage(bitmap: Bitmap, probe: Probe, density: Float): ImageResult {
            val selected = probe.day?.let { selectedDateColor(bitmap, it, density) } == true
            val buttons = probe.rows.mapNotNull { (slot, bounds) ->
                imageButton(bitmap, bounds, density)?.let { slot to it }
            }.toMap()
            val navigation = probe.navigationArea?.let { original ->
                val area = Rect(original)
                if (!area.intersect(0, 0, bitmap.width, bitmap.height)) null else {
                    HoursNavigationIcon.find(area.left, area.top, area.width(), area.height()) { x, y ->
                        val pixel = bitmap.getPixel(x, y)
                        (Color.red(pixel) * 3 + Color.green(pixel) * 6 + Color.blue(pixel)) / 10
                    }?.let { (x, y) -> Point(x, y) }
                }
            }
            return ImageResult(selected, buttons, navigation)
        }

        private fun selectedDateColor(bitmap: Bitmap, bounds: Rect, density: Float): Boolean {
            val margin = max(6, (8 * density).toInt())
            val samples = listOf(
                Point(bounds.left - margin, bounds.centerY()),
                Point(bounds.right + margin, bounds.centerY()),
                Point(bounds.centerX(), bounds.top - margin / 2),
                Point(bounds.centerX(), bounds.bottom + margin / 2)
            )
            return samples.count { point ->
                val pixel = pixelAt(bitmap, point.x, point.y)
                Color.red(pixel) < 75 && Color.green(pixel) < 75 && Color.blue(pixel) < 75
            } >= 2
        }

        private fun imageButton(bitmap: Bitmap, original: Rect, density: Float): Button? {
            val bounds = Rect(original)
            if (!bounds.intersect(0, 0, bitmap.width, bitmap.height) || bounds.width() < 8 || bounds.height() < 8) return null
            val pixels = IntArray(bounds.width() * bounds.height())
            bitmap.getPixels(pixels, 0, bounds.width(), bounds.left, bounds.top, bounds.width(), bounds.height())
            val greenPoints = ArrayList<Point>()
            val redPoints = ArrayList<Point>()
            val step = max(1, (density * 0.9f).toInt())
            for (y in 0 until bounds.height() step step) {
                for (x in 0 until bounds.width() step step) {
                    val p = pixels[y * bounds.width() + x]
                    val r = Color.red(p)
                    val g = Color.green(p)
                    val b = Color.blue(p)
                    if (r < 115 && g in 75..240 && g > r * 1.4 && g > b * 1.14) {
                        greenPoints.add(Point(x + bounds.left, y + bounds.top))
                    } else if (r > 170 && g < 105 && b < 145 && r > g * 1.6) {
                        redPoints.add(Point(x + bounds.left, y + bounds.top))
                    }
                }
            }
            val plus = iconCenter(greenPoints, density)
            if (plus != null && hasWhiteIcon(bitmap, plus, density, diagonal = false)) {
                return Button(ButtonType.ADD, plus)
            }
            val remove = iconCenter(redPoints, density)
            if (remove != null && hasWhiteIcon(bitmap, remove, density, diagonal = true)) {
                return Button(ButtonType.REMOVE, remove)
            }
            return null
        }

        private fun iconCenter(points: List<Point>, density: Float): Point? {
            if (points.size < 28) return null
            val left = points.minOf { it.x }
            val right = points.maxOf { it.x }
            val top = points.minOf { it.y }
            val bottom = points.maxOf { it.y }
            // Ignore long colored decoration and matches clipped to a small line.
            val width = right - left
            val height = bottom - top
            if (width < 5 * density || height < 5 * density ||
                width > 65 * density || height > 65 * density) return null
            return Point((left + right) / 2, (top + bottom) / 2)
        }

        private fun hasWhiteIcon(bitmap: Bitmap, point: Point, density: Float, diagonal: Boolean): Boolean {
            val arm = max(4, (7 * density).toInt())
            val offset = max(1, (2 * density).toInt())
            val sampleStep = max(1, arm / 3)
            fun line(xDirection: Int, yDirection: Int): Boolean =
                (-offset..offset step offset).any { shift ->
                    (-arm..arm step sampleStep).count { distance ->
                        val px = pixelAt(bitmap, point.x + xDirection * distance + if (xDirection == 0) shift else 0,
                            point.y + yDirection * distance + if (xDirection != 0) shift else 0)
                        Color.red(px) > 190 && Color.green(px) > 190 && Color.blue(px) > 180
                    } >= 3
                }
            return if (diagonal) line(1, 1) && line(1, -1) else line(1, 0) && line(0, 1)
        }

        private fun pixelAt(bitmap: Bitmap, x: Int, y: Int) =
            bitmap.getPixel(x.coerceIn(0, bitmap.width - 1), y.coerceIn(0, bitmap.height - 1))
    }
}
