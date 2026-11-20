import AsyncStorage from '@react-native-async-storage/async-storage';

import exercisesJson from './exercises.json';
import type { AuthResult, GymRepository, RepositoryKind } from './repository';
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

const STORAGE_SESSION_KEY = '@forma.ceebase.session.v1';
const FALLBACK_EXERCISES = exercisesJson as Exercise[];

type QueryResponse = {
  success: boolean;
  columns: string[];
  rows: any[][];
  rowcount?: number;
  elapsed_ms?: number;
  error?: string | null;
};

function generatePkId(): number {
  return Date.now() * 1000 + Math.floor(Math.random() * 1000);
}

function safeJsonParse<T>(raw: string | null | undefined, fallback: T): T {
  if (!raw) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

/**
 * CeeBaseRepository connects Forma to the CeeBase custom C++ storage engine
 * via its high-performance Studio REST bridge (/api/v1/query).
 */
export class CeeBaseRepository implements GymRepository {
  kind: RepositoryKind = 'ceebase';
  backendConfigured = true;

  private baseUrl: string;
  private currentUser: AppUser | null = null;
  private authListeners: Set<(user: AppUser | null) => void> = new Set();
  private schemaInitialized: Promise<void> | null = null;

  constructor(baseUrl: string = 'http://127.0.0.1:8080') {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
  }

  private async query(sql: string, parameters: any[] = []): Promise<QueryResponse> {
    try {
      const response = await fetch(`${this.baseUrl}/api/v1/query`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sql, parameters }),
      });

      if (!response.ok) {
        throw new Error(`CeeBase HTTP error ${response.status}: ${response.statusText}`);
      }

      const res: QueryResponse = await response.json();
      if (!res.success) {
        throw new Error(res.error || 'CeeBase query execution failed');
      }
      return res;
    } catch (err: any) {
      if (err.message?.includes('Failed to fetch') || err.message?.includes('Network request failed')) {
        throw new Error(
          `Unable to connect to CeeBase database at ${this.baseUrl}. Make sure CeeBase Studio server is running.`,
        );
      }
      throw err;
    }
  }

  private async ensureSchema(): Promise<void> {
    if (!this.schemaInitialized) {
      this.schemaInitialized = (async () => {
        try {
          const res = await this.query('SHOW TABLES;');
          const existingTables = new Set(res.rows.map((r) => String(r[0]).toLowerCase()));

          if (!existingTables.has('cb_users')) {
            await this.query(`CREATE TABLE cb_users (
              pk_id INTEGER PRIMARY KEY,
              id TEXT,
              email TEXT,
              password TEXT,
              name TEXT,
              created_at TEXT
            );`);
          }

          if (!existingTables.has('cb_profiles')) {
            await this.query(`CREATE TABLE cb_profiles (
              pk_id INTEGER PRIMARY KEY,
              user_id TEXT,
              name TEXT,
              age INTEGER,
              experience TEXT,
              environment TEXT,
              goals TEXT,
              limitations TEXT,
              onboarding_completed BOOLEAN,
              created_at TEXT
            );`);
          }

          if (!existingTables.has('cb_preferences')) {
            await this.query(`CREATE TABLE cb_preferences (
              pk_id INTEGER PRIMARY KEY,
              user_id TEXT,
              workout_days TEXT,
              session_minutes INTEGER,
              equipment TEXT,
              avoid_exercises TEXT,
              reminder_time TEXT,
              units TEXT
            );`);
          }

          if (!existingTables.has('cb_plans')) {
            await this.query(`CREATE TABLE cb_plans (
              pk_id INTEGER PRIMARY KEY,
              id TEXT,
              user_id TEXT,
              name TEXT,
              goal TEXT,
              experience TEXT,
              days_per_week INTEGER,
              session_minutes INTEGER,
              equipment TEXT,
              source TEXT,
              created_at TEXT,
              plan_json TEXT
            );`);
          }

          if (!existingTables.has('cb_sessions')) {
            await this.query(`CREATE TABLE cb_sessions (
              pk_id INTEGER PRIMARY KEY,
              id TEXT,
              user_id TEXT,
              plan_day_id TEXT,
              title TEXT,
              focus TEXT,
              started_at TEXT,
              ended_at TEXT,
              duration_seconds INTEGER,
              status TEXT,
              notes TEXT,
              session_json TEXT
            );`);
          }

          if (!existingTables.has('cb_reminders')) {
            await this.query(`CREATE TABLE cb_reminders (
              pk_id INTEGER PRIMARY KEY,
              user_id TEXT,
              enabled BOOLEAN,
              workout_time TEXT,
              days TEXT,
              rest_day_reminders BOOLEAN,
              hydration_reminders BOOLEAN,
              weekly_progress_reminder BOOLEAN,
              scheduled_ids TEXT
            );`);
          }

          if (!existingTables.has('cb_conversations')) {
            await this.query(`CREATE TABLE cb_conversations (
              pk_id INTEGER PRIMARY KEY,
              id TEXT,
              user_id TEXT,
              title TEXT,
              created_at TEXT,
              updated_at TEXT
            );`);
          }

          if (!existingTables.has('cb_messages')) {
            await this.query(`CREATE TABLE cb_messages (
              pk_id INTEGER PRIMARY KEY,
              id TEXT,
              conversation_id TEXT,
              user_id TEXT,
              role TEXT,
              content TEXT,
              created_at TEXT
            );`);
          }

          if (!existingTables.has('cb_progress')) {
            await this.query(`CREATE TABLE cb_progress (
              pk_id INTEGER PRIMARY KEY,
              id TEXT,
              user_id TEXT,
              recorded_at TEXT,
              bodyweight_kg DOUBLE,
              notes TEXT
            );`);
          }
        } catch (e) {
          // Reset schemaInitialized so it retries on next call
          this.schemaInitialized = null;
          throw e;
        }
      })();
    }
    return this.schemaInitialized;
  }

  async getExercises(): Promise<Exercise[]> {
    return FALLBACK_EXERCISES;
  }

  // --- Authentication ---

  async getCurrentUser(): Promise<AppUser | null> {
    if (this.currentUser) return this.currentUser;
    try {
      const stored = await AsyncStorage.getItem(STORAGE_SESSION_KEY);
      if (stored) {
        this.currentUser = JSON.parse(stored) as AppUser;
        return this.currentUser;
      }
    } catch {
      // ignore storage read errors
    }
    return null;
  }

  onAuthStateChange(callback: (user: AppUser | null) => void): () => void {
    this.authListeners.add(callback);
    return () => {
      this.authListeners.delete(callback);
    };
  }

  private notifyAuth(user: AppUser | null) {
    this.currentUser = user;
    for (const listener of this.authListeners) {
      listener(user);
    }
  }

  async signIn(email: string, password: string): Promise<void> {
    await this.ensureSchema();
    const cleanEmail = email.trim().toLowerCase();
    const res = await this.query('SELECT id, email, password, name FROM cb_users WHERE email = ?;', [
      cleanEmail,
    ]);

    if (!res.rows || res.rows.length === 0) {
      throw new Error('No account found with this email address.');
    }

    const [id, dbEmail, dbPassword] = res.rows[0];
    if (dbPassword !== password) {
      throw new Error('Invalid email or password.');
    }

    const user: AppUser = { id: String(id), email: String(dbEmail) };
    await AsyncStorage.setItem(STORAGE_SESSION_KEY, JSON.stringify(user));
    this.notifyAuth(user);
  }

  async signUp(name: string, email: string, password: string): Promise<AuthResult> {
    await this.ensureSchema();
    const cleanEmail = email.trim().toLowerCase();
    const cleanName = name.trim();

    if (!cleanEmail || !password) {
      throw new Error('Email and password are required.');
    }

    const existing = await this.query('SELECT id FROM cb_users WHERE email = ?;', [cleanEmail]);
    if (existing.rows && existing.rows.length > 0) {
      throw new Error('An account with this email already exists.');
    }

    const userId = `user_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const pkId = generatePkId();
    const createdAt = new Date().toISOString();

    await this.query('INSERT INTO cb_users VALUES (?, ?, ?, ?, ?, ?);', [
      pkId,
      userId,
      cleanEmail,
      password,
      cleanName,
      createdAt,
    ]);

    const user: AppUser = { id: userId, email: cleanEmail };
    await AsyncStorage.setItem(STORAGE_SESSION_KEY, JSON.stringify(user));
    this.notifyAuth(user);

    return { needsEmailConfirmation: false };
  }

  async signOut(): Promise<void> {
    await AsyncStorage.removeItem(STORAGE_SESSION_KEY);
    this.notifyAuth(null);
  }

  async resetPassword(email: string): Promise<void> {
    await this.ensureSchema();
    const cleanEmail = email.trim().toLowerCase();
    const res = await this.query('SELECT id FROM cb_users WHERE email = ?;', [cleanEmail]);
    if (!res.rows || res.rows.length === 0) {
      throw new Error('No account found with this email address.');
    }
  }

  async updatePassword(password: string): Promise<void> {
    const user = await this.getCurrentUser();
    if (!user) throw new Error('Not authenticated.');
    await this.ensureSchema();
    await this.query('UPDATE cb_users SET password = ? WHERE id = ?;', [password, user.id]);
  }

  async deleteAccount(): Promise<void> {
    const user = await this.getCurrentUser();
    if (!user) return;
    await this.ensureSchema();

    await Promise.allSettled([
      this.query('DELETE FROM cb_users WHERE id = ?;', [user.id]),
      this.query('DELETE FROM cb_profiles WHERE user_id = ?;', [user.id]),
      this.query('DELETE FROM cb_preferences WHERE user_id = ?;', [user.id]),
      this.query('DELETE FROM cb_plans WHERE user_id = ?;', [user.id]),
      this.query('DELETE FROM cb_sessions WHERE user_id = ?;', [user.id]),
      this.query('DELETE FROM cb_reminders WHERE user_id = ?;', [user.id]),
      this.query('DELETE FROM cb_conversations WHERE user_id = ?;', [user.id]),
      this.query('DELETE FROM cb_messages WHERE user_id = ?;', [user.id]),
      this.query('DELETE FROM cb_progress WHERE user_id = ?;', [user.id]),
    ]);

    await this.signOut();
  }

  // --- Profiles & Preferences ---

  async getProfile(userId: string): Promise<Profile | null> {
    await this.ensureSchema();
    const res = await this.query('SELECT * FROM cb_profiles WHERE user_id = ?;', [userId]);
    if (!res.rows || res.rows.length === 0) return null;

    const row = res.rows[0];
    // Columns: pk_id(0), user_id(1), name(2), age(3), experience(4), environment(5), goals(6), limitations(7), onboarding_completed(8), created_at(9)
    return {
      id: String(row[1]),
      name: String(row[2] || 'Athlete'),
      age: row[3] !== null && row[3] !== undefined ? Number(row[3]) : null,
      experience: row[4] || 'beginner',
      environment: row[5] || 'both',
      goals: safeJsonParse<any[]>(row[6], []),
      limitations: row[7] ? String(row[7]) : null,
      onboardingCompleted: Boolean(row[8]),
      createdAt: String(row[9] || new Date().toISOString()),
    };
  }

  async saveProfile(profile: Profile): Promise<void> {
    await this.ensureSchema();
    const existing = await this.query('SELECT pk_id FROM cb_profiles WHERE user_id = ?;', [profile.id]);
    const goalsJson = JSON.stringify(profile.goals || []);

    if (existing.rows && existing.rows.length > 0) {
      await this.query(
        `UPDATE cb_profiles SET
          name = ?,
          age = ?,
          experience = ?,
          environment = ?,
          goals = ?,
          limitations = ?,
          onboarding_completed = ?,
          created_at = ?
        WHERE user_id = ?;`,
        [
          profile.name,
          profile.age,
          profile.experience,
          profile.environment,
          goalsJson,
          profile.limitations || '',
          profile.onboardingCompleted,
          profile.createdAt || new Date().toISOString(),
          profile.id,
        ],
      );
    } else {
      const pkId = generatePkId();
      await this.query('INSERT INTO cb_profiles VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
        pkId,
        profile.id,
        profile.name,
        profile.age,
        profile.experience,
        profile.environment,
        goalsJson,
        profile.limitations || '',
        profile.onboardingCompleted,
        profile.createdAt || new Date().toISOString(),
      ]);
    }
  }

  async getPreferences(userId: string): Promise<Preferences | null> {
    await this.ensureSchema();
    const res = await this.query('SELECT * FROM cb_preferences WHERE user_id = ?;', [userId]);
    if (!res.rows || res.rows.length === 0) return null;

    const row = res.rows[0];
    // Columns: pk_id(0), user_id(1), workout_days(2), session_minutes(3), equipment(4), avoid_exercises(5), reminder_time(6), units(7)
    return {
      userId: String(row[1]),
      workoutDays: safeJsonParse<number[]>(row[2], [1, 3, 5]),
      sessionMinutes: row[3] ? Number(row[3]) : 45,
      equipment: safeJsonParse<any[]>(row[4], []),
      avoidExercises: safeJsonParse<string[]>(row[5], []),
      reminderTime: String(row[6] || '18:00'),
      units: row[7] === 'lb' ? 'lb' : 'kg',
    };
  }

  async savePreferences(preferences: Preferences): Promise<void> {
    await this.ensureSchema();
    const existing = await this.query('SELECT pk_id FROM cb_preferences WHERE user_id = ?;', [
      preferences.userId,
    ]);

    const daysJson = JSON.stringify(preferences.workoutDays || []);
    const eqJson = JSON.stringify(preferences.equipment || []);
    const avoidJson = JSON.stringify(preferences.avoidExercises || []);

    if (existing.rows && existing.rows.length > 0) {
      await this.query(
        `UPDATE cb_preferences SET
          workout_days = ?,
          session_minutes = ?,
          equipment = ?,
          avoid_exercises = ?,
          reminder_time = ?,
          units = ?
        WHERE user_id = ?;`,
        [
          daysJson,
          preferences.sessionMinutes,
          eqJson,
          avoidJson,
          preferences.reminderTime,
          preferences.units,
          preferences.userId,
        ],
      );
    } else {
      const pkId = generatePkId();
      await this.query('INSERT INTO cb_preferences VALUES (?, ?, ?, ?, ?, ?, ?, ?);', [
        pkId,
        preferences.userId,
        daysJson,
        preferences.sessionMinutes,
        eqJson,
        avoidJson,
        preferences.reminderTime,
        preferences.units,
      ]);
    }
  }

  // --- Plans ---

  async getActivePlan(userId: string): Promise<WorkoutPlan | null> {
    await this.ensureSchema();
    const res = await this.query(
      'SELECT plan_json FROM cb_plans WHERE user_id = ? ORDER BY pk_id DESC LIMIT 1;',
      [userId],
    );

    if (!res.rows || res.rows.length === 0) return null;
    return safeJsonParse<WorkoutPlan | null>(res.rows[0][0], null);
  }

  async savePlan(plan: WorkoutPlan): Promise<void> {
    await this.ensureSchema();
    const existing = await this.query('SELECT pk_id FROM cb_plans WHERE id = ?;', [plan.id]);
    const planJson = JSON.stringify(plan);
    const eqJson = JSON.stringify(plan.equipment || []);

    if (existing.rows && existing.rows.length > 0) {
      await this.query(
        `UPDATE cb_plans SET
          name = ?,
          goal = ?,
          experience = ?,
          days_per_week = ?,
          session_minutes = ?,
          equipment = ?,
          source = ?,
          plan_json = ?
        WHERE id = ?;`,
        [
          plan.name,
          plan.goal,
          plan.experience,
          plan.daysPerWeek,
          plan.sessionMinutes,
          eqJson,
          plan.source,
          planJson,
          plan.id,
        ],
      );
    } else {
      const pkId = generatePkId();
      await this.query('INSERT INTO cb_plans VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
        pkId,
        plan.id,
        plan.userId,
        plan.name,
        plan.goal,
        plan.experience,
        plan.daysPerWeek,
        plan.sessionMinutes,
        eqJson,
        plan.source,
        plan.createdAt || new Date().toISOString(),
        planJson,
      ]);
    }
  }

  // --- Sessions ---

  async getSessions(userId: string): Promise<WorkoutSession[]> {
    await this.ensureSchema();
    const res = await this.query(
      'SELECT session_json FROM cb_sessions WHERE user_id = ? ORDER BY pk_id DESC;',
      [userId],
    );

    if (!res.rows) return [];
    return res.rows
      .map((row) => safeJsonParse<WorkoutSession | null>(row[0], null))
      .filter((s): s is WorkoutSession => s !== null);
  }

  async getSession(sessionId: string): Promise<WorkoutSession | null> {
    await this.ensureSchema();
    const res = await this.query('SELECT session_json FROM cb_sessions WHERE id = ?;', [sessionId]);
    if (!res.rows || res.rows.length === 0) return null;
    return safeJsonParse<WorkoutSession | null>(res.rows[0][0], null);
  }

  async saveSession(session: WorkoutSession): Promise<void> {
    await this.ensureSchema();
    const existing = await this.query('SELECT pk_id FROM cb_sessions WHERE id = ?;', [session.id]);
    const sessionJson = JSON.stringify(session);
    const focusJson = JSON.stringify(session.focus || []);

    if (existing.rows && existing.rows.length > 0) {
      await this.query(
        `UPDATE cb_sessions SET
          title = ?,
          focus = ?,
          ended_at = ?,
          duration_seconds = ?,
          status = ?,
          notes = ?,
          session_json = ?
        WHERE id = ?;`,
        [
          session.title,
          focusJson,
          session.endedAt || '',
          session.durationSeconds,
          session.status,
          session.notes || '',
          sessionJson,
          session.id,
        ],
      );
    } else {
      const pkId = generatePkId();
      await this.query('INSERT INTO cb_sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
        pkId,
        session.id,
        session.userId,
        session.planDayId || '',
        session.title,
        focusJson,
        session.startedAt,
        session.endedAt || '',
        session.durationSeconds,
        session.status,
        session.notes || '',
        sessionJson,
      ]);
    }
  }

  // --- Reminders ---

  async getReminderSettings(userId: string): Promise<ReminderSettings | null> {
    await this.ensureSchema();
    const res = await this.query('SELECT * FROM cb_reminders WHERE user_id = ?;', [userId]);
    if (!res.rows || res.rows.length === 0) return null;

    const row = res.rows[0];
    // pk_id(0), user_id(1), enabled(2), workout_time(3), days(4), rest_day_reminders(5), hydration_reminders(6), weekly_progress_reminder(7), scheduled_ids(8)
    return {
      userId: String(row[1]),
      enabled: Boolean(row[2]),
      workoutTime: String(row[3] || '18:00'),
      days: safeJsonParse<number[]>(row[4], []),
      restDayReminders: Boolean(row[5]),
      hydrationReminders: Boolean(row[6]),
      weeklyProgressReminder: Boolean(row[7]),
      scheduledIds: safeJsonParse<string[]>(row[8], []),
    };
  }

  async saveReminderSettings(settings: ReminderSettings): Promise<void> {
    await this.ensureSchema();
    const existing = await this.query('SELECT pk_id FROM cb_reminders WHERE user_id = ?;', [settings.userId]);
    const daysJson = JSON.stringify(settings.days || []);
    const scheduledJson = JSON.stringify(settings.scheduledIds || []);

    if (existing.rows && existing.rows.length > 0) {
      await this.query(
        `UPDATE cb_reminders SET
          enabled = ?,
          workout_time = ?,
          days = ?,
          rest_day_reminders = ?,
          hydration_reminders = ?,
          weekly_progress_reminder = ?,
          scheduled_ids = ?
        WHERE user_id = ?;`,
        [
          settings.enabled,
          settings.workoutTime,
          daysJson,
          settings.restDayReminders,
          settings.hydrationReminders,
          settings.weeklyProgressReminder,
          scheduledJson,
          settings.userId,
        ],
      );
    } else {
      const pkId = generatePkId();
      await this.query('INSERT INTO cb_reminders VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);', [
        pkId,
        settings.userId,
        settings.enabled,
        settings.workoutTime,
        daysJson,
        settings.restDayReminders,
        settings.hydrationReminders,
        settings.weeklyProgressReminder,
        scheduledJson,
      ]);
    }
  }

  // --- Conversations & Messages ---

  async listConversations(userId: string): Promise<CoachConversation[]> {
    await this.ensureSchema();
    const res = await this.query('SELECT id, user_id, title, created_at, updated_at FROM cb_conversations WHERE user_id = ? ORDER BY pk_id DESC;', [
      userId,
    ]);
    if (!res.rows) return [];
    return res.rows.map((r) => ({
      id: String(r[0]),
      userId: String(r[1]),
      title: String(r[2]),
      createdAt: String(r[3]),
      updatedAt: String(r[4] || r[3]),
    }));
  }

  async createConversation(conversation: CoachConversation): Promise<void> {
    await this.ensureSchema();
    const pkId = generatePkId();
    await this.query('INSERT INTO cb_conversations VALUES (?, ?, ?, ?, ?, ?);', [
      pkId,
      conversation.id,
      conversation.userId,
      conversation.title,
      conversation.createdAt,
      conversation.updatedAt,
    ]);
  }

  async updateConversation(conversation: CoachConversation): Promise<void> {
    await this.ensureSchema();
    await this.query('UPDATE cb_conversations SET title = ?, updated_at = ? WHERE id = ?;', [
      conversation.title,
      conversation.updatedAt,
      conversation.id,
    ]);
  }

  async deleteConversation(conversationId: string): Promise<void> {
    await this.ensureSchema();
    await this.query('DELETE FROM cb_messages WHERE conversation_id = ?;', [conversationId]);
    await this.query('DELETE FROM cb_conversations WHERE id = ?;', [conversationId]);
  }

  async listMessages(conversationId: string): Promise<CoachMessage[]> {
    await this.ensureSchema();
    const res = await this.query(
      'SELECT id, conversation_id, user_id, role, content, created_at FROM cb_messages WHERE conversation_id = ? ORDER BY pk_id ASC;',
      [conversationId],
    );
    if (!res.rows) return [];
    return res.rows.map((r) => ({
      id: String(r[0]),
      conversationId: String(r[1]),
      userId: String(r[2]),
      role: r[3] as 'user' | 'assistant',
      content: String(r[4]),
      createdAt: String(r[5]),
    }));
  }

  async addMessage(message: CoachMessage): Promise<void> {
    await this.ensureSchema();
    const pkId = generatePkId();
    await this.query('INSERT INTO cb_messages VALUES (?, ?, ?, ?, ?, ?, ?);', [
      pkId,
      message.id,
      message.conversationId,
      message.userId,
      message.role,
      message.content,
      message.createdAt,
    ]);
  }

  // --- Progress Records ---

  async listProgressRecords(userId: string): Promise<ProgressRecord[]> {
    await this.ensureSchema();
    const res = await this.query(
      'SELECT id, user_id, recorded_at, bodyweight_kg, notes FROM cb_progress WHERE user_id = ? ORDER BY pk_id DESC;',
      [userId],
    );
    if (!res.rows) return [];
    return res.rows.map((r) => ({
      id: String(r[0]),
      userId: String(r[1]),
      recordedAt: String(r[2]),
      bodyweightKg: r[3] !== null && r[3] !== undefined ? Number(r[3]) : null,
      notes: r[4] ? String(r[4]) : null,
    }));
  }

  async addProgressRecord(record: ProgressRecord): Promise<void> {
    await this.ensureSchema();
    const pkId = generatePkId();
    await this.query('INSERT INTO cb_progress VALUES (?, ?, ?, ?, ?, ?);', [
      pkId,
      record.id,
      record.userId,
      record.recordedAt,
      record.bodyweightKg,
      record.notes || '',
    ]);
  }
}
