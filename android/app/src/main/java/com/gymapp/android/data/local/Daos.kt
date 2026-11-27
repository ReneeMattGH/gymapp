package com.gymapp.android.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface ProfilesDao {
    @Query("SELECT * FROM profiles ORDER BY createdAt ASC")
    suspend fun all(): List<ProfileEntity>

    @Query("SELECT * FROM profiles WHERE id = :id")
    suspend fun byId(id: String): ProfileEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(profile: ProfileEntity)

    @Query("DELETE FROM profiles WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT COUNT(*) FROM profiles")
    suspend fun count(): Int
}

@Dao
interface PreferencesDao {
    @Query("SELECT * FROM user_preferences WHERE userId = :userId")
    suspend fun byUser(userId: String): PreferencesEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(preferences: PreferencesEntity)

    @Query("DELETE FROM user_preferences WHERE userId = :userId")
    suspend fun deleteForUser(userId: String)
}

@Dao
interface PlanDao {
    @Query("SELECT * FROM workout_plans WHERE userId = :userId AND (status = 'ACTIVE' OR status = 'active' OR status IS NULL) ORDER BY createdAt DESC LIMIT 1")
    suspend fun activePlan(userId: String): PlanEntity?

    @Query("SELECT * FROM workout_plans WHERE userId = :userId ORDER BY createdAt DESC")
    suspend fun allPlans(userId: String): List<PlanEntity>

    @Query("SELECT * FROM workout_plans WHERE id = :planId")
    suspend fun plan(planId: String): PlanEntity?

    @Query("SELECT * FROM workout_days WHERE planId = :planId ORDER BY dayIndex ASC")
    suspend fun days(planId: String): List<DayEntity>

    @Query("SELECT * FROM workout_exercises WHERE dayId = :dayId ORDER BY position ASC")
    suspend fun exercises(dayId: String): List<ExerciseSlotEntity>

    @Query(
        "SELECT e.* FROM workout_exercises e INNER JOIN workout_days d ON d.id = e.dayId " +
            "WHERE d.planId = :planId ORDER BY d.dayIndex ASC, e.position ASC",
    )
    suspend fun exercisesForPlan(planId: String): List<ExerciseSlotEntity>

    @Query("DELETE FROM workout_plans WHERE userId = :userId")
    suspend fun deletePlans(userId: String)

    @Query("DELETE FROM workout_days WHERE planId IN (SELECT id FROM workout_plans WHERE userId = :userId)")
    suspend fun deleteDaysForUser(userId: String)

    @Query(
        "DELETE FROM workout_exercises WHERE dayId IN " +
            "(SELECT d.id FROM workout_days d INNER JOIN workout_plans p ON p.id = d.planId WHERE p.userId = :userId)",
    )
    suspend fun deleteExercisesForUser(userId: String)

    @Query("DELETE FROM workout_days WHERE planId = :planId")
    suspend fun deleteDays(planId: String)

    @Query("DELETE FROM workout_exercises WHERE dayId IN (SELECT id FROM workout_days WHERE planId = :planId)")
    suspend fun deleteExercisesForPlan(planId: String)

    @Query("UPDATE workout_plans SET status = :status WHERE userId = :userId")
    suspend fun setStatusForAll(userId: String, status: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPlan(plan: PlanEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDays(days: List<DayEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertExercises(exercises: List<ExerciseSlotEntity>)

    @Transaction
    suspend fun replacePlan(
        userId: String,
        plan: PlanEntity,
        days: List<DayEntity>,
        exercises: List<ExerciseSlotEntity>,
    ) {
        deleteExercisesForUser(userId)
        deleteDaysForUser(userId)
        deletePlans(userId)
        insertPlan(plan)
        insertDays(days)
        insertExercises(exercises)
    }
}

@Dao
interface SessionsDao {
    @Query("SELECT * FROM workout_sessions WHERE userId = :userId ORDER BY startedAt DESC")
    suspend fun sessions(userId: String): List<SessionEntity>

    @Query("SELECT * FROM workout_sessions WHERE id = :id")
    suspend fun session(id: String): SessionEntity?

    @Query("SELECT * FROM completed_sets WHERE sessionId = :sessionId ORDER BY completedAt ASC, setNumber ASC")
    suspend fun sets(sessionId: String): List<CompletedSetEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSession(session: SessionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSets(sets: List<CompletedSetEntity>)

    @Query("DELETE FROM completed_sets WHERE sessionId = :sessionId")
    suspend fun deleteSets(sessionId: String)

    @Query("DELETE FROM workout_sessions WHERE id = :id")
    suspend fun deleteSession(id: String)

    @Transaction
    suspend fun saveSession(session: SessionEntity, sets: List<CompletedSetEntity>) {
        upsertSession(session)
        deleteSets(session.id)
        insertSets(sets)
    }

    @Query("SELECT COUNT(*) FROM workout_sessions")
    suspend fun count(): Int

    @Query("DELETE FROM completed_sets WHERE sessionId IN (SELECT id FROM workout_sessions WHERE userId = :userId)")
    suspend fun deleteSetsForUser(userId: String)

    @Query("DELETE FROM workout_sessions WHERE userId = :userId")
    suspend fun deleteSessionsForUser(userId: String)
}

@Dao
interface ProgressDao {
    @Query("SELECT * FROM progress_records WHERE userId = :userId ORDER BY recordedAt DESC")
    suspend fun records(userId: String): List<ProgressEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: ProgressEntity)

    @Query("DELETE FROM progress_records WHERE id = :id")
    suspend fun delete(id: String)

    @Query("DELETE FROM progress_records WHERE userId = :userId")
    suspend fun deleteForUser(userId: String)
}

@Dao
interface RemindersDao {
    @Query("SELECT * FROM reminder_settings WHERE userId = :userId")
    suspend fun byUser(userId: String): RemindersEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(reminders: RemindersEntity)

    @Query("DELETE FROM reminder_settings WHERE userId = :userId")
    suspend fun deleteForUser(userId: String)
}

@Dao
interface SettingsDao {
    @Query("SELECT value FROM app_settings WHERE key = :key")
    suspend fun get(key: String): String?

    @Query("SELECT value FROM app_settings WHERE key = :key")
    fun observe(key: String): Flow<String?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun put(setting: SettingEntity)

    @Query("DELETE FROM app_settings WHERE key = :key")
    suspend fun remove(key: String)

    @Query("DELETE FROM app_settings WHERE key LIKE 'active-workout-%'")
    suspend fun clearActiveWorkouts()
}
