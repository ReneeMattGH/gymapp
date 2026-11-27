package com.gymapp.android.notifications

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.gymapp.android.MainActivity
import com.gymapp.android.R

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        val channel = intent.getStringExtra(EXTRA_CHANNEL) ?: ReminderScheduler.CHANNEL_WORKOUT
        val title = intent.getStringExtra(EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        val weekday = intent.getIntExtra(EXTRA_WEEKDAY, -1).takeIf { it in 1..7 }
        val hour = intent.getIntExtra(EXTRA_HOUR, 18)
        val minute = intent.getIntExtra(EXTRA_MINUTE, 0)

        val scheduler = ReminderScheduler(context)
        if (scheduler.canNotify()) {
            val manager = context.getSystemService(NotificationManager::class.java)
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = NotificationCompat.Builder(context, channel)
                .setSmallIcon(R.drawable.ic_stat_forma)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(open)
                .build()
            manager.notify(id.hashCode(), notification)
        }

        val next = ReminderScheduler.nextOccurrence(weekday, hour, minute)
        val followUp = intent(context, id, channel, title, body, weekday, hour, minute)
        val pending = PendingIntent.getBroadcast(
            context,
            id.hashCode(),
            followUp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(android.app.AlarmManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            alarmManager.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, next, pending)
        } else {
            alarmManager.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, next, pending)
        }
    }

    companion object {
        private const val EXTRA_ID = "forma.reminder.id"
        private const val EXTRA_CHANNEL = "forma.reminder.channel"
        private const val EXTRA_TITLE = "forma.reminder.title"
        private const val EXTRA_BODY = "forma.reminder.body"
        private const val EXTRA_WEEKDAY = "forma.reminder.weekday"
        private const val EXTRA_HOUR = "forma.reminder.hour"
        private const val EXTRA_MINUTE = "forma.reminder.minute"

        fun intent(
            context: Context,
            id: String,
            channel: String,
            title: String,
            body: String,
            weekday: Int?,
            hour: Int,
            minute: Int,
        ): Intent = Intent(context, ReminderReceiver::class.java).apply {
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_CHANNEL, channel)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_WEEKDAY, weekday ?: -1)
            putExtra(EXTRA_HOUR, hour)
            putExtra(EXTRA_MINUTE, minute)
        }
    }
}
