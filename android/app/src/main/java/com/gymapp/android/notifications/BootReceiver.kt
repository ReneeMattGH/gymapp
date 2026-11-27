package com.gymapp.android.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.gymapp.android.data.local.FormaDatabase
import com.gymapp.android.data.local.Mappers.toDomain
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Re-arms reminders after a reboot, when AlarmManager has forgotten them. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        val pending = goAsync()
        val appContext = context.applicationContext
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                ReminderScheduler.createChannels(appContext)
                val database = FormaDatabase.get(appContext)
                val activeId = database.settingsDao().get("active-profile-id")
                if (activeId != null) {
                    val stored = database.remindersDao().byUser(activeId) ?: return@launch
                    val settings = stored.toDomain()
                    if (settings.enabled) {
                        ReminderScheduler(appContext).schedule(settings)
                    }
                }
            } catch (_: Exception) {
                // A missing reminder is recoverable; crashing at boot is not.
            } finally {
                pending.finish()
            }
        }
    }
}
