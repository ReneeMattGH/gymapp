import * as Linking from 'expo-linking';

import exercisesJson from './exercises.json';
import type { AuthResult, GymRepository, RepositoryKind } from './repository';
import type {
  AppUser,
  CoachConversation,
  CoachMessage,
  Category,
  CompletedSet,
  Difficulty,
  Equipment,
  Exercise,
  Experience,
  Goal,
  MuscleGroup,
  Preferences,
  Profile,
  ProgressRecord,
  ReminderSettings,
  SessionStatus,
  WorkoutDay,
  WorkoutExercise,
  WorkoutPlan,
  WorkoutSession,
} from './types';
import { requireSupabase } from '@/lib/supabase';

const FALLBACK_EXERCISES = exercisesJson as Exercise[];

type Row = Record<string, any>;

function mapExercise(row: Row): Exercise {
  return {
    id: row.id,
    name: row.name,
    category: row.category as Category,
    primaryMuscles: (row.primary_muscles ?? []) as MuscleGroup[],
    secondaryMuscles: (row.secondary_muscles ?? []) as MuscleGroup[],
    equipment: (row.equipment ?? []) as Equipment[],
    difficulty: row.difficulty as Difficulty,
    instructions: row.instructions ?? [],
    cues: row.cues ?? [],
    mistakes: row.mistakes ?? [],
    alternatives: row.alternatives ?? [],
    isUnilateral: Boolean(row.is_unilateral),
  };
}

function mapProfile(row: Row): Profile {
  return {
    id: row.id,
    name: row.name ?? 'Athlete',
    age: row.age ?? null,
    experience: (row.experience ?? 'beginner') as Experience,
    environment: row.environment ?? 'both',
    goals: (row.goals ?? []) as Goal[],
    limitations: row.limitations ?? null,
    onboardingCompleted: Boolean(row.onboarding_completed),
    createdAt: row.created_at,
  };
}

function mapPreferences(row: Row): Preferences {
  return {
    userId: row.user_id,
    workoutDays: row.workout_days ?? [],
    sessionMinutes: row.session_minutes ?? 45,
    equipment: (row.equipment ?? []) as Equipment[],
    avoidExercises: row.avoid_exercises ?? [],
    reminderTime: row.reminder_time ?? '18:00',
    units: row.units === 'lb' ? 'lb' : 'kg',
  };
}

function mapExerciseRow(row: Row, dayId: string): WorkoutExercise {
  return {
    id: row.id,
    dayId,
    exerciseId: row.exercise_id,
    position: row.position ?? 0,
    sets: row.sets ?? 3,
    repsMin: row.reps_min ?? 8,
    repsMax: row.reps_max ?? 12,
    restSeconds: row.rest_seconds ?? 90,
    notes: row.notes ?? null,
  };
}

function mapPlan(row: Row): WorkoutPlan {
  const days = ((row.days ?? []) as Row[])
    .map<WorkoutDay>((day) => ({
      id: day.id,
      planId: day.plan_id ?? row.id,
      dayIndex: day.day_index ?? 0,
      weekday: day.weekday ?? null,
      title: day.title,
      focus: (day.focus ?? []) as MuscleGroup[],
      estimatedMinutes: day.estimated_minutes ?? 0,
      warmup: day.warmup ?? [],
      cooldown: day.cooldown ?? [],
      isRestDay: Boolean(day.is_rest_day),
      restNote: day.rest_note ?? null,
      exercises: ((day.exercises ?? []) as Row[])
        .slice()
        .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
        .map((exercise) => mapExerciseRow(exercise, day.id)),
    }))
    .sort((a, b) => a.dayIndex - b.dayIndex);

  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    goal: row.goal as Goal,
    experience: row.experience as Experience,
    daysPerWeek: row.days_per_week ?? days.filter((day) => !day.isRestDay).length,
    sessionMinutes: row.session_minutes ?? 45,
    equipment: (row.equipment ?? []) as Equipment[],
    source: row.generated_by === 'ai' ? 'ai' : 'on-device',
    createdAt: row.created_at,
    days,
  };
}

function mapSet(row: Row): CompletedSet {
  return {
    id: row.id,
    sessionId: row.session_id,
    workoutExerciseId: row.workout_exercise_id ?? null,
    exerciseId: row.exercise_id,
    setNumber: row.set_number ?? 1,
    reps: row.reps ?? 0,
    weightKg: row.weight_kg === null ? null : Number(row.weight_kg),
    completedAt: row.completed_at,
  };
}

function mapSession(row: Row): WorkoutSession {
  return {
    id: row.id,
    userId: row.user_id,
    planDayId: row.plan_day_id ?? null,
    title: row.title,
    focus: (row.focus ?? []) as MuscleGroup[],
    startedAt: row.started_at,
    endedAt: row.ended_at ?? null,
    durationSeconds: row.duration_seconds ?? 0,
    status: (row.status ?? 'completed') as SessionStatus,
    sets: ((row.sets ?? []) as Row[])
      .slice()
      .sort((a, b) => (a.completed_at < b.completed_at ? -1 : 1))
      .map(mapSet),
    notes: row.notes ?? null,
  };
}

function mapReminder(row: Row): ReminderSettings {
  return {
    userId: row.user_id,
    enabled: Boolean(row.enabled),
    workoutTime: row.workout_time ?? '18:00',
    days: row.days ?? [],
    restDayReminders: Boolean(row.rest_day_reminders),
    hydrationReminders: Boolean(row.hydration_reminders),
    weeklyProgressReminder: Boolean(row.weekly_progress_reminder),
    scheduledIds: row.scheduled_ids ?? [],
  };
}

function mapConversation(row: Row): CoachConversation {
  return {
    id: row.id,
    userId: row.user_id,
    title: row.title ?? 'Coach chat',
    createdAt: row.created_at,
    updatedAt: row.updated_at ?? row.created_at,
  };
}

function mapMessage(row: Row): CoachMessage {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    userId: row.user_id,
    role: row.role,
    content: row.content,
    createdAt: row.created_at,
  };
}

function mapProgress(row: Row): ProgressRecord {
  return {
    id: row.id,
    userId: row.user_id,
    recordedAt: row.recorded_at,
    bodyweightKg: row.bodyweight_kg === null ? null : Number(row.bodyweight_kg),
    notes: row.notes ?? null,
  };
}

export class SupabaseRepository implements GymRepository {
  kind: RepositoryKind = 'supabase';
  backendConfigured = true;

  private client = requireSupabase();

  async getExercises(): Promise<Exercise[]> {
    const { data, error } = await this.client.from('exercise_library').select('*').order('name');
    if (error || !data || data.length === 0) return FALLBACK_EXERCISES;
    return (data as Row[]).map(mapExercise);
  }

  async getCurrentUser(): Promise<AppUser | null> {
    const { data } = await this.client.auth.getSession();
    const user = data.session?.user;
    return user ? { id: user.id, email: user.email ?? null } : null;
  }

  onAuthStateChange(callback: (user: AppUser | null) => void): () => void {
    const { data } = this.client.auth.onAuthStateChange((_event, session) => {
      const user = session?.user;
      callback(user ? { id: user.id, email: user.email ?? null } : null);
    });
    return () => data.subscription.unsubscribe();
  }

  async signIn(email: string, password: string): Promise<void> {
    const { error } = await this.client.auth.signInWithPassword({ email: email.trim(), password });
    if (error) throw new Error(error.message);
  }

  async signUp(name: string, email: string, password: string): Promise<AuthResult> {
    const { data, error } = await this.client.auth.signUp({
      email: email.trim(),
      password,
      options: { data: { name: name.trim() } },
    });
    if (error) throw new Error(error.message);
    return { needsEmailConfirmation: !data.session };
  }

  async signOut(): Promise<void> {
    const { error } = await this.client.auth.signOut();
    if (error) throw new Error(error.message);
  }

  async resetPassword(email: string): Promise<void> {
    const redirectTo = Linking.createURL('/update-password');
    const { error } = await this.client.auth.resetPasswordForEmail(email.trim(), { redirectTo });
    if (error) throw new Error(error.message);
  }

  async updatePassword(password: string): Promise<void> {
    const { error } = await this.client.auth.updateUser({ password });
    if (error) throw new Error(error.message);
  }

  async deleteAccount(): Promise<void> {
    const { error } = await this.client.functions.invoke('delete-account');
    if (error) throw new Error(error.message);
    await this.client.auth.signOut();
  }

  async getProfile(userId: string): Promise<Profile | null> {
    const { data, error } = await this.client.from('profiles').select('*').eq('id', userId).maybeSingle();
    if (error) throw new Error(error.message);
    return data ? mapProfile(data as Row) : null;
  }

  async saveProfile(profile: Profile): Promise<void> {
    const { error } = await this.client.from('profiles').upsert({
      id: profile.id,
      name: profile.name,
      age: profile.age,
      experience: profile.experience,
      environment: profile.environment,
      goals: profile.goals,
      limitations: profile.limitations,
      onboarding_completed: profile.onboardingCompleted,
    });
    if (error) throw new Error(error.message);
  }

  async getPreferences(userId: string): Promise<Preferences | null> {
    const { data, error } = await this.client
      .from('user_preferences')
      .select('*')
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data ? mapPreferences(data as Row) : null;
  }

  async savePreferences(preferences: Preferences): Promise<void> {
    const { error } = await this.client.from('user_preferences').upsert({
      user_id: preferences.userId,
      workout_days: preferences.workoutDays,
      session_minutes: preferences.sessionMinutes,
      equipment: preferences.equipment,
      avoid_exercises: preferences.avoidExercises,
      reminder_time: preferences.reminderTime,
      units: preferences.units,
    });
    if (error) throw new Error(error.message);
  }

  async getActivePlan(userId: string): Promise<WorkoutPlan | null> {
    const { data, error } = await this.client
      .from('workout_plans')
      .select('*, days:workout_days(*, exercises:workout_exercises(*))')
      .eq('user_id', userId)
      .eq('status', 'active')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data ? mapPlan(data as Row) : null;
  }

  async savePlan(plan: WorkoutPlan): Promise<void> {
    await this.client
      .from('workout_plans')
      .update({ status: 'archived' })
      .eq('user_id', plan.userId)
      .eq('status', 'active');

    const { error: planError } = await this.client.from('workout_plans').insert({
      id: plan.id,
      user_id: plan.userId,
      name: plan.name,
      goal: plan.goal,
      experience: plan.experience,
      days_per_week: plan.daysPerWeek,
      session_minutes: plan.sessionMinutes,
      equipment: plan.equipment,
      generated_by: plan.source === 'ai' ? 'ai' : 'on-device',
      status: 'active',
    });
    if (planError) throw new Error(planError.message);

    const dayRows = plan.days.map((day) => ({
      id: day.id,
      plan_id: plan.id,
      user_id: plan.userId,
      day_index: day.dayIndex,
      weekday: day.weekday,
      title: day.title,
      focus: day.focus,
      estimated_minutes: day.estimatedMinutes,
      warmup: day.warmup,
      cooldown: day.cooldown,
      is_rest_day: day.isRestDay,
      rest_note: day.restNote,
    }));

    const { error: daysError } = await this.client.from('workout_days').insert(dayRows);
    if (daysError) {
      await this.client.from('workout_plans').delete().eq('id', plan.id);
      throw new Error(daysError.message);
    }

    const exerciseRows = plan.days.flatMap((day) =>
      day.exercises.map((exercise) => ({
        id: exercise.id,
        day_id: day.id,
        plan_id: plan.id,
        user_id: plan.userId,
        exercise_id: exercise.exerciseId,
        position: exercise.position,
        sets: exercise.sets,
        reps_min: exercise.repsMin,
        reps_max: exercise.repsMax,
        rest_seconds: exercise.restSeconds,
        notes: exercise.notes,
      })),
    );

    if (exerciseRows.length > 0) {
      const { error: exercisesError } = await this.client.from('workout_exercises').insert(exerciseRows);
      if (exercisesError) {
        await this.client.from('workout_plans').delete().eq('id', plan.id);
        throw new Error(exercisesError.message);
      }
    }
  }

  async getSessions(userId: string): Promise<WorkoutSession[]> {
    const { data, error } = await this.client
      .from('workout_sessions')
      .select('*, sets:completed_sets(*)')
      .eq('user_id', userId)
      .order('started_at', { ascending: false })
      .limit(200);
    if (error) throw new Error(error.message);
    return (data as Row[]).map(mapSession);
  }

  async getSession(sessionId: string): Promise<WorkoutSession | null> {
    const { data, error } = await this.client
      .from('workout_sessions')
      .select('*, sets:completed_sets(*)')
      .eq('id', sessionId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data ? mapSession(data as Row) : null;
  }

  async saveSession(session: WorkoutSession): Promise<void> {
    const { error } = await this.client.from('workout_sessions').upsert({
      id: session.id,
      user_id: session.userId,
      plan_day_id: session.planDayId,
      title: session.title,
      focus: session.focus,
      started_at: session.startedAt,
      ended_at: session.endedAt,
      duration_seconds: session.durationSeconds,
      status: session.status,
      notes: session.notes,
    });
    if (error) throw new Error(error.message);

    await this.client.from('completed_sets').delete().eq('session_id', session.id);
    if (session.sets.length > 0) {
      const { error: setsError } = await this.client.from('completed_sets').insert(
        session.sets.map((set) => ({
          id: set.id,
          session_id: session.id,
          user_id: session.userId,
          workout_exercise_id: set.workoutExerciseId,
          exercise_id: set.exerciseId,
          set_number: set.setNumber,
          reps: set.reps,
          weight_kg: set.weightKg,
          completed_at: set.completedAt,
        })),
      );
      if (setsError) throw new Error(setsError.message);
    }
  }

  async getReminderSettings(userId: string): Promise<ReminderSettings | null> {
    const { data, error } = await this.client
      .from('reminder_settings')
      .select('*')
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data ? mapReminder(data as Row) : null;
  }

  async saveReminderSettings(settings: ReminderSettings): Promise<void> {
    const { error } = await this.client.from('reminder_settings').upsert({
      user_id: settings.userId,
      enabled: settings.enabled,
      workout_time: settings.workoutTime,
      days: settings.days,
      rest_day_reminders: settings.restDayReminders,
      hydration_reminders: settings.hydrationReminders,
      weekly_progress_reminder: settings.weeklyProgressReminder,
      scheduled_ids: settings.scheduledIds,
    });
    if (error) throw new Error(error.message);
  }

  async listConversations(userId: string): Promise<CoachConversation[]> {
    const { data, error } = await this.client
      .from('coach_conversations')
      .select('*')
      .eq('user_id', userId)
      .order('updated_at', { ascending: false });
    if (error) throw new Error(error.message);
    return (data as Row[]).map(mapConversation);
  }

  async createConversation(conversation: CoachConversation): Promise<void> {
    const { error } = await this.client.from('coach_conversations').insert({
      id: conversation.id,
      user_id: conversation.userId,
      title: conversation.title,
      created_at: conversation.createdAt,
      updated_at: conversation.updatedAt,
    });
    if (error) throw new Error(error.message);
  }

  async updateConversation(conversation: CoachConversation): Promise<void> {
    const { error } = await this.client
      .from('coach_conversations')
      .update({ title: conversation.title, updated_at: conversation.updatedAt })
      .eq('id', conversation.id);
    if (error) throw new Error(error.message);
  }

  async deleteConversation(conversationId: string): Promise<void> {
    const { error } = await this.client.from('coach_conversations').delete().eq('id', conversationId);
    if (error) throw new Error(error.message);
  }

  async listMessages(conversationId: string): Promise<CoachMessage[]> {
    const { data, error } = await this.client
      .from('coach_messages')
      .select('*')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: true });
    if (error) throw new Error(error.message);
    return (data as Row[]).map(mapMessage);
  }

  async addMessage(message: CoachMessage): Promise<void> {
    const { error } = await this.client.from('coach_messages').insert({
      id: message.id,
      conversation_id: message.conversationId,
      user_id: message.userId,
      role: message.role,
      content: message.content,
      created_at: message.createdAt,
    });
    if (error) throw new Error(error.message);
  }

  async listProgressRecords(userId: string): Promise<ProgressRecord[]> {
    const { data, error } = await this.client
      .from('progress_records')
      .select('*')
      .eq('user_id', userId)
      .order('recorded_at', { ascending: false });
    if (error) throw new Error(error.message);
    return (data as Row[]).map(mapProgress);
  }

  async addProgressRecord(record: ProgressRecord): Promise<void> {
    const { error } = await this.client.from('progress_records').insert({
      id: record.id,
      user_id: record.userId,
      recorded_at: record.recordedAt,
      bodyweight_kg: record.bodyweightKg,
      notes: record.notes,
    });
    if (error) throw new Error(error.message);
  }
}
