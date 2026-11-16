import XCTest
@testable import Forma

final class PlanValidatorTests: XCTestCase {
    private let squat = Exercise(
        id: "bodyweight-squat",
        name: "Bodyweight Squat",
        category: .strength,
        primaryMuscles: [.quads],
        secondaryMuscles: [.glutes],
        equipment: [.bodyweight],
        difficulty: .beginner,
        instructions: [],
        cues: [],
        mistakes: [],
        alternatives: [],
        isUnilateral: false
    )

    private let pushUp = Exercise(
        id: "push-up",
        name: "Push-Up",
        category: .strength,
        primaryMuscles: [.chest],
        secondaryMuscles: [.arms],
        equipment: [.bodyweight],
        difficulty: .beginner,
        instructions: [],
        cues: [],
        mistakes: [],
        alternatives: [],
        isUnilateral: false
    )

    private let cableRow = Exercise(
        id: "cable-row",
        name: "Cable Row",
        category: .strength,
        primaryMuscles: [.back],
        secondaryMuscles: [.arms],
        equipment: [.cable],
        difficulty: .intermediate,
        instructions: [],
        cues: [],
        mistakes: [],
        alternatives: [],
        isUnilateral: false
    )

    private var catalog: [Exercise] { [squat, pushUp, cableRow] }

    private var profile: Profile {
        Profile(
            id: "user-1",
            name: "Test",
            age: 30,
            experience: .beginner,
            environment: .home,
            goals: [.general],
            limitations: nil,
            onboardingCompleted: true,
            createdAt: Date()
        )
    }

    private func preferences(
        days: [Int] = [1, 3, 5],
        minutes: Int = 45,
        equipment: [Equipment] = [.bodyweight],
        avoid: [String] = []
    ) -> Preferences {
        Preferences(
            userId: "user-1",
            workoutDays: days,
            sessionMinutes: minutes,
            equipment: equipment,
            avoidExercises: avoid
        )
    }

    private func item(_ id: String, sets: Int = 3, reps: ClosedRange<Int> = 8...12, rest: Int = 60) -> WorkoutExercise {
        WorkoutExercise(
            id: UUID().uuidString,
            dayId: "day",
            exerciseId: id,
            position: 0,
            sets: sets,
            repsMin: reps.lowerBound,
            repsMax: reps.upperBound,
            restSeconds: rest,
            notes: nil
        )
    }

    private func plan(
        trainingDays: [Int] = [1, 3, 5],
        minutes: Int = 45,
        exercises: [WorkoutExercise]? = nil,
        restDayExercises: [WorkoutExercise] = []
    ) -> WorkoutPlan {
        let chosen = exercises ?? [item("bodyweight-squat"), item("push-up")]
        var days: [WorkoutDay] = []
        for weekday in 1...7 {
            let training = trainingDays.contains(weekday)
            days.append(WorkoutDay(
                id: "day-\(weekday)",
                planId: "plan-1",
                dayIndex: weekday - 1,
                weekday: weekday,
                title: training ? "Full body" : "Rest",
                focus: training ? [.fullBody] : [],
                estimatedMinutes: training ? minutes : 0,
                warmup: [],
                cooldown: [],
                isRestDay: !training,
                restNote: training ? nil : "Easy day",
                exercises: training ? chosen : restDayExercises
            ))
        }
        return WorkoutPlan(
            id: "plan-1",
            userId: "user-1",
            name: "Test plan",
            goal: .general,
            experience: .beginner,
            daysPerWeek: trainingDays.count,
            sessionMinutes: minutes,
            equipment: [.bodyweight],
            source: .ai,
            createdAt: Date(),
            days: days
        )
    }

    func testValidPlanHasNoErrors() {
        let issues = PlanValidator.issues(
            for: plan(),
            profile: profile,
            preferences: preferences(),
            catalog: catalog
        )
        XCTAssertNil(PlanValidator.firstError(in: issues), "Unexpected errors: \(issues)")
    }

    func testUnknownExerciseIsRejected() {
        let issues = PlanValidator.structureIssues(
            plan(exercises: [item("invented-exercise")]),
            catalog: catalog
        )
        XCTAssertEqual(issues.first { $0.severity == .error }?.severity, .error)
    }

    func testRestDayWithExercisesIsRejected() {
        let issues = PlanValidator.structureIssues(
            plan(restDayExercises: [item("push-up")]),
            catalog: catalog
        )
        XCTAssertNotNil(issues.first { $0.message.contains("rest day") })
    }

    func testDuplicateExerciseOnSameDayIsRejected() {
        let issues = PlanValidator.structureIssues(
            plan(exercises: [item("push-up"), item("push-up")]),
            catalog: catalog
        )
        XCTAssertNotNil(issues.first { $0.message.contains("twice") })
    }

    func testUnsafeRepRangeIsRejected() {
        let issues = PlanValidator.structureIssues(
            plan(exercises: [item("push-up", reps: 20...40)]),
            catalog: catalog
        )
        XCTAssertNotNil(issues.first { $0.message.contains("rep range") })
    }

    func testScheduleMismatchIsRejected() {
        let issues = PlanValidator.issues(
            for: plan(trainingDays: [1, 3]),
            profile: profile,
            preferences: preferences(days: [1, 3, 5]),
            catalog: catalog
        )
        XCTAssertNotNil(issues.first { $0.message.contains("selected training days") })
    }

    func testDurationMismatchIsRejected() {
        let issues = PlanValidator.issues(
            for: plan(minutes: 80),
            profile: profile,
            preferences: preferences(minutes: 45),
            catalog: catalog
        )
        XCTAssertNotNil(issues.first { $0.message.contains("45-minute") })
    }

    func testAvoidListIsRejected() {
        let issues = PlanValidator.issues(
            for: plan(),
            profile: profile,
            preferences: preferences(avoid: ["push-up"]),
            catalog: catalog
        )
        XCTAssertNotNil(issues.first { $0.message.contains("avoid list") })
    }

    func testUnavailableEquipmentIsRejected() {
        let issues = PlanValidator.issues(
            for: plan(exercises: [item("cable-row")]),
            profile: profile,
            preferences: preferences(),
            catalog: catalog
        )
        XCTAssertNotNil(issues.first { $0.message.contains("equipment") })
    }

    func testOutOfRangeSetsAreRejected() {
        let issues = PlanValidator.structureIssues(
            plan(exercises: [item("push-up", sets: 9)]),
            catalog: catalog
        )
        XCTAssertNotNil(issues.first { $0.message.contains("set count") })
    }
}
