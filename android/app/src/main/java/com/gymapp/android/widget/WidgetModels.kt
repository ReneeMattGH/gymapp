package com.gymapp.android.widget

import com.gymapp.android.core.FormaDate
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * The compact, account-scoped snapshot the widget renders. It contains training
 * summaries only: no free text, no health data, no location. Mirrors the iOS
 * Fitness Command Center snapshot so both platforms answer the same questions.
 */
data class WidgetSnapshot(
    val generatedAt: Long,
    val accountId: String,
    val hasPlan: Boolean,
    val totalCompleted: Int,
    val totalReps: Int,
    val streak: Int,
    val lastSessionAt: Long?,
    val today: WidgetTodaySummary,
    val week: WidgetWeekSummary,
) {
    fun weekDay(on: LocalDate, zone: ZoneId = ZoneId.systemDefault()): WidgetWeekDay? =
        week.days.firstOrNull { Instant.ofEpochMilli(it.dateEpochMillis).atZone(zone).toLocalDate() == on }

    companion object {
        /** A neutral snapshot, never fabricated metrics, for a device with no plan yet. */
        fun empty(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): WidgetSnapshot {
            val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
            val weekStart = FormaDate.startOfWeek(today)
            val days = (0 until 7).map { offset ->
                WidgetWeekDay(
                    dateEpochMillis = weekStart.plusDays(offset.toLong()).atStartOfDay(zone).toInstant().toEpochMilli(),
                    completedCount = 0,
                    minutes = 0,
                )
            }
            return WidgetSnapshot(
                generatedAt = now,
                accountId = "",
                hasPlan = false,
                totalCompleted = 0,
                totalReps = 0,
                streak = 0,
                lastSessionAt = null,
                today = WidgetTodaySummary(state = WidgetTodayState.NO_PLAN),
                week = WidgetWeekSummary(
                    startEpochMillis = weekStart.atStartOfDay(zone).toInstant().toEpochMilli(),
                    goal = 0,
                    completed = 0,
                    minutes = 0,
                    days = days,
                ),
            )
        }
    }
}

enum class WidgetTodayState {
    WORKOUT,
    COMPLETED,
    IN_PROGRESS,
    REST,
    NOT_SCHEDULED,
    NO_PLAN,
}

data class WidgetTodaySummary(
    val state: WidgetTodayState,
    val title: String? = null,
    val focus: List<String> = emptyList(),
    val exerciseCount: Int = 0,
    val setCount: Int = 0,
    val estimatedMinutes: Int = 0,
    val completedTitle: String? = null,
    val activeSessionTitle: String? = null,
    val nextTitle: String? = null,
    /** ISO weekday (1 = Monday … 7 = Sunday) of the next training day. */
    val nextWeekday: Int? = null,
)

data class WidgetWeekDay(
    val dateEpochMillis: Long,
    val completedCount: Int,
    val minutes: Int,
) {
    val didTrain: Boolean get() = completedCount > 0
}

data class WidgetWeekSummary(
    val startEpochMillis: Long,
    val goal: Int,
    val completed: Int,
    val minutes: Int,
    val days: List<WidgetWeekDay>,
) {
    val progress: Double
        get() = if (goal <= 0) 0.0 else minOf(completed.toDouble() / goal, 1.0)

    val remaining: Int get() = maxOf(0, goal - completed)

    val hasActivity: Boolean get() = days.any { it.didTrain }
}

/** Small-widget emphasis. Mirrors the iOS AppIntent; medium and large always show everything. */
enum class WidgetFocus(val label: String) {
    AUTOMATIC("Automatic"),
    TODAY("Today's workout"),
    WEEKLY("Weekly goal"),
    CONSISTENCY("Streak");

    companion object {
        fun from(raw: String?): WidgetFocus =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: AUTOMATIC
    }
}
