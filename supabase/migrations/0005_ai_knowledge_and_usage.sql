-- Phase 3: retrieval knowledge base (pgvector), AI usage accounting and a
-- shared retrieval cache. No embeddings are generated or stored by SQL; the
-- knowledge-ingest Edge Function writes real OpenAI embeddings.

create extension if not exists vector;

-- ---------------------------------------------------------------------------
-- knowledge_documents: curated, attributable sources
-- ---------------------------------------------------------------------------
create table if not exists public.knowledge_documents (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,80}$'),
  title text not null check (char_length(title) between 3 and 200),
  publisher text not null,
  url text,
  published_at date,
  license text,
  trust text not null default 'reputable'
    check (trust in ('official', 'peer_reviewed', 'reputable', 'community')),
  topic text,
  summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.knowledge_documents is
  'Curated fitness knowledge sources. Every row is attributable; URLs are only stored when supplied by an administrator.';
comment on column public.knowledge_documents.trust is
  'Editorial trust tier used to weight retrieval and to decide whether a citation is safe to surface.';

create index if not exists knowledge_documents_topic_idx
  on public.knowledge_documents (topic);

-- ---------------------------------------------------------------------------
-- knowledge_chunks: retrievable passages with real embeddings
-- ---------------------------------------------------------------------------
create table if not exists public.knowledge_chunks (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.knowledge_documents (id) on delete cascade,
  chunk_index integer not null check (chunk_index >= 0),
  content text not null check (char_length(content) between 40 and 6000),
  token_count integer not null default 0 check (token_count >= 0),
  embedding vector(1536),
  content_tsv tsvector generated always as (to_tsvector('english', content)) stored,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (document_id, chunk_index)
);

comment on table public.knowledge_chunks is
  'Passages from curated sources. embedding is null only when ingestion ran without an embedding model; lexical fallback still works.';

create index if not exists knowledge_chunks_document_idx
  on public.knowledge_chunks (document_id, chunk_index);
create index if not exists knowledge_chunks_tsv_idx
  on public.knowledge_chunks using gin (content_tsv);
create index if not exists knowledge_chunks_embedding_idx
  on public.knowledge_chunks using hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- Vector similarity search. Falls back to lexical search in the Edge Function
-- when embeddings or this RPC are unavailable.
-- ---------------------------------------------------------------------------
create or replace function public.match_knowledge_chunks(
  query_embedding vector(1536),
  match_count integer default 5,
  min_similarity double precision default 0.15
)
returns table (
  chunk_id uuid,
  document_id uuid,
  content text,
  chunk_index integer,
  similarity double precision,
  title text,
  publisher text,
  url text,
  published_at date,
  trust text,
  topic text
)
language sql
stable
as $$
  with ranked as (
    select
      c.id as chunk_id,
      c.document_id,
      c.content,
      c.chunk_index,
      1 - (c.embedding <=> query_embedding) as similarity,
      d.title,
      d.publisher,
      d.url,
      d.published_at,
      d.trust,
      d.topic
    from public.knowledge_chunks c
    join public.knowledge_documents d on d.id = c.document_id
    where c.embedding is not null
    order by c.embedding <=> query_embedding
    limit greatest(1, least(match_count, 12))
  )
  select *
  from ranked
  where similarity >= greatest(0, least(min_similarity, 0.9));
$$;

comment on function public.match_knowledge_chunks is
  'Cosine similarity over real stored embeddings. The Edge Function filters results again before prompting.';

-- ---------------------------------------------------------------------------
-- ai_usage: per-request token accounting, also used for rate limiting
-- ---------------------------------------------------------------------------
create table if not exists public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  function_name text not null check (char_length(function_name) between 2 and 60),
  intent text,
  model text,
  prompt_tokens integer not null default 0 check (prompt_tokens >= 0),
  completion_tokens integer not null default 0 check (completion_tokens >= 0),
  total_tokens integer not null default 0 check (total_tokens >= 0),
  latency_ms integer not null default 0 check (latency_ms >= 0),
  status text not null default 'ok' check (status in ('ok', 'blocked', 'error', 'cancelled')),
  created_at timestamptz not null default now()
);

comment on table public.ai_usage is
  'One row per AI request. Users can read their own rows; Edge Functions write with the caller token or service role.';

create index if not exists ai_usage_user_created_idx
  on public.ai_usage (user_id, created_at desc);

comment on column public.ai_usage.intent is
  'Deterministic intent classification used to route the request.';

-- ---------------------------------------------------------------------------
-- ai_retrieval_cache: shared, provider-agnostic cache for web results
-- ---------------------------------------------------------------------------
create table if not exists public.ai_retrieval_cache (
  cache_key text primary key,
  provider text not null,
  payload jsonb not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null
);

comment on table public.ai_retrieval_cache is
  'Short-lived cache of public web search results. Contains no user data; readable only by the service role.';

create index if not exists ai_retrieval_cache_expiry_idx
  on public.ai_retrieval_cache (expires_at);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.knowledge_documents enable row level security;
alter table public.knowledge_chunks enable row level security;
alter table public.ai_usage enable row level security;
alter table public.ai_retrieval_cache enable row level security;

drop policy if exists "knowledge_documents_read" on public.knowledge_documents;
create policy "knowledge_documents_read" on public.knowledge_documents
  for select to authenticated using (true);

drop policy if exists "knowledge_chunks_read" on public.knowledge_chunks;
create policy "knowledge_chunks_read" on public.knowledge_chunks
  for select to authenticated using (true);

drop policy if exists "ai_usage_own_read" on public.ai_usage;
create policy "ai_usage_own_read" on public.ai_usage
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "ai_usage_own_insert" on public.ai_usage;
create policy "ai_usage_own_insert" on public.ai_usage
  for insert to authenticated with check (user_id = auth.uid());

-- ai_retrieval_cache intentionally has no policies: service role only.

grant select on public.knowledge_documents to authenticated;
grant select on public.knowledge_chunks to authenticated;
grant select, insert on public.ai_usage to authenticated;
grant execute on function public.match_knowledge_chunks(vector, integer, double precision) to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime is not needed for these tables; they are server-written.
-- ---------------------------------------------------------------------------
