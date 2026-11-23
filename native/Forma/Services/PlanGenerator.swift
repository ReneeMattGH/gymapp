import Foundation

// MARK: - AI payload contract

struct AIPlanPayload: Decodable, Sendable {
    struct Day: Decodable, Sendable {
        struct Item: Decodable, Sendable {
            var exerciseId: String
            var sets: Int?
            var repsMin: Int?
            var repsMax: Int?
            var restSeconds: Int?
            var notes: String?
        }

        var weekday: Int
        var title: String?
        var focus: [String]?
        var estimatedMinutes: Int?
        var isRestDay: Bool?
        var restNote: String?
        var warmup: [String]?
        var cooldown: [String]?
        var exercises: [Item]?
    }

    var name: String?
    var days: [Day]
}

// MARK: - Generator

enum PlanGenerator {
    private static let slots: [PlanKind: [[MuscleGroup]]] = [
        .full: [
            [.quads, .glutes], [.chest], [.back], [.hamstrings, .glutes], [.core], [.shoulders, .arms], [.fullBody],
        ],
        .upper: [
            [.chest], [.back], [.shoulders], [.arms], [.core], [.back], [.chest, .arms],
        ],
        .lower: [
            [.quads], [.hamstrings, .glutes], [.glutes], [.calves], [.core], [.quads, .hamstrings],
        ],
        .push: [
            [.chest], [.shoulders], [.arms], [.chest], [.core], [.shoulders],
        ],
        .pull: [
            [.back], [.back], [.shoulders], [.arms], [.core], [.back],
        ],
        .legs: [
            [.quads], [.hamstrings], [.glutes], [.calves], [.core], [.quads, .glutes],
        ],
        .mobility: [
            [.back, .hips], [.hips], [.shoulders], [.hamstrings], [.calves], [.back],
        ],
    ]

    private static let meta: [PlanKind: (title: String, focus: [MuscleGroup])] = [
        .full: ("Full body", [.fullBody, .quads, .chest, .back, .core]),
        .upper: ("Upper body", [.chest, .back, .shoulders, .arms, .core]),
        .lower: ("Lower body", [.quads, .hamstrings, .glutes, .calves, .core]),
        .push: ("Push", [.chest, .shoulders, .arms, .core]),
        .pull: ("Pull", [.back, .shoulders, .arms, .core]),
        .legs: ("Legs", [.quads, .hamstrings, .glutes, .calves, .core]),
        .mobility: ("Mobility & recovery", [.hips, .back, .shoulders]),
    ]

    private static let restNotes = [
        "A planned rest day is part of the programme. Walk, stretch gently, or simply recover.",
        "Recovery day — prioritize sleep, food, and easy movement. Training adapts when you rest.",
        "Keep today light. Your next session will be better for it.",
        "Rest is productive. A short walk and some easy mobility is plenty.",
    ]

    static func templateSequence(_ trainingDays: Int) -> [PlanKind] {
        switch trainingDays {
        case ...1: [.full]
        case 2: [.full, .full]
        case 3: [.full, .full, .full]
        case 4: [.upper, .lower, .upper, .lower]
        case 5: [.push, .pull, .legs, .upper, .full]
        case 6: [.push, .pull, .legs, .push, .pull, .legs]
        default: [.push, .pull, .legs, .upper, .lower, .full, .mobility]
        }
    }

    static func evenlySpacedWeekdays(_ count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let gap = 7.0 / Double(count)
        var picks: [Int] = []
        for index in 0..<count {
            picks.append(max(1, min(7, Int((1 + Double(index) * gap).rounded()))))
        }
        var seen = Set<Int>()
        return picks.filter { seen.insert($0).inserted }.prefix(count).map { $0 }
    }

    static func normaliseWeekdays(_ selected: [Int], count: Int) -> [Int] {
        var seen = Set<Int>()
        let valid = selected.filter { (1...7).contains($0) }.filter { seen.insert($0).inserted }.sorted()
        if valid.count >= count { return Array(valid.prefix(count)) }
        var merged = Set(valid)
        for day in evenlySpacedWeekdays(count) { merged.insert(day) }
        return Array(merged.sorted().prefix(count))
    }

    static func exerciseCount(_ minutes: Int) -> Int {
        if minutes <= 20 { return 3 }
        if minutes <= 30 { return 4 }
        if minutes <= 45 { return 5 }
        if minutes <= 60 { return 6 }
        return 7
    }

    static func allowedDifficulties(_ experience: Experience) -> [Difficulty] {
        switch experience {
        case .beginner: [.beginner]
        case .intermediate: [.beginner, .intermediate]
        case .advanced: [.beginner, .intermediate, .advanced]
        }
    }

    static func equipmentAvailable(_ exercise: Exercise, equipment: [Equipment]) -> Bool {
        exercise.equipment.allSatisfy { $0 == .bodyweight || equipment.contains($0) }
    }

    private static func pickExercise(
        slot: [MuscleGroup],
        kind: PlanKind,
        dayIndex: Int,
        slotIndex: Int,
        profile: Profile,
        preferences: Preferences,
        used: Set<String>
    ) -> Exercise? {
        let allowed = Set(allowedDifficulties(profile.experience))
        let category: ExerciseCategory = kind == .mobility ? .mobility : .strength
        let library = ExerciseCatalog.all

        func shared(_ exercise: Exercise) -> Bool {
            !used.contains(exercise.id)
                && !preferences.avoidExercises.contains(exercise.id)
                && equipmentAvailable(exercise, equipment: preferences.equipment)
                && exercise.category == category
                && exercise.primaryMuscles.contains(where: { slot.contains($0) })
        }

        let candidates = library.filter { shared($0) && allowed.contains($0.difficulty) }
        let fallback = library.filter { shared($0) }
        let pool = candidates.isEmpty ? fallback : candidates
        guard !pool.isEmpty else { return nil }
        return pool[(dayIndex + slotIndex) % pool.count]
    }

    static func repRange(_ goal: Goal, experience: Experience) -> (min: Int, max: Int, rest: Int) {
        switch goal {
        case .strength:
            return experience == .beginner ? (8, 10, 90) : (5, 8, 120)
        case .endurance: return (12, 15, 60)
        case .mobility: return (8, 12, 45)
        case .consistency: return (8, 12, 75)
        case .general: return (8, 12, 90)
        }
    }

    static func setCount(_ experience: Experience, index: Int) -> Int {
        let base = experience == .beginner ? 2 : 3
        return index == 0 ? base + (experience == .advanced ? 1 : 0) : base
    }

    static func warmup(_ kind: PlanKind) -> [String] {
        if kind == .mobility {
            return [
                "2–3 minutes of easy walking or gentle marching",
                "Move through each mobility drill slowly; stay well below pain",
            ]
        }
        let lower = kind == .lower || kind == .legs
        let upper = kind == .upper || kind == .push || kind == .pull
        return [
            "5 minutes of easy cardio — walk, bike, or row",
            lower ? "10 leg swings each side and 10 bodyweight squats" : "10 arm circles each direction and 10 shoulder rolls",
            upper ? "One light set of your first exercise" : "10 slow hip hinges and 10 glute bridges",
        ]
    }

    static func cooldown(_ kind: PlanKind) -> [String] {
        if kind == .mobility {
            return [
                "Finish with 3 slow breaths in a comfortable seated position",
                "Drink some water and note how your body feels",
            ]
        }
        return [
            "3–5 minutes of easy walking to bring your heart rate down",
            kind == .lower || kind == .legs
                ? "Hold a gentle hamstring and hip flexor stretch for 30 seconds each side"
                : "Hold a gentle chest and lat stretch for 30 seconds each side",
            "Take a few slow breaths and note your effort for next time",
        ]
    }

    // MARK: Local plan

    static func generateLocalPlan(userId: String, profile: Profile, preferences: Preferences) -> WorkoutPlan? {
        guard !ExerciseCatalog.all.isEmpty else { return nil }

        let trainingDays = max(1, min(7, preferences.workoutDays.isEmpty ? 3 : preferences.workoutDays.count))
        let weekdays = normaliseWeekdays(preferences.workoutDays, count: trainingDays)
        let sequence = templateSequence(trainingDays)
        let goal = profile.goals.first ?? .general
        let count = exerciseCount(preferences.sessionMinutes)
        let planId = IDs.uuid()

        var trainingByWeekday: [Int: (kind: PlanKind, dayIndex: Int)] = [:]
        for (index, weekday) in weekdays.enumerated() {
            trainingByWeekday[weekday] = (sequence.indices.contains(index) ? sequence[index] : .full, index)
        }

        var occurrences: [PlanKind: Int] = [:]
        var days: [WorkoutDay] = []

        for weekday in 1...7 {
            guard let training = trainingByWeekday[weekday] else {
                let note = restNotes[(weekday + days.count) % restNotes.count]
                days.append(WorkoutDay(
                    id: IDs.uuid(),
                    planId: planId,
                    dayIndex: weekday - 1,
                    weekday: weekday,
                    title: "Recovery",
                    focus: [],
                    estimatedMinutes: 0,
                    warmup: [],
                    cooldown: [],
                    isRestDay: true,
                    restNote: note,
                    exercises: []
                ))
                continue
            }

            let kind = training.kind
            let meta = Self.meta[kind] ?? ("Training", [])
            var usedToday = Set<String>()
            var exercises: [WorkoutExercise] = []
            let range = repRange(goal, experience: profile.experience)
            let occurrence = occurrences[kind, default: 0]
            occurrences[kind] = occurrence + 1
            let repeats = sequence.filter { $0 == kind }.count > 1
            let kindSlots = slots[kind] ?? []

            for slotIndex in 0..<min(count, kindSlots.count) {
                guard let exercise = pickExercise(
                    slot: kindSlots[slotIndex],
                    kind: kind,
                    dayIndex: training.dayIndex,
                    slotIndex: slotIndex,
                    profile: profile,
                    preferences: preferences,
                    used: usedToday
                ) else { continue }
                usedToday.insert(exercise.id)
                exercises.append(WorkoutExercise(
                    id: IDs.uuid(),
                    dayId: "",
                    exerciseId: exercise.id,
                    position: exercises.count,
                    sets: setCount(profile.experience, index: slotIndex),
                    repsMin: kind == .mobility ? 5 : range.min,
                    repsMax: kind == .mobility ? 8 : range.max,
                    restSeconds: kind == .mobility ? 30 : range.rest,
                    notes: kind == .mobility
                        ? "Move slowly and breathe. Hold or flow through a comfortable range."
                        : (slotIndex == 0 ? "Leave one or two reps in reserve on the final set." : nil)
                ))
            }

            let dayId = IDs.uuid()
            let title = repeats ? "\(meta.title) · \(String(UnicodeScalar(65 + occurrence)!))" : meta.title
            days.append(WorkoutDay(
                id: dayId,
                planId: planId,
                dayIndex: weekday - 1,
                weekday: weekday,
                title: title,
                focus: meta.focus,
                estimatedMinutes: min(preferences.sessionMinutes, 8 + exercises.count * 6 + 4),
                warmup: warmup(kind),
                cooldown: cooldown(kind),
                isRestDay: false,
                restNote: nil,
                exercises: exercises.enumerated().map { index, item in
                    var copy = item
                    copy.dayId = dayId
                    copy.position = index
                    return copy
                }
            ))
        }

        let baseName: String
        switch profile.experience {
        case .beginner: baseName = "Foundation"
        case .intermediate: baseName = "Momentum"
        case .advanced: baseName = "Apex"
        }

        return WorkoutPlan(
            id: planId,
            userId: userId,
            name: "\(baseName) · \(trainingDays) day\(trainingDays == 1 ? "" : "s")",
            goal: goal,
            experience: profile.experience,
            daysPerWeek: trainingDays,
            sessionMinutes: preferences.sessionMinutes,
            equipment: preferences.equipment,
            source: .onDevice,
            createdAt: StoredTimestamp.now(),
            days: days
        )
    }

    // MARK: AI plan validation

    private static func clamp(_ value: Int?, _ minimum: Int, _ maximum: Int, _ fallback: Int) -> Int {
        let raw = value ?? fallback
        return max(minimum, min(maximum, raw))
    }

    /// Converts an AI payload into a typed plan, discarding unknown exercises and unsafe values.
    static func planFromAIPayload(
        _ payload: AIPlanPayload,
        userId: String,
        profile: Profile,
        preferences: Preferences
    ) -> WorkoutPlan? {
        guard !payload.days.isEmpty else { return nil }
        let planId = IDs.uuid()
        let byWeekday = Dictionary(payload.days.map { (max(1, min(7, $0.weekday)), $0) }, uniquingKeysWith: { first, _ in first })
        let validFocus = Set(MuscleGroup.allCases)
        var days: [WorkoutDay] = []

        for weekday in 1...7 {
            let dayId = IDs.uuid()
            guard let raw = byWeekday[weekday], raw.isRestDay != true else {
                let note = byWeekday[weekday]?.restNote?.trimmingCharacters(in: .whitespacesAndNewlines)
                days.append(WorkoutDay(
                    id: dayId,
                    planId: planId,
                    dayIndex: weekday - 1,
                    weekday: weekday,
                    title: "Recovery",
                    focus: [],
                    estimatedMinutes: 0,
                    warmup: [],
                    cooldown: [],
                    isRestDay: true,
                    restNote: (note?.isEmpty == false ? note : restNotes[weekday % restNotes.count]),
                    exercises: []
                ))
                continue
            }

            var exercises: [WorkoutExercise] = []
            for item in raw.exercises ?? [] {
                guard let libraryExercise = ExerciseCatalog.exercise(item.exerciseId) else { continue }
                var notes = item.notes
                if let notesValue = notes, notesValue.count > 240 {
                    notes = String(notesValue.prefix(240))
                }
                exercises.append(WorkoutExercise(
                    id: IDs.uuid(),
                    dayId: dayId,
                    exerciseId: libraryExercise.id,
                    position: exercises.count,
                    sets: clamp(item.sets, 1, 5, 3),
                    repsMin: clamp(item.repsMin, 3, 30, 8),
                    repsMax: clamp(item.repsMax, 3, 40, 12),
                    restSeconds: clamp(item.restSeconds, 15, 300, 90),
                    notes: notes
                ))
            }

            guard !exercises.isEmpty else {
                days.append(WorkoutDay(
                    id: dayId,
                    planId: planId,
                    dayIndex: weekday - 1,
                    weekday: weekday,
                    title: "Recovery",
                    focus: [],
                    estimatedMinutes: 0,
                    warmup: [],
                    cooldown: [],
                    isRestDay: true,
                    restNote: "Recovery day. The AI plan did not include a safe session here.",
                    exercises: []
                ))
                continue
            }

            let title = (raw.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            let focus = (raw.focus ?? [])
                .compactMap { MuscleGroup(rawValue: $0) }
                .filter { validFocus.contains($0) }
                .prefix(5)
            days.append(WorkoutDay(
                id: dayId,
                planId: planId,
                dayIndex: weekday - 1,
                weekday: weekday,
                title: String((title ?? "Training day").prefix(60)),
                focus: Array(focus),
                estimatedMinutes: clamp(raw.estimatedMinutes, 10, 120, preferences.sessionMinutes),
                warmup: Array((raw.warmup ?? warmup(.full)).prefix(5)),
                cooldown: Array((raw.cooldown ?? cooldown(.full)).prefix(5)),
                isRestDay: false,
                restNote: nil,
                exercises: exercises
            ))
        }

        let trainingDays = days.filter { !$0.isRestDay }.count
        guard trainingDays > 0 else { return nil }

        let trimmedName = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmedName?.isEmpty == false)
            ? String(trimmedName!.prefix(60))
            : "\((profile.experience == .beginner ? "Foundation" : "Momentum")) · \(trainingDays) days"

        return WorkoutPlan(
            id: planId,
            userId: userId,
            name: name,
            goal: profile.goals.first ?? .general,
            experience: profile.experience,
            daysPerWeek: trainingDays,
            sessionMinutes: preferences.sessionMinutes,
            equipment: preferences.equipment,
            source: .ai,
            createdAt: StoredTimestamp.now(),
            days: days
        )
    }

    // MARK: Helpers

    static func planForDate(_ plan: WorkoutPlan, date: Date) -> WorkoutDay? {
        let weekday = Weekday.isoWeekday(date)
        return plan.days.first { $0.weekday == weekday }
    }

    static func nextTrainingDay(_ plan: WorkoutPlan, from date: Date) -> WorkoutDay? {
        let todayIndex = Weekday.isoWeekday(date) - 1
        for offset in 1...7 {
            let index = ((todayIndex + offset) % 7 + 7) % 7
            guard plan.days.indices.contains(index) else { continue }
            let day = plan.days[index]
            if !day.isRestDay { return day }
        }
        return nil
    }

    static func exerciseName(_ id: String) -> String {
        ExerciseCatalog.name(id)
    }
}
