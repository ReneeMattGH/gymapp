package com.gymapp.android.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * One resizable widget backed by three RemoteViews families. Every callback
 * rebuilds from the local database and re-arms the midnight rollover alarm.
 */
class FitnessWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetUpdater.ACTION_REFRESH,
            WidgetUpdater.ACTION_MIDNIGHT,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            -> refreshAsync(context)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        refreshAsync(context)
    }

    override fun onEnabled(context: Context) {
        refreshAsync(context)
    }

    override fun onDisabled(context: Context) {
        WidgetUpdater.cancelMidnight(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { WidgetSettings.clearFocus(context, it) }
        refreshAsync(context)
    }

    override fun onRestored(context: Context, oldWidgetIds: IntArray, newWidgetIds: IntArray) {
        refreshAsync(context)
    }

    private fun refreshAsync(context: Context) {
        val pending = goAsync()
        val app = context.applicationContext
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                if (WidgetUpdater.widgetIds(app).isEmpty()) {
                    WidgetUpdater.cancelMidnight(app)
                } else {
                    WidgetUpdater.renderAll(app)
                    WidgetUpdater.scheduleMidnight(app)
                }
            } catch (_: Exception) {
                // A failed refresh must never crash the launcher process callback.
            } finally {
                pending.finish()
            }
        }
    }
}
