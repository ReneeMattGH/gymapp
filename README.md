# Forma

Forma is a native iOS training app written in SwiftUI, backed by its own Node.js
+ PostgreSQL service. Onboarding becomes a personal training plan; workouts run
with a live rest timer and every set is recorded in an on-device SQLite database.
Community — member discovery, connections, direct messages, posts, moderation —
runs on the backend and contains only real registered accounts. A camera form
check analyses body joints on-device with Apple Vision and reports only measured
observations. A WidgetKit extension mirrors the owner's real training week.

The app is fully usable without a backend or account. Only Account and Community
require the server, and both screens say so plainly rather than inventing members,
posts, or email delivery.

> Forma is training software, not medical care. It does not diagnose or treat
> injuries, and it tells the athlete to stop and seek a professional when they
> report pain or dizziness.

## Architecture

| Domain | Storage | Notes |
| --- | --- | --- |
| Profile, plan, workouts, sets, reminders, check-ins, form-analysis sessions | On-device SQLite (GRDB) | `Application Support/Forma/forma.sqlite`; WAL; foreign keys; **not encrypted** |
| Account, sessions, all Community data | PostgreSQL via `backend/` | Argon2id, opaque hashed tokens, server-side ownership |

- No Supabase, no Expo/React Native runtime, and no third-party auth SDK in the
  shipping client.
- Signing in never moves, merges, or rewrites on-device training data.
- Community data is never merged into the local database implicitly.

## Repository layout

```
backend/               Node 22+ TypeScript, Express 5, PostgreSQL, Socket.IO
  src/auth/            Argon2id, opaque tokens, mailer, routes, middleware
  src/community/       Service, REST routes, authenticated realtime
  src/db/              Pool, advisory-locked migrator, SQL migrations
  tests/               Integration tests (real Postgres + raw WebSocket)
native/                Native SwiftUI app (the shipping client)
  Forma/               Core, Database, UI, Store, Services, Community,
                       FormAnalysis, Widget, Screens, Resources
  FormaWidgets/        WidgetKit extension: Fitness Command Center
  Shared/              Widget snapshot, App Group store, timeline helpers
  FormaTests/          Hosted unit tests
  FormaUITests/        End-to-end XCUITest coverage
  SETUP.md             Authoritative setup, backend, and test guide
src/                   Legacy Expo prototype (not shipped, not compiled)
supabase/              Previous architecture, retained on disk, unused
```

`native/SETUP.md` is the authoritative guide. This README is a summary.

## Build and run

Requirements: Xcode 26+, iOS 18.0 deployment target, iPhone only. For Community:
Node 22+, PostgreSQL 14+.

```bash
createdb forma_dev
cd backend && npm install && cp .env.example .env && npm run dev

cd ../native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' build
```

Debug builds point at `http://localhost:8787` through the `FORMA_API_URL` build
setting; Release builds leave it empty until you set a real origin. Without a
backend the app stores everything locally and Account/Community explain that the
server is missing.

## Accounts and security

- Register, login, refresh, logout, verify email, resend verification, change
  password, reset password, delete account.
- Argon2id password hashes; single-use verification/reset tokens stored only as
  SHA-256 hashes; opaque 256-bit access and refresh tokens stored only as hashes.
- Refresh rotation revokes the previous token. Logout, password change, and
  account deletion revoke sessions server-side.
- Tokens live in the iOS Keychain. The API client refreshes once on 401
  (single-flight) and clears the session if refresh fails.
- Verification and reset email require `SMTP_URL`. Without it those endpoints
  answer 503 instead of pretending mail was sent.
- Account deletion requires the current password; local training data is kept.

## Community

Community exists only when a backend URL is configured and an account is signed
in. It is a first-class tab backed by real records; there are no seed members,
sample requests, or placeholder posts.

- Gym selection has three real paths: **Near me** (optional one-time location
  fix, passed only to the gym directory to measure distance), **Search
  worldwide** (name, city, country, postcode), and **Manual** (area picker or
  submit a missing gym). One primary gym plus optional other gyms, removable at
  any time, and selection can be skipped entirely.
- The gym directory is served by the backend: Google Places when
  `GOOGLE_PLACES_API_KEY` is set, otherwise OpenStreetMap Overpass. Nearby OSM
  search needs no key; OSM name search is disabled unless the deployment sets
  `OSM_TEXT_SEARCH=true` or self-hosts Overpass. Local database search and
  member-submitted gyms always work. With no provider configured, gym search
  answers 503 `gym_directory_unavailable` instead of inventing listings.
- Matching uses the chosen gym, neighborhood, city, region, country, or Global
  scope. It never uses GPS, live presence, or exact distance, no coordinate is
  stored on a profile, and choosing a gym does not announce attendance.
- Discovery returns only accounts with a completed profile that are discoverable
  and compatible on age band. Blocks, suspension, privacy switches, and
  connection state are enforced by the server for every read and write.
- Connections move `pending → accepted/declined`; one conversation per accepted
  connection. Messages are text/emoji only, client-idempotent, deduplicated, and
  rejected when a block or suspension applies.
- Posts, likes, comments, hides, and reports; post rate limits; moderation with
  suspension, gym review, and an audit trail. Admins come from
  `COMMUNITY_ADMIN_EMAILS` and are re-checked per request.
- One authenticated Socket.IO connection per signed-in user, restricted to that
  user's own room, delivering `notification`, `activity`, and `message` events.
  REST remains the source of truth after reconnects.
- Avatars are the only upload: resized to 512 px client-side, 5 MB server limit,
  served from `UPLOAD_DIR`.

## Camera form analysis

Open from **Workouts → Camera form check** or from a mapped exercise during a
workout. `AVCaptureSession` at 720p feeds a throttled Vision pipeline
(`VNDetectHumanBodyPoseRequest`); exercise-specific state machines count reps
only while tracking is reliable. Feedback is measured-only — observed / limited /
unavailable — with no score or injury claim. Frames and joint coordinates never
leave the process. Finished sessions are saved to the local database.

This build uses 2D pose only: no trained classifier, no 3D pose, no automatic
exercise identification. The Simulator verifies only permission and honest
camera unavailability; accuracy has **not** been validated on a physical device.

## Home Screen widget

`FormaWidgets` embeds **Fitness Command Center** in small, medium, and large
families. It reads an account-scoped snapshot from the `group.forma.coach` App
Group — training summary plus Community counts only, never message text, member
identities, gym details, health data, location, or credentials. It makes no
network requests; the app reloads it after real changes, and the timeline rolls
over at local midnight. Sign-out and account deletion clear the snapshot.

## Tests

```bash
# Backend (real PostgreSQL at forma_test)
cd backend
TEST_DATABASE_URL=postgres://localhost:5432/forma_test npm test
npm run typecheck

# Native unit tests
cd native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' -only-testing:FormaTests

# Native end-to-end UI test (clean install)
xcrun simctl uninstall <device-udid> forma.coach
xcrun simctl spawn <device-udid> defaults delete forma.coach forma.previewModeEnabled
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Forma.xcodeproj -scheme Forma \
  -destination 'platform=iOS Simulator,id=<device-udid>' -only-testing:FormaUITests
```

## Verification status

Last verified in this checkout (2026-11-23, iOS 26 simulator):

- **Build**: Debug app + widget + test targets build successfully.
- **Backend**: `tsc --noEmit` clean. 23/23 integration tests pass against a real
  PostgreSQL `forma_test`, including registration/login, refresh rotation and
  revocation, verification/reset via a recording mailer, Community privacy, age
  bands, blocks, the connection/message lifecycle with dedupe, feed limits,
  moderation/audit, gym review, and a real raw-WebSocket Socket.IO delivery.
- **Native unit tests**: 159 executed, 0 failed, including the local SQLite
  layer, Community JSON decoding, form-analysis logic, and the widget data
  layer (including an App Group round-trip).
- **Native UI test**: one end-to-end flow passed on a clean install (179 s). It
  covers onboarding, all five tabs, a workout with rest timer, backgrounding,
  reminders, the exercise library, the camera-unavailable setup, relaunch
  persistence, and — against the running backend — creating a real account,
  loading the live Community bootstrap, opening the community profile editor,
  and deleting the account. Screenshots were exported and inspected.
- **Live data**: the signed-in Community screen rendered the server bootstrap
  (profile prompt, "No gym or area yet", zeroed member counts) rather than a
  mock, and returned to the signed-out notice after deletion.

Not verified in this checkout:

- SMTP delivery against a real mail provider (tests use a recording mailer).
- Camera/pose accuracy and rep-count reliability on a physical iPhone.
- Widget gallery placement and pixel rendering (`simctl` cannot add widgets);
  App Group sharing and snapshot contents are tested.
- Physical-device signing, App Group provisioning, and push-style notifications
  (APNs is not implemented; reminders are local).
- Discovery/feed/messaging screens were not driven by the UI test; their
  server behavior is covered by backend tests and their payload decoding by unit
  tests.

## Limitations

- The local SQLite database is not encrypted; it relies on the iOS sandbox.
- Training data is device-local and intentionally not synced to the backend.
- Community requires the backend and network; nothing is queued or faked offline.
- The legacy Expo prototype (`src/`) and the old Supabase project (`supabase/`)
  remain on disk but are not used by the native app.
