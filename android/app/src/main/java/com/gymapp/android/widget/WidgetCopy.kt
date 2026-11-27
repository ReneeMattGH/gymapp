package com.gymapp.android.widget

import com.gymapp.android.core.AppDeepLink

enum class WidgetCtaIcon { PLAY, CHART, ARROW_UP_RIGHT, CALENDAR }

/** The eyebrow/title/detail/CTA block, matching the iOS widget copy exactly. */
data class WidgetStateCopy(
    val eyebrow: String,
    val title: String,
    val detail: String,
    val cta: String,
    val ctaIcon: WidgetCtaIcon,
    val deepLink: AppDeepLink,
) {
    companion object {
        fun forSnapshot(snapshot: WidgetSnapshot): WidgetStateCopy {
            val today = snapshot.today
            return when (today.state) {
                WidgetTodayState.WORKOUT -> WidgetStateCopy(
                    eyebrow = "TODAY",
                    title = today.title ?: "Today's session",
                    detail = workoutDetail(today),
                    cta = "Start workout",
                    ctaIcon = WidgetCtaIcon.PLAY,
                    deepLink = AppDeepLink.START_WORKOUT,
                )

                WidgetTodayState.COMPLETED -> WidgetStateCopy(
                    eyebrow = "COMPLETE",
                    title = today.completedTitle ?: today.title ?: "Workout complete",
                    detail = "Done today. Recovery is part of the plan.",
                    cta = "View progress",
                    ctaIcon = WidgetCtaIcon.CHART,
                    deepLink = AppDeepLink.PROGRESS,
                )

                WidgetTodayState.IN_PROGRESS -> WidgetStateCopy(
                    eyebrow = "IN PROGRESS",
                    title = today.activeSessionTitle ?: today.title ?: "Workout in progress",
                    detail = "Tap to pick up where you left off.",
                    cta = "Resume",
                    ctaIcon = WidgetCtaIcon.PLAY,
                    deepLink = AppDeepLink.TODAY,
                )

                WidgetTodayState.REST -> WidgetStateCopy(
                    eyebrow = "RECOVERY",
                    title = today.title ?: "Rest day",
                    detail = today.nextTitle?.let { "Next: $it" } ?: "Recovery is part of the programme.",
                    cta = "Open Forma",
                    ctaIcon = WidgetCtaIcon.ARROW_UP_RIGHT,
                    deepLink = AppDeepLink.TODAY,
                )

                WidgetTodayState.NOT_SCHEDULED -> WidgetStateCopy(
                    eyebrow = "NO SESSION",
                    title = "No workout today",
                    detail = today.nextTitle?.let { "Next: $it" } ?: "Nothing scheduled for today.",
                    cta = "View plan",
                    ctaIcon = WidgetCtaIcon.CALENDAR,
                    deepLink = AppDeepLink.WORKOUTS,
                )

                WidgetTodayState.NO_PLAN -> WidgetStateCopy(
                    eyebrow = "GET STARTED",
                    title = "Build your plan",
                    detail = "Add your plan in Forma to see today's focus and weekly progress.",
                    cta = "Open Forma",
                    ctaIcon = WidgetCtaIcon.ARROW_UP_RIGHT,
                    deepLink = AppDeepLink.TODAY,
                )
            }
        }

        private fun workoutDetail(today: WidgetTodaySummary): String {
            if (today.estimatedMinutes > 0 && today.exerciseCount > 0) {
                return "${today.estimatedMinutes} min · ${today.exerciseCount} exercises"
            }
            if (today.exerciseCount > 0) return "${today.exerciseCount} exercises"
            return "Planned for today"
        }
    }
}
