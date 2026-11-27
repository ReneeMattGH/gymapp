package com.gymapp.android.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import com.gymapp.android.data.local.FormaDatabase
import java.time.ZoneId

/**
 * Single entry point for widget refreshes. The app calls [publish] after a real
 * write (which also stamps the freshness time); the provider and system events
 * call [renderAll], which recomputes everything from Room without pretending it
 * is newly published.
 */
object WidgetUpdater {
    const val ACTION_REFRESH = "com.gymapp.android.widget.action.REFRESH"
    const val ACTION_MIDNIGHT = "com.gymapp.android.widget.action.MIDNIGHT"
    private const val MIDNIGHT_REQUEST_CODE = 731_100

    fun publish(context: Context) {
        WidgetSettings.markPublished(context, System.currentTimeMillis())
        refresh(context)
    }

    fun refresh(context: Context) {
        val intent = Intent(context.applicationContext, FitnessWidgetProvider::class.java)
            .setAction(ACTION_REFRESH)
        context.applicationContext.sendBroadcast(intent)
    }

    fun widgetIds(context: Context): IntArray {
        val manager = AppWidgetManager.getInstance(context.applicationContext) ?: return IntArray(0)
        val component = ComponentName(context.applicationContext, FitnessWidgetProvider::class.java)
        return manager.getAppWidgetIds(component)
    }

    suspend fun renderAll(context: Context) {
        val app = context.applicationContext
        val manager = AppWidgetManager.getInstance(app) ?: return
        val ids = manager.getAppWidgetIds(ComponentName(app, FitnessWidgetProvider::class.java))
        if (ids.isEmpty()) return

        val now = System.currentTimeMillis()
        val live = WidgetSnapshotRepository(FormaDatabase.get(app), ZoneId.systemDefault()).load(now)
        val publishedAt = WidgetSettings.lastPublishedAt(app)
        // Freshness reflects the last real app write, not this background rebuild.
        val snapshot = if (publishedAt != null) live.copy(generatedAt = publishedAt) else live
        val renderer = WidgetRenderer(app)
        ids.forEach { id ->
            val focus = WidgetSettings.focus(app, id)
            val views = renderer.render(id, snapshot, manager.getAppWidgetOptions(id), focus, now)
            manager.updateAppWidget(id, views)
        }
    }

    fun scheduleMidnight(context: Context) {
        val app = context.applicationContext
        val alarmManager = app.getSystemService(AlarmManager::class.java) ?: return
        val triggerAt = WidgetTimelineLogic.nextRefreshAt(System.currentTimeMillis())
        val pending = midnightPendingIntent(app, PendingIntent.FLAG_UPDATE_CURRENT) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }
    }

    fun cancelMidnight(context: Context) {
        val app = context.applicationContext
        val alarmManager = app.getSystemService(AlarmManager::class.java) ?: return
        val pending = midnightPendingIntent(app, PendingIntent.FLAG_NO_CREATE) ?: return
        alarmManager.cancel(pending)
    }

    private fun midnightPendingIntent(context: Context, flags: Int): PendingIntent? {
        val intent = Intent(context, FitnessWidgetProvider::class.java).setAction(ACTION_MIDNIGHT)
        return PendingIntent.getBroadcast(
            context,
            MIDNIGHT_REQUEST_CODE,
            intent,
            flags or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
