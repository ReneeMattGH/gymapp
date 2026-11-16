-- Row Level Security for Forma.
-- Every table is scoped to auth.uid(); the exercise catalog is public read-only.

alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.exercise_library enable row level security;
alter table public.workout_plans enable row level security;
alter table public.workout_days enable row level security;
alter table public.workout_exercises enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.completed_sets enable row level security;
alter table public.exercise_history enable row level security;
alter table public.reminder_settings enable row level security;
alter table public.coach_conversations enable row level security;
alter table public.coach_messages enable row level security;
alter table public.progress_records enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated
  using (id = auth.uid());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- user_preferences
-- ---------------------------------------------------------------------------
drop policy if exists "user_preferences_select_own" on public.user_preferences;
create policy "user_preferences_select_own" on public.user_preferences
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "user_preferences_insert_own" on public.user_preferences;
create policy "user_preferences_insert_own" on public.user_preferences
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "user_preferences_update_own" on public.user_preferences;
create policy "user_preferences_update_own" on public.user_preferences
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- exercise_library (public read, writes only via service role/migrations)
-- ---------------------------------------------------------------------------
drop policy if exists "exercise_library_public_read" on public.exercise_library;
create policy "exercise_library_public_read" on public.exercise_library
  for select to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- workout_plans
-- ---------------------------------------------------------------------------
drop policy if exists "workout_plans_own" on public.workout_plans;
create policy "workout_plans_own" on public.workout_plans
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- workout_days
-- ---------------------------------------------------------------------------
drop policy if exists "workout_days_own" on public.workout_days;
create policy "workout_days_own" on public.workout_days
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- workout_exercises
-- ---------------------------------------------------------------------------
drop policy if exists "workout_exercises_own" on public.workout_exercises;
create policy "workout_exercises_own" on public.workout_exercises
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- workout_sessions
-- ---------------------------------------------------------------------------
drop policy if exists "workout_sessions_own" on public.workout_sessions;
create policy "workout_sessions_own" on public.workout_sessions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- completed_sets
-- ---------------------------------------------------------------------------
drop policy if exists "completed_sets_own" on public.completed_sets;
create policy "completed_sets_own" on public.completed_sets
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- exercise_history (read-only mirror of completed_sets, written by trigger)
-- ---------------------------------------------------------------------------
drop policy if exists "exercise_history_select_own" on public.exercise_history;
create policy "exercise_history_select_own" on public.exercise_history
  for select to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- reminder_settings
-- ---------------------------------------------------------------------------
drop policy if exists "reminder_settings_own" on public.reminder_settings;
create policy "reminder_settings_own" on public.reminder_settings
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- coach_conversations
-- ---------------------------------------------------------------------------
drop policy if exists "coach_conversations_own" on public.coach_conversations;
create policy "coach_conversations_own" on public.coach_conversations
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- coach_messages
-- ---------------------------------------------------------------------------
drop policy if exists "coach_messages_own" on public.coach_messages;
create policy "coach_messages_own" on public.coach_messages
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- progress_records
-- ---------------------------------------------------------------------------
drop policy if exists "progress_records_own" on public.progress_records;
create policy "progress_records_own" on public.progress_records
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select on public.exercise_library to anon, authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.user_preferences to authenticated;
grant select, insert, update, delete on public.workout_plans to authenticated;
grant select, insert, update, delete on public.workout_days to authenticated;
grant select, insert, update, delete on public.workout_exercises to authenticated;
grant select, insert, update, delete on public.workout_sessions to authenticated;
grant select, insert, update, delete on public.completed_sets to authenticated;
grant select on public.exercise_history to authenticated;
grant select, insert, update, delete on public.reminder_settings to authenticated;
grant select, insert, update, delete on public.coach_conversations to authenticated;
grant select, insert, update, delete on public.coach_messages to authenticated;
grant select, insert, update, delete on public.progress_records to authenticated;
