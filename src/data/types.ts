export type Experience = 'beginner' | 'intermediate' | 'advanced';
export type Environment = 'gym' | 'home' | 'both';
export type Goal = 'strength' | 'endurance' | 'mobility' | 'general' | 'consistency';
export type Equipment =
  | 'bodyweight'
  | 'dumbbells'
  | 'barbell'
  | 'kettlebell'
  | 'resistance-band'
  | 'cable'
  | 'machine'
  | 'bench'
  | 'pull-up-bar'
  | 'jump-rope';
export type Category = 'strength' | 'conditioning' | 'mobility';
export type MuscleGroup =
  | 'chest'
  | 'back'
  | 'shoulders'
  | 'arms'
  | 'quads'
  | 'hamstrings'
  | 'glutes'
  | 'calves'
  | 'core'
  | 'hips'
  | 'full-body';
export type Difficulty = 'beginner' | 'intermediate' | 'advanced';
export type PlanSource = 'ai' | 'on-device';
export type SessionStatus = 'active' | 'paused' | 'completed' | 'abandoned';

export type Profile = {
  id: string;
  name: string;
  age: number | null;
  experience: Experience;
  environment: Environment;
  goals: Goal[];
  limitations: string | null;
  onboardingCompleted: boolean;
  createdAt: string;
};

export type Preferences = {
  userId: string;
  workoutDays: number[];
  sessionMinutes: number;
  equipment: Equipment[];
  avoidExercises: string[];
  reminderTime: string;
  units: 'kg' | 'lb';
};

export type Exercise = {
  id: string;
  name: string;
  category: Category;
  primaryMuscles: MuscleGroup[];
  secondaryMuscles: MuscleGroup[];
  equipment: Equipment[];
  difficulty: Difficulty;
  instructions: string[];
  cues: string[];
  mistakes: string[];
  alternatives: string[];
  isUnilateral?: boolean;
};

export type WorkoutExercise = {
  id: string;
  dayId: string;
  exerciseId: string;
  position: number;
  sets: number;
  repsMin: number;
  repsMax: number;
  restSeconds: number;
  notes: string | null;
};

export type WorkoutDay = {
  id: string;
  planId: string;
  dayIndex: number;
  weekday: number | null;
  title: string;
  focus: MuscleGroup[];
  estimatedMinutes: number;
  warmup: string[];
  cooldown: string[];
  isRestDay: boolean;
  restNote: string | null;
  exercises: WorkoutExercise[];
};

export type WorkoutPlan = {
  id: string;
  userId: string;
  name: string;
  goal: Goal;
  experience: Experience;
  daysPerWeek: number;
  sessionMinutes: number;
  equipment: Equipment[];
  source: PlanSource;
  createdAt: string;
  days: WorkoutDay[];
};

export type CompletedSet = {
  id: string;
  sessionId: string;
  workoutExerciseId: string | null;
  exerciseId: string;
  setNumber: number;
  reps: number;
  weightKg: number | null;
  completedAt: string;
};

export type WorkoutSession = {
  id: string;
  userId: string;
  planDayId: string | null;
  title: string;
  focus: MuscleGroup[];
  startedAt: string;
  endedAt: string | null;
  durationSeconds: number;
  status: SessionStatus;
  sets: CompletedSet[];
  notes: string | null;
};

export type ReminderSettings = {
  userId: string;
  enabled: boolean;
  workoutTime: string;
  days: number[];
  restDayReminders: boolean;
  hydrationReminders: boolean;
  weeklyProgressReminder: boolean;
  scheduledIds: string[];
};

export type CoachConversation = {
  id: string;
  userId: string;
  title: string;
  createdAt: string;
  updatedAt: string;
};

export type CoachMessage = {
  id: string;
  conversationId: string;
  userId: string;
  role: 'user' | 'assistant';
  content: string;
  createdAt: string;
};

export type ProgressRecord = {
  id: string;
  userId: string;
  recordedAt: string;
  bodyweightKg: number | null;
  notes: string | null;
};

export type AppUser = {
  id: string;
  email: string | null;
};

export type ActiveWorkout = {
  sessionId: string;
  userId: string;
  planDayId: string;
  planId: string;
  title: string;
  focus: MuscleGroup[];
  warmup: string[];
  cooldown: string[];
  startedAt: string;
  status: 'active' | 'paused';
  pausedAt: string | null;
  pausedSeconds: number;
  currentExerciseIndex: number;
  exercises: WorkoutExercise[];
  sets: CompletedSet[];
  rest: {
    endsAt: string | null;
    durationSeconds: number;
    pausedRemaining: number | null;
    exerciseId: string;
  } | null;
};

export type LibraryFilters = {
  query: string;
  category: Category | 'all';
  muscle: MuscleGroup | 'all';
  equipment: Equipment | 'all';
  difficulty: Difficulty | 'all';
};

export const EXPERIENCE_LABEL: Record<Experience, string> = {
  beginner: 'Beginner',
  intermediate: 'Intermediate',
  advanced: 'Advanced',
};

export const GOAL_LABEL: Record<Goal, string> = {
  strength: 'Build strength',
  endurance: 'Improve endurance',
  mobility: 'Move better',
  general: 'General fitness',
  consistency: 'Build consistency',
};

export const EQUIPMENT_LABEL: Record<Equipment, string> = {
  bodyweight: 'Bodyweight',
  dumbbells: 'Dumbbells',
  barbell: 'Barbell',
  kettlebell: 'Kettlebell',
  'resistance-band': 'Resistance bands',
  cable: 'Cable station',
  machine: 'Machines',
  bench: 'Bench',
  'pull-up-bar': 'Pull-up bar',
  'jump-rope': 'Jump rope',
};

export const MUSCLE_LABEL: Record<MuscleGroup, string> = {
  chest: 'Chest',
  back: 'Back',
  shoulders: 'Shoulders',
  arms: 'Arms',
  quads: 'Quads',
  hamstrings: 'Hamstrings',
  glutes: 'Glutes',
  calves: 'Calves',
  core: 'Core',
  hips: 'Hips',
  'full-body': 'Full body',
};

export const WEEKDAY_LABEL: Record<number, string> = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};
