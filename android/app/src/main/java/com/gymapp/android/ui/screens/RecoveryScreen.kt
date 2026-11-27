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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.gymapp.android.core.FormaDate
import com.gymapp.android.core.Formatters
import com.gymapp.android.domain.TrainingStats
import com.gymapp.android.domain.WorkoutDay
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.ui.components.ExerciseGlyph
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaDivider
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PageHeading
import com.gymapp.android.ui.components.SectionHeader
import com.gymapp.android.ui.components.SubScreenHeader
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont

@Composable
fun RecoveryScreen(
    state: FormaUiState,
    onBack: () -> Unit,
    onOpenExercise: (String) -> Unit,
) {
    val colors = FormaTheme.colors
    val mobility = state.exercises.filter { it.category == com.gymapp.android.domain.ExerciseCategory.MOBILITY }
    val today = state.todayDay

    Column(Modifier.fillMaxSize()) {
        SubScreenHeader(onBack = onBack)
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.sm, bottom = Spacing.xxxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.xl),
        ) {
            PageHeading(
                eyebrow = "Recover",
                title = "Recovery",
                subtitle = "Rest is part of the programme. Keep it deliberate, not accidental.",
            )

            FormaCard(style = com.gymapp.android.ui.components.CardStyle.RAISED) {
                Overline(text = "Right now")
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(46.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(colors.accentSoft),
                        contentAlignment = Alignment.Center,
                    ) {
                        FormaIcon(
                            if (today?.isRestDay == true) "moon.stars" else "figure.cooldown",
                            size = 20.dp,
                            tint = colors.accentText,
                        )
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            if (today?.isRestDay == true) "Scheduled rest day" else "Training day",
                            style = displayFont(19f, FontWeight.SemiBold),
                            color = colors.text,
                        )
                        Text(
                            if (today?.isRestDay == true) {
                                today.restNote ?: "Keep today easy and let the work settle."
                            } else {
                                "If you have trained today, protect the rest of the evening: food, water, and sleep."
                            },
                            style = bodyFont(12f),
                            color = colors.textSecondary,
                        )
                    }
                }
                FormaDivider()
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xxl)) {
                    SnapshotStat(value = lastSessionLabel(state), label = "last session")
                    SnapshotStat(
                        value = "${TrainingStats.currentWeekCount(state.sessions)}/${maxOf(1, state.plan?.daysPerWeek ?: 3)}",
                        label = "this week",
                    )
                    SnapshotStat(
                        value = "${TrainingStats.currentStreak(state.sessions)} days",
                        label = "streak",
                    )
                    Spacer(Modifier.weight(1f))
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(title = "Today's guidance")
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(Radius.lg))
                        .background(colors.surface)
                        .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
                        .padding(Spacing.lg),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md),
                ) {
                    GuidanceRow(
                        icon = "bed.double",
                        title = "Sleep 7–9 hours",
                        detail = "The strongest recovery tool you have. Keep a consistent window.",
                    )
                    FormaDivider()
                    GuidanceRow(
                        icon = "drop",
                        title = "Drink water through the day",
                        detail = "Urine should stay pale. More if it is hot or you trained hard.",
                    )
                    FormaDivider()
                    GuidanceRow(
                        icon = "fork.knife",
                        title = "Eat enough protein",
                        detail = "Spread it across meals. You do not need to track every gram.",
                    )
                    FormaDivider()
                    GuidanceRow(
                        icon = "figure.walk",
                        title = "Move easily",
                        detail = "A 10–20 minute walk helps soreness without adding training stress.",
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(title = "Gentle mobility")
                if (mobility.isEmpty()) {
                    Text(
                        "No mobility exercises are available in the library right now.",
                        style = bodyFont(12f),
                        color = colors.textTertiary,
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        mobility.take(4).forEach { exercise ->
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(Radius.md))
                                    .background(colors.surface)
                                    .border(1.dp, colors.border, RoundedCornerShape(Radius.md))
                                    .formaClickable { onOpenExercise(exercise.id) }
                                    .padding(Spacing.md),
                                horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                ExerciseGlyph(exercise = exercise, size = 38.dp)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(
                                        exercise.name,
                                        style = bodyFont(13.5f, FontWeight.SemiBold),
                                        color = colors.text,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        exercise.primaryMuscles.joinToString(" · ") { it.label },
                                        style = bodyFont(10.5f),
                                        color = colors.textTertiary,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                                FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
                            }
                        }
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                SectionHeader(title = "Simple checklist")
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(Radius.lg))
                        .background(colors.surface)
                        .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
                        .padding(Spacing.lg),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    listOf(
                        "Soreness that fades with easy movement is normal. Sharp or joint pain is not.",
                        "If a warm-up makes a movement feel worse, skip that movement today.",
                        "Two hard sessions back to back are fine only if sleep and food are on point.",
                        "Hydration and a short walk beat an extra set of stretching.",
                    ).forEach { line ->
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            FormaIcon(
                                "checkmark.circle",
                                size = 12.dp,
                                tint = colors.accentText,
                            )
                            Text(line, style = bodyFont(12.5f), color = colors.textSecondary)
                        }
                    }
                }
            }

            NoticeBanner(
                message = "Recovery guidance is general. Persistent pain, sleep problems, or unusual fatigue deserve a qualified professional.",
                icon = "heart.text.square",
            )
        }
    }
}

@Composable
private fun SnapshotStat(value: String, label: String) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(value, style = bodyFont(13f, FontWeight.SemiBold), color = colors.text)
        Text(label, style = bodyFont(10f), color = colors.textTertiary)
    }
}

private fun lastSessionLabel(state: FormaUiState): String {
    val session = state.completedSessions.firstOrNull() ?: return "—"
    return Formatters.shortDate(FormaDate.date(session.startedAt))
}

@Composable
private fun GuidanceRow(icon: String, title: String, detail: String) {
    val colors = FormaTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Box(
            Modifier
                .size(34.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon(icon, size = 14.dp, tint = colors.accentText)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = bodyFont(13.5f, FontWeight.SemiBold), color = colors.text)
            Text(detail, style = bodyFont(11.5f), color = colors.textSecondary)
        }
    }
}
