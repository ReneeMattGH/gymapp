package com.gymapp.android.domain

import com.gymapp.android.core.FormaDate
import com.gymapp.android.core.IDs
import com.gymapp.android.core.StoredTimestamp

/**
 * Deterministic on-device programme generator. Ported rule-for-rule from the
 * iOS `PlanGenerator` (algorithm version 2) so both platforms produce the same
 * plan for the same profile, preferences and bundled catalog order.
 */
object PlanGenerator {
    const val ALGORITHM_VERSION = 2

    private val slots: Map<PlanKind, List<List<MuscleGroup>>> = mapOf(
        PlanKind.FULL to listOf(
            listOf(MuscleGroup.QUADS, MuscleGroup.GLUTES), listOf(MuscleGroup.CHEST),
            listOf(MuscleGroup.BACK), listOf(MuscleGroup.HAMSTRINGS, MuscleGroup.GLUTES),
            listOf(MuscleGroup.CORE), listOf(MuscleGroup.SHOULDERS, MuscleGroup.ARMS),
            listOf(MuscleGroup.FULL_BODY),
        ),
        PlanKind.UPPER to listOf(
            listOf(MuscleGroup.CHEST), listOf(MuscleGroup.BACK), listOf(MuscleGroup.SHOULDERS),
            listOf(MuscleGroup.ARMS), listOf(MuscleGroup.CORE), listOf(MuscleGroup.BACK),
            listOf(MuscleGroup.CHEST, MuscleGroup.ARMS),
        ),
        PlanKind.LOWER to listOf(
            listOf(MuscleGroup.QUADS), listOf(MuscleGroup.HAMSTRINGS, MuscleGroup.GLUTES),
            listOf(MuscleGroup.GLUTES), listOf(MuscleGroup.CALVES), listOf(MuscleGroup.CORE),
            listOf(MuscleGroup.QUADS, MuscleGroup.HAMSTRINGS),
        ),
        PlanKind.PUSH to listOf(
            listOf(MuscleGroup.CHEST), listOf(MuscleGroup.SHOULDERS), listOf(MuscleGroup.ARMS),
            listOf(MuscleGroup.CHEST), listOf(MuscleGroup.CORE), listOf(MuscleGroup.SHOULDERS),
        ),
        PlanKind.PULL to listOf(
            listOf(MuscleGroup.BACK), listOf(MuscleGroup.BACK), listOf(MuscleGroup.SHOULDERS),
            listOf(MuscleGroup.ARMS), listOf(MuscleGroup.CORE), listOf(MuscleGroup.BACK),
        ),
        PlanKind.LEGS to listOf(
            listOf(MuscleGroup.QUADS), listOf(MuscleGroup.HAMSTRINGS), listOf(MuscleGroup.GLUTES),
            listOf(MuscleGroup.CALVES), listOf(MuscleGroup.CORE),
            listOf(MuscleGroup.QUADS, MuscleGroup.GLUTES),
        ),
        PlanKind.MOBILITY to listOf(
            listOf(MuscleGroup.BACK, MuscleGroup.HIPS), listOf(MuscleGroup.HIPS),
            listOf(MuscleGroup.SHOULDERS), listOf(MuscleGroup.HAMSTRINGS),
            listOf(MuscleGroup.CALVES), listOf(MuscleGroup.BACK),
        ),
    )

    private data class DayMeta(val title: String, val focus: List<MuscleGroup>)

    private val meta: Map<PlanKind, DayMeta> = mapOf(
        PlanKind.FULL to DayMeta(
            "Full body",
            listOf(MuscleGroup.FULL_BODY, MuscleGroup.QUADS, MuscleGroup.CHEST, MuscleGroup.BACK, MuscleGroup.CORE),
        ),
        PlanKind.UPPER to DayMeta(
            "Upper body",
            listOf(MuscleGroup.CHEST, MuscleGroup.BACK, MuscleGroup.SHOULDERS, MuscleGroup.ARMS, MuscleGroup.CORE),
        ),
        PlanKind.LOWER to DayMeta(
            "Lower body",
            listOf(MuscleGroup.QUADS, MuscleGroup.HAMSTRINGS, MuscleGroup.GLUTES, MuscleGroup.CALVES, MuscleGroup.CORE),
        ),
        PlanKind.PUSH to DayMeta(
            "Push",
            listOf(MuscleGroup.CHEST, MuscleGroup.SHOULDERS, MuscleGroup.ARMS, MuscleGroup.CORE),
        ),
        PlanKind.PULL to DayMeta(
            "Pull",
            listOf(MuscleGroup.BACK, MuscleGroup.SHOULDERS, MuscleGroup.ARMS, MuscleGroup.CORE),
        ),
        PlanKind.LEGS to DayMeta(
            "Legs",
            listOf(MuscleGroup.QUADS, MuscleGroup.HAMSTRINGS, MuscleGroup.GLUTES, MuscleGroup.CALVES, MuscleGroup.CORE),
        ),
        PlanKind.MOBILITY to DayMeta(
            "Mobility & recovery",
            listOf(MuscleGroup.HIPS, MuscleGroup.BACK, MuscleGroup.SHOULDERS),
        ),
    )

    private val restNotes = listOf(
        "A planned rest day is part of the programme. Walk, stretch gently, or simply recover.",
        "Recovery day — prioritize sleep, food, and easy movement. Training adapts when you rest.",
        "Keep today light. Your next session will be better for it.",
        "Rest is productive. A short walk and some easy mobility is plenty.",
    )

    fun templateSequence(trainingDays: Int): List<PlanKind> = when {
        trainingDays <= 1 -> listOf(PlanKind.FULL)
        trainingDays == 2 -> listOf(PlanKind.FULL, PlanKind.FULL)
        trainingDays == 3 -> listOf(PlanKind.FULL, PlanKind.FULL, PlanKind.FULL)
        trainingDays == 4 -> listOf(PlanKind.UPPER, PlanKind.LOWER, PlanKind.UPPER, PlanKind.LOWER)
        trainingDays == 5 -> listOf(PlanKind.PUSH, PlanKind.PULL, PlanKind.LEGS, PlanKind.UPPER, PlanKind.FULL)
        trainingDays == 6 -> listOf(
            PlanKind.PUSH, PlanKind.PULL, PlanKind.LEGS, PlanKind.PUSH, PlanKind.PULL, PlanKind.LEGS,
        )
        else -> listOf(
            PlanKind.PUSH, PlanKind.PULL, PlanKind.LEGS, PlanKind.UPPER,
            PlanKind.LOWER, PlanKind.FULL, PlanKind.MOBILITY,
        )
    }

    fun evenlySpacedWeekdays(count: Int): List<Int> {
        if (count <= 0) return emptyList()
        val gap = 7.0 / count
        val picks = (0 until count).map { index ->
            Math.round(1 + index * gap).toInt().coerceIn(1, 7)
        }
        return picks.distinct().take(count)
    }

    fun normaliseWeekdays(selected: List<Int>, count: Int): List<Int> {
        val valid = selected.filter { it in 1..7 }.distinct().sorted()
        if (valid.size >= count) return valid.take(count)
        val merged = (valid + evenlySpacedWeekdays(count)).toSortedSet()
        return merged.take(count)
    }

    fun exerciseCount(minutes: Int): Int = when {
        minutes <= 20 -> 3
        minutes <= 30 -> 4
        minutes <= 45 -> 5
        minutes <= 60 -> 6
        else -> 7
    }

    fun allowedDifficulties(experience: Experience): List<Difficulty> = when (experience) {
        Experience.BEGINNER -> listOf(Difficulty.BEGINNER)
        Experience.INTERMEDIATE -> listOf(Difficulty.BEGINNER, Difficulty.INTERMEDIATE)
        Experience.ADVANCED -> listOf(Difficulty.BEGINNER, Difficulty.INTERMEDIATE, Difficulty.ADVANCED)
    }

    fun equipmentAvailable(exercise: Exercise, equipment: List<Equipment>): Boolean =
        exercise.equipment.all { it == Equipment.BODYWEIGHT || equipment.contains(it) }

    private fun experiencesAtMost(experience: Experience): List<Experience> = when (experience) {
        Experience.BEGINNER -> listOf(Experience.BEGINNER)
        Experience.INTERMEDIATE -> listOf(Experience.BEGINNER, Experience.INTERMEDIATE)
        Experience.ADVANCED -> listOf(Experience.BEGINNER, Experience.INTERMEDIATE, Experience.ADVANCED)
    }

    private fun pickExercise(
        slot: List<MuscleGroup>,
        kind: PlanKind,
        dayIndex: Int,
        slotIndex: Int,
        profile: Profile,
        preferences: Preferences,
        used: Set<String>,
        catalog: List<Exercise>,
    ): Exercise? {
        val allowed = allowedDifficulties(profile.experience).toSet()
        val category = if (kind == PlanKind.MOBILITY) ExerciseCategory.MOBILITY else ExerciseCategory.STRENGTH
        val library = catalog.filter { it.isActive }
        val experienceLevels = experiencesAtMost(profile.experience)

        fun shared(exercise: Exercise): Boolean =
            !used.contains(exercise.id) &&
                !preferences.avoidExercises.contains(exercise.id) &&
                equipmentAvailable(exercise, preferences.equipment) &&
                exercise.category == category &&
                experienceLevels.contains(exercise.experienceLevel)

        val matchesSlot: (Exercise) -> Boolean = if (kind == PlanKind.MOBILITY) {
            { true }
        } else {
            { exercise -> exercise.primaryMuscles.any { slot.contains(it.group) } }
        }

        val candidates = library.filter { shared(it) && matchesSlot(it) && allowed.contains(it.difficulty) }
        if (candidates.isEmpty()) return null
        return candidates[(dayIndex + slotIndex) % candidates.size]
    }

    data class RepRange(val min: Int, val max: Int, val rest: Int)

    fun repRange(goal: Goal, experience: Experience): RepRange = when (goal) {
        Goal.STRENGTH -> if (experience == Experience.BEGINNER) RepRange(8, 10, 90) else RepRange(5, 8, 120)
        Goal.MUSCLE -> RepRange(8, 12, 90)
        Goal.ENDURANCE -> RepRange(12, 15, 60)
        Goal.ATHLETIC -> if (experience == Experience.BEGINNER) RepRange(8, 12, 75) else RepRange(6, 10, 75)
        Goal.MOBILITY -> RepRange(8, 12, 45)
        Goal.CONSISTENCY -> RepRange(8, 12, 75)
        Goal.GENERAL -> RepRange(8, 12, 90)
    }

    fun setCount(experience: Experience, index: Int): Int {
        val base = if (experience == Experience.BEGINNER) 2 else 3
        return if (index == 0) base + if (experience == Experience.ADVANCED) 1 else 0 else base
    }

    fun warmup(kind: PlanKind): List<String> {
        if (kind == PlanKind.MOBILITY) {
            return listOf(
                "2–3 minutes of easy walking or gentle marching",
                "Move through each mobility drill slowly; stay well below pain",
            )
        }
        val lower = kind == PlanKind.LOWER || kind == PlanKind.LEGS
        val upper = kind == PlanKind.UPPER || kind == PlanKind.PUSH || kind == PlanKind.PULL
        return listOf(
            "5 minutes of easy cardio — walk, bike, or row",
            if (lower) "10 leg swings each side and 10 bodyweight squats"
            else "10 arm circles each direction and 10 shoulder rolls",
            if (upper) "One light set of your first exercise"
            else "10 slow hip hinges and 10 glute bridges",
        )
    }

    fun cooldown(kind: PlanKind): List<String> {
        if (kind == PlanKind.MOBILITY) {
            return listOf(
                "Finish with 3 slow breaths in a comfortable seated position",
                "Drink some water and note how your body feels",
            )
        }
        return listOf(
            "3–5 minutes of easy walking to bring your heart rate down",
            if (kind == PlanKind.LOWER || kind == PlanKind.LEGS)
                "Hold a gentle hamstring and hip flexor stretch for 30 seconds each side"
            else "Hold a gentle chest and lat stretch for 30 seconds each side",
            "Take a few slow breaths and note your effort for next time",
        )
    }

    fun generateLocalPlan(
        userId: String,
        profile: Profile,
        preferences: Preferences,
        catalog: List<Exercise> = ExerciseCatalog.all,
    ): WorkoutPlan? {
        if (catalog.isEmpty()) return null

        val trainingDays = (if (preferences.workoutDays.isEmpty()) 3 else preferences.workoutDays.size).coerceIn(1, 7)
        val weekdays = normaliseWeekdays(preferences.workoutDays, trainingDays)
        val sequence = templateSequence(trainingDays)
        val goal = profile.goals.firstOrNull() ?: Goal.GENERAL
        val count = exerciseCount(preferences.sessionMinutes)
        val planId = IDs.uuid()

        val trainingByWeekday = mutableMapOf<Int, Pair<PlanKind, Int>>()
        weekdays.forEachIndexed { index, weekday ->
            trainingByWeekday[weekday] = (if (index < sequence.size) sequence[index] else PlanKind.FULL) to index
        }

        val occurrences = mutableMapOf<PlanKind, Int>()
        val days = mutableListOf<WorkoutDay>()

        for (weekday in 1..7) {
            val training = trainingByWeekday[weekday]
            if (training == null) {
                val note = restNotes[(weekday + days.size) % restNotes.size]
                days.add(
                    WorkoutDay(
                        id = IDs.uuid(),
                        planId = planId,
                        dayIndex = weekday - 1,
                        weekday = weekday,
                        title = "Recovery",
                        focus = emptyList(),
                        estimatedMinutes = 0,
                        warmup = emptyList(),
                        cooldown = emptyList(),
                        isRestDay = true,
                        restNote = note,
                        exercises = emptyList(),
                    ),
                )
                continue
            }

            val kind = training.first
            val meta = this.meta[kind] ?: DayMeta("Training", emptyList())
            val usedToday = mutableSetOf<String>()
            val exercises = mutableListOf<WorkoutExercise>()
            val range = repRange(goal, profile.experience)
            val occurrence = occurrences[kind] ?: 0
            occurrences[kind] = occurrence + 1
            val repeats = sequence.count { it == kind } > 1
            val kindSlots = slots[kind] ?: emptyList()
            val dayId = IDs.uuid()

            for (slotIndex in 0 until minOf(count, kindSlots.size)) {
                val exercise = pickExercise(
                    slot = kindSlots[slotIndex],
                    kind = kind,
                    dayIndex = training.second,
                    slotIndex = slotIndex,
                    profile = profile,
                    preferences = preferences,
                    used = usedToday,
                    catalog = catalog,
                ) ?: continue
                usedToday.add(exercise.id)
                exercises.add(
                    WorkoutExercise(
                        id = IDs.uuid(),
                        dayId = dayId,
                        exerciseId = exercise.id,
                        position = exercises.size,
                        sets = setCount(profile.experience, slotIndex),
                        repsMin = if (kind == PlanKind.MOBILITY) 5 else range.min,
                        repsMax = if (kind == PlanKind.MOBILITY) 8 else range.max,
                        restSeconds = if (kind == PlanKind.MOBILITY) 30 else range.rest,
                        notes = if (kind == PlanKind.MOBILITY) {
                            "Move slowly and breathe. Hold or flow through a comfortable range."
                        } else if (slotIndex == 0) {
                            "Leave one or two reps in reserve on the final set."
                        } else {
                            null
                        },
                    ),
                )
            }

            val title = if (repeats) "${meta.title} · ${('A' + occurrence)}" else meta.title
            days.add(
                WorkoutDay(
                    id = dayId,
                    planId = planId,
                    dayIndex = weekday - 1,
                    weekday = weekday,
                    title = title,
                    focus = meta.focus,
                    estimatedMinutes = minOf(preferences.sessionMinutes, 8 + exercises.size * 6 + 4),
                    warmup = warmup(kind),
                    cooldown = cooldown(kind),
                    isRestDay = false,
                    restNote = null,
                    exercises = exercises,
                ),
            )
        }

        val baseName = when (profile.experience) {
            Experience.BEGINNER -> "Foundation"
            Experience.INTERMEDIATE -> "Momentum"
            Experience.ADVANCED -> "Apex"
        }
        val createdAt = StoredTimestamp.now()
        return WorkoutPlan(
            id = planId,
            userId = userId,
            name = "$baseName · $trainingDays day${if (trainingDays == 1) "" else "s"}",
            goal = goal,
            experience = profile.experience,
            daysPerWeek = trainingDays,
            sessionMinutes = preferences.sessionMinutes,
            equipment = preferences.equipment,
            source = PlanSource.ON_DEVICE,
            createdAt = createdAt,
            days = days,
            algorithmVersion = ALGORITHM_VERSION,
            generatedAt = createdAt,
            status = PlanStatus.ACTIVE,
        )
    }

    private fun clamp(value: Int?, minimum: Int, maximum: Int, fallback: Int): Int =
        (value ?: fallback).coerceIn(minimum, maximum)

    fun planFromAIPayload(
        payload: AIPlanPayload,
        userId: String,
        profile: Profile,
        preferences: Preferences,
        catalog: List<Exercise> = ExerciseCatalog.all,
    ): WorkoutPlan? {
        if (payload.days.isEmpty()) return null
        val planId = IDs.uuid()
        val byWeekday = payload.days.associateBy { it.weekday.coerceIn(1, 7) }
        val validFocus = MuscleGroup.entries.toSet()
        val days = mutableListOf<WorkoutDay>()

        for (weekday in 1..7) {
            val dayId = IDs.uuid()
            val raw = byWeekday[weekday]
            if (raw == null || raw.isRestDay == true) {
                val note = raw?.restNote?.trim()?.takeIf { it.isNotEmpty() }
                days.add(
                    WorkoutDay(
                        id = dayId, planId = planId, dayIndex = weekday - 1, weekday = weekday,
                        title = "Recovery", focus = emptyList(), estimatedMinutes = 0,
                        warmup = emptyList(), cooldown = emptyList(), isRestDay = true,
                        restNote = note ?: restNotes[weekday % restNotes.size], exercises = emptyList(),
                    ),
                )
                continue
            }

            val exercises = mutableListOf<WorkoutExercise>()
            for (item in raw.exercises.orEmpty()) {
                val libraryExercise = catalog.firstOrNull { it.id == item.exerciseId }
                    ?: ExerciseCatalog.exercise(item.exerciseId)
                    ?: continue
                val notes = item.notes?.let { if (it.length > 240) it.take(240) else it }
                exercises.add(
                    WorkoutExercise(
                        id = IDs.uuid(),
                        dayId = dayId,
                        exerciseId = libraryExercise.id,
                        position = exercises.size,
                        sets = clamp(item.sets, 1, 5, 3),
                        repsMin = clamp(item.repsMin, 3, 30, 8),
                        repsMax = clamp(item.repsMax, 3, 40, 12),
                        restSeconds = clamp(item.restSeconds, 15, 300, 90),
                        notes = notes,
                    ),
                )
            }

            if (exercises.isEmpty()) {
                days.add(
                    WorkoutDay(
                        id = dayId, planId = planId, dayIndex = weekday - 1, weekday = weekday,
                        title = "Recovery", focus = emptyList(), estimatedMinutes = 0,
                        warmup = emptyList(), cooldown = emptyList(), isRestDay = true,
                        restNote = "Recovery day. The AI plan did not include a safe session here.",
                        exercises = emptyList(),
                    ),
                )
                continue
            }

            val title = raw.title?.trim()?.takeIf { it.isNotEmpty() }
            val focus = raw.focus.orEmpty()
                .mapNotNull { rawValue -> MuscleGroup.entries.firstOrNull { it.name.lowercase().replace('_', '-') == rawValue || serialName(it) == rawValue } }
                .filter { validFocus.contains(it) }
                .take(5)
            days.add(
                WorkoutDay(
                    id = dayId, planId = planId, dayIndex = weekday - 1, weekday = weekday,
                    title = (title ?: "Training day").take(60),
                    focus = focus,
                    estimatedMinutes = clamp(raw.estimatedMinutes, 10, 120, preferences.sessionMinutes),
                    warmup = (raw.warmup ?: warmup(PlanKind.FULL)).take(5),
                    cooldown = (raw.cooldown ?: cooldown(PlanKind.FULL)).take(5),
                    isRestDay = false, restNote = null, exercises = exercises,
                ),
            )
        }

        val trainingDays = days.count { !it.isRestDay }
        if (trainingDays == 0) return null

        val trimmedName = payload.name?.trim()
        val name = if (!trimmedName.isNullOrEmpty()) trimmedName.take(60)
        else "${if (profile.experience == Experience.BEGINNER) "Foundation" else "Momentum"} · $trainingDays days"

        val createdAt = StoredTimestamp.now()
        return WorkoutPlan(
            id = planId, userId = userId, name = name,
            goal = profile.goals.firstOrNull() ?: Goal.GENERAL,
            experience = profile.experience, daysPerWeek = trainingDays,
            sessionMinutes = preferences.sessionMinutes, equipment = preferences.equipment,
            source = PlanSource.AI, createdAt = createdAt, days = days,
            algorithmVersion = ALGORITHM_VERSION, generatedAt = createdAt, status = PlanStatus.ACTIVE,
        )
    }

    private fun serialName(group: MuscleGroup): String = group.name.lowercase().replace('_', '-')

    fun planForDate(plan: WorkoutPlan, epochMillis: Long): WorkoutDay? {
        val weekday = FormaDate.isoWeekday(epochMillis)
        return plan.days.firstOrNull { it.weekday == weekday }
    }

    fun nextTrainingDay(plan: WorkoutPlan, from: Long): WorkoutDay? {
        val todayIndex = FormaDate.isoWeekday(from) - 1
        for (offset in 1..7) {
            val index = ((todayIndex + offset) % 7 + 7) % 7
            val day = plan.days.getOrNull(index) ?: continue
            if (!day.isRestDay) return day
        }
        return null
    }

    fun exerciseName(id: String): String = ExerciseCatalog.name(id)
}
