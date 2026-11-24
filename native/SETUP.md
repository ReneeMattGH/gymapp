# Forma — native iOS setup

Forma is a fully native SwiftUI app with two independent data domains:

| Domain | Where it lives | Owned by |
| --- | --- | --- |
| Training profile, plan, workout history, form-analysis sessions, reminders, check-ins | On-device SQLite (`Application Support/Forma/forma.sqlite`) | The app |
| Account, sessions, Community (profiles, gyms, connections, messages, posts, moderation, notifications) | PostgreSQL behind the Node/TypeScript backend in `backend/` | The backend |

There is no Supabase, no Expo/React Native runtime, and no third-party auth SDK in
the shipping client. Signing in to a Forma account adds Community and account
features; it never moves, merges, or rewrites on-device training data.

A build with no backend URL is still a complete training app. Only the Account
and Community screens become unavailable, and they say why instead of inventing
members, posts, or deliveries.

## Requirements

- Xcode 26 or newer (iOS 18.0 deployment target, iPhone only)
- Node.js 22 or newer (Node 24 is what this tree was tested with)
- PostgreSQL 14+ running locally (trust auth is fine for development)
- An Apple ID for simulator builds; a paid team for a device build

## 1. Build and run the app as-is

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' build
```

Open `Forma.xcodeproj`, pick a simulator, and Run. Debug builds read
`FORMA_API_URL = http://localhost:8787` from the target build settings. Release
builds leave it empty, so a release-shaped build has no backend until you set a
real origin.

On first launch the app creates `forma.sqlite`, seeds the exercise catalog, and
opens onboarding. No account is needed.

## 2. Create the database and run the backend

```bash
createdb forma_dev
createdb forma_test      # used only by the backend test suite

cd backend
npm install
cp .env.example .env     # adjust DATABASE_URL if your Postgres differs
npm run migrate          # applies src/db/migrations in order
npm run dev              # tsx watch on http://localhost:8787
```

`AUTO_MIGRATE=true` (the default in `.env.example`) also applies pending
migrations on boot, so `npm run migrate` is optional for local work and should
stay an explicit deploy step in production. Boot then verifies that every
migration in this build is recorded and that the critical tables and columns
exist; an incompatible database is reported and the process exits instead of
serving traffic that would fail later with SQL errors.

Check it:

```bash
curl -s http://localhost:8787/health
# {"status":"ok","database":"up","time":"..."}
```

Health is at `/health`; every other route is under `/api/v1`.

### Email delivery

Verification and password-reset email require `SMTP_URL`. Without it those
endpoints answer `503` and say mail is not configured; the backend never
pretends an email was sent. Community notifications are in-app rows delivered
over the authenticated socket, so they need no mail service.

### Community moderators

`COMMUNITY_ADMIN_EMAILS` is a comma-separated allowlist. An account whose email
is in that list receives the admin role in Community. Every admin route re-checks
the list server-side; the client never sends an `isAdmin` flag. Change the value
and restart the backend to grant or revoke access.

### Avatar uploads

`UPLOAD_DIR` (default `./uploads`) receives avatar files. The backend serves them
at `/uploads/<file>`; set `PUBLIC_BASE_URL` to an absolute origin if the API is
reached through a different host so returned URLs stay absolute. `backend/uploads/`
is ignored by git.

## 3. Point the app at the backend

The app reads `FORMA_API_URL` from `Info.plist`, which expands the user-defined
build setting of the same name. A `FORMA_API_URL` entry in the launch
environment overrides it, so a device build can be pointed at a LAN address
from the Xcode scheme (Product → Scheme → Edit Scheme → Run → Arguments →
Environment Variables) without changing the target:

```text
FORMA_API_URL = http://192.168.1.20:8787/   # replace with your Mac's LAN address
```

- Simulator talking to a backend on the Mac: `http://localhost:8787` (already the
  Debug default).
- Physical device: use the Mac's LAN address, e.g. `http://192.168.1.20:8787`.
  `localhost` on a phone is the phone itself, so requests to the Debug default
  can never reach your Mac. The backend must also bind an interface the phone can
  reach (`HOST=0.0.0.0` or the LAN address) and macOS firewall must allow it.
- Production: an HTTPS origin. Set `FORMA_BUILD_CHANNEL` to the channel name you
  want shown in the app.

When a build points at a loopback host while running on a physical device, the
Account screen shows one banner saying exactly that instead of a generic network
error.

### Building for a physical iPhone

1. Put the Mac and the iPhone on the same Wi-Fi network. The app reaches your Mac
   over the network; the USB cable only installs and launches it.
2. Read the Mac's LAN address:

   ```bash
   ipconfig getifaddr en0     # e.g. 192.168.137.64
   ```

3. Bake that origin into the build. A launch-environment variable only applies
   when Xcode launches the app, so an app installed from the Home Screen or with
   `devicectl` needs the build setting:

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
   xcodebuild -project Forma.xcodeproj -scheme Forma -configuration Debug \
     -destination "platform=iOS,id=<device-udid>" \
     -allowProvisioningUpdates \
     FORMA_API_URL="http://192.168.137.64:8787" build
   ```

   `-destination` uses the hardware UDID (`00008101-…`), not the CoreDevice UUID
   that `xcrun devicectl list devices` prints.

4. Keep the backend on `HOST=0.0.0.0` and make sure macOS does not block Node.
   An explicit "Block incoming connections" firewall rule resets LAN requests
   before Express sees them (the symptom is an empty reply, not a timeout):

   ```bash
   /usr/libexec/ApplicationFirewall/socketfilterfw --listapps | grep -A1 node
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$(which node)"
   ```

5. On first launch iOS asks for local-network permission
   (`NSLocalNetworkUsageDescription`); allow it.
6. Test the network path from the phone itself before blaming the app: open
   `http://<mac-lan-ip>:8787/health` in Safari and expect
   `{"status":"ok","database":"up"…}`.

7. Production: deploy the backend behind HTTPS and pass that origin at build
   time (`FORMA_API_URL="https://api.example.com"`). Never ship `localhost` or a
   LAN address in Release. Release defaults to an empty URL, which shows accounts
   as unavailable instead of failing at runtime.

## 4. Accounts and authentication

- Registration, login, refresh, logout, email verification, resend
  verification, password change, password reset, and account deletion.
- Passwords are hashed with Argon2id. Verification and reset tokens are random,
  single-use, stored only as SHA-256 hashes, and expire.
- Access and refresh tokens are opaque random strings; only their hashes are
  stored. Access tokens live 60 minutes (`ACCESS_TOKEN_TTL_MINUTES`); the
  session and its refresh tokens live 30 days (`REFRESH_TOKEN_TTL_DAYS`) and
  slide forward on every rotation. A session therefore survives a cold start a
  day later by refreshing, even though its access token expired.
- Refresh rotates the pair and revokes the previous refresh token; presenting a
  rotated token again kills the session. Logout, password change, and account
  deletion revoke sessions server-side, and an open Community socket is
  disconnected within a minute of its session being revoked or its access token
  expiring.
- The client stores tokens in the Keychain (`coach.forma.tokens`), never in
  UserDefaults or SQLite. `APIClient` refreshes proactively when the access
  token is within 30 seconds of expiry and also on a 401 (single-flight), then
  retries; a failed refresh clears the session.
- Account deletion requires the current password and removes the account and its
  Community data server-side. On-device training data is not touched.

## 5. Community

Community is served only by the backend. The iOS client talks to
`/api/v1/community/...` and opens one authenticated Socket.IO connection per
signed-in user. A connection only joins its own `user:<id>` room, so a member
cannot subscribe to another member's stream.

| Concern | Server enforcement |
| --- | --- |
| Blocks | Discovery, connections, profiles, feed, and messaging filter and reject blocked pairs |
| Age bands | Both accounts must be known and in the same band for discovery, connections, and messaging |
| Suspension | Read-only access; writes are rejected |
| Privacy | A profile must be discoverable; gym/area visibility is a separate switch |
| Connections | `pending → accepted/declined`; messaging requires accepted |
| Moderation | Reports, post/comment removal, suspension, gym review, audit log |
| Rate limits | Login/register/reset are tightly limited; general API is limited too |

Socket events are `ready` (handshake confirmation), `notification`, `activity`
(connection and post activity), and `message`. The client reconnects with
backoff, resubscribes, and reloads lists on reconnect; REST remains the source of
truth so a missed event delays a refresh but never corrupts state.

Gyms come from the server-side directory provider and member submissions; no
gyms are seeded. Discovery covers gym, neighborhood, city, region, country, and
Global scope, and never requests location permission on its own.

Provider configuration (all optional, backend `.env`):

| Variable | Behavior |
| --- | --- |
| `GYM_PROVIDER` | `auto` (default), `google`, `osm`, or `none` |
| `GOOGLE_PLACES_API_KEY` | Enables Google Places under `auto`/`google`; without it nearby falls back to OpenStreetMap |
| `OSM_TEXT_SEARCH` | OSM nearby search works with no key; global OSM name search needs `true` or a self-hosted Overpass |
| `GYM_PROVIDER_TIMEOUT_MS` | Outbound provider timeout, default `12000` |

With no usable provider the gym search endpoints answer
`503 gym_directory_unavailable`; database search and member-submitted gyms keep
working. "Near me" asks for a one-time location fix only after a tap, sends the
coordinate solely to the directory to rank by distance, and never stores it on
the profile.

## 6. On-device data and offline behavior

- SQLite through GRDB, WAL journal, foreign keys on, 5-second busy timeout.
- **The SQLite file is not encrypted.** Forma does not use SQLCipher or a custom
  encryption layer. It relies on the iOS app sandbox and system data protection;
  anyone with the device passcode or an unlocked backup can read it. Do not
  describe local storage as encrypted.
- Completing a workout, logging a check-in, editing reminders, and saving a form
  analysis work with no network.
- Community, account screens, and avatars require the backend. Their empty and
  failure states say so; nothing is queued for fake delivery and no remote write
  is claimed while offline.

## 7. Apple Health

Opt-in from Profile → Apple Health. Read-only access to workouts, active energy,
steps, and heart rate. HealthKit does not reveal read authorization, so Forma
reports what a fetch actually returned and labels the source. Nothing is written
to Health, logged, or uploaded.

## 8. Camera form analysis

Entered from **Workouts → Camera form check**, or the form row inside an active
workout for a mapped movement.

- `AVCaptureSession` at 720p with a serial, throttled Vision pipeline that drops
  frames instead of freezing the preview.
- `VNDetectHumanBodyPoseRequest` is Apple's general 2D body detector, not a
  trained exercise classifier. No 3D pose and no Core ML model.
- Rep counting is a separate state machine with hysteresis, a settled start, a
  bottom hold, minimum duration, cooldown, and confidence gating.
- Feedback is measured-only and labelled observed / limited / unavailable.
  There is no form score and no injury or risk claim.
- Finished sessions are stored in the local database as a workout session plus a
  one-to-one form-analysis record. No frames or joint coordinates are kept.

Frames are analysed in memory, never recorded, uploaded, or shared. The
Simulator has no camera, so it verifies only the permission and
camera-unavailable paths.

### Validation status — physical device required

Pose accuracy, overlay alignment, lighting/occlusion handling, and rep-count
reliability have **not** been validated on a physical iPhone. A device pass must
cover framing at the documented distances, partial and fast reps, poor lighting,
motion blur, loose clothing, occlusion, a second person entering the frame,
camera interruptions, thermal throttling, and pause/resume.

## 9. Home Screen widget

`FormaWidgets` (bundle `forma.coach.widgets`) supplies **Fitness Command
Center** in `systemSmall`, `systemMedium`, and `systemLarge`. It reads a compact,
account-scoped `WidgetSnapshot` from the App Group `group.forma.coach`; it never
calls the network and never walks workout history. The timeline refreshes at the
next local midnight.

The snapshot contains training summary values and Community **counts** only —
never message text, member identities, gym details, notification bodies, health
data, location, or credentials. Sign-out and account deletion clear it.

Provisioning: enable the App Group for both `forma.coach` and
`forma.coach.widgets` in the Apple Developer portal and regenerate profiles.
Simulator builds embed the entitlement.

## 10. Tests

### Backend

```bash
cd backend
TEST_DATABASE_URL=postgres://localhost:5432/forma_test npm test
npm run typecheck
```

The suite runs the real HTTP app against PostgreSQL (`forma_test`), including
registration/login/refresh rotation/revocation, verification and reset flows via
a recording mailer, Community privacy and block enforcement, the connection
state machine, messaging dedupe, moderation and audit, gym verification, and a
real raw-WebSocket Socket.IO delivery test. Test files run serially because they
truncate shared tables.

### Native unit tests

```bash
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -only-testing:FormaTests
```

Covers the local SQLite layer, plan validation and generation, exercise search,
Community JSON decoding and display logic, form-analysis geometry/pipeline/
recorder/queue, and the widget snapshot/timeline layer. Form-analysis fixtures
are synthetic; they prove the logic, not camera accuracy.

### Native UI test

```bash
cd native
xcrun simctl uninstall <device-udid> forma.coach
xcrun simctl spawn <device-udid> defaults delete forma.coach forma.previewModeEnabled

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' \
  -resultBundlePath /tmp/forma-uitests.xcresult
```

With the backend reachable at `localhost:8787`, the test creates a real account
through the UI, signs out and back in, cold-launches the app and checks the
session is restored from the Keychain, verifies the live Community bootstrap,
opens the community profile editor, and deletes the account. Without it, the
account form is not submitted and the Community-unavailable copy is verified
instead.

`FORMA_TEST_API_URL` (passed as `TEST_RUNNER_FORMA_TEST_API_URL=...` to
`xcodebuild`) repoints both the reachability probe and the app's launch
environment, which also exercises the override a device build uses. Running a
second backend with `ACCESS_TOKEN_TTL_MINUTES=1` on another port is how the
refresh path is driven end to end without waiting an hour.

Screenshots are attached to the result bundle:

```bash
xcrun xcresulttool export attachments \
  --path /tmp/forma-uitests.xcresult --output-path /tmp/forma-ui-attachments
```

## 11. Device signing and notifications

- Select your team under **Signing & Capabilities** for the Forma target.
- The bundle id is `forma.coach`; change it if it is taken.
- The app embeds the `FormaWidgets` extension and both targets share
  `group.forma.coach` (see the entitlements files).
- Notifications are local calendar triggers; no push certificates are needed.
  iOS asks for permission when reminders are first saved. The Reminders screen
  reports what iOS actually has pending.

## 12. Project layout

```
backend/                 Node + TypeScript + Express + PostgreSQL + Socket.IO
  src/auth/              Argon2id, opaque tokens, middleware, mailer, routes
  src/community/         Community service, REST routes, Socket.IO realtime
  src/db/                Pool, advisory-locked migrator, SQL migrations
  tests/                 Integration tests against forma_test
native/
  Forma/
    Core/                AppConfig, models, formatters, theme, deep links
    Database/            GRDB database, migrations, records, local repository
    UI/                  Shared components
    Store/               AppModel (@Observable, @MainActor)
    Services/            APIClient, account, keychain, health, notifications,
                         plan engine, validator, profile photo store
    Community/           Models, API service + socket, store, all screens
    FormAnalysis/        Camera, Vision pose, analysers, rep engine, recorder
    Widget/              Snapshot builder and publisher
    Screens/             Root, onboarding, tabs, workout, library, settings
    Resources/           Fonts, exercise catalog
  Shared/                Widget snapshot, App Group store, timeline logic
  FormaWidgets/          WidgetKit extension
  FormaTests/            Hosted unit tests
  FormaUITests/          XCUITest coverage
```

## 13. Security checklist

- Passwords: Argon2id with per-user salts. Constant-time dummy verification
  equalises unknown-account timing.
- Tokens: opaque 256-bit values, stored as SHA-256 hashes; refresh rotation with
  revocation; sessions revoked on logout, password change, and deletion.
- Client tokens: Keychain only.
- Transport: TLS in production. The localhost default is development-only.
- Community: every read and write re-checks the signed-in identity, blocks,
  age-band compatibility, suspension, privacy switches, and connection state.
- Admin: allowlist re-checked per request.
- Discovery responses never include email, phone, address, coordinates,
  presence, or exact distance.
- Avatars are the only upload (JPEG/PNG, 5 MB server limit, 512 px client
  resize); messages are text and emoji only, and links are rejected.
- Camera frames and joint coordinates never leave the process.
- The widget App Group holds only a compact training summary and Community
  counts.

## 14. Known limitations and unverified areas

- The SQLite database is not encrypted.
- No push notifications (APNs); notifications are local reminders plus in-app
  Community rows.
- Training data is intentionally device-local and does not sync through the
  backend. Signing in never moves or merges it.
- SMTP delivery is not exercised against a real mail provider in this checkout;
  tests use a recording mailer.
- Camera/pose accuracy and rep reliability are unverified on a physical device.
- Widget gallery placement and pixel rendering cannot be driven by `simctl`;
  App Group sharing, snapshot contents, and app-side reload triggers are
  covered by tests, including an App Group round-trip.
- The repository still contains legacy `src/` (Expo prototype) and `supabase/`
  directories from the previous architecture; neither is compiled into or used
  by the native app.
