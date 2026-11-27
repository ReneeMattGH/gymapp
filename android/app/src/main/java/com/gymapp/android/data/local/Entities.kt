package com.gymapp.android.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "profiles")
data class ProfileEntity(
    @PrimaryKey val id: String,
    val name: String,
    val age: Int?,
    val heightCm: Double?,
    val experience: String,
    val environment: String,
    val goals: String,
    val secondaryGoals: String?,
    val currentSplit: String?,
    val limitations: String?,
    val photoPath: String?,
    val onboardingCompleted: Boolean,
    val createdAt: Long,
)

@Entity(tableName = "user_preferences")
data class PreferencesEntity(
    @PrimaryKey val userId: String,
    val workoutDays: String,
    val sessionMinutes: Int,
    val equipment: String,
    val avoidExercises: String,
    val preferredExercises: String?,
    val reminderTime: String,
    val units: String,
)

@Entity(tableName = "workout_plans")
data class PlanEntity(
    @PrimaryKey val id: String,
    val userId: String,
    val name: String,
    val goal: String,
    val experience: String,
    val daysPerWeek: Int,
    val sessionMinutes: Int,
    val equipment: String,
    val source: String,
    val createdAt: Long,
    val algorithmVersion: Int?,
    val generatedAt: Long?,
    val status: String?,
    val startDate: Long?,
    val endDate: Long?,
)

@Entity(tableName = "workout_days")
data class DayEntity(
    @PrimaryKey val id: String,
    val planId: String,
    val dayIndex: Int,
    val weekday: Int?,
    val title: String,
    val focus: String,
    val estimatedMinutes: Int,
    val warmup: String,
    val cooldown: String,
    val isRestDay: Boolean,
    val restNote: String?,
)

@Entity(tableName = "workout_exercises")
data class ExerciseSlotEntity(
    @PrimaryKey val id: String,
    val dayId: String,
    val exerciseId: String,
    val position: Int,
    val sets: Int,
    val repsMin: Int,
    val repsMax: Int,
    val restSeconds: Int,
    val notes: String?,
)

@Entity(tableName = "workout_sessions")
data class SessionEntity(
    @PrimaryKey val id: String,
    val userId: String,
    val planDayId: String?,
    val title: String,
    val focus: String,
    val startedAt: Long,
    val endedAt: Long?,
    val durationSeconds: Int,
    val status: String,
    val notes: String?,
    val perceivedExertion: Int?,
    val userFeedback: String?,
    val difficultyFeedback: String?,
)

@Entity(tableName = "completed_sets")
data class CompletedSetEntity(
    @PrimaryKey val id: String,
    val sessionId: String,
    val workoutExerciseId: String?,
    val exerciseId: String,
    val setNumber: Int,
    val reps: Int,
    val weightKg: Double?,
    val completedAt: Long,
    val rir: Double?,
    val isWarmup: Boolean?,
)

@Entity(tableName = "progress_records")
data class ProgressEntity(
    @PrimaryKey val id: String,
    val userId: String,
    val recordedAt: Long,
    val bodyweightKg: Double?,
    val notes: String?,
)

@Entity(tableName = "reminder_settings")
data class RemindersEntity(
    @PrimaryKey val userId: String,
    val enabled: Boolean,
    val workoutTime: String,
    val days: String,
    val restDayReminders: Boolean,
    val hydrationReminders: Boolean,
    val weeklyProgressReminder: Boolean,
    val scheduledIds: String,
)

@Entity(tableName = "app_settings")
data class SettingEntity(
    @PrimaryKey val key: String,
    val value: String,
)
