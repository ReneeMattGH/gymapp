import Foundation

enum FormaError: LocalizedError {
    case message(String)
    case notConfigured
    case notAuthenticated
    case previewOnly

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .notConfigured: "The backend is not configured. See the setup guide to connect Supabase."
        case .notAuthenticated: "Your session has expired. Sign in again to continue."
        case .previewOnly: "This action needs a connected Supabase project."
        }
    }
}

protocol FormaRepository: Sendable {
    var kind: RepositoryKind { get }

    func getExercises() async throws -> [Exercise]

    func getProfile(userId: String) async throws -> Profile?
    func saveProfile(_ profile: Profile) async throws
    func getPreferences(userId: String) async throws -> Preferences?
    func savePreferences(_ preferences: Preferences) async throws

    func getActivePlan(userId: String) async throws -> WorkoutPlan?
    func savePlan(_ plan: WorkoutPlan) async throws

    func getSessions(userId: String) async throws -> [WorkoutSession]
    func getSession(id: String) async throws -> WorkoutSession?
    func saveSession(_ session: WorkoutSession) async throws

    func getReminderSettings(userId: String) async throws -> ReminderSettings?
    func saveReminderSettings(_ settings: ReminderSettings) async throws

    func listConversations(userId: String) async throws -> [CoachConversation]
    func createConversation(_ conversation: CoachConversation) async throws
    func updateConversation(_ conversation: CoachConversation) async throws
    func deleteConversation(id: String) async throws
    func listMessages(conversationId: String) async throws -> [CoachMessage]
    func addMessage(_ message: CoachMessage) async throws

    func listProgressRecords(userId: String) async throws -> [ProgressRecord]
    func addProgressRecord(_ record: ProgressRecord) async throws
}

protocol AuthProviding: Sendable {
    func currentUser() async -> AppUser?
    func authChanges() -> AsyncStream<AppUser?>
    func signIn(email: String, password: String) async throws
    func signUp(name: String, email: String, password: String) async throws -> Bool
    func signOut() async throws
    func resetPassword(email: String) async throws
    func updatePassword(_ password: String) async throws
    func deleteAccount() async throws
}

protocol AITokenProviding: Sendable {
    func accessToken() async throws -> String
    var anonKey: String { get }
    var functionsURL: URL? { get }
}

/// Tables the app keeps in sync while it is open.
enum RepositoryChange: Sendable, Equatable {
    case plan
    case sessions
    case preferences
    case coachMessages
}

/// Emitted by a live backend. `connected` means a realtime channel is joined,
/// so the UI may honestly say it is receiving live changes.
enum RepositorySignal: Sendable, Equatable {
    case connected
    case changed(RepositoryChange)
    case disconnected
}

protocol RealtimeProviding: Sendable {
    /// A long-lived signal stream, scoped to the signed-in user by the backend's RLS.
    func signals(userId: String) -> AsyncStream<RepositorySignal>
}
