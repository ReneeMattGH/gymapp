import Foundation

struct PreviewSnapshot: Codable {
    var profiles: [String: Profile] = [:]
    var preferences: [String: Preferences] = [:]
    var plans: [WorkoutPlan] = []
    var sessions: [WorkoutSession] = []
    var reminders: [String: ReminderSettings] = [:]
    var conversations: [CoachConversation] = []
    var messages: [CoachMessage] = []
    var progress: [ProgressRecord] = []
}

/// Debug-only local repository. Data is written to this device and clearly
/// labelled in the UI as preview data.
actor PreviewRepository: FormaRepository {
    nonisolated let kind: RepositoryKind = .preview

    private let store: LocalStore
    private var snapshot: PreviewSnapshot?
    private let fileName = "preview-snapshot"

    init(store: LocalStore = .shared) {
        self.store = store
    }

    private func load() async -> PreviewSnapshot {
        if let snapshot { return snapshot }
        let loaded = await store.read(PreviewSnapshot.self, name: fileName) ?? PreviewSnapshot()
        snapshot = loaded
        return loaded
    }

    private func persist(_ value: PreviewSnapshot) async {
        snapshot = value
        await store.write(value, name: fileName)
    }

    func getExercises() async throws -> [Exercise] {
        ExerciseCatalog.all
    }

    func getProfile(userId: String) async throws -> Profile? {
        await load().profiles[userId]
    }

    func saveProfile(_ profile: Profile) async throws {
        var next = await load()
        next.profiles[profile.id] = profile
        await persist(next)
    }

    func getPreferences(userId: String) async throws -> Preferences? {
        await load().preferences[userId]
    }

    func savePreferences(_ preferences: Preferences) async throws {
        var next = await load()
        next.preferences[preferences.userId] = preferences
        await persist(next)
    }

    func getActivePlan(userId: String) async throws -> WorkoutPlan? {
        await load().plans
            .filter { $0.userId == userId }
            .max { $0.createdAt < $1.createdAt }
    }

    func savePlan(_ plan: WorkoutPlan) async throws {
        var next = await load()
        next.plans.removeAll { $0.userId == plan.userId }
        next.plans.append(plan)
        await persist(next)
    }

    func getSessions(userId: String) async throws -> [WorkoutSession] {
        await load().sessions
            .filter { $0.userId == userId }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func getSession(id: String) async throws -> WorkoutSession? {
        await load().sessions.first { $0.id == id }
    }

    func saveSession(_ session: WorkoutSession) async throws {
        var next = await load()
        if let index = next.sessions.firstIndex(where: { $0.id == session.id }) {
            next.sessions[index] = session
        } else {
            next.sessions.append(session)
        }
        await persist(next)
    }

    func getReminderSettings(userId: String) async throws -> ReminderSettings? {
        await load().reminders[userId]
    }

    func saveReminderSettings(_ settings: ReminderSettings) async throws {
        var next = await load()
        next.reminders[settings.userId] = settings
        await persist(next)
    }

    func listConversations(userId: String) async throws -> [CoachConversation] {
        await load().conversations
            .filter { $0.userId == userId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func createConversation(_ conversation: CoachConversation) async throws {
        var next = await load()
        next.conversations.append(conversation)
        await persist(next)
    }

    func updateConversation(_ conversation: CoachConversation) async throws {
        var next = await load()
        if let index = next.conversations.firstIndex(where: { $0.id == conversation.id }) {
            next.conversations[index] = conversation
        }
        await persist(next)
    }

    func deleteConversation(id: String) async throws {
        var next = await load()
        next.conversations.removeAll { $0.id == id }
        next.messages.removeAll { $0.conversationId == id }
        await persist(next)
    }

    func listMessages(conversationId: String) async throws -> [CoachMessage] {
        await load().messages
            .filter { $0.conversationId == conversationId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func addMessage(_ message: CoachMessage) async throws {
        var next = await load()
        if !next.messages.contains(where: { $0.id == message.id }) {
            next.messages.append(message)
        }
        await persist(next)
    }

    func listProgressRecords(userId: String) async throws -> [ProgressRecord] {
        await load().progress
            .filter { $0.userId == userId }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func addProgressRecord(_ record: ProgressRecord) async throws {
        var next = await load()
        next.progress.append(record)
        await persist(next)
    }

    func deleteProgressRecord(id: String) async throws {
        var next = await load()
        next.progress.removeAll { $0.id == id }
        await persist(next)
    }

    /// Wipes preview data and any locally persisted workout.
    func reset(userId: String) async {
        await store.remove(name: fileName)
        await store.clearActiveWorkout(userId: userId)
        snapshot = PreviewSnapshot()
    }
}
