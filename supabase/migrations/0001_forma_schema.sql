-- Forma core schema.
-- Apply with: supabase db push   (or paste into the SQL editor in order).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default 'Athlete' check (char_length(name) between 1 and 80),
  age integer check (age is null or age between 13 and 100),
  experience text not null default 'beginner'
    check (experience in ('beginner', 'intermediate', 'advanced')),
  environment text not null default 'both'
    check (environment in ('gym', 'home', 'both')),
  goals text[] not null default '{}'
    check (goals <@ array['strength', 'endurance', 'mobility', 'general', 'consistency']::text[]),
  limitations text check (limitations is null or char_length(limitations) <= 1000),
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'One row per user, created by the auth trigger.';

-- ---------------------------------------------------------------------------
-- user_preferences
-- ---------------------------------------------------------------------------
create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  workout_days integer[] not null default '{1, 3, 5}'
    check (workout_days <@ array[1, 2, 3, 4, 5, 6, 7]),
  session_minutes integer not null default 45 check (session_minutes between 10 and 180),
  equipment text[] not null default '{}',
  avoid_exercises text[] not null default '{}',
  reminder_time text not null default '18:00'
    check (reminder_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  units text not null default 'kg' check (units in ('kg', 'lb')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- exercise_library
-- ---------------------------------------------------------------------------
create table if not exists public.exercise_library (
  id text primary key check (char_length(id) between 1 and 80),
  name text not null,
  category text not null check (category in ('strength', 'conditioning', 'mobility')),
  primary_muscles text[] not null default '{}',
  secondary_muscles text[] not null default '{}',
  equipment text[] not null default '{}',
  difficulty text not null default 'beginner'
    check (difficulty in ('beginner', 'intermediate', 'advanced')),
  instructions text[] not null default '{}',
  cues text[] not null default '{}',
  mistakes text[] not null default '{}',
  alternatives text[] not null default '{}',
  is_unilateral boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.exercise_library is 'Public exercise catalog. Seeded from src/data/exercises.json.';

-- ---------------------------------------------------------------------------
-- workout_plans / workout_days / workout_exercises
-- ---------------------------------------------------------------------------
create table if not exists public.workout_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  goal text not null default 'general'
    check (goal in ('strength', 'endurance', 'mobility', 'general', 'consistency')),
  experience text not null default 'beginner'
    check (experience in ('beginner', 'intermediate', 'advanced')),
  days_per_week integer not null default 3 check (days_per_week between 1 and 7),
  session_minutes integer not null default 45 check (session_minutes between 10 and 180),
  equipment text[] not null default '{}',
  generated_by text not null default 'on-device' check (generated_by in ('ai', 'on-device')),
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now()
);

create index if not exists workout_plans_user_created_idx
  on public.workout_plans (user_id, created_at desc);
create unique index if not exists workout_plans_one_active_idx
  on public.workout_plans (user_id) where status = 'active';

create table if not exists public.workout_days (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.workout_plans (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  day_index integer not null check (day_index >= 0),
  weekday integer check (weekday is null or weekday between 1 and 7),
  title text not null,
  focus text[] not null default '{}',
  estimated_minutes integer not null default 0 check (estimated_minutes >= 0),
  warmup text[] not null default '{}',
  cooldown text[] not null default '{}',
  is_rest_day boolean not null default false,
  rest_note text,
  unique (plan_id, day_index)
);

create index if not exists workout_days_user_idx on public.workout_days (user_id);

create table if not exists public.workout_exercises (
  id uuid primary key default gen_random_uuid(),
  day_id uuid not null references public.workout_days (id) on delete cascade,
  plan_id uuid not null references public.workout_plans (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  exercise_id text not null references public.exercise_library (id) on delete restrict,
  position integer not null default 0 check (position >= 0),
  sets integer not null default 3 check (sets between 1 and 12),
  reps_min integer not null default 8 check (reps_min between 1 and 100),
  reps_max integer not null default 12 check (reps_max between 1 and 100),
  rest_seconds integer not null default 90 check (rest_seconds between 0 and 600),
  notes text,
  unique (day_id, position),
  check (reps_max >= reps_min)
);

create index if not exists workout_exercises_user_idx on public.workout_exercises (user_id);
create index if not exists workout_exercises_day_idx on public.workout_exercises (day_id);

-- ---------------------------------------------------------------------------
-- workout_sessions / completed_sets
-- ---------------------------------------------------------------------------
create table if not exists public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_day_id uuid references public.workout_days (id) on delete set null,
  title text not null,
  focus text[] not null default '{}',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  status text not null default 'active'
    check (status in ('active', 'paused', 'completed', 'abandoned')),
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists workout_sessions_user_started_idx
  on public.workout_sessions (user_id, started_at desc);

create table if not exists public.completed_sets (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.workout_sessions (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  workout_exercise_id uuid references public.workout_exercises (id) on delete set null,
  exercise_id text not null references public.exercise_library (id) on delete restrict,
  set_number integer not null check (set_number between 1 and 99),
  reps integer not null default 0 check (reps between 0 and 500),
  weight_kg numeric(7, 2) check (weight_kg is null or weight_kg between 0 and 1000),
  completed_at timestamptz not null default now()
);

create index if not exists completed_sets_session_idx on public.completed_sets (session_id);
create index if not exists completed_sets_user_exercise_idx
  on public.completed_sets (user_id, exercise_id, completed_at desc);

-- ---------------------------------------------------------------------------
-- exercise_history (per-set log kept in sync by trigger)
-- ---------------------------------------------------------------------------
create table if not exists public.exercise_history (
  id uuid primary key default gen_random_uuid(),
  source_set_id uuid not null unique references public.completed_sets (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  exercise_id text not null references public.exercise_library (id) on delete restrict,
  session_id uuid not null references public.workout_sessions (id) on delete cascade,
  reps integer not null default 0,
  weight_kg numeric(7, 2),
  completed_at timestamptz not null default now()
);

create index if not exists exercise_history_user_exercise_idx
  on public.exercise_history (user_id, exercise_id, completed_at desc);

-- ---------------------------------------------------------------------------
-- reminder_settings
-- ---------------------------------------------------------------------------
create table if not exists public.reminder_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  enabled boolean not null default false,
  workout_time text not null default '18:00'
    check (workout_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  days integer[] not null default '{}' check (days <@ array[1, 2, 3, 4, 5, 6, 7]),
  rest_day_reminders boolean not null default true,
  hydration_reminders boolean not null default false,
  weekly_progress_reminder boolean not null default true,
  scheduled_ids text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- coach_conversations / coach_messages
-- ---------------------------------------------------------------------------
create table if not exists public.coach_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null default 'Coach chat' check (char_length(title) between 1 and 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists coach_conversations_user_updated_idx
  on public.coach_conversations (user_id, updated_at desc);

create table if not exists public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.coach_conversations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) between 1 and 12000),
  created_at timestamptz not null default now()
);

create index if not exists coach_messages_conversation_idx
  on public.coach_messages (conversation_id, created_at);

-- ---------------------------------------------------------------------------
-- progress_records
-- ---------------------------------------------------------------------------
create table if not exists public.progress_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  recorded_at timestamptz not null default now(),
  bodyweight_kg numeric(5, 2) check (bodyweight_kg is null or bodyweight_kg between 20 and 400),
  notes text check (notes is null or char_length(notes) <= 2000),
  created_at timestamptz not null default now()
);

create index if not exists progress_records_user_recorded_idx
  on public.progress_records (user_id, recorded_at desc);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists user_preferences_set_updated_at on public.user_preferences;
create trigger user_preferences_set_updated_at
  before update on public.user_preferences
  for each row execute function public.set_updated_at();

drop trigger if exists reminder_settings_set_updated_at on public.reminder_settings;
create trigger reminder_settings_set_updated_at
  before update on public.reminder_settings
  for each row execute function public.set_updated_at();

drop trigger if exists coach_conversations_set_updated_at on public.coach_conversations;
create trigger coach_conversations_set_updated_at
  before update on public.coach_conversations
  for each row execute function public.set_updated_at();

-- Keep exercise_history in sync with completed_sets.
create or replace function public.sync_exercise_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.exercise_history where source_set_id = old.id;
    return old;
  end if;

  insert into public.exercise_history
    (source_set_id, user_id, exercise_id, session_id, reps, weight_kg, completed_at)
  values
    (new.id, new.user_id, new.exercise_id, new.session_id, new.reps, new.weight_kg, new.completed_at)
  on conflict (source_set_id) do update
    set user_id = excluded.user_id,
        exercise_id = excluded.exercise_id,
        session_id = excluded.session_id,
        reps = excluded.reps,
        weight_kg = excluded.weight_kg,
        completed_at = excluded.completed_at;

  return new;
end;
$$;

drop trigger if exists completed_sets_sync_history on public.completed_sets;
create trigger completed_sets_sync_history
  after insert or update or delete on public.completed_sets
  for each row execute function public.sync_exercise_history();

-- Provision a user's rows on sign-up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(nullif(btrim(new.raw_user_meta_data ->> 'name'), ''), 'Athlete'))
  on conflict (id) do nothing;

  insert into public.user_preferences (user_id) values (new.id)
  on conflict (user_id) do nothing;

  insert into public.reminder_settings (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
