-- The AI Coach is replaced by Community. Any existing coach conversations are
-- preserved in an archive schema before the live tables are removed, so no
-- account content is destroyed by this cleanup. Nothing in the app reads the
-- archive; it exists only so an operator can review or export old rows.

create schema if not exists archive_ai_coach;

revoke all on schema archive_ai_coach from anon, authenticated;

do $$
declare
  target text;
begin
  if to_regclass('public.coach_conversations') is not null then
    execute 'create table if not exists archive_ai_coach.coach_conversations as
             select * from public.coach_conversations';
  end if;

  if to_regclass('public.coach_messages') is not null then
    execute 'create table if not exists archive_ai_coach.coach_messages as
             select * from public.coach_messages';
  end if;

  if to_regclass('public.knowledge_documents') is not null then
    execute 'create table if not exists archive_ai_coach.knowledge_documents as
             select * from public.knowledge_documents';
  end if;

  if to_regclass('public.knowledge_chunks') is not null then
    execute 'create table if not exists archive_ai_coach.knowledge_chunks as
             select * from public.knowledge_chunks';
  end if;

  if to_regclass('public.ai_usage') is not null then
    execute 'create table if not exists archive_ai_coach.ai_usage as
             select * from public.ai_usage';
  end if;

  if to_regclass('public.ai_retrieval_cache') is not null then
    execute 'create table if not exists archive_ai_coach.ai_retrieval_cache as
             select * from public.ai_retrieval_cache';
  end if;

  -- Realtime membership disappears with the tables, but remove it explicitly so
  -- the publication is clean even if a table was already missing.
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    for target in
      select unnest(array[
        'public.coach_conversations',
        'public.coach_messages'
      ])
    loop
      if to_regclass(target) is not null then
        begin
          execute format('alter publication supabase_realtime drop table %s', target);
        exception
          when undefined_object then null;
        end;
      end if;
    end loop;
  end if;
end $$;

-- Messages first: they reference conversations. Cascade also covers installations
-- where the FK is present.
drop table if exists public.coach_messages cascade;
drop table if exists public.coach_conversations cascade;

drop table if exists public.knowledge_chunks cascade;
drop table if exists public.knowledge_documents cascade;
drop table if exists public.ai_usage cascade;
drop table if exists public.ai_retrieval_cache cascade;

drop function if exists public.match_knowledge_chunks cascade;

-- The vector extension stays installed: it is shared infrastructure and removing
-- it could affect unrelated objects added later.

comment on schema archive_ai_coach is
  'Retired AI Coach and knowledge-base rows kept for operator review only. Not reachable by app clients.';
