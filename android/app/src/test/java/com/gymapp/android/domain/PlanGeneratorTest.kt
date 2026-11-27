package com.gymapp.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Rule-for-rule checks of the on-device generator, matching the iOS algorithm v2. */
class PlanGeneratorTest {
    private val profile = Profile(
        id = "test-user",
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
        userId = "test-user",
        workoutDays = days,
        sessionMinutes = minutes,
        equipment = equipment,
        avoidExercises = avoid,
    )

    private fun exercise(
        id: String,
        muscle: Muscle,
        category: ExerciseCategory = ExerciseCategory.STRENGTH,
        difficulty: Difficulty = Difficulty.BEGINNER,
        experienceLevel: Experience = Experience.BEGINNER,
        equipment: List<Equipment> = listOf(Equipment.BODYWEIGHT),
    ) = Exercise(
        id = id,
        name = id,
        category = category,
        primaryMuscles = listOf(muscle),
        equipment = equipment,
        difficulty = difficulty,
        experienceLevel = experienceLevel,
    )

    private val catalog: List<Exercise> = listOf(
        exercise("squat", Muscle.QUADRICEPS),
        exercise("glute-bridge", Muscle.GLUTES),
        exercise("push-up", Muscle.MIDDLE_CHEST),
        exercise("row", Muscle.LATS),
        exercise("plank", Muscle.RECTUS_ABDOMINIS),
    )

    @Test
    fun `template sequence matches training day count`() {
        assertEquals(listOf(PlanKind.FULL), PlanGenerator.templateSequence(1))
        assertEquals(listOf(PlanKind.FULL, PlanKind.FULL), PlanGenerator.templateSequence(2))
        assertEquals(
            listOf(PlanKind.UPPER, PlanKind.LOWER, PlanKind.UPPER, PlanKind.LOWER),
            PlanGenerator.templateSequence(4),
        )
        assertEquals(
            listOf(PlanKind.PUSH, PlanKind.PULL, PlanKind.LEGS, PlanKind.UPPER, PlanKind.FULL),
            PlanGenerator.templateSequence(5),
        )
        assertEquals(
            listOf(
                PlanKind.PUSH, PlanKind.PULL, PlanKind.LEGS, PlanKind.PUSH, PlanKind.PULL, PlanKind.LEGS,
            ),
            PlanGenerator.templateSequence(6),
        )
        assertEquals(7, PlanGenerator.templateSequence(7).size)
    }

    @Test
    fun `evenly spaced weekdays stay inside the week and stay distinct`() {
        for (count in 1..7) {
            val days = PlanGenerator.evenlySpacedWeekdays(count)
            assertEquals(count, days.size)
            assertEquals(count, days.distinct().size)
            assertTrue(days.all { it in 1..7 })
            assertEquals(days.sorted(), days)
        }
        assertEquals(listOf(1, 3, 6), PlanGenerator.evenlySpacedWeekdays(3))
        assertTrue(PlanGenerator.evenlySpacedWeekdays(0).isEmpty())
    }

    @Test
    fun `normalise weekdays keeps valid selections and tops up the rest`() {
        assertEquals(listOf(1, 3, 5), PlanGenerator.normaliseWeekdays(listOf(1, 3, 5), 3))
        assertEquals(listOf(1, 3, 5), PlanGenerator.normaliseWeekdays(listOf(8, 1, 3, 5), 3))
        assertEquals(listOf(1, 2, 3), PlanGenerator.normaliseWeekdays(listOf(2), 3))
        assertTrue(PlanGenerator.normaliseWeekdays(emptyList(), 0).isEmpty())
    }

    @Test
    fun `exercise count follows the session length`() {
        assertEquals(3, PlanGenerator.exerciseCount(15))
        assertEquals(3, PlanGenerator.exerciseCount(20))
        assertEquals(4, PlanGenerator.exerciseCount(30))
        assertEquals(5, PlanGenerator.exerciseCount(45))
        assertEquals(6, PlanGenerator.exerciseCount(60))
        assertEquals(7, PlanGenerator.exerciseCount(75))
    }

    @Test
    fun `allowed difficulties widen with experience`() {
        assertEquals(listOf(Difficulty.BEGINNER), PlanGenerator.allowedDifficulties(Experience.BEGINNER))
        assertEquals(
            listOf(Difficulty.BEGINNER, Difficulty.INTERMEDIATE),
            PlanGenerator.allowedDifficulties(Experience.INTERMEDIATE),
        )
        assertEquals(3, PlanGenerator.allowedDifficulties(Experience.ADVANCED).size)
    }

    @Test
    fun `rep ranges match goal and experience`() {
        assertEquals(PlanGenerator.RepRange(8, 10, 90), PlanGenerator.repRange(Goal.STRENGTH, Experience.BEGINNER))
        assertEquals(PlanGenerator.RepRange(5, 8, 120), PlanGenerator.repRange(Goal.STRENGTH, Experience.ADVANCED))
        assertEquals(PlanGenerator.RepRange(8, 12, 90), PlanGenerator.repRange(Goal.MUSCLE, Experience.BEGINNER))
        assertEquals(PlanGenerator.RepRange(12, 15, 60), PlanGenerator.repRange(Goal.ENDURANCE, Experience.BEGINNER))
        assertEquals(PlanGenerator.RepRange(8, 12, 90), PlanGenerator.repRange(Goal.GENERAL, Experience.BEGINNER))
    }

    @Test
    fun `set count gives the first slot the bonus for advanced athletes`() {
        assertEquals(2, PlanGenerator.setCount(Experience.BEGINNER, 0))
        assertEquals(2, PlanGenerator.setCount(Experience.BEGINNER, 1))
        assertEquals(3, PlanGenerator.setCount(Experience.INTERMEDIATE, 0))
        assertEquals(3, PlanGenerator.setCount(Experience.INTERMEDIATE, 1))
        assertEquals(4, PlanGenerator.setCount(Experience.ADVANCED, 0))
        assertEquals(3, PlanGenerator.setCount(Experience.ADVANCED, 1))
    }

    @Test
    fun `equipment availability treats bodyweight as always available`() {
        val bodyweight = exercise("squat", Muscle.QUADRICEPS)
        val dumbbell = exercise("goblet", Muscle.QUADRICEPS, equipment = listOf(Equipment.DUMBBELLS))
        val mixed = exercise(
            "weighted-squat",
            Muscle.QUADRICEPS,
            equipment = listOf(Equipment.BODYWEIGHT, Equipment.DUMBBELLS),
        )
        assertTrue(PlanGenerator.equipmentAvailable(bodyweight, emptyList()))
        assertFalse(PlanGenerator.equipmentAvailable(dumbbell, emptyList()))
        assertTrue(PlanGenerator.equipmentAvailable(dumbbell, listOf(Equipment.DUMBBELLS)))
        assertFalse(PlanGenerator.equipmentAvailable(mixed, listOf(Equipment.BARBELL)))
        assertTrue(PlanGenerator.equipmentAvailable(mixed, listOf(Equipment.DUMBBELLS)))
    }

    @Test
    fun `generated plan declares algorithm version status and timestamp`() {
        val plan = PlanGenerator.generateLocalPlan("test-user", profile, preferences(), catalog)
        assertNotNull(plan)
        plan!!
        assertEquals(PlanGenerator.ALGORITHM_VERSION, plan.effectiveAlgorithmVersion)
        assertEquals(PlanStatus.ACTIVE, plan.planStatus)
        assertEquals(plan.createdAt, plan.generatedAt)
        assertEquals(PlanSource.ON_DEVICE, plan.source)
    }

    @Test
    fun `generated plan schedules the selected weekdays with rest elsewhere`() {
        val plan = PlanGenerator.generateLocalPlan("test-user", profile, preferences(days = listOf(1, 3, 5)), catalog)!!
        assertEquals(7, plan.days.size)
        assertEquals(3, plan.daysPerWeek)
        assertEquals("Foundation · 3 days", plan.name)
        assertEquals(listOf(1, 3, 5), plan.trainingDays.map { it.weekday })
        assertEquals(listOf(2, 4, 6, 7), plan.days.filter { it.isRestDay }.map { it.weekday })
        assertEquals(listOf("Full body · A", "Full body · B", "Full body · C"), plan.trainingDays.map { it.title })

        val first = plan.trainingDays.first()
        assertEquals(5, first.exercises.size)
        assertEquals(42, first.estimatedMinutes)
        assertEquals(3, first.warmup.size)
        assertEquals(3, first.cooldown.size)
    }

    @Test
    fun `generated plan passes its own validator`() {
        val prefs = preferences()
        val plan = PlanGenerator.generateLocalPlan("test-user", profile, prefs, catalog)!!
        val issues = PlanValidator.issues(plan, profile, prefs, catalog)
        assertNull("Unexpected errors: $issues", PlanValidator.firstError(issues))
    }

    @Test
    fun `beginner plans never prescribe advanced exercises`() {
        val advancedCatalog = catalog + exercise("hard-push-up", Muscle.MIDDLE_CHEST, difficulty = Difficulty.ADVANCED)
        val plan = PlanGenerator.generateLocalPlan("test-user", profile, preferences(minutes = 60), advancedCatalog)!!
        for (day in plan.trainingDays) {
            for (item in day.exercises) {
                val picked = advancedCatalog.first { it.id == item.exerciseId }
                assertEquals(Difficulty.BEGINNER, picked.difficulty)
                assertEquals(Experience.BEGINNER, picked.experienceLevel)
            }
        }
    }

    @Test
    fun `avoid list is never scheduled`() {
        val plan = PlanGenerator.generateLocalPlan(
            "test-user",
            profile,
            preferences(avoid = listOf("push-up", "squat")),
            catalog,
        )!!
        val scheduled = plan.days.flatMap { day -> day.exercises.map { it.exerciseId } }
        assertFalse(scheduled.contains("push-up"))
        assertFalse(scheduled.contains("squat"))
    }

    @Test
    fun `generator refuses an empty catalog`() {
        assertNull(PlanGenerator.generateLocalPlan("test-user", profile, preferences(), emptyList()))
    }

    @Test
    fun `ai payload is clamped and unknown ids are dropped`() {
        val payload = AIPlanPayload(
            name = "n".repeat(80),
            days = listOf(
                AIPlanPayload.Day(
                    weekday = 1,
                    title = "Upper",
                    focus = listOf("chest"),
                    estimatedMinutes = 50,
                    warmup = listOf("warm up"),
                    cooldown = listOf("cool down"),
                    exercises = listOf(
                        AIPlanPayload.Item("push-up", sets = 9, repsMin = 2, repsMax = 99, restSeconds = 5),
                        AIPlanPayload.Item("invented"),
                    ),
                ),
                AIPlanPayload.Day(weekday = 3, isRestDay = true),
            ),
        )
        val plan = PlanGenerator.planFromAIPayload(payload, "test-user", profile, preferences(), catalog)
        assertNotNull(plan)
        plan!!
        assertEquals(60, plan.name.length)
        assertEquals(7, plan.days.size)
        val training = plan.days.first { it.weekday == 1 }
        assertFalse(training.isRestDay)
        assertEquals("Upper", training.title)
        assertEquals(50, training.estimatedMinutes)
        assertEquals(listOf(MuscleGroup.CHEST), training.focus)
        assertEquals(1, training.exercises.size)
        val item = training.exercises.single()
        assertEquals("push-up", item.exerciseId)
        assertEquals(5, item.sets)
        assertEquals(3, item.repsMin)
        assertEquals(40, item.repsMax)
        assertEquals(15, item.restSeconds)
        assertTrue(plan.days.first { it.weekday == 3 }.isRestDay)
        assertEquals(PlanSource.AI, plan.source)
    }

    @Test
    fun `ai payload with nothing trainable is rejected`() {
        val empty = AIPlanPayload(days = emptyList())
        assertNull(PlanGenerator.planFromAIPayload(empty, "test-user", profile, preferences(), catalog))

        val allUnknown = AIPlanPayload(
            days = listOf(AIPlanPayload.Day(weekday = 1, exercises = listOf(AIPlanPayload.Item("invented")))),
        )
        assertNull(PlanGenerator.planFromAIPayload(allUnknown, "test-user", profile, preferences(), catalog))
    }

    @Test
    fun `next training day skips rest days and wraps the week`() {
        val plan = PlanGenerator.generateLocalPlan("test-user", profile, preferences(days = listOf(1, 3)), catalog)!!
        // Wednesday 2026-11-25 (weekday 3) → next training day is Monday (weekday 1) of the following week.
        val wednesday = java.time.LocalDate.of(2026, 11, 25)
            .atTime(12, 0)
            .atZone(java.time.ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
        val next = PlanGenerator.nextTrainingDay(plan, wednesday)
        assertEquals(1, next?.weekday)
    }
}
