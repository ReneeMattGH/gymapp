package com.gymapp.android.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// MARK: - Enumerations

@Serializable
enum class Experience(val label: String) {
    @SerialName("beginner") BEGINNER("Beginner"),
    @SerialName("intermediate") INTERMEDIATE("Intermediate"),
    @SerialName("advanced") ADVANCED("Advanced"),
}

@Serializable
enum class TrainingEnvironment(val label: String) {
    @SerialName("gym") GYM("Gym"),
    @SerialName("home") HOME("Home"),
    @SerialName("both") BOTH("Both"),
}

@Serializable
enum class Goal(val label: String, val shortLabel: String) {
    @SerialName("strength") STRENGTH("Build strength", "Strength"),
    @SerialName("muscle-development") MUSCLE("Build muscle", "Muscle"),
    @SerialName("endurance") ENDURANCE("Improve endurance", "Endurance"),
    @SerialName("athletic-conditioning") ATHLETIC("Athletic conditioning", "Athletic"),
    @SerialName("mobility") MOBILITY("Move better", "Mobility"),
    @SerialName("general") GENERAL("General fitness", "General"),
    @SerialName("consistency") CONSISTENCY("Build consistency", "Consistency"),
}

@Serializable
enum class Equipment(val label: String) {
    @SerialName("bodyweight") BODYWEIGHT("Bodyweight"),
    @SerialName("dumbbells") DUMBBELLS("Dumbbells"),
    @SerialName("barbell") BARBELL("Barbell"),
    @SerialName("kettlebell") KETTLEBELL("Kettlebell"),
    @SerialName("resistance-band") RESISTANCE_BAND("Resistance bands"),
    @SerialName("cable") CABLE("Cable station"),
    @SerialName("machine") MACHINE("Machines"),
    @SerialName("bench") BENCH("Bench"),
    @SerialName("pull-up-bar") PULL_UP_BAR("Pull-up bar"),
    @SerialName("jump-rope") JUMP_ROPE("Jump rope"),
}

@Serializable
enum class ExerciseCategory(val label: String) {
    @SerialName("strength") STRENGTH("Strength"),
    @SerialName("conditioning") CONDITIONING("Conditioning"),
    @SerialName("mobility") MOBILITY("Mobility"),
}

@Serializable
enum class MuscleGroup(val label: String) {
    @SerialName("chest") CHEST("Chest"),
    @SerialName("back") BACK("Back"),
    @SerialName("shoulders") SHOULDERS("Shoulders"),
    @SerialName("arms") ARMS("Arms"),
    @SerialName("quads") QUADS("Quads"),
    @SerialName("hamstrings") HAMSTRINGS("Hamstrings"),
    @SerialName("glutes") GLUTES("Glutes"),
    @SerialName("calves") CALVES("Calves"),
    @SerialName("core") CORE("Core"),
    @SerialName("hips") HIPS("Hips"),
    @SerialName("full-body") FULL_BODY("Full body"),
    @SerialName("cardio") CARDIO("Cardio"),
    @SerialName("mobility") MOBILITY("Mobility"),
}

@Serializable
enum class Muscle(val label: String) {
    @SerialName("upper-chest") UPPER_CHEST("Upper chest"),
    @SerialName("middle-chest") MIDDLE_CHEST("Middle chest"),
    @SerialName("lower-chest") LOWER_CHEST("Lower chest"),
    @SerialName("lats") LATS("Lats"),
    @SerialName("upper-back") UPPER_BACK("Upper back"),
    @SerialName("traps") TRAPS("Traps"),
    @SerialName("rhomboids") RHOMBOIDS("Rhomboids"),
    @SerialName("front-deltoids") FRONT_DELTOIDS("Front delts"),
    @SerialName("side-deltoids") SIDE_DELTOIDS("Side delts"),
    @SerialName("rear-deltoids") REAR_DELTOIDS("Rear delts"),
    @SerialName("biceps") BICEPS("Biceps"),
    @SerialName("triceps") TRICEPS("Triceps"),
    @SerialName("forearms") FOREARMS("Forearms"),
    @SerialName("quadriceps") QUADRICEPS("Quadriceps"),
    @SerialName("hamstrings") HAMSTRINGS("Hamstrings"),
    @SerialName("glutes") GLUTES("Glutes"),
    @SerialName("calves") CALVES("Calves"),
    @SerialName("hip-abductors") HIP_ABDUCTORS("Hip abductors"),
    @SerialName("hip-adductors") HIP_ADDUCTORS("Hip adductors"),
    @SerialName("hip-flexors") HIP_FLEXORS("Hip flexors"),
    @SerialName("rectus-abdominis") RECTUS_ABDOMINIS("Rectus abdominis"),
    @SerialName("obliques") OBLIQUES("Obliques"),
    @SerialName("transverse-abdominis") TRANSVERSE_ABDOMINIS("Transverse abdominis"),
    @SerialName("spinal-erectors") SPINAL_ERECTORS("Spinal erectors"),
    @SerialName("full-body") FULL_BODY("Full body"),
    @SerialName("cardiovascular") CARDIOVASCULAR("Cardiovascular"),
    @SerialName("mobility") MOBILITY("Mobility");

    val group: MuscleGroup
        get() = when (this) {
            UPPER_CHEST, MIDDLE_CHEST, LOWER_CHEST -> MuscleGroup.CHEST
            LATS, UPPER_BACK, TRAPS, RHOMBOIDS -> MuscleGroup.BACK
            FRONT_DELTOIDS, SIDE_DELTOIDS, REAR_DELTOIDS -> MuscleGroup.SHOULDERS
            BICEPS, TRICEPS, FOREARMS -> MuscleGroup.ARMS
            QUADRICEPS -> MuscleGroup.QUADS
            HAMSTRINGS -> MuscleGroup.HAMSTRINGS
            GLUTES -> MuscleGroup.GLUTES
            CALVES -> MuscleGroup.CALVES
            HIP_ABDUCTORS, HIP_ADDUCTORS, HIP_FLEXORS -> MuscleGroup.HIPS
            RECTUS_ABDOMINIS, OBLIQUES, TRANSVERSE_ABDOMINIS, SPINAL_ERECTORS -> MuscleGroup.CORE
            FULL_BODY -> MuscleGroup.FULL_BODY
            CARDIOVASCULAR -> MuscleGroup.CARDIO
            MOBILITY -> MuscleGroup.MOBILITY
        }

    val searchTerms: List<String>
        get() = listOf(label, group.label)

    val isAnatomical: Boolean
        get() = this != FULL_BODY && this != CARDIOVASCULAR && this != MOBILITY

    companion object {
        fun legacy(group: MuscleGroup): Muscle = when (group) {
            MuscleGroup.CHEST -> MIDDLE_CHEST
            MuscleGroup.BACK -> LATS
            MuscleGroup.SHOULDERS -> FRONT_DELTOIDS
            MuscleGroup.ARMS -> BICEPS
            MuscleGroup.QUADS -> QUADRICEPS
            MuscleGroup.HAMSTRINGS -> HAMSTRINGS
            MuscleGroup.GLUTES -> GLUTES
            MuscleGroup.CALVES -> CALVES
            MuscleGroup.CORE -> RECTUS_ABDOMINIS
            MuscleGroup.HIPS -> HIP_ABDUCTORS
            MuscleGroup.FULL_BODY -> FULL_BODY
            MuscleGroup.CARDIO -> CARDIOVASCULAR
            MuscleGroup.MOBILITY -> MOBILITY
        }
    }
}

@Serializable
enum class MovementPattern(val label: String) {
    @SerialName("horizontal-push") HORIZONTAL_PUSH("Horizontal push"),
    @SerialName("vertical-push") VERTICAL_PUSH("Vertical push"),
    @SerialName("horizontal-pull") HORIZONTAL_PULL("Horizontal pull"),
    @SerialName("vertical-pull") VERTICAL_PULL("Vertical pull"),
    @SerialName("squat") SQUAT("Squat"),
    @SerialName("hinge") HINGE("Hinge"),
    @SerialName("lunge") LUNGE("Lunge"),
    @SerialName("carry") CARRY("Carry"),
    @SerialName("anti-extension") ANTI_EXTENSION("Anti-extension"),
    @SerialName("anti-rotation") ANTI_ROTATION("Anti-rotation"),
    @SerialName("lateral-stability") LATERAL_STABILITY("Lateral stability"),
    @SerialName("core-flexion") CORE_FLEXION("Core flexion"),
    @SerialName("rotation") ROTATION("Rotation"),
    @SerialName("elbow-flexion") ELBOW_FLEXION("Elbow flexion"),
    @SerialName("elbow-extension") ELBOW_EXTENSION("Elbow extension"),
    @SerialName("knee-flexion") KNEE_FLEXION("Knee flexion"),
    @SerialName("plantar-flexion") PLANTAR_FLEXION("Plantar flexion"),
    @SerialName("shoulder-abduction") SHOULDER_ABDUCTION("Shoulder abduction"),
    @SerialName("locomotion") LOCOMOTION("Locomotion"),
    @SerialName("jump") JUMP("Jump"),
    @SerialName("mobility") MOBILITY("Mobility"),
}

@Serializable
enum class CompoundClass(val label: String) {
    @SerialName("compound") COMPOUND("Compound"),
    @SerialName("isolation") ISOLATION("Isolation"),
}

@Serializable
enum class PlanStatus {
    @SerialName("active") ACTIVE,
    @SerialName("archived") ARCHIVED,
    @SerialName("completed") COMPLETED,
}

@Serializable
enum class TrainingSplit(val label: String) {
    @SerialName("none") NONE("No current split"),
    @SerialName("full-body") FULL_BODY("Full body"),
    @SerialName("upper-lower") UPPER_LOWER("Upper / lower"),
    @SerialName("push-pull-legs") PUSH_PULL_LEGS("Push / pull / legs"),
    @SerialName("other") OTHER("Other"),
}

@Serializable
enum class ExerciseDifficultyFeedback(val label: String) {
    @SerialName("too-easy") TOO_EASY("Too easy"),
    @SerialName("appropriate") APPROPRIATE("About right"),
    @SerialName("too-hard") TOO_HARD("Too hard"),
}

@Serializable
enum class Difficulty(val label: String) {
    @SerialName("beginner") BEGINNER("Beginner"),
    @SerialName("intermediate") INTERMEDIATE("Intermediate"),
    @SerialName("advanced") ADVANCED("Advanced"),
}

@Serializable
enum class PlanSource(val label: String) {
    @SerialName("ai") AI("AI generated"),
    @SerialName("on-device") ON_DEVICE("On-device"),
}

@Serializable
enum class SessionStatus {
    @SerialName("active") ACTIVE,
    @SerialName("paused") PAUSED,
    @SerialName("completed") COMPLETED,
    @SerialName("abandoned") ABANDONED,
}

@Serializable
enum class UnitSystem(val label: String, val abbreviation: String) {
    @SerialName("kg") KG("Kilograms", "kg"),
    @SerialName("lb") LB("Pounds", "lb"),
}

@Serializable
enum class PlanKind {
    @SerialName("full") FULL,
    @SerialName("upper") UPPER,
    @SerialName("lower") LOWER,
    @SerialName("push") PUSH,
    @SerialName("pull") PULL,
    @SerialName("legs") LEGS,
    @SerialName("mobility") MOBILITY,
}

@Serializable
enum class WorkoutRunStatus {
    @SerialName("active") ACTIVE,
    @SerialName("paused") PAUSED,
}

enum class ThemeMode(val label: String) {
    DARK("Dark"),
    LIGHT("Light"),
    SYSTEM("System");

    companion object {
        fun from(raw: String?): ThemeMode = entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: DARK
    }
}

// MARK: - Domain models

@Serializable
data class Profile(
    val id: String,
    val name: String,
    val age: Int? = null,
    val heightCm: Double? = null,
    val experience: Experience,
    val environment: TrainingEnvironment,
    val goals: List<Goal>,
    val secondaryGoals: List<Goal>? = null,
    val currentSplit: TrainingSplit? = null,
    val limitations: String? = null,
    val photoPath: String? = null,
    val onboardingCompleted: Boolean,
    val createdAt: Long,
)

@Serializable
data class Preferences(
    val userId: String,
    val workoutDays: List<Int> = listOf(1, 3, 5),
    val sessionMinutes: Int = 45,
    val equipment: List<Equipment> = listOf(Equipment.BODYWEIGHT, Equipment.DUMBBELLS, Equipment.BENCH),
    val avoidExercises: List<String> = emptyList(),
    val preferredExercises: List<String>? = null,
    val reminderTime: String = "18:00",
    val units: UnitSystem = UnitSystem.KG,
)

@Serializable
data class ExerciseSource(
    val title: String,
    val publisher: String? = null,
    val url: String? = null,
    val note: String? = null,
)

@Serializable
data class Exercise(
    val id: String,
    val name: String,
    val alternativeNames: List<String> = emptyList(),
    val category: ExerciseCategory,
    val primaryMuscles: List<Muscle>,
    val secondaryMuscles: List<Muscle> = emptyList(),
    val equipment: List<Equipment> = emptyList(),
    val difficulty: Difficulty = Difficulty.BEGINNER,
    val experienceLevel: Experience = Experience.BEGINNER,
    val movementPattern: MovementPattern? = null,
    val compoundClass: CompoundClass? = null,
    val instructions: List<String> = emptyList(),
    val setupInstructions: List<String> = emptyList(),
    val executionSteps: List<String> = emptyList(),
    val cues: List<String> = emptyList(),
    val breathingGuidance: String? = null,
    val mistakes: List<String> = emptyList(),
    val safetyConsiderations: List<String> = emptyList(),
    val variations: List<String> = emptyList(),
    val alternatives: List<String> = emptyList(),
    val isUnilateral: Boolean = false,
    val supportedGoals: List<Goal> = emptyList(),
    val sourceReferences: List<ExerciseSource> = emptyList(),
    val mediaURL: String? = null,
    val isActive: Boolean = true,
    val source: String? = null,
) {
    val primaryGroups: List<MuscleGroup>
        get() = primaryMuscles.map { it.group }.distinct().sortedBy { it.name }

    val secondaryGroups: List<MuscleGroup>
        get() = secondaryMuscles.map { it.group }.distinct().sortedBy { it.name }

    val steps: List<String>
        get() = executionSteps.ifEmpty { instructions }
}

@Serializable
data class WorkoutExercise(
    val id: String,
    val dayId: String,
    val exerciseId: String,
    val position: Int,
    val sets: Int,
    val repsMin: Int,
    val repsMax: Int,
    val restSeconds: Int,
    val notes: String? = null,
)

@Serializable
data class WorkoutDay(
    val id: String,
    val planId: String,
    val dayIndex: Int,
    val weekday: Int? = null,
    val title: String,
    val focus: List<MuscleGroup> = emptyList(),
    val estimatedMinutes: Int,
    val warmup: List<String> = emptyList(),
    val cooldown: List<String> = emptyList(),
    val isRestDay: Boolean,
    val restNote: String? = null,
    val exercises: List<WorkoutExercise> = emptyList(),
)

@Serializable
data class WorkoutPlan(
    val id: String,
    val userId: String,
    val name: String,
    val goal: Goal,
    val experience: Experience,
    val daysPerWeek: Int,
    val sessionMinutes: Int,
    val equipment: List<Equipment>,
    val source: PlanSource,
    val createdAt: Long,
    val days: List<WorkoutDay>,
    val algorithmVersion: Int? = null,
    val generatedAt: Long? = null,
    val status: PlanStatus? = null,
    val startDate: Long? = null,
    val endDate: Long? = null,
) {
    val trainingDays: List<WorkoutDay> get() = days.filter { !it.isRestDay }
    val totalExercises: Int get() = days.sumOf { it.exercises.size }
    val planStatus: PlanStatus get() = status ?: PlanStatus.ACTIVE
    val effectiveAlgorithmVersion: Int get() = algorithmVersion ?: 1
}

@Serializable
data class CompletedSet(
    val id: String,
    val sessionId: String,
    val workoutExerciseId: String? = null,
    val exerciseId: String,
    val setNumber: Int,
    val reps: Int,
    val weightKg: Double? = null,
    val completedAt: Long,
    val rir: Double? = null,
    val isWarmup: Boolean? = null,
) {
    val isWarmupSet: Boolean get() = isWarmup ?: false
}

@Serializable
data class WorkoutSession(
    val id: String,
    val userId: String,
    val planDayId: String? = null,
    val title: String,
    val focus: List<MuscleGroup> = emptyList(),
    val startedAt: Long,
    val endedAt: Long? = null,
    val durationSeconds: Int,
    val status: SessionStatus,
    val sets: List<CompletedSet> = emptyList(),
    val notes: String? = null,
    val perceivedExertion: Int? = null,
    val userFeedback: String? = null,
    val difficultyFeedback: ExerciseDifficultyFeedback? = null,
) {
    val isCompleted: Boolean get() = status == SessionStatus.COMPLETED && endedAt != null
}

@Serializable
data class ReminderSettings(
    val userId: String,
    val enabled: Boolean,
    val workoutTime: String,
    val days: List<Int>,
    val restDayReminders: Boolean,
    val hydrationReminders: Boolean,
    val weeklyProgressReminder: Boolean,
    val scheduledIds: List<String> = emptyList(),
) {
    companion object {
        fun defaults(userId: String) = ReminderSettings(
            userId = userId,
            enabled = false,
            workoutTime = "18:00",
            days = listOf(1, 3, 5),
            restDayReminders = true,
            hydrationReminders = false,
            weeklyProgressReminder = true,
            scheduledIds = emptyList(),
        )
    }
}

@Serializable
data class ProgressRecord(
    val id: String,
    val userId: String,
    val recordedAt: Long,
    val bodyweightKg: Double? = null,
    val notes: String? = null,
)

@Serializable
data class AppUser(
    val id: String,
    val email: String? = null,
    val emailVerified: Boolean = false,
)

// MARK: - Active workout

@Serializable
data class ActiveRest(
    val endsAt: Long? = null,
    val durationSeconds: Int,
    val pausedRemaining: Int? = null,
    val exerciseId: String,
) {
    fun remaining(now: Long): Int {
        pausedRemaining?.let { return maxOf(0, it) }
        val end = endsAt ?: return 0
        return maxOf(0, ((end - now) / 1000.0).let { kotlin.math.ceil(it).toInt() })
    }

    val isPaused: Boolean get() = pausedRemaining != null
}

@Serializable
data class ActiveWorkout(
    val sessionId: String,
    val userId: String,
    val planDayId: String,
    val planId: String,
    val title: String,
    val focus: List<MuscleGroup> = emptyList(),
    val warmup: List<String> = emptyList(),
    val cooldown: List<String> = emptyList(),
    val startedAt: Long,
    val status: WorkoutRunStatus,
    val pausedAt: Long? = null,
    val pausedSeconds: Int = 0,
    val currentExerciseIndex: Int = 0,
    val exercises: List<WorkoutExercise> = emptyList(),
    val sets: List<CompletedSet> = emptyList(),
    val rest: ActiveRest? = null,
) {
    fun elapsedSeconds(now: Long): Int {
        var elapsed = (now - startedAt) / 1000.0 - pausedSeconds
        if (status == WorkoutRunStatus.PAUSED && pausedAt != null) {
            elapsed -= (now - pausedAt) / 1000.0
        }
        return maxOf(0, elapsed.toInt())
    }

    val currentExercise: WorkoutExercise?
        get() = exercises.getOrNull(currentExerciseIndex)

    fun setsFor(exercise: WorkoutExercise): List<CompletedSet> =
        sets.filter { it.exerciseId == exercise.exerciseId && it.workoutExerciseId == exercise.id }

    val totalPlannedSets: Int get() = exercises.sumOf { it.sets }

    fun allSetsComplete(exercise: WorkoutExercise): Boolean =
        setsFor(exercise).size >= exercise.sets

    val isComplete: Boolean get() = exercises.all { allSetsComplete(it) }
}

// MARK: - AI payload contract

@Serializable
data class AIPlanPayload(
    val name: String? = null,
    val days: List<Day> = emptyList(),
) {
    @Serializable
    data class Day(
        val weekday: Int,
        val title: String? = null,
        val focus: List<String>? = null,
        val estimatedMinutes: Int? = null,
        val isRestDay: Boolean? = null,
        val restNote: String? = null,
        val warmup: List<String>? = null,
        val cooldown: List<String>? = null,
        val exercises: List<Item>? = null,
    )

    @Serializable
    data class Item(
        val exerciseId: String,
        val sets: Int? = null,
        val repsMin: Int? = null,
        val repsMax: Int? = null,
        val restSeconds: Int? = null,
        val notes: String? = null,
    )
}

// MARK: - Weekday helpers

object Weekday {
    val names = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

    fun short(weekday: Int): String =
        if (weekday in 1..7) names[weekday - 1] else "—"
}
