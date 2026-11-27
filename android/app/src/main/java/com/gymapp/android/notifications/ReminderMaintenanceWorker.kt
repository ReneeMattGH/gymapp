package com.gymapp.android.notifications

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.gymapp.android.data.local.FormaDatabase
import com.gymapp.android.data.local.Mappers.toDomain

/**
 * Android clears alarms when the app is force-stopped, and the system may drop
 * them after exact-alarm permission changes. This daily check re-arms them when
 * the count no longer matches the saved settings. It is a no-op otherwise.
 */
class ReminderMaintenanceWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        return try {
            val database = FormaDatabase.get(applicationContext)
            val activeId = database.settingsDao().get("active-profile-id")
            val stored = activeId?.let { database.remindersDao().byUser(it) }
            if (stored != null) {
                val settings = stored.toDomain()
                val scheduler = ReminderScheduler(applicationContext)
                if (settings.enabled &&
                    scheduler.canNotify() &&
                    scheduler.pendingCount() < scheduler.expectedCount(settings)
                ) {
                    scheduler.rearm(settings)
                }
            }
            Result.success()
        } catch (_: Exception) {
            Result.success()
        }
    }
}
