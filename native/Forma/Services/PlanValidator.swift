import Foundation

struct PlanIssue: Equatable, Sendable {
    enum Severity: Sendable, Equatable {
        case warning, error
    }

    var severity: Severity
    var message: String
}

/// Client-side guard rails for plans before they are shown or saved. The
/// backend validates AI output too; this layer catches anything that slipped
/// through or was edited on-device.
enum PlanValidator {
    static func structureIssues(_ plan: WorkoutPlan, catalog: [Exercise]) -> [PlanIssue] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var issues: [PlanIssue] = []
        let trainingDays = plan.days.filter { !$0.isRestDay }
        if trainingDays.isEmpty {
            issues.append(.init(severity: .error, message: "The plan has no training days."))
        }

        for day in plan.days {
            let label = day.weekday.map { "day \($0)" } ?? "day \(day.dayIndex + 1)"
            if day.isRestDay {
                if !day.exercises.isEmpty {
                    issues.append(.init(severity: .error, message: "The rest day on \(label) contains exercises."))
                }
                continue
            }
            if day.exercises.isEmpty {
                issues.append(.init(severity: .error, message: "The session on \(label) has no exercises."))
                continue
            }
            if day.exercises.count > 6 {
                issues.append(.init(severity: .error, message: "The session on \(label) has more than six exercises."))
            }
            if day.estimatedMinutes < 10 || day.estimatedMinutes > 120 {
                issues.append(.init(severity: .warning, message: "The session on \(label) has an unusual estimated length."))
            }

            var seen = Set<String>()
            for item in day.exercises {
                guard let exercise = byID[item.exerciseId] else {
                    issues.append(.init(severity: .error, message: "“\(item.exerciseId)” is not in the verified library."))
                    continue
                }
                if !seen.insert(item.exerciseId).inserted {
                    issues.append(.init(severity: .error, message: "“\(exercise.name)” appears twice on \(label)."))
                }
                if item.sets < 1 || item.sets > 6 {
                    issues.append(.init(severity: .error, message: "“\(exercise.name)” has an unsafe set count."))
                }
                if item.repsMin < 1 || item.repsMax > 30 || item.repsMax < item.repsMin {
                    issues.append(.init(severity: .error, message: "“\(exercise.name)” has an invalid rep range."))
                }
                if item.restSeconds < 0 || item.restSeconds > 300 {
                    issues.append(.init(severity: .error, message: "“\(exercise.name)” has an unsafe rest period."))
                }
            }
        }
        return issues
    }

    /// Full AI-draft validation: structure, equipment, schedule, and session length.
    static func issues(
        for plan: WorkoutPlan,
        profile: Profile,
        preferences: Preferences,
        catalog: [Exercise]
    ) -> [PlanIssue] {
        var issues = structureIssues(plan, catalog: catalog)
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = Set(preferences.workoutDays.filter { (1...7).contains($0) })
        let training = plan.days.filter { !$0.isRestDay }

        if !selected.isEmpty {
            let scheduled = Set(training.compactMap(\.weekday))
            if scheduled != selected {
                issues.append(.init(
                    severity: .error,
                    message: "The plan does not match your selected training days."
                ))
            }
            if training.count != selected.count {
                issues.append(.init(
                    severity: .error,
                    message: "The plan has \(training.count) sessions but you selected \(selected.count) days."
                ))
            }
        }

        for day in training {
            let label = day.weekday.map { "day \($0)" } ?? "day \(day.dayIndex + 1)"
            if abs(day.estimatedMinutes - preferences.sessionMinutes) > 15 {
                issues.append(.init(
                    severity: .error,
                    message: "The session on \(label) does not fit your \(preferences.sessionMinutes)-minute window."
                ))
            }
            for item in day.exercises {
                guard let exercise = byID[item.exerciseId] else { continue }
                if !PlanGenerator.equipmentAvailable(exercise, equipment: preferences.equipment) {
                    issues.append(.init(
                        severity: .error,
                        message: "“\(exercise.name)” needs equipment you have not selected."
                    ))
                }
                if preferences.avoidExercises.contains(item.exerciseId) {
                    issues.append(.init(
                        severity: .error,
                        message: "“\(exercise.name)” is on your avoid list."
                    ))
                }
                if exercise.difficulty == .advanced && profile.experience == .beginner {
                    issues.append(.init(
                        severity: .warning,
                        message: "“\(exercise.name)” is advanced for a beginner."
                    ))
                }
            }
        }

        return issues
    }

    static func firstError(in issues: [PlanIssue]) -> String? {
        issues.first { $0.severity == .error }?.message
    }
}
