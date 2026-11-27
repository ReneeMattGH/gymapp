package com.gymapp.android.widget

import com.gymapp.android.data.LocalRepository
import com.gymapp.android.data.local.FormaDatabase
import java.time.ZoneId

/**
 * Reads the active profile's training data straight from the on-device database
 * so every widget refresh renders the same state the app would show.
 */
class WidgetSnapshotRepository(
    private val database: FormaDatabase,
    private val zone: ZoneId = ZoneId.systemDefault(),
) {
    suspend fun load(now: Long): WidgetSnapshot {
        val activeId = database.settingsDao().get(ACTIVE_PROFILE_ID)
            ?: return WidgetSnapshot.empty(now, zone)
        val repository = LocalRepository(database)
        return WidgetSnapshotBuilder.build(
            accountId = activeId,
            plan = repository.getActivePlan(activeId),
            preferences = repository.getPreferences(activeId),
            sessions = repository.getSessions(activeId),
            activeWorkout = repository.loadActiveWorkout(activeId),
            now = now,
            zone = zone,
        )
    }

    companion object {
        const val ACTIVE_PROFILE_ID = "active-profile-id"
    }
}
