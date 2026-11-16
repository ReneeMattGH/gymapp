# Forma — native iOS setup

Forma is a SwiftUI app that talks to Supabase for auth, sync, and the AI coach.
No keys ship in the repository. Without them the app builds and runs in an
honest **Setup required** state; a debug build can also run a local, clearly
labelled preview mode.

## Requirements

- Xcode 26 or newer (iOS 18.0 deployment target, iPhone only)
- An Apple ID for simulator builds; a paid team for a device build
- A Supabase project (free tier is enough)
- An OpenAI API key, stored only as a server-side Edge Function secret

## 1. Build and run the app as-is

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Open `Forma.xcodeproj` in Xcode, pick a simulator, and Run. Because
`SUPABASE_URL` and `SUPABASE_ANON_KEY` are empty, the app opens on the
Setup required screen with instructions.

To explore the interface without a backend, use **Explore preview data** at the
bottom of that screen (debug builds only). Preview mode stores everything in
Application Support on the device, labels itself throughout the UI, and uses
on-device coach replies. It is not a fake backend; it is a separate local
repository that is reset when you exit preview from Profile.

## 2. Create the Supabase project

1. Create a project at <https://supabase.com>.
2. Apply the schema, policies, and exercise seed:

   ```bash
   supabase link --project-ref <your-project-ref>
   supabase db push          # runs every file in supabase/migrations, in order
   ```

   Or paste the files from `supabase/migrations/` into the SQL editor in
   filename order. Migration `0004_ai_memory_and_realtime.sql` adds conversation
   summaries/message metadata, exercise provenance, and enables Realtime on the
   synced tables — the upgraded functions and the app's live sync require it.
   Migration `0005_ai_knowledge_and_usage.sql` enables the `vector` extension,
   adds the curated knowledge tables (1536-dimension embeddings, HNSW index,
   lexical index, `match_knowledge_chunks`), token usage accounting, and the
   private web-retrieval cache. pgvector is available on Supabase; on a
   self-hosted Postgres, install it before applying 0005.

3. **Realtime.** The app subscribes to a per-user channel filtered by `user_id`
   on `workout_plans`, `workout_sessions`, `completed_sets`, `user_preferences`,
   and `coach_messages`. Migration 0004 sets `replica identity full` and adds
   those tables to the `supabase_realtime` publication. If Realtime is disabled
   at the project level, the app still works and honestly shows **Cached**
   instead of **Live** on the Home header.

4. In **Authentication → URL configuration**, add `forma://auth-callback` as an
   allowed redirect URL. Email confirmation and password recovery both use it.

## 3. Deploy the Edge Functions

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
# optional live web retrieval; without a key the coach discloses that it cannot
# verify current information and never invents links
supabase secrets set WEB_SEARCH_PROVIDER=tavily
supabase secrets set TAVILY_API_KEY=...
supabase secrets set KNOWLEDGE_INGEST_SECRET=$(openssl rand -hex 32)
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
provided by the Edge runtime; do not hardcode them. The functions verify the
caller's JWT, scope every query by user id, and keep the OpenAI key on the
server only. `delete-account` and `knowledge-ingest` use the service role for
admin operations; ingestion additionally requires the shared secret above.
`supabase/.env.example` lists every supported secret and limit for local
`supabase functions serve --env-file supabase/.env`.

### Ingest the curated knowledge base

The corpus in `supabase/knowledge/forma-coaching-notes.json` is original Forma
coaching content with publisher, date, licence, trust tier, and topic on every
document. It contains no invented external citations. Real OpenAI embeddings are
generated during ingestion; nothing is embedded client-side.

```bash
FORMA_SUPABASE_URL=https://<ref>.supabase.co \
FORMA_SUPABASE_ANON_KEY=<anon-key> \
FORMA_INGEST_SECRET=<the secret set above> \
  node scripts/ingest-knowledge.mjs
```

The script calls the deployed `knowledge-ingest` function, prints stored/embedded
counts, and exits non-zero if any document is rejected. Pass `--allow-lexical`
(or `?allowLexical=true` in the function body) only when intentionally running
without embeddings; lexical retrieval still works, but vector search does not.
Embedding dimensions must stay 1536 unless the column and RPC are migrated too.

### How a coach reply is produced

`coach-chat` authenticates the caller, enforces per-minute/per-day usage limits,
loads a bounded history window (not the entire conversation), resolves short
follow-ups, classifies intent, routes to the smallest adequate model tier, then
retrieves in parallel from the curated knowledge base and — only when current
information is requested — a live web provider. Retrieved passages are treated
as untrusted data, screened for prompt injection, and never override the system
rules. The draft streams to the app; afterwards the server verifies every URL,
citation marker, and exercise ID against the sources actually retrieved, performs
at most one correction pass, removes unverified links, and appends an explicit
uncertainty note when a claim could not be tied to a source. Usage rows in
`ai_usage` record model, intent, tokens, latency, and status.

Web results are cached for a short, configurable window in
`ai_retrieval_cache`. The cache key is a hash of provider, limit, and query; it
stores no user identifiers or personal data.

## 4. Point the app at the project

Set these Xcode build settings (target **Forma** → Build Settings → + Add User-
Defined Setting), or pass them on the command line:

| Setting | Value |
| --- | --- |
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | the project's anon/publishable key |

They flow into `Info.plist` as `SUPABASE_URL` / `SUPABASE_ANON_KEY` and are read
by `AppConfig`. Never add a service-role key or an OpenAI key to the app target.

Build again. The Setup required screen is replaced by email sign-up/sign-in.
After confirming your email, onboarding collects training details, generates a
plan on-device, and syncs it to Supabase.

## 5. Device signing and notifications

- Select your team under **Signing & Capabilities** for the Forma target.
- The bundle id is `com.forma.coach`; change it if it is already taken.
- Notifications are local calendar triggers, so no push certificates are
  needed. iOS asks for permission the first time reminders are saved, including
  during onboarding. The Reminders screen reports the count iOS actually has
  pending, never an optimistic value.
- To test on a physical iPhone, trust the developer certificate in
  Settings → General → VPN & Device Management.

## 6. Apple Health

Health access is opt-in from Profile → Apple Health. The app requests read-only
access to workouts, active energy, steps, and heart rate. HealthKit does not
reveal read authorization, so Forma reports what a fetch actually returned and
labels the source as Apple Health. It never writes to Health.

`Info.plist` already contains the required usage strings.

## 7. Tests

`FormaTests` is a hosted unit-test target covering the plan validator (schedule,
duration, equipment, duplicates, safe volume), the assistant response safety
validator, and exercise search/filtering/pagination. Run it alone with:

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -only-testing:FormaTests
```

`LiveBackendTests` in the same target signs in to a real project and calls the
deployed `coach-chat` and `coach-plan` functions. They **skip** unless all four
variables are set, and a skip is not evidence that the backend works:

```bash
FORMA_SUPABASE_URL=https://<ref>.supabase.co \
FORMA_ANON_KEY=<anon-key> \
FORMA_TEST_EMAIL=<confirmed-test-user> \
FORMA_TEST_PASSWORD=<password> \
  xcodebuild test ... -only-testing:FormaTests/LiveBackendTests
```

The server modules are also exercised directly against their shipped
TypeScript. These run under Node and transpile the real Edge Function sources;
they do not call a mock API:

```bash
cd ..
node tests/planValidation.test.mjs   # plan schema, schedule, volume, duplicates
node tests/aiPipeline.test.mjs       # intent, routing, accuracy, safety, chunking, web filtering
node tests/retrievalEval.test.mjs    # lexical retrieval quality over the real corpus
```

`retrievalEval` prints recall@3 and MRR for the lexical fallback and fails below
80% / 0.70. It deliberately does **not** claim to measure pgvector; a live vector
run requires an ingested project and real credentials.

The A–J evaluation dataset lives in `supabase/knowledge/eval-ai.json`. Run it
against a deployed project with a confirmed test user:

```bash
FORMA_SUPABASE_URL=https://<ref>.supabase.co \
FORMA_SUPABASE_ANON_KEY=<anon-key> \
FORMA_TEST_EMAIL=<confirmed-test-user> \
FORMA_TEST_PASSWORD=<password> \
  node scripts/eval-ai.mjs
```

It signs in, creates a real conversation, streams real replies, checks each
category, prints per-category results, and deletes the conversation. It spends
real model tokens. Without the four variables it prints `SKIPPED`, exits with
code 3, and states that nothing was tested — a skip is not a pass. Use
`FORMA_EVAL_CATEGORY` or `FORMA_EVAL_LIMIT` to narrow a run, and
`FORMA_EVAL_DELAY_MS` to pace calls against the per-minute limit.

`FormaUITests` drives the real app end-to-end on a simulator: setup screen,
preview entry, the seven onboarding steps, plan generation, all five tabs,
logging a set with the rest timer, backgrounding and reactivation, finishing
and saving the session, coach replies, reminders scheduling with the system
permission prompt, and relaunch persistence.

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -resultBundlePath /tmp/forma-uitests.xcresult
```

The test needs a clean install to exercise the setup screen:

```bash
xcrun simctl uninstall <device-udid> com.forma.coach
```

Screenshots are attached to the result bundle and can be exported with
`xcrun xcresulttool export attachments`.

## 8. Project layout

```
native/Forma/
  Core/        AppConfig, models, formatters, theme tokens
  UI/          Shared components
  Store/       AppModel (@Observable, @MainActor)
  Services/    Supabase, AI, HealthKit, notifications, plan engine, storage
  Screens/     Root, onboarding, tabs, workout, library, coach, settings
  Resources/   Fonts, exercise catalog
native/FormaUITests/   XCUITest coverage
supabase/              Migrations and Edge Functions
```

## Security checklist

- Only the anon/publishable key is in the app; RLS restricts every table to the
  signed-in user.
- The OpenAI key exists only as an Edge Function secret.
- Auth sessions are persisted by the Supabase SDK (Keychain-backed) and cleared
  on sign out or account deletion.
- Health data is read on demand and is never logged or sent to the coach.
- AI output is validated server-side and client-side: exercises must exist in
  the catalog, loads stay conservative, and pain or medical questions are
  redirected to a professional rather than diagnosed.
- Retrieved knowledge and web content is wrapped as untrusted reference data and
  screened for instruction injection before it reaches the model.
- URLs, citation markers, and exercise IDs in a reply are checked against the
  sources actually retrieved; unverified links are removed and the athlete sees
  an uncertainty label instead of a confident fabrication.
- The web-retrieval cache is server-only and contains public search results, not
  user data. Conversations, summaries, and private cache entries are never
  shared across users.
- When live retrieval is unavailable, the coach says so. It does not present
  general knowledge as current evidence.
