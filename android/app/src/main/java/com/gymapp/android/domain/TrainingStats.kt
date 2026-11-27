package com.gymapp.android.domain

import com.gymapp.android.core.FormaDate
import com.gymapp.android.core.Formatters
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale

object TrainingStats {
    data class WeekCount(val start: LocalDate, val value: Int) {
        val label: String get() = start.format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault()))
    }

    data class DayCount(val start: LocalDate, val value: Int) {
        val label: String get() = start.format(DateTimeFormatter.ofPattern("EEEEE", Locale.getDefault()))
    }

    data class MonthCount(val start: YearMonth, val value: Int) {
        val label: String get() = start.format(DateTimeFormatter.ofPattern("MMM", Locale.getDefault()))
    }

    fun startOfWeek(date: LocalDate = LocalDate.now()): LocalDate = FormaDate.startOfWeek(date)

    fun completedSessions(sessions: List<WorkoutSession>): List<WorkoutSession> =
        sessions.filter { it.status == SessionStatus.COMPLETED && it.endedAt != null }

    fun sessionsOnDay(sessions: List<WorkoutSession>, date: LocalDate): List<WorkoutSession> =
        completedSessions(sessions).filter { FormaDate.date(it.startedAt) == date }

    fun activeDayKeys(sessions: List<WorkoutSession>): Set<LocalDate> =
        completedSessions(sessions).map { FormaDate.date(it.startedAt) }.toSet()

    fun currentWeekCount(sessions: List<WorkoutSession>, reference: LocalDate = LocalDate.now()): Int {
        val start = startOfWeek(reference)
        val end = start.plusDays(7)
        return completedSessions(sessions).count {
            val day = FormaDate.date(it.startedAt)
            !day.isBefore(start) && day.isBefore(end)
        }
    }

    fun lastWeeksCounts(
        sessions: List<WorkoutSession>,
        weeks: Int,
        reference: LocalDate = LocalDate.now(),
    ): List<WeekCount> {
        val currentStart = startOfWeek(reference)
        return (0 until weeks).map { index ->
            val start = currentStart.minusWeeks((weeks - 1 - index).toLong())
            val end = start.plusDays(7)
            val value = completedSessions(sessions).count {
                val day = FormaDate.date(it.startedAt)
                !day.isBefore(start) && day.isBefore(end)
            }
            WeekCount(start, value)
        }
    }

    fun lastDaysCounts(
        sessions: List<WorkoutSession>,
        days: Int,
        reference: LocalDate = LocalDate.now(),
    ): List<DayCount> {
        return (0 until days).map { index ->
            val start = reference.minusDays((days - 1 - index).toLong())
            val value = completedSessions(sessions).count {
                FormaDate.date(it.startedAt) == start
            }
            DayCount(start, value)
        }
    }

    fun lastMonthsCounts(
        sessions: List<WorkoutSession>,
        months: Int,
        reference: LocalDate = LocalDate.now(),
    ): List<MonthCount> {
        val current = YearMonth.from(reference)
        return (0 until months).map { index ->
            val start = current.minusMonths((months - 1 - index).toLong())
            val value = completedSessions(sessions).count {
                YearMonth.from(FormaDate.date(it.startedAt)) == start
            }
            MonthCount(start, value)
        }
    }

    fun currentStreak(sessions: List<WorkoutSession>, reference: LocalDate = LocalDate.now()): Int {
        val days = activeDayKeys(sessions)
        var day = reference
        if (!days.contains(day)) {
            val yesterday = day.minusDays(1)
            if (!days.contains(yesterday)) return 0
            day = yesterday
        }
        var streak = 0
        while (days.contains(day)) {
            streak += 1
            day = day.minusDays(1)
        }
        return streak
    }

    fun totalReps(sets: List<CompletedSet>): Int = sets.sumOf { it.reps }

    fun sessionReps(session: WorkoutSession): Int = totalReps(session.sets)

    fun sessionSubtitle(session: WorkoutSession): String =
        "${Formatters.shortDate(FormaDate.date(session.startedAt))} · " +
            "${Formatters.minutesLabel(session.durationSeconds)} · ${session.sets.size} sets"
}
