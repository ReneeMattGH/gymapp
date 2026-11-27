package com.gymapp.android.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class WidgetTimelineLogicTest {
    private val zone = ZoneId.of("UTC")
    private val now = LocalDate.of(2026, 11, 25).atTime(22, 30).atZone(zone).toInstant().toEpochMilli()

    @Test
    fun `refresh targets the next local midnight`() {
        val expected = LocalDate.of(2026, 11, 26)
            .atStartOfDay(zone).toInstant().toEpochMilli()
        assertEquals(expected, WidgetTimelineLogic.nextRefreshAt(now, zone))
    }

    @Test
    fun `refresh from just after midnight targets the following midnight`() {
        val justAfter = LocalDate.of(2026, 11, 26)
            .atTime(0, 0, 30).atZone(zone).toInstant().toEpochMilli()
        val expected = LocalDate.of(2026, 11, 27)
            .atStartOfDay(zone).toInstant().toEpochMilli()
        assertEquals(expected, WidgetTimelineLogic.nextRefreshAt(justAfter, zone))
    }

    @Test
    fun `freshness copy matches the iOS thresholds`() {
        assertEquals("Updated just now", WidgetTimelineLogic.freshnessLabel(now, now))
        assertEquals("Updated just now", WidgetTimelineLogic.freshnessLabel(now - 59_000, now))
        assertEquals("Updated 1 min ago", WidgetTimelineLogic.freshnessLabel(now - 60_000, now))
        assertEquals("Updated 59 min ago", WidgetTimelineLogic.freshnessLabel(now - 59 * 60_000, now))
        assertEquals("Updated 1 hr ago", WidgetTimelineLogic.freshnessLabel(now - 60 * 60_000, now))
        assertEquals("Updated 23 hr ago", WidgetTimelineLogic.freshnessLabel(now - 23 * 3_600_000, now))
        assertEquals("Updated yesterday", WidgetTimelineLogic.freshnessLabel(now - 24 * 3_600_000, now))
        assertEquals("Updated 2 days ago", WidgetTimelineLogic.freshnessLabel(now - 48 * 3_600_000, now))
    }

    @Test
    fun `staleness begins after twelve hours`() {
        assertFalse(WidgetTimelineLogic.isStale(now - 11 * 3_600_000, now))
        assertFalse(WidgetTimelineLogic.isStale(now - 12 * 3_600_000, now))
        assertTrue(WidgetTimelineLogic.isStale(now - 12 * 3_600_000 - 1, now))
    }

    @Test
    fun `refresh respects the supplied zone`() {
        val kolkata = ZoneId.of("Asia/Kolkata")
        val midnight = LocalDate.of(2026, 11, 26).atStartOfDay(kolkata).toInstant().toEpochMilli()
        assertEquals(
            LocalDate.of(2026, 11, 27).atStartOfDay(kolkata).toInstant().toEpochMilli(),
            WidgetTimelineLogic.nextRefreshAt(midnight, kolkata),
        )
    }
}
