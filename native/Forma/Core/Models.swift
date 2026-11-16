import Foundation

// MARK: - Enumerations

enum Experience: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var label: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }
}

enum TrainingEnvironment: String, Codable, CaseIterable, Identifiable, Sendable {
    case gym, home, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gym: "Gym"
        case .home: "Home"
        case .both: "Both"
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength, endurance, mobility, general, consistency
    var id: String { rawValue }
    var label: String {
        switch self {
        case .strength: "Build strength"
        case .endurance: "Improve endurance"
        case .mobility: "Move better"
        case .general: "General fitness"
        case .consistency: "Build consistency"
        }
    }
    var shortLabel: String {
        switch self {
        case .strength: "Strength"
        case .endurance: "Endurance"
        case .mobility: "Mobility"
        case .general: "General"
        case .consistency: "Consistency"
        }
    }
    var icon: String {
        switch self {
        case .strength: "figure.strengthtraining.traditional"
        case .endurance: "figure.run"
        case .mobility: "figure.flexibility"
        case .general: "figure.mixed.cardio"
        case .consistency: "calendar"
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case bodyweight
    case dumbbells
    case barbell
    case kettlebell
    case resistanceBand = "resistance-band"
    case cable
    case machine
    case bench
    case pullUpBar = "pull-up-bar"
    case jumpRope = "jump-rope"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .bodyweight: "Bodyweight"
        case .dumbbells: "Dumbbells"
        case .barbell: "Barbell"
        case .kettlebell: "Kettlebell"
        case .resistanceBand: "Resistance bands"
        case .cable: "Cable station"
        case .machine: "Machines"
        case .bench: "Bench"
        case .pullUpBar: "Pull-up bar"
        case .jumpRope: "Jump rope"
        }
    }
}

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength, conditioning, mobility
    var id: String { rawValue }
    var label: String {
        switch self {
        case .strength: "Strength"
        case .conditioning: "Conditioning"
        case .mobility: "Mobility"
        }
    }
}

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, shoulders, arms, quads, hamstrings, glutes, calves, core, hips
    case fullBody = "full-body"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .core: "Core"
        case .hips: "Hips"
        case .fullBody: "Full body"
        }
    }
}

enum Difficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum PlanSource: String, Codable, Sendable {
    case ai
    case onDevice = "on-device"
    var label: String { self == .ai ? "AI generated" : "On-device" }
}

enum SessionStatus: String, Codable, Sendable {
    case active, paused, completed, abandoned
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case kg, lb
    var id: String { rawValue }
    var label: String { self == .kg ? "Kilograms" : "Pounds" }
    var abbreviation: String { rawValue }
}

enum PlanKind: String, Codable, Sendable {
    case full, upper, lower, push, pull, legs, mobility
}

enum WorkoutRunStatus: String, Codable, Sendable {
    case active, paused
}

enum RepositoryKind: String, Sendable {
    case supabase, preview
}

// MARK: - Domain models

struct Profile: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var age: Int?
    var experience: Experience
    var environment: TrainingEnvironment
    var goals: [Goal]
    var limitations: String?
    var onboardingCompleted: Bool
    var createdAt: Date

    init(
        id: String,
        name: String,
        age: Int?,
        experience: Experience,
        environment: TrainingEnvironment,
        goals: [Goal],
        limitations: String?,
        onboardingCompleted: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.experience = experience
        self.environment = environment
        self.goals = goals
        self.limitations = limitations
        self.onboardingCompleted = onboardingCompleted
        self.createdAt = createdAt
    }
}

struct Preferences: Codable, Equatable, Sendable {
    var userId: String
    var workoutDays: [Int]
    var sessionMinutes: Int
    var equipment: [Equipment]
    var avoidExercises: [String]
    var reminderTime: String
    var units: UnitSystem

    init(
        userId: String,
        workoutDays: [Int] = [1, 3, 5],
        sessionMinutes: Int = 45,
        equipment: [Equipment] = [.bodyweight, .dumbbells, .bench],
        avoidExercises: [String] = [],
        reminderTime: String = "18:00",
        units: UnitSystem = .kg
    ) {
        self.userId = userId
        self.workoutDays = workoutDays
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.avoidExercises = avoidExercises
        self.reminderTime = reminderTime
        self.units = units
    }
}

struct Exercise: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var category: ExerciseCategory
    var primaryMuscles: [MuscleGroup]
    var secondaryMuscles: [MuscleGroup]
    var equipment: [Equipment]
    var difficulty: Difficulty
    var instructions: [String]
    var cues: [String]
    var mistakes: [String]
    var alternatives: [String]
    var isUnilateral: Bool
    /// Where this record came from. Shown in the library so provenance is never invented.
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, category, primaryMuscles, secondaryMuscles, equipment
        case difficulty, instructions, cues, mistakes, alternatives, isUnilateral, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(ExerciseCategory.self, forKey: .category)
        primaryMuscles = try container.decodeIfPresent([MuscleGroup].self, forKey: .primaryMuscles) ?? []
        secondaryMuscles = try container.decodeIfPresent([MuscleGroup].self, forKey: .secondaryMuscles) ?? []
        equipment = try container.decodeIfPresent([Equipment].self, forKey: .equipment) ?? []
        difficulty = try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .beginner
        instructions = try container.decodeIfPresent([String].self, forKey: .instructions) ?? []
        cues = try container.decodeIfPresent([String].self, forKey: .cues) ?? []
        mistakes = try container.decodeIfPresent([String].self, forKey: .mistakes) ?? []
        alternatives = try container.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        isUnilateral = try container.decodeIfPresent(Bool.self, forKey: .isUnilateral) ?? false
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    init(
        id: String,
        name: String,
        category: ExerciseCategory,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup],
        equipment: [Equipment],
        difficulty: Difficulty,
        instructions: [String],
        cues: [String],
        mistakes: [String],
        alternatives: [String],
        isUnilateral: Bool,
        source: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.difficulty = difficulty
        self.instructions = instructions
        self.cues = cues
        self.mistakes = mistakes
        self.alternatives = alternatives
        self.isUnilateral = isUnilateral
        self.source = source
    }
}

struct WorkoutExercise: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var dayId: String
    var exerciseId: String
    var position: Int
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    var restSeconds: Int
    var notes: String?
}

struct WorkoutDay: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var planId: String
    var dayIndex: Int
    var weekday: Int?
    var title: String
    var focus: [MuscleGroup]
    var estimatedMinutes: Int
    var warmup: [String]
    var cooldown: [String]
    var isRestDay: Bool
    var restNote: String?
    var exercises: [WorkoutExercise]
}

struct WorkoutPlan: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var userId: String
    var name: String
    var goal: Goal
    var experience: Experience
    var daysPerWeek: Int
    var sessionMinutes: Int
    var equipment: [Equipment]
    var source: PlanSource
    var createdAt: Date
    var days: [WorkoutDay]

    var trainingDays: [WorkoutDay] { days.filter { !$0.isRestDay } }
    var totalExercises: Int { days.reduce(0) { $0 + $1.exercises.count } }
}

struct CompletedSet: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var sessionId: String
    var workoutExerciseId: String?
    var exerciseId: String
    var setNumber: Int
    var reps: Int
    var weightKg: Double?
    var completedAt: Date
}

struct WorkoutSession: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var userId: String
    var planDayId: String?
    var title: String
    var focus: [MuscleGroup]
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var status: SessionStatus
    var sets: [CompletedSet]
    var notes: String?

    var isCompleted: Bool { status == .completed && endedAt != nil }
}

struct ReminderSettings: Codable, Equatable, Sendable {
    var userId: String
    var enabled: Bool
    var workoutTime: String
    var days: [Int]
    var restDayReminders: Bool
    var hydrationReminders: Bool
    var weeklyProgressReminder: Bool
    var scheduledIds: [String]

    static func defaults(userId: String) -> ReminderSettings {
        ReminderSettings(
            userId: userId,
            enabled: false,
            workoutTime: "18:00",
            days: [1, 3, 5],
            restDayReminders: true,
            hydrationReminders: false,
            weeklyProgressReminder: true,
            scheduledIds: []
        )
    }
}

struct CoachConversation: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var userId: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
}

struct CoachMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant
    }

    var id: String
    var conversationId: String
    var userId: String
    var role: Role
    var content: String
    var createdAt: Date
    /// Verified library entries that grounded an assistant reply.
    var sources: [CoachSource]

    init(
        id: String,
        conversationId: String,
        userId: String,
        role: Role,
        content: String,
        createdAt: Date,
        sources: [CoachSource] = []
    ) {
        self.id = id
        self.conversationId = conversationId
        self.userId = userId
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case id, conversationId, userId, role, content, createdAt, sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        userId = try container.decode(String.self, forKey: .userId)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sources = try container.decodeIfPresent([CoachSource].self, forKey: .sources) ?? []
    }
}

struct CoachSource: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var category: String
}

struct ProgressRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var userId: String
    var recordedAt: Date
    var bodyweightKg: Double?
    var notes: String?
}

struct AppUser: Identifiable, Equatable, Sendable {
    var id: String
    var email: String?
}

// MARK: - Active workout

struct ActiveRest: Codable, Hashable, Sendable {
    var endsAt: Date?
    var durationSeconds: Int
    var pausedRemaining: Int?
    var exerciseId: String

    func remaining(at date: Date) -> Int {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(date).rounded(.up)))
    }

    var isPaused: Bool { pausedRemaining != nil }
}

struct ActiveWorkout: Codable, Equatable, Sendable {
    var sessionId: String
    var userId: String
    var planDayId: String
    var planId: String
    var title: String
    var focus: [MuscleGroup]
    var warmup: [String]
    var cooldown: [String]
    var startedAt: Date
    var status: WorkoutRunStatus
    var pausedAt: Date?
    var pausedSeconds: Int
    var currentExerciseIndex: Int
    var exercises: [WorkoutExercise]
    var sets: [CompletedSet]
    var rest: ActiveRest?

    func elapsedSeconds(at date: Date) -> Int {
        var elapsed = date.timeIntervalSince(startedAt) - Double(pausedSeconds)
        if status == .paused, let pausedAt {
            elapsed -= date.timeIntervalSince(pausedAt)
        }
        return max(0, Int(elapsed.rounded(.down)))
    }

    var currentExercise: WorkoutExercise? {
        guard exercises.indices.contains(currentExerciseIndex) else { return nil }
        return exercises[currentExerciseIndex]
    }

    func sets(for exercise: WorkoutExercise) -> [CompletedSet] {
        sets.filter { $0.exerciseId == exercise.exerciseId && $0.workoutExerciseId == exercise.id }
    }

    var totalPlannedSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    func allSetsComplete(for exercise: WorkoutExercise) -> Bool {
        sets(for: exercise).count >= exercise.sets
    }

    var isComplete: Bool {
        exercises.allSatisfy { allSetsComplete(for: $0) }
    }
}

// MARK: - Labels & helpers

enum Weekday {
    static let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func short(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "—" }
        return names[weekday - 1]
    }

    static func isoWeekday(_ date: Date, calendar: Calendar = .current) -> Int {
        let component = calendar.component(.weekday, from: date)
        return component == 1 ? 7 : component - 1
    }
}

func weekdayShort(_ weekday: Int) -> String { Weekday.short(weekday) }
