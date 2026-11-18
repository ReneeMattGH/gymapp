import Foundation

/// Builds the widget snapshot from the same models, plan helpers and session
/// records the app renders. Summaries are computed here, in the app process,
/// so the extension never walks workout history.
enum WidgetSnapshotBuilder {
    static func build(
        accountID: String,
        plan: WorkoutPlan?,
        preferences: Preferences?,
        sessions: [WorkoutSession],
        activeWorkout: ActiveWorkout?,
        isPreview: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let completed = TrainingStats.completedSessions(sessions)
        let weekStart = TrainingStats.startOfWeek(now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        let weekSessions = completed.filter { $0.startedAt >= weekStart && $0.startedAt < weekEnd }
        let todaySessions = completed.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }

        let planDay = plan.flatMap { PlanGenerator.planForDate($0, date: now) }
        let nextDay = plan.flatMap { PlanGenerator.nextTrainingDay($0, from: now) }

        let goal: Int = {
            if let plan { return max(1, plan.daysPerWeek) }
            if let preferences, !preferences.workoutDays.isEmpty {
                return max(1, preferences.workoutDays.count)
            }
            return 0
        }()

        let state: WidgetTodayState
        if activeWorkout != nil {
            state = .inProgress
        } else if plan == nil {
            state = .noPlan
        } else if let planDay {
            if planDay.isRestDay {
                state = .rest
            } else if !todaySessions.isEmpty {
                state = .completed
            } else {
                state = .workout
            }
        } else {
            state = .notScheduled
        }

        let title: String?
        switch state {
        case .inProgress: title = activeWorkout?.title ?? planDay?.title
        case .workout, .completed: title = planDay?.title
        case .rest: title = planDay?.title ?? "Rest day"
        case .notScheduled, .noPlan: title = nil
        }

        let today = WidgetTodaySummary(
            state: state,
            title: title,
            focus: planDay?.focus.map(\.label) ?? [],
            exerciseCount: planDay?.exercises.count ?? 0,
            setCount: planDay?.exercises.reduce(0) { $0 + $1.sets } ?? 0,
            estimatedMinutes: planDay?.estimatedMinutes ?? 0,
            completedTitle: todaySessions.first?.title,
            activeSessionTitle: activeWorkout?.title,
            nextTitle: nextDay?.title,
            nextWeekday: nextDay?.weekday
        )

        let days = (0..<7).map { offset -> WidgetWeekDay in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let sessions = weekSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
            return WidgetWeekDay(
                date: date,
                completedCount: sessions.count,
                minutes: sessions.reduce(0) { $0 + $1.durationSeconds } / 60
            )
        }

        let week = WidgetWeekSummary(
            start: weekStart,
            goal: goal,
            completed: weekSessions.count,
            minutes: weekSessions.reduce(0) { $0 + $1.durationSeconds } / 60,
            days: days
        )

        return WidgetSnapshot(
            schemaVersion: WidgetSnapshot.currentSchemaVersion,
            generatedAt: now,
            accountID: accountID,
            isPreview: isPreview,
            hasPlan: plan != nil,
            totalCompleted: completed.count,
            totalReps: completed.reduce(0) { $0 + TrainingStats.sessionReps($1) },
            streak: TrainingStats.currentStreak(sessions, reference: now, calendar: calendar),
            lastSessionAt: completed.map(\.startedAt).max(),
            today: today,
            week: week,
            community: nil
        )
    }
}
