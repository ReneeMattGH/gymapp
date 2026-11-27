package com.gymapp.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton as MaterialTextButton
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.domain.Equipment
import com.gymapp.android.domain.Exercise
import com.gymapp.android.domain.ExerciseCatalog
import com.gymapp.android.domain.Weekday
import com.gymapp.android.domain.WorkoutDay
import com.gymapp.android.domain.WorkoutExercise
import com.gymapp.android.domain.WorkoutPlan
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.CardStyle
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.ExerciseGlyph
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaDivider
import com.gymapp.android.ui.components.FormaEmptyState
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.FormaTextField
import com.gymapp.android.ui.components.LoadingCard
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PageHeading
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.SecondaryButton
import com.gymapp.android.ui.components.SectionHeader
import com.gymapp.android.ui.components.SheetHeading
import com.gymapp.android.ui.components.StepperControl
import com.gymapp.android.ui.components.SubScreenHeader
import com.gymapp.android.ui.components.TagLabel
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont

@Composable
fun WorkoutsScreen(
    model: FormaViewModel,
    state: FormaUiState,
    onOpenDay: (String) -> Unit,
    onOpenLibrary: () -> Unit,
    onOpenBuilder: () -> Unit,
) {
    val colors = FormaTheme.colors
    var startError by remember { mutableStateOf<String?>(null) }

    val todayTrainingDay = state.todayDay?.takeIf { !it.isRestDay }
    val orderedDays = state.plan?.days?.sortedBy { it.dayIndex }.orEmpty()

    fun start(day: WorkoutDay) {
        startError = null
        if (state.activeWorkout != null) return
        model.startWorkout(day) { startError = it }
    }

    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.xl)
            .padding(top = Spacing.md, bottom = Spacing.xxxl),
        verticalArrangement = Arrangement.spacedBy(Spacing.xl),
    ) {
        PageHeading(
            eyebrow = "Training",
            title = "Your week",
            subtitle = state.plan?.name ?: "No active plan yet.",
        )
        startError?.let { ErrorBanner(message = it) }

        PlanCard(
            plan = state.plan,
            todayTrainingDay = todayTrainingDay,
            hasActiveWorkout = state.activeWorkout != null,
            onStart = ::start,
            onOpenBuilder = onOpenBuilder,
        )

        if (orderedDays.isNotEmpty()) {
            SectionHeader(title = "Week schedule")
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radius.lg))
                    .background(colors.surface)
                    .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
                    .padding(horizontal = Spacing.md, vertical = Spacing.xs),
            ) {
                orderedDays.forEachIndexed { index, day ->
                    if (day.isRestDay) {
                        ScheduleRow(day = day, isRest = true, onClick = null)
                    } else {
                        ScheduleRow(day = day, isRest = false, onClick = { onOpenDay(day.id) })
                    }
                    if (index != orderedDays.lastIndex) {
                        Box(Modifier.padding(start = 56.dp)) { FormaDivider() }
                    }
                }
            }

            val trainingDays = state.plan?.trainingDays.orEmpty()
            if (trainingDays.isNotEmpty()) {
                SectionHeader(title = "Sessions")
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    trainingDays.forEach { day ->
                        SessionCard(day = day, onClick = { onOpenDay(day.id) })
                    }
                }
            }
        }

        LibraryCard(count = state.exercises.size, onClick = onOpenLibrary)
    }
}

// MARK: - Plan card

@Composable
private fun PlanCard(
    plan: WorkoutPlan?,
    todayTrainingDay: WorkoutDay?,
    hasActiveWorkout: Boolean,
    onStart: (WorkoutDay) -> Unit,
    onOpenBuilder: () -> Unit,
) {
    val colors = FormaTheme.colors
    FormaCard(style = CardStyle.RAISED) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Overline(text = if (plan == null) "Plan" else "Active plan")
            Spacer(Modifier.weight(1f))
            if (plan != null) TagLabel(text = plan.source.label)
        }
        if (plan != null) {
            Text(
                plan.name,
                style = displayFont(24f, FontWeight.Bold),
                color = colors.text,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.lg)) {
                PlanStat(value = "${plan.daysPerWeek}", label = "days / week")
                PlanStat(value = "${plan.sessionMinutes}m", label = "per session")
                PlanStat(value = "${plan.totalExercises}", label = "exercises")
            }
            if (todayTrainingDay != null) {
                PrimaryButton(
                    title = if (hasActiveWorkout) "Resume workout" else "Start today's session",
                    icon = "play.fill",
                    onClick = { onStart(todayTrainingDay) },
                )
            }
            SecondaryButton(
                title = "Rebuild plan",
                icon = "arrow.triangle.2.circlepath",
                onClick = onOpenBuilder,
            )
        } else {
            Text(
                "Answer a few questions and Forma will build a schedule you can actually keep.",
                style = bodyFont(13f),
                color = colors.textSecondary,
            )
            PrimaryButton(
                title = "Build my plan",
                icon = "arrow.triangle.2.circlepath",
                onClick = onOpenBuilder,
            )
        }
    }
}

@Composable
private fun PlanStat(value: String, label: String) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(value, style = displayFont(18f, FontWeight.SemiBold), color = colors.text)
        Text(label, style = bodyFont(10f), color = colors.textTertiary)
    }
}

@Composable
private fun ScheduleRow(day: WorkoutDay, isRest: Boolean, onClick: (() -> Unit)?) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.formaClickable(onClick = onClick) else Modifier)
            .padding(vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Box(
            Modifier
                .size(width = 40.dp, height = 36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(if (isRest) colors.surfaceRaised else colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                day.weekday?.let { Weekday.short(it) } ?: "—",
                style = bodyFont(11f, FontWeight.SemiBold),
                color = if (isRest) colors.textTertiary else colors.accentText,
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                if (isRest) "Recovery" else day.title,
                style = bodyFont(14f, FontWeight.SemiBold),
                color = if (isRest) colors.textSecondary else colors.text,
            )
            Text(
                if (isRest) day.restNote ?: "Rest and recover."
                else "${day.exercises.size} exercises · ${day.estimatedMinutes} min",
                style = bodyFont(11f),
                color = colors.textTertiary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (!isRest) {
            FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
        }
    }
}

@Composable
private fun SessionCard(day: WorkoutDay, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
            .formaClickable(onClick = onClick)
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Box(
            Modifier
                .size(42.dp)
                .clip(RoundedCornerShape(13.dp))
                .background(colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon("figure.strengthtraining.traditional", size = 16.dp, tint = colors.accentText)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(day.title, style = bodyFont(15f, FontWeight.SemiBold), color = colors.text)
            Text(
                "${day.exercises.size} exercises · ${day.estimatedMinutes} min · ${day.exercises.sumOf { it.sets }} sets",
                style = bodyFont(11f),
                color = colors.textTertiary,
            )
        }
        FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
    }
}

@Composable
private fun LibraryCard(count: Int, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
            .formaClickable(onClick = onClick)
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Box(
            Modifier
                .size(42.dp)
                .clip(RoundedCornerShape(13.dp))
                .background(colors.surfaceRaised),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon("books.vertical", size = 16.dp, tint = colors.text)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Exercise library", style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
            Text(
                "$count verified movements with form cues",
                style = bodyFont(11f),
                color = colors.textTertiary,
            )
        }
        FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
    }
}

// MARK: - Plan builder

@Composable
fun PlanBuilderScreen(
    model: FormaViewModel,
    state: FormaUiState,
    onBack: () -> Unit,
) {
    val colors = FormaTheme.colors
    var draft by remember { mutableStateOf<WorkoutPlan?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }

    fun rebuild() {
        error = null
        notice = null
        isLoading = true
        model.buildPlanDraft { plan, message ->
            draft = plan
            error = message
            isLoading = false
        }
    }

    LaunchedEffect(Unit) { rebuild() }

    fun save() {
        val plan = draft ?: return
        error = null
        isSaving = true
        model.adoptEditedPlan(plan) { message ->
            isSaving = false
            if (message == null) {
                onBack()
            } else {
                error = message
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        SubScreenHeader(
            title = "Build a plan",
            subtitle = "Review the draft before saving. Nothing changes until you save.",
            onBack = onBack,
        )
        Column(
            Modifier
                .weight(1f)
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.xl)
                .padding(bottom = Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            error?.let { ErrorBanner(message = it) }
            notice?.let { NoticeBanner(message = it, icon = "checkmark.seal", accent = true) }
            if (isLoading) {
                LoadingCard(label = "Building a balanced week")
            } else if (draft != null) {
                DraftContent(draft = draft!!, exercises = state.exercises)
            } else {
                FormaCard {
                    Text(
                        "A new draft could not be built. Try again in a moment.",
                        style = bodyFont(13f),
                        color = colors.textSecondary,
                    )
                }
            }
            NoticeBanner(
                message = "The built-in template uses your goals, equipment, and schedule, and is validated against the exercise library before it can be saved.",
                icon = "shield.lefthalf.filled",
            )
        }
        Column(
            Modifier
                .fillMaxWidth()
                .background(colors.background)
                .navigationBarsPadding()
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.md, bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            SecondaryButton(
                title = "Use built-in template",
                icon = "arrow.triangle.2.circlepath",
                isDisabled = isSaving,
                onClick = ::rebuild,
            )
            PrimaryButton(
                title = "Save plan",
                icon = "checkmark",
                isLoading = isSaving,
                isDisabled = draft == null || isLoading,
                onClick = ::save,
            )
        }
    }
}

@Composable
private fun DraftContent(draft: WorkoutPlan, exercises: List<Exercise>) {
    val colors = FormaTheme.colors
    FormaCard(style = CardStyle.RAISED) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Overline(text = "Draft")
            Spacer(Modifier.weight(1f))
            TagLabel(text = draft.source.label)
        }
        Text(draft.name, style = displayFont(22f, FontWeight.Bold), color = colors.text)
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.lg)) {
            BuilderStat(value = "${draft.daysPerWeek}", label = "days")
            BuilderStat(value = "${draft.sessionMinutes}m", label = "session")
            BuilderStat(value = "${draft.totalExercises}", label = "exercises")
            BuilderStat(value = draft.goal.shortLabel, label = "focus")
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(title = "Training days")
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radius.lg))
                .background(colors.surface)
                .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
                .padding(Spacing.md),
        ) {
            draft.trainingDays.forEach { day ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                ) {
                    Box(
                        Modifier
                            .size(width = 40.dp, height = 32.dp)
                            .clip(RoundedCornerShape(9.dp))
                            .background(colors.accentSoft),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            day.weekday?.let { Weekday.short(it) } ?: "—",
                            style = bodyFont(11f, FontWeight.SemiBold),
                            color = colors.accentText,
                        )
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(day.title, style = bodyFont(13.5f, FontWeight.SemiBold), color = colors.text)
                        Text(
                            day.exercises.joinToString(", ") { exerciseName(it.exerciseId, exercises) },
                            style = bodyFont(11f),
                            color = colors.textTertiary,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
    Text(
        "You can fine-tune sets, reps, rest, and exercise choices after saving from any training day.",
        style = bodyFont(11f),
        color = colors.textTertiary,
    )
}

@Composable
private fun BuilderStat(value: String, label: String) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(value, style = displayFont(17f, FontWeight.SemiBold), color = colors.text)
        Text(label, style = bodyFont(10f), color = colors.textTertiary)
    }
}

// MARK: - Day detail

private sealed interface DaySheet {
    data class Edit(val exercise: WorkoutExercise) : DaySheet
    data class Replace(val exercise: WorkoutExercise) : DaySheet
}

@Composable
fun PlanDayScreen(
    model: FormaViewModel,
    state: FormaUiState,
    dayId: String,
    onBack: () -> Unit,
) {
    val colors = FormaTheme.colors
    val haptics = LocalHapticFeedback.current
    val initialDay = state.plan?.days?.firstOrNull { it.id == dayId }
    var day by remember(dayId) { mutableStateOf(initialDay) }
    var error by remember { mutableStateOf<String?>(null) }
    var sheet by remember { mutableStateOf<DaySheet?>(null) }
    var removing by remember { mutableStateOf<WorkoutExercise?>(null) }
    var isSaving by remember { mutableStateOf(false) }

    if (day == null) {
        Column(Modifier.fillMaxSize()) {
            SubScreenHeader(onBack = onBack)
            FormaEmptyState(
                icon = "calendar",
                title = "This day is gone",
                message = "The plan changed. Go back and pick another training day.",
                modifier = Modifier.padding(top = Spacing.xxxl),
            )
        }
        return
    }

    val currentDay = day!!

    fun start() {
        error = null
        if (model.state.value.activeWorkout != null) return
        model.startWorkout(currentDay) { error = it }
    }

    fun currentExercises(): List<WorkoutExercise> =
        model.state.value.plan?.days?.firstOrNull { it.dayIndex == currentDay.dayIndex }
            ?.exercises?.sortedBy { it.position }
            ?: currentDay.exercises

    fun persist(exercises: List<WorkoutExercise>) {
        val plan = model.state.value.plan
        if (plan == null) {
            error = "The plan could not be found. Refresh and try again."
            return
        }
        val index = plan.days.indexOfFirst { it.dayIndex == currentDay.dayIndex }
        if (index < 0) {
            error = "The plan could not be found. Refresh and try again."
            return
        }
        val dayIdentity = plan.days[index].id
        val updatedDay = plan.days[index].copy(
            exercises = exercises.mapIndexed { position, item ->
                item.copy(position = position, dayId = dayIdentity)
            },
        )
        val updatedPlan = plan.copy(
            days = plan.days.toMutableList().also { it[index] = updatedDay },
        )
        isSaving = true
        model.adoptEditedPlan(updatedPlan) { message ->
            isSaving = false
            if (message != null) {
                error = message
            } else {
                model.state.value.plan?.days?.firstOrNull { it.dayIndex == currentDay.dayIndex }
                    ?.let { day = it }
            }
        }
    }

    fun applyReplacement(exercise: WorkoutExercise, newId: String) {
        val exercises = currentExercises().toMutableList()
        val index = exercises.indexOfFirst { it.id == exercise.id }
        if (index < 0) return
        exercises[index] = exercises[index].copy(exerciseId = newId)
        persist(exercises)
    }

    fun applyRemoval(exercise: WorkoutExercise) {
        removing = null
        if (currentDay.exercises.size <= 1) {
            error = "A session needs at least one exercise. Rebuild the plan instead."
            return
        }
        persist(currentDay.exercises.filter { it.id != exercise.id })
    }

    Column(Modifier.fillMaxSize()) {
        SubScreenHeader(onBack = onBack)
        Column(
            Modifier
                .weight(1f)
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.sm, bottom = Spacing.xxxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.xl),
        ) {
            PageHeading(
                eyebrow = "Session",
                title = currentDay.title,
                subtitle = "${currentDay.exercises.size} exercises · about ${currentDay.estimatedMinutes} minutes",
            )
            error?.let { ErrorBanner(message = it) }
            PrimaryButton(
                title = if (state.activeWorkout != null) "Workout in progress" else "Start workout",
                icon = "play.fill",
                isDisabled = state.activeWorkout != null || isSaving,
                onClick = ::start,
            )
            if (currentDay.warmup.isNotEmpty()) {
                BulletCard(title = "Warm-up", icon = "flame", items = currentDay.warmup)
            }
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(title = "Exercises")
                if (currentDay.exercises.isEmpty()) {
                    FormaEmptyState(
                        icon = "dumbbell",
                        title = "No exercises",
                        message = "Replace or rebuild the plan to add movements to this day.",
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        currentDay.exercises.sortedBy { it.position }.forEach { item ->
                            ExerciseRow(
                                item = item,
                                name = exerciseName(item.exerciseId, state.exercises),
                                onOpen = { model.recordExerciseView(item.exerciseId) },
                                onEdit = { sheet = DaySheet.Edit(item) },
                                onReplace = { sheet = DaySheet.Replace(item) },
                                onRemove = { removing = item },
                            )
                        }
                    }
                }
            }
            if (currentDay.cooldown.isNotEmpty()) {
                BulletCard(title = "Cool-down", icon = "wind", items = currentDay.cooldown)
            }
            NoticeBanner(
                message = "Stop any movement that causes sharp pain, dizziness, or unusual shortness of breath. Forma does not diagnose injuries.",
                icon = "heart.text.square",
            )
        }
    }

    when (val active = sheet) {
        is DaySheet.Edit -> WorkoutSheet(onDismiss = { sheet = null }) {
            EditTargetsSheetContent(
                exercise = active.exercise,
                onApply = { updated ->
                    sheet = null
                    val exercises = currentExercises().toMutableList()
                    val index = exercises.indexOfFirst { it.id == updated.id }
                    if (index >= 0) {
                        exercises[index] = updated
                        persist(exercises)
                    }
                },
                onClose = { sheet = null },
            )
        }
        is DaySheet.Replace -> WorkoutSheet(onDismiss = { sheet = null }) {
            ReplaceExerciseSheetContent(
                current = active.exercise,
                exercises = state.exercises,
                onSelect = { newId ->
                    sheet = null
                    applyReplacement(active.exercise, newId)
                },
                onClose = { sheet = null },
            )
        }
        null -> Unit
    }

    removing?.let { target ->
        AlertDialog(
            onDismissRequest = { removing = null },
            containerColor = colors.surfaceRaised,
            titleContentColor = colors.text,
            textContentColor = colors.textSecondary,
            title = { Text("Remove this exercise?", style = displayFont(19f, FontWeight.SemiBold)) },
            text = {
                Text(
                    "The sets you log for this movement will no longer appear in the session.",
                    style = bodyFont(13f),
                )
            },
            confirmButton = {
                MaterialTextButton(
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        applyRemoval(target)
                    },
                ) {
                    Text("Remove exercise", color = colors.danger, style = bodyFont(14f, FontWeight.Medium))
                }
            },
            dismissButton = {
                MaterialTextButton(onClick = { removing = null }) {
                    Text("Cancel", color = colors.textSecondary, style = bodyFont(14f))
                }
            },
        )
    }
}

@Composable
private fun ExerciseRow(
    item: WorkoutExercise,
    name: String,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onReplace: () -> Unit,
    onRemove: () -> Unit,
) {
    val colors = FormaTheme.colors
    var menuOpen by remember { mutableStateOf(false) }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
            .padding(Spacing.md),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Row(
            Modifier
                .weight(1f)
                .formaClickable(onClick = onOpen),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Box(
                Modifier
                    .size(24.dp)
                    .clip(CircleShape)
                    .background(colors.surfaceRaised),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "${item.position + 1}",
                    style = displayFont(13f, FontWeight.SemiBold),
                    color = colors.textTertiary,
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(name, style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
                Text(
                    "${item.sets} sets · ${item.repsMin}–${item.repsMax} reps · ${item.restSeconds}s rest",
                    style = bodyFont(11f),
                    color = colors.textTertiary,
                )
                val notes = item.notes
                if (!notes.isNullOrEmpty()) {
                    Text(
                        notes,
                        style = bodyFont(11f),
                        color = colors.textSecondary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        Box {
            Box(
                Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(colors.surfaceRaised)
                    .formaClickable { menuOpen = true },
                contentAlignment = Alignment.Center,
            ) {
                FormaIcon("ellipsis", size = 14.dp, tint = colors.textSecondary)
            }
            DropdownMenu(
                expanded = menuOpen,
                onDismissRequest = { menuOpen = false },
                containerColor = colors.surfaceRaised,
            ) {
                DropdownMenuItem(
                    text = { Text("Edit targets", style = bodyFont(13f), color = colors.text) },
                    leadingIcon = { FormaIcon("slider.horizontal.3", size = 15.dp, tint = colors.textSecondary) },
                    onClick = {
                        menuOpen = false
                        onEdit()
                    },
                )
                DropdownMenuItem(
                    text = { Text("Replace exercise", style = bodyFont(13f), color = colors.text) },
                    leadingIcon = { FormaIcon("arrow.triangle.2.circlepath", size = 15.dp, tint = colors.textSecondary) },
                    onClick = {
                        menuOpen = false
                        onReplace()
                    },
                )
                DropdownMenuItem(
                    text = { Text("Remove", style = bodyFont(13f), color = colors.danger) },
                    leadingIcon = { FormaIcon("trash", size = 15.dp, tint = colors.danger) },
                    onClick = {
                        menuOpen = false
                        onRemove()
                    },
                )
            }
        }
    }
}

@Composable
private fun BulletCard(title: String, icon: String, items: List<String>) {
    val colors = FormaTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
            .padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            FormaIcon(icon, size = 13.dp, tint = colors.accentText)
            Text(
                title.uppercase(),
                style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
                color = colors.textSecondary,
            )
        }
        items.forEach { item ->
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Box(
                    Modifier
                        .padding(top = 6.dp)
                        .size(4.dp)
                        .clip(CircleShape)
                        .background(colors.accentText),
                )
                Text(item, style = bodyFont(12.5f), color = colors.textSecondary)
            }
        }
    }
}

// MARK: - Edit targets sheet

@Composable
private fun EditTargetsSheetContent(
    exercise: WorkoutExercise,
    onApply: (WorkoutExercise) -> Unit,
    onClose: () -> Unit,
) {
    val colors = FormaTheme.colors
    val haptics = LocalHapticFeedback.current
    var sets by remember(exercise.id) { mutableStateOf(exercise.sets) }
    var repsMin by remember(exercise.id) { mutableStateOf(exercise.repsMin) }
    var repsMax by remember(exercise.id) { mutableStateOf(exercise.repsMax) }
    var rest by remember(exercise.id) { mutableStateOf(exercise.restSeconds) }

    SheetHeading(
        title = "Edit targets",
        subtitle = "Adjust this movement in the plan. Changes apply when you tap Apply.",
        onClose = onClose,
    )
    Spacer(Modifier.height(Spacing.lg))
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Sets", style = bodyFont(12f, FontWeight.Medium), color = colors.textSecondary)
            Spacer(Modifier.weight(1f))
            StepperControl(value = sets, range = 1..8) { sets = it }
        }
        FormaDivider()
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text("Reps range", style = bodyFont(12f, FontWeight.Medium), color = colors.textSecondary)
            StepperControl(value = repsMin, range = 1..30, suffix = "min reps") { next ->
                repsMin = next
                repsMax = maxOf(repsMax, next)
            }
            StepperControl(value = repsMax, range = 1..40, suffix = "max reps") { next ->
                repsMax = next
                repsMin = minOf(repsMin, next)
            }
        }
        FormaDivider()
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text("Rest between sets", style = bodyFont(12f, FontWeight.Medium), color = colors.textSecondary)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.lg),
            ) {
                AdjustButton("minus") {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    rest = maxOf(0, rest - 15)
                }
                Text(
                    if (rest == 0) "No rest" else "$rest sec",
                    style = displayFont(20f, FontWeight.SemiBold),
                    color = colors.text,
                    modifier = Modifier.widthIn(min = 96.dp),
                )
                AdjustButton("plus") {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    rest = minOf(300, rest + 15)
                }
            }
        }
    }
    Spacer(Modifier.height(Spacing.lg))
    PrimaryButton(
        title = "Apply changes",
        icon = "checkmark",
        onClick = {
            val updated = exercise.copy(
                sets = sets,
                repsMin = minOf(repsMin, repsMax),
                repsMax = maxOf(repsMin, repsMax),
                restSeconds = rest,
            )
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            onApply(updated)
        },
    )
}

@Composable
private fun AdjustButton(icon: String, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    Box(
        Modifier
            .size(38.dp)
            .clip(CircleShape)
            .background(colors.surfaceRaised)
            .border(1.dp, colors.border, CircleShape)
            .formaClickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        FormaIcon(icon, size = 13.dp, tint = colors.text)
    }
}

// MARK: - Replace exercise sheet

@Composable
fun ReplaceExerciseSheetContent(
    current: WorkoutExercise,
    exercises: List<Exercise>,
    onSelect: (String) -> Unit,
    onClose: () -> Unit,
) {
    val colors = FormaTheme.colors
    var query by remember { mutableStateOf("") }

    val candidates = remember(query, exercises, current.exerciseId) {
        val original = exercises.firstOrNull { it.id == current.exerciseId }
        val alternates = original?.alternatives?.toSet().orEmpty()
        val muscles = original?.primaryMuscles?.toSet().orEmpty()
        val text = query.trim().lowercase()
        exercises
            .filter { it.id != current.exerciseId }
            .filter { exercise ->
                if (text.isEmpty()) return@filter true
                exercise.name.lowercase().contains(text) ||
                    exercise.primaryMuscles.any { muscle ->
                        muscle.searchTerms.any { it.lowercase().contains(text) }
                    }
            }
            .sortedWith(
                compareBy(
                    {
                        when {
                            alternates.contains(it.id) -> 0
                            it.primaryMuscles.any(muscles::contains) -> 1
                            else -> 2
                        }
                    },
                    { it.name },
                ),
            )
    }

    SheetHeading(
        title = "Replace exercise",
        subtitle = "Alternatives for ${ExerciseCatalog.name(current.exerciseId)} are listed first.",
        onClose = onClose,
    )
    Spacer(Modifier.height(Spacing.lg))
    FormaTextField(
        value = query,
        onValueChange = { query = it },
        placeholder = "Search exercises",
        capitalization = KeyboardCapitalization.None,
    )
    Spacer(Modifier.height(Spacing.sm))
    LazyColumn(Modifier.heightIn(max = 440.dp)) {
        items(candidates, key = { it.id }) { exercise ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .formaClickable { onSelect(exercise.id) }
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.md),
            ) {
                ExerciseGlyph(exercise = exercise, size = 38.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(exercise.name, style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
                    Text(
                        exercise.primaryMuscles.joinToString(" · ") { it.label },
                        style = bodyFont(11f),
                        color = colors.textTertiary,
                    )
                }
                if (exercise.equipment.isNotEmpty() && exercise.equipment.all { it == Equipment.BODYWEIGHT }) {
                    TagLabel(text = "Bodyweight", color = colors.textTertiary)
                }
            }
            FormaDivider()
        }
        if (candidates.isEmpty()) {
            item {
                Text(
                    "No exercises match that search.",
                    style = bodyFont(12f),
                    color = colors.textTertiary,
                    modifier = Modifier.padding(vertical = Spacing.xxl),
                )
            }
        }
    }
    Spacer(Modifier.height(Spacing.sm))
}

// MARK: - Shared chrome

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WorkoutSheet(onDismiss: () -> Unit, content: @Composable () -> Unit) {
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

private fun exerciseName(id: String, exercises: List<Exercise>): String =
    exercises.firstOrNull { it.id == id }?.name ?: ExerciseCatalog.name(id)
