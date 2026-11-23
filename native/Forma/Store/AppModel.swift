import Foundation
import Network
import Observation
import SwiftUI

enum RuntimeMode: Equatable {
    case loading
    case local
}

/// What the UI may honestly claim about where data came from.
enum SyncState: Equatable {
    case local
    case syncing
    case live
    case cached
    case offline

    var label: String {
        switch self {
        case .local: "Local"
        case .syncing: "Syncing"
        case .live: "Live"
        case .cached: "Cached"
        case .offline: "Offline"
        }
    }

    var detail: String {
        switch self {
        case .local: "Saved on this device only."
        case .syncing: "Fetching your latest data."
        case .live: "Receiving realtime changes from your account."
        case .cached: "Showing the last data loaded for your account."
        case .offline: "The server could not be reached. Changes may not be saved."
        }
    }
}

struct OnboardingOutcome {
    let plan: WorkoutPlan
    let reminderMessage: String
    let scheduledCount: Int
}

@MainActor
@Observable
final class AppModel {
    // Configuration
    let config = AppConfig.current
    private(set) var mode: RuntimeMode = .loading

    // Services
    private(set) var repository: FormaRepository?
    private var repo: FormaRepository? { repository }
    private var signalsTask: Task<Void, Never>?
    private var signalsUserId: String?
    private var refreshTask: Task<Void, Never>?
    private var connectivityMonitor: NWPathMonitor?
    private var connectivitySatisfied: Bool?

    // Sync
    private(set) var syncState: SyncState = .local
    private(set) var lastSyncedAt: Date?
    var libraryNotice: String?

    // Session
    private(set) var user: AppUser?
    /// Every profile stored in this device's database.
    private(set) var localProfiles: [Profile] = []
    var isBootstrapping = true
    var profileError: String?
    /// A widget deep link waiting for onboarding or navigation.
    var pendingDeepLink: AppDeepLink?

    // Remote account (separate from the on-device training profile)
    private(set) var accountService: AccountService?
    private(set) var communityAPIService: CommunityAPIService?
    private var accountTask: Task<Void, Never>?
    /// The signed-in Forma account. Signing in never rewrites the local profile.
    private(set) var remoteAccount: AppUser?
    /// A reset token from `forma://auth/reset-password` awaiting a new password.
    var pendingPasswordResetToken: String?
    var accountNotice: String?
    /// Set by an account deep link so the Account screen opens from any tab.
    var isAccountPresented = false

    // Data
    var profile: Profile?
    var preferences: Preferences?
    var plan: WorkoutPlan?
    var sessions: [WorkoutSession] = []
    var exercises: [Exercise] = []
    var reminders: ReminderSettings?
    var progressRecords: [ProgressRecord] = []
    var pendingOnboardingOutcome: OnboardingOutcome?
    var isCompletingOnboarding = false
    /// Form-analysis sessions that are saved on this device but not yet synced.
    private(set) var pendingFormSessionIDs: Set<String> = []

    var isLoadingData = false
    var loadError: String?

    // Theme
    var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: Self.themeKey) }
    }

    // Active workout
    var activeWorkout: ActiveWorkout?
    var workoutSummary: WorkoutSession?
    var workoutError: String?
    var isSavingWorkout = false

    // Plan generation
    var isGeneratingPlan = false
    var planError: String?

    // Reminders
    var isSavingReminders = false
    var reminderError: String?

    // Progress check-ins
    var isSavingCheckIn = false

    // Health
    var healthAvailable = HealthKitService.shared.availability == .ready
    var healthOptIn: Bool {
        didSet { UserDefaults.standard.set(healthOptIn, forKey: Self.healthKey) }
    }
    var healthSummary: HealthSummary?
    var healthBusy = false
    var healthError: String?
    var healthFetched = false

    // Exercise library preferences (local to this device)
    var favoriteExercises: Set<String> {
        didSet { UserDefaults.standard.set(Array(favoriteExercises), forKey: Self.favoritesKey) }
    }
    var recentExercises: [String] {
        didSet { UserDefaults.standard.set(recentExercises, forKey: Self.recentKey) }
    }

    private static let themeKey = "forma.themeMode"
    private static let healthKey = "forma.healthOptIn"
    private static let favoritesKey = "forma.favoriteExercises"
    private static let recentKey = "forma.recentExercises"

    init() {
        let storedTheme = UserDefaults.standard.string(forKey: Self.themeKey)
        themeMode = ThemeMode(rawValue: storedTheme ?? "") ?? .dark
        healthOptIn = UserDefaults.standard.bool(forKey: Self.healthKey)
        favoriteExercises = Set(UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? [])
        recentExercises = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        isBootstrapping = true
        startConnectivityMonitor()
    }

    private func startConnectivityMonitor() {
        guard connectivityMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                let reconnected = satisfied && self.connectivitySatisfied == false
                self.connectivitySatisfied = satisfied
                guard reconnected, !self.pendingFormSessionIDs.isEmpty else { return }
                await self.refreshRemoteData()
            }
        }
        monitor.start(queue: DispatchQueue(label: "forma.connectivity"))
        connectivityMonitor = monitor
    }

    // MARK: - Derived

    var colorScheme: ColorScheme? {
        switch themeMode {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    var isRemote: Bool { repository?.kind == .remote }

    /// Nil until this build has a backend URL. Community still requires a
    /// signed-in account on top of this, which the Community screen checks.
    var communityService: (any CommunityServicing)? {
        communityAPIService
    }

    var needsOnboarding: Bool {
        guard let profile else { return true }
        return !profile.onboardingCompleted
    }

    var units: UnitSystem { preferences?.units ?? .kg }

    var completedSessions: [WorkoutSession] { TrainingStats.completedSessions(sessions) }

    var todayDay: WorkoutDay? {
        guard let plan else { return nil }
        return PlanGenerator.planForDate(plan, date: Date())
    }

    var nextDay: WorkoutDay? {
        guard let plan else { return nil }
        return PlanGenerator.nextTrainingDay(plan, from: Date())
    }

    var lastCompletedSession: WorkoutSession? { completedSessions.first }

    var latestCheckIn: ProgressRecord? { progressRecords.first }

    func exercise(_ id: String) -> Exercise? {
        exercises.first { $0.id == id } ?? ExerciseCatalog.exercise(id)
    }

    func exerciseName(_ id: String) -> String {
        exercise(id)?.name ?? id
    }

    func toggleFavorite(_ id: String) {
        if favoriteExercises.contains(id) {
            favoriteExercises.remove(id)
        } else {
            favoriteExercises.insert(id)
        }
        Haptics.selection()
    }

    func recordExerciseView(_ id: String) {
        var next = recentExercises.filter { $0 != id }
        next.insert(id, at: 0)
        recentExercises = Array(next.prefix(12))
    }

    // MARK: - Bootstrap

    /// Opens the on-device database and activates the remembered local profile.
    /// A fresh install gets a stable pending identity so onboarding can write
    /// the first profile; no profile row is invented before the user saves one.
    func bootstrap() async {
        isBootstrapping = true
        loadError = nil
        do {
            let database = try AppDatabase.onDisk()
            let repo = LocalRepository(database: database)
            repository = repo
            mode = .local
            syncState = .local
            configureAccountLayer()

            let storedExercises = try await repo.getExercises()
            exercises = storedExercises.isEmpty ? ExerciseCatalog.all : storedExercises

            let profiles = try await repo.listProfiles()
            localProfiles = profiles
            let activeID = try? await repo.activeProfileID()
            let active = profiles.first { $0.id == activeID } ?? profiles.first
            if let active {
                try? await repo.setActiveProfileID(active.id)
                user = AppUser(id: active.id, email: nil)
                isBootstrapping = false
                await loadAll()
            } else {
                user = AppUser(id: IDs.uuid(), email: nil)
                isLoadingData = false
                isBootstrapping = false
            }
        } catch {
            repository = nil
            loadError = error.localizedDescription
            isBootstrapping = false
        }
    }

    // MARK: - Loading

    func loadAll() async {
        guard let repo, let user else { return }
        isLoadingData = true
        loadError = nil
        libraryNotice = nil
        if isRemote { syncState = .syncing }
        await loadPendingFormSessions(userId: user.id)
        do {
            async let profileTask = repo.getProfile(userId: user.id)
            async let preferencesTask = repo.getPreferences(userId: user.id)
            async let planTask = repo.getActivePlan(userId: user.id)
            async let sessionsTask = repo.getSessions(userId: user.id)
            async let remindersTask = repo.getReminderSettings(userId: user.id)
            async let progressTask = repo.listProgressRecords(userId: user.id)

            let (loadedProfile, loadedPreferences, loadedPlan, loadedSessions, loadedReminders, loadedProgress) =
                try await (profileTask, preferencesTask, planTask, sessionsTask, remindersTask, progressTask)

            profile = loadedProfile
            preferences = loadedPreferences
            plan = loadedPlan
            sessions = loadedSessions
            reminders = loadedReminders
            progressRecords = loadedProgress

            do {
                let fetched = try await repo.getExercises()
                exercises = fetched.isEmpty ? ExerciseCatalog.all : fetched
                if fetched.isEmpty {
                    libraryNotice = "The local library has no exercises yet, so the bundled verified copy is being used."
                }
            } catch {
                exercises = ExerciseCatalog.all
                libraryNotice = "The local exercise library could not be read. Showing the bundled verified copy."
            }

            await mergePendingFormSessions(userId: user.id)
            await flushPendingFormSessions()
            activeWorkout = await LocalStore.shared.loadActiveWorkout(userId: user.id)
            if activeWorkout != nil { workoutSummary = nil }
            lastSyncedAt = Date()
            if isRemote {
                syncState = .cached
                startSignalsIfNeeded(userId: user.id)
            } else {
                syncState = .local
            }
            await reconcileReminders()
            publishWidgetSnapshot()
        } catch {
            loadError = error.localizedDescription
            if isRemote { syncState = .offline }
            await mergePendingFormSessions(userId: user.id)
            discardWidgetSnapshotIfAccountDiffers()
        }
        isLoadingData = false
    }

    /// Pulls the synced rows without disturbing an in-progress workout.
    func refreshRemoteData() async {
        guard let repo, let user else { return }
        if isRemote, syncState == .offline { syncState = .syncing }
        do {
            async let profileTask = repo.getProfile(userId: user.id)
            async let preferencesTask = repo.getPreferences(userId: user.id)
            async let planTask = repo.getActivePlan(userId: user.id)
            async let sessionsTask = repo.getSessions(userId: user.id)
            async let progressTask = repo.listProgressRecords(userId: user.id)

            let (nextProfile, nextPreferences, nextPlan, nextSessions, nextProgress) =
                try await (profileTask, preferencesTask, planTask, sessionsTask, progressTask)

            profile = nextProfile
            preferences = nextPreferences
            plan = nextPlan
            sessions = nextSessions
            progressRecords = nextProgress
            await mergePendingFormSessions(userId: user.id)
            await flushPendingFormSessions()
            lastSyncedAt = Date()
            if isRemote, syncState != .live { syncState = .cached }
            publishWidgetSnapshot()
        } catch {
            if isRemote { syncState = .offline }
            await mergePendingFormSessions(userId: user.id)
            discardWidgetSnapshotIfAccountDiffers()
        }
    }

    /// Lightweight check used when the app returns to the foreground.
    func refreshOnForeground() async {
        guard isRemote, user != nil else { return }
        if let lastSyncedAt, Date().timeIntervalSince(lastSyncedAt) < 30 { return }
        await refreshRemoteData()
    }

    private func startSignalsIfNeeded(userId: String) {
        guard let realtime = repository as? RealtimeProviding else { return }
        if signalsTask != nil, signalsUserId == userId { return }
        signalsTask?.cancel()
        signalsUserId = userId
        signalsTask = Task { [weak self] in
            for await signal in realtime.signals(userId: userId) {
                guard let self, !Task.isCancelled else { break }
                self.handleSignal(signal)
            }
        }
    }

    private func handleSignal(_ signal: RepositorySignal) {
        switch signal {
        case .connected:
            if isRemote { syncState = .live }
        case .disconnected:
            if isRemote, syncState == .live { syncState = .cached }
        case .changed:
            scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            await self.refreshRemoteData()
        }
    }

    func refresh() async {
        if repository == nil {
            await bootstrap()
        } else {
            await loadAll()
        }
    }

    // MARK: - Remote account

    /// Nil when this build has no backend URL, so the Account screen can say so
    /// instead of pretending to sign in.
    var isAccountAvailable: Bool { accountService != nil }

    private func configureAccountLayer() {
        guard let baseURL = config.apiBaseURL else { return }
        if accountService == nil {
            let client = APIClient(baseURL: baseURL)
            let service = AccountService(client: client)
            accountService = service
            communityAPIService = CommunityAPIService(client: client, baseURL: baseURL)
            accountTask = Task { [weak self] in
                for await account in service.authChanges() {
                    guard let self else { return }
                    self.remoteAccount = account
                }
            }
        }
        Task { [weak self] in await self?.refreshAccountState() }
    }

    private func refreshAccountState() async {
        guard let service = accountService else { return }
        let account = await service.currentAccount()
        remoteAccount = account.map {
            AppUser(id: $0.id, email: $0.email, emailVerified: $0.emailVerified)
        }
    }

    func signInAccount(email: String, password: String) async throws {
        guard let accountService else { throw FormaError.backendRequired }
        accountNotice = nil
        try await accountService.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }

    func createAccount(name: String, email: String, password: String) async throws -> AccountRegistration {
        guard let accountService else { throw FormaError.backendRequired }
        accountNotice = nil
        let registration = try await accountService.register(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        accountNotice = registration.verificationEmailSent
            ? "Account created. Check \(registration.user.email) for the confirmation link."
            : "Account created. The backend did not send a confirmation email, so verification is still pending."
        return registration
    }

    func signOutAccount() async {
        accountNotice = nil
        try? await accountService?.signOut()
    }

    func changeAccountPassword(current: String, new: String) async throws {
        guard let accountService else { throw FormaError.backendRequired }
        try await accountService.changePassword(current: current, new: new)
        accountNotice = "Password updated. Other sessions were signed out."
    }

    func deleteRemoteAccount(password: String) async throws {
        guard let accountService else { throw FormaError.backendRequired }
        try await accountService.deleteAccount(password: password)
        accountNotice = "Your Forma account was deleted."
    }

    func requestAccountPasswordReset(email: String) async throws {
        guard let accountService else { throw FormaError.backendRequired }
        try await accountService.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        accountNotice = "If that address has an account, a reset link is on its way."
    }

    func resendVerificationEmail() async throws -> Bool {
        guard let accountService else { throw FormaError.backendRequired }
        return try await accountService.resendVerification()
    }

    func confirmAccountPasswordReset(token: String, password: String) async throws {
        guard let accountService else { throw FormaError.backendRequired }
        try await accountService.confirmPasswordReset(token: token, password: password)
        pendingPasswordResetToken = nil
        accountNotice = "Password updated. Sign in with the new password."
    }

    private func handleAuthDeepLink(_ link: AuthDeepLink) async {
        accountNotice = nil
        switch link {
        case .verifyEmail(let token):
            isAccountPresented = true
            guard let accountService else {
                accountNotice = FormaError.backendRequired.localizedDescription
                return
            }
            do {
                try await accountService.verifyEmail(token: token)
                accountNotice = "Email confirmed. Your account is verified."
            } catch {
                accountNotice = "That confirmation link could not be used: \(error.localizedDescription)"
            }
        case .resetPassword(let token):
            pendingPasswordResetToken = token
            isAccountPresented = true
        }
    }

    private func clearUserData() {
        signalsTask?.cancel()
        signalsTask = nil
        signalsUserId = nil
        refreshTask?.cancel()
        refreshTask = nil
        syncState = .local
        lastSyncedAt = nil
        libraryNotice = nil
        profile = nil
        preferences = nil
        plan = nil
        sessions = []
        reminders = nil
        progressRecords = []
        pendingFormSessionIDs = []
        activeWorkout = nil
        workoutSummary = nil
        planError = nil
        workoutError = nil
        healthSummary = nil
        healthFetched = false
        WidgetPublisher.clear()
    }

    // MARK: - Local profiles

    func routeDeepLink(_ url: URL) {
        if let authLink = AuthDeepLink.parse(url) {
            Task { await handleAuthDeepLink(authLink) }
            return
        }
        guard let link = AppDeepLink.parse(url) else { return }
        pendingDeepLink = link
    }

    func consumeDeepLink(_ link: AppDeepLink) {
        guard pendingDeepLink == link else { return }
        pendingDeepLink = nil
    }

    /// Switches the active profile. Personal data never crosses between
    /// profiles: the whole in-memory state is cleared and reloaded from SQLite.
    func switchProfile(to id: String) async {
        guard id != user?.id,
              let repo = repository as? LocalRepository,
              localProfiles.contains(where: { $0.id == id }) else { return }
        profileError = nil
        do {
            try await repo.setActiveProfileID(id)
        } catch {
            profileError = error.localizedDescription
            return
        }
        clearUserData()
        user = AppUser(id: id, email: nil)
        await loadAll()
        Haptics.selection()
    }

    /// Starts a fresh profile. Onboarding writes the row once the user saves.
    func beginNewProfile() async {
        guard let repo = repository as? LocalRepository else { return }
        profileError = nil
        try? await repo.setActiveProfileID(nil)
        clearUserData()
        user = AppUser(id: IDs.uuid(), email: nil)
        isLoadingData = false
        Haptics.selection()
    }

    /// Deletes the active profile and everything that belongs to it. Requires
    /// an explicit confirmation in the UI before it is called.
    func deleteActiveProfile() async -> Bool {
        guard let repo = repository as? LocalRepository, let user else { return false }
        profileError = nil
        do {
            if let photoPath = profile?.photoPath {
                ProfilePhotoStore.delete(photoPath)
            }
            try await repo.deleteProfile(userId: user.id)
            await LocalStore.shared.clearActiveWorkout(userId: user.id)
            let remaining = try await repo.listProfiles()
            localProfiles = remaining
            clearUserData()
            if let next = remaining.first {
                try await repo.setActiveProfileID(next.id)
                self.user = AppUser(id: next.id, email: nil)
                await loadAll()
            } else {
                try await repo.setActiveProfileID(nil)
                self.user = AppUser(id: IDs.uuid(), email: nil)
                isLoadingData = false
            }
            WidgetPublisher.clear()
            return true
        } catch {
            profileError = error.localizedDescription
            return false
        }
    }

    // MARK: - Onboarding & profile

    func completeOnboarding(
        profile nextProfile: Profile,
        preferences nextPreferences: Preferences,
        reminders nextReminders: ReminderSettings
    ) async throws -> OnboardingOutcome {
        guard let repo, let user else { throw FormaError.notAuthenticated }
        isCompletingOnboarding = true
        defer { isCompletingOnboarding = false }
        try await repo.saveProfile(nextProfile)
        try await repo.savePreferences(nextPreferences)
        profile = nextProfile
        preferences = nextPreferences

        guard let generated = PlanGenerator.generateLocalPlan(
            userId: user.id,
            profile: nextProfile,
            preferences: nextPreferences
        ) else {
            throw FormaError.message("The exercise library could not be loaded, so a plan could not be built.")
        }
        try await repo.savePlan(generated)
        plan = generated

        var settings = nextReminders
        settings.userId = user.id
        var reminderMessage: String
        var scheduledCount = 0

        if settings.enabled {
            do {
                let result = try await NotificationService.shared.schedule(settings)
                settings.enabled = result.count > 0
                settings.scheduledIds = result.scheduledIds
                reminderMessage = result.message
                scheduledCount = result.count
            } catch {
                settings.enabled = false
                settings.scheduledIds = []
                reminderMessage = error.localizedDescription
            }
        } else {
            settings.scheduledIds = []
            reminderMessage = "Reminders are off. You can enable them in Profile → Reminders."
        }

        try await repo.saveReminderSettings(settings)
        reminders = settings

        if let local = repository as? LocalRepository {
            try? await local.setActiveProfileID(user.id)
            localProfiles = (try? await local.listProfiles()) ?? [nextProfile]
        }

        let outcome = OnboardingOutcome(
            plan: generated,
            reminderMessage: reminderMessage,
            scheduledCount: scheduledCount
        )
        pendingOnboardingOutcome = outcome
        publishWidgetSnapshot()
        return outcome
    }

    func dismissPlanReady() {
        pendingOnboardingOutcome = nil
    }

    func saveProfile(_ next: Profile) async throws {
        guard let repo else { throw FormaError.notConfigured }
        try await repo.saveProfile(next)
        profile = next
        if let local = repository as? LocalRepository {
            localProfiles = (try? await local.listProfiles()) ?? localProfiles
        }
    }

    func savePreferences(_ next: Preferences) async throws {
        guard let repo else { throw FormaError.notConfigured }
        try await repo.savePreferences(next)
        preferences = next
        publishWidgetSnapshot()
    }

    func saveUnits(_ units: UnitSystem) async throws {
        guard var next = preferences else { return }
        next.units = units
        try await savePreferences(next)
    }

    // MARK: - Plans

    func buildLocalPlanDraft() throws -> WorkoutPlan {
        guard let user, let profile, let preferences else {
            throw FormaError.message("Finish onboarding before generating a plan.")
        }
        guard let plan = PlanGenerator.generateLocalPlan(userId: user.id, profile: profile, preferences: preferences) else {
            throw FormaError.message("The exercise library could not be loaded, so a plan could not be built.")
        }
        return plan
    }

    func adoptPlan(_ next: WorkoutPlan) async throws {
        guard let repo else { throw FormaError.notConfigured }
        let issues = PlanValidator.structureIssues(
            next,
            catalog: exercises.isEmpty ? ExerciseCatalog.all : exercises
        )
        if let problem = PlanValidator.firstError(in: issues) {
            planError = problem
            throw FormaError.message("This plan cannot be saved: \(problem)")
        }
        isGeneratingPlan = true
        defer { isGeneratingPlan = false }
        do {
            try await repo.savePlan(next)
            plan = next
            publishWidgetSnapshot()
        } catch {
            planError = error.localizedDescription
            throw error
        }
    }

    /// Saves structural edits as a new active plan. The repository archives the
    /// previous plan, so ids must change to avoid a primary-key collision.
    func saveEditedPlan(_ next: WorkoutPlan) async throws -> WorkoutPlan {
        guard let repo, let user else { throw FormaError.notAuthenticated }
        var copy = next
        copy.userId = user.id
        copy.createdAt = StoredTimestamp.now()
        let planId = IDs.uuid()
        copy.id = planId
        copy.days = copy.days.map { day in
            var dayCopy = day
            let dayId = IDs.uuid()
            dayCopy.id = dayId
            dayCopy.planId = planId
            dayCopy.exercises = dayCopy.exercises.enumerated().map { index, item in
                var exercise = item
                exercise.id = IDs.uuid()
                exercise.dayId = dayId
                exercise.position = index
                return exercise
            }
            return dayCopy
        }
        let issues = PlanValidator.structureIssues(
            copy,
            catalog: exercises.isEmpty ? ExerciseCatalog.all : exercises
        )
        if let problem = PlanValidator.firstError(in: issues) {
            planError = problem
            throw FormaError.message("This plan cannot be saved: \(problem)")
        }
        do {
            try await repo.savePlan(copy)
            plan = copy
            publishWidgetSnapshot()
            return copy
        } catch {
            planError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Reminders

    @discardableResult
    func saveReminders(_ next: ReminderSettings) async throws -> ReminderScheduleResult {
        guard let repo, let user else { throw FormaError.notAuthenticated }
        isSavingReminders = true
        reminderError = nil
        defer { isSavingReminders = false }

        var settings = next
        settings.userId = user.id

        do {
            let result = try await NotificationService.shared.schedule(settings)
            settings.enabled = settings.enabled && result.count > 0
            settings.scheduledIds = result.count > 0 ? result.scheduledIds : []
            try await repo.saveReminderSettings(settings)
            reminders = settings
            return result
        } catch {
            settings.enabled = false
            settings.scheduledIds = []
            reminders = settings
            try? await repo.saveReminderSettings(settings)
            reminderError = error.localizedDescription
            throw error
        }
    }

    private func reconcileReminders() async {
        guard let repo, var settings = reminders, settings.enabled else { return }
        let pending = await NotificationService.shared.pendingAppOwnedCount()
        if pending == 0 {
            settings.enabled = false
            settings.scheduledIds = []
            reminders = settings
            try? await repo.saveReminderSettings(settings)
        }
    }

    // MARK: - Active workout

    func startWorkout(day: WorkoutDay) async throws {
        guard let user, let plan else { throw FormaError.notAuthenticated }
        guard activeWorkout == nil else {
            throw FormaError.message("Finish or discard your current workout before starting another.")
        }
        guard !day.exercises.isEmpty else {
            throw FormaError.message("This day has no exercises. Edit the plan or pick another day.")
        }
        let workout = ActiveWorkout(
            sessionId: IDs.uuid(),
            userId: user.id,
            planDayId: day.id,
            planId: plan.id,
            title: day.title,
            focus: day.focus,
            warmup: day.warmup,
            cooldown: day.cooldown,
            startedAt: StoredTimestamp.now(),
            status: .active,
            pausedAt: nil,
            pausedSeconds: 0,
            currentExerciseIndex: 0,
            exercises: day.exercises,
            sets: [],
            rest: nil
        )
        activeWorkout = workout
        workoutError = nil
        workoutSummary = nil
        Haptics.medium()
        await persistActiveWorkout()
        publishWidgetSnapshot()
    }

    private func persistActiveWorkout() async {
        guard let activeWorkout else { return }
        await LocalStore.shared.saveActiveWorkout(activeWorkout)
    }

    func currentExercise() -> WorkoutExercise? {
        activeWorkout?.currentExercise
    }

    func completedSetCount(for exercise: WorkoutExercise) -> Int {
        activeWorkout?.sets(for: exercise).count ?? 0
    }

    func completeSet(exercise: WorkoutExercise, reps: Int, weightKg: Double?) async {
        guard var workout = activeWorkout else { return }
        guard workout.status == .active else {
            workoutError = "Resume the workout before logging a set."
            return
        }
        guard workout.sets(for: exercise).count < exercise.sets else { return }

        let now = StoredTimestamp.now()
        let completed = CompletedSet(
            id: IDs.uuid(),
            sessionId: workout.sessionId,
            workoutExerciseId: exercise.id,
            exerciseId: exercise.exerciseId,
            setNumber: workout.sets(for: exercise).count + 1,
            reps: max(0, reps),
            weightKg: weightKg,
            completedAt: now
        )
        workout.sets.append(completed)

        let finishedExercise = workout.sets(for: exercise).count >= exercise.sets
        if finishedExercise,
           let next = workout.exercises.firstIndex(where: { $0.position > exercise.position && !workout.allSetsComplete(for: $0) }) {
            workout.currentExerciseIndex = next
        }

        if !workout.isComplete && exercise.restSeconds > 0 {
            workout.rest = ActiveRest(
                endsAt: now.addingTimeInterval(Double(exercise.restSeconds)),
                durationSeconds: exercise.restSeconds,
                pausedRemaining: nil,
                exerciseId: exercise.exerciseId
            )
        } else {
            workout.rest = nil
        }

        activeWorkout = workout
        Haptics.success()
        await persistActiveWorkout()
    }

    func removeLastSet(for exercise: WorkoutExercise) async {
        guard var workout = activeWorkout else { return }
        guard let index = workout.sets.lastIndex(where: { $0.workoutExerciseId == exercise.id }) else { return }
        workout.sets.remove(at: index)
        if let position = workout.exercises.firstIndex(where: { $0.id == exercise.id }) {
            workout.currentExerciseIndex = position
        }
        if workout.rest?.exerciseId == exercise.exerciseId {
            workout.rest = nil
        }
        activeWorkout = workout
        Haptics.light()
        await persistActiveWorkout()
    }

    func selectExercise(index: Int) async {
        guard var workout = activeWorkout, workout.exercises.indices.contains(index) else { return }
        workout.currentExerciseIndex = index
        activeWorkout = workout
        Haptics.selection()
        await persistActiveWorkout()
    }

    func skipExercise() async {
        guard var workout = activeWorkout else { return }
        guard let next = workout.exercises.indices.first(where: { $0 > workout.currentExerciseIndex && !workout.allSetsComplete(for: workout.exercises[$0]) }) else {
            return
        }
        workout.currentExerciseIndex = next
        workout.rest = nil
        activeWorkout = workout
        Haptics.light()
        await persistActiveWorkout()
    }

    func replaceExercise(_ exercise: WorkoutExercise, withId newId: String) async {
        guard var workout = activeWorkout,
              let index = workout.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        guard exercise.exerciseId != newId else { return }
        workout.exercises[index].exerciseId = newId
        workout.sets.removeAll { $0.workoutExerciseId == exercise.id }
        if workout.rest?.exerciseId == exercise.exerciseId {
            workout.rest = nil
        }
        activeWorkout = workout
        Haptics.medium()
        await persistActiveWorkout()
    }

    func startRest(seconds: Int, exerciseId: String) async {
        guard var workout = activeWorkout, seconds > 0 else { return }
        workout.rest = ActiveRest(
            endsAt: Date().addingTimeInterval(Double(seconds)),
            durationSeconds: seconds,
            pausedRemaining: nil,
            exerciseId: exerciseId
        )
        activeWorkout = workout
        await persistActiveWorkout()
    }

    func pauseRest() async {
        guard var workout = activeWorkout, var rest = workout.rest, rest.endsAt != nil else { return }
        rest.pausedRemaining = rest.remaining(at: Date())
        rest.endsAt = nil
        workout.rest = rest
        activeWorkout = workout
        Haptics.light()
        await persistActiveWorkout()
    }

    func resumeRest() async {
        guard var workout = activeWorkout, var rest = workout.rest, let remaining = rest.pausedRemaining else { return }
        rest.endsAt = Date().addingTimeInterval(Double(remaining))
        rest.pausedRemaining = nil
        workout.rest = rest
        activeWorkout = workout
        await persistActiveWorkout()
    }

    func skipRest() async {
        guard var workout = activeWorkout, workout.rest != nil else { return }
        workout.rest = nil
        activeWorkout = workout
        Haptics.light()
        await persistActiveWorkout()
    }

    func tickRest() async {
        guard var workout = activeWorkout, let rest = workout.rest else { return }
        let remaining = rest.remaining(at: Date())
        if remaining <= 0 && !rest.isPaused {
            workout.rest = nil
            activeWorkout = workout
            Haptics.success()
            await persistActiveWorkout()
        }
    }

    func pauseWorkout() async {
        guard var workout = activeWorkout, workout.status == .active else { return }
        let now = Date()
        if var rest = workout.rest, let endsAt = rest.endsAt {
            rest.pausedRemaining = max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
            rest.endsAt = nil
            workout.rest = rest
        }
        workout.status = .paused
        workout.pausedAt = now
        activeWorkout = workout
        Haptics.medium()
        await persistActiveWorkout()
    }

    func resumeWorkout() async {
        guard var workout = activeWorkout, workout.status == .paused else { return }
        let now = Date()
        if let pausedAt = workout.pausedAt {
            workout.pausedSeconds += max(0, Int(now.timeIntervalSince(pausedAt).rounded(.down)))
        }
        workout.pausedAt = nil
        workout.status = .active
        if var rest = workout.rest, let remaining = rest.pausedRemaining {
            rest.endsAt = now.addingTimeInterval(Double(remaining))
            rest.pausedRemaining = nil
            workout.rest = rest
        }
        activeWorkout = workout
        Haptics.medium()
        await persistActiveWorkout()
    }

    func finishWorkout() async {
        guard let workout = activeWorkout, let repo = repository else { return }
        isSavingWorkout = true
        workoutError = nil
        let ended = StoredTimestamp.now()
        let session = WorkoutSession(
            id: workout.sessionId,
            userId: workout.userId,
            planDayId: workout.planDayId,
            title: workout.title,
            focus: workout.focus,
            startedAt: workout.startedAt,
            endedAt: ended,
            durationSeconds: workout.elapsedSeconds(at: ended),
            status: .completed,
            sets: workout.sets,
            notes: nil
        )
        do {
            try await repo.saveSession(session)
            sessions.insert(session, at: 0)
            sessions.sort { $0.startedAt > $1.startedAt }
            workoutSummary = session
            activeWorkout = nil
            await LocalStore.shared.clearActiveWorkout(userId: workout.userId)
            Haptics.success()
            publishWidgetSnapshot()
        } catch {
            workoutError = error.localizedDescription
        }
        isSavingWorkout = false
    }

    func discardWorkout() async {
        guard let workout = activeWorkout else { return }
        activeWorkout = nil
        workoutSummary = nil
        workoutError = nil
        await LocalStore.shared.clearActiveWorkout(userId: workout.userId)
        publishWidgetSnapshot()
    }

    func dismissSummary() {
        workoutSummary = nil
    }

    // MARK: - Form analysis persistence

    func saveFormAnalysisSession(
        _ summary: FormAnalysisSessionSummary,
        sessionID: String
    ) async -> FormSessionSaveState {
        guard let repo, let user else {
            return .failed("Your local profile could not be loaded, so this session was not saved.")
        }
        let session = FormAnalysisSavedSession.workoutSession(
            for: summary,
            sessionID: sessionID,
            userId: user.id
        )
        mergeSession(session)
        publishWidgetSnapshot()
        do {
            try await repo.saveSession(session)
            pendingFormSessionIDs.remove(session.id)
            await LocalStore.shared.removePendingFormSession(id: session.id, userId: user.id)
            // A realtime refresh can run while the two writes are in flight;
            // re-merge the complete local record so measured data never blinks out.
            mergeSession(session)
            return .saved
        } catch {
            pendingFormSessionIDs.insert(session.id)
            await LocalStore.shared.enqueuePendingFormSession(session, userId: user.id)
            return .queued
        }
    }

    func isFormSessionPending(_ id: String) -> Bool {
        pendingFormSessionIDs.contains(id)
    }

    private func mergeSession(_ session: WorkoutSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.startedAt > $1.startedAt }
    }

    private func loadPendingFormSessions(userId: String) async {
        let pending = await LocalStore.shared.pendingFormSessions(userId: userId)
        pendingFormSessionIDs = Set(pending.map(\.id))
    }

    private func mergePendingFormSessions(userId: String) async {
        let pending = await LocalStore.shared.pendingFormSessions(userId: userId)
        pendingFormSessionIDs = Set(pending.map(\.id))
        for session in pending {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                // The local copy carries the measured form record even when a
                // partial remote write left an empty session row behind.
                sessions[index] = session
            } else {
                sessions.append(session)
            }
        }
        sessions.sort { $0.startedAt > $1.startedAt }
    }

    private func flushPendingFormSessions() async {
        guard let repo, let user, !pendingFormSessionIDs.isEmpty else { return }
        let pending = await LocalStore.shared.pendingFormSessions(userId: user.id)
        for session in pending {
            do {
                try await repo.saveSession(session)
                await LocalStore.shared.removePendingFormSession(id: session.id, userId: user.id)
                pendingFormSessionIDs.remove(session.id)
            } catch {
                break
            }
        }
    }

    // MARK: - Progress

    func addCheckIn(weightKg: Double?, notes: String) async throws -> ProgressRecord {
        guard let repo, let user else { throw FormaError.notAuthenticated }
        isSavingCheckIn = true
        defer { isSavingCheckIn = false }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = ProgressRecord(
            id: IDs.uuid(),
            userId: user.id,
            recordedAt: StoredTimestamp.now(),
            bodyweightKg: weightKg,
            notes: trimmed.isEmpty ? nil : trimmed
        )
        try await repo.addProgressRecord(record)
        progressRecords.insert(record, at: 0)
        return record
    }

    // MARK: - Health

    func requestHealthAccess() async {
        healthBusy = true
        healthError = nil
        do {
            _ = try await HealthKitService.shared.requestAuthorization()
            healthOptIn = true
            await loadHealth()
        } catch {
            healthError = error.localizedDescription
            healthOptIn = false
        }
        healthBusy = false
    }

    func loadHealth() async {
        guard healthOptIn else { return }
        healthBusy = true
        healthError = nil
        do {
            healthSummary = try await HealthKitService.shared.fetchSummary()
            healthFetched = true
        } catch {
            healthError = error.localizedDescription
        }
        healthBusy = false
    }

    func disableHealth() {
        healthOptIn = false
        healthSummary = nil
        healthFetched = false
        healthError = nil
    }
}
