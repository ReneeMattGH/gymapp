package com.gymapp.android.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.gymapp.android.R
import com.gymapp.android.widget.WidgetFixtures.epoch
import com.gymapp.android.widget.WidgetFixtures.session
import com.gymapp.android.widget.WidgetFixtures.today
import com.gymapp.android.widget.WidgetFixtures.weekPlan
import com.gymapp.android.widget.WidgetFixtures.zone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.ZoneId
import java.util.Locale
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WidgetRendererTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var originalTimeZone: TimeZone
    private lateinit var originalLocale: Locale
    private val now = epoch(today)
    private val renderer by lazy { WidgetRenderer(context) }

    @Before
    fun pinClock() {
        originalTimeZone = TimeZone.getDefault()
        originalLocale = Locale.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        Locale.setDefault(Locale.US)
    }

    @After
    fun restoreClock() {
        TimeZone.setDefault(originalTimeZone)
        Locale.setDefault(originalLocale)
    }

    @Test
    fun `widget size follows the launcher options`() {
        assertEquals(WidgetSize.SMALL, WidgetSize.fromOptions(options(110, 110)))
        assertEquals(WidgetSize.MEDIUM, WidgetSize.fromOptions(options(250, 110)))
        assertEquals(WidgetSize.LARGE, WidgetSize.fromOptions(options(250, 220)))
        assertEquals(WidgetSize.SMALL, WidgetSize.fromOptions(null))
    }

    @Test
    fun `layout selection covers focus, size and no-plan states`() {
        val snapshot = snapshot(emptyList())

        assertEquals(
            R.layout.widget_small_today,
            renderer.render(1, snapshot, options(110, 110), WidgetFocus.AUTOMATIC, now).layoutId,
        )
        assertEquals(
            R.layout.widget_small_today,
            renderer.render(1, snapshot, options(110, 110), WidgetFocus.TODAY, now).layoutId,
        )
        assertEquals(
            R.layout.widget_small_weekly,
            renderer.render(1, snapshot, options(110, 110), WidgetFocus.WEEKLY, now).layoutId,
        )
        assertEquals(
            R.layout.widget_small_consistency,
            renderer.render(1, snapshot, options(110, 110), WidgetFocus.CONSISTENCY, now).layoutId,
        )
        assertEquals(
            R.layout.widget_medium,
            renderer.render(1, snapshot, options(250, 110), WidgetFocus.WEEKLY, now).layoutId,
        )
        assertEquals(
            R.layout.widget_large,
            renderer.render(1, snapshot, options(250, 220), WidgetFocus.WEEKLY, now).layoutId,
        )

        val empty = WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID, null, null, emptyList(), null, now, zone,
        )
        assertEquals(
            R.layout.widget_medium_empty,
            renderer.render(1, empty, options(250, 110), WidgetFocus.AUTOMATIC, now).layoutId,
        )
        assertEquals(
            R.layout.widget_large_empty,
            renderer.render(1, empty, options(250, 220), WidgetFocus.AUTOMATIC, now).layoutId,
        )
    }

    @Test
    fun `small today binds copy, week fraction and progress`() {
        val snapshot = snapshot(listOf(session(today, durationSeconds = 3_600)))
        val view = inflate(renderer.render(1, snapshot, options(110, 110), WidgetFocus.TODAY, now))

        assertEquals("COMPLETE", text(view, R.id.widget_eyebrow))
        assertEquals("Upper body", text(view, R.id.widget_title))
        assertEquals("Done today. Recovery is part of the plan.", text(view, R.id.widget_detail))
        assertEquals("1/3", text(view, R.id.widget_week_fraction))
        assertEquals("View progress", text(view, R.id.widget_cta_label))
        assertEquals(33, view.findViewById<ProgressBar>(R.id.widget_week_bar).progress)
        assertNotNull(view.findViewById<ImageView>(R.id.widget_brand_mark).drawable)
        assertTrue(view.findViewById<View>(R.id.widget_cta).hasOnClickListeners())
    }

    @Test
    fun `small weekly emphasis draws the ring and chart`() {
        val snapshot = snapshot(listOf(session(today, durationSeconds = 3_600)))
        val view = inflate(renderer.render(1, snapshot, options(110, 110), WidgetFocus.WEEKLY, now))

        assertEquals("THIS WEEK", text(view, R.id.widget_eyebrow))
        assertEquals(
            "1 of 3 sessions this week. 2 sessions to go.",
            view.findViewById<View>(R.id.widget_ring).contentDescription.toString(),
        )
        assertEquals("2 sessions to go", text(view, R.id.widget_remaining))
        assertEquals("1 hr trained", text(view, R.id.widget_trained))
        assertNotNull(view.findViewById<ImageView>(R.id.widget_ring).drawable)
        assertEquals("W", text(view, R.id.widget_chart_day_3))
        assertEquals(33, view.findViewById<ProgressBar>(R.id.widget_chart_bar_3).progress)
        assertEquals(0, view.findViewById<ProgressBar>(R.id.widget_chart_bar_2).progress)
        assertEquals("View progress", text(view, R.id.widget_link_label))
        assertTrue(view.findViewById<View>(R.id.widget_link).hasOnClickListeners())
    }

    @Test
    fun `small consistency emphasis leads with the streak`() {
        val snapshot = snapshot(
            listOf(session(today), session(today.minusDays(1)), session(today.minusDays(2))),
        )
        val view = inflate(renderer.render(1, snapshot, options(110, 110), WidgetFocus.CONSISTENCY, now))

        assertEquals("CONSISTENCY", text(view, R.id.widget_eyebrow))
        assertEquals("3", text(view, R.id.widget_streak))
        assertEquals("days", text(view, R.id.widget_streak_unit))
        assertEquals("Consecutive training days.", text(view, R.id.widget_streak_detail))
        assertEquals(
            "3 day streak",
            view.findViewById<View>(R.id.widget_streak).contentDescription.toString(),
        )
    }

    @Test
    fun `medium binds the week panel`() {
        val snapshot = snapshot(listOf(session(today, durationSeconds = 3_600)))
        val view = inflate(renderer.render(1, snapshot, options(250, 110), WidgetFocus.AUTOMATIC, now))

        assertEquals("COMPLETE", text(view, R.id.widget_eyebrow))
        assertEquals("1/3", text(view, R.id.widget_week_fraction))
        assertEquals(33, view.findViewById<ProgressBar>(R.id.widget_week_bar).progress)
        assertEquals("2 sessions to go", text(view, R.id.widget_remaining))
        assertEquals("1 hr trained", text(view, R.id.widget_minutes))
        assertEquals("Open progress", view.findViewById<View>(R.id.widget_progress_link).contentDescription.toString())
        assertTrue(view.findViewById<View>(R.id.widget_progress_link).hasOnClickListeners())
    }

    @Test
    fun `large binds header, ring, chart summary and consistency`() {
        val snapshot = snapshot(listOf(session(today, durationSeconds = 3_600)))
        val view = inflate(renderer.render(1, snapshot, options(250, 220), WidgetFocus.AUTOMATIC, now))

        assertEquals(WidgetText.dayAndMonth(now, ZoneId.systemDefault()), text(view, R.id.widget_date))
        assertEquals("Updated just now", text(view, R.id.widget_freshness))
        assertEquals(
            "1 of 3 sessions this week. 2 sessions to go.",
            view.findViewById<View>(R.id.widget_week_ring).contentDescription.toString(),
        )
        assertEquals("1 sessions", text(view, R.id.widget_chart_summary))
        assertEquals(View.GONE, view.findViewById<View>(R.id.widget_chart_hint).visibility)
        assertEquals("1", text(view, R.id.widget_streak))
        assertEquals("1 sessions · 10 reps logged", text(view, R.id.widget_streak_detail))
        assertEquals("Done today. Recovery is part of the plan.", text(view, R.id.widget_detail))
        assertNotNull(view.findViewById<ImageView>(R.id.widget_week_ring).drawable)
    }

    @Test
    fun `empty layouts invite the user to build a plan`() {
        val empty = WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID, null, null, emptyList(), null, now, zone,
        )
        val medium = inflate(renderer.render(1, empty, options(250, 110), WidgetFocus.AUTOMATIC, now))
        assertEquals("Your plan starts here", text(medium, R.id.widget_empty_title))
        assertEquals(
            context.getString(R.string.widget_empty_body_medium),
            text(medium, R.id.widget_empty_body),
        )
        assertEquals("Open Forma", text(medium, R.id.widget_cta_label))
        assertNotNull(medium.findViewById<ImageView>(R.id.widget_brand_mark).drawable)
        assertNotNull(medium.findViewById<ImageView>(R.id.widget_empty_mark).drawable)

        val large = inflate(renderer.render(1, empty, options(250, 220), WidgetFocus.AUTOMATIC, now))
        assertEquals("Your plan starts here", text(large, R.id.widget_empty_title))
        assertTrue(text(large, R.id.widget_freshness).startsWith("Updated"))
        assertEquals("Open Forma", text(large, R.id.widget_cta_label))
    }

    @Test
    fun `stale snapshots warn in the freshness label`() {
        val snapshot = snapshot(emptyList()).copy(generatedAt = now - 48 * 3_600_000L)
        val view = inflate(renderer.render(1, snapshot, options(250, 220), WidgetFocus.AUTOMATIC, now))

        assertEquals("Updated 2 days ago", text(view, R.id.widget_freshness))
    }

    @Test
    fun `chart bars keep a visible minimum and mark today`() {
        val plan = weekPlan(1, 3, 5, daysPerWeek = 5)
        val snapshot = WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID, plan, null, listOf(session(today)), null, now, zone,
        )
        val view = inflate(renderer.render(1, snapshot, options(250, 110), WidgetFocus.AUTOMATIC, now))

        val todayBar = view.findViewById<ProgressBar>(R.id.widget_chart_bar_3)
        assertEquals(28, todayBar.progress)
        assertEquals(
            context.resources.getColor(R.color.widget_accent_text, context.theme),
            view.findViewById<TextView>(R.id.widget_chart_day_3).currentTextColor,
        )
        assertEquals(
            context.resources.getColor(R.color.widget_text_tertiary, context.theme),
            view.findViewById<TextView>(R.id.widget_chart_day_2).currentTextColor,
        )
        assertEquals(
            "Wed: 1 workout, today",
            view.findViewById<View>(R.id.widget_chart_day_3).contentDescription.toString(),
        )
    }

    private fun snapshot(sessions: List<com.gymapp.android.domain.WorkoutSession>): WidgetSnapshot =
        WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID,
            weekPlan(1, 3, 5),
            null,
            sessions,
            null,
            now,
            zone,
        )

    private fun options(width: Int, height: Int): Bundle = Bundle().apply {
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, width)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, width)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, height)
    }

    private fun inflate(views: android.widget.RemoteViews): View =
        views.apply(context, FrameLayout(context))

    private fun text(view: View, id: Int): String =
        view.findViewById<TextView>(id).text.toString()
}
