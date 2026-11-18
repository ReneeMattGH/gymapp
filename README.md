# Forma

Forma is a native iOS training app written in SwiftUI. It turns a short
onboarding into a personal training plan, runs workouts with a live rest timer,
records every set, and reflects the results in progress analytics. Community
lets people who chose the same gym or area find each other, connect, post, and
message — using only real registered accounts and real backend records. A camera
form check tracks body joints on-device with Apple Vision and reports only what
it can measure. A WidgetKit Home Screen widget mirrors the owner's real training
week without a second data store.

> Forma is training software, not medical care. It does not diagnose or treat
> injuries, and it tells the athlete to stop and seek a professional when they
> report pain or dizziness.

## Repository layout

```
native/                Native SwiftUI app (the shipping client)
  Forma/               App sources: Core, UI, Store, Services, Community,
                       FormAnalysis, Widget, Screens, Resources
  FormaWidgets/        WidgetKit extension: Fitness Command Center
  Shared/              Snapshot models, App Group store, timeline helpers
                       compiled into both the app and the widget
  FormaTests/          Hosted unit tests, including gated live-backend tests
  FormaUITests/        End-to-end XCUITest coverage
  SETUP.md             Full backend, signing, and test instructions
supabase/
  migrations/          Schema, RLS, seed, form analysis, Community, AI cleanup
  functions/           Deno Edge Function: delete-account
  .env.example         Server secrets (none required for Community)
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
a fake backend. Production builds do not offer it. Community is disabled in
preview mode and says so instead of inventing members.

Point the app at a project by setting `SUPABASE_URL` and `SUPABASE_ANON_KEY` as
user-defined Xcode build settings. Only the anon/publishable key belongs in the
app; it is constrained by RLS.

## Backend

### Schema

Apply the migrations in `supabase/migrations/` in filename order:

| File | Purpose |
| --- | --- |
| `0001_forma_schema.sql` | Profiles, exercises, plans, workouts, sets, reminders |
| `0002_forma_rls.sql` | Row Level Security and grants |
| `0003_seed_exercises.sql` | Exercise catalog seed |
| `0004_ai_memory_and_realtime.sql` | Historical AI memory tables (archived and dropped by `0008`) |
| `0005_ai_knowledge_and_usage.sql` | Historical AI knowledge tables (archived and dropped by `0008`) |
| `0006_form_analysis.sql` | One-to-one `form_analysis_sessions` record per camera session, RLS, Realtime |
| `0007_community.sql` | Gyms, areas, profiles, preferences, memberships, account status, blocks, connections, conversations, messages, reads, mutes, posts, likes, comments, hidden posts, reports, admins, moderation actions, notifications, RPCs, RLS, avatar storage, Realtime |
| `0008_remove_ai_coach.sql` | Copies legacy AI coach, knowledge, usage, and cache rows into the unexposed `archive_ai_coach` schema, then drops the AI tables and functions |

`0008` archives rather than silently discarding old AI conversations. The
archive schema is revoked from `anon` and `authenticated`: it exists only for an
operator to review or export legacy rows, not for the app.

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

### Edge Functions

```bash
supabase functions deploy delete-account
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected by the Edge runtime. Community needs no custom server secrets: every
mutation runs through `SECURITY DEFINER` RPCs and RLS. There is no AI provider,
model key, or knowledge-ingestion secret in this build.

## Community

Community is a first-class tab backed by real database records. There are no
seed members, fake requests, sample conversations, or placeholder posts, and the
preview repository cannot construct any: in preview mode the tab explains that
Community needs a real account and backend.

### Discovery and privacy

- A member picks a gym from the `gyms` table or an area from `community_areas`.
  Chennai areas ship as reference data; gyms are searched, joined when verified,
  or submitted for review. Duplicate gym submissions are detected by normalized
  name and city.
- Discovery returns only accounts that completed a Community profile and left
  `discoverable` on. `community_discover` enforces blocks, suspension,
  age-band compatibility, and the viewer's privacy switches on the server.
- Matching uses the chosen gym or area only. It never uses GPS, background
  location, presence, current gym attendance, or exact distance. The app does
  not request location permission for Community and never reveals whether a
  member is physically inside a gym.
- Results expose only public profile fields: user id, username, display name,
  avatar URL, bio, interests, workout categories, gym name, area, city, and
  connection status. Email, phone, address, coordinates, presence, and exact
  distance are neither selected nor returned.
- Feed visibility, profile visibility, and messaging each have their own
  server-side checks (`community_can_read_post`, `community_can_view_profile`,
  `community_can_message`).

### Connections, messaging, feed, and notifications

- A connection moves through `pending → accepted/declined`; either side can
  remove it. Messaging requires an accepted connection, and each accepted
  connection gets exactly one conversation.
- Messages are text and emoji sent through `community_send_message`, with
  server-side length, link rejection, block, suspension, and connection checks.
  The client sends an idempotency key and deduplicates retries. Threads load 40
  messages per page; unread counts come from per-conversation read state. Mute
  suppresses notifications without removing the conversation.
- The feed supports post kinds, optional achievement labels, optional sharing of
  an existing workout summary the author chooses, likes, comments, hide, and
  report. Nothing is auto-published from a completed workout.
- Notifications are in-app rows written by database triggers for connection
  requests and acceptance, messages, comments, and likes. Unread badges come
  from the server. One Realtime subscription per signed-in user refreshes the
  notification list and conversation timestamps; it does not open a channel per
  screen or per row. APNs is not configured in this build, and the settings
  screen says so.
- Search, lists, and threads paginate; the store debounces search and avoids
  duplicate in-flight loads.

### Safety and moderation

- Blocking is enforced server-side in discovery, connections, feed, profiles,
  and messaging. Reporting covers profiles, posts, comments, and messages.
- Age bands (`minor`, `adult`, `unknown`) are stored on the server and
  cross-band discovery, connections, and messaging are denied there. A
  client-supplied age is never trusted on its own.
- Admin access is checked by `community_is_admin` on every admin RPC; the app
  never sends an `isAdmin` flag. Admin screens can review reports, remove posts
  or comments, suspend or reinstate an account, review gym submissions, and read
  the moderation audit trail. Suspended accounts lose Community write access.
- Avatars are the only upload: JPEGs resized to at most 512 px, validated in the
  app, and written to the member's own folder in the `community-avatars` bucket.
  The bucket allows public reads (avatars appear in Community) and owner-only
  writes. Messaging v1 has no attachments, images, video, or link sharing.

## Camera form analysis

**Workouts → Camera form check** (and a Form check row during a mapped
exercise) opens an on-device analysis session for bodyweight squat, push-up,
lunge, or jumping jack. The setup screen explains camera placement, exercise
selection, framing, and privacy; the live screen shows the unmirrored preview,
a skeleton of reliably detected joints, rep count only while counting is
reliable, and measured observations; the summary lists duration, coverage,
validated reps when available, observations with the body points used, and
explicit limitations.

- Capture is `AVCaptureSession` at 720p with a serial, throttled Vision
  pipeline that drops frames rather than freezing the preview.
- Pose comes from `VNDetectHumanBodyPoseRequest`. It is Apple's general 2D body
  detector — not a trained exercise classifier, a form-scoring model, or a
  medical assessment. No 3D request or Core ML model is used in this build.
- Rep counting is a separate state machine with hysteresis, a settled start, a
  bottom hold, minimum duration, cooldown, and confidence gating. Partial, too
  fast, or ambiguous movement is rejected and stated rather than counted.
- When tracking is insufficient during a set the live screen displays exactly:
  *“Rep counting paused — body movement cannot be tracked reliably.”* If no
  reliable count was ever established, the summary displays exactly: *“Rep
  counting unavailable — movement could not be tracked reliably.”*
- A finished session is written to the same workout history as other workouts:
  a `workout_sessions` row plus one `form_analysis_sessions` row keyed by that
  session id. Validated reps are not duplicated as completed sets. RLS scopes
  every row to `auth.uid()`.
- If the backend cannot be reached the finished session is saved locally on the
  device and retried with an idempotent upsert on the next load, foreground
  refresh, manual refresh, or network reconnect.
- Frames are processed in memory and never recorded, saved, uploaded, sent to a
  model, or shared to Community. Joint coordinates never leave the process.
- 2D analysis has **not** been validated on a physical device in this build. The
  setup and summary screens state that factual limitation. The Simulator has no
  camera and only verifies permission and honest unavailability. See
  `native/SETUP.md` for the physical-device test checklist.

## Home Screen widget

`FormaWidgets` is a real WidgetKit extension embedded in the app. It offers
**Fitness Command Center** in the small, medium, and large system families:

- **Small** — today's focus with status, exercise and set counts, duration, and
  weekly goal progress. A configuration intent lets the owner choose automatic,
  today, weekly, or consistency emphasis.
- **Medium** — today plus the current week: goal, completed and remaining
  sessions, actual minutes, a real seven-day chart, and a quick action.
- **Large** — today, weekly ring, last-seven-days chart, streak, and Community
  counts when the signed-in account has any. Community shows pending request and
  unread message/notification **counts only** — never message text, member
  names, gym details, or notification bodies.

Data flows through the `group.forma.coach` App Group, not through a second
workout system. `WidgetPublisher` builds a compact, account-scoped
`WidgetSnapshot` from the same `WorkoutPlan`, `Preferences`, `WorkoutSession`,
`TrainingStats`, and `ActiveWorkout` records the app uses, then asks
`WidgetCenter` to reload after real changes: data loads, onboarding, plan edits,
preference changes, workout start/finish/discard, form-analysis saves, and
Community count changes. The extension never calls the network and never walks
workout history. The timeline refreshes at the next local midnight so "today"
and the seven-day strip roll over; app-driven reloads handle everything else. An
old snapshot is labelled with its age rather than presented as live.

Deep links reuse the existing navigation: today, start workout, workouts (plan),
progress, Community, connection requests, and messages. `start-workout` opens
Home and starts the genuine active-workout flow; it never marks a workout
complete. Auth callback URLs are still handled before navigation routing.

There are no fabricated values. With no plan the widget shows a real empty state
and an "Open Forma" action; with no history the chart is empty; rest days,
unscheduled days, completed days, in-progress workouts, and missing or expired
snapshots each have their own state.

Provisioning: enable the `group.forma.coach` App Group for both `forma.coach`
and `forma.coach.widgets` in the Apple Developer portal, then regenerate
profiles. Simulator builds embed the entitlement; a physical device needs
matching profiles. See `native/SETUP.md`.

## Tests

### Native unit tests

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -only-testing:FormaTests
```

`LiveBackendTests` signs in to a real project and calls the deployed Community
RPCs. They **skip** unless `FORMA_SUPABASE_URL`, `FORMA_ANON_KEY`,
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

## Security

- Only the anon key ships in the app. RLS scopes every row to `auth.uid()`.
- The service-role key exists only inside the `delete-account` Edge Function
  runtime, never in the app.
- Auth sessions are Keychain-backed and cleared on sign out or account deletion.
- Health data is read on demand; it is never logged or uploaded.
- Community mutations are RPC-only and re-check blocks, suspension, age
  compatibility, privacy switches, and connection state on the server.
- Admin actions re-check `community_is_admin` on every call; no client flag can
  grant moderation access.
- Legacy AI conversation data is archived in a schema revoked from app roles,
  not exposed through the API.
- Camera frames, audio, video, and joint coordinates never leave the device or
  reach disk.

## Verification status

Last verified in this repository (2026-11-18):

- `FormaTests`: 147 executed, 4 skipped (`LiveBackendTests`), 0 failures. That
  includes 36 widget tests (snapshot encode/decode, schema and corruption
  rejection, account isolation, Community count overlay and change detection,
  builder accuracy for every today state and weekly metric, timeline refresh and
  freshness logic, deep-link parsing, and an App Group round-trip) plus 11
  Community model-decoding tests and the form-analysis suites. The form-analysis
  suites use synthetic pose fixtures; they prove the pipeline, recorder,
  persistence, and offline-queue logic, not camera or pose accuracy.
- `FormaUITests`: passed end to end on a clean install (128 s), covering
  onboarding, all five tabs, the preview Community honest state, workout
  logging, reminders, relaunch persistence, and the camera-unavailable setup
  screen.
- Debug and Release builds: succeeded, including the embedded
  `FormaWidgets.appex`. PlugInKit lists `forma.coach.widgets` as a WidgetKit
  extension, and the `group.forma.coach` container resolves on the Simulator.
- End-to-end widget data: after the UI test completed preview onboarding and a
  workout, the shared App Group contained a real snapshot (preview account,
  completed session title, 5 exercises, 10 sets, real weekly goal and seven-day
  records, streak and reps) written by the app — no fabricated values.
- Home Screen widget **placement and pixel rendering in the iOS widget gallery
  were not verified**: the Simulator provides no supported command to add a
  widget from the gallery. Physical-device behaviour is also unverified.
- Live Supabase behavior — migrations, RLS, RPC enforcement, Realtime, storage,
  and the privacy checks in `LiveBackendTests` — is **not verified** in this
  checkout because no project credentials were available. The live tests skip
  and say so.

## Limitations

- Local notifications only; APNs is not configured.
- Realtime requires the project to have it enabled; otherwise lists and badges
  refresh on load and pull-to-refresh instead of live.
- Community requires a real Supabase project. Preview mode intentionally shows
  none of it.
- The legacy Expo prototype in `src/` is not the shipping client and was not
  migrated to Community.
- Camera form analysis has **not** been validated on a physical device. The
  Simulator has no camera, so real keypoint accuracy, skeleton alignment, and
  rep-count reliability are untested in this checkout.
- Form analysis uses 2D Vision pose only. There is no trained exercise classifier,
  no 3D pose, no automatic exercise identification, and no form score.
- The widget has not been placed on a Home Screen or visually inspected in the
  widget gallery in this checkout; the Simulator offers no supported CLI for
  that. Extension registration, App Group sharing, snapshot contents, and the
  app-side reload triggers are verified, but layout at every Dynamic Type size,
  light/dark rendering on device, and widget-specific performance still need a
  physical-device pass. Lock Screen accessory families are not implemented.
