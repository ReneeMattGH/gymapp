package com.gymapp.android.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import com.gymapp.android.MainActivity
import com.gymapp.android.R
import com.gymapp.android.core.AppDeepLink
import java.time.Instant
import java.time.ZoneId
import kotlin.math.roundToInt

enum class WidgetSize {
    SMALL,
    MEDIUM,
    LARGE;

    companion object {
        /** Launchers report cell dimensions as min/max pairs; the larger pair wins. */
        fun fromOptions(options: Bundle?): WidgetSize {
            if (options == null) return SMALL
            val width = maxOf(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH),
            )
            val height = maxOf(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT),
            )
            if (width <= 0) return SMALL
            return when {
                width >= 250 && height >= 220 -> LARGE
                width >= 250 -> MEDIUM
                else -> SMALL
            }
        }
    }
}

/**
 * Binds one snapshot to the RemoteViews tree for a single widget instance.
 * Every refresh rebuilds from Room, so the widget is never more stale than the
 * last write or the last midnight rollover.
 */
class WidgetRenderer(private val context: Context) {
    private val app = context.applicationContext
    private val palette = WidgetPalette(app)
    private val density = app.resources.displayMetrics.density
    private val zone: ZoneId = ZoneId.systemDefault()

    fun render(
        appWidgetId: Int,
        snapshot: WidgetSnapshot,
        options: Bundle?,
        focus: WidgetFocus,
        now: Long = System.currentTimeMillis(),
    ): RemoteViews {
        val size = WidgetSize.fromOptions(options)
        val layout = when {
            size == WidgetSize.SMALL -> when (focus) {
                WidgetFocus.WEEKLY -> R.layout.widget_small_weekly
                WidgetFocus.CONSISTENCY -> R.layout.widget_small_consistency
                WidgetFocus.AUTOMATIC, WidgetFocus.TODAY -> R.layout.widget_small_today
            }

            !snapshot.hasPlan ->
                if (size == WidgetSize.LARGE) R.layout.widget_large_empty else R.layout.widget_medium_empty

            size == WidgetSize.LARGE -> R.layout.widget_large
            else -> R.layout.widget_medium
        }

        val views = RemoteViews(app.packageName, layout)
        when (layout) {
            R.layout.widget_small_today -> bindSmallToday(views, appWidgetId, snapshot)
            R.layout.widget_small_weekly -> bindSmallWeekly(views, appWidgetId, snapshot, now)
            R.layout.widget_small_consistency -> bindSmallConsistency(views, appWidgetId, snapshot, now)
            R.layout.widget_medium -> bindMedium(views, appWidgetId, snapshot, now)
            R.layout.widget_large -> bindLarge(views, appWidgetId, snapshot, now)
            R.layout.widget_medium_empty -> bindEmpty(views, appWidgetId, medium = true, snapshot = snapshot, now = now)
            R.layout.widget_large_empty -> bindEmpty(views, appWidgetId, medium = false, snapshot = snapshot, now = now)
        }
        return views
    }

    // MARK: - Small

    private fun bindSmallToday(views: RemoteViews, appWidgetId: Int, snapshot: WidgetSnapshot) {
        val copy = WidgetStateCopy.forSnapshot(snapshot)
        bindBrand(views, 13)
        bindStateIcon(views, snapshot.today.state)
        views.setTextViewText(R.id.widget_eyebrow, copy.eyebrow)
        views.setTextViewText(R.id.widget_title, copy.title)
        views.setTextViewText(R.id.widget_detail, copy.detail)
        views.setTextViewText(R.id.widget_week_fraction, WidgetText.weekFraction(snapshot.week))
        views.setProgressBar(R.id.widget_week_bar, 100, progressPercent(snapshot.week.progress), false)
        views.setContentDescription(R.id.widget_week_fraction, WidgetText.weekAccessibilityLabel(snapshot.week))
        bindCta(views, appWidgetId, copy)
        bindRoot(views, appWidgetId, AppDeepLink.TODAY)
    }

    private fun bindSmallWeekly(views: RemoteViews, appWidgetId: Int, snapshot: WidgetSnapshot, now: Long) {
        val week = snapshot.week
        bindBrand(views, 12)
        bindStateIcon(views, snapshot.today.state)
        views.setTextViewText(R.id.widget_eyebrow, app.getString(R.string.widget_this_week))
        views.setImageViewBitmap(R.id.widget_ring, WidgetArt.weekRing(app, dp(46), week, palette))
        views.setContentDescription(R.id.widget_ring, WidgetText.weekAccessibilityLabel(week))
        views.setTextViewText(R.id.widget_remaining, WidgetText.remaining(week))
        views.setTextViewText(
            R.id.widget_trained,
            app.getString(R.string.widget_minutes_trained, WidgetText.minutes(week.minutes)),
        )
        bindChart(views, week, now)
        views.setTextViewText(R.id.widget_link_label, app.getString(R.string.widget_view_progress))
        views.setOnClickPendingIntent(R.id.widget_link, deepLinkPendingIntent(appWidgetId, AppDeepLink.PROGRESS))
        bindRoot(views, appWidgetId, AppDeepLink.TODAY)
    }

    private fun bindSmallConsistency(views: RemoteViews, appWidgetId: Int, snapshot: WidgetSnapshot, now: Long) {
        bindBrand(views, 12)
        bindStateIcon(views, snapshot.today.state)
        views.setTextViewText(R.id.widget_eyebrow, app.getString(R.string.widget_consistency))
        views.setTextViewText(R.id.widget_streak, snapshot.streak.toString())
        views.setTextViewText(
            R.id.widget_streak_unit,
            app.getString(if (snapshot.streak == 1) R.string.widget_day else R.string.widget_days),
        )
        views.setContentDescription(R.id.widget_streak, "${snapshot.streak} day streak")
        views.setTextViewText(R.id.widget_streak_detail, WidgetText.streakDetail(snapshot.streak))
        bindChart(views, snapshot.week, now)
        views.setTextViewText(R.id.widget_link_label, app.getString(R.string.widget_view_progress))
        views.setOnClickPendingIntent(R.id.widget_link, deepLinkPendingIntent(appWidgetId, AppDeepLink.PROGRESS))
        bindRoot(views, appWidgetId, AppDeepLink.TODAY)
    }

    // MARK: - Medium

    private fun bindMedium(views: RemoteViews, appWidgetId: Int, snapshot: WidgetSnapshot, now: Long) {
        val copy = WidgetStateCopy.forSnapshot(snapshot)
        val week = snapshot.week
        bindBrand(views, 13)
        bindStateIcon(views, snapshot.today.state)
        views.setTextViewText(R.id.widget_eyebrow, copy.eyebrow)
        views.setTextViewText(R.id.widget_title, copy.title)
        views.setTextViewText(R.id.widget_detail, copy.detail)
        bindCta(views, appWidgetId, copy)
        views.setTextViewText(R.id.widget_week_fraction, WidgetText.weekFraction(week))
        views.setContentDescription(R.id.widget_week_fraction, WidgetText.weekAccessibilityLabel(week))
        views.setProgressBar(R.id.widget_week_bar, 100, progressPercent(week.progress), false)
        views.setTextViewText(R.id.widget_remaining, WidgetText.remaining(week))
        views.setTextViewText(
            R.id.widget_minutes,
            app.getString(R.string.widget_minutes_trained, WidgetText.minutes(week.minutes)),
        )
        bindChart(views, week, now)
        views.setContentDescription(R.id.widget_progress_link, app.getString(R.string.widget_open_progress))
        views.setOnClickPendingIntent(R.id.widget_progress_link, deepLinkPendingIntent(appWidgetId, AppDeepLink.PROGRESS))
        bindRoot(views, appWidgetId, AppDeepLink.TODAY)
    }

    // MARK: - Large

    private fun bindLarge(views: RemoteViews, appWidgetId: Int, snapshot: WidgetSnapshot, now: Long) {
        val copy = WidgetStateCopy.forSnapshot(snapshot)
        val week = snapshot.week
        bindBrand(views, 15)
        bindStateIcon(views, snapshot.today.state)
        views.setTextViewText(R.id.widget_date, WidgetText.dayAndMonth(now, zone))
        bindFreshness(views, snapshot.generatedAt, now)
        views.setTextViewText(R.id.widget_eyebrow, copy.eyebrow)
        views.setTextViewText(R.id.widget_title, copy.title)
        views.setTextViewText(R.id.widget_detail, copy.detail)
        bindCta(views, appWidgetId, copy)
        views.setImageViewBitmap(R.id.widget_week_ring, WidgetArt.weekRing(app, dp(48), week, palette))
        views.setContentDescription(R.id.widget_week_ring, WidgetText.weekAccessibilityLabel(week))
        views.setTextViewText(R.id.widget_week_remaining, WidgetText.remaining(week))
        views.setTextViewText(
            R.id.widget_week_minutes,
            app.getString(R.string.widget_minutes_trained, WidgetText.minutes(week.minutes)),
        )
        views.setTextViewText(
            R.id.widget_chart_summary,
            if (week.hasActivity) {
                app.getString(R.string.widget_sessions_count, week.completed)
            } else {
                app.getString(R.string.widget_no_sessions)
            },
        )
        bindChart(views, week, now)
        views.setViewVisibility(R.id.widget_chart_hint, if (week.hasActivity) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.widget_streak, snapshot.streak.toString())
        views.setTextViewText(R.id.widget_streak_unit, app.getString(R.string.widget_day_streak))
        views.setContentDescription(R.id.widget_streak, "${snapshot.streak} day streak")
        views.setTextViewText(
            R.id.widget_streak_detail,
            if (snapshot.totalCompleted > 0) {
                app.getString(R.string.widget_total_detail, snapshot.totalCompleted, snapshot.totalReps)
            } else {
                app.getString(R.string.widget_first_session)
            },
        )
        bindRoot(views, appWidgetId, AppDeepLink.TODAY)
    }

    private fun bindEmpty(views: RemoteViews, appWidgetId: Int, medium: Boolean, snapshot: WidgetSnapshot, now: Long) {
        bindBrand(views, if (medium) 13 else 17)
        views.setTextViewText(R.id.widget_empty_title, app.getString(R.string.widget_empty_title))
        views.setTextViewText(
            R.id.widget_empty_body,
            app.getString(if (medium) R.string.widget_empty_body_medium else R.string.widget_empty_body),
        )
        val copy = WidgetStateCopy.forSnapshot(snapshot)
        bindCta(views, appWidgetId, copy)
        if (medium) {
            views.setImageViewBitmap(R.id.widget_empty_mark, WidgetArt.brandMark(app, dp(42), palette.accent))
        } else {
            bindFreshness(views, snapshot.generatedAt, now)
        }
        bindRoot(views, appWidgetId, AppDeepLink.TODAY)
    }

    // MARK: - Shared pieces

    private fun bindBrand(views: RemoteViews, sizeDp: Int) {
        views.setImageViewBitmap(R.id.widget_brand_mark, WidgetArt.brandMark(app, dp(sizeDp), palette.accent))
    }

    private fun bindStateIcon(views: RemoteViews, state: WidgetTodayState) {
        views.setImageViewResource(R.id.widget_state_icon, stateIcon(state))
    }

    private fun stateIcon(state: WidgetTodayState): Int = when (state) {
        WidgetTodayState.WORKOUT -> R.drawable.ic_widget_workout
        WidgetTodayState.COMPLETED -> R.drawable.ic_widget_completed
        WidgetTodayState.IN_PROGRESS -> R.drawable.ic_widget_progress
        WidgetTodayState.REST -> R.drawable.ic_widget_rest
        WidgetTodayState.NOT_SCHEDULED -> R.drawable.ic_widget_calendar
        WidgetTodayState.NO_PLAN -> R.drawable.ic_widget_sparkles
    }

    private fun bindCta(views: RemoteViews, appWidgetId: Int, copy: WidgetStateCopy) {
        views.setTextViewText(R.id.widget_cta_label, copy.cta)
        views.setImageViewResource(R.id.widget_cta_icon, ctaIcon(copy.ctaIcon))
        views.setOnClickPendingIntent(R.id.widget_cta, deepLinkPendingIntent(appWidgetId, copy.deepLink))
    }

    private fun ctaIcon(icon: WidgetCtaIcon): Int = when (icon) {
        WidgetCtaIcon.PLAY -> R.drawable.ic_widget_play
        WidgetCtaIcon.CHART -> R.drawable.ic_widget_chart
        WidgetCtaIcon.ARROW_UP_RIGHT -> R.drawable.ic_widget_arrow
        WidgetCtaIcon.CALENDAR -> R.drawable.ic_widget_calendar
    }

    private fun bindChart(views: RemoteViews, week: WidgetWeekSummary, now: Long) {
        val maximum = maxOf(week.goal, week.days.maxOfOrNull { it.completedCount } ?: 0, 1)
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        week.days.take(7).forEachIndexed { index, day ->
            val barId = CHART_BARS[index]
            val dayId = CHART_DAYS[index]
            val fraction = if (day.didTrain) {
                maxOf(0.28f, day.completedCount.toFloat() / maximum)
            } else {
                0f
            }
            views.setProgressBar(barId, 100, (fraction * 100f).roundToInt(), false)
            val date = Instant.ofEpochMilli(day.dateEpochMillis).atZone(zone).toLocalDate()
            val isToday = date == today
            views.setTextViewText(dayId, WidgetText.narrowWeekday(day.dateEpochMillis, zone))
            views.setTextColor(dayId, if (isToday) palette.accentText else palette.textTertiary)
            views.setContentDescription(dayId, WidgetText.chartDayAccessibilityLabel(day, isToday, zone))
        }
    }

    private fun bindFreshness(views: RemoteViews, generatedAt: Long, now: Long) {
        views.setTextViewText(R.id.widget_freshness, WidgetTimelineLogic.freshnessLabel(generatedAt, now))
        views.setTextColor(
            R.id.widget_freshness,
            if (WidgetTimelineLogic.isStale(generatedAt, now)) palette.warning else palette.textTertiary,
        )
        views.setContentDescription(
            R.id.widget_freshness,
            WidgetTimelineLogic.freshnessLabel(generatedAt, now),
        )
    }

    private fun bindRoot(views: RemoteViews, appWidgetId: Int, link: AppDeepLink) {
        views.setOnClickPendingIntent(R.id.widget_root, deepLinkPendingIntent(appWidgetId, link))
    }

    private fun deepLinkPendingIntent(appWidgetId: Int, link: AppDeepLink): PendingIntent {
        val path = when (link) {
            AppDeepLink.TODAY -> "today"
            AppDeepLink.START_WORKOUT -> "start-workout"
            AppDeepLink.WORKOUTS -> "workouts"
            AppDeepLink.PROGRESS -> "progress"
            AppDeepLink.COMMUNITY -> "community"
            AppDeepLink.CONNECTION_REQUESTS -> "community/requests"
            AppDeepLink.MESSAGES -> "community/messages"
            AppDeepLink.NOTIFICATIONS -> "community/notifications"
        }
        val intent = Intent(app, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("forma://$path")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val requestCode = 1000 + appWidgetId * 16 + link.ordinal
        return PendingIntent.getActivity(
            app,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun progressPercent(progress: Double): Int =
        (progress.coerceIn(0.0, 1.0) * 100.0).roundToInt()

    private fun dp(value: Int): Int = (value * density).roundToInt()

    private companion object {
        val CHART_BARS = intArrayOf(
            R.id.widget_chart_bar_0,
            R.id.widget_chart_bar_1,
            R.id.widget_chart_bar_2,
            R.id.widget_chart_bar_3,
            R.id.widget_chart_bar_4,
            R.id.widget_chart_bar_5,
            R.id.widget_chart_bar_6,
        )
        val CHART_DAYS = intArrayOf(
            R.id.widget_chart_day_0,
            R.id.widget_chart_day_1,
            R.id.widget_chart_day_2,
            R.id.widget_chart_day_3,
            R.id.widget_chart_day_4,
            R.id.widget_chart_day_5,
            R.id.widget_chart_day_6,
        )
    }
}
