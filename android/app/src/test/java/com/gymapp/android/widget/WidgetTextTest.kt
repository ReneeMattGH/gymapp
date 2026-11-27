package com.gymapp.android.widget

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

class WidgetTextTest {
    private val zone = ZoneId.of("UTC")
    private val today = LocalDate.of(2026, 11, 25)

    private fun epoch(date: LocalDate) = date.atStartOfDay(zone).toInstant().toEpochMilli()

    private fun week(
        goal: Int,
        completed: Int,
        minutes: Int = 60,
        dayCounts: List<Int> = listOf(0, 0, 1, 0, 0, 0, 0),
    ): WidgetWeekSummary = WidgetWeekSummary(
        startEpochMillis = epoch(today.minusDays(3)),
        goal = goal,
        completed = completed,
        minutes = minutes,
        days = dayCounts.mapIndexed { index, count ->
            WidgetWeekDay(
                dateEpochMillis = epoch(today.minusDays(3).plusDays(index.toLong())),
                completedCount = count,
                minutes = count * 30,
            )
        },
    )

    @Test
    fun `week fraction and remaining copy`() {
        assertEquals("2/3", WidgetText.weekFraction(week(goal = 3, completed = 2)))
        assertEquals("1 session to go", WidgetText.remaining(week(goal = 3, completed = 2)))
        assertEquals("Weekly goal reached", WidgetText.remaining(week(goal = 3, completed = 3)))
        assertEquals("No goal", WidgetText.weekFraction(week(goal = 0, completed = 0)))
        assertEquals("No weekly goal set", WidgetText.remaining(week(goal = 0, completed = 0)))
    }

    @Test
    fun `minutes format hours and minutes`() {
        assertEquals("0 min", WidgetText.minutes(0))
        assertEquals("45 min", WidgetText.minutes(45))
        assertEquals("1 hr", WidgetText.minutes(60))
        assertEquals("1 hr 30 min", WidgetText.minutes(90))
        assertEquals("2 hr 5 min", WidgetText.minutes(125))
    }

    @Test
    fun `week accessibility label explains progress`() {
        assertEquals(
            "2 of 3 sessions this week. 1 session to go.",
            WidgetText.weekAccessibilityLabel(week(goal = 3, completed = 2)),
        )
        assertEquals(
            "No weekly goal set. 0 sessions completed.",
            WidgetText.weekAccessibilityLabel(week(goal = 0, completed = 0)),
        )
    }

    @Test
    fun `weekday labels use narrow and short forms`() {
        val date = epoch(today)
        assertEquals("W", WidgetText.narrowWeekday(date, zone, Locale.US))
        assertEquals("Wed", WidgetText.shortWeekday(date, zone, Locale.US))
        assertEquals("Wed, 25 Nov", WidgetText.dayAndMonth(date, zone, Locale.US))
    }

    @Test
    fun `chart day label reports workouts and today`() {
        val day = WidgetWeekDay(dateEpochMillis = epoch(today), completedCount = 2, minutes = 60)
        assertEquals(
            "Wed: 2 workouts, today",
            WidgetText.chartDayAccessibilityLabel(day, isToday = true, zone = zone, locale = Locale.US),
        )
        val rest = day.copy(completedCount = 0)
        assertEquals(
            "Wed: no workout",
            WidgetText.chartDayAccessibilityLabel(rest, isToday = false, zone = zone, locale = Locale.US),
        )
        val single = day.copy(completedCount = 1)
        assertEquals(
            "Wed: 1 workout, today",
            WidgetText.chartDayAccessibilityLabel(single, isToday = true, zone = zone, locale = Locale.US),
        )
    }

    @Test
    fun `streak detail copy`() {
        assertEquals("Finish a session to start your streak.", WidgetText.streakDetail(0))
        assertEquals("Consecutive training days.", WidgetText.streakDetail(3))
    }
}
