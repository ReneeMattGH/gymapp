import Foundation
import GRDB

/// Device-local repository. Every personal record is stored in SQLite on this
/// device; nothing here talks to a server.
actor LocalRepository: FormaRepository {
    nonisolated let kind: RepositoryKind = .local

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    private var writer: any DatabaseWriter { database.writer }

    // MARK: - Profiles

    func getExercises() async throws -> [Exercise] {
        try await writer.read { db in
            try ExerciseRecord
                .order(Column("position"))
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    func listProfiles() async throws -> [Profile] {
        try await writer.read { db in
            try ProfileRecord
                .order(Column("created_at"))
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    func getProfile(userId: String) async throws -> Profile? {
        try await writer.read { db in
            try ProfileRecord.fetchOne(db, key: userId)?.toDomain()
        }
    }

    func saveProfile(_ profile: Profile) async throws {
        let record = try ProfileRecord(profile: profile)
        try await writer.write { db in
            try record.save(db)
        }
    }

    /// Deleting a profile cascades to preferences, plans, sessions, sets,
    /// progress records and reminders through the schema's foreign keys.
    func deleteProfile(userId: String) async throws {
        _ = try await writer.write { db in
            try ProfileRecord.deleteOne(db, key: userId)
        }
    }

    // MARK: - Preferences

    func getPreferences(userId: String) async throws -> Preferences? {
        try await writer.read { db in
            try PreferencesRecord.fetchOne(db, key: userId)?.toDomain()
        }
    }

    func savePreferences(_ preferences: Preferences) async throws {
        let record = try PreferencesRecord(preferences: preferences)
        try await writer.write { db in
            try record.save(db)
        }
    }

    // MARK: - Plans

    func getActivePlan(userId: String) async throws -> WorkoutPlan? {
        try await writer.read { db in
            guard let planRow = try PlanRecord
                .filter(Column("user_id") == userId)
                .order(Column("created_at").desc)
                .fetchOne(db) else { return nil }

            let days = try DayRecord
                .filter(Column("plan_id") == planRow.id)
                .order(Column("day_index"))
                .fetchAll(db)
                .map { dayRow in
                    let exercises = try PlanExerciseRecord
                        .filter(Column("day_id") == dayRow.id)
                        .order(Column("position"))
                        .fetchAll(db)
                        .map { $0.toDomain() }
                    return try dayRow.toDomain(exercises: exercises)
                }
            return try planRow.toDomain(days: days)
        }
    }

    /// The newest plan is the active one, so saving a plan archives the rest
    /// in a single transaction; sessions keep their history and lose only the
    /// day reference.
    func savePlan(_ plan: WorkoutPlan) async throws {
        let planRecord = try PlanRecord(plan: plan)
        let dayRecords = try plan.days.map { try DayRecord(day: $0) }
        let exerciseRecords = plan.days.flatMap { $0.exercises.map(PlanExerciseRecord.init) }
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM workout_plans WHERE user_id = ?", arguments: [plan.userId])
            try planRecord.insert(db)
            for day in dayRecords { try day.insert(db) }
            for exercise in exerciseRecords { try exercise.insert(db) }
        }
    }

    // MARK: - Sessions

    func getSessions(userId: String) async throws -> [WorkoutSession] {
        try await writer.read { db in
            let sessionRows = try SessionRecord
                .filter(Column("user_id") == userId)
                .order(Column("started_at").desc)
                .fetchAll(db)
            let setRows = try CompletedSetRecord.fetchAll(db, sql: """
                SELECT completed_sets.* FROM completed_sets
                JOIN workout_sessions ON workout_sessions.id = completed_sets.session_id
                WHERE workout_sessions.user_id = ?
                ORDER BY completed_sets.completed_at
                """, arguments: [userId])
            let setsBySession = Dictionary(grouping: setRows, by: \.sessionId)
            return try sessionRows.map { row in
                try row.toDomain(sets: (setsBySession[row.id] ?? []).map { $0.toDomain() })
            }
        }
    }

    func getSession(id: String) async throws -> WorkoutSession? {
        try await writer.read { db in
            guard let row = try SessionRecord.fetchOne(db, key: id) else { return nil }
            let sets = try CompletedSetRecord
                .filter(Column("session_id") == id)
                .order(Column("completed_at"))
                .fetchAll(db)
                .map { $0.toDomain() }
            return try row.toDomain(sets: sets)
        }
    }

    func saveSession(_ session: WorkoutSession) async throws {
        let sessionRecord = try SessionRecord(session: session)
        let setRecords = session.sets.map(CompletedSetRecord.init)
        let sessionId = session.id
        try await writer.write { db in
            try sessionRecord.save(db)
            _ = try CompletedSetRecord
                .filter(Column("session_id") == sessionId)
                .deleteAll(db)
            for set in setRecords { try set.insert(db) }
        }
    }

    // MARK: - Reminders

    func getReminderSettings(userId: String) async throws -> ReminderSettings? {
        try await writer.read { db in
            try ReminderRecord.fetchOne(db, key: userId)?.toDomain()
        }
    }

    func saveReminderSettings(_ settings: ReminderSettings) async throws {
        let record = try ReminderRecord(settings: settings)
        try await writer.write { db in
            try record.save(db)
        }
    }

    // MARK: - Progress

    func listProgressRecords(userId: String) async throws -> [ProgressRecord] {
        try await writer.read { db in
            try ProgressEntryRecord
                .filter(Column("user_id") == userId)
                .order(Column("recorded_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    func addProgressRecord(_ record: ProgressRecord) async throws {
        let entry = ProgressEntryRecord(record: record)
        try await writer.write { db in
            try entry.insert(db)
        }
    }

    func deleteProgressRecord(id: String) async throws {
        _ = try await writer.write { db in
            try ProgressEntryRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - App settings

    func activeProfileID() async throws -> String? {
        try await writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_settings WHERE key = ?", arguments: [AppSettingKey.activeProfile])
        }
    }

    func setActiveProfileID(_ id: String?) async throws {
        try await writer.write { db in
            if let id {
                try AppSettingRecord(key: AppSettingKey.activeProfile, value: id, updatedAt: StoredTimestamp.now()).save(db)
            } else {
                _ = try AppSettingRecord.deleteOne(db, key: AppSettingKey.activeProfile)
            }
        }
    }
}

enum AppSettingKey {
    static let activeProfile = "active_profile_id"
    static let pendingProfile = "pending_profile_id"
}
