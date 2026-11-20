import type {
  AppUser,
  CoachConversation,
  CoachMessage,
  Exercise,
  Preferences,
  Profile,
  ProgressRecord,
  ReminderSettings,
  WorkoutPlan,
  WorkoutSession,
} from './types';

export type RepositoryKind = 'supabase' | 'preview' | 'ceebase';

export type AuthResult = { needsEmailConfirmation: boolean };

export interface GymRepository {
  kind: RepositoryKind;
  backendConfigured: boolean;
  getExercises(): Promise<Exercise[]>;
  getCurrentUser(): Promise<AppUser | null>;
  onAuthStateChange(callback: (user: AppUser | null) => void): () => void;
  signIn(email: string, password: string): Promise<void>;
  signUp(name: string, email: string, password: string): Promise<AuthResult>;
  signOut(): Promise<void>;
  resetPassword(email: string): Promise<void>;
  updatePassword(password: string): Promise<void>;
  deleteAccount(): Promise<void>;

  getProfile(userId: string): Promise<Profile | null>;
  saveProfile(profile: Profile): Promise<void>;
  getPreferences(userId: string): Promise<Preferences | null>;
  savePreferences(preferences: Preferences): Promise<void>;

  getActivePlan(userId: string): Promise<WorkoutPlan | null>;
  savePlan(plan: WorkoutPlan): Promise<void>;

  getSessions(userId: string): Promise<WorkoutSession[]>;
  getSession(sessionId: string): Promise<WorkoutSession | null>;
  saveSession(session: WorkoutSession): Promise<void>;

  getReminderSettings(userId: string): Promise<ReminderSettings | null>;
  saveReminderSettings(settings: ReminderSettings): Promise<void>;

  listConversations(userId: string): Promise<CoachConversation[]>;
  createConversation(conversation: CoachConversation): Promise<void>;
  updateConversation(conversation: CoachConversation): Promise<void>;
  deleteConversation(conversationId: string): Promise<void>;
  listMessages(conversationId: string): Promise<CoachMessage[]>;
  addMessage(message: CoachMessage): Promise<void>;

  listProgressRecords(userId: string): Promise<ProgressRecord[]>;
  addProgressRecord(record: ProgressRecord): Promise<void>;
}
