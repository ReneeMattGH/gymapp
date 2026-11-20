# Database & Backend Setup Guide for Forma

This guide explains how the database layer in **Forma** is designed, how to configure your environment, and how to run the app depending on your workflow.

---

## Architecture Overview

The app's data layer uses a clean Repository pattern defined by `GymRepository` in `src/data/repository.ts`. This abstracts database operations away from the UI components.

Forma supports three storage backends switchable via `.env`:

```
┌────────────────────────────────────────────────────────┐
│                   Forma React Native App               │
│               (UI Screens, State, Navigation)          │
└───────────────────────────┬────────────────────────────┘
                            │
               ┌────────────┴────────────┐
               │  GymRepository Router   │
               └────────────┬────────────┘
         ┌──────────────────┼──────────────────┐
         ▼                  ▼                  ▼
┌─────────────────┐┌─────────────────┐┌─────────────────┐
│ Preview Mode    ││ CeeBase (Custom)││ Supabase (Cloud)│
│ (AsyncStorage)  ││ (C++ Engine)    ││ (PostgreSQL)    │
│ Zero setup      ││ High-performance││ Optional        │
└─────────────────┘└─────────────────┘└─────────────────┘
```

1. **Offline Preview Mode (`PreviewRepository`)**: Built-in on-device storage (`AsyncStorage`). Requires **no servers, no background processes, no extra software**.
2. **CeeBase (`CeeBaseRepository`)**: Custom high-performance C++20 relational database engine with B+ Tree indexing, WAL durability, and a lightweight REST API bridge (`/api/v1/query`).
3. **Supabase (`SupabaseRepository`)**: Optional cloud-hosted PostgreSQL backend.

---

## Mode 1: Offline Preview Mode (Recommended for Frontend & UI Work)

If you are working on UI screens, animations, workout flows, or features and don't need a live database server running:

### Step 1: Create your `.env` file
Copy `.env.example` or create a `.env` in the root folder:

```env
EXPO_PUBLIC_DATABASE_BACKEND=preview
EXPO_PUBLIC_DEV_PREVIEW=1
```

### Step 2: Install dependencies & run
```bash
npm install
npm run web       # Launch in browser
# or
npm start         # Launch Expo dev server (iOS / Android / Web)
```

**What works in Preview Mode:**
- Athlete onboarding and profile editing
- Plan generation (using the deterministic on-device sports science engine)
- Active workout sessions and set logging
- Bodyweight tracking and progress history
- Local coach assistance

---

## Mode 2: Connecting to a Shared CeeBase Instance

If your teammate is hosting CeeBase (e.g., via ngrok, Cloudflare Tunnel, or a shared server) and you want to test against the same live database:

### Configure `.env`
```env
EXPO_PUBLIC_DATABASE_BACKEND=ceebase
EXPO_PUBLIC_CEEBASE_URL=https://<your-teammates-ngrok-or-server-url>
EXPO_PUBLIC_DEV_PREVIEW=0
```

Run `npm run web` or `npm start`. All data will sync to the shared CeeBase engine in real time.

---

## Mode 3: Running CeeBase Locally

If you want to run the CeeBase C++ database engine on your own machine:

### 1. Clone CeeBase
```bash
git clone https://github.com/MackenzieCampbelAndross/CeeBase.git
```

### 2. Start the REST Server
```bash
cd CeeBase
python tools/studio/server.py ceebase.cbdb --port 8080 --host 0.0.0.0
```

### 3. Configure `.env` in Forma
```env
EXPO_PUBLIC_DATABASE_BACKEND=ceebase
EXPO_PUBLIC_CEEBASE_URL=http://127.0.0.1:8080
EXPO_PUBLIC_DEV_PREVIEW=0
```

---

## Database Schema (CeeBase Tables)

When running on CeeBase, tables are automatically bootstrapped on first launch:

| Table | Purpose |
| :--- | :--- |
| `cb_users` | Account credentials (`id`, `email`, `password`, `name`, `created_at`) |
| `cb_profiles` | Athlete profiles (`name`, `age`, `experience`, `environment`, `goals`) |
| `cb_preferences` | Workout schedule, target session duration, available equipment, units |
| `cb_plans` | Multi-day workout splits and exercise configurations |
| `cb_sessions` | Completed and in-progress workouts with logged set metrics |
| `cb_progress` | Athlete weigh-in timeline and bodyweight logs |
| `cb_reminders` | Notification settings |
| `cb_conversations` & `cb_messages` | Coach conversation history |

---

## Useful Commands

```bash
npm run typecheck         # Verify TypeScript types (tsc --noEmit)
npm run lint              # Run Expo / ESLint checks
node scripts/bootstrap-db.mjs       # Verify / bootstrap CeeBase tables
node scripts/verify-full-flow.mjs   # Run end-to-end database integration test
```
