package com.gymapp.android.widget

import android.content.Context
import androidx.core.content.ContextCompat
import com.gymapp.android.R

/** Snapshot of the widget palette, resolved for the current system appearance. */
class WidgetPalette(context: Context) {
    val background: Int = color(context, R.color.widget_bg)
    val backgroundAlt: Int = color(context, R.color.widget_bg_alt)
    val surface: Int = color(context, R.color.widget_surface)
    val surfaceRaised: Int = color(context, R.color.widget_surface_raised)
    val text: Int = color(context, R.color.widget_text)
    val textSecondary: Int = color(context, R.color.widget_text_secondary)
    val textTertiary: Int = color(context, R.color.widget_text_tertiary)
    val accent: Int = color(context, R.color.widget_accent)
    val accentText: Int = color(context, R.color.widget_accent_text)
    val track: Int = color(context, R.color.widget_track)
    val warning: Int = color(context, R.color.widget_warning)

    private fun color(context: Context, id: Int): Int = ContextCompat.getColor(context, id)
}
