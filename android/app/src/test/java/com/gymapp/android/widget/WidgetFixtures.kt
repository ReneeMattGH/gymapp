package com.gymapp.android.widget

import com.gymapp.android.domain.CompletedSet
import com.gymapp.android.domain.Equipment
import com.gymapp.android.domain.Experience
import com.gymapp.android.domain.Goal
import com.gymapp.android.domain.PlanSource
import com.gymapp.android.domain.SessionStatus
import com.gymapp.android.domain.WorkoutDay
import com.gymapp.android.domain.WorkoutExercise
import com.gymapp.android.domain.WorkoutPlan
import com.gymapp.android.domain.WorkoutSession
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** Shared fixtures for the widget tests. All times are pinned to UTC. */
object WidgetFixtures {
    val zone: ZoneId = ZoneId.of("UTC")
    val today: LocalDate = LocalDate.of(2026, 11, 25) // Wednesday

    fun epoch(date: LocalDate = today, time: LocalTime = LocalTime.of(10, 0)): Long =
        date.atTime(time).atZone(zone).toInstant().toEpochMilli()

    fun day(
        weekday: Int,
        rest: Boolean = false,
        title: String = "Day $weekday",
        exerciseCount: Int = 3,
    ): WorkoutDay = WorkoutDay(
        id = "day-$weekday",
        planId = PLAN_ID,
        dayIndex = weekday - 1,
        weekday = weekday,
        title = if (rest) "Rest day" else title,
        focus = emptyList(),
        estimatedMinutes = if (rest) 0 else 40,
        warmup = emptyList(),
        cooldown = emptyList(),
        isRestDay = rest,
        exercises = (1..exerciseCount).map { index ->
            WorkoutExercise(
                id = "we-$weekday-$index",
                dayId = "day-$weekday",
                exerciseId = "ex-$index",
                position = index,
                sets = 3,
                repsMin = 8,
                repsMax = 12,
                restSeconds = 60,
            )
        },
    )

    /** Seven ordered days so next-training-day lookups behave like a real plan. */
    fun weekPlan(vararg trainingWeekdays: Int, daysPerWeek: Int = trainingWeekdays.size): WorkoutPlan {
        val days = (1..7).map { weekday ->
            day(weekday, rest = weekday !in trainingWeekdays)
        }
        return WorkoutPlan(
            id = PLAN_ID,
            userId = USER_ID,
            name = "Test plan",
            goal = Goal.STRENGTH,
            experience = Experience.BEGINNER,
            daysPerWeek = daysPerWeek,
            sessionMinutes = 45,
            equipment = listOf(Equipment.BODYWEIGHT),
            source = PlanSource.ON_DEVICE,
            createdAt = 0,
            days = days,
        )
    }

    fun session(
        date: LocalDate,
        time: LocalTime = LocalTime.of(9, 0),
        title: String = "Upper body",
        durationSeconds: Int = 2_400,
        reps: Int = 10,
    ): WorkoutSession {
        val started = epoch(date, time)
        return WorkoutSession(
            id = "session-$date-$time",
            userId = USER_ID,
            title = title,
            startedAt = started,
            endedAt = started + durationSeconds * 1000L,
            durationSeconds = durationSeconds,
            status = SessionStatus.COMPLETED,
            sets = listOf(
                CompletedSet(
                    id = "set-$date-$time",
                    sessionId = "session-$date-$time",
                    exerciseId = "ex-1",
                    setNumber = 1,
                    reps = reps,
                    completedAt = started + 60_000L,
                ),
            ),
        )
    }

    const val USER_ID = "user-1"
    const val PLAN_ID = "plan-1"
}
