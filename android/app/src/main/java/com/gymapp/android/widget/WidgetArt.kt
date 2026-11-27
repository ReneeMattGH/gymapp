package com.gymapp.android.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat
import com.gymapp.android.R
import kotlin.math.roundToInt

/** Bitmap art that RemoteViews cannot express with XML alone. */
object WidgetArt {
    fun brandMark(context: Context, sizePx: Int, color: Int): Bitmap {
        val size = maxOf(1, sizePx)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val w = size.toFloat()
        val h = size.toFloat()
        val bar = w * 0.16f
        val gap = w * 0.10f
        val radius = bar / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        canvas.drawRoundRect(RectF(0f, h * 0.55f, bar, h), radius, radius, paint)
        canvas.drawRoundRect(RectF(bar + gap, h * 0.28f, bar * 2f + gap, h), radius, radius, paint)
        paint.alpha = (Color.alpha(color) * 0.75f).roundToInt()
        val thirdLeft = (bar + gap) * 2f
        canvas.drawRoundRect(RectF(thirdLeft, h * 0.06f, thirdLeft + bar, h), radius, radius, paint)
        return bitmap
    }

    fun weekRing(
        context: Context,
        sizePx: Int,
        week: WidgetWeekSummary,
        palette: WidgetPalette,
    ): Bitmap {
        val size = maxOf(1, sizePx)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val lineWidth = size * 0.11f
        val center = size / 2f
        val radius = center - lineWidth / 2f
        val bounds = RectF(center - radius, center - radius, center + radius, center + radius)

        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = lineWidth
            color = palette.track
        }
        canvas.drawCircle(center, center, radius, track)

        if (week.goal > 0 && week.progress > 0) {
            val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = lineWidth
                strokeCap = Paint.Cap.ROUND
                color = palette.accent
            }
            canvas.drawArc(bounds, -90f, (week.progress * 360f).toFloat(), false, arc)
        }

        val fraction = WidgetText.weekFraction(week)
        val fractionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = font(context, R.font.space_grotesk_bold) ?: Typeface.DEFAULT_BOLD
            textSize = size * 0.22f
            color = palette.text
        }
        val maxTextWidth = size * 0.72f
        val measured = fractionPaint.measureText(fraction)
        if (measured > maxTextWidth && measured > 0f) {
            fractionPaint.textSize = fractionPaint.textSize * (maxTextWidth / measured)
        }
        canvas.drawText(fraction, center, center - size * 0.035f, fractionPaint)

        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = font(context, R.font.inter_medium) ?: Typeface.DEFAULT
            textSize = size * 0.11f
            color = palette.textTertiary
        }
        canvas.drawText("sessions", center, center + size * 0.18f, labelPaint)
        return bitmap
    }

    private fun font(context: Context, id: Int): Typeface? =
        runCatching { ResourcesCompat.getFont(context, id) }.getOrNull()
}
