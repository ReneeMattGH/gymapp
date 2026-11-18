# Forma — native iOS setup

Forma is a SwiftUI app that talks to Supabase for auth, sync, and Community, and
keeps training plans, form analysis, and workout history on-device or in the
user's own rows. No keys ship in the repository. Without them the app builds and
runs in an honest **Setup required** state; a debug build can also run a local,
clearly labelled preview mode.

## Requirements

- Xcode 26 or newer (iOS 18.0 deployment target, iPhone only)
- An Apple ID for simulator builds; a paid team for a device build
- A Supabase project (free tier is enough)

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
local training data. It is not a fake backend; it is a separate local repository
that is reset when you exit preview from Profile. Community is disabled in
preview mode and says so, because preview data contains no real accounts.

## 2. Create the Supabase project

1. Create a project at <https://supabase.com>.
2. Apply the schema, policies, and exercise seed:

   ```bash
   supabase link --project-ref <your-project-ref>
   supabase db push          # runs every file in supabase/migrations, in order
   ```

   Or paste the files from `supabase/migrations/` into the SQL editor in
   filename order. Migration `0004_ai_memory_and_realtime.sql` created the old AI
   memory tables, added exercise provenance (`exercise_library.source`), set
   replica identity on the synced training tables, and published them to
   Realtime. `0008_remove_ai_coach.sql` archives and drops the AI tables but
   keeps the training columns and publication. Migration
   `0005_ai_knowledge_and_usage.sql` is historical: it created the pgvector
   knowledge and usage tables, which `0008` archives and removes. Migration
   `0006_form_analysis.sql` adds the one-to-one `form_analysis_sessions` table
   for camera sessions (RLS, cascade from `workout_sessions`, Realtime).
   Migration `0007_community.sql` adds gyms, Chennai area reference data,
   profiles, preferences, memberships, account status, blocks, connections,
   conversations, messages, read state, mutes, posts, likes, comments, hidden
   posts, reports, admins, moderation actions, notifications, all Community RPCs,
   RLS, the `community-avatars` storage bucket, and its Realtime publication.

3. **Realtime.** Two things subscribe to Realtime: the per-user training channel
   on `workout_plans`, `workout_sessions`, `completed_sets`, and
   `user_preferences`, and a single per-user Community channel on
   `community_notifications`. If Realtime is disabled at the project level the
   app still works: the Home header shows **Cached** instead of **Live**, and
   Community lists and badges refresh on load and pull-to-refresh.

4. In **Authentication → URL configuration**, add `forma://auth-callback` as an
   allowed redirect URL. Email confirmation and password recovery both use it.

5. **Community staff access.** Community starts with no administrators. After you
   have created your own account, grant yourself moderator access in the SQL
   editor:

   ```sql
   insert into public.community_admins (user_id, note)
   select id, 'initial admin' from auth.users where email = 'you@example.com'
   on conflict (user_id) do nothing;
   ```

   `community_admins` has RLS with no client policies and its grants are revoked
   from `anon` and `authenticated`, so this must be done server-side. Every admin
   RPC re-checks membership in this table; the app never sends an `isAdmin` flag.
   Remove the row to revoke access.

6. **Gyms.** No gyms are seeded on purpose: listing a gym is a real-world claim.
   Members search existing rows, request a gym, and an admin approves it. Seeded
   Chennai areas are only coarse area groups and contain no member data. To add
   verified gyms directly:

   ```sql
   insert into public.gyms (name, city, area, address, verification_status)
   values ('Example Strength Club', 'Chennai', 'Adyar', '1 Example Road', 'verified')
   on conflict do nothing;
   ```

   Duplicate requests are detected by normalized name and city in
   `community_request_gym`.

## 3. Deploy the Edge Function

```bash
supabase functions deploy delete-account
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
provided by the Edge runtime; do not hardcode them. The service-role key exists
only inside that function and is never shipped in the app. `supabase/.env.example`
documents that Community and account deletion need no custom secrets.

### Community writes

Community needs no Edge Functions. Every mutation is a `SECURITY DEFINER` RPC in
`0007_community.sql` that authenticates the caller and re-checks blocks,
suspension, age-band compatibility, privacy switches, and connection state
server-side. Direct table access is SELECT-only under RLS. The app cannot write
another member's rows or read private contact data, because those columns are not
selected or returned by any RPC.

- Avatars upload to the `community-avatars` bucket. Reads are public to signed-in
  clients through a storage policy; writes are restricted to the caller's own
  `auth.uid()` folder. The app resizes to at most 512 px and rejects files over
  4 MB before upload.
- Notifications are written by database triggers for connection requests and
  acceptance, messages, comments, and likes. The app opens one per-user Realtime
  channel; it never opens a channel per screen or per row.
- Messaging v1 accepts text and emoji only. The server rejects links and there is
  no attachment or image path.
- Age bands (`minor`, `adult`, `unknown`) are derived and stored server-side.
  Cross-band discovery, connections, and messaging are denied on the server; the
  client does not decide compatibility.

## 4. Point the app at the project

Set these Xcode build settings (target **Forma** → Build Settings → + Add User-
Defined Setting), or pass them on the command line:

| Setting | Value |
| --- | --- |
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | the project's anon/publishable key |

They flow into `Info.plist` as `SUPABASE_URL` / `SUPABASE_ANON_KEY` and are read
by `AppConfig`. Never add a service-role key to the app target.

Build again. The Setup required screen is replaced by email sign-up/sign-in.
After confirming your email, onboarding collects training details, generates a
plan on-device, and syncs it to Supabase.

## 5. Device signing and notifications

- Select your team under **Signing & Capabilities** for the Forma target.
- The bundle id is `forma.coach`; change it if it is already taken.
- The app embeds the `FormaWidgets` extension (`forma.coach.widgets`). Both
  targets use the App Group **`group.forma.coach`**, declared in
  `Forma/Forma.entitlements` and `FormaWidgets/FormaWidgets.entitlements`.
- Enable that App Group for **both** App IDs in the Apple Developer portal and
  regenerate provisioning profiles. Without it the app builds, but the widget
  cannot read the snapshot on a device.
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

## 7. Camera form analysis

The camera form check is entered from **Workouts → Camera form check**, or from
the Form check row inside an active workout when the current movement has a
matching analysis (bodyweight squat, push-up, walking lunge). Jumping jack is
available from the setup screen even though no catalog exercise maps to it.

What is implemented:

- `AVCaptureSession` at 720p with a video-data output, a serial analysis
  pipeline, frame dropping, and 10 fps throttling (slower when the device is
  warm). The preview keeps rendering while analysis drops frames.
- Apple Vision 2D body pose (`VNDetectHumanBodyPoseRequest`). This is Apple's
  general body detector, **not** a trained exercise classifier. No 3D request
  and no Core ML model are integrated in this build.
- Exercise-specific analysers for squat, push-up, lunge, and jumping jack using
  only the joints each movement needs. Rep counting is a separate state machine
  (settled start → descending → bottom hold → ascending → completed) with
  hysteresis, minimum duration, cooldown, and confidence gating.
- Feedback is measured-only, labelled observed / limited / unavailable, and
  lists the body points used and the measured values. There is no form score and
  no injury or risk claim. While tracking is insufficient the live screen shows
  exactly: **“Rep counting paused — body movement cannot be tracked reliably.”**
  If no reliable count was established for the whole session, the summary shows
  exactly: **“Rep counting unavailable — movement could not be tracked
  reliably.”**
- A finished session is saved to the existing workout history: a
  `workout_sessions` row (no completed sets) plus a one-to-one
  `form_analysis_sessions` row from migration `0006_form_analysis.sql`. RLS
  restricts both to `user_id = auth.uid()`. If the write fails, the session is
  queued in `Application Support/Forma` for that user, merged into history
  immediately, and retried with an idempotent upsert on the next load, foreground
  refresh, manual refresh, or network reconnect. Only session metadata and
  measured observations are queued — never frames or keypoints.

The required `NSCameraUsageDescription` is in `Info.plist`. Analysis is opt-in
and can be denied without affecting the rest of the app.

### Privacy

Frames are analysed in memory on the device. Nothing is recorded, written to
disk, uploaded to Supabase, or shared with any other service. Joint coordinates
never leave the process. The summary screen shows only measured text (exercise,
duration, counted reps, coverage, measured observations, limitations) — never
images, video, frames, or keypoints. The pipeline releases the camera on pause,
end, backgrounding, and screen dismissal.

The only camera-derived data that is persisted is the structured session record
described above (rep count, availability, coverage, interruptions, observation
text, measured values, limitations). The offline retry queue lives in the app's
Application Support directory and is scoped per user; it is removed after a
successful sync or sign-out.

### Validation status — physical device required

The Simulator has no camera, so it only verifies the permission and
camera-unavailable paths. **Pose accuracy, overlay alignment, lighting and
occlusion handling, and rep-count reliability have not been validated on a
physical iPhone in this build.** The UI states this limitation factually in the
setup and summary screens, and no production-accuracy claim is made. A
real-device pass must still cover:

1. Front and rear camera at the documented distances and angles for each
   exercise, checking that the skeleton lines up with the body at the edges of
   the frame (aspect-fill mapping) and in both camera positions.
2. Squat / push-up / lunge / jumping jack sets at normal, slow, and fast tempos,
   confirming that deliberate partial reps are rejected rather than counted.
3. Poor lighting, motion blur, loose clothing, partial occlusion, one person
   leaving and re-entering, and a second person entering the frame.
4. Backgrounding, phone-call-style camera interruptions, pause/resume, thermal
   throttling, and ending the session.
5. Comparing the app's per-rep observations against manual video review before
   calling any exercise “validated”. Until then, treat counts and observations
   as experimental even when they look plausible.

## 8. Home Screen widget

`FormaWidgets` is a WidgetKit app extension embedded in Forma. It supplies
**Fitness Command Center** in the `systemSmall`, `systemMedium`, and
`systemLarge` families. The widget is available from the iOS widget gallery at
runtime; the extension target is `forma.coach.widgets` and its extension point
is `com.apple.widgetkit-extension`.

### Shared data

The app and extension both compile `native/Shared/` and communicate through the
App Group `group.forma.coach`:

| Type | Responsibility |
| --- | --- |
| `WidgetSnapshot` | Codable, versioned, account-scoped summary of plan, today, week, streak, totals and Community counts |
| `WidgetSharedDataStore` | App Group codec, schema/account validation, Community-count overlay |
| `WidgetTimelineLogic` | Next-midnight refresh date, freshness label, staleness threshold |
| `WidgetSnapshotBuilder` (app) | Builds the snapshot from `WorkoutPlan`, `Preferences`, `WorkoutSession`, `TrainingStats`, and `ActiveWorkout` |
| `WidgetPublisher` (app) | Saves the snapshot, clears it on sign-out, reloads the widget after real changes |

The training snapshot and Community counts are stored under separate keys.
Counts carry the account id they belong to; a snapshot only overlays counts for
its own account, so a late or early Community write cannot leak across accounts
or depend on write order. Sign-out, account deletion, and preview exit clear the
shared state.

The widget performs no network requests. The app reloads the timeline after
onboarding, plan or preference changes, workout start/finish/discard,
form-analysis saves, data loads, and changes in Community counts. The timeline
also refreshes at the next local midnight.

### Deep links

The extension uses the app's existing `forma://` routes:

```
forma://today
forma://start-workout
forma://workouts      (forma://plan also maps here)
forma://progress
forma://community
forma://community/requests
forma://community/messages
```

`start-workout` routes through the existing Home flow and starts a real
`ActiveWorkout`; it does not write a completed session. Auth callback URLs are
handled before navigation parsing and are rejected by the navigation deep-link
parser.

### Configuration

The small family supports a `WidgetConfigurationIntent` with automatic, today,
weekly, and consistency emphasis. Medium and large always show their full
layout. All families support light and dark appearances and derive every value
from the snapshot.

### Privacy

The widget shows only workout summaries and Community **counts**. Message text,
member identities, gym details, notification bodies, health data, location, and
API keys are never written to the shared container. The snapshot contains only
the signed-in account's id.

### Testing

- `FormaTests` covers the codec, schema versioning, corrupt and missing data,
  account isolation, count change detection, builder accuracy for every today
  state, weekly totals, streak, reps, timeline/freshness logic, deep links, and
  an App Group round-trip.
- The extension is registered by PlugInKit and the App Group container resolves
  on the Simulator.
- Adding a widget from the iOS gallery cannot be automated with `simctl`, so
  gallery placement and rendering are not verified by the automated tests. Do a
  physical-device pass:

1. Install a signed build via Xcode, then long-press the Home Screen → **+** →
   search **Forma** → add small, medium, and large.
2. Complete onboarding and a workout; confirm counts, minutes, goal, streak, and
   the seven-day chart match the app.
3. Check rest day, unscheduled day, no-plan, and no-history states, plus light
   and dark appearance and larger Dynamic Type sizes.
4. Tap each family and each Community count row to confirm the correct tab or
   screen opens.
5. Sign out and confirm the widget returns to the empty state instead of showing
   the previous account.
6. Background the app after a change and confirm the widget refreshes; leave it
   overnight to confirm the date-based rollover.

## 9. Tests

`FormaTests` is a hosted unit-test target covering the plan validator (schedule,
duration, equipment, duplicates, safe volume), exercise search/filtering/
pagination, Community JSON decoding and defaults, and the form-analysis core:
pose geometry and confidence filtering, smoothing, rep-state transitions,
incomplete-rep rejection, per-exercise analysers, feedback wording, the
pipeline with a scripted pose detector, the session recorder, preview-to-view
alignment, the view model's permission/camera/pause paths, availability
classification, and the saved-session record, per-user offline queue and
rep-total logic. It also covers the widget data layer: snapshot
encode/decode, schema and corruption rejection, account isolation, Community
count overlay and change detection, builder output for no-plan/rest/workout/
completed/in-progress/not-scheduled days, weekly totals, streak, reps, timeline
refresh and freshness, deep-link parsing, and an App Group round-trip.
All form-analysis tests use synthetic pose fixtures; synthetic fixtures prove the
logic, not real-world accuracy. The Community model tests prove decoding and
display logic against representative payloads, not live backend behavior. Run it
alone with:

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -only-testing:FormaTests
```

`LiveBackendTests` in the same target signs in to a real project and checks the
deployed Community RPCs: the bootstrap payload, discovery privacy (no contact or
location fields), messaging denial without a connection, and admin RPC rejection
for non-admins. They **skip** unless all four variables are set, and a skip is
not evidence that the backend works:

```bash
FORMA_SUPABASE_URL=https://<ref>.supabase.co \
FORMA_ANON_KEY=<anon-key> \
FORMA_TEST_EMAIL=<confirmed-test-user> \
FORMA_TEST_PASSWORD=<password> \
  xcodebuild test ... -only-testing:FormaTests/LiveBackendTests
```

`FormaUITests` drives the real app end-to-end on a simulator: setup screen,
preview entry, the seven preview onboarding steps (an optional eighth Community
step appears only with a real backend and account), plan generation, all five
tabs (including the honest preview Community state), logging a set with the rest
timer, backgrounding and reactivation, finishing and saving the session,
reminders scheduling with the system permission prompt, launch persistence, and
the camera form-check setup screen (including the honest “camera unavailable”
state on the Simulator).

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -resultBundlePath /tmp/forma-uitests.xcresult
```

The test needs a clean install to exercise the setup screen:

```bash
xcrun simctl uninstall <device-udid> forma.coach
```

Screenshots are attached to the result bundle and can be exported with
`xcrun xcresulttool export attachments`.

## 10. Project layout

```
native/Forma/
  Core/        AppConfig, models, formatters, theme tokens
  UI/          Shared components
  Store/       AppModel (@Observable, @MainActor)
  Services/    Supabase, HealthKit, notifications, plan engine, storage
  Community/   Models, service, store, root/home/discover/connections,
               messages, feed, profile/settings, notifications, admin
  FormAnalysis/ Camera, Vision pose, analysers, rep engine, feedback, session
  Widget/      WidgetSnapshotBuilder, WidgetPublisher, AppModel extensions
  Screens/     Root, onboarding, tabs, workout, library, settings
  Resources/   Fonts, exercise catalog
native/Shared/          WidgetSnapshot, WidgetSharedDataStore,
                        WidgetTimelineLogic (compiled into both targets)
native/FormaWidgets/    WidgetKit extension: bundle, timeline, configuration
                        intent, views, theme
native/FormaTests/      Hosted unit tests
native/FormaUITests/    XCUITest coverage
supabase/               Migrations and the delete-account Edge Function
```

## Security checklist

- Only the anon/publishable key is in the app; RLS restricts every table to the
  signed-in user or to data a Community RPC deliberately exposes.
- The service-role key exists only inside the `delete-account` Edge Function
  runtime.
- Auth sessions are persisted by the Supabase SDK (Keychain-backed) and cleared
  on sign out or account deletion.
- Health data is read on demand and is never logged or uploaded.
- Community mutations are RPC-only and re-check blocks, suspension, age-band
  compatibility, privacy switches, and connection state on the server.
- Admin RPCs re-check `community_admins` on every call; the client cannot grant
  itself moderation access.
- Discovery, feed, profile, and messaging RPCs never return email, phone,
  address, coordinates, presence, or exact distance.
- The widget App Group contains only a compact account-scoped training summary
  and Community counts. It never contains message text, notification bodies,
  health data, location, or credentials, and the snapshot is cleared on sign-out,
  account change, or account deletion.
- Community never requests location permission and never runs background
  location tracking.
- Messaging v1 is text and emoji only; the server rejects links and there is no
  attachment or image path. Avatars are the only upload and are owner-scoped.
- Legacy AI conversation data is archived in `archive_ai_coach`, a schema with
  all grants revoked from `anon` and `authenticated`.
- Camera frames, audio, video, and joint coordinates stay in memory. Nothing is
  uploaded or written to disk, and no recording permission is requested.
