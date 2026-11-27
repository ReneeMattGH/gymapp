package com.gymapp.android.data.local

import com.gymapp.android.domain.ActiveWorkout
import com.gymapp.android.domain.CompletedSet
import com.gymapp.android.domain.Difficulty
import com.gymapp.android.domain.Exercise
import com.gymapp.android.domain.ExerciseDifficultyFeedback
import com.gymapp.android.domain.Experience
import com.gymapp.android.domain.Goal
import com.gymapp.android.domain.MuscleGroup
import com.gymapp.android.domain.PlanSource
import com.gymapp.android.domain.PlanStatus
import com.gymapp.android.domain.Preferences
import com.gymapp.android.domain.Profile
import com.gymapp.android.domain.ProgressRecord
import com.gymapp.android.domain.ReminderSettings
import com.gymapp.android.domain.SessionStatus
import com.gymapp.android.domain.TrainingEnvironment
import com.gymapp.android.domain.TrainingSplit
import com.gymapp.android.domain.UnitSystem
import com.gymapp.android.domain.WorkoutDay
import com.gymapp.android.domain.WorkoutExercise
import com.gymapp.android.domain.WorkoutPlan
import com.gymapp.android.domain.WorkoutSession
import com.gymapp.android.domain.Equipment
import kotlinx.serialization.serializer

private inline fun <reified T : Enum<T>> enumOf(name: String?, fallback: T): T =
    name?.let { raw -> enumValues<T>().firstOrNull { it.name == raw } } ?: fallback

object Mappers {
    fun ProfileEntity.toDomain(): Profile = Profile(
        id = id,
        name = name,
        age = age,
        heightCm = heightCm,
        experience = enumOf(experience, Experience.BEGINNER),
        environment = enumOf(environment, TrainingEnvironment.BOTH),
        goals = StoreJson.decodeList(Goal.serializer(), goals),
        secondaryGoals = secondaryGoals?.let { StoreJson.decodeList(Goal.serializer(), it) },
        currentSplit = currentSplit?.let { enumOf<TrainingSplit>(it, TrainingSplit.NONE) },
        limitations = limitations,
        photoPath = photoPath,
        onboardingCompleted = onboardingCompleted,
        createdAt = createdAt,
    )

    fun Profile.toEntity(): ProfileEntity = ProfileEntity(
        id = id,
        name = name,
        age = age,
        heightCm = heightCm,
        experience = experience.name,
        environment = environment.name,
        goals = StoreJson.encodeList(Goal.serializer(), goals),
        secondaryGoals = secondaryGoals?.let { StoreJson.encodeList(Goal.serializer(), it) },
        currentSplit = currentSplit?.name,
        limitations = limitations,
        photoPath = photoPath,
        onboardingCompleted = onboardingCompleted,
        createdAt = createdAt,
    )

    fun PreferencesEntity.toDomain(): Preferences = Preferences(
        userId = userId,
        workoutDays = StoreJson.decodeList(serializer<Int>(), workoutDays),
        sessionMinutes = sessionMinutes,
        equipment = StoreJson.decodeList(Equipment.serializer(), equipment),
        avoidExercises = StoreJson.decodeList(serializer<String>(), avoidExercises),
        preferredExercises = preferredExercises?.let {
            StoreJson.decodeList(serializer<String>(), it)
        },
        reminderTime = reminderTime,
        units = enumOf(units, UnitSystem.KG),
    )

    fun Preferences.toEntity(): PreferencesEntity = PreferencesEntity(
        userId = userId,
        workoutDays = StoreJson.encodeList(serializer<Int>(), workoutDays),
        sessionMinutes = sessionMinutes,
        equipment = StoreJson.encodeList(Equipment.serializer(), equipment),
        avoidExercises = StoreJson.encodeList(serializer<String>(), avoidExercises),
        preferredExercises = preferredExercises?.let {
            StoreJson.encodeList(serializer<String>(), it)
        },
        reminderTime = reminderTime,
        units = units.name,
    )

    fun RemindersEntity.toDomain(): ReminderSettings = ReminderSettings(
        userId = userId,
        enabled = enabled,
        workoutTime = workoutTime,
        days = StoreJson.decodeList(serializer<Int>(), days),
        restDayReminders = restDayReminders,
        hydrationReminders = hydrationReminders,
        weeklyProgressReminder = weeklyProgressReminder,
        scheduledIds = StoreJson.decodeList(serializer<String>(), scheduledIds),
    )

    fun ReminderSettings.toEntity(): RemindersEntity = RemindersEntity(
        userId = userId,
        enabled = enabled,
        workoutTime = workoutTime,
        days = StoreJson.encodeList(serializer<Int>(), days),
        restDayReminders = restDayReminders,
        hydrationReminders = hydrationReminders,
        weeklyProgressReminder = weeklyProgressReminder,
        scheduledIds = StoreJson.encodeList(serializer<String>(), scheduledIds),
    )

    fun ProgressEntity.toDomain(): ProgressRecord = ProgressRecord(
        id = id,
        userId = userId,
        recordedAt = recordedAt,
        bodyweightKg = bodyweightKg,
        notes = notes,
    )

    fun ProgressRecord.toEntity(): ProgressEntity = ProgressEntity(
        id = id,
        userId = userId,
        recordedAt = recordedAt,
        bodyweightKg = bodyweightKg,
        notes = notes,
    )

    fun PlanEntity.toDomain(days: List<WorkoutDay>): WorkoutPlan = WorkoutPlan(
        id = id,
        userId = userId,
        name = name,
        goal = enumOf(goal, Goal.GENERAL),
        experience = enumOf(experience, Experience.BEGINNER),
        daysPerWeek = daysPerWeek,
        sessionMinutes = sessionMinutes,
        equipment = StoreJson.decodeList(Equipment.serializer(), equipment),
        source = enumOf(source, PlanSource.ON_DEVICE),
        createdAt = createdAt,
        days = days,
        algorithmVersion = algorithmVersion,
        generatedAt = generatedAt,
        status = status?.let { enumOf<PlanStatus>(it, PlanStatus.ACTIVE) },
        startDate = startDate,
        endDate = endDate,
    )

    fun WorkoutPlan.toEntity(): PlanEntity = PlanEntity(
        id = id,
        userId = userId,
        name = name,
        goal = goal.name,
        experience = experience.name,
        daysPerWeek = daysPerWeek,
        sessionMinutes = sessionMinutes,
        equipment = StoreJson.encodeList(Equipment.serializer(), equipment),
        source = source.name,
        createdAt = createdAt,
        algorithmVersion = algorithmVersion,
        generatedAt = generatedAt,
        status = status?.name,
        startDate = startDate,
        endDate = endDate,
    )

    fun DayEntity.toDomain(exercises: List<WorkoutExercise>): WorkoutDay = WorkoutDay(
        id = id,
        planId = planId,
        dayIndex = dayIndex,
        weekday = weekday,
        title = title,
        focus = StoreJson.decodeList(MuscleGroup.serializer(), focus),
        estimatedMinutes = estimatedMinutes,
        warmup = StoreJson.decodeList(serializer<String>(), warmup),
        cooldown = StoreJson.decodeList(serializer<String>(), cooldown),
        isRestDay = isRestDay,
        restNote = restNote,
        exercises = exercises,
    )

    fun WorkoutDay.toEntity(): DayEntity = DayEntity(
        id = id,
        planId = planId,
        dayIndex = dayIndex,
        weekday = weekday,
        title = title,
        focus = StoreJson.encodeList(MuscleGroup.serializer(), focus),
        estimatedMinutes = estimatedMinutes,
        warmup = StoreJson.encodeList(serializer<String>(), warmup),
        cooldown = StoreJson.encodeList(serializer<String>(), cooldown),
        isRestDay = isRestDay,
        restNote = restNote,
    )

    fun ExerciseSlotEntity.toDomain(): WorkoutExercise = WorkoutExercise(
        id = id,
        dayId = dayId,
        exerciseId = exerciseId,
        position = position,
        sets = sets,
        repsMin = repsMin,
        repsMax = repsMax,
        restSeconds = restSeconds,
        notes = notes,
    )

    fun WorkoutExercise.toEntity(): ExerciseSlotEntity = ExerciseSlotEntity(
        id = id,
        dayId = dayId,
        exerciseId = exerciseId,
        position = position,
        sets = sets,
        repsMin = repsMin,
        repsMax = repsMax,
        restSeconds = restSeconds,
        notes = notes,
    )

    fun SessionEntity.toDomain(sets: List<CompletedSet>): WorkoutSession = WorkoutSession(
        id = id,
        userId = userId,
        planDayId = planDayId,
        title = title,
        focus = StoreJson.decodeList(MuscleGroup.serializer(), focus),
        startedAt = startedAt,
        endedAt = endedAt,
        durationSeconds = durationSeconds,
        status = enumOf(status, SessionStatus.COMPLETED),
        sets = sets,
        notes = notes,
        perceivedExertion = perceivedExertion,
        userFeedback = userFeedback,
        difficultyFeedback = difficultyFeedback?.let {
            enumOf<ExerciseDifficultyFeedback>(it, ExerciseDifficultyFeedback.APPROPRIATE)
        },
    )

    fun WorkoutSession.toEntity(): SessionEntity = SessionEntity(
        id = id,
        userId = userId,
        planDayId = planDayId,
        title = title,
        focus = StoreJson.encodeList(MuscleGroup.serializer(), focus),
        startedAt = startedAt,
        endedAt = endedAt,
        durationSeconds = durationSeconds,
        status = status.name,
        notes = notes,
        perceivedExertion = perceivedExertion,
        userFeedback = userFeedback,
        difficultyFeedback = difficultyFeedback?.name,
    )

    fun CompletedSetEntity.toDomain(): CompletedSet = CompletedSet(
        id = id,
        sessionId = sessionId,
        workoutExerciseId = workoutExerciseId,
        exerciseId = exerciseId,
        setNumber = setNumber,
        reps = reps,
        weightKg = weightKg,
        completedAt = completedAt,
        rir = rir,
        isWarmup = isWarmup,
    )

    fun CompletedSet.toEntity(): CompletedSetEntity = CompletedSetEntity(
        id = id,
        sessionId = sessionId,
        workoutExerciseId = workoutExerciseId,
        exerciseId = exerciseId,
        setNumber = setNumber,
        reps = reps,
        weightKg = weightKg,
        completedAt = completedAt,
        rir = rir,
        isWarmup = isWarmup,
    )

    fun activeWorkoutToJson(workout: ActiveWorkout): String =
        StoreJson.encode(ActiveWorkout.serializer(), workout)

    fun activeWorkoutFromJson(text: String?): ActiveWorkout? =
        text?.let { runCatching { StoreJson.decode(ActiveWorkout.serializer(), it) }.getOrNull() }

    /** The catalog is bundled, so this conversion is only used for parity checks. */
    fun Exercise.roundTrip(): Exercise = this

    fun difficultyOf(raw: String?): Difficulty = enumOf(raw, Difficulty.BEGINNER)
}
