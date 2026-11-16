import Foundation

struct ExerciseFilters: Sendable, Equatable {
    var query: String = ""
    var category: ExerciseCategory?
    var muscle: MuscleGroup?
    var onlyFavorites: Bool = false
    var favoriteIDs: Set<String> = []
    var equipment: Set<Equipment> = []
}

struct ExercisePage: Sendable {
    var items: [Exercise]
    var total: Int
    var hasMore: Bool
}

/// Search, filtering, and alternatives over whichever verified catalog is
/// loaded (server-backed or bundled). Pure value-in/value-out so it is testable.
enum ExerciseService {
    static func search(
        _ exercises: [Exercise],
        filters: ExerciseFilters,
        offset: Int = 0,
        limit: Int = 30
    ) -> ExercisePage {
        let text = filters.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = exercises.filter { exercise in
            if filters.onlyFavorites && !filters.favoriteIDs.contains(exercise.id) { return false }
            if let category = filters.category, exercise.category != category { return false }
            if let muscle = filters.muscle,
               !exercise.primaryMuscles.contains(muscle),
               !exercise.secondaryMuscles.contains(muscle) {
                return false
            }
            if !filters.equipment.isEmpty,
               !Set(exercise.equipment).isSubset(of: filters.equipment.union([.bodyweight])) {
                return false
            }
            guard !text.isEmpty else { return true }
            if exercise.name.lowercased().contains(text) { return true }
            if exercise.primaryMuscles.contains(where: { $0.label.lowercased().contains(text) }) { return true }
            if exercise.secondaryMuscles.contains(where: { $0.label.lowercased().contains(text) }) { return true }
            if exercise.equipment.contains(where: { $0.label.lowercased().contains(text) }) { return true }
            if exercise.category.label.lowercased().contains(text) { return true }
            return false
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let start = max(0, min(offset, matches.count))
        let end = max(start, min(start + max(1, limit), matches.count))
        return ExercisePage(
            items: Array(matches[start..<end]),
            total: matches.count,
            hasMore: end < matches.count
        )
    }

    static func exercise(_ id: String, in exercises: [Exercise]) -> Exercise? {
        exercises.first { $0.id == id } ?? ExerciseCatalog.exercise(id)
    }

    static func alternatives(for exercise: Exercise, in exercises: [Exercise]) -> [Exercise] {
        exercise.alternatives.compactMap { Self.exercise($0, in: exercises) }
    }

    /// IDs present in the verified catalog, used to reject hallucinated exercises.
    static func verifiedIDs(in exercises: [Exercise]) -> Set<String> {
        Set(exercises.map(\.id))
    }

    static func isVerified(_ id: String, in exercises: [Exercise]) -> Bool {
        exercises.contains { $0.id == id } || ExerciseCatalog.exercise(id) != nil
    }
}
