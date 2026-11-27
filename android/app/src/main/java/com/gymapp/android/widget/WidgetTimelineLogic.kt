package com.gymapp.android.widget

import java.time.Instant
import java.time.ZoneId

/**
 * Pure refresh helpers shared by the alarm scheduler, the provider and tests.
 * Widgets refresh at the next local midnight so "today" and the seven-day strip
 * roll over without polling; the app also pushes a refresh on every real write.
 */
object WidgetTimelineLogic {
    fun nextRefreshAt(now: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
        val date = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        return date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
    }

    fun freshnessLabel(generatedAt: Long, now: Long): String {
        val interval = maxOf(0L, now - generatedAt)
        if (interval < 60_000L) return "Updated just now"
        if (interval < 3_600_000L) return "Updated ${interval / 60_000L} min ago"
        if (interval < 86_400_000L) return "Updated ${interval / 3_600_000L} hr ago"
        val days = interval / 86_400_000L
        return if (days == 1L) "Updated yesterday" else "Updated $days days ago"
    }

    fun isStale(generatedAt: Long, now: Long, thresholdMillis: Long = 12 * 60 * 60 * 1000L): Boolean =
        now - generatedAt > thresholdMillis
}
