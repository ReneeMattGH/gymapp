import AsyncStorage from '@react-native-async-storage/async-storage';
import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';

import { isPreviewMode, repository, setupRequired as setupRequiredFlag } from '@/data';
import type { AuthResult } from '@/data/repository';
import type {
  AppUser,
  Exercise,
  Preferences,
  Profile,
  ProgressRecord,
  ReminderSettings,
  WorkoutPlan,
  WorkoutSession,
} from '@/data/types';
import { EXERCISE_LIBRARY } from '@/lib/plan';

type AppContextValue = {
  ready: boolean;
  dataLoading: boolean;
  dataError: string | null;
  user: AppUser | null;
  profile: Profile | null;
  preferences: Preferences | null;
  plan: WorkoutPlan | null;
  sessions: WorkoutSession[];
  exercises: Exercise[];
  reminders: ReminderSettings | null;
  progressRecords: ProgressRecord[];
  setupRequired: boolean;
  previewMode: boolean;

  refreshAll: () => Promise<void>;
  refreshPlan: () => Promise<void>;
  refreshSessions: () => Promise<void>;
  refreshReminders: () => Promise<void>;
  refreshProgress: () => Promise<void>;
  saveProfile: (profile: Profile) => Promise<void>;
  savePreferences: (preferences: Preferences) => Promise<void>;
  savePlan: (plan: WorkoutPlan) => Promise<void>;
  saveSession: (session: WorkoutSession) => Promise<void>;
  saveReminders: (settings: ReminderSettings) => Promise<void>;
  addProgressRecord: (record: ProgressRecord) => Promise<void>;

  signIn: (email: string, password: string) => Promise<void>;
  signUp: (name: string, email: string, password: string) => Promise<AuthResult>;
  signOut: () => Promise<void>;
  resetPassword: (email: string) => Promise<void>;
  updatePassword: (password: string) => Promise<void>;
  deleteAccount: () => Promise<void>;
};

const AppContext = createContext<AppContextValue | null>(null);

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : 'Something went wrong. Please try again.';
}

export function AppProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(setupRequiredFlag);
  const [dataLoading, setDataLoading] = useState(false);
  const [dataError, setDataError] = useState<string | null>(null);
  const [user, setUser] = useState<AppUser | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [preferences, setPreferences] = useState<Preferences | null>(null);
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [exercises, setExercises] = useState<Exercise[]>(EXERCISE_LIBRARY);
  const [reminders, setReminders] = useState<ReminderSettings | null>(null);
  const [progressRecords, setProgressRecords] = useState<ProgressRecord[]>([]);

  const activeUserId = useRef<string | null>(null);

  const clearData = useCallback(() => {
    setProfile(null);
    setPreferences(null);
    setPlan(null);
    setSessions([]);
    setReminders(null);
    setProgressRecords([]);
  }, []);

  const loadAll = useCallback(async (userId: string) => {
    setDataLoading(true);
    setDataError(null);
    try {
      const [nextProfile, nextPreferences, nextPlan, nextSessions, nextReminders, nextProgress, library] =
        await Promise.all([
          repository.getProfile(userId),
          repository.getPreferences(userId),
          repository.getActivePlan(userId),
          repository.getSessions(userId),
          repository.getReminderSettings(userId),
          repository.listProgressRecords(userId),
          repository.getExercises(),
        ]);
      setProfile(nextProfile);
      setPreferences(nextPreferences);
      setPlan(nextPlan);
      setSessions(nextSessions);
      setReminders(nextReminders);
      setProgressRecords(nextProgress);
      if (library.length > 0) setExercises(library);
    } catch (error) {
      setDataError(messageOf(error));
    } finally {
      setDataLoading(false);
      setReady(true);
    }
  }, []);

  const applyUser = useCallback(
    async (next: AppUser | null, force = false) => {
      if (!force && next?.id === activeUserId.current) return;
      activeUserId.current = next?.id ?? null;
      setUser(next);
      if (next) {
        await loadAll(next.id);
      } else {
        clearData();
        setReady(true);
      }
    },
    [clearData, loadAll],
  );

  useEffect(() => {
    let mounted = true;

    const boot = async () => {
      if (setupRequiredFlag) {
        setReady(true);
        return;
      }
      try {
        const current = await repository.getCurrentUser();
        if (!mounted) return;
        await applyUser(current, true);
      } catch (error) {
        if (!mounted) return;
        setDataError(messageOf(error));
        setReady(true);
      }
    };

    void boot();

    const unsubscribe =
      repository.kind !== 'preview'
        ? repository.onAuthStateChange((next) => {
            if (!mounted) return;
            void applyUser(next);
          })
        : () => {};

    return () => {
      mounted = false;
      unsubscribe();
    };
  }, [applyUser]);

  const refreshAll = useCallback(async () => {
    if (user) await loadAll(user.id);
  }, [loadAll, user]);

  const refreshPlan = useCallback(async () => {
    if (!user) return;
    setPlan(await repository.getActivePlan(user.id));
  }, [user]);

  const refreshSessions = useCallback(async () => {
    if (!user) return;
    setSessions(await repository.getSessions(user.id));
  }, [user]);

  const refreshReminders = useCallback(async () => {
    if (!user) return;
    setReminders(await repository.getReminderSettings(user.id));
  }, [user]);

  const refreshProgress = useCallback(async () => {
    if (!user) return;
    setProgressRecords(await repository.listProgressRecords(user.id));
  }, [user]);

  const saveProfile = useCallback(async (next: Profile) => {
    await repository.saveProfile(next);
    setProfile(next);
  }, []);

  const savePreferences = useCallback(async (next: Preferences) => {
    await repository.savePreferences(next);
    setPreferences(next);
  }, []);

  const savePlan = useCallback(async (next: WorkoutPlan) => {
    await repository.savePlan(next);
    setPlan(next);
  }, []);

  const saveSession = useCallback(
    async (session: WorkoutSession) => {
      await repository.saveSession(session);
      if (user) setSessions(await repository.getSessions(user.id));
    },
    [user],
  );

  const saveReminders = useCallback(async (settings: ReminderSettings) => {
    await repository.saveReminderSettings(settings);
    setReminders(settings);
  }, []);

  const addProgressRecord = useCallback(
    async (record: ProgressRecord) => {
      await repository.addProgressRecord(record);
      if (user) setProgressRecords(await repository.listProgressRecords(user.id));
    },
    [user],
  );

  const signIn = useCallback(
    async (email: string, password: string) => {
      await repository.signIn(email, password);
      const current = await repository.getCurrentUser();
      if (current) await applyUser(current, true);
    },
    [applyUser],
  );

  const signUp = useCallback(
    async (name: string, email: string, password: string) => repository.signUp(name, email, password),
    [],
  );

  const signOut = useCallback(async () => {
    await repository.signOut();
    activeUserId.current = null;
    setUser(null);
    clearData();
  }, [clearData]);

  const resetPassword = useCallback(async (email: string) => {
    await repository.resetPassword(email);
  }, []);

  const updatePassword = useCallback(async (password: string) => {
    await repository.updatePassword(password);
  }, []);

  const deleteAccount = useCallback(async () => {
    if (user) await AsyncStorage.removeItem(`forma.activeWorkout.${user.id}`);
    await repository.deleteAccount();
    activeUserId.current = null;
    setUser(null);
    clearData();
  }, [clearData, user]);

  const value = useMemo<AppContextValue>(
    () => ({
      ready,
      dataLoading,
      dataError,
      user,
      profile,
      preferences,
      plan,
      sessions,
      exercises,
      reminders,
      progressRecords,
      setupRequired: setupRequiredFlag,
      previewMode: isPreviewMode,
      refreshAll,
      refreshPlan,
      refreshSessions,
      refreshReminders,
      refreshProgress,
      saveProfile,
      savePreferences,
      savePlan,
      saveSession,
      saveReminders,
      addProgressRecord,
      signIn,
      signUp,
      signOut,
      resetPassword,
      updatePassword,
      deleteAccount,
    }),
    [
      ready,
      dataLoading,
      dataError,
      user,
      profile,
      preferences,
      plan,
      sessions,
      exercises,
      reminders,
      progressRecords,
      refreshAll,
      refreshPlan,
      refreshSessions,
      refreshReminders,
      refreshProgress,
      saveProfile,
      savePreferences,
      savePlan,
      saveSession,
      saveReminders,
      addProgressRecord,
      signIn,
      signUp,
      signOut,
      resetPassword,
      updatePassword,
      deleteAccount,
    ],
  );

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useApp() {
  const context = useContext(AppContext);
  if (!context) throw new Error('useApp must be used inside AppProvider');
  return context;
}
