package com.gymapp.android.domain

/** In-memory verified exercise library, in the same order as the bundled iOS catalog. */
object ExerciseCatalog {
    @Volatile
    private var items: List<Exercise> = emptyList()

    private var index: Map<String, Exercise> = emptyMap()

    val all: List<Exercise> get() = items

    fun initialize(exercises: List<Exercise>) {
        items = exercises
        index = exercises.associateBy { it.id }
    }

    fun exercise(id: String): Exercise? = index[id]

    fun name(id: String): String = index[id]?.name ?: id

    fun search(query: String): List<Exercise> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return all
        return all.filter { exercise ->
            exercise.name.lowercase().contains(needle) ||
                exercise.alternativeNames.any { it.lowercase().contains(needle) } ||
                exercise.primaryMuscles.any { it.label.lowercase().contains(needle) } ||
                exercise.primaryGroups.any { it.label.lowercase().contains(needle) } ||
                exercise.equipment.any { it.label.lowercase().contains(needle) }
        }
    }
}
