# Forma

Forma is a native iOS AI personal gym coach written in SwiftUI. It turns a short
onboarding into a personal training plan, runs workouts with a live rest timer,
records every set, and reflects the results in progress analytics. The coach is
grounded in the athlete's own profile, plan, and training history, and in a
curated fitness knowledge base plus optional live web retrieval.

> Forma is training software, not medical care. It does not diagnose or treat
> injuries, and it tells the athlete to stop and seek a professional when they
> report pain or dizziness.

## Repository layout

```
native/                Native SwiftUI app (the shipping client)
  Forma/               App sources: Core, UI, Store, Services, Screens, Resources
  FormaTests/          Hosted unit tests, including gated live-backend tests
  FormaUITests/        End-to-end XCUITest coverage
  SETUP.md             Full backend, signing, and test instructions
supabase/
  migrations/          Schema, RLS, seed, memory/realtime, knowledge/usage
  functions/           Deno Edge Functions: coach-chat, coach-plan,
                       delete-account, knowledge-ingest
  knowledge/           Curated corpus and evaluation datasets
  .env.example         Every supported server secret and limit
scripts/               Ingestion, seeding, brand assets, live AI evaluation
tests/                 Node tests that execute the shipped TypeScript modules
src/                   Legacy Expo prototype (kept for reference, not shipped)
```

`native/SETUP.md` is the authoritative setup guide. This README is a summary.

## Build and run

Requirements: Xcode 26 or newer, iOS 18.0 deployment target, iPhone only.

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Open `Forma.xcodeproj` in Xcode and Run, or install the built app with
`xcrun simctl install` / `launch`.

With no Supabase build settings the app opens in an honest **Setup required**
state. A debug build offers **Explore preview data**, a local repository stored
in Application Support that is labelled as preview throughout the UI and is not
a fake backend. Production builds do not offer it.

Point the app at a project by setting `SUPABASE_URL` and `SUPABASE_ANON_KEY` as
user-defined Xcode build settings. Only the anon/publishable key belongs in the
app; it is constrained by RLS.

## Backend

### Schema

Apply the migrations in `supabase/migrations/` in filename order:

| File | Purpose |
| --- | --- |
| `0001_forma_schema.sql` | Tables, constraints, indexes, triggers |
| `0002_forma_rls.sql` | Row Level Security and grants |
| `0003_seed_exercises.sql` | Exercise catalog seed |
| `0004_ai_memory_and_realtime.sql` | Conversation summaries, message metadata, exercise provenance, Realtime publication |
| `0005_ai_knowledge_and_usage.sql` | pgvector, knowledge tables (1536-dim, HNSW, lexical index), `match_knowledge_chunks`, `ai_usage`, private retrieval cache |

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

### Edge Functions

```bash
supabase functions deploy coach-chat
supabase functions deploy coach-plan
supabase functions deploy delete-account
supabase functions deploy knowledge-ingest

supabase secrets set OPENAI_API_KEY=sk-...
# optional model routing (defaults shown)
supabase secrets set OPENAI_MODEL_FAST=gpt-4o-mini
supabase secrets set OPENAI_MODEL_STANDARD=gpt-4o-mini
supabase secrets set OPENAI_MODEL_REASONING=gpt-4o
supabase secrets set OPENAI_EMBEDDING_MODEL=text-embedding-3-small
# optional live web retrieval
supabase secrets set WEB_SEARCH_PROVIDER=tavily
supabase secrets set TAVILY_API_KEY=...
supabase secrets set KNOWLEDGE_INGEST_SECRET=$(openssl rand -hex 32)
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected by the Edge runtime. The OpenAI key exists only as a server secret and
is never shipped in the app or committed. `supabase/.env.example` lists every
supported secret and limit.

### Knowledge ingestion

The corpus in `supabase/knowledge/forma-coaching-notes.json` is original Forma
coaching content with publisher, date, licence, trust tier, and topic on every
document. Real OpenAI embeddings are generated server-side during ingestion.

```bash
FORMA_SUPABASE_URL=https://<ref>.supabase.co \
FORMA_SUPABASE_ANON_KEY=<anon-key> \
FORMA_INGEST_SECRET=<the secret above> \
  node scripts/ingest-knowledge.mjs
```

The script reports documents upserted, chunks stored, and chunks with real
embeddings, and exits non-zero if any document is rejected. Without embeddings,
retrieval still works lexically; the script says so explicitly.

## The coach pipeline

`coach-chat` authenticates the caller, enforces per-minute and per-day limits,
loads a bounded history window (not the whole conversation), resolves short
follow-ups, classifies intent, and routes to the smallest adequate model tier.
It then retrieves in parallel from the curated knowledge base and — only when
current information is requested — a live web provider.

Retrieved passages are treated as untrusted data, screened for instruction
injection, and cannot override the system rules. The answer streams to the app;
afterwards the server verifies every URL, citation marker, and exercise ID
against the sources actually retrieved, performs at most one correction pass,
removes unverified links, and appends an uncertainty note when a claim cannot be
tied to a source. `ai_usage` records model, intent, tokens, latency, and status.
Web results are cached for a short window under a key that contains no user
identifiers.

`coach-plan` generates a seven-day plan, validates schedule, duration, equipment,
duplicates, catalog IDs, and volume, and retries with a bounded revision loop.
The athlete must approve a generated plan in the app before it replaces the
active one.

## Tests

### Server modules (Node, real shipped TypeScript)

These run under Node, transpile the actual Edge Function sources, and need no
mocks or credentials:

```bash
node tests/planValidation.test.mjs   # plan schema, schedule, volume, duplicates
node tests/aiPipeline.test.mjs       # intent, routing, accuracy, safety, chunking, web filtering
node tests/retrievalEval.test.mjs    # lexical retrieval quality over the real corpus
```

`retrievalEval` reports recall@3 and MRR for the lexical fallback and fails
below 80% / 0.70. It does not measure pgvector; a vector run requires an
ingested project and real credentials.

### Native unit tests

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -only-testing:FormaTests
```

`LiveBackendTests` signs in to a real project and calls the deployed functions.
They **skip** unless `FORMA_SUPABASE_URL`, `FORMA_ANON_KEY`,
`FORMA_TEST_EMAIL`, and `FORMA_TEST_PASSWORD` are set. A skip is not evidence
that the backend works.

### Native UI tests

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -resultBundlePath /tmp/forma-uitests.xcresult
```

The UI test needs a clean install to exercise the setup screen:

```bash
xcrun simctl uninstall <device-udid> forma.coach
```

### Live AI evaluation (A–J)

`supabase/knowledge/eval-ai.json` holds ten cases covering the required
categories. The runner signs in, creates a real conversation, streams real
replies, checks each case, prints per-category results, and deletes the
conversation. It spends real model tokens.

```bash
FORMA_SUPABASE_URL=https://<ref>.supabase.co \
FORMA_SUPABASE_ANON_KEY=<anon-key> \
FORMA_TEST_EMAIL=<confirmed-test-user> \
FORMA_TEST_PASSWORD=<password> \
  node scripts/eval-ai.mjs
```

Without those four variables it prints `SKIPPED`, exits with code 3, and states
that nothing was tested. Use `FORMA_EVAL_CATEGORY`, `FORMA_EVAL_LIMIT`, and
`FORMA_EVAL_DELAY_MS` to narrow or pace a run.

## Security

- Only the anon key ships in the app. RLS scopes every row to `auth.uid()`.
- The OpenAI key and service-role key exist only as server secrets.
- Auth sessions are Keychain-backed and cleared on sign out or account deletion.
- Health data is read on demand; it is never logged or sent to the coach.
- Retrieved knowledge and web content is wrapped as untrusted reference data.
- URLs, citations, and exercise IDs are verified deterministically; unverified
  links are removed and the UI shows an uncertainty label.
- The web-retrieval cache is server-only and stores no user data. Conversations,
  summaries, and private data are never shared across users.
- When live retrieval is unavailable, the coach says so. It does not present
  general knowledge as current evidence.

## Verification status

Last verified in this repository:

- TypeScript typecheck of the Edge Function sources: passed.
- `tests/aiPipeline.test.mjs`: 47 checks passed.
- `tests/planValidation.test.mjs`: 9 checks passed.
- `tests/retrievalEval.test.mjs`: recall@3 100% (15/15), MRR 0.900 over the real
  corpus (lexical fallback; pgvector not measured).
- `FormaTests`: 34 executed, 2 skipped (`LiveBackendTests`), 0 failures.
- `FormaUITests`: passed.
- Debug and Release builds: succeeded.
- `scripts/eval-ai.mjs`: **SKIPPED** — no live credentials were available. Live
  OpenAI, Supabase, web retrieval, pgvector, and deployed-function behavior are
  therefore **not verified** in this checkout.

## Limitations

- Local notifications only; no push notifications.
- Realtime requires the project to have it enabled; otherwise the Home header
  shows **Cached** instead of **Live**.
- Live web retrieval needs a Tavily or Brave key. Without one the coach
  discloses that it cannot verify current information.
- Vector retrieval needs the ingested corpus and a project with pgvector.
- The Expo prototype in `src/` is legacy and not the shipping client.
