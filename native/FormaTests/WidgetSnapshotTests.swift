import XCTest
@testable import Forma

final class WidgetSnapshotTests: XCTestCase {
    private var defaultsSuiteNames: [String] = []

    // MARK: - Fixtures

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Wednesday 18 November 2026. The week starts Monday 16 November.
    private var today: Date { date(2026, 11, 18) }
    private var weekStart: Date { date(2026, 11, 16, 0) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeDefaults() -> UserDefaults {
        let name = "forma.widget.tests.\(UUID().uuidString)"
        defaultsSuiteNames.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeSnapshot(
        accountID: String = "account-a",
        now: Date? = nil,
        community: WidgetCommunitySummary? = nil
    ) -> WidgetSnapshot {
        let now = now ?? today
        let start = WidgetSnapshot.weekStart(for: now, calendar: calendar)
        var snapshot = WidgetSnapshot.empty(now: now, calendar: calendar)
        snapshot.accountID = accountID
        snapshot.generatedAt = now
        snapshot.isPreview = false
        snapshot.hasPlan = true
        snapshot.totalCompleted = 12
        snapshot.totalReps = 345
        snapshot.streak = 4
        snapshot.lastSessionAt = date(2026, 11, 17, 18)
        snapshot.today = WidgetTodaySummary(
            state: .workout,
            title: "Push Day",
            focus: ["Chest", "Back"],
            exerciseCount: 5,
            setCount: 15,
            estimatedMinutes: 45,
            completedTitle: nil,
            activeSessionTitle: nil,
            nextTitle: "Pull Day",
            nextWeekday: 5
        )
        snapshot.week = WidgetWeekSummary(
            start: start,
            goal: 4,
            completed: 2,
            minutes: 88,
            days: (0..<7).map { offset in
                WidgetWeekDay(
                    date: calendar.date(byAdding: .day, value: offset, to: start) ?? start,
                    completedCount: offset == 0 ? 1 : 0,
                    minutes: offset == 0 ? 45 : 0
                )
            }
        )
        snapshot.community = community
        return snapshot
    }

    private func workoutExercise(_ index: Int, sets: Int = 3) -> WorkoutExercise {
        WorkoutExercise(
            id: "exercise-\(index)",
            dayId: "day",
            exerciseId: "bodyweight-squat",
            position: index,
            sets: sets,
            repsMin: 8,
            repsMax: 12,
            restSeconds: 60,
            notes: nil
        )
    }

    private func makeDay(
        dayIndex: Int,
        weekday: Int?,
        title: String,
        isRestDay: Bool = false,
        exercises: Int = 2,
        minutes: Int = 45,
        focus: [MuscleGroup] = [.chest, .back]
    ) -> WorkoutDay {
        WorkoutDay(
            id: "day-\(dayIndex)",
            planId: "plan",
            dayIndex: dayIndex,
            weekday: weekday,
            title: title,
            focus: isRestDay ? [] : focus,
            estimatedMinutes: isRestDay ? 0 : minutes,
            warmup: [],
            cooldown: [],
            isRestDay: isRestDay,
            restNote: isRestDay ? "Easy walk and stretch." : nil,
            exercises: isRestDay ? [] : (0..<exercises).map { workoutExercise(dayIndex * 10 + $0) }
        )
    }

    private func makePlan(daysPerWeek: Int = 3, days: [WorkoutDay]) -> WorkoutPlan {
        WorkoutPlan(
            id: "plan",
            userId: "account-a",
            name: "Test Plan",
            goal: .strength,
            experience: .intermediate,
            daysPerWeek: daysPerWeek,
            sessionMinutes: 45,
            equipment: [.bodyweight],
            source: .onDevice,
            createdAt: date(2026, 11, 1),
            days: days
        )
    }

    /// Monday, Wednesday and Friday are training days; the rest is rest.
    private func weekdayPlan() -> WorkoutPlan {
        let days = (1...7).map { weekday in
            let trains = [1, 3, 5].contains(weekday)
            return makeDay(
                dayIndex: weekday - 1,
                weekday: weekday,
                title: trains ? "Day \(weekday) Strength" : "Rest",
                isRestDay: !trains
            )
        }
        return makePlan(days: days)
    }

    private func makeSession(
        id: String = UUID().uuidString,
        title: String = "Day 3 Strength",
        startedAt: Date,
        durationSeconds: Int = 2700,
        reps: [Int] = [],
        status: SessionStatus = .completed,
        hasEndedAt: Bool = true,
        formReps: Int? = nil
    ) -> WorkoutSession {
        let endedAt: Date? = hasEndedAt
            ? startedAt.addingTimeInterval(TimeInterval(durationSeconds))
            : nil
        let sets = reps.enumerated().map { index, value in
            CompletedSet(
                id: "\(id)-set-\(index)",
                sessionId: id,
                workoutExerciseId: nil,
                exerciseId: "bodyweight-squat",
                setNumber: index + 1,
                reps: value,
                weightKg: nil,
                completedAt: startedAt.addingTimeInterval(60)
            )
        }
        let form: FormAnalysisRecord? = formReps.map { count in
            FormAnalysisRecord(
                sessionID: id,
                exercise: .squat,
                exerciseID: "bodyweight-squat",
                startedAt: startedAt,
                endedAt: endedAt ?? startedAt,
                durationSeconds: 60,
                repCount: count,
                availability: .reliable,
                coverage: 0.9,
                trackingInterruptions: 0,
                observations: [],
                limitations: [],
                cameraPosition: .front
            )
        }
        return WorkoutSession(
            id: id,
            userId: "account-a",
            planDayId: "day-2",
            title: title,
            focus: [.chest],
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            status: status,
            sets: sets,
            notes: nil,
            formAnalysis: form
        )
    }

    private func makeActiveWorkout(title: String = "Morning Lift") -> ActiveWorkout {
        ActiveWorkout(
            sessionId: "active-session",
            userId: "account-a",
            planDayId: "day-2",
            planId: "plan",
            title: title,
            focus: [.chest],
            warmup: [],
            cooldown: [],
            startedAt: today.addingTimeInterval(-600),
            status: .active,
            pausedAt: nil,
            pausedSeconds: 0,
            currentExerciseIndex: 0,
            exercises: [],
            sets: [],
            rest: nil
        )
    }

    private func build(
        plan: WorkoutPlan?,
        preferences: Preferences? = nil,
        sessions: [WorkoutSession] = [],
        activeWorkout: ActiveWorkout? = nil,
        isPreview: Bool = false,
        now: Date? = nil
    ) -> WidgetSnapshot {
        WidgetSnapshotBuilder.build(
            accountID: "account-a",
            plan: plan,
            preferences: preferences,
            sessions: sessions,
            activeWorkout: activeWorkout,
            isPreview: isPreview,
            now: now ?? today,
            calendar: calendar
        )
    }

    private func rawEncode(_ snapshot: WidgetSnapshot) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try! encoder.encode(snapshot)
    }

    override func tearDown() {
        for name in defaultsSuiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
        defaultsSuiteNames.removeAll()
        super.tearDown()
    }

    // MARK: - Snapshot codec

    func testSnapshotRoundTripsThroughCodec() throws {
        let snapshot = makeSnapshot(community: WidgetCommunitySummary(
            pendingRequests: 2,
            unreadMessages: 1,
            unreadNotifications: 3,
            updatedAt: today
        ))
        let data = try XCTUnwrap(WidgetSharedDataStore.encode(snapshot))
        let decoded = try XCTUnwrap(WidgetSharedDataStore.decode(data))

        XCTAssertEqual(decoded.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.accountID, "account-a")
        XCTAssertEqual(decoded.generatedAt, snapshot.generatedAt)
        XCTAssertEqual(decoded.hasPlan, true)
        XCTAssertEqual(decoded.today.state, .workout)
        XCTAssertEqual(decoded.today.title, "Push Day")
        XCTAssertEqual(decoded.today.focus, ["Chest", "Back"])
        XCTAssertEqual(decoded.week.goal, 4)
        XCTAssertEqual(decoded.week.completed, 2)
        XCTAssertEqual(decoded.week.days.count, 7)
        XCTAssertEqual(decoded.community?.unreadMessages, 1)
        XCTAssertEqual(WidgetSharedDataStore.decode(WidgetSharedDataStore.encode(decoded)!), decoded)
    }

    func testEncodeRejectsUnsupportedSchemaVersion() {
        var snapshot = makeSnapshot()
        snapshot.schemaVersion = WidgetSnapshot.currentSchemaVersion + 1
        XCTAssertNil(WidgetSharedDataStore.encode(snapshot))
    }

    func testEncodeRejectsMissingAccount() {
        var snapshot = makeSnapshot()
        snapshot.accountID = ""
        XCTAssertNil(WidgetSharedDataStore.encode(snapshot))
    }

    func testDecodeRejectsCorruptPayload() {
        XCTAssertNil(WidgetSharedDataStore.decode(Data("not a snapshot".utf8)))
        XCTAssertNil(WidgetSharedDataStore.decode(Data()))
    }

    func testDecodeRejectsUnsupportedSchemaVersion() {
        var snapshot = makeSnapshot()
        snapshot.schemaVersion = 99
        XCTAssertNil(WidgetSharedDataStore.decode(rawEncode(snapshot)))
    }

    func testDecodeRejectsMissingAccount() {
        var snapshot = makeSnapshot()
        snapshot.accountID = ""
        XCTAssertNil(WidgetSharedDataStore.decode(rawEncode(snapshot)))
    }

    func testEmptySnapshotCarriesNoFabricatedMetrics() {
        let snapshot = WidgetSnapshot.empty(now: today, calendar: calendar)

        XCTAssertEqual(snapshot.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertTrue(snapshot.accountID.isEmpty)
        XCTAssertFalse(snapshot.hasPlan)
        XCTAssertEqual(snapshot.totalCompleted, 0)
        XCTAssertEqual(snapshot.totalReps, 0)
        XCTAssertEqual(snapshot.streak, 0)
        XCTAssertNil(snapshot.lastSessionAt)
        XCTAssertEqual(snapshot.today.state, .noPlan)
        XCTAssertNil(snapshot.today.title)
        XCTAssertEqual(snapshot.week.goal, 0)
        XCTAssertEqual(snapshot.week.completed, 0)
        XCTAssertEqual(snapshot.week.days.count, 7)
        XCTAssertTrue(snapshot.week.days.allSatisfy { $0.completedCount == 0 && $0.minutes == 0 })
        XCTAssertNil(snapshot.community)
    }

    func testWeekSummaryDerivations() {
        let partial = WidgetWeekSummary(start: weekStart, goal: 4, completed: 2, minutes: 88, days: [])
        XCTAssertEqual(partial.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(partial.remaining, 2)
        XCTAssertFalse(partial.hasActivity)

        let exceeded = WidgetWeekSummary(start: weekStart, goal: 3, completed: 5, minutes: 120, days: [])
        XCTAssertEqual(exceeded.progress, 1)
        XCTAssertEqual(exceeded.remaining, 0)

        let noGoal = WidgetWeekSummary(start: weekStart, goal: 0, completed: 0, minutes: 0, days: [])
        XCTAssertEqual(noGoal.progress, 0)
        XCTAssertEqual(noGoal.remaining, 0)

        let active = WidgetWeekSummary(
            start: weekStart,
            goal: 3,
            completed: 1,
            minutes: 30,
            days: [WidgetWeekDay(date: weekStart, completedCount: 1, minutes: 30)]
        )
        XCTAssertTrue(active.hasActivity)
    }

    func testWeekDayLookupOnlyMatchesDaysInTheSnapshotWeek() {
        let snapshot = makeSnapshot()
        let monday = WidgetSnapshot.weekStart(for: today, calendar: calendar)

        XCTAssertEqual(snapshot.weekDay(on: monday, calendar: calendar)?.completedCount, 1)
        let thursday = calendar.date(byAdding: .day, value: 3, to: monday)!
        XCTAssertEqual(snapshot.weekDay(on: thursday, calendar: calendar)?.completedCount, 0)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: monday)!
        XCTAssertNil(snapshot.weekDay(on: nextWeek, calendar: calendar))
    }

    // MARK: - Shared store and account isolation

    func testSaveAndLoadSnapshot() {
        let defaults = makeDefaults()
        let snapshot = makeSnapshot()

        XCTAssertTrue(WidgetSharedDataStore.save(snapshot, defaults: defaults))
        let loaded = WidgetSharedDataStore.load(defaults: defaults)
        XCTAssertEqual(loaded?.accountID, snapshot.accountID)
        XCTAssertEqual(loaded?.today.title, "Push Day")
        XCTAssertEqual(loaded?.week.completed, 2)
    }

    func testSaveRejectsInvalidSnapshot() {
        let defaults = makeDefaults()
        var snapshot = makeSnapshot()
        snapshot.accountID = ""
        XCTAssertFalse(WidgetSharedDataStore.save(snapshot, defaults: defaults))
        XCTAssertNil(WidgetSharedDataStore.load(defaults: defaults))
    }

    func testSaveWithoutContainerFails() {
        XCTAssertFalse(WidgetSharedDataStore.save(makeSnapshot(), defaults: nil))
        XCTAssertNil(WidgetSharedDataStore.load(defaults: nil))
    }

    func testClearRemovesSnapshotAndCommunityCounts() {
        let defaults = makeDefaults()
        XCTAssertTrue(WidgetSharedDataStore.save(makeSnapshot(), defaults: defaults))
        XCTAssertTrue(WidgetSharedDataStore.updateCommunity(
            accountID: "account-a",
            pendingRequests: 1,
            unreadMessages: 2,
            unreadNotifications: 3,
            defaults: defaults
        ))

        WidgetSharedDataStore.clear(defaults: defaults)

        XCTAssertNil(WidgetSharedDataStore.load(defaults: defaults))
        XCTAssertNil(WidgetSharedDataStore.community(for: "account-a", defaults: defaults))
    }

    func testCommunityCountsOverlayOnlyForMatchingAccount() {
        let defaults = makeDefaults()
        let updatedAt = date(2026, 11, 18, 8)
        XCTAssertTrue(WidgetSharedDataStore.save(makeSnapshot(accountID: "account-a"), defaults: defaults))
        XCTAssertTrue(WidgetSharedDataStore.updateCommunity(
            accountID: "account-a",
            pendingRequests: 2,
            unreadMessages: 1,
            unreadNotifications: 3,
            at: updatedAt,
            defaults: defaults
        ))

        let sameAccount = WidgetSharedDataStore.load(defaults: defaults)
        XCTAssertEqual(sameAccount?.community?.pendingRequests, 2)
        XCTAssertEqual(sameAccount?.community?.unreadMessages, 1)
        XCTAssertEqual(sameAccount?.community?.unreadNotifications, 3)
        XCTAssertEqual(sameAccount?.community?.updatedAt, updatedAt)

        XCTAssertNil(WidgetSharedDataStore.community(for: "account-b", defaults: defaults))

        XCTAssertTrue(WidgetSharedDataStore.updateCommunity(
            accountID: "account-b",
            pendingRequests: 9,
            unreadMessages: 9,
            unreadNotifications: 9,
            defaults: defaults
        ))
        // The training snapshot still belongs to account A, so B's counts must
        // never appear beside it.
        XCTAssertNil(WidgetSharedDataStore.load(defaults: defaults)?.community)

        XCTAssertTrue(WidgetSharedDataStore.save(makeSnapshot(accountID: "account-b"), defaults: defaults))
        XCTAssertEqual(WidgetSharedDataStore.load(defaults: defaults)?.community?.pendingRequests, 9)
    }

    func testCommunityCountsWrittenBeforeSnapshotAreOverlaid() {
        let defaults = makeDefaults()
        XCTAssertTrue(WidgetSharedDataStore.updateCommunity(
            accountID: "account-a",
            pendingRequests: 1,
            unreadMessages: 1,
            unreadNotifications: 0,
            defaults: defaults
        ))
        XCTAssertTrue(WidgetSharedDataStore.save(makeSnapshot(), defaults: defaults))

        XCTAssertEqual(WidgetSharedDataStore.load(defaults: defaults)?.community?.unreadMessages, 1)
    }

    func testUpdateCommunityReportsOnlyRealChanges() {
        let defaults = makeDefaults()
        XCTAssertTrue(WidgetSharedDataStore.updateCommunity(
            accountID: "account-a",
            pendingRequests: 2,
            unreadMessages: 1,
            unreadNotifications: 3,
            at: date(2026, 11, 18, 8),
            defaults: defaults
        ))
        XCTAssertFalse(WidgetSharedDataStore.updateCommunity(
            accountID: "account-a",
            pendingRequests: 2,
            unreadMessages: 1,
            unreadNotifications: 3,
            at: date(2026, 11, 18, 9),
            defaults: defaults
        ))
        XCTAssertTrue(WidgetSharedDataStore.updateCommunity(
            accountID: "account-a",
            pendingRequests: 0,
            unreadMessages: 1,
            unreadNotifications: 3,
            defaults: defaults
        ))
    }

    func testUpdateCommunityClampsNegativeCounts() {
        let defaults = makeDefaults()
        XCTAssertTrue(WidgetSharedDataStore.updateCommunity(
            accountID: "account-a",
            pendingRequests: -3,
            unreadMessages: -1,
            unreadNotifications: -2,
            defaults: defaults
        ))
        let summary = WidgetSharedDataStore.community(for: "account-a", defaults: defaults)
        XCTAssertEqual(summary?.pendingRequests, 0)
        XCTAssertEqual(summary?.unreadMessages, 0)
        XCTAssertEqual(summary?.unreadNotifications, 0)
        XCTAssertEqual(summary?.hasAny, false)
    }

    func testAppGroupSuiteRoundTripsWhenAvailable() throws {
        guard let defaults = WidgetSharedDataStore.sharedDefaults else {
            throw XCTSkip("App Group container is unavailable in this environment")
        }
        WidgetSharedDataStore.clear(defaults: defaults)
        defer { WidgetSharedDataStore.clear(defaults: defaults) }

        let snapshot = makeSnapshot(accountID: "app-group-check")
        XCTAssertTrue(WidgetSharedDataStore.save(snapshot, defaults: defaults))
        defaults.synchronize()

        XCTAssertEqual(WidgetSharedDataStore.load(defaults: defaults)?.accountID, "app-group-check")
        XCTAssertTrue(WidgetSharedDataStore.updateCommunity(
            accountID: "app-group-check",
            pendingRequests: 1,
            unreadMessages: 0,
            unreadNotifications: 0,
            defaults: defaults
        ))
        defaults.synchronize()
        XCTAssertEqual(WidgetSharedDataStore.load(defaults: defaults)?.community?.pendingRequests, 1)
    }

    // MARK: - Snapshot builder

    func testBuilderWithoutPlanProducesNoPlanState() {
        let snapshot = build(plan: nil)

        XCTAssertFalse(snapshot.hasPlan)
        XCTAssertEqual(snapshot.today.state, .noPlan)
        XCTAssertNil(snapshot.today.title)
        XCTAssertEqual(snapshot.today.exerciseCount, 0)
        XCTAssertEqual(snapshot.week.goal, 0)
        XCTAssertEqual(snapshot.week.completed, 0)
        XCTAssertEqual(snapshot.week.days.count, 7)
        XCTAssertNil(snapshot.community)
    }

    func testBuilderUsesPreferencesGoalWithoutPlan() {
        let preferences = Preferences(userId: "account-a", workoutDays: [1, 3, 5])
        let snapshot = build(plan: nil, preferences: preferences)

        XCTAssertEqual(snapshot.today.state, .noPlan)
        XCTAssertEqual(snapshot.week.goal, 3)
    }

    func testBuilderRestDayState() {
        var plan = weekdayPlan()
        plan.days[2] = makeDay(dayIndex: 2, weekday: 3, title: "Rest", isRestDay: true)

        let snapshot = build(plan: plan)

        XCTAssertEqual(snapshot.today.state, .rest)
        XCTAssertEqual(snapshot.today.title, "Rest")
        XCTAssertEqual(snapshot.week.goal, 3)
        XCTAssertEqual(snapshot.today.nextTitle, "Day 5 Strength")
        XCTAssertEqual(snapshot.today.nextWeekday, 5)
    }

    func testBuilderWorkoutTodayState() {
        let snapshot = build(plan: weekdayPlan())

        XCTAssertEqual(snapshot.today.state, .workout)
        XCTAssertEqual(snapshot.today.title, "Day 3 Strength")
        XCTAssertEqual(snapshot.today.focus, ["Chest", "Back"])
        XCTAssertEqual(snapshot.today.exerciseCount, 2)
        XCTAssertEqual(snapshot.today.setCount, 6)
        XCTAssertEqual(snapshot.today.estimatedMinutes, 45)
        XCTAssertNil(snapshot.today.completedTitle)
        XCTAssertEqual(snapshot.week.completed, 0)
        XCTAssertEqual(snapshot.week.minutes, 0)
    }

    func testBuilderCompletedTodayState() {
        let session = makeSession(
            title: "Lunch Strength",
            startedAt: date(2026, 11, 18, 9),
            durationSeconds: 1800,
            reps: [10, 10, 10]
        )
        let snapshot = build(plan: weekdayPlan(), sessions: [session])

        XCTAssertEqual(snapshot.today.state, .completed)
        XCTAssertEqual(snapshot.today.completedTitle, "Lunch Strength")
        XCTAssertEqual(snapshot.week.completed, 1)
        XCTAssertEqual(snapshot.week.minutes, 30)
        XCTAssertEqual(snapshot.week.days[2].completedCount, 1)
        XCTAssertEqual(snapshot.week.days[2].minutes, 30)
        XCTAssertEqual(snapshot.totalCompleted, 1)
        XCTAssertEqual(snapshot.totalReps, 30)
        XCTAssertEqual(snapshot.streak, 1)
    }

    func testBuilderInProgressStateTakesPrecedence() {
        let snapshot = build(plan: weekdayPlan(), activeWorkout: makeActiveWorkout())

        XCTAssertEqual(snapshot.today.state, .inProgress)
        XCTAssertEqual(snapshot.today.title, "Morning Lift")
        XCTAssertEqual(snapshot.today.activeSessionTitle, "Morning Lift")
        XCTAssertEqual(snapshot.week.completed, 0)
    }

    func testBuilderNotScheduledUsesNextTrainingDay() {
        var plan = weekdayPlan()
        plan.days[2] = makeDay(dayIndex: 2, weekday: nil, title: "Wednesday")

        let snapshot = build(plan: plan)

        XCTAssertEqual(snapshot.today.state, .notScheduled)
        XCTAssertNil(snapshot.today.title)
        // Thursday is a rest day, so the next training day is Friday.
        XCTAssertEqual(snapshot.today.nextTitle, "Day 5 Strength")
        XCTAssertEqual(snapshot.today.nextWeekday, 5)
    }

    func testBuilderWeeklyMetricsUseOnlyCompletedSessionsInTheWeek() {
        let sessions = [
            makeSession(id: "previous-week", startedAt: date(2026, 11, 15, 9), durationSeconds: 1200, reps: [5]),
            makeSession(id: "monday", startedAt: date(2026, 11, 16, 9), durationSeconds: 1800, reps: [10, 10]),
            makeSession(id: "tuesday", startedAt: date(2026, 11, 17, 7), durationSeconds: 1200, reps: [10]),
            makeSession(id: "wednesday", startedAt: date(2026, 11, 18, 9), durationSeconds: 2700, reps: [10, 10, 10])
        ]
        let snapshot = build(plan: weekdayPlan(), sessions: sessions)

        XCTAssertEqual(snapshot.week.start, weekStart)
        XCTAssertEqual(snapshot.week.completed, 3)
        XCTAssertEqual(snapshot.week.minutes, 95)
        XCTAssertEqual(snapshot.week.days.map(\.completedCount), [1, 1, 1, 0, 0, 0, 0])
        XCTAssertEqual(snapshot.week.days.map(\.minutes), [30, 20, 45, 0, 0, 0, 0])
        XCTAssertEqual(snapshot.totalCompleted, 4)
        XCTAssertEqual(snapshot.totalReps, 65)
        XCTAssertEqual(snapshot.streak, 4)
        XCTAssertEqual(snapshot.lastSessionAt, date(2026, 11, 18, 9))
    }

    func testBuilderExcludesUnfinishedSessions() {
        let sessions = [
            makeSession(id: "active", startedAt: today, status: .active, hasEndedAt: false),
            makeSession(id: "abandoned", startedAt: date(2026, 11, 17), status: .abandoned, hasEndedAt: false),
            makeSession(id: "completed-without-end", startedAt: date(2026, 11, 16), status: .completed, hasEndedAt: false)
        ]
        let snapshot = build(plan: weekdayPlan(), sessions: sessions)

        XCTAssertEqual(snapshot.totalCompleted, 0)
        XCTAssertEqual(snapshot.week.completed, 0)
        XCTAssertEqual(snapshot.today.state, .workout)
        XCTAssertNil(snapshot.lastSessionAt)
    }

    func testBuilderStreakBreaksWhenYesterdayIsMissing() {
        let sessions = [
            makeSession(id: "two-days-ago", startedAt: date(2026, 11, 16, 9), reps: [10]),
            makeSession(id: "four-days-ago", startedAt: date(2026, 11, 14, 9), reps: [10])
        ]
        let snapshot = build(plan: weekdayPlan(), sessions: sessions)

        XCTAssertEqual(snapshot.streak, 0)
    }

    func testBuilderCountsFormAnalysisRepsExactlyOnce() {
        let session = makeSession(
            startedAt: date(2026, 11, 18, 9),
            reps: [10, 10],
            formReps: 25
        )
        let snapshot = build(plan: weekdayPlan(), sessions: [session])

        XCTAssertEqual(snapshot.totalReps, 45)
        XCTAssertEqual(snapshot.totalCompleted, 1)
    }

    func testBuilderCarriesPreviewFlag() {
        XCTAssertTrue(build(plan: weekdayPlan(), isPreview: true).isPreview)
        XCTAssertFalse(build(plan: weekdayPlan()).isPreview)
    }

    // MARK: - Timeline logic

    func testNextDayBoundaryIsNextMidnight() {
        XCTAssertEqual(
            WidgetTimelineLogic.nextDayBoundary(after: date(2026, 11, 18, 12), calendar: calendar),
            date(2026, 11, 19, 0)
        )
        XCTAssertEqual(
            WidgetTimelineLogic.nextDayBoundary(after: date(2026, 11, 18, 0), calendar: calendar),
            date(2026, 11, 19, 0)
        )
    }

    func testNextRefreshMatchesDayBoundary() {
        let now = date(2026, 11, 18, 12)
        XCTAssertEqual(
            WidgetTimelineLogic.nextRefreshDate(after: now, calendar: calendar),
            WidgetTimelineLogic.nextDayBoundary(after: now, calendar: calendar)
        )
    }

    func testFreshnessLabels() {
        let now = date(2026, 11, 18, 12)
        XCTAssertEqual(WidgetTimelineLogic.freshnessLabel(generatedAt: now, now: now), "Updated just now")
        XCTAssertEqual(
            WidgetTimelineLogic.freshnessLabel(generatedAt: now.addingTimeInterval(-5 * 60), now: now),
            "Updated 5 min ago"
        )
        XCTAssertEqual(
            WidgetTimelineLogic.freshnessLabel(generatedAt: now.addingTimeInterval(-2 * 3600), now: now),
            "Updated 2 hr ago"
        )
        XCTAssertEqual(
            WidgetTimelineLogic.freshnessLabel(generatedAt: now.addingTimeInterval(-86_400), now: now),
            "Updated yesterday"
        )
        XCTAssertEqual(
            WidgetTimelineLogic.freshnessLabel(generatedAt: now.addingTimeInterval(-3 * 86_400), now: now),
            "Updated 3 days ago"
        )
        XCTAssertEqual(
            WidgetTimelineLogic.freshnessLabel(generatedAt: now.addingTimeInterval(60), now: now),
            "Updated just now"
        )
    }

    func testStalenessThreshold() {
        let now = date(2026, 11, 18, 12)
        XCTAssertFalse(WidgetTimelineLogic.isStale(generatedAt: now, now: now))
        XCTAssertFalse(WidgetTimelineLogic.isStale(generatedAt: now.addingTimeInterval(-12 * 3600), now: now))
        XCTAssertTrue(WidgetTimelineLogic.isStale(generatedAt: now.addingTimeInterval(-13 * 3600), now: now))
    }

    // MARK: - Deep links

    func testDeepLinkParsing() {
        XCTAssertEqual(AppDeepLink.parse(URL(string: "forma://today")!), .today)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "FORMA://Today")!), .today)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "forma://start-workout")!), .startWorkout)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "forma://workouts")!), .workouts)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "forma://plan")!), .workouts)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "forma://progress")!), .progress)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "forma://community")!), .community)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "forma://community/requests")!), .connectionRequests)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "forma://community/messages")!), .messages)
    }

    func testDeepLinkRejectsUnsupportedURLs() {
        XCTAssertNil(AppDeepLink.parse(URL(string: "https://today")!))
        XCTAssertNil(AppDeepLink.parse(URL(string: "forma://unknown")!))
        XCTAssertNil(AppDeepLink.parse(URL(string: "forma://community/unknown")!))
        XCTAssertNil(AppDeepLink.parse(URL(string: "forma://auth-callback?code=abc")!))
        XCTAssertNil(AppDeepLink.parse(URL(string: "forma://update-password")!))
    }
}
