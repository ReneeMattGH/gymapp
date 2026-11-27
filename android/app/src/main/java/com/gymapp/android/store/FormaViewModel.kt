package com.gymapp.android.store

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.gymapp.android.core.AppConfig
import com.gymapp.android.core.FormaDate
import com.gymapp.android.core.IDs
import com.gymapp.android.core.StoredTimestamp
import com.gymapp.android.data.ExerciseCatalogLoader
import com.gymapp.android.data.LocalRepository
import com.gymapp.android.data.local.FormaDatabase
import com.gymapp.android.data.remote.AccountService
import com.gymapp.android.data.remote.AccountUser
import com.gymapp.android.data.remote.ApiClient
import com.gymapp.android.data.remote.ApiException
import com.gymapp.android.data.remote.PendingVerificationState
import com.gymapp.android.domain.ActiveRest
import com.gymapp.android.domain.ActiveWorkout
import com.gymapp.android.domain.CompletedSet
import com.gymapp.android.domain.Equipment
import com.gymapp.android.domain.Exercise
import com.gymapp.android.domain.ExerciseCatalog
import com.gymapp.android.domain.Experience
import com.gymapp.android.domain.Goal
import com.gymapp.android.domain.PlanStatus
import com.gymapp.android.domain.PlanValidator
import com.gymapp.android.domain.PlanGenerator
import com.gymapp.android.domain.Preferences
import com.gymapp.android.domain.Profile
import com.gymapp.android.domain.ProgressRecord
import com.gymapp.android.domain.ReminderSettings
import com.gymapp.android.domain.SessionStatus
import com.gymapp.android.domain.ThemeMode
import com.gymapp.android.domain.TrainingEnvironment
import com.gymapp.android.domain.UnitSystem
import com.gymapp.android.domain.WorkoutDay
import com.gymapp.android.domain.WorkoutExercise
import com.gymapp.android.domain.WorkoutPlan
import com.gymapp.android.domain.WorkoutRunStatus
import com.gymapp.android.domain.WorkoutSession
import com.gymapp.android.notifications.ReminderPermissionException
import com.gymapp.android.notifications.ReminderScheduler
import com.gymapp.android.widget.WidgetUpdater
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class OnboardingOutcome(
    val planName: String,
    val trainingDays: Int,
    val reminderMessage: String,
    val scheduledCount: Int,
)

data class FormaUiState(
    val bootstrapping: Boolean = true,
    val loadError: String? = null,
    val userId: String = "",
    val profile: Profile? = null,
    val preferences: Preferences? = null,
    val plan: WorkoutPlan? = null,
    val sessions: List<WorkoutSession> = emptyList(),
    val exercises: List<Exercise> = emptyList(),
    val reminders: ReminderSettings? = null,
    val progress: List<ProgressRecord> = emptyList(),
    val activeWorkout: ActiveWorkout? = null,
    val workoutSummary: WorkoutSession? = null,
    val workoutError: String? = null,
    val isSavingWorkout: Boolean = false,
    val onboardingOutcome: OnboardingOutcome? = null,
    val isCompletingOnboarding: Boolean = false,
    val isGeneratingPlan: Boolean = false,
    val planError: String? = null,
    val isSavingCheckIn: Boolean = false,
    val themeMode: ThemeMode = ThemeMode.DARK,
    val account: AccountUser? = null,
    val accountConfigured: Boolean = false,
    val accountBusy: Boolean = false,
    val accountError: String? = null,
    val accountNotice: String? = null,
    val pendingVerification: PendingVerificationState? = null,
    val pendingResetToken: String? = null,
    val localProfiles: List<Profile> = emptyList(),
    val favoriteExercises: Set<String> = emptySet(),
    val recentExercises: List<String> = emptyList(),
) {
    val needsOnboarding: Boolean get() = profile?.onboardingCompleted != true
    val completedSessions: List<WorkoutSession>
        get() = sessions.filter { it.status == SessionStatus.COMPLETED && it.endedAt != null }
    val units: UnitSystem get() = preferences?.units ?: UnitSystem.KG
    val todayDay: WorkoutDay?
        get() = plan?.let { PlanGenerator.planForDate(it, System.currentTimeMillis()) }
    val nextDay: WorkoutDay?
        get() = plan?.let { PlanGenerator.nextTrainingDay(it, System.currentTimeMillis()) }
    val latestCheckIn: ProgressRecord? get() = progress.firstOrNull()
}

class FormaViewModel(application: Application) : AndroidViewModel(application) {
    private val _state = MutableStateFlow(FormaUiState())
    val state: StateFlow<FormaUiState> = _state.asStateFlow()

    private val app = application
    private val settings = application.getSharedPreferences("forma.settings", android.content.Context.MODE_PRIVATE)
    private val reminderScheduler = ReminderScheduler(application)
    private var repository: LocalRepository? = null
    private var accountService: AccountService? = null

    private val accountConfigured = AppConfig.isBackendConfigured

    init {
        val theme = ThemeMode.from(settings.getString(KEY_THEME, ThemeMode.DARK.name))
        val favorites = settings.getStringSet(KEY_FAVORITES, emptySet()).orEmpty().toSet()
        val recent = settings.getString(KEY_RECENT, null)
            ?.split("|")
            ?.filter { it.isNotBlank() }
            .orEmpty()
        _state.update {
            it.copy(
                themeMode = theme,
                accountConfigured = accountConfigured,
                favoriteExercises = favorites,
                recentExercises = recent,
            )
        }
        if (accountConfigured) {
            accountService = AccountService(ApiClient(application, AppConfig.apiBaseUrl))
        }
        bootstrap()
    }

    // MARK: - Bootstrap

    fun bootstrap() {
        viewModelScope.launch {
            _state.update { it.copy(bootstrapping = true, loadError = null) }
            try {
                val catalog = withContext(Dispatchers.IO) {
                    ExerciseCatalogLoader.load(app)
                }
                ExerciseCatalog.initialize(catalog)
                val repo = LocalRepository(FormaDatabase.get(app))
                repository = repo

                val profiles = repo.listProfiles()
                val activeId = repo.activeProfileId()
                val active = profiles.firstOrNull { it.id == activeId } ?: profiles.firstOrNull()
                val userId = active?.id ?: IDs.uuid()
                if (active != null) repo.setActiveProfileId(active.id)

                val preferences = repo.getPreferences(userId)
                val plan = repo.getActivePlan(userId)
                val sessions = repo.getSessions(userId)
                val reminders = repo.getReminderSettings(userId)
                val progress = repo.listProgressRecords(userId)
                val workout = repo.loadActiveWorkout(userId)

                _state.update {
                    it.copy(
                        bootstrapping = false,
                        userId = userId,
                        profile = active,
                        preferences = preferences,
                        plan = plan,
                        sessions = sessions,
                        exercises = catalog,
                        reminders = reminders,
                        progress = progress,
                        activeWorkout = workout,
                        workoutSummary = null,
                        localProfiles = profiles,
                    )
                }
                rescheduleReminders(reminders)
                publishWidgets()
                restoreAccount()
            } catch (error: Exception) {
                _state.update {
                    it.copy(bootstrapping = false, loadError = error.message ?: "The local database could not be opened.")
                }
            }
        }
    }

    private fun restoreAccount() {
        val service = accountService ?: return
        viewModelScope.launch {
            val user = service.restoreSession()
            val pending = service.tokenStore.pendingVerification()
            _state.update { it.copy(account = user, pendingVerification = pending) }
        }
    }

    private fun rescheduleReminders(settings: ReminderSettings) {
        if (!settings.enabled) return
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { reminderScheduler.schedule(settings) }
        }
    }

    /** Mirrors iOS: the widget reloads only after a real write, never on a timer. */
    private fun publishWidgets() = WidgetUpdater.publish(app)

    // MARK: - Theme & units

    fun setThemeMode(mode: ThemeMode) {
        settings.edit().putString(KEY_THEME, mode.name).apply()
        _state.update { it.copy(themeMode = mode) }
    }

    fun setUnits(units: UnitSystem) {
        val prefs = _state.value.preferences ?: return
        viewModelScope.launch { savePreferences(prefs.copy(units = units)) }
    }

    // MARK: - Onboarding

    fun completeOnboarding(input: OnboardingInput) {
        val repo = repository ?: return
        viewModelScope.launch {
            _state.update { it.copy(isCompletingOnboarding = true) }
            try {
                val userId = _state.value.userId
                val profile = Profile(
                    id = userId,
                    name = input.name.trim(),
                    age = input.age,
                    experience = input.experience,
                    environment = input.environment,
                    goals = input.goals,
                    limitations = input.limitations.trim().takeIf { it.isNotEmpty() },
                    onboardingCompleted = true,
                    createdAt = StoredTimestamp.now(),
                )
                val preferences = Preferences(
                    userId = userId,
                    workoutDays = input.days.sorted(),
                    sessionMinutes = input.minutes,
                    equipment = input.equipment.toList(),
                    avoidExercises = input.avoid,
                    reminderTime = input.reminderTime,
                    units = UnitSystem.KG,
                )
                repo.saveProfile(profile)
                repo.savePreferences(preferences)
                repo.setActiveProfileId(userId)

                val plan = PlanGenerator.generateLocalPlan(userId, profile, preferences)
                if (plan == null) {
                    _state.update {
                        it.copy(
                            isCompletingOnboarding = false,
                            loadError = "The exercise library could not be loaded, so a plan could not be built.",
                        )
                    }
                    return@launch
                }
                repo.savePlan(plan)

                var reminders = ReminderSettings(
                    userId = userId,
                    enabled = input.remindersOn,
                    workoutTime = input.reminderTime,
                    days = input.days.sorted(),
                    restDayReminders = true,
                    hydrationReminders = false,
                    weeklyProgressReminder = true,
                )
                var message: String
                var scheduled = 0
                if (reminders.enabled) {
                    try {
                        val result = withContext(Dispatchers.IO) { reminderScheduler.schedule(reminders) }
                        reminders = reminders.copy(
                            enabled = result.count > 0,
                            scheduledIds = result.scheduledIds,
                        )
                        message = result.message
                        scheduled = result.count
                    } catch (error: ReminderPermissionException) {
                        reminders = reminders.copy(enabled = false, scheduledIds = emptyList())
                        message = error.message ?: "Reminders could not be scheduled."
                    }
                } else {
                    reminders = reminders.copy(scheduledIds = emptyList())
                    message = "Reminders are off. You can enable them in Profile → Reminders."
                }
                repo.saveReminderSettings(reminders)

                _state.update {
                    it.copy(
                        isCompletingOnboarding = false,
                        profile = profile,
                        preferences = preferences,
                        plan = plan,
                        reminders = reminders,
                        localProfiles = repo.listProfiles(),
                        onboardingOutcome = OnboardingOutcome(
                            planName = plan.name,
                            trainingDays = plan.daysPerWeek,
                            reminderMessage = message,
                            scheduledCount = scheduled,
                        ),
                    )
                }
                publishWidgets()
            } catch (error: Exception) {
                _state.update {
                    it.copy(
                        isCompletingOnboarding = false,
                        loadError = error.message ?: "Onboarding could not be saved.",
                    )
                }
            }
        }
    }

    fun dismissPlanReady() {
        _state.update { it.copy(onboardingOutcome = null) }
    }

    // MARK: - Preferences

    private suspend fun savePreferences(next: Preferences) {
        repository?.savePreferences(next)
        _state.update { it.copy(preferences = next) }
        publishWidgets()
    }

    fun updateSchedule(days: List<Int>, minutes: Int) {
        val prefs = _state.value.preferences ?: return
        viewModelScope.launch { savePreferences(prefs.copy(workoutDays = days.sorted(), sessionMinutes = minutes)) }
    }

    fun updateEquipment(equipment: Set<Equipment>) {
        val prefs = _state.value.preferences ?: return
        viewModelScope.launch { savePreferences(prefs.copy(equipment = equipment.toList())) }
    }

    // MARK: - Plans

    fun rebuildPlan(onDone: (String?) -> Unit = {}) {
        val repo = repository ?: return
        val state = _state.value
        val profile = state.profile ?: return onDone("Finish onboarding first.")
        val preferences = state.preferences ?: return onDone("Finish onboarding first.")
        viewModelScope.launch {
            _state.update { it.copy(isGeneratingPlan = true, planError = null) }
            val next = PlanGenerator.generateLocalPlan(state.userId, profile, preferences, state.exercises)
            if (next == null) {
                _state.update { it.copy(isGeneratingPlan = false, planError = "The plan could not be generated.") }
                onDone("The plan could not be generated.")
                return@launch
            }
            val issue = PlanValidator.firstError(PlanValidator.structureIssues(next, state.exercises))
            if (issue != null) {
                _state.update { it.copy(isGeneratingPlan = false, planError = issue) }
                onDone(issue)
                return@launch
            }
            repo.savePlan(next)
            _state.update { it.copy(isGeneratingPlan = false, plan = next) }
            publishWidgets()
            onDone(null)
        }
    }

    fun buildPlanDraft(onResult: (WorkoutPlan?, String?) -> Unit) {
        val state = _state.value
        val profile = state.profile ?: return onResult(null, "Finish onboarding first.")
        val preferences = state.preferences ?: return onResult(null, "Finish onboarding first.")
        val next = PlanGenerator.generateLocalPlan(state.userId, profile, preferences, state.exercises)
            ?: return onResult(null, "The plan could not be generated.")
        val issue = PlanValidator.firstError(PlanValidator.structureIssues(next, state.exercises))
        if (issue != null) return onResult(null, issue)
        onResult(next, null)
    }

    fun adoptEditedPlan(plan: WorkoutPlan, onDone: (String?) -> Unit = {}) {
        val repo = repository ?: return
        val state = _state.value
        viewModelScope.launch {
            val issue = PlanValidator.firstError(PlanValidator.structureIssues(plan, state.exercises))
            if (issue != null) {
                onDone(issue)
                return@launch
            }
            repo.savePlan(plan)
            _state.update { it.copy(plan = plan) }
            publishWidgets()
            onDone(null)
        }
    }

    // MARK: - Active workout

    fun startWorkout(day: WorkoutDay, onError: (String) -> Unit = {}) {
        val state = _state.value
        if (state.activeWorkout != null) {
            onError("Finish or discard your current workout before starting another.")
            return
        }
        if (day.exercises.isEmpty()) {
            onError("This day has no exercises. Pick another day.")
            return
        }
        val plan = state.plan ?: return onError("No plan is active.")
        val workout = ActiveWorkout(
            sessionId = IDs.uuid(),
            userId = state.userId,
            planDayId = day.id,
            planId = plan.id,
            title = day.title,
            focus = day.focus,
            warmup = day.warmup,
            cooldown = day.cooldown,
            startedAt = StoredTimestamp.now(),
            status = WorkoutRunStatus.ACTIVE,
            currentExerciseIndex = 0,
            exercises = day.exercises,
            sets = emptyList(),
            rest = null,
        )
        _state.update { it.copy(activeWorkout = workout, workoutSummary = null, workoutError = null) }
        persist(workout, publish = true)
    }

    private fun updateWorkout(transform: (ActiveWorkout) -> ActiveWorkout) {
        val current = _state.value.activeWorkout ?: return
        val next = transform(current)
        _state.update { it.copy(activeWorkout = next) }
        persist(next)
    }

    private fun persist(workout: ActiveWorkout, publish: Boolean = false) {
        val repo = repository ?: return
        viewModelScope.launch(Dispatchers.IO) {
            repo.saveActiveWorkout(workout)
            if (publish) publishWidgets()
        }
    }

    fun completeSet(exercise: WorkoutExercise, reps: Int, weightKg: Double?) {
        val workout = _state.value.activeWorkout ?: return
        if (workout.status != WorkoutRunStatus.ACTIVE) {
            _state.update { it.copy(workoutError = "Resume the workout before logging a set.") }
            return
        }
        if (workout.setsFor(exercise).size >= exercise.sets) return

        val now = StoredTimestamp.now()
        val completed = CompletedSet(
            id = IDs.uuid(),
            sessionId = workout.sessionId,
            workoutExerciseId = exercise.id,
            exerciseId = exercise.exerciseId,
            setNumber = workout.setsFor(exercise).size + 1,
            reps = maxOf(0, reps),
            weightKg = weightKg,
            completedAt = now,
        )
        val sets = workout.sets + completed
        val next = workout.copy(sets = sets)

        val finishedExercise = sets.count { it.workoutExerciseId == exercise.id } >= exercise.sets
        val advanced = if (finishedExercise) {
            val nextIndex = next.exercises.indices.firstOrNull { index ->
                val candidate = next.exercises[index]
                candidate.position > exercise.position && !next.allSetsComplete(candidate)
            }
            if (nextIndex != null) next.copy(currentExerciseIndex = nextIndex) else next
        } else {
            next
        }

        val withRest = if (!advanced.isComplete && exercise.restSeconds > 0) {
            advanced.copy(
                rest = ActiveRest(
                    endsAt = now + exercise.restSeconds * 1000L,
                    durationSeconds = exercise.restSeconds,
                    exerciseId = exercise.exerciseId,
                ),
            )
        } else {
            advanced.copy(rest = null)
        }
        _state.update { it.copy(activeWorkout = withRest) }
        persist(withRest)
    }

    fun removeLastSet(exercise: WorkoutExercise) {
        updateWorkout { workout ->
            val index = workout.sets.indexOfLast { it.workoutExerciseId == exercise.id }
            if (index < 0) return@updateWorkout workout
            val sets = workout.sets.toMutableList().apply { removeAt(index) }
            val position = workout.exercises.indexOfFirst { it.id == exercise.id }
            workout.copy(
                sets = sets,
                currentExerciseIndex = if (position >= 0) position else workout.currentExerciseIndex,
                rest = if (workout.rest?.exerciseId == exercise.exerciseId) null else workout.rest,
            )
        }
    }

    fun selectExercise(index: Int) {
        updateWorkout { workout ->
            if (index !in workout.exercises.indices) workout
            else workout.copy(currentExerciseIndex = index)
        }
    }

    fun skipExercise() {
        updateWorkout { workout ->
            val next = workout.exercises.indices.firstOrNull { index ->
                index > workout.currentExerciseIndex && !workout.allSetsComplete(workout.exercises[index])
            }
            if (next == null) workout
            else workout.copy(currentExerciseIndex = next, rest = null)
        }
    }

    fun replaceExercise(exercise: WorkoutExercise, newId: String) {
        if (exercise.exerciseId == newId) return
        updateWorkout { workout ->
            val index = workout.exercises.indexOfFirst { it.id == exercise.id }
            if (index < 0) return@updateWorkout workout
            val exercises = workout.exercises.toMutableList()
            exercises[index] = exercises[index].copy(exerciseId = newId)
            workout.copy(
                exercises = exercises,
                sets = workout.sets.filterNot { it.workoutExerciseId == exercise.id },
                rest = if (workout.rest?.exerciseId == exercise.exerciseId) null else workout.rest,
            )
        }
    }

    fun pauseRest() {
        updateWorkout { workout ->
            val rest = workout.rest ?: return@updateWorkout workout
            if (rest.endsAt == null) return@updateWorkout workout
            workout.copy(
                rest = rest.copy(
                    pausedRemaining = rest.remaining(StoredTimestamp.now()),
                    endsAt = null,
                ),
            )
        }
    }

    fun resumeRest() {
        updateWorkout { workout ->
            val rest = workout.rest ?: return@updateWorkout workout
            val remaining = rest.pausedRemaining ?: return@updateWorkout workout
            workout.copy(
                rest = rest.copy(
                    endsAt = StoredTimestamp.now() + remaining * 1000L,
                    pausedRemaining = null,
                ),
            )
        }
    }

    fun skipRest() {
        updateWorkout { workout -> workout.copy(rest = null) }
    }

    fun tickRest() {
        val workout = _state.value.activeWorkout ?: return
        val rest = workout.rest ?: return
        if (!rest.isPaused && rest.remaining(StoredTimestamp.now()) <= 0) {
            updateWorkout { it.copy(rest = null) }
        }
    }

    fun pauseWorkout() {
        updateWorkout { workout ->
            if (workout.status != WorkoutRunStatus.ACTIVE) return@updateWorkout workout
            val now = StoredTimestamp.now()
            val rest = workout.rest?.let { current ->
                current.endsAt?.let {
                    current.copy(pausedRemaining = current.remaining(now), endsAt = null)
                } ?: current
            }
            workout.copy(status = WorkoutRunStatus.PAUSED, pausedAt = now, rest = rest)
        }
    }

    fun resumeWorkout() {
        updateWorkout { workout ->
            if (workout.status != WorkoutRunStatus.PAUSED) return@updateWorkout workout
            val now = StoredTimestamp.now()
            val pausedSeconds = workout.pausedSeconds +
                if (workout.pausedAt != null) ((now - workout.pausedAt) / 1000).toInt().coerceAtLeast(0) else 0
            val rest = workout.rest?.let { current ->
                current.pausedRemaining?.let {
                    current.copy(endsAt = now + it * 1000L, pausedRemaining = null)
                } ?: current
            }
            workout.copy(
                status = WorkoutRunStatus.ACTIVE,
                pausedAt = null,
                pausedSeconds = pausedSeconds,
                rest = rest,
            )
        }
    }

    fun finishWorkout() {
        val repo = repository ?: return
        val workout = _state.value.activeWorkout ?: return
        viewModelScope.launch {
            _state.update { it.copy(isSavingWorkout = true, workoutError = null) }
            val ended = StoredTimestamp.now()
            val session = WorkoutSession(
                id = workout.sessionId,
                userId = workout.userId,
                planDayId = workout.planDayId,
                title = workout.title,
                focus = workout.focus,
                startedAt = workout.startedAt,
                endedAt = ended,
                durationSeconds = workout.elapsedSeconds(ended),
                status = SessionStatus.COMPLETED,
                sets = workout.sets,
            )
            try {
                repo.saveSession(session)
                withContext(Dispatchers.IO) { repo.clearActiveWorkout(workout.userId) }
                val sessions = (_state.value.sessions + session).sortedByDescending { it.startedAt }
                _state.update {
                    it.copy(
                        isSavingWorkout = false,
                        sessions = sessions,
                        workoutSummary = session,
                        activeWorkout = null,
                    )
                }
                publishWidgets()
            } catch (error: Exception) {
                _state.update {
                    it.copy(isSavingWorkout = false, workoutError = error.message ?: "The workout could not be saved.")
                }
            }
        }
    }

    fun discardWorkout() {
        val repo = repository
        val workout = _state.value.activeWorkout ?: return
        _state.update { it.copy(activeWorkout = null, workoutSummary = null, workoutError = null) }
        viewModelScope.launch(Dispatchers.IO) {
            repo?.clearActiveWorkout(workout.userId)
            publishWidgets()
        }
    }

    fun dismissSummary() {
        _state.update { it.copy(workoutSummary = null) }
    }

    // MARK: - Progress

    fun addCheckIn(weightKg: Double?, notes: String, onDone: (String?) -> Unit = {}) {
        val repo = repository ?: return
        val state = _state.value
        viewModelScope.launch {
            _state.update { it.copy(isSavingCheckIn = true) }
            val trimmed = notes.trim()
            val record = ProgressRecord(
                id = IDs.uuid(),
                userId = state.userId,
                recordedAt = StoredTimestamp.now(),
                bodyweightKg = weightKg,
                notes = trimmed.takeIf { it.isNotEmpty() },
            )
            try {
                repo.saveProgressRecord(record)
                val next = (listOf(record) + state.progress).sortedByDescending { it.recordedAt }
                _state.update { it.copy(isSavingCheckIn = false, progress = next) }
                onDone(null)
            } catch (error: Exception) {
                _state.update { it.copy(isSavingCheckIn = false) }
                onDone(error.message ?: "The check-in could not be saved.")
            }
        }
    }

    // MARK: - Reminders

    fun saveReminders(next: ReminderSettings, onDone: (String?) -> Unit = {}) {
        val repo = repository ?: return
        viewModelScope.launch {
            val result = runCatching {
                withContext(Dispatchers.IO) { reminderScheduler.schedule(next) }
            }
            val error = result.exceptionOrNull()
            val settingsToSave = if (result.isSuccess) {
                val value = result.getOrThrow()
                next.copy(enabled = value.count > 0, scheduledIds = value.scheduledIds)
            } else {
                next.copy(enabled = false, scheduledIds = emptyList())
            }
            repo.saveReminderSettings(settingsToSave)
            _state.update { it.copy(reminders = settingsToSave) }
            if (error != null) {
                onDone(error.message ?: "Reminders could not be scheduled.")
            } else {
                onDone(null)
            }
        }
    }

    // MARK: - Account

    private fun accountError(error: Exception): String = when (error) {
        is ApiException -> error.message
        else -> error.message ?: "Something went wrong."
    }

    fun register(name: String, email: String, password: String, onDone: (String?) -> Unit) {
        val service = accountService ?: return onDone("This build has no account server configured.")
        viewModelScope.launch {
            _state.update { it.copy(accountBusy = true, accountError = null, accountNotice = null) }
            try {
                val result = service.register(name, email, password)
                val pending = PendingVerificationState(
                    email = result.user.email,
                    resendAvailableAt = System.currentTimeMillis() + result.resendAfterSeconds * 1000L,
                    codeExpiresAt = System.currentTimeMillis() + result.expiresInSeconds * 1000L,
                )
                service.tokenStore.savePendingVerification(pending)
                _state.update {
                    it.copy(
                        accountBusy = false,
                        pendingVerification = pending,
                        accountNotice = if (result.otpSent) {
                            "We emailed a six-digit code. It works once and expires in ten minutes."
                        } else {
                            "The account was created, but no code was delivered. Request a new one below."
                        },
                    )
                }
                onDone(null)
            } catch (error: Exception) {
                val message = accountError(error)
                _state.update { it.copy(accountBusy = false, accountError = message) }
                onDone(message)
            }
        }
    }

    fun signIn(email: String, password: String, onDone: (String?) -> Unit) {
        val service = accountService ?: return onDone("This build has no account server configured.")
        viewModelScope.launch {
            _state.update { it.copy(accountBusy = true, accountError = null, accountNotice = null) }
            try {
                val user = service.login(email, password)
                service.tokenStore.savePendingVerification(null)
                _state.update { it.copy(accountBusy = false, account = user, pendingVerification = null) }
                onDone(null)
            } catch (error: ApiException) {
                if (error.isEmailNotVerified) {
                    val pending = PendingVerificationState(
                        email = email.trim(),
                        resendAvailableAt = 0L,
                        codeExpiresAt = System.currentTimeMillis() + 600_000L,
                    )
                    service.tokenStore.savePendingVerification(pending)
                    _state.update {
                        it.copy(
                            accountBusy = false,
                            pendingVerification = pending,
                            accountNotice = error.message,
                        )
                    }
                    onDone(null)
                } else {
                    val message = accountError(error)
                    _state.update { it.copy(accountBusy = false, accountError = message) }
                    onDone(message)
                }
            } catch (error: Exception) {
                val message = accountError(error)
                _state.update { it.copy(accountBusy = false, accountError = message) }
                onDone(message)
            }
        }
    }

    fun verifyOtp(code: String, onDone: (String?) -> Unit) {
        val service = accountService ?: return onDone("This build has no account server configured.")
        val pending = _state.value.pendingVerification ?: return onDone("Start again with your email address.")
        viewModelScope.launch {
            _state.update { it.copy(accountBusy = true, accountError = null) }
            try {
                val user = service.verifyOtp(pending.email, code)
                service.tokenStore.savePendingVerification(null)
                _state.update {
                    it.copy(
                        accountBusy = false,
                        account = user,
                        pendingVerification = null,
                        accountNotice = "Email verified. You are signed in on this device.",
                    )
                }
                onDone(null)
            } catch (error: Exception) {
                val message = accountError(error)
                _state.update { it.copy(accountBusy = false, accountError = message) }
                onDone(message)
            }
        }
    }

    fun resendOtp(onDone: (String?) -> Unit) {
        val service = accountService ?: return onDone("This build has no account server configured.")
        val pending = _state.value.pendingVerification ?: return onDone("Start again with your email address.")
        viewModelScope.launch {
            _state.update { it.copy(accountBusy = true, accountError = null) }
            try {
                val result = service.resendOtp(pending.email)
                val next = pending.copy(
                    resendAvailableAt = System.currentTimeMillis() + result.resendAfterSeconds * 1000L,
                )
                service.tokenStore.savePendingVerification(next)
                _state.update {
                    it.copy(
                        accountBusy = false,
                        pendingVerification = next,
                        accountNotice = "If that address needs a code, a new one is on its way.",
                    )
                }
                onDone(null)
            } catch (error: Exception) {
                val message = accountError(error)
                _state.update { it.copy(accountBusy = false, accountError = message) }
                onDone(message)
            }
        }
    }

    fun cancelPendingVerification() {
        val service = accountService ?: return
        viewModelScope.launch {
            service.tokenStore.savePendingVerification(null)
            _state.update { it.copy(pendingVerification = null, accountNotice = null, accountError = null) }
        }
    }

    /** Re-opens the code step for an account that signed in but never verified its email. */
    fun beginVerification(email: String) {
        val service = accountService ?: return
        viewModelScope.launch {
            val pending = PendingVerificationState(
                email = email,
                resendAvailableAt = 0L,
                codeExpiresAt = System.currentTimeMillis() + 600_000L,
            )
            service.tokenStore.savePendingVerification(pending)
            _state.update {
                it.copy(
                    pendingVerification = pending,
                    accountError = null,
                    accountNotice = "Request a new code below if the last one expired.",
                )
            }
        }
    }

    fun signOut(onDone: () -> Unit = {}) {
        val service = accountService ?: return onDone()
        viewModelScope.launch {
            service.signOut()
            service.tokenStore.savePendingVerification(null)
            _state.update { it.copy(account = null, pendingVerification = null, accountNotice = null) }
            onDone()
        }
    }

    fun requestPasswordReset(email: String, onDone: (String?) -> Unit) {
        val service = accountService ?: return onDone("This build has no account server configured.")
        viewModelScope.launch {
            _state.update { it.copy(accountBusy = true, accountError = null) }
            try {
                service.requestPasswordReset(email.trim())
                _state.update {
                    it.copy(accountBusy = false, accountNotice = "If that address has an account, a reset link is on its way.")
                }
                onDone(null)
            } catch (error: Exception) {
                val message = accountError(error)
                _state.update { it.copy(accountBusy = false, accountError = message) }
                onDone(message)
            }
        }
    }

    fun confirmPasswordReset(token: String, password: String, onDone: (String?) -> Unit) {
        val service = accountService ?: return onDone("This build has no account server configured.")
        viewModelScope.launch {
            _state.update { it.copy(accountBusy = true, accountError = null) }
            try {
                service.confirmPasswordReset(token, password)
                _state.update {
                    it.copy(accountBusy = false, accountNotice = "Password updated. Sign in with the new password.")
                }
                onDone(null)
            } catch (error: Exception) {
                val message = accountError(error)
                _state.update { it.copy(accountBusy = false, accountError = message) }
                onDone(message)
            }
        }
    }

    fun changePassword(current: String, new: String, onDone: (String?) -> Unit) {
        val service = accountService ?: return onDone("This build has no account server configured.")
        viewModelScope.launch {
            _state.update { it.copy(accountBusy = true, accountError = null) }
            try {
                service.changePassword(current, new)
                _state.update { it.copy(accountBusy = false, accountNotice = "Password changed.") }
                onDone(null)
            } catch (error: Exception) {
                val message = accountError(error)
                _state.update { it.copy(accountBusy = false, accountError = message) }
                onDone(message)
            }
        }
    }

    fun deleteAccount(password: String, onDone: (String?) -> Unit) {
        val service = accountService ?: return onDone("This build has no account server configured.")
        viewModelScope.launch {
            _state.update { it.copy(accountBusy = true, accountError = null) }
            try {
                service.deleteAccount(password)
                _state.update { it.copy(accountBusy = false, account = null, accountNotice = "Your account was deleted.") }
                onDone(null)
            } catch (error: Exception) {
                val message = accountError(error)
                _state.update { it.copy(accountBusy = false, accountError = message) }
                onDone(message)
            }
        }
    }

    fun clearAccountMessages() {
        _state.update { it.copy(accountError = null) }
    }

    fun clearNotice() {
        _state.update { it.copy(accountNotice = null) }
    }

    fun setPendingResetToken(token: String?) {
        _state.update { it.copy(pendingResetToken = token) }
    }

    // MARK: - Local profiles

    fun toggleFavorite(id: String) {
        val next = _state.value.favoriteExercises.toMutableSet().apply {
            if (!add(id)) remove(id)
        }
        settings.edit().putStringSet(KEY_FAVORITES, next).apply()
        _state.update { it.copy(favoriteExercises = next) }
    }

    fun recordExerciseView(id: String) {
        val next = (listOf(id) + _state.value.recentExercises.filter { it != id }).take(12)
        settings.edit().putString(KEY_RECENT, next.joinToString("|")).apply()
        _state.update { it.copy(recentExercises = next) }
    }

    fun saveProfile(profile: Profile, onDone: (String?) -> Unit = {}) {
        val repo = repository ?: return onDone("The local database is not ready.")
        viewModelScope.launch {
            runCatching {
                repo.saveProfile(profile)
                _state.update { it.copy(profile = profile, localProfiles = repo.listProfiles()) }
            }.onSuccess { onDone(null) }
                .onFailure { onDone(it.message ?: "The profile could not be saved.") }
        }
    }

    fun saveTrainingProfile(profile: Profile, preferences: Preferences, onDone: (String?) -> Unit = {}) {
        val repo = repository ?: return onDone("The local database is not ready.")
        viewModelScope.launch {
            runCatching {
                repo.saveProfile(profile)
                repo.savePreferences(preferences)
                _state.update {
                    it.copy(
                        profile = profile,
                        preferences = preferences,
                        localProfiles = repo.listProfiles(),
                    )
                }
                publishWidgets()
            }.onSuccess { onDone(null) }
                .onFailure { onDone(it.message ?: "Your changes could not be saved.") }
        }
    }

    fun switchProfile(id: String) {
        val repo = repository ?: return
        if (id == _state.value.userId) return
        viewModelScope.launch {
            val profile = repo.getProfile(id) ?: return@launch
            repo.setActiveProfileId(id)
            val preferences = repo.getPreferences(id)
            val plan = repo.getActivePlan(id)
            val sessions = repo.getSessions(id)
            val reminders = repo.getReminderSettings(id)
            val progress = repo.listProgressRecords(id)
            val workout = repo.loadActiveWorkout(id)
            _state.update {
                it.copy(
                    userId = id,
                    profile = profile,
                    preferences = preferences,
                    plan = plan,
                    sessions = sessions,
                    reminders = reminders,
                    progress = progress,
                    activeWorkout = workout,
                    workoutSummary = null,
                    onboardingOutcome = null,
                    planError = null,
                    workoutError = null,
                )
            }
            rescheduleReminders(reminders)
            publishWidgets()
        }
    }

    fun beginNewProfile() {
        val repo = repository ?: return
        val id = IDs.uuid()
        viewModelScope.launch {
            repo.setActiveProfileId(id)
            _state.update {
                it.copy(
                    userId = id,
                    profile = null,
                    preferences = null,
                    plan = null,
                    sessions = emptyList(),
                    progress = emptyList(),
                    reminders = null,
                    activeWorkout = null,
                    workoutSummary = null,
                    onboardingOutcome = null,
                    planError = null,
                    workoutError = null,
                )
            }
            publishWidgets()
        }
    }

    fun deleteActiveProfile(onDone: (String?) -> Unit = {}) {
        val repo = repository ?: return onDone("The local database is not ready.")
        val removing = _state.value.userId
        viewModelScope.launch {
            runCatching {
                repo.deleteProfileData(removing)
                val remaining = repo.listProfiles()
                if (remaining.isNotEmpty()) {
                    repo.setActiveProfileId(remaining.first().id)
                    val nextId = remaining.first().id
                    val preferences = repo.getPreferences(nextId)
                    val plan = repo.getActivePlan(nextId)
                    val sessions = repo.getSessions(nextId)
                    val reminders = repo.getReminderSettings(nextId)
                    val progress = repo.listProgressRecords(nextId)
                    val workout = repo.loadActiveWorkout(nextId)
                    _state.update {
                        it.copy(
                            userId = nextId,
                            profile = remaining.first(),
                            preferences = preferences,
                            plan = plan,
                            sessions = sessions,
                            reminders = reminders,
                            progress = progress,
                            activeWorkout = workout,
                            workoutSummary = null,
                            onboardingOutcome = null,
                            localProfiles = remaining,
                        )
                    }
                    rescheduleReminders(reminders)
                } else {
                    withContext(Dispatchers.IO) { reminderScheduler.cancelAll() }
                    val nextId = IDs.uuid()
                    repo.setActiveProfileId(nextId)
                    _state.update {
                        it.copy(
                            userId = nextId,
                            profile = null,
                            preferences = null,
                            plan = null,
                            sessions = emptyList(),
                            progress = emptyList(),
                            reminders = null,
                            activeWorkout = null,
                            workoutSummary = null,
                            onboardingOutcome = null,
                            localProfiles = emptyList(),
                        )
                    }
                }
                publishWidgets()
            }.onSuccess { onDone(null) }
                .onFailure { onDone(it.message ?: "The profile could not be deleted.") }
        }
    }

    // MARK: - Local data

    fun resetLocalData() {
        val repo = repository ?: return
        val service = accountService
        viewModelScope.launch {
            repo.clearAllData()
            service?.tokenStore?.clear()
            service?.tokenStore?.savePendingVerification(null)
            _state.update {
                FormaUiState(
                    bootstrapping = false,
                    userId = IDs.uuid(),
                    exercises = _state.value.exercises,
                    themeMode = _state.value.themeMode,
                    accountConfigured = _state.value.accountConfigured,
                )
            }
            reminderScheduler.cancelAll()
            publishWidgets()
        }
    }

    fun planDayFor(date: java.time.LocalDate): WorkoutDay? {
        val plan = _state.value.plan ?: return null
        return plan.days.firstOrNull { it.weekday == date.dayOfWeek.value }
    }

    fun isoWeekdayToday(): Int = FormaDate.isoWeekday(java.time.LocalDate.now())

    data class OnboardingInput(
        val name: String,
        val age: Int,
        val experience: Experience,
        val environment: TrainingEnvironment,
        val goals: List<Goal>,
        val days: Set<Int>,
        val minutes: Int,
        val equipment: Set<Equipment>,
        val avoid: List<String>,
        val limitations: String,
        val reminderTime: String,
        val remindersOn: Boolean,
    )

    private companion object {
        const val KEY_THEME = "themeMode"
        const val KEY_FAVORITES = "forma.favoriteExercises"
        const val KEY_RECENT = "forma.recentExercises"
    }
}
