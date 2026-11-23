import Foundation
import GRDB

enum FormaMigrations {
    static func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial_schema") { db in
            try db.execute(sql: schemaV1)
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        migrator.registerMigration("v2_seed_exercise_library") { db in
            try seedExerciseLibrary(db)
            try db.execute(sql: "PRAGMA user_version = 2")
        }
        try migrator.migrate(writer)
    }

    /// Exercises ship with the app. Seeding is idempotent so re-running a
    /// migration or reinstalling never duplicates rows.
    private static func seedExerciseLibrary(_ db: Database) throws {
        let exercises = ExerciseCatalog.all
        guard !exercises.isEmpty else { return }
        let insert = try db.makeStatement(sql: """
            INSERT OR IGNORE INTO exercise_library (
                id, name, category, primary_muscles, secondary_muscles, equipment,
                difficulty, instructions, cues, mistakes, alternatives,
                is_unilateral, source, position
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        for (index, exercise) in exercises.enumerated() {
            try insert.execute(arguments: [
                exercise.id,
                exercise.name,
                exercise.category.rawValue,
                try RecordCoding.encodeJSON(exercise.primaryMuscles),
                try RecordCoding.encodeJSON(exercise.secondaryMuscles),
                try RecordCoding.encodeJSON(exercise.equipment),
                exercise.difficulty.rawValue,
                try RecordCoding.encodeJSON(exercise.instructions),
                try RecordCoding.encodeJSON(exercise.cues),
                try RecordCoding.encodeJSON(exercise.mistakes),
                try RecordCoding.encodeJSON(exercise.alternatives),
                exercise.isUnilateral,
                exercise.source,
                index,
            ])
        }
    }

    private static let schemaV1 = """
        CREATE TABLE profiles (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            age INTEGER,
            experience TEXT NOT NULL,
            environment TEXT NOT NULL,
            goals TEXT NOT NULL,
            limitations TEXT,
            photo_path TEXT,
            onboarding_completed INTEGER NOT NULL DEFAULT 0,
            created_at DATETIME NOT NULL
        );

        CREATE TABLE user_preferences (
            user_id TEXT PRIMARY KEY NOT NULL
                REFERENCES profiles(id) ON DELETE CASCADE,
            workout_days TEXT NOT NULL,
            session_minutes INTEGER NOT NULL,
            equipment TEXT NOT NULL,
            avoid_exercises TEXT NOT NULL,
            reminder_time TEXT NOT NULL,
            units TEXT NOT NULL,
            updated_at DATETIME NOT NULL
        );

        CREATE TABLE exercise_library (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            primary_muscles TEXT NOT NULL,
            secondary_muscles TEXT NOT NULL,
            equipment TEXT NOT NULL,
            difficulty TEXT NOT NULL,
            instructions TEXT NOT NULL,
            cues TEXT NOT NULL,
            mistakes TEXT NOT NULL,
            alternatives TEXT NOT NULL,
            is_unilateral INTEGER NOT NULL DEFAULT 0,
            source TEXT,
            position INTEGER NOT NULL
        );
        CREATE INDEX idx_exercise_library_name ON exercise_library(name);
        CREATE INDEX idx_exercise_library_category ON exercise_library(category);

        CREATE TABLE workout_plans (
            id TEXT PRIMARY KEY NOT NULL,
            user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            goal TEXT NOT NULL,
            experience TEXT NOT NULL,
            days_per_week INTEGER NOT NULL,
            session_minutes INTEGER NOT NULL,
            equipment TEXT NOT NULL,
            source TEXT NOT NULL,
            created_at DATETIME NOT NULL
        );
        CREATE INDEX idx_workout_plans_user_created
            ON workout_plans(user_id, created_at DESC);

        CREATE TABLE workout_days (
            id TEXT PRIMARY KEY NOT NULL,
            plan_id TEXT NOT NULL REFERENCES workout_plans(id) ON DELETE CASCADE,
            day_index INTEGER NOT NULL,
            weekday INTEGER,
            title TEXT NOT NULL,
            focus TEXT NOT NULL,
            estimated_minutes INTEGER NOT NULL,
            warmup TEXT NOT NULL,
            cooldown TEXT NOT NULL,
            is_rest_day INTEGER NOT NULL DEFAULT 0,
            rest_note TEXT,
            UNIQUE(plan_id, day_index)
        );
        CREATE INDEX idx_workout_days_plan ON workout_days(plan_id);

        CREATE TABLE workout_exercises (
            id TEXT PRIMARY KEY NOT NULL,
            day_id TEXT NOT NULL REFERENCES workout_days(id) ON DELETE CASCADE,
            exercise_id TEXT NOT NULL
                REFERENCES exercise_library(id) ON DELETE RESTRICT,
            position INTEGER NOT NULL,
            sets INTEGER NOT NULL,
            reps_min INTEGER NOT NULL,
            reps_max INTEGER NOT NULL,
            rest_seconds INTEGER NOT NULL,
            notes TEXT,
            UNIQUE(day_id, position)
        );
        CREATE INDEX idx_workout_exercises_day ON workout_exercises(day_id);
        CREATE INDEX idx_workout_exercises_exercise ON workout_exercises(exercise_id);

        CREATE TABLE workout_sessions (
            id TEXT PRIMARY KEY NOT NULL,
            user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            plan_day_id TEXT REFERENCES workout_days(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            focus TEXT NOT NULL,
            started_at DATETIME NOT NULL,
            ended_at DATETIME,
            duration_seconds INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            notes TEXT,
            form_analysis TEXT
        );
        CREATE INDEX idx_workout_sessions_user_started
            ON workout_sessions(user_id, started_at DESC);
        CREATE INDEX idx_workout_sessions_day ON workout_sessions(plan_day_id);

        CREATE TABLE completed_sets (
            id TEXT PRIMARY KEY NOT NULL,
            session_id TEXT NOT NULL
                REFERENCES workout_sessions(id) ON DELETE CASCADE,
            workout_exercise_id TEXT,
            exercise_id TEXT NOT NULL,
            set_number INTEGER NOT NULL,
            reps INTEGER NOT NULL,
            weight_kg REAL,
            completed_at DATETIME NOT NULL
        );
        CREATE INDEX idx_completed_sets_session ON completed_sets(session_id);
        CREATE INDEX idx_completed_sets_exercise ON completed_sets(exercise_id);

        CREATE TABLE progress_records (
            id TEXT PRIMARY KEY NOT NULL,
            user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            recorded_at DATETIME NOT NULL,
            bodyweight_kg REAL,
            notes TEXT
        );
        CREATE INDEX idx_progress_records_user_recorded
            ON progress_records(user_id, recorded_at DESC);

        CREATE TABLE reminder_settings (
            user_id TEXT PRIMARY KEY NOT NULL
                REFERENCES profiles(id) ON DELETE CASCADE,
            enabled INTEGER NOT NULL,
            workout_time TEXT NOT NULL,
            days TEXT NOT NULL,
            rest_day_reminders INTEGER NOT NULL,
            hydration_reminders INTEGER NOT NULL,
            weekly_progress_reminder INTEGER NOT NULL,
            scheduled_ids TEXT NOT NULL
        );

        CREATE TABLE app_settings (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT,
            updated_at DATETIME NOT NULL
        );
        """
}
