import type { Preferences, Profile, WorkoutPlan, WorkoutSession } from '@/data/types';
import { completedSessions, currentStreak, currentWeekCount } from '@/lib/date';
import { planForDate } from '@/lib/plan';

type InsightInput = {
  profile: Profile;
  preferences: Preferences;
  plan: WorkoutPlan | null;
  sessions: WorkoutSession[];
};

/**
 * Honest, deterministic coaching note built only from saved training data.
 * Used when a live AI coach is not available (or as a fallback if the request fails).
 */
export function localDailyInsight({ profile, preferences, plan, sessions }: InsightInput): string {
  const name = profile.name.trim().split(/\s+/)[0] || 'there';
  const today = new Date();
  const todayPlan = plan ? planForDate(plan, today) : undefined;
  const completed = completedSessions(sessions);
  const weekCount = currentWeekCount(sessions);
  const streak = currentStreak(sessions);
  const plannedPerWeek = plan
    ? plan.days.filter((day) => !day.isRestDay).length
    : preferences.workoutDays.length;

  if (completed.length === 0) {
    return `${name}, your plan is ready and waiting. For the first session, aim to finish every set with about two reps still in reserve. Showing up consistently matters far more than how heavy you go this week.`;
  }

  if (todayPlan?.isRestDay) {
    return `You have ${weekCount} completed session${weekCount === 1 ? '' : 's'} this week. Today is a planned recovery day — a short walk, some easy mobility, and good sleep will set up your next session. Rest is part of the programme, not a gap in it.`;
  }

  if (todayPlan && !todayPlan.isRestDay) {
    const streakText = streak > 1 ? ` That is a ${streak}-day streak.` : '';
    return `Today is ${todayPlan.title.toLowerCase()} — about ${todayPlan.estimatedMinutes} minutes. You are at ${weekCount} of ${plannedPerWeek} planned sessions this week.${streakText} Keep the final set a couple of reps away from failure so you can recover and train again soon.`;
  }

  const last = completed[0];
  const minutes = Math.round(last.durationSeconds / 60);
  return `Your last session was ${last.title} (${minutes} min, ${last.sets.length} set${last.sets.length === 1 ? '' : 's'}). You are at ${weekCount} of ${plannedPerWeek} planned sessions this week.${
    streak > 1 ? ` Your ${streak}-day streak is still alive.` : ''
  } Follow the plan rather than chasing extra volume today.`;
}
