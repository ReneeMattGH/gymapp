package com.gymapp.android.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        ProfileEntity::class,
        PreferencesEntity::class,
        PlanEntity::class,
        DayEntity::class,
        ExerciseSlotEntity::class,
        SessionEntity::class,
        CompletedSetEntity::class,
        ProgressEntity::class,
        RemindersEntity::class,
        SettingEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class FormaDatabase : RoomDatabase() {
    abstract fun profilesDao(): ProfilesDao
    abstract fun preferencesDao(): PreferencesDao
    abstract fun planDao(): PlanDao
    abstract fun sessionsDao(): SessionsDao
    abstract fun progressDao(): ProgressDao
    abstract fun remindersDao(): RemindersDao
    abstract fun settingsDao(): SettingsDao

    companion object {
        @Volatile
        private var instance: FormaDatabase? = null

        fun get(context: Context): FormaDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(
                context.applicationContext,
                FormaDatabase::class.java,
                "forma.db",
            ).build().also { instance = it }
        }
    }
}
