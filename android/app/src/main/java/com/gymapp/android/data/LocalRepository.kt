package com.gymapp.android.data

import com.gymapp.android.data.local.FormaDatabase
import com.gymapp.android.data.local.Mappers
import com.gymapp.android.data.local.Mappers.toDomain
import com.gymapp.android.data.local.Mappers.toEntity
import com.gymapp.android.data.local.SettingEntity
import com.gymapp.android.domain.ActiveWorkout
import com.gymapp.android.domain.CompletedSet
import com.gymapp.android.domain.Exercise
import com.gymapp.android.domain.ExerciseCatalog
import com.gymapp.android.domain.Preferences
import com.gymapp.android.domain.Profile
import com.gymapp.android.domain.ProgressRecord
import com.gymapp.android.domain.ReminderSettings
import com.gymapp.android.domain.WorkoutDay
import com.gymapp.android.domain.WorkoutPlan
import com.gymapp.android.domain.WorkoutSession

/**
 * The on-device training store. Mirrors the iOS GRDB repository: training data
 * is device-local by design; only the separate account layer talks to the server.
 */
class LocalRepository(private val database: FormaDatabase) {

    private val profiles = database.profilesDao()
    private val preferences = database.preferencesDao()
    private val plans = database.planDao()
    private val sessions = database.sessionsDao()
    private val progress = database.progressDao()
    private val reminders = database.remindersDao()
    private val settings = database.settingsDao()

    suspend fun listProfiles(): List<Profile> = profiles.all().map { it.toDomain() }

    suspend fun activeProfileId(): String? = settings.get(KEY_ACTIVE_PROFILE)

    suspend fun setActiveProfileId(id: String) =
        settings.put(SettingEntity(KEY_ACTIVE_PROFILE, id))

    suspend fun getProfile(userId: String): Profile? = profiles.byId(userId)?.toDomain()

    suspend fun saveProfile(profile: Profile) = profiles.upsert(profile.toEntity())

    suspend fun deleteProfile(userId: String) = profiles.delete(userId)

    suspend fun getPreferences(userId: String): Preferences? = preferences.byUser(userId)?.toDomain()

    suspend fun savePreferences(value: Preferences) = preferences.upsert(value.toEntity())

    suspend fun getActivePlan(userId: String): WorkoutPlan? {
        val plan = plans.activePlan(userId) ?: return null
        val days = plans.days(plan.id)
        val slots = plans.exercisesForPlan(plan.id).groupBy { it.dayId }
        val domainDays: List<WorkoutDay> = days.map { day ->
            day.toDomain(slots[day.id].orEmpty().map { it.toDomain() })
        }
        return plan.toDomain(domainDays)
    }

    suspend fun allPlans(userId: String): List<WorkoutPlan> = plans.allPlans(userId).mapNotNull { plan ->
        val days = plans.days(plan.id)
        val slots = plans.exercisesForPlan(plan.id).groupBy { it.dayId }
        plan.toDomain(days.map { day -> day.toDomain(slots[day.id].orEmpty().map { it.toDomain() }) })
    }

    suspend fun savePlan(plan: WorkoutPlan) {
        plans.replacePlan(
            userId = plan.userId,
            plan = plan.toEntity(),
            days = plan.days.map { it.toEntity() },
            exercises = plan.days.flatMap { day -> day.exercises.map { it.toEntity() } },
        )
    }

    suspend fun getSessions(userId: String): List<WorkoutSession> =
        sessions.sessions(userId).map { entity ->
            entity.toDomain(sessions.sets(entity.id).map { it.toDomain() })
        }

    suspend fun saveSession(session: WorkoutSession) {
        sessions.saveSession(session.toEntity(), session.sets.map { it.toEntity() })
    }

    suspend fun deleteSession(id: String) = sessions.deleteSession(id)

    suspend fun getReminderSettings(userId: String): ReminderSettings =
        reminders.byUser(userId)?.toDomain() ?: ReminderSettings.defaults(userId)

    suspend fun saveReminderSettings(value: ReminderSettings) = reminders.upsert(value.toEntity())

    suspend fun listProgressRecords(userId: String): List<ProgressRecord> =
        progress.records(userId).map { it.toDomain() }

    suspend fun saveProgressRecord(record: ProgressRecord) = progress.upsert(record.toEntity())

    suspend fun deleteProgressRecord(id: String) = progress.delete(id)

    suspend fun getExercises(): List<Exercise> = ExerciseCatalog.all

    suspend fun loadActiveWorkout(userId: String): ActiveWorkout? =
        Mappers.activeWorkoutFromJson(settings.get(activeWorkoutKey(userId)))

    suspend fun saveActiveWorkout(workout: ActiveWorkout) = settings.put(
        SettingEntity(activeWorkoutKey(workout.userId), Mappers.activeWorkoutToJson(workout)),
    )

    suspend fun clearActiveWorkout(userId: String) = settings.remove(activeWorkoutKey(userId))

    suspend fun clearAllData() {
        database.clearAllTables()
    }

    suspend fun deleteProfileData(userId: String) {
        plans.deleteExercisesForUser(userId)
        plans.deleteDaysForUser(userId)
        plans.deletePlans(userId)
        sessions.deleteSetsForUser(userId)
        sessions.deleteSessionsForUser(userId)
        progress.deleteForUser(userId)
        preferences.deleteForUser(userId)
        reminders.deleteForUser(userId)
        profiles.delete(userId)
        clearActiveWorkout(userId)
    }

    private fun activeWorkoutKey(userId: String): String = "active-workout-$userId"

    companion object {
        private const val KEY_ACTIVE_PROFILE = "active-profile-id"
    }
}
