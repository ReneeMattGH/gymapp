package com.gymapp.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors `native/FormaTests/PlanValidatorTests.swift`. */
class PlanValidatorTest {
    private val squat = Exercise(
        id = "bodyweight-squat",
        name = "Bodyweight Squat",
        category = ExerciseCategory.STRENGTH,
        primaryMuscles = listOf(Muscle.QUADRICEPS),
        secondaryMuscles = listOf(Muscle.GLUTES),
        equipment = listOf(Equipment.BODYWEIGHT),
        difficulty = Difficulty.BEGINNER,
    )

    private val pushUp = Exercise(
        id = "push-up",
        name = "Push-Up",
        category = ExerciseCategory.STRENGTH,
        primaryMuscles = listOf(Muscle.MIDDLE_CHEST),
        secondaryMuscles = listOf(Muscle.TRICEPS),
        equipment = listOf(Equipment.BODYWEIGHT),
        difficulty = Difficulty.BEGINNER,
    )

    private val cableRow = Exercise(
        id = "cable-row",
        name = "Cable Row",
        category = ExerciseCategory.STRENGTH,
        primaryMuscles = listOf(Muscle.LATS),
        secondaryMuscles = listOf(Muscle.TRICEPS),
        equipment = listOf(Equipment.CABLE),
        difficulty = Difficulty.INTERMEDIATE,
    )

    private val catalog: List<Exercise> get() = listOf(squat, pushUp, cableRow)

    private val profile = Profile(
        id = "user-1",
        name = "Test",
        age = 30,
        experience = Experience.BEGINNER,
        environment = TrainingEnvironment.HOME,
        goals = listOf(Goal.GENERAL),
        onboardingCompleted = true,
        createdAt = 0L,
    )

    private fun preferences(
        days: List<Int> = listOf(1, 3, 5),
        minutes: Int = 45,
        equipment: List<Equipment> = listOf(Equipment.BODYWEIGHT),
        avoid: List<String> = emptyList(),
    ) = Preferences(
        userId = "user-1",
        workoutDays = days,
        sessionMinutes = minutes,
        equipment = equipment,
        avoidExercises = avoid,
    )

    private var itemCounter = 0

    private fun item(
        id: String,
        sets: Int = 3,
        reps: IntRange = 8..12,
        rest: Int = 60,
    ) = WorkoutExercise(
        id = "item-${itemCounter++}",
        dayId = "day",
        exerciseId = id,
        position = 0,
        sets = sets,
        repsMin = reps.first,
        repsMax = reps.last,
        restSeconds = rest,
    )

    private fun plan(
        trainingDays: List<Int> = listOf(1, 3, 5),
        minutes: Int = 45,
        exercises: List<WorkoutExercise>? = null,
        restDayExercises: List<WorkoutExercise> = emptyList(),
    ): WorkoutPlan {
        val chosen = exercises ?: listOf(item("bodyweight-squat"), item("push-up"))
        val days = (1..7).map { weekday ->
            val training = trainingDays.contains(weekday)
            WorkoutDay(
                id = "day-$weekday",
                planId = "plan-1",
                dayIndex = weekday - 1,
                weekday = weekday,
                title = if (training) "Full body" else "Rest",
                focus = if (training) listOf(MuscleGroup.FULL_BODY) else emptyList(),
                estimatedMinutes = if (training) minutes else 0,
                warmup = emptyList(),
                cooldown = emptyList(),
                isRestDay = !training,
                restNote = if (training) null else "Easy day",
                exercises = if (training) chosen else restDayExercises,
            )
        }
        return WorkoutPlan(
            id = "plan-1",
            userId = "user-1",
            name = "Test plan",
            goal = Goal.GENERAL,
            experience = Experience.BEGINNER,
            daysPerWeek = trainingDays.size,
            sessionMinutes = minutes,
            equipment = listOf(Equipment.BODYWEIGHT),
            source = PlanSource.AI,
            createdAt = 0L,
            days = days,
        )
    }

    @Test
    fun `valid plan has no errors`() {
        val issues = PlanValidator.issues(plan(), profile, preferences(), catalog)
        assertNull("Unexpected errors: $issues", PlanValidator.firstError(issues))
    }

    @Test
    fun `unknown exercise is rejected`() {
        val issues = PlanValidator.structureIssues(plan(exercises = listOf(item("invented-exercise"))), catalog)
        assertEquals(PlanIssue.Severity.ERROR, issues.first { it.severity == PlanIssue.Severity.ERROR }.severity)
    }

    @Test
    fun `rest day with exercises is rejected`() {
        val issues = PlanValidator.structureIssues(plan(restDayExercises = listOf(item("push-up"))), catalog)
        assertNotNull(issues.firstOrNull { it.message.contains("rest day") })
    }

    @Test
    fun `duplicate exercise on same day is rejected`() {
        val issues = PlanValidator.structureIssues(
            plan(exercises = listOf(item("push-up"), item("push-up"))),
            catalog,
        )
        assertNotNull(issues.firstOrNull { it.message.contains("twice") })
    }

    @Test
    fun `unsafe rep range is rejected`() {
        val issues = PlanValidator.structureIssues(plan(exercises = listOf(item("push-up", reps = 20..40))), catalog)
        assertNotNull(issues.firstOrNull { it.message.contains("rep range") })
    }

    @Test
    fun `schedule mismatch is rejected`() {
        val issues = PlanValidator.issues(
            plan(trainingDays = listOf(1, 3)),
            profile,
            preferences(days = listOf(1, 3, 5)),
            catalog,
        )
        assertNotNull(issues.firstOrNull { it.message.contains("selected training days") })
    }

    @Test
    fun `duration mismatch is rejected`() {
        val issues = PlanValidator.issues(plan(minutes = 80), profile, preferences(minutes = 45), catalog)
        assertNotNull(issues.firstOrNull { it.message.contains("45-minute") })
    }

    @Test
    fun `avoid list is rejected`() {
        val issues = PlanValidator.issues(plan(), profile, preferences(avoid = listOf("push-up")), catalog)
        assertNotNull(issues.firstOrNull { it.message.contains("avoid list") })
    }

    @Test
    fun `unavailable equipment is rejected`() {
        val issues = PlanValidator.issues(
            plan(exercises = listOf(item("cable-row"))),
            profile,
            preferences(),
            catalog,
        )
        assertNotNull(issues.firstOrNull { it.message.contains("equipment") })
    }

    @Test
    fun `out of range sets are rejected`() {
        val issues = PlanValidator.structureIssues(plan(exercises = listOf(item("push-up", sets = 9))), catalog)
        assertTrue(issues.any { it.message.contains("set count") })
    }
}
