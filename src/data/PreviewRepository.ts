import AsyncStorage from '@react-native-async-storage/async-storage';

import exercisesJson from './exercises.json';
import type { GymRepository, RepositoryKind } from './repository';
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
import { PREVIEW_USER_ID } from '@/lib/env';

type PreviewDb = {
  profile: Profile | null;
  preferences: Preferences | null;
  plan: WorkoutPlan | null;
  sessions: WorkoutSession[];
  reminderSettings: ReminderSettings | null;
  conversations: CoachConversation[];
  messages: CoachMessage[];
  progressRecords: ProgressRecord[];
};

const STORAGE_KEY = 'forma.preview.db.v1';
const EXERCISES = exercisesJson as Exercise[];

function emptyDb(): PreviewDb {
  return {
    profile: null,
    preferences: null,
    plan: null,
    sessions: [],
    reminderSettings: null,
    conversations: [],
    messages: [],
    progressRecords: [],
  };
}

const previewUser: AppUser = { id: PREVIEW_USER_ID, email: null };

/**
 * Development-only repository. Data lives on this device in AsyncStorage.
 * It never claims to be a backend, and the UI labels it as a preview.
 */
export class PreviewRepository implements GymRepository {
  kind: RepositoryKind = 'preview';
  backendConfigured = false;
  private db: PreviewDb | null = null;

  private async load(): Promise<PreviewDb> {
    if (this.db) return this.db;
    try {
      const raw = await AsyncStorage.getItem(STORAGE_KEY);
      this.db = raw ? { ...emptyDb(), ...(JSON.parse(raw) as Partial<PreviewDb>) } : emptyDb();
    } catch {
      this.db = emptyDb();
    }
    return this.db;
  }

  private async persist(): Promise<void> {
    if (!this.db) return;
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(this.db));
  }

  async getExercises(): Promise<Exercise[]> {
    return EXERCISES;
  }

  async getCurrentUser(): Promise<AppUser | null> {
    return previewUser;
  }

  onAuthStateChange(callback: (user: AppUser | null) => void): () => void {
    callback(previewUser);
    return () => {};
  }

  async signIn(): Promise<void> {
    throw new Error('Preview mode has no accounts. Sign-in is available after Supabase is configured.');
  }

  async signUp(): Promise<never> {
    throw new Error('Preview mode has no accounts. Sign-up is available after Supabase is configured.');
  }

  async signOut(): Promise<void> {
    throw new Error('Preview mode has no account to sign out of.');
  }

  async resetPassword(): Promise<never> {
    throw new Error('Preview mode has no accounts. Password reset is available after Supabase is configured.');
  }

  async updatePassword(): Promise<never> {
    throw new Error('Preview mode has no accounts. Password updates are available after Supabase is configured.');
  }

  async deleteAccount(): Promise<void> {
    this.db = emptyDb();
    await AsyncStorage.removeItem(STORAGE_KEY);
  }

  async getProfile(): Promise<Profile | null> {
    return (await this.load()).profile;
  }

  async saveProfile(profile: Profile): Promise<void> {
    const db = await this.load();
    db.profile = profile;
    await this.persist();
  }

  async getPreferences(): Promise<Preferences | null> {
    return (await this.load()).preferences;
  }

  async savePreferences(preferences: Preferences): Promise<void> {
    const db = await this.load();
    db.preferences = preferences;
    await this.persist();
  }

  async getActivePlan(): Promise<WorkoutPlan | null> {
    return (await this.load()).plan;
  }

  async savePlan(plan: WorkoutPlan): Promise<void> {
    const db = await this.load();
    db.plan = plan;
    await this.persist();
  }

  async getSessions(): Promise<WorkoutSession[]> {
    const db = await this.load();
    return [...db.sessions].sort((a, b) => (a.startedAt < b.startedAt ? 1 : -1));
  }

  async getSession(sessionId: string): Promise<WorkoutSession | null> {
    const db = await this.load();
    return db.sessions.find((session) => session.id === sessionId) ?? null;
  }

  async saveSession(session: WorkoutSession): Promise<void> {
    const db = await this.load();
    const index = db.sessions.findIndex((item) => item.id === session.id);
    if (index >= 0) db.sessions[index] = session;
    else db.sessions.unshift(session);
    await this.persist();
  }

  async getReminderSettings(): Promise<ReminderSettings | null> {
    return (await this.load()).reminderSettings;
  }

  async saveReminderSettings(settings: ReminderSettings): Promise<void> {
    const db = await this.load();
    db.reminderSettings = settings;
    await this.persist();
  }

  async listConversations(): Promise<CoachConversation[]> {
    const db = await this.load();
    return [...db.conversations].sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1));
  }

  async createConversation(conversation: CoachConversation): Promise<void> {
    const db = await this.load();
    db.conversations.unshift(conversation);
    await this.persist();
  }

  async updateConversation(conversation: CoachConversation): Promise<void> {
    const db = await this.load();
    const index = db.conversations.findIndex((item) => item.id === conversation.id);
    if (index >= 0) db.conversations[index] = conversation;
    await this.persist();
  }

  async deleteConversation(conversationId: string): Promise<void> {
    const db = await this.load();
    db.conversations = db.conversations.filter((item) => item.id !== conversationId);
    db.messages = db.messages.filter((item) => item.conversationId !== conversationId);
    await this.persist();
  }

  async listMessages(conversationId: string): Promise<CoachMessage[]> {
    const db = await this.load();
    return db.messages
      .filter((message) => message.conversationId === conversationId)
      .sort((a, b) => (a.createdAt < b.createdAt ? -1 : 1));
  }

  async addMessage(message: CoachMessage): Promise<void> {
    const db = await this.load();
    db.messages.push(message);
    await this.persist();
  }

  async listProgressRecords(): Promise<ProgressRecord[]> {
    const db = await this.load();
    return [...db.progressRecords].sort((a, b) => (a.recordedAt < b.recordedAt ? 1 : -1));
  }

  async addProgressRecord(record: ProgressRecord): Promise<void> {
    const db = await this.load();
    db.progressRecords.unshift(record);
    await this.persist();
  }
}
