package com.gymapp.android.domain

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Mirrors `native/FormaTests/TaxonomyTests.swift`, including the bundled catalog checks. */
class TaxonomyTest {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        explicitNulls = false
        isLenient = true
    }

    private val catalog: List<Exercise> by lazy {
        val file = File("src/main/assets/exercises.json")
        assertTrue("Bundled catalog not found at ${file.absolutePath}", file.exists())
        json.decodeFromString(ListSerializer(Exercise.serializer()), file.readText())
    }

    @Test
    fun `every muscle has a presentation group`() {
        for (muscle in Muscle.entries) {
            assertTrue("${muscle.name} has no group label", muscle.group.label.isNotEmpty())
        }
        assertEquals(
            "Every presentation group must be reachable from the fine taxonomy",
            MuscleGroup.entries.toSet(),
            Muscle.entries.map { it.group }.toSet(),
        )
    }

    @Test
    fun `non anatomical muscles are the delivery categories`() {
        assertEquals(
            setOf(Muscle.FULL_BODY, Muscle.CARDIOVASCULAR, Muscle.MOBILITY),
            Muscle.entries.filterNot { it.isAnatomical }.toSet(),
        )
    }

    @Test
    fun `catalog is internally consistent`() {
        assertTrue(catalog.isNotEmpty())
        assertEquals("Exercise IDs must be unique", catalog.size, catalog.map { it.id }.toSet().size)

        val ids = catalog.map { it.id }.toSet()
        for (exercise in catalog) {
            assertFalse("${exercise.id} has no primary muscle", exercise.primaryMuscles.isEmpty())
            assertFalse("${exercise.id} declares no supported goals", exercise.supportedGoals.isEmpty())
            assertNotNull("${exercise.id} has no movement pattern", exercise.movementPattern)
            if (exercise.category != ExerciseCategory.MOBILITY) {
                assertNotNull("${exercise.id} has no compound/isolation class", exercise.compoundClass)
            }
            assertNotNull("${exercise.id} must declare provenance", exercise.source)
            assertTrue("Bundled catalog should only ship active exercises", exercise.isActive)
            for (alternative in exercise.alternatives) {
                assertTrue("${exercise.id} points at missing alternative $alternative", ids.contains(alternative))
            }
            for (reference in exercise.sourceReferences) {
                assertFalse(reference.title.isEmpty())
            }
        }
    }

    @Test
    fun `catalog uses fine muscles beyond the coarse groups`() {
        val fineMuscles = catalog.flatMap { it.primaryMuscles }.toSet()
        assertTrue(fineMuscles.contains(Muscle.UPPER_CHEST))
        assertTrue(fineMuscles.contains(Muscle.LATS))
        assertTrue(fineMuscles.contains(Muscle.REAR_DELTOIDS))
        assertTrue(fineMuscles.contains(Muscle.QUADRICEPS))
        assertTrue(fineMuscles.contains(Muscle.RECTUS_ABDOMINIS))
        assertFalse(
            "Conditioning and mobility must not be conflated",
            fineMuscles.contains(Muscle.CARDIOVASCULAR) && fineMuscles.contains(Muscle.MOBILITY),
        )
    }

    @Test
    fun `search still matches the coarse group name`() {
        val page = ExerciseService.search(catalog, ExerciseFilters(query = "chest"))
        assertTrue("Searching a coarse group must still find fine-taxonomy exercises", page.items.isNotEmpty())
        assertTrue(
            page.items.all { exercise ->
                exercise.primaryMuscles.any { it.group == MuscleGroup.CHEST } ||
                    exercise.secondaryMuscles.any { it.group == MuscleGroup.CHEST } ||
                    exercise.name.contains("chest", ignoreCase = true)
            },
        )
    }
}
