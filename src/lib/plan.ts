import exercisesJson from '@/data/exercises.json';
import type {
  Equipment,
  Exercise,
  Experience,
  Goal,
  MuscleGroup,
  Preferences,
  Profile,
  WorkoutDay,
  WorkoutExercise,
  WorkoutPlan,
} from '@/data/types';
import { newId } from '@/lib/id';

export const EXERCISE_LIBRARY = exercisesJson as Exercise[];

export const exerciseMap: Record<string, Exercise> = Object.fromEntries(
  EXERCISE_LIBRARY.map((exercise) => [exercise.id, exercise]),
);

export function getExercise(id: string): Exercise | undefined {
  return exerciseMap[id];
}

export function exerciseName(id: string): string {
  return exerciseMap[id]?.name ?? id;
}

type TemplateKind = 'full' | 'upper' | 'lower' | 'push' | 'pull' | 'legs' | 'mobility';

type Slot = MuscleGroup[];

const SLOTS: Record<TemplateKind, Slot[]> = {
  full: [
    ['quads', 'glutes'],
    ['chest'],
    ['back'],
    ['hamstrings', 'glutes'],
    ['core'],
    ['shoulders', 'arms'],
    ['full-body'],
  ],
  upper: [
    ['chest'],
    ['back'],
    ['shoulders'],
    ['arms'],
    ['core'],
    ['back'],
    ['chest', 'arms'],
  ],
  lower: [
    ['quads'],
    ['hamstrings', 'glutes'],
    ['glutes'],
    ['calves'],
    ['core'],
    ['quads', 'hamstrings'],
  ],
  push: [
    ['chest'],
    ['shoulders'],
    ['arms'],
    ['chest'],
    ['core'],
    ['shoulders'],
  ],
  pull: [
    ['back'],
    ['back'],
    ['shoulders'],
    ['arms'],
    ['core'],
    ['back'],
  ],
  legs: [
    ['quads'],
    ['hamstrings'],
    ['glutes'],
    ['calves'],
    ['core'],
    ['quads', 'glutes'],
  ],
  mobility: [
    ['back', 'hips'],
    ['hips'],
    ['shoulders'],
    ['hamstrings'],
    ['calves'],
    ['back'],
  ],
};

const TEMPLATE_META: Record<TemplateKind, { title: string; focus: MuscleGroup[] }> = {
  full: { title: 'Full body', focus: ['full-body', 'quads', 'chest', 'back', 'core'] },
  upper: { title: 'Upper body', focus: ['chest', 'back', 'shoulders', 'arms', 'core'] },
  lower: { title: 'Lower body', focus: ['quads', 'hamstrings', 'glutes', 'calves', 'core'] },
  push: { title: 'Push', focus: ['chest', 'shoulders', 'arms', 'core'] },
  pull: { title: 'Pull', focus: ['back', 'shoulders', 'arms', 'core'] },
  legs: { title: 'Legs', focus: ['quads', 'hamstrings', 'glutes', 'calves', 'core'] },
  mobility: { title: 'Mobility & recovery', focus: ['hips', 'back', 'shoulders'] },
};

function templateSequence(trainingDays: number): TemplateKind[] {
  if (trainingDays <= 1) return ['full'];
  if (trainingDays === 2) return ['full', 'full'];
  if (trainingDays === 3) return ['full', 'full', 'full'];
  if (trainingDays === 4) return ['upper', 'lower', 'upper', 'lower'];
  if (trainingDays === 5) return ['push', 'pull', 'legs', 'upper', 'full'];
  if (trainingDays === 6) return ['push', 'pull', 'legs', 'push', 'pull', 'legs'];
  return ['push', 'pull', 'legs', 'upper', 'lower', 'full', 'mobility'];
}

function evenlySpacedWeekdays(count: number): number[] {
  const picks: number[] = [];
  const gap = 7 / count;
  for (let index = 0; index < count; index += 1) {
    picks.push(Math.max(1, Math.min(7, Math.round(1 + index * gap))));
  }
  return Array.from(new Set(picks)).slice(0, count);
}

function normaliseWeekdays(selected: number[], count: number): number[] {
  const valid = Array.from(new Set(selected.filter((day) => day >= 1 && day <= 7))).sort();
  if (valid.length >= count) return valid.slice(0, count);
  const fallback = evenlySpacedWeekdays(count);
  return Array.from(new Set([...valid, ...fallback])).sort((a, b) => a - b).slice(0, count);
}

function exerciseCount(minutes: number): number {
  if (minutes <= 20) return 3;
  if (minutes <= 30) return 4;
  if (minutes <= 45) return 5;
  if (minutes <= 60) return 6;
  return 7;
}

function allowedDifficulties(experience: Experience) {
  if (experience === 'beginner') return ['beginner'] as const;
  if (experience === 'intermediate') return ['beginner', 'intermediate'] as const;
  return ['beginner', 'intermediate', 'advanced'] as const;
}

function equipmentAvailable(exercise: Exercise, equipment: Equipment[]): boolean {
  return exercise.equipment.every((item) => item === 'bodyweight' || equipment.includes(item));
}

function pickExercise(
  slot: Slot,
  kind: TemplateKind,
  dayIndex: number,
  slotIndex: number,
  input: { preferences: Preferences; profile: Profile; used: Set<string> },
): Exercise | null {
  const allowed = allowedDifficulties(input.profile.experience);
  const category = kind === 'mobility' ? 'mobility' : 'strength';
  const candidates = EXERCISE_LIBRARY.filter((exercise) => {
    if (input.used.has(exercise.id)) return false;
    if (input.preferences.avoidExercises.includes(exercise.id)) return false;
    if (!equipmentAvailable(exercise, input.preferences.equipment)) return false;
    if (exercise.category !== category) return false;
    if (!(allowed as readonly string[]).includes(exercise.difficulty)) return false;
    return exercise.primaryMuscles.some((muscle) => slot.includes(muscle));
  });

  const fallback = EXERCISE_LIBRARY.filter((exercise) => {
    if (input.used.has(exercise.id)) return false;
    if (input.preferences.avoidExercises.includes(exercise.id)) return false;
    if (!equipmentAvailable(exercise, input.preferences.equipment)) return false;
    if (exercise.category !== category) return false;
    return exercise.primaryMuscles.some((muscle) => slot.includes(muscle));
  });

  const pool = candidates.length > 0 ? candidates : fallback;
  if (pool.length === 0) return null;
  return pool[(dayIndex + slotIndex) % pool.length];
}

function repRange(goal: Goal, experience: Experience): { min: number; max: number; rest: number } {
  if (goal === 'strength') {
    return experience === 'beginner'
      ? { min: 8, max: 10, rest: 90 }
      : { min: 5, max: 8, rest: 120 };
  }
  if (goal === 'endurance') return { min: 12, max: 15, rest: 60 };
  if (goal === 'mobility') return { min: 8, max: 12, rest: 45 };
  if (goal === 'consistency') return { min: 8, max: 12, rest: 75 };
  return { min: 8, max: 12, rest: 90 };
}

function setCount(experience: Experience, index: number): number {
  const base = experience === 'beginner' ? 2 : experience === 'intermediate' ? 3 : 3;
  return index === 0 ? base + (experience === 'advanced' ? 1 : 0) : base;
}

function buildWarmup(kind: TemplateKind): string[] {
  if (kind === 'mobility') {
    return [
      '2–3 minutes of easy walking or gentle marching',
      'Move through each mobility drill slowly; stay well below pain',
    ];
  }
  const lower = kind === 'lower' || kind === 'legs';
  const upper = kind === 'upper' || kind === 'push' || kind === 'pull';
  return [
    '5 minutes of easy cardio — walk, bike, or row',
    lower ? '10 leg swings each side and 10 bodyweight squats' : '10 arm circles each direction and 10 shoulder rolls',
    upper ? 'One light set of your first exercise' : '10 slow hip hinges and 10 glute bridges',
  ];
}

function buildCooldown(kind: TemplateKind): string[] {
  if (kind === 'mobility') {
    return ['Finish with 3 slow breaths in a comfortable seated position', 'Drink some water and note how your body feels'];
  }
  return [
    '3–5 minutes of easy walking to bring your heart rate down',
    kind === 'lower' || kind === 'legs'
      ? 'Hold a gentle hamstring and hip flexor stretch for 30 seconds each side'
      : 'Hold a gentle chest and lat stretch for 30 seconds each side',
    'Take a few slow breaths and note your effort for next time',
  ];
}

const REST_NOTES = [
  'A planned rest day is part of the programme. Walk, stretch gently, or simply recover.',
  'Recovery day — prioritize sleep, food, and easy movement. Training adapts when you rest.',
  'Keep today light. Your next session will be better for it.',
  'Rest is productive. A short walk and some easy mobility is plenty.',
];

export function generateLocalPlan(input: {
  userId: string;
  profile: Profile;
  preferences: Preferences;
}): WorkoutPlan {
  const { profile, preferences, userId } = input;
  const trainingDays = Math.max(1, Math.min(7, preferences.workoutDays.length || 3));
  const weekdays = normaliseWeekdays(preferences.workoutDays, trainingDays);
  const sequence = templateSequence(trainingDays);
  const goal: Goal = profile.goals[0] ?? 'general';
  const count = exerciseCount(preferences.sessionMinutes);
  const planId = newId('plan');
  const occurrences = new Map<TemplateKind, number>();

  const trainingByWeekday = new Map<number, { kind: TemplateKind; dayIndex: number }>();
  weekdays.forEach((weekday, index) => {
    trainingByWeekday.set(weekday, { kind: sequence[index] ?? 'full', dayIndex: index });
  });

  const days: WorkoutDay[] = [];
  for (let weekday = 1; weekday <= 7; weekday += 1) {
    const training = trainingByWeekday.get(weekday);
    if (!training) {
      days.push({
        id: newId('day'),
        planId,
        dayIndex: weekday - 1,
        weekday,
        title: 'Recovery',
        focus: [],
        estimatedMinutes: 0,
        warmup: [],
        cooldown: [],
        isRestDay: true,
        restNote: REST_NOTES[(weekday + days.length) % REST_NOTES.length],
        exercises: [],
      });
      continue;
    }

    const meta = TEMPLATE_META[training.kind];
    const usedToday = new Set<string>();
    const slots = SLOTS[training.kind];
    const exercises: WorkoutExercise[] = [];
    const range = repRange(goal, profile.experience);
    const occurrence = occurrences.get(training.kind) ?? 0;
    occurrences.set(training.kind, occurrence + 1);
    const repeats = sequence.filter((kind) => kind === training.kind).length > 1;

    for (let slotIndex = 0; slotIndex < Math.min(count, slots.length); slotIndex += 1) {
      const exercise = pickExercise(slots[slotIndex], training.kind, training.dayIndex, slotIndex, {
        preferences,
        profile,
        used: usedToday,
      });
      if (!exercise) continue;
      usedToday.add(exercise.id);
      exercises.push({
        id: newId('we'),
        dayId: '',
        exerciseId: exercise.id,
        position: exercises.length,
        sets: setCount(profile.experience, slotIndex),
        repsMin: training.kind === 'mobility' ? 5 : range.min,
        repsMax: training.kind === 'mobility' ? 8 : range.max,
        restSeconds: training.kind === 'mobility' ? 30 : range.rest,
        notes:
          training.kind === 'mobility'
            ? 'Move slowly and breathe. Hold or flow through a comfortable range.'
            : slotIndex === 0
              ? 'Leave one or two reps in reserve on the final set.'
              : null,
      });
    }

    const day: WorkoutDay = {
      id: newId('day'),
      planId,
      dayIndex: weekday - 1,
      weekday,
      title: repeats ? `${meta.title} · ${String.fromCharCode(65 + occurrence)}` : meta.title,
      focus: meta.focus,
      estimatedMinutes: Math.min(preferences.sessionMinutes, 8 + exercises.length * 6 + 4),
      warmup: buildWarmup(training.kind),
      cooldown: buildCooldown(training.kind),
      isRestDay: false,
      restNote: null,
      exercises: [],
    };
    day.exercises = exercises.map((exercise, index) => ({
      ...exercise,
      dayId: day.id,
      position: index,
    }));
    days.push(day);
  }

  const baseName =
    profile.experience === 'beginner' ? 'Foundation' : profile.experience === 'intermediate' ? 'Momentum' : 'Apex';

  return {
    id: planId,
    userId,
    name: `${baseName} · ${trainingDays} day${trainingDays === 1 ? '' : 's'}`,
    goal,
    experience: profile.experience,
    daysPerWeek: trainingDays,
    sessionMinutes: preferences.sessionMinutes,
    equipment: preferences.equipment,
    source: 'on-device',
    createdAt: new Date().toISOString(),
    days,
  };
}

export type AiPlanPayload = {
  name?: string;
  days: {
    weekday: number;
    title: string;
    focus: MuscleGroup[];
    estimatedMinutes?: number;
    isRestDay?: boolean;
    restNote?: string | null;
    warmup?: string[];
    cooldown?: string[];
    exercises: {
      exerciseId: string;
      sets: number;
      repsMin: number;
      repsMax: number;
      restSeconds: number;
      notes?: string | null;
    }[];
  }[];
};

const VALID_FOCUS: MuscleGroup[] = [
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
];

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, Math.round(value)));
}

/** Convert the AI payload into our typed plan, discarding unknown exercises and unsafe values. */
export function planFromAiPayload(
  payload: AiPlanPayload,
  input: { userId: string; profile: Profile; preferences: Preferences },
): WorkoutPlan | null {
  if (!payload || !Array.isArray(payload.days) || payload.days.length === 0) return null;
  const planId = newId('plan');
  const byWeekday = new Map(payload.days.map((day) => [Number(day.weekday), day]));
  const days: WorkoutDay[] = [];

  for (let weekday = 1; weekday <= 7; weekday += 1) {
    const raw = byWeekday.get(weekday);
    const id = newId('day');
    if (!raw || raw.isRestDay) {
      days.push({
        id,
        planId,
        dayIndex: weekday - 1,
        weekday,
        title: 'Recovery',
        focus: [],
        estimatedMinutes: 0,
        warmup: [],
        cooldown: [],
        isRestDay: true,
        restNote:
          typeof raw?.restNote === 'string' && raw.restNote.trim()
            ? raw.restNote.trim()
            : REST_NOTES[weekday % REST_NOTES.length],
        exercises: [],
      });
      continue;
    }

    const exercises: WorkoutExercise[] = [];
    for (const item of raw.exercises ?? []) {
      const libraryExercise = exerciseMap[item.exerciseId];
      if (!libraryExercise) continue;
      exercises.push({
        id: newId('we'),
        dayId: id,
        exerciseId: libraryExercise.id,
        position: exercises.length,
        sets: clamp(Number(item.sets) || 3, 1, 5),
        repsMin: clamp(Number(item.repsMin) || 8, 3, 30),
        repsMax: clamp(Number(item.repsMax) || 12, 3, 40),
        restSeconds: clamp(Number(item.restSeconds) || 90, 15, 300),
        notes: typeof item.notes === 'string' ? item.notes.slice(0, 240) : null,
      });
    }
    if (exercises.length === 0) {
      days.push({
        id,
        planId,
        dayIndex: weekday - 1,
        weekday,
        title: 'Recovery',
        focus: [],
        estimatedMinutes: 0,
        warmup: [],
        cooldown: [],
        isRestDay: true,
        restNote: 'Recovery day. The AI plan did not include a safe session here.',
        exercises: [],
      });
      continue;
    }

    days.push({
      id,
      planId,
      dayIndex: weekday - 1,
      weekday,
      title: typeof raw.title === 'string' && raw.title.trim() ? raw.title.trim().slice(0, 60) : 'Training day',
      focus: (raw.focus ?? []).filter((muscle): muscle is MuscleGroup => VALID_FOCUS.includes(muscle)).slice(0, 5),
      estimatedMinutes: clamp(Number(raw.estimatedMinutes) || input.preferences.sessionMinutes, 10, 120),
      warmup: Array.isArray(raw.warmup) ? raw.warmup.slice(0, 5).map(String) : buildWarmup('full'),
      cooldown: Array.isArray(raw.cooldown) ? raw.cooldown.slice(0, 5).map(String) : buildCooldown('full'),
      isRestDay: false,
      restNote: null,
      exercises,
    });
  }

  const trainingDays = days.filter((day) => !day.isRestDay).length;
  if (trainingDays === 0) return null;

  return {
    id: planId,
    userId: input.userId,
    name:
      typeof payload.name === 'string' && payload.name.trim()
        ? payload.name.trim().slice(0, 60)
        : `${input.profile.experience === 'beginner' ? 'Foundation' : 'Momentum'} · ${trainingDays} days`,
    goal: input.profile.goals[0] ?? 'general',
    experience: input.profile.experience,
    daysPerWeek: trainingDays,
    sessionMinutes: input.preferences.sessionMinutes,
    equipment: input.preferences.equipment,
    source: 'ai',
    createdAt: new Date().toISOString(),
    days,
  };
}

export function planForDate(plan: WorkoutPlan, date: Date): WorkoutDay | undefined {
  const weekday = date.getDay() === 0 ? 7 : date.getDay();
  return plan.days.find((day) => day.weekday === weekday);
}

export function nextTrainingDay(plan: WorkoutPlan, from: Date): WorkoutDay | undefined {
  const todayIndex = (from.getDay() === 0 ? 7 : from.getDay()) - 1;
  for (let offset = 1; offset <= 7; offset += 1) {
    const day = plan.days[(todayIndex + offset) % 7];
    if (day && !day.isRestDay) return day;
  }
  return undefined;
}

export function totalExercises(plan: WorkoutPlan): number {
  return plan.days.reduce((total, day) => total + day.exercises.length, 0);
}

export function nextPosition(day: WorkoutDay, exerciseIndex: number): number {
  if (exerciseIndex >= day.exercises.length) return 0;
  return exerciseIndex + 1;
}
