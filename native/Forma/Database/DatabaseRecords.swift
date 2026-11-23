import Foundation
import GRDB

// Row types mirror the SQLite schema one-to-one. Array-valued columns are
// JSON text; scalar columns are indexed and constrained in the schema.

private func decodeEnum<T: RawRepresentable>(_ type: T.Type, _ raw: String, field: String) throws -> T
where T.RawValue == String {
    guard let value = T(rawValue: raw) else {
        throw DatabaseFailure.corruptValue(field: field, value: raw)
    }
    return value
}

struct ProfileRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "profiles"

    private enum CodingKeys: String, CodingKey {
        case id, name, age, experience, environment, goals, limitations, photoPath = "photo_path"
        case onboardingCompleted = "onboarding_completed", createdAt = "created_at"
    }

    var id: String
    var name: String
    var age: Int?
    var experience: String
    var environment: String
    var goals: String
    var limitations: String?
    var photoPath: String?
    var onboardingCompleted: Bool
    var createdAt: Date

    init(profile: Profile) throws {
        id = profile.id
        name = profile.name
        age = profile.age
        experience = profile.experience.rawValue
        environment = profile.environment.rawValue
        goals = try RecordCoding.encodeJSON(profile.goals)
        limitations = profile.limitations
        photoPath = profile.photoPath
        onboardingCompleted = profile.onboardingCompleted
        createdAt = profile.createdAt
    }

    func toDomain() throws -> Profile {
        Profile(
            id: id,
            name: name,
            age: age,
            experience: try decodeEnum(Experience.self, experience, field: "profiles.experience"),
            environment: try decodeEnum(TrainingEnvironment.self, environment, field: "profiles.environment"),
            goals: try RecordCoding.decodeJSON([Goal].self, from: goals, field: "profiles.goals"),
            limitations: limitations,
            photoPath: photoPath,
            onboardingCompleted: onboardingCompleted,
            createdAt: createdAt
        )
    }
}

struct PreferencesRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "user_preferences"

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id", workoutDays = "workout_days", sessionMinutes = "session_minutes"
        case equipment, avoidExercises = "avoid_exercises", reminderTime = "reminder_time", units
        case updatedAt = "updated_at"
    }

    var userId: String
    var workoutDays: String
    var sessionMinutes: Int
    var equipment: String
    var avoidExercises: String
    var reminderTime: String
    var units: String
    var updatedAt: Date

    init(preferences: Preferences, updatedAt: Date = StoredTimestamp.now()) throws {
        userId = preferences.userId
        workoutDays = try RecordCoding.encodeJSON(preferences.workoutDays)
        sessionMinutes = preferences.sessionMinutes
        equipment = try RecordCoding.encodeJSON(preferences.equipment)
        avoidExercises = try RecordCoding.encodeJSON(preferences.avoidExercises)
        reminderTime = preferences.reminderTime
        units = preferences.units.rawValue
        self.updatedAt = updatedAt
    }

    func toDomain() throws -> Preferences {
        Preferences(
            userId: userId,
            workoutDays: try RecordCoding.decodeJSON([Int].self, from: workoutDays, field: "user_preferences.workout_days"),
            sessionMinutes: sessionMinutes,
            equipment: try RecordCoding.decodeJSON([Equipment].self, from: equipment, field: "user_preferences.equipment"),
            avoidExercises: try RecordCoding.decodeJSON([String].self, from: avoidExercises, field: "user_preferences.avoid_exercises"),
            reminderTime: reminderTime,
            units: try decodeEnum(UnitSystem.self, units, field: "user_preferences.units")
        )
    }
}

struct ExerciseRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "exercise_library"

    private enum CodingKeys: String, CodingKey {
        case id, name, category, primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles", equipment, difficulty, instructions, cues
        case mistakes, alternatives, isUnilateral = "is_unilateral", source, position
    }

    var id: String
    var name: String
    var category: String
    var primaryMuscles: String
    var secondaryMuscles: String
    var equipment: String
    var difficulty: String
    var instructions: String
    var cues: String
    var mistakes: String
    var alternatives: String
    var isUnilateral: Bool
    var source: String?
    var position: Int

    func toDomain() throws -> Exercise {
        Exercise(
            id: id,
            name: name,
            category: try decodeEnum(ExerciseCategory.self, category, field: "exercise_library.category"),
            primaryMuscles: try RecordCoding.decodeJSON([MuscleGroup].self, from: primaryMuscles, field: "exercise_library.primary_muscles"),
            secondaryMuscles: try RecordCoding.decodeJSON([MuscleGroup].self, from: secondaryMuscles, field: "exercise_library.secondary_muscles"),
            equipment: try RecordCoding.decodeJSON([Equipment].self, from: equipment, field: "exercise_library.equipment"),
            difficulty: try decodeEnum(Difficulty.self, difficulty, field: "exercise_library.difficulty"),
            instructions: try RecordCoding.decodeJSON([String].self, from: instructions, field: "exercise_library.instructions"),
            cues: try RecordCoding.decodeJSON([String].self, from: cues, field: "exercise_library.cues"),
            mistakes: try RecordCoding.decodeJSON([String].self, from: mistakes, field: "exercise_library.mistakes"),
            alternatives: try RecordCoding.decodeJSON([String].self, from: alternatives, field: "exercise_library.alternatives"),
            isUnilateral: isUnilateral,
            source: source
        )
    }
}

struct PlanRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_plans"

    private enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", name, goal, experience, daysPerWeek = "days_per_week"
        case sessionMinutes = "session_minutes", equipment, source, createdAt = "created_at"
    }

    var id: String
    var userId: String
    var name: String
    var goal: String
    var experience: String
    var daysPerWeek: Int
    var sessionMinutes: Int
    var equipment: String
    var source: String
    var createdAt: Date

    init(plan: WorkoutPlan) throws {
        id = plan.id
        userId = plan.userId
        name = plan.name
        goal = plan.goal.rawValue
        experience = plan.experience.rawValue
        daysPerWeek = plan.daysPerWeek
        sessionMinutes = plan.sessionMinutes
        equipment = try RecordCoding.encodeJSON(plan.equipment)
        source = plan.source.rawValue
        createdAt = plan.createdAt
    }

    func toDomain(days: [WorkoutDay]) throws -> WorkoutPlan {
        WorkoutPlan(
            id: id,
            userId: userId,
            name: name,
            goal: try decodeEnum(Goal.self, goal, field: "workout_plans.goal"),
            experience: try decodeEnum(Experience.self, experience, field: "workout_plans.experience"),
            daysPerWeek: daysPerWeek,
            sessionMinutes: sessionMinutes,
            equipment: try RecordCoding.decodeJSON([Equipment].self, from: equipment, field: "workout_plans.equipment"),
            source: try decodeEnum(PlanSource.self, source, field: "workout_plans.source"),
            createdAt: createdAt,
            days: days
        )
    }
}

struct DayRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_days"

    private enum CodingKeys: String, CodingKey {
        case id, planId = "plan_id", dayIndex = "day_index", weekday, title, focus
        case estimatedMinutes = "estimated_minutes", warmup, cooldown, isRestDay = "is_rest_day"
        case restNote = "rest_note"
    }

    var id: String
    var planId: String
    var dayIndex: Int
    var weekday: Int?
    var title: String
    var focus: String
    var estimatedMinutes: Int
    var warmup: String
    var cooldown: String
    var isRestDay: Bool
    var restNote: String?

    init(day: WorkoutDay) throws {
        id = day.id
        planId = day.planId
        dayIndex = day.dayIndex
        weekday = day.weekday
        title = day.title
        focus = try RecordCoding.encodeJSON(day.focus)
        estimatedMinutes = day.estimatedMinutes
        warmup = try RecordCoding.encodeJSON(day.warmup)
        cooldown = try RecordCoding.encodeJSON(day.cooldown)
        isRestDay = day.isRestDay
        restNote = day.restNote
    }

    func toDomain(exercises: [WorkoutExercise]) throws -> WorkoutDay {
        WorkoutDay(
            id: id,
            planId: planId,
            dayIndex: dayIndex,
            weekday: weekday,
            title: title,
            focus: try RecordCoding.decodeJSON([MuscleGroup].self, from: focus, field: "workout_days.focus"),
            estimatedMinutes: estimatedMinutes,
            warmup: try RecordCoding.decodeJSON([String].self, from: warmup, field: "workout_days.warmup"),
            cooldown: try RecordCoding.decodeJSON([String].self, from: cooldown, field: "workout_days.cooldown"),
            isRestDay: isRestDay,
            restNote: restNote,
            exercises: exercises
        )
    }
}

struct PlanExerciseRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_exercises"

    private enum CodingKeys: String, CodingKey {
        case id, dayId = "day_id", exerciseId = "exercise_id", position, sets
        case repsMin = "reps_min", repsMax = "reps_max", restSeconds = "rest_seconds", notes
    }

    var id: String
    var dayId: String
    var exerciseId: String
    var position: Int
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    var restSeconds: Int
    var notes: String?

    init(exercise: WorkoutExercise) {
        id = exercise.id
        dayId = exercise.dayId
        exerciseId = exercise.exerciseId
        position = exercise.position
        sets = exercise.sets
        repsMin = exercise.repsMin
        repsMax = exercise.repsMax
        restSeconds = exercise.restSeconds
        notes = exercise.notes
    }

    func toDomain() -> WorkoutExercise {
        WorkoutExercise(
            id: id,
            dayId: dayId,
            exerciseId: exerciseId,
            position: position,
            sets: sets,
            repsMin: repsMin,
            repsMax: repsMax,
            restSeconds: restSeconds,
            notes: notes
        )
    }
}

struct SessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_sessions"

    private enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", planDayId = "plan_day_id", title, focus
        case startedAt = "started_at", endedAt = "ended_at", durationSeconds = "duration_seconds"
        case status, notes, formAnalysis = "form_analysis"
    }

    var id: String
    var userId: String
    var planDayId: String?
    var title: String
    var focus: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var status: String
    var notes: String?
    var formAnalysis: String?

    init(session: WorkoutSession) throws {
        id = session.id
        userId = session.userId
        planDayId = session.planDayId
        title = session.title
        focus = try RecordCoding.encodeJSON(session.focus)
        startedAt = session.startedAt
        endedAt = session.endedAt
        durationSeconds = session.durationSeconds
        status = session.status.rawValue
        notes = session.notes
        formAnalysis = try session.formAnalysis.map { try RecordCoding.encodeJSON($0) }
    }

    func toDomain(sets: [CompletedSet]) throws -> WorkoutSession {
        WorkoutSession(
            id: id,
            userId: userId,
            planDayId: planDayId,
            title: title,
            focus: try RecordCoding.decodeJSON([MuscleGroup].self, from: focus, field: "workout_sessions.focus"),
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            status: try decodeEnum(SessionStatus.self, status, field: "workout_sessions.status"),
            sets: sets,
            notes: notes,
            formAnalysis: try formAnalysis.map {
                try RecordCoding.decodeJSON(FormAnalysisRecord.self, from: $0, field: "workout_sessions.form_analysis")
            }
        )
    }
}

struct CompletedSetRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "completed_sets"

    private enum CodingKeys: String, CodingKey {
        case id, sessionId = "session_id", workoutExerciseId = "workout_exercise_id"
        case exerciseId = "exercise_id", setNumber = "set_number", reps, weightKg = "weight_kg"
        case completedAt = "completed_at"
    }

    var id: String
    var sessionId: String
    var workoutExerciseId: String?
    var exerciseId: String
    var setNumber: Int
    var reps: Int
    var weightKg: Double?
    var completedAt: Date

    init(set: CompletedSet) {
        id = set.id
        sessionId = set.sessionId
        workoutExerciseId = set.workoutExerciseId
        exerciseId = set.exerciseId
        setNumber = set.setNumber
        reps = set.reps
        weightKg = set.weightKg
        completedAt = set.completedAt
    }

    func toDomain() -> CompletedSet {
        CompletedSet(
            id: id,
            sessionId: sessionId,
            workoutExerciseId: workoutExerciseId,
            exerciseId: exerciseId,
            setNumber: setNumber,
            reps: reps,
            weightKg: weightKg,
            completedAt: completedAt
        )
    }
}

struct ProgressEntryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "progress_records"

    private enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", recordedAt = "recorded_at", bodyweightKg = "bodyweight_kg"
        case notes
    }

    var id: String
    var userId: String
    var recordedAt: Date
    var bodyweightKg: Double?
    var notes: String?

    init(record: ProgressRecord) {
        id = record.id
        userId = record.userId
        recordedAt = record.recordedAt
        bodyweightKg = record.bodyweightKg
        notes = record.notes
    }

    func toDomain() -> ProgressRecord {
        ProgressRecord(
            id: id,
            userId: userId,
            recordedAt: recordedAt,
            bodyweightKg: bodyweightKg,
            notes: notes
        )
    }
}

struct ReminderRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reminder_settings"

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id", enabled, workoutTime = "workout_time", days
        case restDayReminders = "rest_day_reminders", hydrationReminders = "hydration_reminders"
        case weeklyProgressReminder = "weekly_progress_reminder", scheduledIds = "scheduled_ids"
    }

    var userId: String
    var enabled: Bool
    var workoutTime: String
    var days: String
    var restDayReminders: Bool
    var hydrationReminders: Bool
    var weeklyProgressReminder: Bool
    var scheduledIds: String

    init(settings: ReminderSettings) throws {
        userId = settings.userId
        enabled = settings.enabled
        workoutTime = settings.workoutTime
        days = try RecordCoding.encodeJSON(settings.days)
        restDayReminders = settings.restDayReminders
        hydrationReminders = settings.hydrationReminders
        weeklyProgressReminder = settings.weeklyProgressReminder
        scheduledIds = try RecordCoding.encodeJSON(settings.scheduledIds)
    }

    func toDomain() throws -> ReminderSettings {
        ReminderSettings(
            userId: userId,
            enabled: enabled,
            workoutTime: workoutTime,
            days: try RecordCoding.decodeJSON([Int].self, from: days, field: "reminder_settings.days"),
            restDayReminders: restDayReminders,
            hydrationReminders: hydrationReminders,
            weeklyProgressReminder: weeklyProgressReminder,
            scheduledIds: try RecordCoding.decodeJSON([String].self, from: scheduledIds, field: "reminder_settings.scheduled_ids")
        )
    }
}

struct AppSettingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_settings"

    private enum CodingKeys: String, CodingKey {
        case key, value, updatedAt = "updated_at"
    }

    var key: String
    var value: String?
    var updatedAt: Date
}
