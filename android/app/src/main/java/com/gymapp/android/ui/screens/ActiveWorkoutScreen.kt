package com.gymapp.android.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.core.FormaDate
import com.gymapp.android.core.Formatters
import com.gymapp.android.domain.ActiveRest
import com.gymapp.android.domain.ActiveWorkout
import com.gymapp.android.domain.Exercise
import com.gymapp.android.domain.TrainingStats
import com.gymapp.android.domain.UnitSystem
import com.gymapp.android.domain.WorkoutExercise
import com.gymapp.android.domain.WorkoutRunStatus
import com.gymapp.android.domain.WorkoutSession
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.CardStyle
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.ExerciseGlyph
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.KeyValueRow
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.ProgressRing
import com.gymapp.android.ui.components.SecondaryButton
import com.gymapp.android.ui.components.SectionHeader
import com.gymapp.android.ui.components.SetDots
import com.gymapp.android.ui.components.StatTile
import com.gymapp.android.ui.components.TextButton
import com.gymapp.android.ui.components.Wordmark
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont
import kotlinx.coroutines.delay

@Composable
fun ActiveWorkoutScreen(
    model: FormaViewModel,
    state: FormaUiState,
) {
    val colors = FormaTheme.colors
    val workout = state.activeWorkout ?: return
    val units = state.units

    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var repsText by remember { mutableStateOf("") }
    var weightText by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    var showWarmup by remember { mutableStateOf(false) }
    var confirmFinish by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var confirmSkip by remember { mutableStateOf(false) }
    var lastExerciseId by remember { mutableStateOf<String?>(null) }

    fun lastWeight(exerciseId: String): Double? {
        state.completedSessions.forEach { session ->
            val set = session.sets.lastOrNull { it.exerciseId == exerciseId && it.weightKg != null }
            if (set != null) return set.weightKg
        }
        return null
    }

    fun syncInputs(exercise: WorkoutExercise) {
        if (lastExerciseId != exercise.id) {
            lastExerciseId = exercise.id
            repsText = "${exercise.repsMax}"
            val kg = lastWeight(exercise.exerciseId)
            weightText = when {
                kg == null -> ""
                units == UnitSystem.KG -> formatNumber(kg)
                else -> formatNumber(kg * 2.2046226218)
            }
        }
    }

    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            model.tickRest()
            delay(1000)
        }
    }

    LaunchedEffect(workout.currentExercise?.id) {
        workout.currentExercise?.let { syncInputs(it) }
    }

    fun logSet(exercise: WorkoutExercise) {
        if (workout.status != WorkoutRunStatus.ACTIVE) return
        val reps = repsText.trim().toIntOrNull() ?: exercise.repsMax
        if (reps <= 0) {
            error = "Enter the reps you completed."
            return
        }
        var weightKg: Double? = null
        val trimmed = weightText.trim().replace(",", ".")
        if (trimmed.isNotEmpty()) {
            val entered = trimmed.toDoubleOrNull()
            if (entered == null || entered < 0 || entered >= 1000) {
                error = "Enter a valid weight in ${units.abbreviation}, or leave it blank."
                return
            }
            weightKg = if (units == UnitSystem.KG) entered else entered / 2.2046226218
        }
        error = null
        model.completeSet(exercise, reps, weightKg)
        repsText = "${exercise.repsMax}"
    }

    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.sm, bottom = Spacing.md)
                .background(colors.background.copy(alpha = 0.96f)),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
                Wordmark(compact = true)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(
                        workout.title,
                        style = displayFont(16f, FontWeight.SemiBold),
                        color = colors.text,
                        maxLines = 1,
                    )
                    Text(
                        statusLabel(workout, now),
                        style = bodyFont(10f),
                        color = colors.textTertiary,
                    )
                }
                Text(
                    Formatters.clock(workout.elapsedSeconds(now)),
                    style = displayFont(22f, FontWeight.Bold),
                    color = if (workout.status == WorkoutRunStatus.PAUSED) colors.textTertiary else colors.text,
                )
                Box {
                    Box(
                        Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(colors.surface)
                            .border(1.dp, colors.border, CircleShape)
                            .formaClickable { menuOpen = true },
                        contentAlignment = Alignment.Center,
                    ) {
                        FormaIcon("ellipsis", size = 15.dp, tint = colors.text)
                    }
                    DropdownMenu(
                        expanded = menuOpen,
                        onDismissRequest = { menuOpen = false },
                        containerColor = colors.surfaceRaised,
                    ) {
                        DropdownMenuItem(
                            text = {
                                Text(
                                    if (workout.status == WorkoutRunStatus.PAUSED) "Resume workout" else "Pause workout",
                                    style = bodyFont(13f),
                                    color = colors.text,
                                )
                            },
                            leadingIcon = {
                                FormaIcon(
                                    if (workout.status == WorkoutRunStatus.PAUSED) "play.fill" else "pause.fill",
                                    size = 15.dp,
                                    tint = colors.textSecondary,
                                )
                            },
                            onClick = {
                                menuOpen = false
                                if (workout.status == WorkoutRunStatus.PAUSED) model.resumeWorkout() else model.pauseWorkout()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Finish & save", style = bodyFont(13f), color = colors.text) },
                            leadingIcon = { FormaIcon("checkmark.circle", size = 15.dp, tint = colors.textSecondary) },
                            enabled = workout.sets.isNotEmpty(),
                            onClick = {
                                menuOpen = false
                                confirmFinish = true
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Discard", style = bodyFont(13f), color = colors.danger) },
                            leadingIcon = { FormaIcon("trash", size = 15.dp, tint = colors.danger) },
                            onClick = {
                                menuOpen = false
                                confirmDiscard = true
                            },
                        )
                    }
                }
            }
            val completion by animateFloatAsState(
                targetValue = if (workout.totalPlannedSets == 0) 0f
                else (workout.sets.size.toFloat() / workout.totalPlannedSets).coerceIn(0f, 1f),
                label = "completion",
            )
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(3.dp)
                    .clip(CircleShape)
                    .background(colors.surfaceRaised),
            ) {
                Box(
                    Modifier
                        .fillMaxHeight()
                        .fillMaxWidth(completion.coerceAtLeast(0.01f))
                        .clip(CircleShape)
                        .background(colors.accent),
                )
            }
        }

        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.xl)
                .padding(bottom = Spacing.xxxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            error?.let { ErrorBanner(message = it) }
            state.workoutError?.let { ErrorBanner(message = it) }
            if (workout.status == WorkoutRunStatus.PAUSED) {
                NoticeBanner(
                    message = "Workout paused. The elapsed timer and rest timer are frozen.",
                    icon = "pause.circle",
                    accent = true,
                )
            }
            ProgressStrip(workout = workout, now = now)
            val exercise = workout.exercises.getOrNull(workout.currentExerciseIndex)
            if (exercise != null) {
                CurrentExerciseCard(
                    workout = workout,
                    exercise = exercise,
                    detail = state.exercises.firstOrNull { it.id == exercise.exerciseId },
                    name = exerciseName(exercise.exerciseId, state.exercises),
                    now = now,
                    units = units,
                    repsText = repsText,
                    weightText = weightText,
                    onRepsChange = { repsText = it.filter { ch -> ch.isDigit() } },
                    onWeightChange = { weightText = it.filter { ch -> ch.isDigit() || ch == '.' || ch == ',' } },
                    onLog = { logSet(exercise) },
                    onRemoveLast = {
                        model.removeLastSet(exercise)
                        repsText = "${exercise.repsMax}"
                    },
                    onPauseRest = { if (workout.rest?.isPaused == true) model.resumeRest() else model.pauseRest() },
                    onSkipRest = model::skipRest,
                    onReplace = { model.replaceExercise(exercise, it) },
                    onConfirmSkip = { confirmSkip = true },
                )
                NextCard(workout = workout, exercise = exercise, exercises = state.exercises)
            } else {
                CompletionCard(
                    workout = workout,
                    now = now,
                    onFinish = { confirmFinish = true },
                )
            }
            if (workout.warmup.isNotEmpty()) {
                WarmupCard(
                    steps = workout.warmup,
                    expanded = showWarmup,
                    onToggle = { showWarmup = !showWarmup },
                )
            }
            ExercisePicker(workout = workout, exercises = state.exercises, onSelect = model::selectExercise)
        }

        Column(
            Modifier
                .fillMaxWidth()
                .background(colors.background.copy(alpha = 0.97f))
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.md, bottom = Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            if (workout.status == WorkoutRunStatus.PAUSED) {
                PrimaryButton(title = "Resume workout", icon = "play.fill") { model.resumeWorkout() }
            } else {
                PrimaryButton(
                    title = if (state.isSavingWorkout) "Saving…" else "Finish workout",
                    icon = "flag.checkered",
                    isLoading = state.isSavingWorkout,
                    isDisabled = workout.sets.isEmpty(),
                    onClick = { confirmFinish = true },
                )
            }
            if (workout.sets.isEmpty()) {
                Text(
                    "Log at least one set to save the session.",
                    style = bodyFont(10.5f),
                    color = colors.textTertiary,
                )
            }
        }
    }

    if (confirmFinish) {
        ConfirmDialog(
            title = "Finish and save this workout?",
            message = "${workout.sets.size} sets will be saved from the numbers you logged.",
            confirmLabel = "Finish & save",
            cancelLabel = "Keep training",
            onConfirm = {
                confirmFinish = false
                error = null
                model.finishWorkout()
            },
            onDismiss = { confirmFinish = false },
        )
    }
    if (confirmDiscard) {
        ConfirmDialog(
            title = "Discard this workout?",
            message = "Nothing from this session will be saved.",
            confirmLabel = "Discard workout",
            destructive = true,
            cancelLabel = "Keep training",
            onConfirm = {
                confirmDiscard = false
                model.discardWorkout()
            },
            onDismiss = { confirmDiscard = false },
        )
    }
    if (confirmSkip) {
        ConfirmDialog(
            title = "Skip this exercise?",
            message = "Sets you have not logged will not be saved. You can come back to this movement later.",
            confirmLabel = "Skip exercise",
            destructive = true,
            cancelLabel = "Keep going",
            onConfirm = {
                confirmSkip = false
                model.skipExercise()
            },
            onDismiss = { confirmSkip = false },
        )
    }
}

private fun formatNumber(value: Double): String {
    val rounded = Math.round(value).toDouble()
    return if (kotlin.math.abs(value - rounded) < 0.05) "${rounded.toInt()}"
    else String.format(java.util.Locale.US, "%.1f", value)
}

private fun statusLabel(workout: ActiveWorkout, now: Long): String {
    if (workout.status == WorkoutRunStatus.PAUSED) return "Paused"
    val rest = workout.rest
    if (rest != null) return "Resting · ${rest.remaining(now)}s left"
    return "Set ${minOf(workout.sets.size + 1, workout.totalPlannedSets)} of ${workout.totalPlannedSets}"
}

@Composable
private fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    cancelLabel: String,
    destructive: Boolean = false,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = FormaTheme.colors
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surfaceRaised,
        titleContentColor = colors.text,
        textContentColor = colors.textSecondary,
        title = { Text(title, style = displayFont(19f, FontWeight.SemiBold)) },
        text = { Text(message, style = bodyFont(13f)) },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onConfirm) {
                Text(
                    confirmLabel,
                    color = if (destructive) colors.danger else colors.accentText,
                    style = bodyFont(14f, FontWeight.Medium),
                )
            }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) {
                Text(cancelLabel, color = colors.textSecondary, style = bodyFont(14f))
            }
        },
    )
}

@Composable
private fun ProgressStrip(workout: ActiveWorkout, now: Long) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.md))
            .padding(horizontal = Spacing.md, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        FormaIcon("checkmark.circle.fill", size = 14.dp, tint = colors.accentText)
        Text(
            "${workout.sets.size} of ${workout.totalPlannedSets} sets logged",
            style = bodyFont(12f, FontWeight.Medium),
            color = colors.textSecondary,
        )
        Spacer(Modifier.weight(1f))
        workout.rest?.let { rest ->
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                FormaIcon("timer", size = 11.dp, tint = colors.accentText)
                Text(
                    Formatters.clock(rest.remaining(now)),
                    style = bodyFont(12f, FontWeight.SemiBold),
                    color = colors.accentText,
                )
            }
        }
    }
}

@Composable
private fun CurrentExerciseCard(
    workout: ActiveWorkout,
    exercise: WorkoutExercise,
    detail: Exercise?,
    name: String,
    now: Long,
    units: UnitSystem,
    repsText: String,
    weightText: String,
    onRepsChange: (String) -> Unit,
    onWeightChange: (String) -> Unit,
    onLog: () -> Unit,
    onRemoveLast: () -> Unit,
    onPauseRest: () -> Unit,
    onSkipRest: () -> Unit,
    onReplace: (String) -> Unit,
    onConfirmSkip: () -> Unit,
) {
    val colors = FormaTheme.colors
    val completed = workout.setsFor(exercise).size
    val isComplete = completed >= exercise.sets
    var showReplace by remember(exercise.id) { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.xl))
            .background(colors.surface)
            .border(1.dp, colors.accentBorder, RoundedCornerShape(Radius.xl))
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Overline(text = if (isComplete) "Exercise complete" else "Current exercise")
                Text(name, style = displayFont(25f, FontWeight.Bold), color = colors.text)
            }
            if (detail != null) {
                ExerciseGlyph(exercise = detail, size = 48.dp)
            }
        }
        if (detail != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                detail.primaryMuscles.take(3).forEach { muscle ->
                    Text(
                        muscle.label,
                        style = bodyFont(10f, FontWeight.Medium),
                        color = colors.textSecondary,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(colors.surfaceRaised)
                            .padding(horizontal = 7.dp, vertical = 3.dp),
                    )
                }
            }
            detail.cues.firstOrNull()?.let { cue ->
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Box(Modifier.padding(top = 2.dp)) {
                        FormaIcon("target", size = 11.dp, tint = colors.accentText)
                    }
                    Text(cue, style = bodyFont(11.5f), color = colors.textSecondary)
                }
            }
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            TargetPill("${exercise.sets}", "sets")
            TargetPill("${exercise.repsMin}–${exercise.repsMax}", "reps")
            TargetPill(if (exercise.restSeconds == 0) "—" else "${exercise.restSeconds}s", "rest")
            Spacer(Modifier.weight(1f))
            SetDots(total = exercise.sets, completed = completed)
        }

        val rest = workout.rest
        if (rest != null && (!isComplete || rest.exerciseId == exercise.exerciseId)) {
            RestCard(
                rest = rest,
                duration = exercise.restSeconds,
                now = now,
                onPauseRest = onPauseRest,
                onSkipRest = onSkipRest,
            )
        } else if (isComplete) {
            NoticeBanner(
                message = "All sets logged for this movement. Pick another exercise or finish the session.",
                icon = "checkmark.circle",
                accent = true,
            )
        } else if (workout.status == WorkoutRunStatus.ACTIVE) {
            InputRow(
                units = units,
                repsText = repsText,
                weightText = weightText,
                onRepsChange = onRepsChange,
                onWeightChange = onWeightChange,
            )
            PrimaryButton(
                title = "Log set ${completed + 1} of ${exercise.sets}",
                icon = "checkmark",
                onClick = onLog,
            )
            if (completed > 0) {
                TextButton(title = "Remove last set", destructive = true, onClick = onRemoveLast)
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            SecondaryButton(
                title = "Replace",
                icon = "arrow.triangle.2.circlepath",
                isDisabled = workout.status == WorkoutRunStatus.PAUSED,
                onClick = { showReplace = true },
            )
            SecondaryButton(
                title = "Skip",
                icon = "forward.end",
                isDisabled = workout.status == WorkoutRunStatus.PAUSED,
                onClick = onConfirmSkip,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Box(Modifier.padding(top = 1.dp)) {
                FormaIcon("camera.viewfinder", size = 13.dp, tint = colors.textTertiary)
            }
            Text(
                "Camera form analysis is available in the iOS app. This Android build does not include it.",
                style = bodyFont(10.5f),
                color = colors.textTertiary,
            )
        }
    }

    if (showReplace) {
        ReplaceSheetHost(
            current = exercise,
            exercises = com.gymapp.android.domain.ExerciseCatalog.all,
            onSelect = { id ->
                showReplace = false
                onReplace(id)
            },
            onDismiss = { showReplace = false },
        )
    }
}

@Composable
private fun TargetPill(value: String, label: String) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .clip(CircleShape)
            .background(colors.surfaceRaised)
            .padding(horizontal = 9.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(value, style = displayFont(15f, FontWeight.SemiBold), color = colors.text)
        Text(label, style = bodyFont(10f), color = colors.textTertiary)
    }
}

@Composable
private fun RestCard(
    rest: ActiveRest,
    duration: Int,
    now: Long,
    onPauseRest: () -> Unit,
    onSkipRest: () -> Unit,
) {
    val colors = FormaTheme.colors
    val remaining = rest.remaining(now)
    val total = maxOf(1, duration)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.accentSoft)
            .border(1.dp, colors.accentBorder, RoundedCornerShape(Radius.lg))
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.lg),
    ) {
        ProgressRing(
            progress = remaining.toDouble() / total,
            size = 82.dp,
            lineWidth = 8.dp,
            label = Formatters.clock(remaining),
            caption = if (rest.isPaused) "paused" else "rest",
        )
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(
                if (rest.isPaused) "Rest paused" else "Resting",
                style = displayFont(18f, FontWeight.SemiBold),
                color = colors.text,
            )
            Text(
                "Breathe. The next set starts when you are ready.",
                style = bodyFont(11.5f),
                color = colors.textSecondary,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Box(
                    Modifier
                        .clip(CircleShape)
                        .background(colors.accent)
                        .formaClickable(onClick = onPauseRest)
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                ) {
                    Text(
                        if (rest.isPaused) "Resume" else "Pause",
                        style = bodyFont(12f, FontWeight.SemiBold),
                        color = colors.accentInk,
                    )
                }
                Box(
                    Modifier
                        .clip(CircleShape)
                        .background(colors.surfaceRaised)
                        .formaClickable(onClick = onSkipRest)
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                ) {
                    Text("Skip rest", style = bodyFont(12f, FontWeight.Medium), color = colors.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun InputRow(
    units: UnitSystem,
    repsText: String,
    weightText: String,
    onRepsChange: (String) -> Unit,
    onWeightChange: (String) -> Unit,
) {
    val colors = FormaTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        InputField(
            label = "Reps",
            value = repsText,
            suffix = null,
            keyboardType = KeyboardType.Number,
            onValueChange = onRepsChange,
            modifier = Modifier.weight(1f),
        )
        InputField(
            label = "Weight (${units.abbreviation})",
            value = weightText,
            suffix = "Optional",
            keyboardType = KeyboardType.Decimal,
            onValueChange = onWeightChange,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun InputField(
    label: String,
    value: String,
    suffix: String?,
    keyboardType: KeyboardType,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = FormaTheme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = bodyFont(11f, FontWeight.Medium), color = colors.textSecondary)
        Box(
            Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clip(RoundedCornerShape(Radius.md))
                .background(colors.input)
                .border(1.dp, colors.border, RoundedCornerShape(Radius.md)),
            contentAlignment = Alignment.Center,
        ) {
            if (value.isEmpty() && suffix != null) {
                Text(suffix, style = displayFont(18f, FontWeight.SemiBold), color = colors.textTertiary)
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                textStyle = displayFont(22f, FontWeight.SemiBold).copy(color = colors.text, textAlign = TextAlign.Center),
                cursorBrush = SolidColor(colors.accentText),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun NextCard(workout: ActiveWorkout, exercise: WorkoutExercise, exercises: List<Exercise>) {
    val colors = FormaTheme.colors
    val next = workout.exercises.firstOrNull { it.position > exercise.position && !workout.allSetsComplete(it) }
        ?: return
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surfaceRaised)
            .padding(horizontal = Spacing.md, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Text(
            "NEXT",
            style = bodyFont(9.5f, FontWeight.SemiBold).copy(letterSpacing = 1.2.sp),
            color = colors.textTertiary,
        )
        Text(
            exerciseName(next.exerciseId, exercises),
            style = bodyFont(13f, FontWeight.SemiBold),
            color = colors.text,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        Text(
            "${next.sets} × ${next.repsMin}–${next.repsMax}",
            style = bodyFont(11f),
            color = colors.textTertiary,
        )
    }
}

@Composable
private fun WarmupCard(steps: List<String>, expanded: Boolean, onToggle: () -> Unit) {
    val colors = FormaTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surface)
            .padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Row(
            Modifier.fillMaxWidth().formaClickable(onClick = onToggle),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FormaIcon("flame", size = 12.dp, tint = colors.accentText)
            Spacer(Modifier.width(Spacing.sm))
            Text(
                "Warm-up · ${steps.size} steps",
                style = bodyFont(12f, FontWeight.SemiBold),
                color = colors.textSecondary,
                modifier = Modifier.weight(1f),
            )
            FormaIcon(if (expanded) "chevron.up" else "chevron.down", size = 10.dp, tint = colors.textTertiary)
        }
        if (expanded) {
            steps.forEach { step ->
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Box(
                        Modifier
                            .padding(top = 6.dp)
                            .size(4.dp)
                            .clip(CircleShape)
                            .background(colors.accentText),
                    )
                    Text(step, style = bodyFont(11.5f), color = colors.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun ExercisePicker(workout: ActiveWorkout, exercises: List<Exercise>, onSelect: (Int) -> Unit) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(title = "Exercises")
        Row(
            Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            workout.exercises.forEachIndexed { index, exercise ->
                val done = workout.allSetsComplete(exercise)
                val current = index == workout.currentExerciseIndex
                Column(
                    Modifier
                        .width(124.dp)
                        .clip(RoundedCornerShape(Radius.md))
                        .background(if (current) colors.accentSoft else colors.surface)
                        .border(1.dp, if (current) colors.accentBorder else colors.border, RoundedCornerShape(Radius.md))
                        .formaClickable { onSelect(index) }
                        .padding(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        FormaIcon(
                            when {
                                done -> "checkmark.circle.fill"
                                current -> "circle.inset.filled"
                                else -> "circle"
                            },
                            size = 11.dp,
                            tint = if (done || current) colors.accentText else colors.textTertiary,
                        )
                        Text(
                            "${index + 1}",
                            style = bodyFont(9.5f, FontWeight.SemiBold),
                            color = colors.textTertiary,
                        )
                    }
                    Text(
                        exerciseName(exercise.exerciseId, exercises),
                        style = bodyFont(11.5f, FontWeight.SemiBold),
                        color = if (current) colors.text else colors.textSecondary,
                        maxLines = 2,
                    )
                }
            }
        }
    }
}

@Composable
private fun CompletionCard(workout: ActiveWorkout, now: Long, onFinish: () -> Unit) {
    val colors = FormaTheme.colors
    FormaCard(style = CardStyle.ACCENT) {
        FormaIcon("checkmark.seal", size = 28.dp, tint = colors.accentText)
        Text("Every set is logged", style = displayFont(22f, FontWeight.Bold), color = colors.text)
        Text(
            "Finish to save ${workout.sets.size} sets and ${Formatters.minutesLabel(workout.elapsedSeconds(now))} of work.",
            style = bodyFont(12.5f),
            color = colors.textSecondary,
        )
        PrimaryButton(title = "Finish & save", icon = "checkmark", onClick = onFinish)
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun ReplaceSheetHost(
    current: WorkoutExercise,
    exercises: List<Exercise>,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = FormaTheme.colors.background,
        dragHandle = null,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.xl, bottom = Spacing.lg),
        ) {
            ReplaceExerciseSheetContent(
                current = current,
                exercises = exercises,
                onSelect = onSelect,
                onClose = onDismiss,
            )
        }
    }
}

// MARK: - Summary

@Composable
fun WorkoutSummaryScreen(
    state: FormaUiState,
    onViewProgress: () -> Unit,
    onDone: () -> Unit,
) {
    val colors = FormaTheme.colors
    val session = state.workoutSummary ?: return
    val exerciseCount = session.sets.map { it.exerciseId }.distinct().size
    val volume = session.sets
        .mapNotNull { set -> set.weightKg?.let { it * set.reps } }
        .takeIf { it.isNotEmpty() }
        ?.sum()
    val durationText = if (session.durationSeconds < 60) Formatters.clock(session.durationSeconds)
    else Formatters.minutesLabel(session.durationSeconds)

    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.xl)
            .padding(bottom = Spacing.xxxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.lg),
    ) {
        Box(
            Modifier
                .padding(top = Spacing.xl)
                .size(76.dp)
                .clip(RoundedCornerShape(26.dp))
                .background(colors.accentSoft)
                .border(1.dp, colors.accentBorder, RoundedCornerShape(26.dp)),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon("checkmark", size = 28.dp, tint = colors.accentText)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Overline(text = "Saved")
            Text(
                session.title,
                style = displayFont(27f, FontWeight.Bold),
                color = colors.text,
                textAlign = TextAlign.Center,
            )
            Text(
                "${Formatters.longDate(FormaDate.date(session.startedAt))} · ${Formatters.time(session.startedAt)}",
                style = bodyFont(12f),
                color = colors.textSecondary,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                StatTile(value = durationText, label = "Duration", modifier = Modifier.weight(1f))
                StatTile(value = "${session.sets.size}", label = "Sets", modifier = Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                StatTile(value = "${TrainingStats.totalReps(session.sets)}", label = "Reps", modifier = Modifier.weight(1f))
                StatTile(value = "$exerciseCount", label = "Exercises", accent = true, modifier = Modifier.weight(1f))
            }
        }
        if (volume != null) {
            FormaCard(style = CardStyle.RAISED) {
                KeyValueRow(
                    label = "Logged volume",
                    value = Formatters.weight(volume, state.units) + " total",
                    valueColor = colors.accentText,
                )
                Text(
                    "Only sets with a recorded weight are counted. Forma never estimates calories or heart rate.",
                    style = bodyFont(10.5f),
                    color = colors.textTertiary,
                )
            }
        }
        PrimaryButton(
            title = "Done",
            icon = "checkmark",
            modifier = Modifier.padding(top = Spacing.sm),
            onClick = onDone,
        )
        SecondaryButton(
            title = "View in Progress",
            icon = "chart.line.uptrend.xyaxis",
            onClick = onViewProgress,
        )
        Text(
            "Saved on this device. Open Progress to see it in your history.",
            style = bodyFont(10.5f),
            color = colors.textTertiary,
            textAlign = TextAlign.Center,
        )
    }
}

private fun exerciseName(id: String, exercises: List<Exercise>): String =
    exercises.firstOrNull { it.id == id }?.name ?: com.gymapp.android.domain.ExerciseCatalog.name(id)
