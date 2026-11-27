package com.gymapp.android.ui

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.gymapp.android.core.AppDeepLink
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.BrandMark
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.FormaBackground
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.Wordmark
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.screens.AccountScreen
import com.gymapp.android.ui.screens.ActiveWorkoutScreen
import com.gymapp.android.ui.screens.ExerciseDetailScreen
import com.gymapp.android.ui.screens.HomeScreen
import com.gymapp.android.ui.screens.LibraryScreen
import com.gymapp.android.ui.screens.OnboardingFlow
import com.gymapp.android.ui.screens.PlanBuilderScreen
import com.gymapp.android.ui.screens.PlanDayScreen
import com.gymapp.android.ui.screens.PreferencesScreen
import com.gymapp.android.ui.screens.ProfileScreen
import com.gymapp.android.ui.screens.ProgressScreen
import com.gymapp.android.ui.screens.RecoveryScreen
import com.gymapp.android.ui.screens.RemindersScreen
import com.gymapp.android.ui.screens.SessionDetailScreen
import com.gymapp.android.ui.screens.WorkoutSummaryScreen
import com.gymapp.android.ui.screens.WorkoutsScreen
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont

object Routes {
    const val HOME = "home"
    const val WORKOUTS = "workouts"
    const val PROGRESS = "progress"
    const val PROFILE = "profile"
    const val LIBRARY = "library"
    const val EXERCISE = "exercise/{exerciseId}"
    const val RECOVERY = "recovery"
    const val PLAN_DAY = "plan-day/{dayId}"
    const val PLAN_BUILDER = "plan-builder"
    const val PREFERENCES = "preferences"
    const val REMINDERS = "reminders"
    const val ACCOUNT = "account"
    const val SESSION = "session/{sessionId}"

    fun exercise(id: String) = "exercise/$id"
    fun planDay(id: String) = "plan-day/$id"
    fun session(id: String) = "session/$id"
}

@Composable
fun FormaApp(
    model: FormaViewModel,
    deepLink: AppDeepLink?,
    onConsumeDeepLink: () -> Unit,
    resetToken: String?,
    onConsumeResetToken: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val dark = when (state.themeMode) {
        com.gymapp.android.domain.ThemeMode.DARK -> true
        com.gymapp.android.domain.ThemeMode.LIGHT -> false
        com.gymapp.android.domain.ThemeMode.SYSTEM -> isSystemInDarkTheme()
    }

    FormaTheme(darkTheme = dark) {
        val view = LocalView.current
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            val controller = androidx.core.view.WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = !dark
            controller.isAppearanceLightNavigationBars = !dark
        }
        val navController = rememberNavController()
        var startRequest by remember { mutableIntStateOf(0) }

        // Wait until the main graph exists, otherwise the navigation call would
        // run before the NavHost is composed (bootstrapping or onboarding).
        val shellReady = !state.bootstrapping && !state.needsOnboarding && state.profile != null

        LaunchedEffect(deepLink, shellReady) {
            val link = deepLink ?: return@LaunchedEffect
            if (!shellReady) return@LaunchedEffect
            when (link) {
                AppDeepLink.TODAY -> navController.openTab(Routes.HOME)
                AppDeepLink.START_WORKOUT -> {
                    navController.openTab(Routes.HOME)
                    startRequest += 1
                }
                AppDeepLink.WORKOUTS -> navController.openTab(Routes.WORKOUTS)
                AppDeepLink.PROGRESS -> navController.openTab(Routes.PROGRESS)
                else -> Unit
            }
            onConsumeDeepLink()
        }

        LaunchedEffect(resetToken, shellReady) {
            val token = resetToken ?: return@LaunchedEffect
            if (!shellReady) return@LaunchedEffect
            model.setPendingResetToken(token)
            navController.navigate(Routes.ACCOUNT) { launchSingleTop = true }
            onConsumeResetToken()
        }

        // iOS disables interactive dismissal while a workout runs; do the same
        // for the system back gesture so the session cannot be lost by accident.
        BackHandler(enabled = state.activeWorkout != null) { }
        BackHandler(enabled = state.activeWorkout == null && state.workoutSummary != null) {
            model.dismissSummary()
        }

        Box(Modifier.fillMaxSize()) {
            FormaBackground()
            when {
                state.bootstrapping -> LaunchScreen()
                state.profile == null && state.loadError != null ->
                    LoadFailureScreen(state.loadError!!, onRetry = model::bootstrap)
                state.needsOnboarding || state.onboardingOutcome != null || state.isCompletingOnboarding ->
                    OnboardingFlow(model = model, state = state)
                else -> MainShell(
                    model = model,
                    state = state,
                    navController = navController,
                    startRequest = startRequest,
                )
            }
            val active = state.activeWorkout
            if (active != null) {
                ActiveWorkoutScreen(
                    model = model,
                    state = state,
                )
            } else {
                val summary = state.workoutSummary
                if (summary != null) {
                    WorkoutSummaryScreen(
                        state = state,
                        onViewProgress = {
                            model.dismissSummary()
                            navController.openTab(Routes.PROGRESS)
                        },
                        onDone = model::dismissSummary,
                    )
                }
            }
        }
    }
}

private fun NavHostController.openTab(route: String) {
    navigate(route) {
        popUpTo(Routes.HOME) { inclusive = false }
        launchSingleTop = true
    }
}

@Composable
private fun MainShell(
    model: FormaViewModel,
    state: FormaUiState,
    navController: NavHostController,
    startRequest: Int,
) {
    val backStack by navController.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val showTabs = route in setOf(Routes.HOME, Routes.WORKOUTS, Routes.PROGRESS, Routes.PROFILE)

    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f)) {
            NavHost(navController = navController, startDestination = Routes.HOME) {
                composable(Routes.HOME) {
                    HomeScreen(
                        model = model,
                        state = state,
                        startRequest = startRequest,
                        onOpenWorkouts = { navController.openTab(Routes.WORKOUTS) },
                        onOpenProgress = { navController.openTab(Routes.PROGRESS) },
                        onOpenProfile = { navController.openTab(Routes.PROFILE) },
                        onOpenLibrary = { navController.navigate(Routes.LIBRARY) },
                        onOpenRecovery = { navController.navigate(Routes.RECOVERY) },
                        onOpenSession = { navController.navigate(Routes.session(it)) },
                    )
                }
                composable(Routes.WORKOUTS) {
                    WorkoutsScreen(
                        model = model,
                        state = state,
                        onOpenDay = { navController.navigate(Routes.planDay(it)) },
                        onOpenLibrary = { navController.navigate(Routes.LIBRARY) },
                        onOpenBuilder = { navController.navigate(Routes.PLAN_BUILDER) },
                    )
                }
                composable(Routes.PROGRESS) {
                    ProgressScreen(
                        model = model,
                        state = state,
                        onOpenSession = { navController.navigate(Routes.session(it)) },
                    )
                }
                composable(Routes.PROFILE) {
                    ProfileScreen(
                        model = model,
                        state = state,
                        onOpenAccount = { navController.navigate(Routes.ACCOUNT) },
                        onOpenPreferences = { navController.navigate(Routes.PREFERENCES) },
                        onOpenReminders = { navController.navigate(Routes.REMINDERS) },
                    )
                }
                composable(Routes.LIBRARY) {
                    LibraryScreen(
                        model = model,
                        state = state,
                        onOpenExercise = { navController.navigate(Routes.exercise(it)) },
                    )
                }
                composable(Routes.EXERCISE) { entry ->
                    val id = entry.arguments?.getString("exerciseId").orEmpty()
                    ExerciseDetailScreen(
                        model = model,
                        state = state,
                        exerciseId = id,
                        onBack = { navController.popBackStack() },
                        onOpenExercise = { navController.navigate(Routes.exercise(it)) },
                    )
                }
                composable(Routes.RECOVERY) {
                    RecoveryScreen(
                        state = state,
                        onBack = { navController.popBackStack() },
                        onOpenExercise = { navController.navigate(Routes.exercise(it)) },
                    )
                }
                composable(Routes.PLAN_DAY) { entry ->
                    val id = entry.arguments?.getString("dayId").orEmpty()
                    PlanDayScreen(
                        model = model,
                        state = state,
                        dayId = id,
                        onBack = { navController.popBackStack() },
                    )
                }
                composable(Routes.PLAN_BUILDER) {
                    PlanBuilderScreen(
                        model = model,
                        state = state,
                        onBack = { navController.popBackStack() },
                    )
                }
                composable(Routes.PREFERENCES) {
                    PreferencesScreen(
                        model = model,
                        state = state,
                        onBack = { navController.popBackStack() },
                        onOpenBuilder = { navController.navigate(Routes.PLAN_BUILDER) },
                    )
                }
                composable(Routes.REMINDERS) {
                    RemindersScreen(
                        model = model,
                        state = state,
                        onBack = { navController.popBackStack() },
                    )
                }
                composable(Routes.ACCOUNT) {
                    AccountScreen(
                        model = model,
                        state = state,
                        onBack = { navController.popBackStack() },
                    )
                }
                composable(Routes.SESSION) { entry ->
                    val id = entry.arguments?.getString("sessionId").orEmpty()
                    SessionDetailScreen(
                        state = state,
                        sessionId = id,
                        onBack = { navController.popBackStack() },
                    )
                }
            }
        }
        if (showTabs) {
            FormaTabBar(
                selected = route ?: Routes.HOME,
                onSelect = { navController.openTab(it) },
            )
        }
    }
}

@Composable
private fun FormaTabBar(selected: String, onSelect: (String) -> Unit) {
    val colors = FormaTheme.colors
    val items = listOf(
        Triple(Routes.HOME, "house", "Home"),
        Triple(Routes.WORKOUTS, "dumbbell", "Workouts"),
        Triple(Routes.PROGRESS, "chart.line.uptrend.xyaxis", "Progress"),
        Triple(Routes.PROFILE, "person.crop.circle", "Profile"),
    )
    Column {
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
        Row(
            Modifier
                .fillMaxWidth()
                .background(colors.background)
                .navigationBarsPadding()
                .padding(vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEach { (route, icon, label) ->
                val active = selected == route
                Column(
                    Modifier
                        .width(84.dp)
                        .formaClickable { if (!active) onSelect(route) }
                        .padding(vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    FormaIcon(
                        icon,
                        size = 19.dp,
                        tint = if (active) colors.accentText else colors.textTertiary,
                    )
                    Text(
                        label,
                        style = bodyFont(10f, if (active) FontWeight.SemiBold else FontWeight.Medium),
                        color = if (active) colors.accentText else colors.textTertiary,
                    )
                }
            }
        }
    }
}

// MARK: - Launch & failure

@Composable
private fun LaunchScreen() {
    val colors = FormaTheme.colors
    val transition = rememberInfiniteTransition(label = "launch")
    val pulse by transition.animateFloat(
        initialValue = 0.97f,
        targetValue = 1.03f,
        animationSpec = infiniteRepeatable(tween(1400), RepeatMode.Reverse),
        label = "launchPulse",
    )
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
            Box(Modifier.scale(pulse)) {
                BrandMark(size = 58.dp, color = colors.accentText)
            }
            Text(
                "FORMA",
                style = displayFont(17f, FontWeight.Bold).copy(letterSpacing = 5.sp),
                color = colors.text,
            )
        }
    }
}

@Composable
private fun LoadFailureScreen(message: String, onRetry: () -> Unit) {
    val colors = FormaTheme.colors
    Box(Modifier.fillMaxSize().statusBarsPadding(), contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(Spacing.xxl).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            Wordmark()
            FormaIcon("externaldrive.badge.exclamationmark", size = 30.dp, tint = colors.warning)
            Text("Your local data could not open", style = displayFont(21f, FontWeight.SemiBold), color = colors.text)
            Text(
                message,
                style = bodyFont(13f),
                color = colors.textSecondary,
                modifier = Modifier.padding(horizontal = Spacing.huge),
            )
            PrimaryButton(title = "Try again", icon = "arrow.clockwise", onClick = onRetry)
        }
    }
}
