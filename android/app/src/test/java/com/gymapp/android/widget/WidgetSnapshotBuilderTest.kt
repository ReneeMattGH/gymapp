package com.gymapp.android.widget

import com.gymapp.android.domain.ActiveWorkout
import com.gymapp.android.domain.WorkoutRunStatus
import com.gymapp.android.widget.WidgetFixtures.epoch
import com.gymapp.android.widget.WidgetFixtures.session
import com.gymapp.android.widget.WidgetFixtures.today
import com.gymapp.android.widget.WidgetFixtures.weekPlan
import com.gymapp.android.widget.WidgetFixtures.zone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** Mirrors `native/FormaTests` coverage for WidgetSnapshotBuilder. */
class WidgetSnapshotBuilderTest {
    private val now = epoch(today)

    @Test
    fun `no plan yields no-plan state without fabricated numbers`() {
        val snapshot = WidgetSnapshotBuilder.build(
            accountId = WidgetFixtures.USER_ID,
            plan = null,
            preferences = null,
            sessions = emptyList(),
            activeWorkout = null,
            now = now,
            zone = zone,
        )

        assertFalse(snapshot.hasPlan)
        assertEquals(WidgetTodayState.NO_PLAN, snapshot.today.state)
        assertNull(snapshot.today.title)
        assertEquals(0, snapshot.week.goal)
        assertEquals(0, snapshot.totalCompleted)
        assertEquals(0, snapshot.streak)
        assertEquals(7, snapshot.week.days.size)
        assertTrue(snapshot.week.days.all { !it.didTrain })
    }

    @Test
    fun `scheduled training day drives the workout state`() {
        val plan = weekPlan(1, 3, 5)
        val snapshot = WidgetSnapshotBuilder.build(
            accountId = WidgetFixtures.USER_ID,
            plan = plan,
            preferences = null,
            sessions = emptyList(),
            activeWorkout = null,
            now = now,
            zone = zone,
        )

        assertTrue(snapshot.hasPlan)
        assertEquals(WidgetTodayState.WORKOUT, snapshot.today.state)
        assertEquals("Day 3", snapshot.today.title)
        assertEquals(3, snapshot.today.exerciseCount)
        assertEquals(9, snapshot.today.setCount)
        assertEquals(40, snapshot.today.estimatedMinutes)
        assertEquals("Day 5", snapshot.today.nextTitle)
        assertEquals(5, snapshot.today.nextWeekday)
        assertEquals(3, snapshot.week.goal)
    }

    @Test
    fun `rest day and not-scheduled days are distinct`() {
        val restPlan = weekPlan(1, 5)
        val rest = WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID, restPlan, null, emptyList(), null, now, zone,
        )
        assertEquals(WidgetTodayState.REST, rest.today.state)
        assertEquals("Day 5", rest.today.nextTitle)

        val sparsePlan = weekPlan(1, 5).copy(days = listOf(WidgetFixtures.day(1), WidgetFixtures.day(5)))
        val notScheduled = WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID, sparsePlan, null, emptyList(), null, now, zone,
        )
        assertEquals(WidgetTodayState.NOT_SCHEDULED, notScheduled.today.state)
        assertNull(notScheduled.today.title)
        assertEquals("Day 1", notScheduled.today.nextTitle)
    }

    @Test
    fun `today completion wins over the planned workout`() {
        val completed = session(today)
        val snapshot = WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID,
            weekPlan(1, 3, 5),
            null,
            listOf(completed),
            null,
            now,
            zone,
        )

        assertEquals(WidgetTodayState.COMPLETED, snapshot.today.state)
        assertEquals("Upper body", snapshot.today.completedTitle)
        assertEquals(1, snapshot.week.completed)
        assertEquals(40, snapshot.week.minutes)
        assertEquals(1, snapshot.totalCompleted)
        assertEquals(10, snapshot.totalReps)
        assertEquals(completed.startedAt, snapshot.lastSessionAt)
        assertTrue(snapshot.week.days.first { it.dateEpochMillis == epoch(today, java.time.LocalTime.MIDNIGHT) }.didTrain)
    }

    @Test
    fun `unfinished workout reports in progress`() {
        val active = ActiveWorkout(
            sessionId = "active-1",
            userId = WidgetFixtures.USER_ID,
            planDayId = "day-3",
            planId = WidgetFixtures.PLAN_ID,
            title = "Push day",
            startedAt = now - 600_000L,
            status = WorkoutRunStatus.ACTIVE,
            currentExerciseIndex = 0,
            exercises = emptyList(),
            sets = emptyList(),
            rest = null,
        )
        val snapshot = WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID,
            weekPlan(1, 3, 5),
            null,
            emptyList(),
            active,
            now,
            zone,
        )

        assertEquals(WidgetTodayState.IN_PROGRESS, snapshot.today.state)
        assertEquals("Push day", snapshot.today.activeSessionTitle)
        assertEquals("Push day", snapshot.today.title)
    }

    @Test
    fun `streak counts consecutive days, allowing yesterday when today is empty`() {
        val sessions = listOf(
            session(today),
            session(today.minusDays(1)),
            session(today.minusDays(2)),
            session(today.minusDays(4)),
        )
        val withToday = build(sessions)
        assertEquals(3, withToday.streak)

        val withoutToday = build(sessions.drop(1))
        assertEquals(2, withoutToday.streak)

        val gap = build(listOf(session(today.minusDays(4))))
        assertEquals(0, gap.streak)
    }

    @Test
    fun `week summary ignores sessions outside the current week`() {
        val lastWeek = today.minusDays(9)
        val snapshot = build(listOf(session(today), session(lastWeek)))

        assertEquals(1, snapshot.week.completed)
        assertEquals(2, snapshot.totalCompleted)
        assertEquals(7, snapshot.week.days.size)
        assertTrue(snapshot.week.days.all { it.dateEpochMillis != epoch(lastWeek) })
    }

    private fun build(sessions: List<com.gymapp.android.domain.WorkoutSession>): WidgetSnapshot =
        WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID,
            weekPlan(1, 3, 5),
            null,
            sessions,
            null,
            now,
            zone,
        )
}
