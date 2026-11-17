-- Phase 4: structured, user-owned records for on-device camera form analysis.
-- Only measured session metadata and short observations are stored. Camera
-- frames, images, audio, video and raw pose-frame histories are never written
-- here (or anywhere) by the app.

create table if not exists public.form_analysis_sessions (
  id uuid primary key references public.workout_sessions (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  exercise_key text not null
    check (exercise_key in ('squat', 'pushUp', 'lunge', 'jumpingJack')),
  exercise_id text references public.exercise_library (id) on delete set null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_seconds integer not null check (duration_seconds >= 0),
  rep_count integer check (rep_count is null or rep_count >= 0),
  analysis_availability text not null
    check (analysis_availability in ('reliable', 'limited', 'unavailable')),
  coverage numeric(4, 3)
    check (coverage is null or (coverage >= 0 and coverage <= 1)),
  tracking_interruptions integer not null default 0
    check (tracking_interruptions >= 0),
  observations jsonb not null default '[]'::jsonb,
  limitations text[] not null default '{}',
  camera_position text not null check (camera_position in ('front', 'back')),
  created_at timestamptz not null default now(),
  constraint form_analysis_ended_after_started check (ended_at >= started_at)
);

comment on table public.form_analysis_sessions is
  'One row per completed camera form-analysis session. rep_count is null unless the on-device tracker produced a reliable count.';
comment on column public.form_analysis_sessions.observations is
  'Short measured observations (status, text, body points, limitation, measurements). No frames or keypoint histories.';

create index if not exists form_analysis_sessions_user_started_idx
  on public.form_analysis_sessions (user_id, started_at desc);

alter table public.form_analysis_sessions enable row level security;

drop policy if exists "form_analysis_sessions_own" on public.form_analysis_sessions;
create policy "form_analysis_sessions_own" on public.form_analysis_sessions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.form_analysis_sessions to authenticated;

-- Refresh history and progress when a form session is written.
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    begin
      alter publication supabase_realtime add table public.form_analysis_sessions;
    exception
      when duplicate_object then null;
    end;
  end if;
end
$$;
