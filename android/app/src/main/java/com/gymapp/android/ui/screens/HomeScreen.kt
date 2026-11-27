package com.gymapp.android.ui.screens

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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.core.Formatters
import com.gymapp.android.core.FormaDate
import com.gymapp.android.domain.TrainingStats
import com.gymapp.android.domain.WorkoutDay
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaEmptyState
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.ProfileAvatar
import com.gymapp.android.ui.components.ProgressRing
import com.gymapp.android.ui.components.SecondaryButton
import com.gymapp.android.ui.components.SectionHeader
import com.gymapp.android.ui.components.TagLabel
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont
import java.time.LocalDate

@Composable
fun HomeScreen(
    model: FormaViewModel,
    state: FormaUiState,
    startRequest: Int,
    onOpenWorkouts: () -> Unit,
    onOpenProgress: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenLibrary: () -> Unit,
    onOpenRecovery: () -> Unit,
    onOpenSession: (String) -> Unit,
) {
    val colors = FormaTheme.colors
    var startError by remember { mutableStateOf<String?>(null) }

    val firstName = state.profile?.name?.trim()?.split(" ")?.firstOrNull()?.takeIf { it.isNotEmpty() } ?: "there"
    val weekCount = TrainingStats.currentWeekCount(state.sessions)
    val weeklyTarget = maxOf(1, state.plan?.daysPerWeek ?: state.preferences?.workoutDays?.size ?: 3)

    fun start(day: WorkoutDay) {
        startError = null
        if (state.activeWorkout != null) return
        model.startWorkout(day) { startError = it }
    }

    LaunchedEffect(startRequest) {
        if (startRequest == 0) return@LaunchedEffect
        if (state.activeWorkout != null) return@LaunchedEffect
        val day = state.todayDay
        if (day == null || day.isRestDay || day.exercises.isEmpty()) {
            startError = "There is no workout planned for today."
            return@LaunchedEffect
        }
        if (TrainingStats.sessionsOnDay(state.sessions, LocalDate.now()).isNotEmpty()) {
            startError = "Today's session is already complete."
            return@LaunchedEffect
        }
        start(day)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(horizontal = Spacing.xl)
            .padding(top = Spacing.md, bottom = Spacing.xxxl),
        verticalArrangement = Arrangement.spacedBy(Spacing.xl),
    ) {
        HomeHeader(
            firstName = firstName,
            profileName = state.profile?.name.orEmpty(),
            photoPath = state.profile?.photoPath,
            onOpenProfile = onOpenProfile,
        )

        startError?.let { ErrorBanner(message = it) }

        TodaySection(
            state = state,
            onStart = ::start,
            onOpenWorkouts = onOpenWorkouts,
            onOpenRecovery = onOpenRecovery,
        )

        FormaCard {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
                ProgressRing(
                    progress = weekCount.toDouble() / weeklyTarget.toDouble(),
                    size = 92.dp,
                    lineWidth = 9.dp,
                    label = "$weekCount/$weeklyTarget",
                    caption = "this week",
                )
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("Weekly rhythm", style = displayFont(18f, FontWeight.SemiBold), color = colors.text)
                        Text(
                            if (weekCount >= weeklyTarget) {
                                "Target hit — anything else is a bonus."
                            } else {
                                "${weeklyTarget - weekCount} session${if (weeklyTarget - weekCount == 1) "" else "s"} to go."
                            },
                            style = bodyFont(11.5f),
                            color = colors.textSecondary,
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.lg)) {
                        MiniStat("${TrainingStats.currentStreak(state.sessions)}", "day streak")
                        MiniStat("${state.completedSessions.size}", "total")
                        MiniStat(
                            "${state.completedSessions.sumOf { TrainingStats.sessionReps(it) }}",
                            "reps",
                        )
                    }
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
            QuickAction(
                icon = "figure.strengthtraining.traditional",
                title = "Exercise library",
                detail = "Form guides",
                modifier = Modifier.weight(1f),
                onClick = onOpenLibrary,
            )
            QuickAction(
                icon = "leaf",
                title = "Recovery",
                detail = "Mobility & rest",
                modifier = Modifier.weight(1f),
                onClick = onOpenRecovery,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(title = "Recent sessions", actionLabel = "See all", onAction = onOpenProgress)
            if (state.completedSessions.isEmpty()) {
                FormaEmptyState(
                    icon = "calendar.badge.clock",
                    title = "No sessions yet",
                    message = "Finish your first workout and it will appear here with the sets you actually logged.",
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    state.completedSessions.take(3).forEach { session ->
                        SessionRow(session.title, TrainingStats.sessionSubtitle(session)) {
                            onOpenSession(session.id)
                        }
                    }
                }
            }
        }

        Text(
            "Forma provides general fitness guidance, not medical advice. Stop if you feel pain, dizziness, or unusual shortness of breath.",
            style = bodyFont(10.5f),
            color = colors.textTertiary,
            modifier = Modifier.padding(top = Spacing.sm),
        )
    }
}

@Composable
private fun HomeHeader(firstName: String, profileName: String, photoPath: String?, onOpenProfile: () -> Unit) {
    val colors = FormaTheme.colors
    val context = androidx.compose.ui.platform.LocalContext.current
    val photo by androidx.compose.runtime.produceState<android.graphics.Bitmap?>(initialValue = null, photoPath) {
        value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            com.gymapp.android.core.ProfilePhotoStore.load(context, photoPath)
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                Formatters.longDate(LocalDate.now()).uppercase(),
                style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.5.sp),
                color = colors.accentText,
            )
            Text(
                "${Formatters.greeting()}, $firstName.",
                style = displayFont(30f, FontWeight.Bold),
                color = colors.text,
            )
        }
        Box(
            Modifier
                .size(44.dp)
                .clip(CircleShape)
                .formaClickable(onClick = onOpenProfile),
            contentAlignment = Alignment.Center,
        ) {
            ProfileAvatar(name = profileName, size = 38.dp, photo = photo)
        }
    }
}

@Composable
private fun TodaySection(
    state: FormaUiState,
    onStart: (WorkoutDay) -> Unit,
    onOpenWorkouts: () -> Unit,
    onOpenRecovery: () -> Unit,
) {
    val colors = FormaTheme.colors
    val day = state.todayDay
    when {
        day == null -> FormaCard {
            Overline("Get started")
            Text("No plan yet", style = displayFont(22f, FontWeight.Bold), color = colors.text)
            Text(
                "Build a plan in Workouts, then today's session will show up here.",
                style = bodyFont(13f),
                color = colors.textSecondary,
            )
            SecondaryButton(title = "Open Workouts", icon = "dumbbell", onClick = onOpenWorkouts)
        }

        day.isRestDay -> RestCard(
            day = day,
            state = state,
            onOpenWorkouts = onOpenWorkouts,
            onOpenRecovery = onOpenRecovery,
        )

        else -> WorkoutCard(day = day, state = state, onStart = { onStart(day) })
    }
}

@Composable
private fun WorkoutCard(day: WorkoutDay, state: FormaUiState, onStart: () -> Unit) {
    val colors = FormaTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.xl))
            .background(colors.surface)
            .background(colors.accentSoft)
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Overline(if (state.activeWorkout != null) "In progress" else "Today's session")
            Spacer(Modifier.weight(1f))
            state.plan?.let { TagLabel(it.source.label) }
        }
        Text(day.title, style = displayFont(27f, FontWeight.Bold), color = colors.text)
        if (day.focus.isNotEmpty()) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                day.focus.forEach { muscle ->
                    Text(
                        muscle.label,
                        style = bodyFont(10.5f, FontWeight.Medium),
                        color = colors.textSecondary,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(colors.surfaceRaised)
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                    )
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xl)) {
            TodayStat("${day.exercises.size}", "exercises")
            TodayStat("${day.exercises.sumOf { it.sets }}", "sets")
            TodayStat("${day.estimatedMinutes}", "minutes")
        }
        PrimaryButton(
            title = if (state.activeWorkout != null) "Resume workout" else "Start workout",
            icon = "play.fill",
            onClick = onStart,
        )
    }
}

@Composable
private fun RestCard(
    day: WorkoutDay,
    state: FormaUiState,
    onOpenWorkouts: () -> Unit,
    onOpenRecovery: () -> Unit,
) {
    val colors = FormaTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.xl))
            .background(colors.surface)
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Overline("Recovery")
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(42.dp).clip(RoundedCornerShape(13.dp)).background(colors.accentSoft),
                contentAlignment = Alignment.Center,
            ) {
                FormaIcon("moon.stars", size = 19.dp, tint = colors.accentText)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Rest day", style = displayFont(22f, FontWeight.Bold), color = colors.text)
                Text(
                    day.restNote ?: "Recovery is part of the programme. Keep today easy.",
                    style = bodyFont(12.5f),
                    color = colors.textSecondary,
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(
                "Open recovery",
                style = bodyFont(13f, FontWeight.SemiBold),
                color = colors.accentInk,
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(Radius.md))
                    .background(colors.accent)
                    .formaClickable(onClick = onOpenRecovery)
                    .padding(vertical = 13.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            state.nextDay?.let { next ->
                Text(
                    "Next: ${next.title}",
                    style = bodyFont(13f, FontWeight.Medium),
                    color = colors.text,
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(Radius.md))
                        .background(colors.surfaceRaised)
                        .formaClickable(onClick = onOpenWorkouts)
                        .padding(vertical = 13.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun TodayStat(value: String, label: String) {
    val colors = FormaTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Bottom) {
        Text(value, style = displayFont(17f, FontWeight.SemiBold), color = colors.text)
        Text(label, style = bodyFont(11f), color = colors.textTertiary)
    }
}

@Composable
private fun MiniStat(value: String, label: String) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(value, style = displayFont(17f, FontWeight.SemiBold), color = colors.text)
        Text(label, style = bodyFont(10f), color = colors.textTertiary)
    }
}

@Composable
private fun QuickAction(
    icon: String,
    title: String,
    detail: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = FormaTheme.colors
    Column(
        modifier
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .formaClickable(onClick = onClick)
            .padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Box(
            Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon(icon, size = 15.dp, tint = colors.accentText)
        }
        Text(title, style = bodyFont(13f, FontWeight.SemiBold), color = colors.text)
        Text(detail, style = bodyFont(10.5f), color = colors.textTertiary)
    }
}

@Composable
fun SessionRow(title: String, subtitle: String, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surface)
            .formaClickable(onClick = onClick)
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)).background(colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon("checkmark.circle.fill", size = 16.dp, tint = colors.accentText)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
            Text(subtitle, style = bodyFont(11f), color = colors.textTertiary)
        }
        FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
    }
}
