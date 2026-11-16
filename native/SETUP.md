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
supabase secrets set OPENAI_API_KEY=sk-...
# optional, defaults to gpt-4o-mini
supabase secrets set OPENAI_MODEL=gpt-4o-mini
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
provided by the Edge runtime; do not hardcode them. The functions verify the
caller's JWT, scope every query by user id, and keep the OpenAI key on the
server only. `delete-account` uses the service role to remove the user's rows
and the auth user.

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

The server plan validator is also exercised directly against its shipped
TypeScript:

```bash
cd ..
node tests/planValidation.test.mjs
```

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
