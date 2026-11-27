package com.gymapp.android.ui.screens

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.gymapp.android.core.Formatters
import com.gymapp.android.domain.Equipment
import com.gymapp.android.domain.Experience
import com.gymapp.android.domain.Goal
import com.gymapp.android.domain.PlanGenerator
import com.gymapp.android.domain.TrainingEnvironment
import com.gymapp.android.domain.Weekday
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.store.OnboardingOutcome
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.FormaBackground
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaChip
import com.gymapp.android.ui.components.FormaDivider
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.FormaTextEditor
import com.gymapp.android.ui.components.FormaTextField
import com.gymapp.android.ui.components.FormaToggle
import com.gymapp.android.ui.components.IconButton
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PageHeading
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.StepperControl
import com.gymapp.android.ui.components.Wordmark
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.sheets.AvoidExerciseSheetContent
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont

private val durations = listOf(20, 30, 45, 60, 75)
private val reminderTimes = listOf("07:00", "08:00", "12:00", "17:30", "18:00", "19:00", "20:00")

@Composable
fun OnboardingFlow(model: FormaViewModel, state: FormaUiState) {
    val outcome = state.onboardingOutcome
    if (outcome != null) {
        PlanReadyScreen(state = state, outcome = outcome, onEnter = model::dismissPlanReady)
        return
    }

    val colors = FormaTheme.colors
    val context = LocalContext.current
    val totalSteps = 7

    var step by remember { mutableStateOf(0) }
    var name by remember { mutableStateOf("") }
    var age by remember { mutableStateOf(28) }
    var experience by remember { mutableStateOf(Experience.BEGINNER) }
    var environment by remember { mutableStateOf(TrainingEnvironment.BOTH) }
    var goals by remember { mutableStateOf(listOf(Goal.GENERAL)) }
    var days by remember { mutableStateOf(setOf(1, 3, 5)) }
    var minutes by remember { mutableStateOf(45) }
    var equipment by remember {
        mutableStateOf(setOf(Equipment.BODYWEIGHT, Equipment.DUMBBELLS, Equipment.BENCH))
    }
    var avoid by remember { mutableStateOf(emptyList<String>()) }
    var limitations by remember { mutableStateOf("") }
    var reminderTime by remember { mutableStateOf("18:00") }
    var remindersOn by remember { mutableStateOf(true) }
    var showAvoid by remember { mutableStateOf(false) }
    var didHydrate by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var awaitPermission by remember { mutableStateOf(false) }
    var permissionResult by remember { mutableStateOf<Boolean?>(null) }
    var submitted by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        if (didHydrate) return@LaunchedEffect
        didHydrate = true
        state.profile?.let { existing ->
            if (existing.name.isNotEmpty()) name = existing.name
            existing.age?.let { age = it }
            experience = existing.experience
            environment = existing.environment
            if (existing.goals.isNotEmpty()) goals = existing.goals
            existing.limitations?.let { limitations = it }
        }
        state.preferences?.let { preferences ->
            if (preferences.workoutDays.isNotEmpty()) days = preferences.workoutDays.toSet()
            minutes = preferences.sessionMinutes
            equipment = preferences.equipment.toSet() + Equipment.BODYWEIGHT
            avoid = preferences.avoidExercises
            reminderTime = preferences.reminderTime
        }
    }

    LaunchedEffect(state.loadError) {
        if (state.loadError != null && submitted) {
            error = state.loadError
            submitted = false
            awaitPermission = false
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> permissionResult = granted }

    fun toggleGoal(goal: Goal) {
        goals = if (goals.contains(goal)) {
            if (goals.size <= 1) goals else goals - goal
        } else if (goals.size < 3) {
            goals + goal
        } else {
            goals
        }
    }

    fun toggleDay(day: Int) {
        days = when {
            days.contains(day) -> if (days.size <= 1) days else days - day
            days.size >= 6 -> days
            else -> days + day
        }
    }

    fun toggleEquipment(item: Equipment) {
        if (item == Equipment.BODYWEIGHT) return
        equipment = if (equipment.contains(item)) equipment - item else equipment + item
    }

    val nameProblem = name.trim().length < 2
    val canContinue = when (step) {
        0 -> !nameProblem
        2 -> goals.isNotEmpty()
        3 -> days.isNotEmpty()
        4 -> equipment.contains(Equipment.BODYWEIGHT) || equipment.isNotEmpty()
        else -> true
    }
    val helper = when {
        canContinue -> null
        step == 0 -> "Add your name to continue."
        step == 2 -> "Choose at least one goal."
        step == 3 -> "Choose at least one training day."
        step == 4 -> "Choose at least one equipment option."
        else -> null
    }

    fun submit() {
        if (submitted) return
        submitted = true
        error = null
        val input = FormaViewModel.OnboardingInput(
            name = name.trim(),
            age = age,
            experience = experience,
            environment = environment,
            goals = Goal.entries.filter { goals.contains(it) },
            days = days,
            minutes = minutes,
            equipment = Equipment.entries.filter { it == Equipment.BODYWEIGHT || equipment.contains(it) }.toSet(),
            avoid = avoid,
            limitations = limitations,
            reminderTime = reminderTime,
            remindersOn = remindersOn,
        )
        model.completeOnboarding(input)
    }

    LaunchedEffect(permissionResult) {
        if (permissionResult != null) {
            permissionResult = null
            awaitPermission = false
            submit()
        }
    }

    fun advance() {
        if (!canContinue || state.isCompletingOnboarding) return
        if (step == totalSteps - 1) {
            val needsPermission = remindersOn &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            if (needsPermission) {
                awaitPermission = true
                permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                submit()
            }
        } else {
            error = null
            step += 1
        }
    }

    Column(Modifier.fillMaxSize()) {
        OnboardingHeader(step = step, totalSteps = totalSteps, onBack = { if (step > 0) step -= 1 })

        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.xl, vertical = Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(Spacing.xl),
        ) {
            when (step) {
                0 -> AboutStep(name = name, onName = { name = it }, age = age, onAge = { age = it })
                1 -> ExperienceStep(selected = experience, onSelect = { experience = it })
                2 -> DirectionStep(
                    goals = goals,
                    onToggleGoal = ::toggleGoal,
                    environment = environment,
                    onSelectEnvironment = { environment = it },
                )
                3 -> ScheduleStep(
                    days = days,
                    onToggleDay = ::toggleDay,
                    minutes = minutes,
                    onMinutes = { minutes = it },
                )
                4 -> EquipmentStep(
                    equipment = equipment,
                    onToggle = ::toggleEquipment,
                )
                5 -> PreferencesStep(
                    limitations = limitations,
                    onLimitations = { limitations = it },
                    avoidCount = avoid.size,
                    onOpenAvoid = { showAvoid = true },
                    reminderTime = reminderTime,
                    onReminderTime = { reminderTime = it },
                    remindersOn = remindersOn,
                    onRemindersOn = { remindersOn = it },
                )
                else -> ReviewStep(
                    name = name,
                    age = age,
                    experience = experience,
                    environment = environment,
                    days = days,
                    minutes = minutes,
                    equipment = equipment,
                    remindersOn = remindersOn,
                    reminderTime = reminderTime,
                    avoidCount = avoid.size,
                )
            }
            Spacer(Modifier.height(Spacing.sm))
        }

        Column(
            Modifier
                .fillMaxWidth()
                .background(colors.background)
                .navigationBarsPadding()
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.md, bottom = Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
            if (helper != null) {
                Text(
                    helper,
                    style = bodyFont(11f),
                    color = colors.textTertiary,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (error != null) {
                ErrorBanner(message = error!!)
            }
            PrimaryButton(
                title = if (step == totalSteps - 1) "Build my plan" else "Continue",
                icon = if (step == totalSteps - 1) "sparkles" else "arrow.right",
                isLoading = state.isCompletingOnboarding || awaitPermission,
                isDisabled = !canContinue || state.isCompletingOnboarding,
                onClick = ::advance,
            )
        }
    }

    if (showAvoid) {
        FormaBottomSheet(onDismiss = { showAvoid = false }) {
            AvoidExerciseSheetContent(
                exercises = state.exercises,
                selected = avoid,
                onToggle = { id ->
                    avoid = if (avoid.contains(id)) avoid - id else avoid + id
                },
                onClose = { showAvoid = false },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FormaBottomSheet(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = FormaTheme.colors.background,
        dragHandle = null,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.xl, bottom = Spacing.lg),
        ) {
            content()
        }
    }
}

@Composable
private fun OnboardingHeader(step: Int, totalSteps: Int, onBack: () -> Unit) {
    val colors = FormaTheme.colors
    val progress by animateFloatAsState((step + 1).toFloat() / totalSteps, label = "onboardingProgress")
    Column(
        Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = Spacing.xl)
            .padding(top = Spacing.sm, bottom = Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (step > 0) {
                IconButton(icon = "chevron.left", label = "Previous step", onClick = onBack)
            } else {
                Wordmark()
            }
            Spacer(Modifier.weight(1f))
            Text(
                "%02d / %02d".format(step + 1, totalSteps),
                style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
                color = colors.textSecondary,
            )
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(3.dp)
                .clip(CircleShape)
                .background(colors.surfaceRaised),
        ) {
            Box(
                Modifier
                    .fillMaxWidth(progress.coerceIn(0.02f, 1f))
                    .height(3.dp)
                    .clip(CircleShape)
                    .background(colors.accent),
            )
        }
    }
}

// MARK: - Steps

@Composable
private fun AboutStep(name: String, onName: (String) -> Unit, age: Int, onAge: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        StepIntro(
            eyebrow = "About you",
            title = "Let's make this yours.",
            subtitle = "A few honest answers now saves guesswork later. Nothing here is shared publicly.",
        )
        FormaTextField(
            value = name,
            onValueChange = onName,
            placeholder = "What should we call you?",
            label = "Name",
            capitalization = KeyboardCapitalization.Words,
        )
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text("Age", style = bodyFont(12f, FontWeight.Medium), color = FormaTheme.colors.textSecondary)
            StepperControl(value = age, range = 13..90, suffix = "years", onChange = onAge)
        }
        OnboardingNote(
            icon = "checkmark.shield",
            text = "Your age helps calibrate sensible training loads. It is not used for body-image scoring or anything public.",
        )
    }
}

@Composable
private fun ExperienceStep(selected: Experience, onSelect: (Experience) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        StepIntro(
            eyebrow = "Experience",
            title = "Where are you starting?",
            subtitle = "Be honest — the plan will meet you there and progress from it.",
        )
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Experience.entries.forEach { option ->
                OnboardingOption(
                    title = option.label,
                    detail = when (option) {
                        Experience.BEGINNER ->
                            "New, or returning after a long break. We keep volume conservative and technique first."
                        Experience.INTERMEDIATE ->
                            "Training consistently for six months or more. Comfortable with the main movement patterns."
                        Experience.ADVANCED ->
                            "Years of structured training. You know your body and can manage higher intensity."
                    },
                    icon = when (option) {
                        Experience.BEGINNER -> "figure.walk"
                        Experience.INTERMEDIATE -> "dumbbell"
                        Experience.ADVANCED -> "flame"
                    },
                    selected = selected == option,
                    onClick = { onSelect(option) },
                )
            }
        }
    }
}

@Composable
private fun DirectionStep(
    goals: List<Goal>,
    onToggleGoal: (Goal) -> Unit,
    environment: TrainingEnvironment,
    onSelectEnvironment: (TrainingEnvironment) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        StepIntro(
            eyebrow = "Direction",
            title = "What are you training for?",
            subtitle = "Pick up to three. You can change this whenever your focus shifts.",
        )
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Goal.entries.forEach { goal ->
                FormaChip(label = goal.label, selected = goals.contains(goal)) { onToggleGoal(goal) }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            Text(
                "WHERE WILL YOU TRAIN?",
                style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
                color = FormaTheme.colors.textSecondary,
            )
            TrainingEnvironment.entries.forEach { option ->
                OnboardingOption(
                    title = option.label,
                    detail = when (option) {
                        TrainingEnvironment.GYM -> "Full equipment access, including machines and cables."
                        TrainingEnvironment.HOME -> "A mix of bodyweight, dumbbells, bands, or a small setup."
                        TrainingEnvironment.BOTH -> "Sometimes at home, sometimes at the gym."
                    },
                    icon = when (option) {
                        TrainingEnvironment.GYM -> "building.2"
                        TrainingEnvironment.HOME -> "house"
                        TrainingEnvironment.BOTH -> "square.stack.3d.up"
                    },
                    selected = environment == option,
                    onClick = { onSelectEnvironment(option) },
                )
            }
        }
    }
}

@Composable
private fun ScheduleStep(
    days: Set<Int>,
    onToggleDay: (Int) -> Unit,
    minutes: Int,
    onMinutes: (Int) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        StepIntro(
            eyebrow = "Schedule",
            title = "Build the week around your life.",
            subtitle = "Choose the days you can realistically show up. Up to six training days; recovery stays in the plan.",
        )
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(
                "TRAINING DAYS",
                style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
                color = FormaTheme.colors.textSecondary,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                (1..7).forEach { day ->
                    DayButton(day = day, selected = days.contains(day), modifier = Modifier.weight(1f)) {
                        onToggleDay(day)
                    }
                }
            }
            Text(
                "${days.size} day${if (days.size == 1) "" else "s"} selected · at least one recovery day stays open.",
                style = bodyFont(11f),
                color = FormaTheme.colors.textTertiary,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(
                "SESSION LENGTH",
                style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
                color = FormaTheme.colors.textSecondary,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                durations.forEach { duration ->
                    FormaChip(label = "$duration min", selected = minutes == duration) { onMinutes(duration) }
                }
            }
        }
        OnboardingNote(
            icon = "calendar",
            text = "Consistency beats intensity. Two or three focused sessions per week is a strong foundation.",
        )
    }
}

@Composable
private fun EquipmentStep(equipment: Set<Equipment>, onToggle: (Equipment) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        StepIntro(
            eyebrow = "Equipment",
            title = "What do you have access to?",
            subtitle = "Your plan only uses movements you can actually do. Bodyweight is always included.",
        )
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Equipment.entries.forEach { item ->
                FormaChip(
                    label = item.label,
                    selected = item == Equipment.BODYWEIGHT || equipment.contains(item),
                    disabled = item == Equipment.BODYWEIGHT,
                ) { onToggle(item) }
            }
        }
        OnboardingNote(
            icon = "dumbbell",
            text = "Not sure? Choose fewer options. You can add equipment later and regenerate the plan.",
        )
    }
}

@Composable
private fun PreferencesStep(
    limitations: String,
    onLimitations: (String) -> Unit,
    avoidCount: Int,
    onOpenAvoid: () -> Unit,
    reminderTime: String,
    onReminderTime: (String) -> Unit,
    remindersOn: Boolean,
    onRemindersOn: (Boolean) -> Unit,
) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        StepIntro(
            eyebrow = "Preferences",
            title = "Anything to work around?",
            subtitle = "Optional. This helps the plan avoid movements you would rather skip.",
        )
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            FormaTextEditor(
                value = limitations,
                onValueChange = onLimitations,
                label = "Injuries or limitations (optional)",
                placeholder = "e.g. left knee feels sensitive on deep squats",
            )
            Text(
                "Forma does not diagnose or treat injuries. For persistent pain, see a qualified professional.",
                style = bodyFont(11f),
                color = colors.textTertiary,
            )
        }
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radius.lg))
                .background(colors.surface)
                .padding(Spacing.md)
                .formaClickable(onClick = onOpenAvoid),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Box(
                Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(colors.surfaceRaised),
                contentAlignment = Alignment.Center,
            ) {
                FormaIcon("exclamationmark.triangle", size = 15.dp, tint = colors.textSecondary)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Exercises to skip", style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
                Text(
                    if (avoidCount == 0) "None selected" else "$avoidCount selected",
                    style = bodyFont(11f),
                    color = colors.textTertiary,
                )
            }
            FormaIcon("chevron.right", size = 12.dp, tint = colors.textTertiary)
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(
                "PREFERRED REMINDER TIME",
                style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
                color = colors.textSecondary,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                reminderTimes.forEach { time ->
                    FormaChip(label = Formatters.timeOfDay(time), selected = reminderTime == time) {
                        onReminderTime(time)
                    }
                }
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radius.lg))
                .background(colors.surface)
                .padding(Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Box(
                Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(colors.accentSoft),
                contentAlignment = Alignment.Center,
            ) {
                FormaIcon("bell.badge", size = 15.dp, tint = colors.accentText)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Training reminders", style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
                Text(
                    "A local reminder on your training days. No spam, no guilt.",
                    style = bodyFont(11f),
                    color = colors.textTertiary,
                )
            }
            FormaToggle(checked = remindersOn, onCheckedChange = onRemindersOn)
        }
    }
}

@Composable
private fun ReviewStep(
    name: String,
    age: Int,
    experience: Experience,
    environment: TrainingEnvironment,
    days: Set<Int>,
    minutes: Int,
    equipment: Set<Equipment>,
    remindersOn: Boolean,
    reminderTime: String,
    avoidCount: Int,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        StepIntro(
            eyebrow = "Review",
            title = "Ready to build your base.",
            subtitle = "Your plan will be generated on-device from these answers. You can rebuild it any time.",
        )
        FormaCard {
            ReviewRow(
                icon = "sparkles",
                label = "Name",
                value = "${name.trim()}, $age",
            )
            FormaDivider()
            ReviewRow(icon = "figure.strengthtraining.traditional", label = "Experience", value = experience.label)
            FormaDivider()
            ReviewRow(icon = "mappin.and.ellipse", label = "Environment", value = environment.label)
            FormaDivider()
            ReviewRow(
                icon = "calendar",
                label = "Schedule",
                value = "${days.sorted().map(Weekday::short).joinToString(", ")} · $minutes min",
            )
            FormaDivider()
            ReviewRow(
                icon = "dumbbell",
                label = "Equipment",
                value = Equipment.entries.filter { equipment.contains(it) }.joinToString(", ") { it.label },
            )
            FormaDivider()
            ReviewRow(
                icon = "bell",
                label = "Reminder",
                value = if (remindersOn) {
                    "${Formatters.timeOfDay(reminderTime)} on training days"
                } else {
                    "Off"
                },
            )
            if (avoidCount > 0) {
                FormaDivider()
                ReviewRow(
                    icon = "exclamationmark.triangle",
                    label = "Skipping",
                    value = "$avoidCount exercise${if (avoidCount == 1) "" else "s"}",
                )
            }
        }
        NoticeBanner(
            message = "Forma provides general fitness guidance, not medical advice. Stop any activity that causes pain, dizziness, or unusual shortness of breath, and seek appropriate professional help.",
            icon = "heart.text.square",
            accent = true,
        )
    }
}

// MARK: - Plan ready

@Composable
fun PlanReadyScreen(state: FormaUiState, outcome: OnboardingOutcome, onEnter: () -> Unit) {
    val colors = FormaTheme.colors
    val plan = state.plan
    val nextDay = plan?.let {
        val today = PlanGenerator.planForDate(it, System.currentTimeMillis())
        if (today != null && !today.isRestDay) today else PlanGenerator.nextTrainingDay(it, System.currentTimeMillis())
    }

    Box(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.xxxl, bottom = Spacing.xxxl),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            Box(
                Modifier
                    .size(88.dp)
                    .clip(RoundedCornerShape(30.dp))
                    .background(colors.accentSoft),
                contentAlignment = Alignment.Center,
            ) {
                FormaIcon("checkmark", size = 34.dp, tint = colors.accentText)
            }
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                Overline("Plan ready")
                Text("Your base is built.", style = displayFont(32f, FontWeight.Bold), color = colors.text)
                Text(
                    "${outcome.planName} is saved. Each session has a warm-up, structured sets, rest targets, and a cool-down.",
                    style = bodyFont(14f),
                    color = colors.textSecondary,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radius.lg))
                    .background(colors.surface),
            ) {
                Row(Modifier.fillMaxWidth().padding(Spacing.lg)) {
                    ReadyStat(value = "${outcome.trainingDays}", label = "Days / week", modifier = Modifier.weight(1f))
                    Box(Modifier.width(1.dp).height(32.dp).background(colors.border))
                    ReadyStat(
                        value = "${plan?.sessionMinutes ?: 45}m",
                        label = "Per session",
                        modifier = Modifier.weight(1f),
                    )
                    Box(Modifier.width(1.dp).height(32.dp).background(colors.border))
                    ReadyStat(
                        value = plan?.goal?.shortLabel ?: "—",
                        label = "Focus",
                        modifier = Modifier.weight(1f),
                    )
                }
                if (nextDay != null) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
                    Column(Modifier.fillMaxWidth().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            "NEXT SESSION",
                            style = bodyFont(10f, FontWeight.SemiBold).copy(letterSpacing = 1.2.sp),
                            color = colors.textTertiary,
                        )
                        Text(nextDay.title, style = displayFont(19f, FontWeight.SemiBold), color = colors.text)
                        Text(
                            "${nextDay.exercises.size} exercises · ${nextDay.estimatedMinutes} min",
                            style = bodyFont(12f),
                            color = colors.textSecondary,
                        )
                    }
                }
            }
            NoticeBanner(message = outcome.reminderMessage, icon = "bell", accent = true)
            Text(
                "Generated on-device from your answers and stored in this device's database. Open Workouts to rebuild it whenever your schedule changes.",
                style = bodyFont(11f),
                color = colors.textTertiary,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            PrimaryButton(title = "Enter Forma", icon = "arrow.right", onClick = onEnter)
        }
    }
}

@Composable
private fun ReadyStat(value: String, label: String, modifier: Modifier = Modifier) {
    val colors = FormaTheme.colors
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, style = displayFont(24f, FontWeight.Bold), color = colors.text)
        Text(label, style = bodyFont(10.5f), color = colors.textTertiary)
    }
}

// MARK: - Pieces

@Composable
private fun DayButton(day: Int, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    Box(
        modifier
            .height(46.dp)
            .clip(RoundedCornerShape(Radius.md))
            .background(if (selected) colors.accent else colors.surface)
            .formaClickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            Weekday.short(day),
            style = bodyFont(11.5f, FontWeight.SemiBold),
            color = if (selected) colors.accentInk else colors.textSecondary,
        )
    }
}

@Composable
private fun ReviewRow(icon: String, label: String, value: String) {
    val colors = FormaTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Box(
            Modifier.size(34.dp).clip(RoundedCornerShape(11.dp)).background(colors.surfaceRaised),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon(icon, size = 14.dp, tint = colors.textSecondary)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(label, style = bodyFont(11f), color = colors.textTertiary)
            Text(if (value.isEmpty()) "—" else value, style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
        }
    }
}

@Composable
private fun StepIntro(eyebrow: String, title: String, subtitle: String) {
    val colors = FormaTheme.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Overline(eyebrow)
        Text(title, style = displayFont(30f, FontWeight.Bold), color = colors.text)
        Text(subtitle, style = bodyFont(14f), color = colors.textSecondary)
    }
}

@Composable
private fun OnboardingOption(
    title: String,
    detail: String,
    icon: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(if (selected) colors.accentSoft else colors.surface)
            .formaClickable(onClick = onClick)
            .padding(Spacing.md),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Box(
            Modifier.size(38.dp).clip(RoundedCornerShape(12.dp))
                .background(if (selected) colors.accent else colors.surfaceRaised),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon(icon, size = 16.dp, tint = if (selected) colors.accentInk else colors.accentText)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = bodyFont(15f, FontWeight.SemiBold), color = colors.text)
            Text(detail, style = bodyFont(12f), color = colors.textSecondary)
        }
        FormaIcon(
            if (selected) "checkmark.circle.fill" else "circle",
            size = 17.dp,
            tint = if (selected) colors.accentText else colors.textTertiary,
        )
    }
}

@Composable
private fun OnboardingNote(icon: String, text: String) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surfaceRaised)
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        FormaIcon(icon, size = 14.dp, tint = colors.accentText)
        Text(text, style = bodyFont(12f), color = colors.textSecondary, modifier = Modifier.weight(1f))
    }
}
