package com.gymapp.android.domain

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class TrainingStatsTest {
    private fun session(
        id: String,
        day: LocalDate,
        status: SessionStatus = SessionStatus.COMPLETED,
        reps: List<Int> = emptyList(),
    ): WorkoutSession {
        val startedAt = day.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        return WorkoutSession(
            id = id,
            userId = "user-1",
            title = "Session",
            startedAt = startedAt,
            endedAt = if (status == SessionStatus.COMPLETED) startedAt + 3_600_000 else null,
            durationSeconds = 3600,
            status = status,
            sets = reps.mapIndexed { index, value ->
                CompletedSet(
                    id = "$id-set-$index",
                    sessionId = id,
                    exerciseId = "push-up",
                    setNumber = index + 1,
                    reps = value,
                    completedAt = startedAt,
                )
            },
        )
    }

    private val reference: LocalDate = LocalDate.of(2026, 11, 27)

    @Test
    fun `only completed sessions count`() {
        val sessions = listOf(
            session("a", reference),
            session("b", reference.minusDays(1), status = SessionStatus.ACTIVE),
            session("c", reference.minusDays(2), status = SessionStatus.ABANDONED),
        )
        assertEquals(listOf("a"), TrainingStats.completedSessions(sessions).map { it.id })
    }

    @Test
    fun `sessions on day filters by local start date`() {
        val sessions = listOf(session("a", reference), session("b", reference.minusDays(1)))
        assertEquals(listOf("a"), TrainingStats.sessionsOnDay(sessions, reference).map { it.id })
    }

    @Test
    fun `current week count stays inside the locale week`() {
        val start = TrainingStats.startOfWeek(reference)
        val sessions = listOf(
            session("mon", start),
            session("tue", start.plusDays(1)),
            session("wed", start.plusDays(2)),
            session("thu", start.plusDays(3)),
            session("previous", start.minusDays(1)),
        )
        assertEquals(4, TrainingStats.currentWeekCount(sessions, reference))
    }

    @Test
    fun `last weeks counts align to week windows`() {
        val start = TrainingStats.startOfWeek(reference)
        val sessions = listOf(
            session("this-week", start.plusDays(2)),
            session("last-week", start.minusDays(3)),
        )
        val counts = TrainingStats.lastWeeksCounts(sessions, weeks = 3, reference = reference)
        assertEquals(3, counts.size)
        assertEquals(listOf(0, 1, 1), counts.map { it.value })
    }

    @Test
    fun `last days counts include only the trailing window`() {
        val sessions = listOf(
            session("today", reference),
            session("two-days-ago", reference.minusDays(2)),
            session("out-of-window", reference.minusDays(5)),
        )
        assertEquals(listOf(1, 0, 1), TrainingStats.lastDaysCounts(sessions, days = 3, reference = reference).map { it.value })
    }

    @Test
    fun `last months counts group by calendar month`() {
        val sessions = listOf(
            session("october", LocalDate.of(2026, 10, 12)),
            session("november", LocalDate.of(2026, 11, 2)),
            session("september", LocalDate.of(2026, 9, 30)),
        )
        val counts = TrainingStats.lastMonthsCounts(sessions, months = 3, reference = reference)
        assertEquals(3, counts.size)
        assertEquals(listOf(1, 1, 1), counts.map { it.value })
    }

    @Test
    fun `streak counts consecutive active days and forgives one idle day`() {
        val sessions = listOf(
            session("today", reference),
            session("yesterday", reference.minusDays(1)),
            session("two", reference.minusDays(2)),
            session("gap", reference.minusDays(4)),
        )
        assertEquals(3, TrainingStats.currentStreak(sessions, reference))

        val onlyYesterday = listOf(session("yesterday", reference.minusDays(1)))
        assertEquals(1, TrainingStats.currentStreak(onlyYesterday, reference))

        assertEquals(0, TrainingStats.currentStreak(emptyList(), reference))
    }

    @Test
    fun `rep totals add up across sets`() {
        val done = session("a", reference, reps = listOf(10, 8, 12))
        assertEquals(30, TrainingStats.sessionReps(done))
        assertEquals(0, TrainingStats.totalReps(emptyList()))
    }
}
