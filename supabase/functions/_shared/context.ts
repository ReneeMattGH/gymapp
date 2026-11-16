import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

import { LIMITS } from './config.ts';

type Row = Record<string, unknown>;

export type TrainingContext = {
  profile: Row | null;
  preferences: Row | null;
  plan: Row | null;
  sessions: Row[];
  exerciseHistory: Row[];
  exercises: Row[];
  today: string;
  planAgeDays: number | null;
  planStale: boolean;
  lastSessionAt: string | null;
  contextWarnings: string[];
  exerciseName: (id: string) => string;
  exerciseById: (id: string) => Row | undefined;
  retrieveExercises: (query: string, limit?: number) => Row[];
};

const WEEKDAY = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

function arr(value: unknown): Row[] {
  return Array.isArray(value) ? (value as Row[]) : [];
}

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function asNumber(value: unknown, fallback = 0): number {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : [];
}

function daysSince(iso: string): number | null {
  const time = Date.parse(iso);
  if (!Number.isFinite(time)) return null;
  return Math.max(0, Math.floor((Date.now() - time) / 86_400_000));
}

export async function loadTrainingContext(
  client: SupabaseClient,
  userId: string,
): Promise<TrainingContext> {
  const [profile, preferences, plan, sessions, exerciseHistory, exercises] = await Promise.all([
    client.from('profiles').select('*').eq('id', userId).maybeSingle(),
    client.from('user_preferences').select('*').eq('user_id', userId).maybeSingle(),
    client
      .from('workout_plans')
      .select('*, days:workout_days(*, exercises:workout_exercises(*))')
      .eq('user_id', userId)
      .eq('status', 'active')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
    client
      .from('workout_sessions')
      .select('*, sets:completed_sets(*)')
      .eq('user_id', userId)
      .order('started_at', { ascending: false })
      .limit(12),
    client
      .from('exercise_history')
      .select('exercise_id, reps, weight_kg, completed_at')
      .eq('user_id', userId)
      .order('completed_at', { ascending: false })
      .limit(120),
    client
      .from('exercise_library')
      .select(
        'id, name, category, primary_muscles, secondary_muscles, equipment, difficulty, instructions, cues, mistakes, alternatives, is_unilateral, source',
      )
      .order('name')
      .limit(400),
  ]);

  const exerciseRows = arr(exercises.data);
  const byId = new Map(exerciseRows.map((row) => [asString(row.id), row]));
  const planRow = (plan.data as Row | null) ?? null;
  const sessionRows = arr(sessions.data);
  const planCreated = planRow ? asString(planRow.created_at) : '';
  const planAgeDays = planCreated ? daysSince(planCreated) : null;
  const planStale = planAgeDays !== null && planAgeDays > LIMITS.planStaleDays;
  const lastSessionAt = sessionRows.length > 0 ? asString(sessionRows[0].started_at) || null : null;

  const contextWarnings: string[] = [];
  if (planStale && planAgeDays !== null) {
    contextWarnings.push(`The active plan is ${planAgeDays} days old and may no longer match the athlete.`);
  }
  if (!planRow) contextWarnings.push('No active plan is stored for this athlete.');
  if (sessionRows.length === 0) contextWarnings.push('No completed workouts are stored for this athlete.');

  return {
    profile: (profile.data as Row | null) ?? null,
    preferences: (preferences.data as Row | null) ?? null,
    plan: planRow,
    sessions: sessionRows,
    exerciseHistory: arr(exerciseHistory.data),
    exercises: exerciseRows,
    today: new Date().toISOString().slice(0, 10),
    planAgeDays,
    planStale,
    lastSessionAt,
    contextWarnings,
    exerciseName: (id: string) => asString(byId.get(id)?.name, id),
    exerciseById: (id: string) => byId.get(id),
    retrieveExercises: (query: string, limit = 3) => retrieveExercises(exerciseRows, query, limit),
  };
}

/**
 * Deterministic keyword retrieval over the verified exercise library. This is
 * lexical retrieval, not vector search — no embeddings are invented or stored.
 */
export function retrieveExercises(exercises: Row[], query: string, limit = 3): Row[] {
  const tokens = query
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length >= 3 && !STOP_WORDS.has(token));
  if (tokens.length === 0) return [];

  const scored = exercises
    .map((exercise) => {
      const name = asString(exercise.name).toLowerCase();
      const muscles = [
        ...stringList(exercise.primary_muscles),
        ...stringList(exercise.secondary_muscles),
      ].join(' ').toLowerCase();
      const equipment = stringList(exercise.equipment).join(' ').toLowerCase();
      const category = asString(exercise.category).toLowerCase();

      let score = 0;
      for (const token of tokens) {
        if (name.includes(token)) score += 6;
        if (muscles.includes(token)) score += 3;
        if (equipment.includes(token)) score += 1;
        if (category.includes(token)) score += 1;
      }
      return { exercise, score };
    })
    .filter((item) => item.score >= 3)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);

  return scored.map((item) => item.exercise);
}

const STOP_WORDS = new Set([
  'the', 'and', 'for', 'you', 'your', 'how', 'what', 'why', 'should', 'could', 'would',
  'this', 'that', 'with', 'have', 'has', 'are', 'was', 'can', 'get', 'does', 'did',
  'today', 'week', 'workout', 'exercise', 'exercises', 'training', 'train', 'help',
  'good', 'best', 'better', 'need', 'want', 'about', 'from', 'when', 'where', 'which',
]);

export function formatToday(context: TrainingContext): string {
  const parsed = new Date(`${context.today}T00:00:00Z`);
  const weekday = Number.isNaN(parsed.getTime())
    ? ''
    : WEEKDAY[parsed.getUTCDay() === 0 ? 7 : parsed.getUTCDay()];
  return `Today (server UTC date): ${context.today}${weekday ? ` (${weekday})` : ''}`;
}

export function formatProfile(context: TrainingContext): string {
  const profile = context.profile;
  const preferences = context.preferences;
  const lines: string[] = [];

  if (profile) {
    lines.push(
      `Name: ${asString(profile.name, 'Athlete')}`,
      `Age: ${profile.age === null || profile.age === undefined ? 'not provided' : asNumber(profile.age)}`,
      `Experience: ${asString(profile.experience, 'beginner')}`,
      `Training environment: ${asString(profile.environment, 'both')}`,
      `Goals: ${stringList(profile.goals).join(', ') || 'general fitness'}`,
      `Reported limitations: ${asString(profile.limitations, 'none reported')}`,
    );
  } else {
    lines.push('No profile has been completed yet.');
  }

  if (preferences) {
    const days = Array.isArray(preferences.workout_days)
      ? (preferences.workout_days as unknown[]).filter((day): day is number => typeof day === 'number')
      : [];
    lines.push(
      `Selected training weekdays: ${
        days.length > 0 ? days.map((day) => WEEKDAY[day] ?? String(day)).join(', ') : 'not set'
      }`,
      `Session length: ${asNumber(preferences.session_minutes, 45)} minutes`,
      `Equipment available: ${stringList(preferences.equipment).join(', ') || 'not set'}`,
      `Exercises to avoid: ${stringList(preferences.avoid_exercises).join(', ') || 'none'}`,
      `Units: ${asString(preferences.units, 'kg')}`,
    );
  } else {
    lines.push('No training preferences saved yet.');
  }

  return lines.join('\n');
}

/** Current plan plus explicit freshness. Stale plans are never presented as current. */
export function formatPlan(context: TrainingContext): string {
  const plan = context.plan;
  if (!plan) return 'No active training plan. Do not imply one exists.';

  const days = arr(plan.days)
    .slice()
    .sort((a, b) => asNumber(a.day_index) - asNumber(b.day_index));

  const blocks = days.map((day) => {
    const weekday = asNumber(day.weekday);
    const title = asString(day.title, 'Training');
    if (day.is_rest_day) {
      return `${WEEKDAY[weekday] ?? 'Day'}: rest day — ${asString(day.rest_note, 'recovery')}`;
    }
    const exercises = arr(day.exercises)
      .slice()
      .sort((a, b) => asNumber(a.position) - asNumber(b.position))
      .map((exercise) => {
        const name = context.exerciseName(asString(exercise.exercise_id));
        return `${name} ${asNumber(exercise.sets, 3)}x${asNumber(exercise.reps_min, 8)}-${asNumber(
          exercise.reps_max,
          12,
        )} (rest ${asNumber(exercise.rest_seconds, 90)}s)`;
      });
    return `${WEEKDAY[weekday] ?? 'Day'}: ${title} — ${exercises.join('; ') || 'no exercises'}`;
  });

  const created = asString(plan.created_at).slice(0, 10);
  const freshness =
    context.planAgeDays !== null
      ? `Plan created: ${created || 'date unknown'} (${context.planAgeDays} days ago)${
          context.planStale ? ' — STALE: confirm with the athlete before treating it as current.' : ''
        }`
      : 'Plan creation date unavailable.';

  return [
    `Plan: ${asString(plan.name, 'Training plan')} (goal: ${asString(plan.goal, 'general')}, ${asNumber(
      plan.days_per_week,
      days.filter((day) => !day.is_rest_day).length,
    )} days/week, ${asNumber(plan.session_minutes, 45)} min sessions)`,
    freshness,
    ...blocks,
  ].join('\n');
}

export function formatHistory(context: TrainingContext): string {
  const completed = context.sessions.filter((session) => session.status === 'completed');
  if (completed.length === 0) {
    return 'No completed workouts have been recorded for this account. Do not claim to have reviewed workout history; say it is unavailable.';
  }

  const lastAge = context.lastSessionAt ? daysSince(context.lastSessionAt) : null;
  const header =
    lastAge !== null
      ? `Most recent completed workout: ${context.lastSessionAt?.slice(0, 10)} (${lastAge} days ago).`
      : 'Most recent workout date unavailable.';

  return [
    header,
    ...completed.slice(0, 8).map((session) => {
      const sets = arr(session.sets);
      const volume = sets.reduce((total, set) => {
        const weight = Number(set.weight_kg);
        const reps = asNumber(set.reps);
        return total + (Number.isFinite(weight) ? weight * reps : 0);
      }, 0);
      const date = asString(session.started_at).slice(0, 10);
      const notes = asString(session.notes).trim();
      return `${date}: ${asString(session.title, 'Workout')} · ${Math.round(
        asNumber(session.duration_seconds) / 60,
      )} min · ${sets.length} sets${volume > 0 ? ` · ${Math.round(volume)} kg volume` : ''}${
        notes ? ` · notes: ${notes.slice(0, 140)}` : ''
      }`;
    }),
  ].join('\n');
}

/** Recent per-exercise performance, derived from logged sets. */
export function formatExerciseHistory(context: TrainingContext): string {
  const rows = context.exerciseHistory;
  if (rows.length === 0) return 'No exercise-level history recorded yet.';

  const grouped = new Map<
    string,
    { sessions: Set<string>; sets: number; reps: number; topWeight: number; last: string }
  >();

  for (const row of rows) {
    const id = asString(row.exercise_id);
    if (!id) continue;
    const entry = grouped.get(id) ?? {
      sessions: new Set<string>(),
      sets: 0,
      reps: 0,
      topWeight: 0,
      last: asString(row.completed_at).slice(0, 10),
    };
    entry.sets += 1;
    entry.reps += asNumber(row.reps);
    const weight = Number(row.weight_kg);
    if (Number.isFinite(weight)) entry.topWeight = Math.max(entry.topWeight, weight);
    const date = asString(row.completed_at).slice(0, 10);
    if (date && date > entry.last) entry.last = date;
    grouped.set(id, entry);
  }

  return [...grouped.entries()]
    .slice(0, 12)
    .map(([id, entry]) => {
      const weight = entry.topWeight > 0 ? `, top ${Math.round(entry.topWeight * 10) / 10} kg` : '';
      return `${context.exerciseName(id)}: ${entry.sets} sets, ${entry.reps} reps logged${weight}, last ${entry.last}`;
    })
    .join('\n');
}

export function formatExerciseCatalog(context: TrainingContext, limit = 160): string {
  return context.exercises
    .slice(0, Math.max(1, limit))
    .map((exercise) => {
      const muscles = stringList(exercise.primary_muscles).join('/');
      const equipment = stringList(exercise.equipment).join(', ');
      return `${asString(exercise.id)} — ${asString(exercise.name)} (${muscles}; ${equipment}; ${asString(
        exercise.difficulty,
        'beginner',
      )})`;
    })
    .join('\n');
}

/** Full reference entries for retrieved exercises, used for grounded answers. */
export function formatRetrievedExercises(rows: Row[], context: TrainingContext): string {
  if (rows.length === 0) return '';
  return rows
    .map((row) => {
      const lines = [
        `### ${asString(row.name)} (id: ${asString(row.id)})`,
        `Category: ${asString(row.category)} · Difficulty: ${asString(row.difficulty)} · Equipment: ${stringList(
          row.equipment,
        ).join(', ') || 'none'}`,
        `Primary muscles: ${stringList(row.primary_muscles).join(', ') || 'not listed'}${
          stringList(row.secondary_muscles).length > 0
            ? ` · Secondary: ${stringList(row.secondary_muscles).join(', ')}`
            : ''
        }`,
      ];
      const instructions = stringList(row.instructions).slice(0, 5);
      if (instructions.length > 0) {
        lines.push('Instructions:');
        instructions.forEach((item, index) => lines.push(`${index + 1}. ${item.slice(0, 220)}`));
      }
      const cues = stringList(row.cues).slice(0, 3);
      if (cues.length > 0) lines.push(`Coaching cues: ${cues.join(' | ')}`);
      const mistakes = stringList(row.mistakes).slice(0, 3);
      if (mistakes.length > 0) lines.push(`Common mistakes: ${mistakes.join(' | ')}`);
      const alternatives = stringList(row.alternatives).slice(0, 4);
      if (alternatives.length > 0) {
        lines.push(`Alternatives: ${alternatives.map((id) => context.exerciseName(id)).join(', ')}`);
      }
      return lines.join('\n');
    })
    .join('\n\n');
}

/**
 * Trims prompt sections to a character budget without dropping the active plan
 * or safety-relevant profile. Later sections are shortened first.
 */
export function fitContextBudget(sections: { title: string; body: string }[], budget: number): string {
  let remaining = Math.max(2000, budget);
  const output: string[] = [];
  for (const section of sections) {
    if (!section.body.trim()) continue;
    const header = `## ${section.title}`;
    const room = Math.max(0, remaining - header.length - 2);
    if (room < 120) continue;
    const body = section.body.length <= room ? section.body : `${section.body.slice(0, room - 24)}\n[section truncated]`;
    output.push(`${header}\n${body}`);
    remaining -= header.length + body.length + 2;
  }
  return output.join('\n\n');
}
