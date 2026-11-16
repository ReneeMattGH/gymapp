import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';
import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { Platform } from 'react-native';

import type {
  ActiveWorkout,
  CompletedSet,
  WorkoutDay,
  WorkoutExercise,
  WorkoutPlan,
  WorkoutSession,
} from '@/data/types';
import { newId } from '@/lib/id';
import { useApp } from '@/state/AppProvider';

type WorkoutContextValue = {
  active: ActiveWorkout | null;
  restored: boolean;
  elapsedSeconds: number;
  restRemaining: number;
  restRunning: boolean;
  currentExercise: WorkoutExercise | null;
  completedForCurrent: number;
  startWorkout: (day: WorkoutDay, plan: WorkoutPlan) => Promise<ActiveWorkout>;
  addSet: (params: { reps: number; weightKg: number | null; exerciseId: string }) => Promise<void>;
  goToExercise: (index: number) => void;
  nextExercise: () => void;
  substituteCurrent: (exerciseId: string, sets: number, repsMin: number, repsMax: number, restSeconds: number) => void;
  skipCurrent: () => void;
  pauseWorkout: () => void;
  resumeWorkout: () => void;
  startRest: (seconds: number, exerciseId: string) => void;
  pauseRest: () => void;
  resumeRest: () => void;
  addRestTime: (seconds: number) => void;
  skipRest: () => void;
  finishWorkout: (notes: string | null) => Promise<WorkoutSession>;
  discardWorkout: () => Promise<void>;
};

const WorkoutContext = createContext<WorkoutContextValue | null>(null);

function storageKey(userId: string) {
  return `forma.activeWorkout.${userId}`;
}

function elapsedOf(workout: ActiveWorkout, now: number): number {
  const start = new Date(workout.startedAt).getTime();
  const reference = workout.pausedAt ? new Date(workout.pausedAt).getTime() : now;
  return Math.max(0, Math.floor((reference - start) / 1000) - workout.pausedSeconds);
}

export function WorkoutProvider({ children }: { children: React.ReactNode }) {
  const { user, saveSession } = useApp();
  const [active, setActive] = useState<ActiveWorkout | null>(null);
  const [restoredFor, setRestoredFor] = useState<string | null>(null);
  const [now, setNow] = useState(0);
  const vibratedFor = useRef<string | null>(null);
  const restored = Boolean(user && restoredFor === user.id);

  useEffect(() => {
    let mounted = true;
    const restore = async () => {
      let next: ActiveWorkout | null = null;
      if (user) {
        try {
          const raw = await AsyncStorage.getItem(storageKey(user.id));
          if (raw) {
            const parsed = JSON.parse(raw) as ActiveWorkout;
            if (parsed.userId === user.id && Array.isArray(parsed.exercises)) next = parsed;
          }
        } catch {
          // A corrupt snapshot should never block starting a new workout.
        }
      }
      if (!mounted) return;
      setActive(next);
      setRestoredFor(user?.id ?? null);
    };
    void restore();
    return () => {
      mounted = false;
    };
  }, [user]);

  useEffect(() => {
    if (!restored || !user) return;
    const key = storageKey(user.id);
    if (active) {
      AsyncStorage.setItem(key, JSON.stringify(active)).catch(() => {});
    } else {
      AsyncStorage.removeItem(key).catch(() => {});
    }
  }, [active, restored, user]);

  const activeSessionId = active?.sessionId ?? null;
  const activeStatus = active?.status ?? null;

  useEffect(() => {
    if (!activeSessionId) return;
    const tick = () => setNow(Date.now());
    const initial = setTimeout(tick, 0);
    const interval = setInterval(tick, 1000);
    return () => {
      clearTimeout(initial);
      clearInterval(interval);
    };
  }, [activeSessionId, activeStatus]);

  let restRemaining = 0;
  if (active?.rest) {
    if (active.rest.pausedRemaining !== null) {
      restRemaining = Math.max(0, active.rest.pausedRemaining);
    } else if (active.rest.endsAt) {
      restRemaining = Math.max(0, Math.ceil((new Date(active.rest.endsAt).getTime() - now) / 1000));
    }
  }

  const restRunning = Boolean(
    active?.rest && active.rest.pausedRemaining === null && restRemaining > 0,
  );

  useEffect(() => {
    if (!active?.rest || restRemaining > 0) return;
    if (Platform.OS === 'web') return;
    const marker = active.rest.endsAt ?? `paused-${active.rest.durationSeconds}`;
    if (vibratedFor.current === marker) return;
    vibratedFor.current = marker;
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
  }, [active?.rest, restRemaining]);

  const currentExercise = active ? active.exercises[active.currentExerciseIndex] ?? null : null;
  const completedForCurrent = active && currentExercise
    ? active.sets.filter((set) => set.workoutExerciseId === currentExercise.id).length
    : 0;

  const startWorkout = useCallback(
    async (day: WorkoutDay, plan: WorkoutPlan): Promise<ActiveWorkout> => {
      if (!user) throw new Error('Sign in before starting a workout.');
      if (active) return active;
      const workout: ActiveWorkout = {
        sessionId: newId('session'),
        userId: user.id,
        planDayId: day.id,
        planId: plan.id,
        title: day.title,
        focus: day.focus,
        warmup: day.warmup,
        cooldown: day.cooldown,
        startedAt: new Date().toISOString(),
        status: 'active',
        pausedAt: null,
        pausedSeconds: 0,
        currentExerciseIndex: 0,
        exercises: day.exercises.map((exercise) => ({ ...exercise })),
        sets: [],
        rest: null,
      };
      setActive(workout);
      return workout;
    },
    [active, user],
  );

  const addSet = useCallback(
    async ({ reps, weightKg, exerciseId }: { reps: number; weightKg: number | null; exerciseId: string }) => {
      const id = newId('set');
      const completedAt = new Date().toISOString();
      setActive((previous) => {
        if (!previous) return previous;
        const current = previous.exercises[previous.currentExerciseIndex];
        const workoutExerciseId = current && current.exerciseId === exerciseId ? current.id : null;
        const existing = previous.sets.filter((set) => set.workoutExerciseId === workoutExerciseId).length;
        const nextSet: CompletedSet = {
          id,
          sessionId: previous.sessionId,
          workoutExerciseId,
          exerciseId,
          setNumber: existing + 1,
          reps,
          weightKg,
          completedAt,
        };
        return { ...previous, sets: [...previous.sets, nextSet] };
      });
      if (Platform.OS !== 'web') {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => {});
      }
    },
    [],
  );

  const goToExercise = useCallback((index: number) => {
    setActive((previous) => {
      if (!previous) return previous;
      const clamped = Math.max(0, Math.min(previous.exercises.length - 1, index));
      return { ...previous, currentExerciseIndex: clamped, rest: null };
    });
  }, []);

  const nextExercise = useCallback(() => {
    setActive((previous) => {
      if (!previous) return previous;
      const nextIndex = Math.min(previous.exercises.length - 1, previous.currentExerciseIndex + 1);
      return { ...previous, currentExerciseIndex: nextIndex, rest: null };
    });
  }, []);

  const substituteCurrent = useCallback(
    (exerciseId: string, sets: number, repsMin: number, repsMax: number, restSeconds: number) => {
      const id = newId('we');
      setActive((previous) => {
        if (!previous) return previous;
        const current = previous.exercises[previous.currentExerciseIndex];
        if (!current) return previous;
        const replacement: WorkoutExercise = {
          ...current,
          id,
          exerciseId,
          sets,
          repsMin,
          repsMax,
          restSeconds,
          notes: 'Substituted during the session.',
        };
        const exercises = previous.exercises.map((exercise, index) =>
          index === previous.currentExerciseIndex ? replacement : exercise,
        );
        return { ...previous, exercises, rest: null };
      });
    },
    [],
  );

  const skipCurrent = useCallback(() => {
    setActive((previous) => {
      if (!previous) return previous;
      const nextIndex = Math.min(previous.exercises.length - 1, previous.currentExerciseIndex + 1);
      return { ...previous, currentExerciseIndex: nextIndex, rest: null };
    });
  }, []);

  const pauseWorkout = useCallback(() => {
    const timestamp = new Date().toISOString();
    setActive((previous) => {
      if (!previous || previous.status === 'paused') return previous;
      const rest = previous.rest
        ? {
            ...previous.rest,
            pausedRemaining:
              previous.rest.pausedRemaining ??
              Math.max(
                0,
                Math.ceil((new Date(previous.rest.endsAt ?? timestamp).getTime() - Date.now()) / 1000),
              ),
            endsAt: null,
          }
        : null;
      return { ...previous, status: 'paused', pausedAt: timestamp, rest };
    });
  }, []);

  const resumeWorkout = useCallback(() => {
    setActive((previous) => {
      if (!previous || previous.status !== 'paused') return previous;
      const pausedSeconds =
        previous.pausedSeconds +
        Math.max(
          0,
          Math.round((Date.now() - new Date(previous.pausedAt ?? new Date().toISOString()).getTime()) / 1000),
        );
      const rest =
        previous.rest && previous.rest.pausedRemaining !== null && previous.rest.pausedRemaining > 0
          ? {
              ...previous.rest,
              endsAt: new Date(Date.now() + previous.rest.pausedRemaining * 1000).toISOString(),
              pausedRemaining: null,
            }
          : previous.rest;
      return { ...previous, status: 'active', pausedAt: null, pausedSeconds, rest };
    });
  }, []);

  const startRest = useCallback((seconds: number, exerciseId: string) => {
    const safe = Math.max(5, Math.round(seconds));
    setActive((previous) => {
      if (!previous) return previous;
      return {
        ...previous,
        rest: {
          endsAt: new Date(Date.now() + safe * 1000).toISOString(),
          durationSeconds: safe,
          pausedRemaining: null,
          exerciseId,
        },
      };
    });
  }, []);

  const pauseRest = useCallback(() => {
    const remainingFrom = (endsAt: string | null) =>
      endsAt ? Math.max(0, Math.ceil((new Date(endsAt).getTime() - Date.now()) / 1000)) : 0;
    setActive((previous) => {
      if (!previous?.rest || previous.rest.pausedRemaining !== null) return previous;
      return {
        ...previous,
        rest: {
          ...previous.rest,
          endsAt: null,
          pausedRemaining: remainingFrom(previous.rest.endsAt),
        },
      };
    });
  }, []);

  const resumeRest = useCallback(() => {
    setActive((previous) => {
      if (!previous?.rest || previous.rest.pausedRemaining === null) return previous;
      const remaining = Math.max(1, previous.rest.pausedRemaining);
      return {
        ...previous,
        rest: {
          ...previous.rest,
          endsAt: new Date(Date.now() + remaining * 1000).toISOString(),
          pausedRemaining: null,
        },
      };
    });
  }, []);

  const addRestTime = useCallback((seconds: number) => {
    setActive((previous) => {
      if (!previous?.rest) return previous;
      if (previous.rest.pausedRemaining !== null) {
        return {
          ...previous,
          rest: { ...previous.rest, pausedRemaining: previous.rest.pausedRemaining + seconds },
        };
      }
      const base = previous.rest.endsAt ? new Date(previous.rest.endsAt).getTime() : Date.now();
      return {
        ...previous,
        rest: {
          ...previous.rest,
          endsAt: new Date(Math.max(Date.now(), base) + seconds * 1000).toISOString(),
          durationSeconds: previous.rest.durationSeconds + seconds,
        },
      };
    });
  }, []);

  const skipRest = useCallback(() => {
    vibratedFor.current = null;
    setActive((previous) => (previous ? { ...previous, rest: null } : previous));
  }, []);

  const finishWorkout = useCallback(
    async (notes: string | null): Promise<WorkoutSession> => {
      if (!active) throw new Error('There is no active workout to finish.');
      const endedAt = new Date().toISOString();
      const durationSeconds = elapsedOf(active, Date.now());
      const session: WorkoutSession = {
        id: active.sessionId,
        userId: active.userId,
        planDayId: active.planDayId,
        title: active.title,
        focus: active.focus,
        startedAt: active.startedAt,
        endedAt,
        durationSeconds,
        status: active.sets.length > 0 ? 'completed' : 'abandoned',
        sets: active.sets,
        notes,
      };
      await saveSession(session);
      setActive(null);
      vibratedFor.current = null;
      return session;
    },
    [active, saveSession],
  );

  const discardWorkout = useCallback(async () => {
    setActive(null);
    vibratedFor.current = null;
  }, []);

  const value = useMemo<WorkoutContextValue>(
    () => ({
      active,
      restored,
      elapsedSeconds: active ? elapsedOf(active, now) : 0,
      restRemaining,
      restRunning,
      currentExercise,
      completedForCurrent,
      startWorkout,
      addSet,
      goToExercise,
      nextExercise,
      substituteCurrent,
      skipCurrent,
      pauseWorkout,
      resumeWorkout,
      startRest,
      pauseRest,
      resumeRest,
      addRestTime,
      skipRest,
      finishWorkout,
      discardWorkout,
    }),
    [
      active,
      restored,
      now,
      restRemaining,
      restRunning,
      currentExercise,
      completedForCurrent,
      startWorkout,
      addSet,
      goToExercise,
      nextExercise,
      substituteCurrent,
      skipCurrent,
      pauseWorkout,
      resumeWorkout,
      startRest,
      pauseRest,
      resumeRest,
      addRestTime,
      skipRest,
      finishWorkout,
      discardWorkout,
    ],
  );

  return <WorkoutContext.Provider value={value}>{children}</WorkoutContext.Provider>;
}

export function useWorkout() {
  const context = useContext(WorkoutContext);
  if (!context) throw new Error('useWorkout must be used inside WorkoutProvider');
  return context;
}
