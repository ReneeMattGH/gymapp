package com.gymapp.android.widget

import android.content.Context
import androidx.core.content.edit

/** Per-widget small-widget emphasis plus the last time the app published data. */
object WidgetSettings {
    private const val FILE = "forma.widgets"
    private const val KEY_FOCUS_PREFIX = "focus."
    private const val KEY_PUBLISHED_AT = "last-published-at"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun focus(context: Context, appWidgetId: Int): WidgetFocus =
        WidgetFocus.from(prefs(context).getString(KEY_FOCUS_PREFIX + appWidgetId, null))

    fun setFocus(context: Context, appWidgetId: Int, focus: WidgetFocus) {
        prefs(context).edit { putString(KEY_FOCUS_PREFIX + appWidgetId, focus.name) }
    }

    fun clearFocus(context: Context, appWidgetId: Int) {
        prefs(context).edit { remove(KEY_FOCUS_PREFIX + appWidgetId) }
    }

    fun lastPublishedAt(context: Context): Long? =
        prefs(context).getLong(KEY_PUBLISHED_AT, 0L).takeIf { it > 0L }

    fun markPublished(context: Context, now: Long) {
        prefs(context).edit { putLong(KEY_PUBLISHED_AT, now) }
    }
}
