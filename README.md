# Forma

An AI personal gym coach built with Expo, React Native, TypeScript, and Supabase. Forma turns a short onboarding into a personal training plan, runs the workout with a live rest timer, records every set, and reflects the results in real progress analytics. The coach is grounded in the user's own profile, plan, and training history.

> Forma is training software, not medical care. It does not diagnose or treat injuries, and it tells the user to stop and seek a professional when they report pain or dizziness.

## Stack

- Expo SDK 58 / React Native 0.88 / React 19 / TypeScript
- Expo Router (typed routes) with a custom tab bar
- Supabase: Postgres, Auth, Row Level Security, Edge Functions
- OpenAI Chat Completions called only from a Supabase Edge Function
- AsyncStorage, expo-notifications, expo-haptics, react-native-svg, date-fns

## Run the app

```bash
npm install
cp .env.example .env        # fill in the values described below
npx expo start              # press i, a, or w
```

Useful checks:

```bash
npx tsc --noEmit
npx expo lint
npx expo-doctor
```

Launcher and splash assets are generated from the in-app brand mark (arc, crossbar, dot) with `npm run assets:brand`. It writes `assets/icon.png`, favicon, splash, and the Android adaptive foreground/background/monochrome layers.

### Preview mode

Set `EXPO_PUBLIC_DEV_PREVIEW=1` to use the on-device preview repository when no Supabase credentials exist. Preview data lives in AsyncStorage on that device, is labelled as a preview in the UI, and never pretends to be a backend. It is disabled in production builds. Remove the flag or provide Supabase credentials to use the real backend.

## Supabase setup

### 1. Create a project

Create a project at [supabase.com](https://supabase.com). Copy the project URL and anon key into `.env`:

```dotenv
EXPO_PUBLIC_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=YOUR-ANON-KEY
EXPO_PUBLIC_DEV_PREVIEW=0
```

The anon key is safe to ship in a client; it is constrained by RLS. Never put a service-role key in the app or in any `EXPO_PUBLIC_*` variable.

### 2. Apply the schema

Migrations live in `supabase/migrations/` and must be applied in order:

| File | Purpose |
| --- | --- |
| `0001_forma_schema.sql` | 13 tables, constraints, indexes, triggers |
| `0002_forma_rls.sql` | Row Level Security policies and grants |
| `0003_seed_exercises.sql` | 60-exercise catalog (generated) |

With the Supabase CLI:

```bash
npx supabase login
npx supabase link --project-ref YOUR-PROJECT-REF
npx supabase db push
```

Or paste each file into the SQL editor in filename order. The app also ships the catalog in `src/data/exercises.json`, so the library still renders before the seed is applied, but plans, sets, and history need the seeded `exercise_library` rows because of foreign keys.

After editing `src/data/exercises.json`, regenerate the seed:

```bash
npm run seed:exercises
```

### 3. Configure Auth

- Enable Email provider (email + password).
- Decide whether email confirmation is required. With confirmation on, the app shows a "check your email" state after sign-up.
- Add redirect URLs under Authentication → URL Configuration:
  - `forma://update-password` (production build)
  - `exp://127.0.0.1:8081/--/update-password` (Expo Go on a simulator)
  - your LAN `exp://<host>:8081/--/update-password` while testing on a device
  - the equivalent `http://localhost:8081/update-password` when testing in a browser
- Set the Site URL to your web URL in production.

Password reset uses `Linking.createURL('/update-password')`, so the redirect must be allow-listed for the reset link to return to the app.

### 4. Deploy the Edge Functions

```bash
npx supabase functions deploy coach-chat
npx supabase functions deploy coach-plan
npx supabase functions deploy delete-account
npx supabase secrets set OPENAI_API_KEY=sk-...
npx supabase secrets set OPENAI_MODEL=gpt-4o-mini   # optional
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are provided to deployed functions by Supabase. Do not duplicate them in `.env`.

| Function | Method | Responsibility |
| --- | --- | --- |
| `coach-chat` | POST | Verifies the caller, checks conversation ownership, streams a grounded coach reply, persists both messages |
| `coach-plan` | POST | `generate_plan` builds a 7-day plan from the user's profile, preferences, and catalog; `daily_insight` produces a short factual summary |
| `delete-account` | POST | Authenticated account deletion via the admin API |

The functions call OpenAI server-side. The client never sees `OPENAI_API_KEY` or the service-role key; only the anon key and the user's JWT are sent.

### 5. Database model

| Table | Notes |
| --- | --- |
| `profiles` | One row per user, created by an `auth.users` trigger |
| `user_preferences` | Training days, session length, equipment, avoid list, units |
| `exercise_library` | Public read-only catalog |
| `workout_plans` | One active plan per user (partial unique index) |
| `workout_days` | Seven rows per plan, including rest days |
| `workout_exercises` | Ordered prescriptions referencing the catalog |
| `workout_sessions` | Active, paused, completed, or abandoned sessions |
| `completed_sets` | Every logged set with reps and load |
| `exercise_history` | Trigger-maintained per-exercise log for progression |
| `reminder_settings` | Server copy of reminder preferences |
| `coach_conversations` | Chat threads |
| `coach_messages` | User and assistant turns |
| `progress_records` | Check-ins: bodyweight and notes |

Trigger behavior:

- `handle_new_user` provisions `profiles`, `user_preferences`, and `reminder_settings` on sign-up.
- `sync_exercise_history` mirrors inserts, updates, and deletes from `completed_sets` into `exercise_history`.
- `set_updated_at` keeps `profiles`, `user_preferences`, `reminder_settings`, and `coach_conversations` timestamps current.

RLS is enabled on all 13 tables. Every row is scoped to `auth.uid()`; the exercise catalog is readable by `anon` and `authenticated` but writable only by migrations/service role.

## How the app works

- **Onboarding** collects experience, environment, goals, days, session length, equipment, and exercises to skip, then generates a plan locally. If AI is configured, the plan screen offers an AI regeneration path; otherwise the on-device plan remains.
- **Workout mode** keeps `ActiveWorkout` in AsyncStorage, including elapsed time and rest state, so a restart resumes the same session. Rest supports pause, resume, skip, and +15 seconds; vibration fires when time is up.
- **History and analytics** are computed only from recorded sessions. Empty states are explicit: no sessions means no streaks, no charts, and no invented numbers.
- **Recovery** is training guidance derived from recent workload. It is not a readiness score and says so in the UI.
- **Coach** streams responses. Without a configured backend it shows a setup-required state instead of a canned reply.
- **Reminders** are local notifications, scheduled only after the OS grants permission. The app stores the notification IDs the OS actually accepted. Web shows an unsupported message rather than pretending to schedule anything.
- **Profile and settings** edit profile, preferences, units, avoid list, theme, reminders, and account. Destructive account deletion requires typing `DELETE`.

## Security notes

- API keys and service-role keys stay in Supabase secrets.
- Edge Functions authenticate the caller with `auth.getUser()` and scope queries to the caller (or verify resource ownership).
- `delete-account` requires a signed-in user with an email identity and refuses anonymous accounts.
- Coach prompts include safety rules: no diagnosis or prescriptions, stop on pain/dizziness, refer to a professional, conservative loading, and no pressure to train through pain.
- RLS plus explicit `user_id` columns prevent cross-user reads and writes. Verified with local Postgres tests covering cross-user inserts, updates, catalog writes, and the one-active-plan constraint.

## Project layout

```
src/app/              Expo Router routes (tabs, onboarding, workout, settings)
src/components/       UI primitives, charts, coach, workout components
src/data/             Types, repositories, exercise catalog
src/features/         Onboarding and feature-specific components
src/lib/              Plan generation, AI client, notifications, dates, ids
src/state/            App and workout providers
src/theme/            Tokens and theme provider
supabase/functions/   Deno Edge Functions and shared modules
supabase/migrations/  Schema, RLS, seed
scripts/              Seed generator
```

## Limitations

- Local notifications work on iOS/Android, not in the browser.
- Expo web is the verified development surface in this environment; the UI is mobile-first.
- Edge Functions require Deno to typecheck locally (`deno check supabase/functions/*/index.ts`). Deploying them requires the Supabase CLI.
- AI features require `OPENAI_API_KEY` and a deployed `coach-chat` / `coach-plan`; until then the UI shows setup-required states.
