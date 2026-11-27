package com.gymapp.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors `native/FormaTests/ExerciseServiceTests.swift`. */
class ExerciseServiceTest {
    private val catalog: List<Exercise> = listOf(
        Exercise(
            id = "push-up", name = "Push-Up", category = ExerciseCategory.STRENGTH,
            primaryMuscles = listOf(Muscle.MIDDLE_CHEST), secondaryMuscles = listOf(Muscle.TRICEPS),
            equipment = listOf(Equipment.BODYWEIGHT), difficulty = Difficulty.BEGINNER,
            alternatives = listOf("incline-push-up"),
        ),
        Exercise(
            id = "incline-push-up", name = "Incline Push-Up", category = ExerciseCategory.STRENGTH,
            primaryMuscles = listOf(Muscle.MIDDLE_CHEST), secondaryMuscles = listOf(Muscle.TRICEPS),
            equipment = listOf(Equipment.BENCH), difficulty = Difficulty.BEGINNER,
        ),
        Exercise(
            id = "cable-row", name = "Cable Row", category = ExerciseCategory.STRENGTH,
            primaryMuscles = listOf(Muscle.LATS), secondaryMuscles = listOf(Muscle.TRICEPS),
            equipment = listOf(Equipment.CABLE), difficulty = Difficulty.INTERMEDIATE,
        ),
        Exercise(
            id = "hip-mobility", name = "90/90 Hip Switch", category = ExerciseCategory.MOBILITY,
            primaryMuscles = listOf(Muscle.HIP_ABDUCTORS), equipment = listOf(Equipment.BODYWEIGHT),
            difficulty = Difficulty.BEGINNER, isUnilateral = true,
        ),
    )

    @Test
    fun `search matches names case insensitively`() {
        val page = ExerciseService.search(catalog, ExerciseFilters(query = "PUSH"))
        assertEquals(setOf("push-up", "incline-push-up"), page.items.map { it.id }.toSet())
    }

    @Test
    fun `search matches muscle and equipment`() {
        val byMuscle = ExerciseService.search(catalog, ExerciseFilters(query = "back"))
        assertEquals(listOf("cable-row"), byMuscle.items.map { it.id })
        val byEquipment = ExerciseService.search(catalog, ExerciseFilters(query = "cable"))
        assertEquals(listOf("cable-row"), byEquipment.items.map { it.id })
    }

    @Test
    fun `category and muscle filters`() {
        val mobility = ExerciseService.search(catalog, ExerciseFilters(category = ExerciseCategory.MOBILITY))
        assertEquals(1, mobility.total)
        val chest = ExerciseService.search(catalog, ExerciseFilters(muscle = MuscleGroup.CHEST))
        assertEquals(2, chest.total)
    }

    @Test
    fun `favorites filter`() {
        val page = ExerciseService.search(
            catalog,
            ExerciseFilters(onlyFavorites = true, favoriteIDs = setOf("cable-row")),
        )
        assertEquals(listOf("cable-row"), page.items.map { it.id })
    }

    @Test
    fun `pagination reports totals and has more`() {
        val first = ExerciseService.search(catalog, ExerciseFilters(), limit = 2)
        assertEquals(2, first.items.size)
        assertEquals(4, first.total)
        assertTrue(first.hasMore)

        val second = ExerciseService.search(catalog, ExerciseFilters(), offset = 2, limit = 2)
        assertEquals(2, second.items.size)
        assertFalse(second.hasMore)

        val empty = ExerciseService.search(catalog, ExerciseFilters(), offset = 99)
        assertTrue(empty.items.isEmpty())
    }

    @Test
    fun `equipment filter keeps bodyweight accessible`() {
        val benchOnly = ExerciseService.search(catalog, ExerciseFilters(equipment = setOf(Equipment.BENCH)))
        assertEquals(setOf("push-up", "incline-push-up", "hip-mobility"), benchOnly.items.map { it.id }.toSet())
    }

    @Test
    fun `alternatives resolve against catalog`() {
        assertEquals(
            listOf("incline-push-up"),
            ExerciseService.alternatives(catalog[0], catalog).map { it.id },
        )
    }

    @Test
    fun `verified ids only contains catalog entries`() {
        assertTrue(ExerciseService.isVerified("push-up", catalog))
        assertFalse(ExerciseService.isVerified("made-up-movement", catalog))
    }
}
