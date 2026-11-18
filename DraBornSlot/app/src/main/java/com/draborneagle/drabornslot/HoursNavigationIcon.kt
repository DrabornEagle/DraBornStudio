package com.draborneagle.drabornslot

import kotlin.math.max
import kotlin.math.roundToInt

internal object HoursNavigationIcon {
    private val radii = doubleArrayOf(0.026, 0.023, 0.029, 0.032)
    private val rim = listOf(-1.23 to 0.0, 1.23 to 0.0, 0.0 to -1.23, 0.0 to 1.23)
    private val face = listOf(-0.55 to 0.0, 0.50 to 0.35, 0.0 to 0.57, -0.44 to -0.47, 0.47 to -0.42)
    private val hands = listOf(-0.07 to -0.46, -0.07 to -0.24, 0.10 to 0.0, 0.32 to 0.0)

    /** Trendyol GO's clock in the second position of the bottom navigation. */
    fun find(left: Int, top: Int, width: Int, height: Int, brightness: (Int, Int) -> Int): Pair<Int, Int>? {
        if (width < 180 || height < width) return null
        val right = left + width
        val bottom = top + height
        val step = max(1, width / 480)
        val firstX = left + (width * 0.282).roundToInt()
        val lastX = left + (width * 0.318).roundToInt()
        val firstY = top + (height * 0.87).roundToInt()
        val lastY = top + (height * 0.978).roundToInt()

        for (scale in radii) {
            val radius = width * scale
            for (y in firstY..lastY step step) {
                for (x in firstX..lastX step step) {
                    if (y + (radius * 1.23).roundToInt() >= bottom) continue
                    fun luminance(offset: Pair<Double, Double>): Int {
                        val px = (x + (offset.first * radius).roundToInt()).coerceIn(left, right - 1)
                        val py = (y + (offset.second * radius).roundToInt()).coerceIn(top, bottom - 1)
                        return brightness(px, py)
                    }
                    if (!face.all { luminance(it) < 175 }) continue
                    if (!rim.all { luminance(it) > 220 }) continue
                    if (hands.count { luminance(it) > 192 } >= 3) return x to y
                }
            }
        }
        return null
    }
}
