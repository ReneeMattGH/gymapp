package com.gymapp.android.widget

import com.gymapp.android.core.AppDeepLink
import com.gymapp.android.widget.WidgetFixtures.epoch
import com.gymapp.android.widget.WidgetFixtures.session
import com.gymapp.android.widget.WidgetFixtures.today
import com.gymapp.android.widget.WidgetFixtures.weekPlan
import com.gymapp.android.widget.WidgetFixtures.zone
import org.junit.Assert.assertEquals
import org.junit.Test

/** The eyebrow/title/detail/CTA block must match the iOS widget copy. */
class WidgetCopyTest {
    private val now = epoch(today)

    @Test
    fun `workout state leads with today's session`() {
        val snapshot = build(emptyList(), null)
        val copy = WidgetStateCopy.forSnapshot(snapshot)

        assertEquals("TODAY", copy.eyebrow)
        assertEquals("Day 3", copy.title)
        assertEquals("40 min · 3 exercises", copy.detail)
        assertEquals("Start workout", copy.cta)
        assertEquals(WidgetCtaIcon.PLAY, copy.ctaIcon)
        assertEquals(AppDeepLink.START_WORKOUT, copy.deepLink)
    }

    @Test
    fun `completed state points at progress`() {
        val snapshot = build(listOf(session(today, title = "Legs")), null)
        val copy = WidgetStateCopy.forSnapshot(snapshot)

        assertEquals("COMPLETE", copy.eyebrow)
        assertEquals("Legs", copy.title)
        assertEquals("Done today. Recovery is part of the plan.", copy.detail)
        assertEquals("View progress", copy.cta)
        assertEquals(WidgetCtaIcon.CHART, copy.ctaIcon)
        assertEquals(AppDeepLink.PROGRESS, copy.deepLink)
    }

    @Test
    fun `rest and not scheduled states name the next session`() {
        val rest = WidgetStateCopy.forSnapshot(build(emptyList(), null, plan = weekPlan(1, 5)))
        assertEquals("RECOVERY", rest.eyebrow)
        assertEquals("Rest day", rest.title)
        assertEquals("Next: Day 5", rest.detail)
        assertEquals(AppDeepLink.TODAY, rest.deepLink)

        val sparse = weekPlan(1, 5).copy(days = listOf(WidgetFixtures.day(1), WidgetFixtures.day(5)))
        val notScheduled = WidgetStateCopy.forSnapshot(build(emptyList(), null, plan = sparse))
        assertEquals("NO SESSION", notScheduled.eyebrow)
        assertEquals("No workout today", notScheduled.title)
        assertEquals("Next: Day 1", notScheduled.detail)
        assertEquals(WidgetCtaIcon.CALENDAR, notScheduled.ctaIcon)
        assertEquals(AppDeepLink.WORKOUTS, notScheduled.deepLink)
    }

    @Test
    fun `in progress resumes the open session`() {
        val active = com.gymapp.android.domain.ActiveWorkout(
            sessionId = "active-1",
            userId = WidgetFixtures.USER_ID,
            planDayId = "day-3",
            planId = WidgetFixtures.PLAN_ID,
            title = "Pull day",
            startedAt = now - 60_000L,
            status = com.gymapp.android.domain.WorkoutRunStatus.ACTIVE,
        )
        val copy = WidgetStateCopy.forSnapshot(build(emptyList(), active))

        assertEquals("IN PROGRESS", copy.eyebrow)
        assertEquals("Pull day", copy.title)
        assertEquals("Tap to pick up where you left off.", copy.detail)
        assertEquals("Resume", copy.cta)
        assertEquals(AppDeepLink.TODAY, copy.deepLink)
    }

    @Test
    fun `no plan invites the user to build one`() {
        val snapshot = WidgetSnapshotBuilder.build(
            WidgetFixtures.USER_ID, null, null, emptyList(), null, now, zone,
        )
        val copy = WidgetStateCopy.forSnapshot(snapshot)

        assertEquals("GET STARTED", copy.eyebrow)
        assertEquals("Build your plan", copy.title)
        assertEquals("Open Forma", copy.cta)
        assertEquals(WidgetCtaIcon.ARROW_UP_RIGHT, copy.ctaIcon)
        assertEquals(AppDeepLink.TODAY, copy.deepLink)
    }

    private fun build(
        sessions: List<com.gymapp.android.domain.WorkoutSession>,
        active: com.gymapp.android.domain.ActiveWorkout?,
        plan: com.gymapp.android.domain.WorkoutPlan = weekPlan(1, 3, 5),
    ): WidgetSnapshot = WidgetSnapshotBuilder.build(
        WidgetFixtures.USER_ID, plan, null, sessions, active, now, zone,
    )
}
