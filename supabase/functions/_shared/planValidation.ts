/**
 * Strict, deterministic validation for AI-generated plans. The model is never
 * trusted to respect the athlete's equipment, schedule, or safe volume limits.
 */

export type PlanPayload = {
  name: string;
  days: {
    weekday: number;
    title: string;
    focus: string[];
    estimatedMinutes: number;
    isRestDay: boolean;
    restNote: string | null;
    warmup: string[];
    cooldown: string[];
    exercises: {
      exerciseId: string;
      sets: number;
      repsMin: number;
      repsMax: number;
      restSeconds: number;
      notes: string | null;
    }[];
  }[];
};

export type PlanConstraints = {
  allowedIds: Set<string>;
  preferredWeekdays: number[];
  sessionMinutes: number;
  experience: 'beginner' | 'intermediate' | 'advanced';
};

export type ValidationIssue = {
  severity: 'warning' | 'error';
  code: string;
  message: string;
};

export type PlanValidationResult = {
  plan: PlanPayload | null;
  issues: ValidationIssue[];
};

const MUSCLES = new Set([
  'chest',
  'back',
  'shoulders',
  'arms',
  'quads',
  'hamstrings',
  'glutes',
  'calves',
  'core',
  'hips',
  'full-body',
]);

const DEFAULT_WARMUP = [
  '5 minutes of easy cardio to raise your body temperature',
  'A light rehearsal set of the first exercise',
];
const DEFAULT_COOLDOWN = [
  '3–5 minutes of easy walking to bring your heart rate down',
  'Gentle static stretching for the muscles you trained',
];

type RawExercise = {
  exerciseId?: unknown;
  sets?: unknown;
  repsMin?: unknown;
  repsMax?: unknown;
  restSeconds?: unknown;
  notes?: unknown;
};

type RawDay = {
  weekday?: unknown;
  title?: unknown;
  focus?: unknown;
  estimatedMinutes?: unknown;
  isRestDay?: unknown;
  restNote?: unknown;
  warmup?: unknown;
  cooldown?: unknown;
  exercises?: unknown;
};

function clamp(value: unknown, min: number, max: number, fallback: number): number {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, Math.round(number)));
}

function text(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed.slice(0, max) : null;
}

function stringList(value: unknown, maxItems: number, maxLength: number): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => text(item, maxLength))
    .filter((item): item is string => Boolean(item))
    .slice(0, maxItems);
}

export function validateAndNormalizePlan(
  raw: unknown,
  constraints: PlanConstraints,
): PlanValidationResult {
  const issues: ValidationIssue[] = [];
  const error = (code: string, message: string) =>
    issues.push({ severity: 'error', code, message });
  const warn = (code: string, message: string) =>
    issues.push({ severity: 'warning', code, message });

  if (!raw || typeof raw !== 'object') {
    error('invalid_json', 'The plan was not a JSON object.');
    return { plan: null, issues };
  }

  const data = raw as { name?: unknown; days?: unknown };
  if (!Array.isArray(data.days)) {
    error('missing_days', 'The plan did not contain a days array.');
    return { plan: null, issues };
  }

  const byWeekday = new Map<number, RawDay>();
  for (const day of data.days) {
    if (!day || typeof day !== 'object') continue;
    const candidate = day as RawDay;
    const weekday = clamp(candidate.weekday, 1, 7, 0);
    if (weekday > 0 && !byWeekday.has(weekday)) byWeekday.set(weekday, candidate);
  }
  if (byWeekday.size === 0) {
    error('missing_days', 'No weekday could be read from the plan.');
    return { plan: null, issues };
  }

  const preferred = [...new Set(constraints.preferredWeekdays.filter((day) => day >= 1 && day <= 7))].sort(
    (a, b) => a - b,
  );
  const preferredSet = new Set(preferred);
  const sessionMinutes = Math.max(10, Math.min(180, Math.round(constraints.sessionMinutes || 45)));
  const maxSets = constraints.experience === 'beginner' ? 3 : 5;

  const days: PlanPayload['days'] = [];
  let trainingDays = 0;

  for (let weekday = 1; weekday <= 7; weekday += 1) {
    const day = byWeekday.get(weekday);
    const wantsTraining = preferredSet.size === 0 || preferredSet.has(weekday);

    if (!day || day.isRestDay === true) {
      if (wantsTraining) {
        error(
          'missing_training_day',
          `Weekday ${weekday} should be a training day but the plan made it rest.`,
        );
      }
      days.push({
        weekday,
        title: text(day?.title, 60) ?? 'Recovery',
        focus: [],
        estimatedMinutes: 0,
        isRestDay: true,
        restNote:
          text(day?.restNote, 200) ?? 'Easy movement, mobility, and enough food and sleep.',
        warmup: [],
        cooldown: [],
        exercises: [],
      });
      continue;
    }

    if (!wantsTraining) {
      error(
        'unexpected_training_day',
        `Weekday ${weekday} was not one of the athlete's chosen training days.`,
      );
      days.push({
        weekday,
        title: 'Recovery',
        focus: [],
        estimatedMinutes: 0,
        isRestDay: true,
        restNote: 'Recovery day outside the athlete’s selected schedule.',
        warmup: [],
        cooldown: [],
        exercises: [],
      });
      continue;
    }

    const focus = Array.isArray(day.focus)
      ? day.focus
          .filter((item): item is string => typeof item === 'string' && MUSCLES.has(item))
          .slice(0, 4)
      : [];

    const rawExercises = Array.isArray(day.exercises)
      ? (day.exercises as RawExercise[])
      : [];
    const seen = new Set<string>();
    const exercises: PlanPayload['days'][number]['exercises'] = [];

    for (const exercise of rawExercises) {
      const exerciseId = text(exercise.exerciseId, 80);
      if (!exerciseId) {
        error('missing_exercise_id', 'An exercise entry had no id.');
        continue;
      }
      if (!constraints.allowedIds.has(exerciseId)) {
        error(
          'exercise_not_allowed',
          `"${exerciseId}" is not in the verified library with the athlete’s equipment.`,
        );
        continue;
      }
      if (seen.has(exerciseId)) {
        error('duplicate_exercise', `"${exerciseId}" appeared more than once on the same day.`);
        continue;
      }
      seen.add(exerciseId);

      const rawSets = clamp(exercise.sets, 1, 6, 3);
      const sets = Math.min(rawSets, maxSets);
      if (rawSets !== sets) {
        warn('sets_clamped', `Sets for "${exerciseId}" were reduced to ${sets} for safe volume.`);
      }

      const repsMinRaw = clamp(exercise.repsMin, 3, 30, 8);
      const repsMaxRaw = clamp(exercise.repsMax, 3, 40, Math.max(repsMinRaw, 12));
      const repsMin = Math.min(repsMinRaw, 25);
      const repsMax = Math.max(repsMin, Math.min(repsMaxRaw, constraints.experience === 'beginner' ? 20 : 30));
      if (repsMin !== repsMinRaw || repsMax !== repsMaxRaw) {
        warn('reps_clamped', `Rep range for "${exerciseId}" was adjusted to a safe range.`);
      }

      const restSeconds = clamp(exercise.restSeconds, 30, 180, 90);

      exercises.push({
        exerciseId,
        sets,
        repsMin,
        repsMax,
        restSeconds,
        notes: text(exercise.notes, 200),
      });
    }

    if (exercises.length < 2) {
      error(
        'insufficient_exercises',
        `Weekday ${weekday} needs at least two verified exercises; the plan had ${exercises.length}.`,
      );
      continue;
    }
    if (exercises.length > 6) {
      warn('exercises_truncated', `Weekday ${weekday} was trimmed to six exercises.`);
      exercises.splice(6);
    }

    const estimatedMinutes = clamp(day.estimatedMinutes, 10, 120, sessionMinutes);
    if (Math.abs(estimatedMinutes - sessionMinutes) > 15) {
      error(
        'duration_mismatch',
        `Weekday ${weekday} was estimated at ${estimatedMinutes} minutes; the athlete selected ${sessionMinutes}.`,
      );
    }

    const warmup = stringList(day.warmup, 6, 160);
    const cooldown = stringList(day.cooldown, 6, 160);
    if (warmup.length === 0) warn('missing_warmup', `Weekday ${weekday} had no warm-up; a standard one was added.`);
    if (cooldown.length === 0) warn('missing_cooldown', `Weekday ${weekday} had no cool-down; a standard one was added.`);

    trainingDays += 1;
    days.push({
      weekday,
      title: text(day.title, 60) ?? 'Training',
      focus,
      estimatedMinutes,
      isRestDay: false,
      restNote: null,
      warmup: warmup.length > 0 ? warmup : DEFAULT_WARMUP,
      cooldown: cooldown.length > 0 ? cooldown : DEFAULT_COOLDOWN,
      exercises,
    });
  }

  if (preferred.length > 0 && trainingDays !== preferred.length) {
    error(
      'training_day_count',
      `The plan has ${trainingDays} training days but the athlete selected ${preferred.length}.`,
    );
  }
  if (trainingDays === 0) {
    error('no_training_days', 'The plan contained no usable training day.');
  }

  const hasErrors = issues.some((issue) => issue.severity === 'error');
  if (hasErrors) return { plan: null, issues };

  return {
    plan: {
      name: text(data.name, 60) ?? 'Personal training plan',
      days,
    },
    issues,
  };
}
