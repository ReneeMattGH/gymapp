package com.gymapp.android.domain

data class PlanIssue(val severity: Severity, val message: String) {
    enum class Severity { WARNING, ERROR }
}

/** Client-side guard rails for plans before they are shown or saved. */
object PlanValidator {
    fun structureIssues(plan: WorkoutPlan, catalog: List<Exercise>): List<PlanIssue> {
        val byId = catalog.associateBy { it.id }
        val issues = mutableListOf<PlanIssue>()
        val trainingDays = plan.days.filter { !it.isRestDay }
        if (trainingDays.isEmpty()) {
            issues.add(PlanIssue(PlanIssue.Severity.ERROR, "The plan has no training days."))
        }

        for (day in plan.days) {
            val label = day.weekday?.let { "day $it" } ?: "day ${day.dayIndex + 1}"
            if (day.isRestDay) {
                if (day.exercises.isNotEmpty()) {
                    issues.add(PlanIssue(PlanIssue.Severity.ERROR, "The rest day on $label contains exercises."))
                }
                continue
            }
            if (day.exercises.isEmpty()) {
                issues.add(PlanIssue(PlanIssue.Severity.ERROR, "The session on $label has no exercises."))
                continue
            }
            if (day.exercises.size > 6) {
                issues.add(PlanIssue(PlanIssue.Severity.ERROR, "The session on $label has more than six exercises."))
            }
            if (day.estimatedMinutes < 10 || day.estimatedMinutes > 120) {
                issues.add(PlanIssue(PlanIssue.Severity.WARNING, "The session on $label has an unusual estimated length."))
            }

            val seen = mutableSetOf<String>()
            for (item in day.exercises) {
                val exercise = byId[item.exerciseId]
                if (exercise == null) {
                    issues.add(PlanIssue(PlanIssue.Severity.ERROR, "“${item.exerciseId}” is not in the verified library."))
                    continue
                }
                if (!seen.add(item.exerciseId)) {
                    issues.add(PlanIssue(PlanIssue.Severity.ERROR, "“${exercise.name}” appears twice on $label."))
                }
                if (item.sets < 1 || item.sets > 6) {
                    issues.add(PlanIssue(PlanIssue.Severity.ERROR, "“${exercise.name}” has an unsafe set count."))
                }
                if (item.repsMin < 1 || item.repsMax > 30 || item.repsMax < item.repsMin) {
                    issues.add(PlanIssue(PlanIssue.Severity.ERROR, "“${exercise.name}” has an invalid rep range."))
                }
                if (item.restSeconds < 0 || item.restSeconds > 300) {
                    issues.add(PlanIssue(PlanIssue.Severity.ERROR, "“${exercise.name}” has an unsafe rest period."))
                }
            }
        }
        return issues
    }

    fun issues(
        plan: WorkoutPlan,
        profile: Profile,
        preferences: Preferences,
        catalog: List<Exercise>,
    ): List<PlanIssue> {
        val issues = structureIssues(plan, catalog).toMutableList()
        val byId = catalog.associateBy { it.id }
        val selected = preferences.workoutDays.filter { it in 1..7 }.toSet()
        val training = plan.days.filter { !it.isRestDay }

        if (selected.isNotEmpty()) {
            val scheduled = training.mapNotNull { it.weekday }.toSet()
            if (scheduled != selected) {
                issues.add(PlanIssue(PlanIssue.Severity.ERROR, "The plan does not match your selected training days."))
            }
            if (training.size != selected.size) {
                issues.add(
                    PlanIssue(
                        PlanIssue.Severity.ERROR,
                        "The plan has ${training.size} sessions but you selected ${selected.size} days.",
                    ),
                )
            }
        }

        for (day in training) {
            val label = day.weekday?.let { "day $it" } ?: "day ${day.dayIndex + 1}"
            if (kotlin.math.abs(day.estimatedMinutes - preferences.sessionMinutes) > 15) {
                issues.add(
                    PlanIssue(
                        PlanIssue.Severity.ERROR,
                        "The session on $label does not fit your ${preferences.sessionMinutes}-minute window.",
                    ),
                )
            }
            for (item in day.exercises) {
                val exercise = byId[item.exerciseId] ?: continue
                if (!PlanGenerator.equipmentAvailable(exercise, preferences.equipment)) {
                    issues.add(
                        PlanIssue(
                            PlanIssue.Severity.ERROR,
                            "“${exercise.name}” needs equipment you have not selected.",
                        ),
                    )
                }
                if (preferences.avoidExercises.contains(item.exerciseId)) {
                    issues.add(PlanIssue(PlanIssue.Severity.ERROR, "“${exercise.name}” is on your avoid list."))
                }
                if (exercise.difficulty == Difficulty.ADVANCED && profile.experience == Experience.BEGINNER) {
                    issues.add(PlanIssue(PlanIssue.Severity.WARNING, "“${exercise.name}” is advanced for a beginner."))
                }
            }
        }

        return issues
    }

    fun firstError(issues: List<PlanIssue>): String? =
        issues.firstOrNull { it.severity == PlanIssue.Severity.ERROR }?.message
}
