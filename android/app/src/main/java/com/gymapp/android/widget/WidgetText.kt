package com.gymapp.android.widget

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Copy helpers shared by the widget layouts and their tests. */
object WidgetText {
    fun narrowWeekday(dateEpochMillis: Long, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val date = Instant.ofEpochMilli(dateEpochMillis).atZone(zone).toLocalDate()
        return date.format(DateTimeFormatter.ofPattern("EEEEE", locale))
    }

    fun shortWeekday(dateEpochMillis: Long, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val date = Instant.ofEpochMilli(dateEpochMillis).atZone(zone).toLocalDate()
        return date.format(DateTimeFormatter.ofPattern("EEE", locale))
    }

    fun dayAndMonth(date: Long, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val value = Instant.ofEpochMilli(date).atZone(zone).toLocalDate()
        return value.format(DateTimeFormatter.ofPattern("EEE, d MMM", locale))
    }

    fun minutes(total: Int): String {
        if (total < 60) return "$total min"
        val hours = total / 60
        val rest = total % 60
        return if (rest == 0) "$hours hr" else "$hours hr $rest min"
    }

    fun remaining(week: WidgetWeekSummary): String {
        if (week.goal <= 0) return "No weekly goal set"
        if (week.remaining == 0) return "Weekly goal reached"
        return "${week.remaining} session${if (week.remaining == 1) "" else "s"} to go"
    }

    fun weekFraction(week: WidgetWeekSummary): String =
        if (week.goal <= 0) "No goal" else "${week.completed}/${week.goal}"

    fun weekAccessibilityLabel(week: WidgetWeekSummary): String {
        if (week.goal <= 0) return "No weekly goal set. ${week.completed} sessions completed."
        return "${week.completed} of ${week.goal} sessions this week. ${remaining(week)}."
    }

    fun chartDayAccessibilityLabel(
        day: WidgetWeekDay,
        isToday: Boolean,
        zone: ZoneId = ZoneId.systemDefault(),
        locale: Locale = Locale.getDefault(),
    ): String {
        val weekday = shortWeekday(day.dateEpochMillis, zone, locale)
        val status = if (day.didTrain) {
            "${day.completedCount} workout${if (day.completedCount == 1) "" else "s"}"
        } else {
            "no workout"
        }
        return "$weekday: $status${if (isToday) ", today" else ""}"
    }

    fun streakDetail(streak: Int): String =
        if (streak == 0) "Finish a session to start your streak." else "Consecutive training days."
}
