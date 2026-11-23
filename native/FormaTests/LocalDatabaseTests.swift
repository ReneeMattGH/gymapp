import XCTest
import GRDB
@testable import Forma

final class LocalDatabaseTests: XCTestCase {
    private var directory: URL!
    private var database: AppDatabase!
    private var repository: LocalRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormaDBTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = try AppDatabase.onDisk(at: directory.appendingPathComponent("forma.sqlite"))
        repository = LocalRepository(database: database)
    }

    override func tearDownWithError() throws {
        database = nil
        repository = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testSchemaContainsEveryRequiredTable() throws {
        let tables = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        let required = [
            "app_settings", "completed_sets", "exercise_library", "profiles",
            "progress_records", "reminder_settings", "user_preferences",
            "workout_days", "workout_exercises", "workout_plans", "workout_sessions",
        ]
        for table in required {
            XCTAssertTrue(tables.contains(table), "Missing table \(table)")
        }
    }

    func testForeignKeysAreEnforced() throws {
        try database.writer.write { db in
            XCTAssertTrue(try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") ?? false)
            XCTAssertThrowsError(
                try db.execute(sql: """
                    INSERT INTO user_preferences
                    (user_id, workout_days, session_minutes, equipment, avoid_exercises, reminder_time, units, updated_at)
                    VALUES ('missing', '[]', 45, '[]', '[]', '18:00', 'kg', '2026-01-01')
                    """)
            )
        }
    }

    func testExerciseLibrarySeedsOnceFromBundledCatalog() async throws {
        let count = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise_library") ?? 0
        }
        XCTAssertEqual(count, ExerciseCatalog.all.count, "Seeded rows must match the bundled verified catalog")
        XCTAssertGreaterThan(count, 0)

        // Re-running migrations must not duplicate seeds.
        try FormaMigrations.migrate(database.writer)
        let again = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise_library") ?? 0
        }
        XCTAssertEqual(again, count)

        let exercises = try await repository.getExercises()
        XCTAssertEqual(exercises.count, count)
        XCTAssertEqual(exercises.first?.id, ExerciseCatalog.all.first?.id, "Catalog order must be preserved")
    }

    func testProfilePreferencesAndCascadeDelete() async throws {
        let profile = makeProfile(name: "Matt")
        let preferences = Preferences(userId: profile.id, workoutDays: [1, 3, 5], sessionMinutes: 45)
        try await repository.saveProfile(profile)
        try await repository.savePreferences(preferences)

        let loaded = try await repository.getProfile(userId: profile.id)
        XCTAssertEqual(loaded, profile)
        let loadedPreferences = try await repository.getPreferences(userId: profile.id)
        XCTAssertEqual(loadedPreferences, preferences)
        let profileIDs = try await repository.listProfiles().map(\.id)
        XCTAssertEqual(profileIDs, [profile.id])

        try await repository.deleteProfile(userId: profile.id)
        let deletedProfile = try await repository.getProfile(userId: profile.id)
        let deletedPreferences = try await repository.getPreferences(userId: profile.id)
        XCTAssertNil(deletedProfile)
        XCTAssertNil(deletedPreferences, "Preferences must cascade with the profile")
    }

    func testPlanRoundTripPreservesDaysAndExercises() async throws {
        let profile = makeProfile(name: "Matt")
        try await repository.saveProfile(profile)
        let preferences = Preferences(userId: profile.id, workoutDays: [1, 3, 5], sessionMinutes: 45)
        let plan = try XCTUnwrap(
            PlanGenerator.generateLocalPlan(userId: profile.id, profile: profile, preferences: preferences)
        )
        try await repository.savePlan(plan)

        let loaded = try await repository.getActivePlan(userId: profile.id)
        XCTAssertEqual(loaded, plan)
        XCTAssertEqual(loaded?.days.count, plan.days.count)
        XCTAssertEqual(loaded?.totalExercises, plan.totalExercises)
    }

    func testSavingANewPlanIsAtomicAndArchivesThePreviousOne() async throws {
        let profile = makeProfile(name: "Matt")
        try await repository.saveProfile(profile)
        let preferences = Preferences(userId: profile.id, workoutDays: [1, 3, 5], sessionMinutes: 45)
        let original = try XCTUnwrap(
            PlanGenerator.generateLocalPlan(userId: profile.id, profile: profile, preferences: preferences)
        )
        try await repository.savePlan(original)

        // A plan referencing a missing exercise must fail inside the transaction
        // and leave the previous plan untouched.
        var broken = original
        broken.id = IDs.uuid()
        broken.createdAt = StoredTimestamp.now()
        broken.days = broken.days.map { day in
            var copy = day
            copy.id = IDs.uuid()
            copy.planId = broken.id
            copy.exercises = copy.exercises.map { exercise in
                var item = exercise
                item.id = IDs.uuid()
                item.dayId = copy.id
                item.exerciseId = "does-not-exist"
                return item
            }
            return copy
        }
        do {
            try await repository.savePlan(broken)
            XCTFail("Saving a plan with an unknown exercise must fail")
        } catch {
            let stillActive = try await repository.getActivePlan(userId: profile.id)
            XCTAssertEqual(stillActive?.id, original.id, "Failed save must not delete the active plan")
        }
    }

    func testSessionRoundTripIncludesSetsAndFormAnalysis() async throws {
        let profile = makeProfile(name: "Matt")
        try await repository.saveProfile(profile)
        let preferences = Preferences(userId: profile.id, workoutDays: [1, 3, 5], sessionMinutes: 45)
        let plan = try XCTUnwrap(
            PlanGenerator.generateLocalPlan(userId: profile.id, profile: profile, preferences: preferences)
        )
        try await repository.savePlan(plan)
        let day = try XCTUnwrap(plan.trainingDays.first)
        let exercise = try XCTUnwrap(day.exercises.first)

        let session = WorkoutSession(
            id: IDs.uuid(),
            userId: profile.id,
            planDayId: day.id,
            title: day.title,
            focus: day.focus,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_001_800),
            durationSeconds: 1800,
            status: .completed,
            sets: [
                CompletedSet(
                    id: IDs.uuid(),
                    sessionId: "",
                    workoutExerciseId: exercise.id,
                    exerciseId: exercise.exerciseId,
                    setNumber: 1,
                    reps: 8,
                    weightKg: 60,
                    completedAt: Date(timeIntervalSince1970: 1_800_000_300)
                ),
            ],
            notes: "Felt strong"
        )
        var stored = session
        stored.sets = session.sets.map { set in
            var copy = set
            copy.sessionId = session.id
            return copy
        }
        let form = FormAnalysisRecord(
            sessionID: session.id,
            exercise: .squat,
            exerciseID: exercise.exerciseId,
            startedAt: session.startedAt,
            endedAt: session.endedAt ?? session.startedAt,
            durationSeconds: 120,
            repCount: 8,
            availability: .reliable,
            coverage: 0.82,
            trackingInterruptions: 1,
            observations: [],
            limitations: ["Simulator camera unavailable."],
            cameraPosition: .front
        )
        stored.formAnalysis = form

        try await repository.saveSession(stored)

        let sessions = try await repository.getSessions(userId: profile.id)
        XCTAssertEqual(sessions.count, 1)
        let loaded = try XCTUnwrap(sessions.first)
        XCTAssertEqual(loaded.id, stored.id)
        XCTAssertEqual(loaded.sets.count, 1)
        XCTAssertEqual(loaded.sets.first?.reps, 8)
        XCTAssertEqual(loaded.sets.first?.weightKg, 60)
        XCTAssertEqual(loaded.formAnalysis, form)
        let fetched = try await repository.getSession(id: stored.id)
        XCTAssertEqual(fetched, stored)
    }

    func testReplacingAPlanKeepsSessionHistoryAndClearsDayReference() async throws {
        let profile = makeProfile(name: "Matt")
        try await repository.saveProfile(profile)
        let preferences = Preferences(userId: profile.id, workoutDays: [1, 3, 5], sessionMinutes: 45)
        let first = try XCTUnwrap(
            PlanGenerator.generateLocalPlan(userId: profile.id, profile: profile, preferences: preferences)
        )
        try await repository.savePlan(first)
        let day = try XCTUnwrap(first.trainingDays.first)
        var session = WorkoutSession(
            id: IDs.uuid(),
            userId: profile.id,
            planDayId: day.id,
            title: day.title,
            focus: day.focus,
            startedAt: StoredTimestamp.now(),
            endedAt: StoredTimestamp.now(),
            durationSeconds: 600,
            status: .completed,
            sets: []
        )
        session.endedAt = StoredTimestamp.truncated(session.startedAt.addingTimeInterval(600))
        try await repository.saveSession(session)

        var second = first
        second.id = IDs.uuid()
        second.createdAt = StoredTimestamp.truncated(Date().addingTimeInterval(60))
        second.days = second.days.map { day in
            var copy = day
            copy.id = IDs.uuid()
            copy.planId = second.id
            copy.exercises = copy.exercises.map { exercise in
                var item = exercise
                item.id = IDs.uuid()
                item.dayId = copy.id
                return item
            }
            return copy
        }
        try await repository.savePlan(second)

        let sessions = try await repository.getSessions(userId: profile.id)
        XCTAssertEqual(sessions.count, 1, "History must survive a plan rebuild")
        XCTAssertNil(sessions.first?.planDayId, "Old day reference is cleared, not stale")
    }

    func testActiveProfileSettingPersists() async throws {
        try await repository.setActiveProfileID("abc")
        let stored = try await repository.activeProfileID()
        XCTAssertEqual(stored, "abc")
        try await repository.setActiveProfileID(nil)
        let cleared = try await repository.activeProfileID()
        XCTAssertNil(cleared)
    }

    func testProgressRecordsOrderedAndDeletable() async throws {
        let profile = makeProfile(name: "Matt")
        try await repository.saveProfile(profile)
        let older = ProgressRecord(
            id: IDs.uuid(), userId: profile.id,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            bodyweightKg: 80, notes: nil
        )
        let newer = ProgressRecord(
            id: IDs.uuid(), userId: profile.id,
            recordedAt: Date(timeIntervalSince1970: 1_710_000_000),
            bodyweightKg: 79, notes: "Cut"
        )
        try await repository.addProgressRecord(older)
        try await repository.addProgressRecord(newer)

        let records = try await repository.listProgressRecords(userId: profile.id)
        XCTAssertEqual(records.map(\.id), [newer.id, older.id])
        try await repository.deleteProgressRecord(id: newer.id)
        let remaining = try await repository.listProgressRecords(userId: profile.id).map(\.id)
        XCTAssertEqual(remaining, [older.id])
    }

    func testReminderSettingsRoundTrip() async throws {
        let profile = makeProfile(name: "Matt")
        try await repository.saveProfile(profile)
        var settings = ReminderSettings.defaults(userId: profile.id)
        settings.enabled = true
        settings.days = [2, 4]
        settings.scheduledIds = ["a", "b"]
        try await repository.saveReminderSettings(settings)
        let stored = try await repository.getReminderSettings(userId: profile.id)
        XCTAssertEqual(stored, settings)
    }

    private func makeProfile(name: String) -> Profile {
        Profile(
            id: IDs.uuid(),
            name: name,
            age: 30,
            experience: .intermediate,
            environment: .both,
            goals: [.strength],
            limitations: nil,
            onboardingCompleted: true,
            createdAt: StoredTimestamp.now()
        )
    }
}
