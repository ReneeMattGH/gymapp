package com.gymapp.android.widget

import com.gymapp.android.core.FormaDate
import com.gymapp.android.domain.ActiveWorkout
import com.gymapp.android.domain.Preferences
import com.gymapp.android.domain.SessionStatus
import com.gymapp.android.domain.WorkoutDay
import com.gymapp.android.domain.WorkoutPlan
import com.gymapp.android.domain.WorkoutSession
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Derives the widget snapshot from the same plan helpers and session records the
 * app renders. It runs in the app process against the local database, so the
 * widget never walks workout history itself.
 */
object WidgetSnapshotBuilder {
    fun build(
        accountId: String,
        plan: WorkoutPlan?,
        preferences: Preferences?,
        sessions: List<WorkoutSession>,
        activeWorkout: ActiveWorkout?,
        now: Long,
        zone: ZoneId = ZoneId.systemDefault(),
    ): WidgetSnapshot {
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val weekStart = FormaDate.startOfWeek(today)
        val weekEnd = weekStart.plusDays(7)

        val completed = sessions.filter { it.status == SessionStatus.COMPLETED && it.endedAt != null }
        val weekSessions = completed.filter { session ->
            val day = dayOf(session.startedAt, zone)
            !day.isBefore(weekStart) && day.isBefore(weekEnd)
        }
        val todaySessions = completed.filter { dayOf(it.startedAt, zone) == today }

        val planDay = plan?.days?.firstOrNull { it.weekday == today.dayOfWeek.value }
        val nextDay = plan?.let { nextTrainingDay(it, today) }

        val goal = when {
            plan != null -> maxOf(1, plan.daysPerWeek)
            preferences != null && preferences.workoutDays.isNotEmpty() -> maxOf(1, preferences.workoutDays.size)
            else -> 0
        }

        val state = when {
            activeWorkout != null -> WidgetTodayState.IN_PROGRESS
            plan == null -> WidgetTodayState.NO_PLAN
            planDay == null -> WidgetTodayState.NOT_SCHEDULED
            planDay.isRestDay -> WidgetTodayState.REST
            todaySessions.isNotEmpty() -> WidgetTodayState.COMPLETED
            else -> WidgetTodayState.WORKOUT
        }

        val title = when (state) {
            WidgetTodayState.IN_PROGRESS -> activeWorkout?.title ?: planDay?.title
            WidgetTodayState.WORKOUT, WidgetTodayState.COMPLETED -> planDay?.title
            WidgetTodayState.REST -> planDay?.title ?: "Rest day"
            WidgetTodayState.NOT_SCHEDULED, WidgetTodayState.NO_PLAN -> null
        }

        val todaySummary = WidgetTodaySummary(
            state = state,
            title = title,
            focus = planDay?.focus?.map { it.label }.orEmpty(),
            exerciseCount = planDay?.exercises?.size ?: 0,
            setCount = planDay?.exercises?.sumOf { it.sets } ?: 0,
            estimatedMinutes = planDay?.estimatedMinutes ?: 0,
            completedTitle = todaySessions.firstOrNull()?.title,
            activeSessionTitle = activeWorkout?.title,
            nextTitle = nextDay?.title,
            nextWeekday = nextDay?.weekday,
        )

        val days = (0 until 7).map { offset ->
            val date = weekStart.plusDays(offset.toLong())
            val daySessions = weekSessions.filter { dayOf(it.startedAt, zone) == date }
            WidgetWeekDay(
                dateEpochMillis = date.atStartOfDay(zone).toInstant().toEpochMilli(),
                completedCount = daySessions.size,
                minutes = daySessions.sumOf { it.durationSeconds } / 60,
            )
        }

        return WidgetSnapshot(
            generatedAt = now,
            accountId = accountId,
            hasPlan = plan != null,
            totalCompleted = completed.size,
            totalReps = completed.sumOf { session -> session.sets.sumOf { it.reps } },
            streak = currentStreak(completed, today, zone),
            lastSessionAt = completed.maxOfOrNull { it.startedAt },
            today = todaySummary,
            week = WidgetWeekSummary(
                startEpochMillis = weekStart.atStartOfDay(zone).toInstant().toEpochMilli(),
                goal = goal,
                completed = weekSessions.size,
                minutes = weekSessions.sumOf { it.durationSeconds } / 60,
                days = days,
            ),
        )
    }

    private fun dayOf(epochMillis: Long, zone: ZoneId): LocalDate =
        Instant.ofEpochMilli(epochMillis).atZone(zone).toLocalDate()

    private fun nextTrainingDay(plan: WorkoutPlan, today: LocalDate): WorkoutDay? {
        val todayIndex = today.dayOfWeek.value - 1
        for (offset in 1..7) {
            val index = ((todayIndex + offset) % 7 + 7) % 7
            val day = plan.days.getOrNull(index) ?: continue
            if (!day.isRestDay) return day
        }
        return null
    }

    /** Same rule as the app's TrainingStats: today counts if trained, otherwise yesterday may. */
    private fun currentStreak(completed: List<WorkoutSession>, today: LocalDate, zone: ZoneId): Int {
        val days = completed.map { dayOf(it.startedAt, zone) }.toSet()
        var day = today
        if (day !in days) {
            val yesterday = day.minusDays(1)
            if (yesterday !in days) return 0
            day = yesterday
        }
        var streak = 0
        while (day in days) {
            streak += 1
            day = day.minusDays(1)
        }
        return streak
    }
}
