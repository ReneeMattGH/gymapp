package com.gymapp.android.notifications

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.gymapp.android.R
import com.gymapp.android.core.Formatters
import com.gymapp.android.domain.ReminderSettings
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit

data class ReminderScheduleResult(
    val scheduledIds: List<String>,
    val count: Int,
    val message: String,
)

/**
 * Local reminders with the same identifiers and copy as the iOS app. Android has
 * no "pending request" equivalent, so success means every alarm call completed.
 */
class ReminderScheduler(private val context: Context) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    fun canNotify(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    fun schedule(settings: ReminderSettings): ReminderScheduleResult {
        if (!settings.enabled) {
            cancelAll()
            return ReminderScheduleResult(emptyList(), 0, "Reminders are off. Nothing is scheduled.")
        }
        cancelAlarms()
        if (!canNotify()) {
            throw ReminderPermissionException()
        }
        val result = arm(settings)
        enqueueMaintenance()
        return result
    }

    /** Re-arms alarms without touching WorkManager; used by the maintenance worker itself. */
    fun rearm(settings: ReminderSettings): ReminderScheduleResult {
        cancelAlarms()
        return arm(settings)
    }

    private fun arm(settings: ReminderSettings): ReminderScheduleResult {
        createChannels(context)
        val (hour, minute) = Formatters.hourMinute(settings.workoutTime)
        val trainingDays = settings.days.filter { it in 1..7 }.toSet()
        val scheduled = mutableListOf<String>()

        for (day in trainingDays.sorted()) {
            scheduled += scheduleWeekly(
                id = "$PREFIX workout.$day",
                weekday = day,
                hour = hour,
                minute = minute,
                channel = CHANNEL_WORKOUT,
                title = "Training day",
                body = "Your session is ready. Even a short one keeps the habit alive.",
            )
        }

        if (settings.restDayReminders) {
            for (day in 1..7) {
                if (trainingDays.contains(day)) continue
                scheduled += scheduleWeekly(
                    id = "$PREFIX rest.$day",
                    weekday = day,
                    hour = 10,
                    minute = 0,
                    channel = CHANNEL_REST,
                    title = "Recovery day",
                    body = "A walk, some gentle mobility, and good sleep is today's work.",
                )
            }
        }

        if (settings.hydrationReminders) {
            for ((suffix, hourOfDay) in listOf("am" to 11, "pm" to 16)) {
                scheduled += scheduleWeekly(
                    id = "$PREFIX hydration.$suffix",
                    weekday = null,
                    hour = hourOfDay,
                    minute = 0,
                    channel = CHANNEL_HYDRATION,
                    title = "Water break",
                    body = "A glass of water now keeps the afternoon steady.",
                )
            }
        }

        if (settings.weeklyProgressReminder) {
            scheduled += scheduleWeekly(
                id = "$PREFIX weekly",
                weekday = 7,
                hour = 18,
                minute = 0,
                channel = CHANNEL_WEEKLY,
                title = "Your week in Forma",
                body = "Take a minute to review your sessions and plan the week ahead.",
            )
        }

        return ReminderScheduleResult(
            scheduledIds = scheduled,
            count = scheduled.size,
            message = "${scheduled.size} reminder${if (scheduled.size == 1) "" else "s"} scheduled on this device.",
        )
    }

    /** Number of alarms [schedule] would create for these settings. */
    fun expectedCount(settings: ReminderSettings): Int {
        if (!settings.enabled) return 0
        val trainingDays = settings.days.filter { it in 1..7 }.toSet()
        var count = trainingDays.size
        if (settings.restDayReminders) count += 7 - trainingDays.size
        if (settings.hydrationReminders) count += 2
        if (settings.weeklyProgressReminder) count += 1
        return count
    }

    fun cancelAll() {
        cancelAlarms()
        WorkManager.getInstance(context).cancelUniqueWork(MAINTENANCE_WORK)
    }

    private fun cancelAlarms() {
        for (id in knownIds()) {
            alarmManager.cancel(pendingIntent(id, null, null))
        }
    }

    private fun enqueueMaintenance() {
        val request = PeriodicWorkRequestBuilder<ReminderMaintenanceWorker>(24, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(MAINTENANCE_WORK, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    /** Number of Forma alarms the system currently holds, checked with FLAG_NO_CREATE. */
    fun pendingCount(): Int = knownIds().count { id ->
        PendingIntent.getBroadcast(
            context,
            requestCode(id),
            Intent(context, ReminderReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) != null
    }

    private fun scheduleWeekly(
        id: String,
        weekday: Int?,
        hour: Int,
        minute: Int,
        channel: String,
        title: String,
        body: String,
    ): String {
        val triggerAt = nextOccurrence(weekday, hour, minute)
        val intent = ReminderReceiver.intent(context, id, channel, title, body, weekday, hour, minute)
        val pi = PendingIntent.getBroadcast(
            context,
            requestCode(id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
        }
        return id
    }

    private fun pendingIntent(id: String, intent: Intent?, weekday: Int?): PendingIntent {
        val target = intent ?: Intent(context, ReminderReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            requestCode(id),
            target,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun requestCode(id: String): Int = id.hashCode()

    private fun knownIds(): List<String> {
        val workout = (1..7).map { "$PREFIX workout.$it" }
        val rest = (1..7).map { "$PREFIX rest.$it" }
        return workout + rest + listOf(
            "$PREFIX hydration.am", "$PREFIX hydration.pm", "$PREFIX weekly",
        )
    }

    companion object {
        private const val MAINTENANCE_WORK = "forma.reminder-maintenance"
        const val PREFIX = "forma."
        const val CHANNEL_WORKOUT = "forma.workout"
        const val CHANNEL_REST = "forma.rest"
        const val CHANNEL_HYDRATION = "forma.hydration"
        const val CHANNEL_WEEKLY = "forma.weekly"

        fun nextOccurrence(weekday: Int?, hour: Int, minute: Int, now: LocalDateTime = LocalDateTime.now()): Long {
            val time = LocalTime.of(hour.coerceIn(0, 23), minute.coerceIn(0, 59))
            var date: LocalDate = now.toLocalDate()
            if (weekday != null) {
                val target = DayOfWeek.of(weekday.coerceIn(1, 7))
                while (date.dayOfWeek != target) date = date.plusDays(1)
            }
            var candidate = LocalDateTime.of(date, time)
            if (!candidate.isAfter(now)) candidate = candidate.plusDays(if (weekday == null) 1 else 7)
            return candidate.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        }

        fun createChannels(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            val channels = listOf(
                Triple(CHANNEL_WORKOUT, context.getString(R.string.notification_channel_workout), NotificationManager.IMPORTANCE_DEFAULT),
                Triple(CHANNEL_REST, context.getString(R.string.notification_channel_rest), NotificationManager.IMPORTANCE_LOW),
                Triple(CHANNEL_HYDRATION, context.getString(R.string.notification_channel_hydration), NotificationManager.IMPORTANCE_LOW),
                Triple(CHANNEL_WEEKLY, context.getString(R.string.notification_channel_weekly), NotificationManager.IMPORTANCE_DEFAULT),
            )
            for ((id, name, importance) in channels) {
                manager.createNotificationChannel(
                    NotificationChannel(id, name, importance).apply {
                        setShowBadge(id == CHANNEL_WORKOUT)
                    },
                )
            }
        }
    }
}

class ReminderPermissionException :
    Exception("Notification permission is not granted, so nothing was scheduled. Enable notifications for Forma in Android settings.")
