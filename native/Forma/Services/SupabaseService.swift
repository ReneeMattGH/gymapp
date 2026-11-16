import Foundation
import Supabase

/// Live repository backed by Supabase. Auth session tokens stay in the SDK's
/// keychain storage; no service-role key or AI key ever ships in the app.
final class SupabaseService: FormaRepository, AuthProviding, AITokenProviding {
    let kind: RepositoryKind = .supabase

    private let client: SupabaseClient
    private let baseURL: URL
    let anonKey: String

    init(url: URL, anonKey: String) {
        self.baseURL = url
        self.anonKey = anonKey
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    var functionsURL: URL? {
        baseURL.appendingPathComponent("functions/v1")
    }

    // MARK: - Helpers

    private static func mapError(_ error: Error) -> Error {
        if error is FormaError { return error }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return FormaError.message(message.isEmpty ? "Something went wrong. Please try again." : message)
    }

    private static func date(_ value: String?) -> Date {
        value.flatMap(FormaDate.parse) ?? Date()
    }

    // MARK: - Auth

    private static func user(from session: Session?) -> AppUser? {
        guard let session else { return nil }
        return AppUser(id: session.user.id.uuidString.lowercased(), email: session.user.email)
    }

    func currentUser() async -> AppUser? {
        if let cached = Self.user(from: client.auth.currentSession) { return cached }
        do {
            return Self.user(from: try await client.auth.session)
        } catch {
            return nil
        }
    }

    func authChanges() -> AsyncStream<AppUser?> {
        AsyncStream { continuation in
            let task = Task {
                for await (_, session) in client.auth.authStateChanges {
                    continuation.yield(Self.user(from: session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        } catch {
            throw Self.mapError(error)
        }
    }

    func signUp(name: String, email: String, password: String) async throws -> Bool {
        do {
            let response = try await client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                data: ["name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines))]
            )
            return response.session == nil
        } catch {
            throw Self.mapError(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw Self.mapError(error)
        }
    }

    func resetPassword(email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(
                email.trimmingCharacters(in: .whitespacesAndNewlines),
                redirectTo: URL(string: "forma://update-password")
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func updatePassword(_ password: String) async throws {
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
        } catch {
            throw Self.mapError(error)
        }
    }

    func deleteAccount() async throws {
        do {
            try await client.functions.invoke("delete-account")
        } catch {
            throw Self.mapError(error)
        }
        try? await client.auth.signOut()
    }

    func accessToken() async throws -> String {
        do {
            return try await client.auth.session.accessToken
        } catch {
            throw FormaError.notAuthenticated
        }
    }

    func handleAuthURL(_ url: URL) {
        client.auth.handle(url)
    }

    // MARK: - Exercise catalog

    func getExercises() async throws -> [Exercise] {
        do {
            let pageSize = 200
            var offset = 0
            var rows: [ExerciseRow] = []
            while offset < 2_000 {
                let page: [ExerciseRow] = try await client
                    .from("exercise_library")
                    .select()
                    .order("name")
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
                rows.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += pageSize
            }
            return rows.map(Self.mapExercise)
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func mapExercise(_ row: ExerciseRow) -> Exercise {
        Exercise(
            id: row.id,
            name: row.name,
            category: ExerciseCategory(rawValue: row.category ?? "strength") ?? .strength,
            primaryMuscles: (row.primary_muscles ?? []).compactMap(MuscleGroup.init(rawValue:)),
            secondaryMuscles: (row.secondary_muscles ?? []).compactMap(MuscleGroup.init(rawValue:)),
            equipment: (row.equipment ?? []).compactMap(Equipment.init(rawValue:)),
            difficulty: Difficulty(rawValue: row.difficulty ?? "beginner") ?? .beginner,
            instructions: row.instructions ?? [],
            cues: row.cues ?? [],
            mistakes: row.mistakes ?? [],
            alternatives: row.alternatives ?? [],
            isUnilateral: row.is_unilateral ?? false,
            source: row.source ?? "Forma verified library"
        )
    }

    // MARK: - Profile

    func getProfile(userId: String) async throws -> Profile? {
        do {
            let row: ProfileRow? = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .maybeSingle()
                .execute()
                .value
            guard let row else { return nil }
            return Profile(
                id: row.id,
                name: row.name ?? "Athlete",
                age: row.age,
                experience: Experience(rawValue: row.experience ?? "beginner") ?? .beginner,
                environment: TrainingEnvironment(rawValue: row.environment ?? "both") ?? .both,
                goals: (row.goals ?? []).compactMap(Goal.init(rawValue:)),
                limitations: row.limitations,
                onboardingCompleted: row.onboarding_completed ?? false,
                createdAt: Self.date(row.created_at)
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func saveProfile(_ profile: Profile) async throws {
        do {
            try await client.from("profiles").upsert(ProfileUpsert(
                id: profile.id,
                name: profile.name,
                age: profile.age,
                experience: profile.experience.rawValue,
                environment: profile.environment.rawValue,
                goals: profile.goals.map(\.rawValue),
                limitations: profile.limitations,
                onboarding_completed: profile.onboardingCompleted
            )).execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Preferences

    func getPreferences(userId: String) async throws -> Preferences? {
        do {
            let row: PreferencesRow? = try await client
                .from("user_preferences")
                .select()
                .eq("user_id", value: userId)
                .maybeSingle()
                .execute()
                .value
            guard let row else { return nil }
            return Preferences(
                userId: row.user_id,
                workoutDays: row.workout_days ?? [1, 3, 5],
                sessionMinutes: row.session_minutes ?? 45,
                equipment: (row.equipment ?? []).compactMap(Equipment.init(rawValue:)),
                avoidExercises: row.avoid_exercises ?? [],
                reminderTime: row.reminder_time ?? "18:00",
                units: UnitSystem(rawValue: row.units ?? "kg") ?? .kg
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func savePreferences(_ preferences: Preferences) async throws {
        do {
            try await client.from("user_preferences").upsert(PreferencesUpsert(
                user_id: preferences.userId,
                workout_days: preferences.workoutDays,
                session_minutes: preferences.sessionMinutes,
                equipment: preferences.equipment.map(\.rawValue),
                avoid_exercises: preferences.avoidExercises,
                reminder_time: preferences.reminderTime,
                units: preferences.units.rawValue
            )).execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Plans

    func getActivePlan(userId: String) async throws -> WorkoutPlan? {
        do {
            let rows: [PlanRow] = try await client
                .from("workout_plans")
                .select("*, days:workout_days(*, exercises:workout_exercises(*))")
                .eq("user_id", value: userId)
                .eq("status", value: "active")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            return Self.mapPlan(row)
        } catch {
            throw Self.mapError(error)
        }
    }

    func savePlan(_ plan: WorkoutPlan) async throws {
        do {
            try await client
                .from("workout_plans")
                .update(StatusUpdate(status: "archived"))
                .eq("user_id", value: plan.userId)
                .eq("status", value: "active")
                .execute()

            try await client.from("workout_plans").insert(PlanInsert(
                id: plan.id,
                user_id: plan.userId,
                name: plan.name,
                goal: plan.goal.rawValue,
                experience: plan.experience.rawValue,
                days_per_week: plan.daysPerWeek,
                session_minutes: plan.sessionMinutes,
                equipment: plan.equipment.map(\.rawValue),
                generated_by: plan.source == .ai ? "ai" : "on-device",
                status: "active"
            )).execute()

            let dayRows = plan.days.map { day in
                DayInsert(
                    id: day.id,
                    plan_id: plan.id,
                    user_id: plan.userId,
                    day_index: day.dayIndex,
                    weekday: day.weekday,
                    title: day.title,
                    focus: day.focus.map(\.rawValue),
                    estimated_minutes: day.estimatedMinutes,
                    warmup: day.warmup,
                    cooldown: day.cooldown,
                    is_rest_day: day.isRestDay,
                    rest_note: day.restNote
                )
            }
            if !dayRows.isEmpty {
                try await client.from("workout_days").insert(dayRows).execute()
            }

            let exerciseRows = plan.days.flatMap { day in
                day.exercises.map { item in
                    ExerciseInsert(
                        id: item.id,
                        day_id: day.id,
                        plan_id: plan.id,
                        user_id: plan.userId,
                        exercise_id: item.exerciseId,
                        position: item.position,
                        sets: item.sets,
                        reps_min: item.repsMin,
                        reps_max: max(item.repsMin, item.repsMax),
                        rest_seconds: item.restSeconds,
                        notes: item.notes
                    )
                }
            }
            if !exerciseRows.isEmpty {
                try await client.from("workout_exercises").insert(exerciseRows).execute()
            }
        } catch {
            _ = try? await client.from("workout_plans").delete().eq("id", value: plan.id).execute()
            throw Self.mapError(error)
        }
    }

    private static func mapPlan(_ row: PlanRow) -> WorkoutPlan {
        let days = (row.days ?? [])
            .map { day -> WorkoutDay in
                let exercises = (day.exercises ?? [])
                    .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
                    .map { item in
                        WorkoutExercise(
                            id: item.id,
                            dayId: day.id,
                            exerciseId: item.exercise_id,
                            position: item.position ?? 0,
                            sets: item.sets ?? 3,
                            repsMin: item.reps_min ?? 8,
                            repsMax: item.reps_max ?? 12,
                            restSeconds: item.rest_seconds ?? 90,
                            notes: item.notes
                        )
                    }
                return WorkoutDay(
                    id: day.id,
                    planId: row.id,
                    dayIndex: day.day_index ?? 0,
                    weekday: day.weekday,
                    title: day.title,
                    focus: (day.focus ?? []).compactMap(MuscleGroup.init(rawValue:)),
                    estimatedMinutes: day.estimated_minutes ?? 0,
                    warmup: day.warmup ?? [],
                    cooldown: day.cooldown ?? [],
                    isRestDay: day.is_rest_day ?? false,
                    restNote: day.rest_note,
                    exercises: exercises
                )
            }
            .sorted { $0.dayIndex < $1.dayIndex }

        return WorkoutPlan(
            id: row.id,
            userId: row.user_id,
            name: row.name,
            goal: Goal(rawValue: row.goal) ?? .general,
            experience: Experience(rawValue: row.experience) ?? .beginner,
            daysPerWeek: row.days_per_week ?? days.filter { !$0.isRestDay }.count,
            sessionMinutes: row.session_minutes ?? 45,
            equipment: (row.equipment ?? []).compactMap(Equipment.init(rawValue:)),
            source: row.generated_by == "ai" ? .ai : .onDevice,
            createdAt: date(row.created_at),
            days: days
        )
    }

    // MARK: - Sessions

    func getSessions(userId: String) async throws -> [WorkoutSession] {
        do {
            let rows: [SessionRow] = try await client
                .from("workout_sessions")
                .select("*, sets:completed_sets(*)")
                .eq("user_id", value: userId)
                .order("started_at", ascending: false)
                .limit(200)
                .execute()
                .value
            return rows.map(Self.mapSession)
        } catch {
            throw Self.mapError(error)
        }
    }

    func getSession(id: String) async throws -> WorkoutSession? {
        do {
            let row: SessionRow? = try await client
                .from("workout_sessions")
                .select("*, sets:completed_sets(*)")
                .eq("id", value: id)
                .maybeSingle()
                .execute()
                .value
            return row.map(Self.mapSession)
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func mapSession(_ row: SessionRow) -> WorkoutSession {
        let sets = (row.sets ?? [])
            .sorted { $0.completed_at < $1.completed_at }
            .map { item in
                CompletedSet(
                    id: item.id,
                    sessionId: item.session_id,
                    workoutExerciseId: item.workout_exercise_id,
                    exerciseId: item.exercise_id,
                    setNumber: item.set_number ?? 1,
                    reps: item.reps ?? 0,
                    weightKg: item.weight_kg,
                    completedAt: date(item.completed_at)
                )
            }
        return WorkoutSession(
            id: row.id,
            userId: row.user_id,
            planDayId: row.plan_day_id,
            title: row.title,
            focus: (row.focus ?? []).compactMap(MuscleGroup.init(rawValue:)),
            startedAt: date(row.started_at),
            endedAt: row.ended_at.flatMap(FormaDate.parse),
            durationSeconds: row.duration_seconds ?? 0,
            status: SessionStatus(rawValue: row.status ?? "completed") ?? .completed,
            sets: sets,
            notes: row.notes
        )
    }

    func saveSession(_ session: WorkoutSession) async throws {
        do {
            try await client.from("workout_sessions").upsert(SessionUpsert(
                id: session.id,
                user_id: session.userId,
                plan_day_id: session.planDayId,
                title: session.title,
                focus: session.focus.map(\.rawValue),
                started_at: FormaDate.string(session.startedAt),
                ended_at: session.endedAt.map(FormaDate.string),
                duration_seconds: session.durationSeconds,
                status: session.status.rawValue,
                notes: session.notes
            )).execute()

            try await client.from("completed_sets").delete().eq("session_id", value: session.id).execute()

            if !session.sets.isEmpty {
                let rows = session.sets.map { item in
                    SetInsert(
                        id: item.id,
                        session_id: session.id,
                        user_id: session.userId,
                        workout_exercise_id: item.workoutExerciseId,
                        exercise_id: item.exerciseId,
                        set_number: item.setNumber,
                        reps: item.reps,
                        weight_kg: item.weightKg,
                        completed_at: FormaDate.string(item.completedAt)
                    )
                }
                try await client.from("completed_sets").insert(rows).execute()
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Reminders

    func getReminderSettings(userId: String) async throws -> ReminderSettings? {
        do {
            let row: ReminderRow? = try await client
                .from("reminder_settings")
                .select()
                .eq("user_id", value: userId)
                .maybeSingle()
                .execute()
                .value
            guard let row else { return nil }
            return ReminderSettings(
                userId: row.user_id,
                enabled: row.enabled ?? false,
                workoutTime: row.workout_time ?? "18:00",
                days: row.days ?? [],
                restDayReminders: row.rest_day_reminders ?? true,
                hydrationReminders: row.hydration_reminders ?? false,
                weeklyProgressReminder: row.weekly_progress_reminder ?? true,
                scheduledIds: row.scheduled_ids ?? []
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func saveReminderSettings(_ settings: ReminderSettings) async throws {
        do {
            try await client.from("reminder_settings").upsert(ReminderUpsert(
                user_id: settings.userId,
                enabled: settings.enabled,
                workout_time: settings.workoutTime,
                days: settings.days,
                rest_day_reminders: settings.restDayReminders,
                hydration_reminders: settings.hydrationReminders,
                weekly_progress_reminder: settings.weeklyProgressReminder,
                scheduled_ids: settings.scheduledIds
            )).execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Coach

    func listConversations(userId: String) async throws -> [CoachConversation] {
        do {
            let rows: [ConversationRow] = try await client
                .from("coach_conversations")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .execute()
                .value
            return rows.map {
                CoachConversation(
                    id: $0.id,
                    userId: $0.user_id,
                    title: $0.title,
                    createdAt: Self.date($0.created_at),
                    updatedAt: Self.date($0.updated_at)
                )
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    func createConversation(_ conversation: CoachConversation) async throws {
        do {
            try await client.from("coach_conversations").insert(ConversationInsert(
                id: conversation.id,
                user_id: conversation.userId,
                title: conversation.title,
                created_at: FormaDate.string(conversation.createdAt),
                updated_at: FormaDate.string(conversation.updatedAt)
            )).execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    func updateConversation(_ conversation: CoachConversation) async throws {
        do {
            try await client
                .from("coach_conversations")
                .update(ConversationUpdate(title: conversation.title, updated_at: FormaDate.string(conversation.updatedAt)))
                .eq("id", value: conversation.id)
                .execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    func deleteConversation(id: String) async throws {
        do {
            try await client.from("coach_conversations").delete().eq("id", value: id).execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    func listMessages(conversationId: String) async throws -> [CoachMessage] {
        do {
            let rows: [MessageRow] = try await client
                .from("coach_messages")
                .select()
                .eq("conversation_id", value: conversationId)
                .order("created_at", ascending: true)
                .execute()
                .value
            return rows.map {
                CoachMessage(
                    id: $0.id,
                    conversationId: $0.conversation_id,
                    userId: $0.user_id,
                    role: CoachMessage.Role(rawValue: $0.role) ?? .assistant,
                    content: $0.content,
                    createdAt: Self.date($0.created_at),
                    sources: ($0.metadata?.sources ?? []).map {
                        CoachSource(
                            id: $0.id,
                            name: $0.name,
                            category: $0.category ?? "strength"
                        )
                    }
                )
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    func addMessage(_ message: CoachMessage) async throws {
        do {
            try await client.from("coach_messages").insert(MessageInsert(
                id: message.id,
                conversation_id: message.conversationId,
                user_id: message.userId,
                role: message.role.rawValue,
                content: message.content,
                created_at: FormaDate.string(message.createdAt),
                metadata: MessageMetadataInsert(sources: message.sources)
            )).execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Progress

    func listProgressRecords(userId: String) async throws -> [ProgressRecord] {
        do {
            let rows: [ProgressRow] = try await client
                .from("progress_records")
                .select()
                .eq("user_id", value: userId)
                .order("recorded_at", ascending: false)
                .execute()
                .value
            return rows.map {
                ProgressRecord(
                    id: $0.id,
                    userId: $0.user_id,
                    recordedAt: Self.date($0.recorded_at),
                    bodyweightKg: $0.bodyweight_kg,
                    notes: $0.notes
                )
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    func addProgressRecord(_ record: ProgressRecord) async throws {
        do {
            try await client.from("progress_records").insert(ProgressInsert(
                id: record.id,
                user_id: record.userId,
                recorded_at: FormaDate.string(record.recordedAt),
                bodyweight_kg: record.bodyweightKg,
                notes: record.notes
            )).execute()
        } catch {
            throw Self.mapError(error)
        }
    }
}

// MARK: - Realtime

extension SupabaseService: RealtimeProviding {
    /// Joins one user-scoped realtime channel. Postgres changes are filtered by
    /// `user_id` and still enforced by RLS, so no other athlete's rows appear.
    func signals(userId: String) -> AsyncStream<RepositorySignal> {
        AsyncStream { continuation in
            let task = Task {
                let realtime = client.realtimeV2
                let channel = realtime.channel("forma-sync-\(userId)")
                let planToken = channel.onPostgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "workout_plans",
                    filter: .eq("user_id", value: userId)
                ) { _ in
                    continuation.yield(.changed(.plan))
                }
                let sessionToken = channel.onPostgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "workout_sessions",
                    filter: .eq("user_id", value: userId)
                ) { _ in
                    continuation.yield(.changed(.sessions))
                }
                let preferenceToken = channel.onPostgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "user_preferences",
                    filter: .eq("user_id", value: userId)
                ) { _ in
                    continuation.yield(.changed(.preferences))
                }
                let messageToken = channel.onPostgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "coach_messages",
                    filter: .eq("user_id", value: userId)
                ) { _ in
                    continuation.yield(.changed(.coachMessages))
                }
                defer {
                    planToken.cancel()
                    sessionToken.cancel()
                    preferenceToken.cancel()
                    messageToken.cancel()
                }

                do {
                    try await channel.subscribeWithError()
                } catch {
                    continuation.yield(.disconnected)
                    continuation.finish()
                    return
                }

                continuation.yield(.connected)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                }
                await realtime.removeChannel(channel)
                continuation.yield(.disconnected)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Row contracts

private struct ExerciseRow: Decodable {
    var id: String
    var name: String
    var category: String?
    var primary_muscles: [String]?
    var secondary_muscles: [String]?
    var equipment: [String]?
    var difficulty: String?
    var instructions: [String]?
    var cues: [String]?
    var mistakes: [String]?
    var alternatives: [String]?
    var is_unilateral: Bool?
    var source: String?
}

private struct ProfileRow: Decodable {
    var id: String
    var name: String?
    var age: Int?
    var experience: String?
    var environment: String?
    var goals: [String]?
    var limitations: String?
    var onboarding_completed: Bool?
    var created_at: String?
}

private struct PreferencesRow: Decodable {
    var user_id: String
    var workout_days: [Int]?
    var session_minutes: Int?
    var equipment: [String]?
    var avoid_exercises: [String]?
    var reminder_time: String?
    var units: String?
}

private struct PlanRow: Decodable {
    struct Day: Decodable {
        struct Item: Decodable {
            var id: String
            var exercise_id: String
            var position: Int?
            var sets: Int?
            var reps_min: Int?
            var reps_max: Int?
            var rest_seconds: Int?
            var notes: String?
        }

        var id: String
        var day_index: Int?
        var weekday: Int?
        var title: String
        var focus: [String]?
        var estimated_minutes: Int?
        var warmup: [String]?
        var cooldown: [String]?
        var is_rest_day: Bool?
        var rest_note: String?
        var exercises: [Item]?
    }

    var id: String
    var user_id: String
    var name: String
    var goal: String
    var experience: String
    var days_per_week: Int?
    var session_minutes: Int?
    var equipment: [String]?
    var generated_by: String?
    var created_at: String?
    var days: [Day]?
}

private struct SessionRow: Decodable {
    struct SetItem: Decodable {
        var id: String
        var session_id: String
        var workout_exercise_id: String?
        var exercise_id: String
        var set_number: Int?
        var reps: Int?
        var weight_kg: Double?
        var completed_at: String
    }

    var id: String
    var user_id: String
    var plan_day_id: String?
    var title: String
    var focus: [String]?
    var started_at: String
    var ended_at: String?
    var duration_seconds: Int?
    var status: String?
    var notes: String?
    var sets: [SetItem]?
}

private struct ReminderRow: Decodable {
    var user_id: String
    var enabled: Bool?
    var workout_time: String?
    var days: [Int]?
    var rest_day_reminders: Bool?
    var hydration_reminders: Bool?
    var weekly_progress_reminder: Bool?
    var scheduled_ids: [String]?
}

private struct ConversationRow: Decodable {
    var id: String
    var user_id: String
    var title: String
    var created_at: String
    var updated_at: String?
}

private struct MessageRow: Decodable {
    struct Source: Decodable {
        var id: String
        var name: String
        var category: String?
    }

    struct Metadata: Decodable {
        var sources: [Source]?
    }

    var id: String
    var conversation_id: String
    var user_id: String
    var role: String
    var content: String
    var created_at: String
    var metadata: Metadata?
}

private struct ProgressRow: Decodable {
    var id: String
    var user_id: String
    var recorded_at: String
    var bodyweight_kg: Double?
    var notes: String?
}

// MARK: - Insert/update payloads

private struct ProfileUpsert: Encodable {
    var id: String
    var name: String
    var age: Int?
    var experience: String
    var environment: String
    var goals: [String]
    var limitations: String?
    var onboarding_completed: Bool
}

private struct PreferencesUpsert: Encodable {
    var user_id: String
    var workout_days: [Int]
    var session_minutes: Int
    var equipment: [String]
    var avoid_exercises: [String]
    var reminder_time: String
    var units: String
}

private struct StatusUpdate: Encodable {
    var status: String
}

private struct PlanInsert: Encodable {
    var id: String
    var user_id: String
    var name: String
    var goal: String
    var experience: String
    var days_per_week: Int
    var session_minutes: Int
    var equipment: [String]
    var generated_by: String
    var status: String
}

private struct DayInsert: Encodable {
    var id: String
    var plan_id: String
    var user_id: String
    var day_index: Int
    var weekday: Int?
    var title: String
    var focus: [String]
    var estimated_minutes: Int
    var warmup: [String]
    var cooldown: [String]
    var is_rest_day: Bool
    var rest_note: String?
}

private struct ExerciseInsert: Encodable {
    var id: String
    var day_id: String
    var plan_id: String
    var user_id: String
    var exercise_id: String
    var position: Int
    var sets: Int
    var reps_min: Int
    var reps_max: Int
    var rest_seconds: Int
    var notes: String?
}

private struct SessionUpsert: Encodable {
    var id: String
    var user_id: String
    var plan_day_id: String?
    var title: String
    var focus: [String]
    var started_at: String
    var ended_at: String?
    var duration_seconds: Int
    var status: String
    var notes: String?
}

private struct SetInsert: Encodable {
    var id: String
    var session_id: String
    var user_id: String
    var workout_exercise_id: String?
    var exercise_id: String
    var set_number: Int
    var reps: Int
    var weight_kg: Double?
    var completed_at: String
}

private struct ReminderUpsert: Encodable {
    var user_id: String
    var enabled: Bool
    var workout_time: String
    var days: [Int]
    var rest_day_reminders: Bool
    var hydration_reminders: Bool
    var weekly_progress_reminder: Bool
    var scheduled_ids: [String]
}

private struct ConversationInsert: Encodable {
    var id: String
    var user_id: String
    var title: String
    var created_at: String
    var updated_at: String
}

private struct ConversationUpdate: Encodable {
    var title: String
    var updated_at: String
}

private struct MessageInsert: Encodable {
    var id: String
    var conversation_id: String
    var user_id: String
    var role: String
    var content: String
    var created_at: String
    var metadata: MessageMetadataInsert
}

private struct MessageMetadataInsert: Encodable {
    struct Source: Encodable {
        var id: String
        var name: String
        var category: String
    }

    var sources: [Source]

    init(sources: [CoachSource]) {
        self.sources = sources.map { Source(id: $0.id, name: $0.name, category: $0.category) }
    }
}

private struct ProgressInsert: Encodable {
    var id: String
    var user_id: String
    var recorded_at: String
    var bodyweight_kg: Double?
    var notes: String?
}
