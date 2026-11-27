package com.gymapp.android.domain

data class ExerciseFilters(
    val query: String = "",
    val category: ExerciseCategory? = null,
    val muscle: MuscleGroup? = null,
    val onlyFavorites: Boolean = false,
    val favoriteIDs: Set<String> = emptySet(),
    val equipment: Set<Equipment> = emptySet(),
)

data class ExercisePage(
    val items: List<Exercise>,
    val total: Int,
    val hasMore: Boolean,
)

/** Pure search and filtering over the verified catalog, matching iOS behaviour. */
object ExerciseService {
    fun search(
        exercises: List<Exercise>,
        filters: ExerciseFilters,
        offset: Int = 0,
        limit: Int = 30,
    ): ExercisePage {
        val text = filters.query.trim().lowercase()
        val matches = exercises.filter { exercise ->
            if (filters.onlyFavorites && exercise.id !in filters.favoriteIDs) return@filter false
            if (filters.category != null && exercise.category != filters.category) return@filter false
            if (filters.muscle != null &&
                exercise.primaryMuscles.none { it.group == filters.muscle } &&
                exercise.secondaryMuscles.none { it.group == filters.muscle }
            ) {
                return@filter false
            }
            if (filters.equipment.isNotEmpty() &&
                !exercise.equipment.all { it == Equipment.BODYWEIGHT || it in filters.equipment }
            ) {
                return@filter false
            }
            if (text.isEmpty()) return@filter true
            if (exercise.name.lowercase().contains(text)) return@filter true
            if (exercise.primaryMuscles.any { muscle -> muscle.searchTerms.any { it.lowercase().contains(text) } }) {
                return@filter true
            }
            if (exercise.secondaryMuscles.any { muscle -> muscle.searchTerms.any { it.lowercase().contains(text) } }) {
                return@filter true
            }
            if (exercise.equipment.any { it.label.lowercase().contains(text) }) return@filter true
            if (exercise.category.label.lowercase().contains(text)) return@filter true
            false
        }.sortedBy { it.name.lowercase() }

        val start = offset.coerceIn(0, matches.size)
        val end = (start + maxOf(1, limit)).coerceAtMost(matches.size)
        return ExercisePage(
            items = matches.subList(start, end),
            total = matches.size,
            hasMore = end < matches.size,
        )
    }

    fun exercise(id: String, exercises: List<Exercise>): Exercise? =
        exercises.firstOrNull { it.id == id } ?: ExerciseCatalog.exercise(id)

    fun alternatives(exercise: Exercise, exercises: List<Exercise>): List<Exercise> =
        exercise.alternatives.mapNotNull { exercise(it, exercises) }

    fun verifiedIDs(exercises: List<Exercise>): Set<String> = exercises.map { it.id }.toSet()

    fun isVerified(id: String, exercises: List<Exercise>): Boolean =
        exercises.any { it.id == id } || ExerciseCatalog.exercise(id) != null
}
