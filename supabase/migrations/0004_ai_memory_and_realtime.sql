-- Phase 2: conversation memory, grounded reply metadata, exercise provenance,
-- and realtime sync for coach-relevant tables.

-- ---------------------------------------------------------------------------
-- coach_conversations: rolling summary used as long-term memory
-- ---------------------------------------------------------------------------
alter table public.coach_conversations
  add column if not exists summary text,
  add column if not exists summary_message_count integer not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'coach_conversations_summary_message_count_check'
  ) then
    alter table public.coach_conversations
      add constraint coach_conversations_summary_message_count_check
      check (summary_message_count >= 0);
  end if;
end $$;

comment on column public.coach_conversations.summary is
  'Condensed memory of older messages, refreshed by the coach-chat Edge Function.';
comment on column public.coach_conversations.summary_message_count is
  'How many messages (oldest first) are already folded into summary.';

-- ---------------------------------------------------------------------------
-- coach_messages: structured metadata for assistant replies
-- ---------------------------------------------------------------------------
alter table public.coach_messages
  add column if not exists metadata jsonb not null default '{}'::jsonb;

comment on column public.coach_messages.metadata is
  'Structured reply metadata, currently the verified exercise sources used to ground an assistant reply.';

-- ---------------------------------------------------------------------------
-- exercise_library: provenance for every catalog record
-- ---------------------------------------------------------------------------
alter table public.exercise_library
  add column if not exists source text not null default 'Forma verified library';

comment on column public.exercise_library.source is
  'Where the exercise record came from. Rendered in the app so provenance is never invented.';

-- ---------------------------------------------------------------------------
-- Realtime: publish user-scoped tables the coach and dashboard listen to.
-- RLS still applies; these tables are only readable by their owner.
-- REPLICA IDENTITY FULL lets Realtime evaluate user_id filters on changes.
-- ---------------------------------------------------------------------------
alter table public.workout_plans replica identity full;
alter table public.workout_sessions replica identity full;
alter table public.completed_sets replica identity full;
alter table public.user_preferences replica identity full;
alter table public.coach_messages replica identity full;

do $$
declare
  target text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    for target in
      select unnest(array[
        'public.workout_plans',
        'public.workout_sessions',
        'public.completed_sets',
        'public.user_preferences',
        'public.coach_messages'
      ])
    loop
      begin
        execute format('alter publication supabase_realtime add table %s', target);
      exception
        when duplicate_object then null;
        when undefined_table then null;
      end;
    end loop;
  end if;
end $$;
