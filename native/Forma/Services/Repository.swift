import Foundation

enum FormaError: LocalizedError {
    case message(String)
    case notConfigured
    case notAuthenticated
    case backendRequired

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .notConfigured: "The local database could not be opened."
        case .notAuthenticated: "Choose a local profile before continuing."
        case .backendRequired: "This action needs the Forma backend, which is not connected yet."
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

    func listProgressRecords(userId: String) async throws -> [ProgressRecord]
    func addProgressRecord(_ record: ProgressRecord) async throws
    func deleteProgressRecord(id: String) async throws
}

protocol AuthProviding: Sendable {
    func currentUser() async -> AppUser?
    func authChanges() -> AsyncStream<AppUser?>
    func signIn(email: String, password: String) async throws
    func signUp(name: String, email: String, password: String) async throws
    func signOut() async throws
    func resetPassword(email: String) async throws
    func changePassword(current: String, new: String) async throws
    func deleteAccount(password: String) async throws
}

/// Tables the app keeps in sync while it is open.
enum RepositoryChange: Sendable, Equatable {
    case plan
    case sessions
    case preferences
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
