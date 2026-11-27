package com.gymapp.android.ui.screens

import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.core.FormaDate
import com.gymapp.android.core.Formatters
import com.gymapp.android.domain.CompletedSet
import com.gymapp.android.domain.ProgressRecord
import com.gymapp.android.domain.TrainingStats
import com.gymapp.android.domain.UnitSystem
import com.gymapp.android.domain.WorkoutSession
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.CardStyle
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaChip
import com.gymapp.android.ui.components.FormaDivider
import com.gymapp.android.ui.components.FormaEmptyState
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.FormaTextEditor
import com.gymapp.android.ui.components.FormaTextField
import com.gymapp.android.ui.components.KeyValueRow
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PageHeading
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.SectionHeader
import com.gymapp.android.ui.components.SheetHeading
import com.gymapp.android.ui.components.StatTile
import com.gymapp.android.ui.components.SubScreenHeader
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil

private enum class RangeOption(val label: String) {
    WEEK("1W"),
    MONTH("1M"),
    THREE_MONTHS("3M"),
    YEAR("1Y");

    val title: String
        get() = when (this) {
            WEEK -> "Sessions per day"
            MONTH, THREE_MONTHS -> "Sessions per week"
            YEAR -> "Sessions per month"
        }

    val subtitle: String
        get() = when (this) {
            WEEK -> "Last seven days"
            MONTH -> "Last four weeks"
            THREE_MONTHS -> "Last thirteen weeks"
            YEAR -> "Last twelve months"
        }

    val days: Int
        get() = when (this) {
            WEEK -> 7
            MONTH -> 30
            THREE_MONTHS -> 90
            YEAR -> 365
        }
}

private data class ChartBucket(val label: String, val value: Int)

@Composable
fun ProgressScreen(
    model: FormaViewModel,
    state: FormaUiState,
    onOpenSession: (String) -> Unit,
) {
    val colors = FormaTheme.colors
    var range by remember { mutableStateOf(RangeOption.MONTH) }
    var showCheckIn by remember { mutableStateOf(false) }

    val buckets = remember(range, state.sessions) {
        when (range) {
            RangeOption.WEEK -> TrainingStats.lastDaysCounts(state.sessions, 7)
                .map { ChartBucket(it.label, it.value) }
            RangeOption.MONTH -> TrainingStats.lastWeeksCounts(state.sessions, 4)
                .map { ChartBucket(it.label, it.value) }
            RangeOption.THREE_MONTHS -> TrainingStats.lastWeeksCounts(state.sessions, 13)
                .map { ChartBucket(it.label, it.value) }
            RangeOption.YEAR -> TrainingStats.lastMonthsCounts(state.sessions, 12)
                .map { ChartBucket(it.label, it.value) }
        }
    }

    val cutoff = System.currentTimeMillis() - range.days.toLong() * 24 * 60 * 60 * 1000
    val sessionPoints = state.completedSessions
        .filter { it.startedAt >= cutoff }
        .sortedBy { it.startedAt }
        .takeLast(40)
    val weightRecords = state.progress
        .filter { it.bodyweightKg != null }
        .sortedBy { it.recordedAt }
    val totalSeconds = state.completedSessions.sumOf { it.durationSeconds }
    val timeTrainedText = when {
        totalSeconds in 1..59 -> "<1 min"
        else -> Formatters.minutesLabel(totalSeconds)
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
            eyebrow = "Progress",
            title = "The work adds up",
            subtitle = "Charts use only sessions and sets you have actually logged.",
        )
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                val sessionCount = state.completedSessions.size
                StatTile(
                    value = "$sessionCount",
                    label = if (sessionCount == 1) "Session" else "Sessions",
                    detail = "completed",
                    modifier = Modifier.weight(1f),
                )
                val streak = TrainingStats.currentStreak(state.sessions)
                StatTile(
                    value = "$streak",
                    label = "Streak",
                    detail = if (streak == 1) "day" else "days",
                    accent = true,
                    modifier = Modifier.weight(1f),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                val reps = state.completedSessions.sumOf { TrainingStats.sessionReps(it) }
                StatTile(
                    value = "$reps",
                    label = if (reps == 1) "Rep" else "Reps",
                    detail = "logged",
                    modifier = Modifier.weight(1f),
                )
                StatTile(
                    value = timeTrainedText,
                    label = "Time",
                    detail = "trained",
                    modifier = Modifier.weight(1f),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            RangeOption.entries.forEach { option ->
                FormaChip(
                    label = option.label,
                    selected = range == option,
                    onClick = { range = option },
                )
            }
            Spacer(Modifier.weight(1f))
        }

        ChartCard(
            title = range.title,
            subtitle = range.subtitle,
            empty = buckets.all { it.value == 0 },
            emptyMessage = "Finish a session to start the chart.",
        ) {
            BarChart(buckets = buckets, modifier = Modifier.height(160.dp))
        }

        ChartCard(
            title = "Reps per session",
            subtitle = range.subtitle,
            empty = sessionPoints.isEmpty(),
            emptyMessage = "Your logged reps will appear here.",
        ) {
            LineChart(
                values = sessionPoints.map { TrainingStats.sessionReps(it).toFloat() },
                labels = sessionPoints.map { Formatters.shortDate(FormaDate.date(it.startedAt)) },
                modifier = Modifier.height(150.dp),
                showLabels = true,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(title = "Check-ins", actionLabel = "Log check-in", onAction = { showCheckIn = true })
            val latest = state.latestCheckIn
            if (latest != null) {
                FormaCard(style = CardStyle.RAISED) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(
                                latest.bodyweightKg?.let { Formatters.bodyWeight(it, state.units) } ?: "No weight logged",
                                style = displayFont(28f, FontWeight.Bold),
                                color = colors.text,
                            )
                            Text(
                                Formatters.longDate(FormaDate.date(latest.recordedAt)),
                                style = bodyFont(11f),
                                color = colors.textTertiary,
                            )
                        }
                        weightChange(weightRecords, state.units)?.let { change ->
                            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(change, style = bodyFont(13f, FontWeight.SemiBold), color = colors.accentText)
                                Text("since first", style = bodyFont(9.5f), color = colors.textTertiary)
                            }
                        }
                    }
                    latest.notes?.takeIf { it.isNotEmpty() }?.let { notes ->
                        Text(notes, style = bodyFont(12.5f), color = colors.textSecondary)
                    }
                }
                if (weightRecords.size >= 2) {
                    WeightChart(records = weightRecords, units = state.units)
                }
            } else {
                FormaEmptyState(
                    icon = "scalemass",
                    title = "No check-ins yet",
                    message = "Log bodyweight and a short note whenever you want a reference point. This is optional.",
                    actionTitle = "Log check-in",
                    onAction = { showCheckIn = true },
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(title = "Session history")
            if (state.completedSessions.isEmpty()) {
                FormaEmptyState(
                    icon = "calendar",
                    title = "Nothing logged",
                    message = "Completed workouts appear here with the sets you actually recorded.",
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    state.completedSessions.forEach { session ->
                        HistoryRow(session = session, onClick = { onOpenSession(session.id) })
                    }
                }
            }
        }
    }

    if (showCheckIn) {
        CheckInSheet(
            state = state,
            onSave = { kg, notes, done ->
                model.addCheckIn(kg, notes) { error ->
                    if (error == null) showCheckIn = false
                    done(error)
                }
            },
            onDismiss = { showCheckIn = false },
        )
    }
}

private fun weightChange(records: List<ProgressRecord>, units: UnitSystem): String? {
    if (records.size < 2) return null
    val first = records.first().bodyweightKg ?: return null
    val latest = records.last().bodyweightKg ?: return null
    if (first <= 0) return null
    val delta = latest - first
    if (abs(delta) < 0.1) return "No change"
    val sign = if (delta > 0) "+" else "−"
    val magnitude = if (units == UnitSystem.KG) abs(delta) else abs(delta) * 2.2046226218
    val suffix = if (units == UnitSystem.KG) "kg" else "lb"
    return "$sign${String.format(Locale.US, "%.1f", magnitude)} $suffix"
}

@Composable
private fun ChartCard(
    title: String,
    subtitle: String,
    empty: Boolean,
    emptyMessage: String,
    content: @Composable () -> Unit,
) {
    val colors = FormaTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Row(Modifier.fillMaxWidth()) {
            Text(title, style = displayFont(17f, FontWeight.SemiBold), color = colors.text)
            Spacer(Modifier.weight(1f))
            Text(subtitle, style = bodyFont(11.5f, FontWeight.Medium), color = colors.textSecondary)
        }
        if (empty) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .height(120.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                FormaIcon("chart.bar", size = 20.dp, tint = colors.textSecondary)
                Spacer(Modifier.height(6.dp))
                Text(emptyMessage, style = bodyFont(11.5f), color = colors.textSecondary)
            }
        } else {
            content()
        }
    }
}

@Composable
private fun BarChart(buckets: List<ChartBucket>, modifier: Modifier = Modifier) {
    val colors = FormaTheme.colors
    val maxValue = maxOf(1, buckets.maxOfOrNull { it.value } ?: 1)
    Column(modifier.fillMaxWidth()) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            val gridCount = 3
            repeat(gridCount + 1) { index ->
                val y = size.height * index / gridCount
                drawLine(
                    color = colors.border,
                    start = Offset(0f, y),
                    end = Offset(size.width, y),
                    strokeWidth = 1f,
                )
            }
            if (buckets.isEmpty()) return@Canvas
            val slot = size.width / buckets.size
            val barWidth = (slot * 0.52f).coerceAtLeast(2f)
            buckets.forEachIndexed { index, bucket ->
                val fraction = bucket.value.toFloat() / maxValue
                val barHeight = size.height * fraction * 0.92f
                val left = slot * index + (slot - barWidth) / 2f
                if (barHeight > 0.5f) {
                    drawRoundRect(
                        brush = Brush.verticalGradient(
                            listOf(colors.accentText, colors.accentText.copy(alpha = 0.6f)),
                        ),
                        topLeft = Offset(left, size.height - barHeight),
                        size = androidx.compose.ui.geometry.Size(barWidth, barHeight),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(4.dp.toPx()),
                    )
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            val step = ceil(buckets.size / 6.0).toInt().coerceAtLeast(1)
            buckets.forEachIndexed { index, bucket ->
                if (index % step == 0 || index == buckets.lastIndex) {
                    Text(
                        bucket.label,
                        style = bodyFont(9f),
                        color = colors.textTertiary,
                        textAlign = TextAlign.Center,
                    )
                } else {
                    Spacer(Modifier.width(1.dp))
                }
            }
        }
    }
}

@Composable
private fun LineChart(
    values: List<Float>,
    labels: List<String>,
    modifier: Modifier = Modifier,
    showLabels: Boolean,
) {
    val colors = FormaTheme.colors
    if (values.isEmpty()) return
    val maxValue = maxOf(1f, values.max())
    Column(modifier.fillMaxWidth()) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            val gridCount = 3
            repeat(gridCount + 1) { index ->
                val y = size.height * index / gridCount
                drawLine(colors.border, Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
            }
            val denominator = maxOf(1, values.size - 1)
            val points = values.mapIndexed { index, value ->
                Offset(
                    x = if (values.size == 1) size.width / 2f else size.width * index / denominator,
                    y = size.height * (1f - (value / maxValue) * 0.92f),
                )
            }
            if (points.size > 1) {
                val area = Path().apply {
                    moveTo(points.first().x, size.height)
                    points.forEach { lineTo(it.x, it.y) }
                    lineTo(points.last().x, size.height)
                    close()
                }
                drawPath(
                    area,
                    brush = Brush.verticalGradient(
                        listOf(colors.accentText.copy(alpha = 0.22f), colors.accentText.copy(alpha = 0.02f)),
                    ),
                )
                val line = Path().apply {
                    moveTo(points.first().x, points.first().y)
                    points.drop(1).forEach { lineTo(it.x, it.y) }
                }
                drawPath(line, colors.accentText, style = Stroke(width = 2.dp.toPx()))
            }
            points.forEach { point ->
                drawCircle(colors.accentText, radius = 3.dp.toPx(), center = point)
            }
        }
        if (showLabels && labels.isNotEmpty()) {
            Spacer(Modifier.height(6.dp))
            if (labels.size == 1) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    Text(labels.first(), style = bodyFont(9f), color = colors.textTertiary)
                }
            } else {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(labels.first(), style = bodyFont(9f), color = colors.textTertiary)
                    if (labels.size > 2) {
                        Text(labels[labels.size / 2], style = bodyFont(9f), color = colors.textTertiary)
                    }
                    Text(labels.last(), style = bodyFont(9f), color = colors.textTertiary)
                }
            }
        }
    }
}

@Composable
private fun WeightChart(records: List<ProgressRecord>, units: UnitSystem) {
    val colors = FormaTheme.colors
    val recent = records.takeLast(12)
    val values = recent.map { record ->
        val kg = record.bodyweightKg ?: 0.0
        (if (units == UnitSystem.KG) kg else kg * 2.2046226218).toFloat()
    }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Row(Modifier.fillMaxWidth()) {
            Text("Bodyweight", style = displayFont(16f, FontWeight.SemiBold), color = colors.text)
            Spacer(Modifier.weight(1f))
            Text(
                units.abbreviation.uppercase(),
                style = bodyFont(9.5f, FontWeight.SemiBold).copy(letterSpacing = 1.sp),
                color = colors.textTertiary,
            )
        }
        LineChart(
            values = values,
            labels = recent.map { Formatters.shortDate(FormaDate.date(it.recordedAt)) },
            modifier = Modifier.height(130.dp),
            showLabels = true,
        )
    }
}

@Composable
private fun HistoryRow(session: WorkoutSession, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    val date = FormaDate.date(session.startedAt)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.md))
            .formaClickable(onClick = onClick)
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Column(
            Modifier
                .size(42.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(colors.surfaceRaised),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text("${date.dayOfMonth}", style = displayFont(17f, FontWeight.Bold), color = colors.text)
            Text(
                date.format(DateTimeFormatter.ofPattern("MMM", Locale.getDefault())).uppercase(),
                style = bodyFont(8.5f, FontWeight.SemiBold),
                color = colors.textTertiary,
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(session.title, style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
            Text(TrainingStats.sessionSubtitle(session), style = bodyFont(10.5f), color = colors.textTertiary)
        }
        FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
    }
}

// MARK: - Check-in

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CheckInSheet(
    state: FormaUiState,
    onSave: (Double?, String, (String?) -> Unit) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = FormaTheme.colors
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var weight by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        if (weight.isEmpty()) {
            val latest = state.latestCheckIn?.bodyweightKg
            if (latest != null) {
                val value = if (state.units == UnitSystem.KG) latest else latest * 2.2046226218
                weight = String.format(Locale.US, "%.1f", value)
            }
        }
    }

    fun save() {
        error = null
        var kilograms: Double? = null
        val trimmed = weight.trim().replace(",", ".")
        if (trimmed.isNotEmpty()) {
            val entered = trimmed.toDoubleOrNull()
            if (entered == null || entered <= 20 || entered >= 400) {
                error = "Enter a bodyweight in ${state.units.abbreviation} or leave it blank."
                return
            }
            kilograms = if (state.units == UnitSystem.KG) entered else entered / 2.2046226218
        }
        saving = true
        onSave(kilograms, notes) { message ->
            saving = false
            error = message
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = colors.background,
        dragHandle = null,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.xl, bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            SheetHeading(
                title = "Log check-in",
                subtitle = "Optional. Bodyweight is a reference point, not a score.",
                onClose = onDismiss,
            )
            error?.let { ErrorBanner(message = it) }
            FormaTextField(
                value = weight,
                onValueChange = { weight = it.filter { ch -> ch.isDigit() || ch == '.' || ch == ',' } },
                placeholder = "Optional",
                label = "Bodyweight (${state.units.abbreviation})",
                keyboardType = KeyboardType.Decimal,
                suffix = state.units.abbreviation,
            )
            FormaTextEditor(
                value = notes,
                onValueChange = { notes = it },
                label = "Notes (optional)",
                placeholder = "Energy, sleep, appetite, anything worth remembering",
            )
            NoticeBanner(
                message = "Forma does not give diet plans or weight-loss targets. If bodyweight is complicated for you, skip this and focus on how you feel and perform.",
                icon = "info.circle",
            )
            PrimaryButton(
                title = "Save check-in",
                icon = "checkmark",
                isLoading = saving,
                onClick = ::save,
            )
        }
    }
}

// MARK: - Session detail

@Composable
fun SessionDetailScreen(
    state: FormaUiState,
    sessionId: String,
    onBack: () -> Unit,
) {
    val colors = FormaTheme.colors
    val session = state.sessions.firstOrNull { it.id == sessionId }
    if (session == null) {
        Column(Modifier.fillMaxSize()) {
            SubScreenHeader(onBack = onBack)
            FormaEmptyState(
                icon = "list.bullet.clipboard",
                title = "Session not found",
                message = "This session is no longer stored on this device.",
            )
        }
        return
    }

    val order = mutableListOf<String>()
    val grouped = mutableMapOf<String, MutableList<CompletedSet>>()
    session.sets.forEach { set ->
        if (!grouped.containsKey(set.exerciseId)) order.add(set.exerciseId)
        grouped.getOrPut(set.exerciseId) { mutableListOf() }.add(set)
    }
    val totalVolume = session.sets
        .mapNotNull { set -> set.weightKg?.let { it * set.reps } }
        .takeIf { it.isNotEmpty() }
        ?.sum()

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
                eyebrow = Formatters.longDate(FormaDate.date(session.startedAt)),
                title = session.title,
                subtitle = endedLabel(session),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                StatTile(
                    value = Formatters.minutesLabel(session.durationSeconds),
                    label = "Duration",
                    modifier = Modifier.weight(1f),
                )
                StatTile(
                    value = "${session.sets.size}",
                    label = "Sets",
                    modifier = Modifier.weight(1f),
                )
                StatTile(
                    value = "${TrainingStats.sessionReps(session)}",
                    label = "Reps",
                    modifier = Modifier.weight(1f),
                )
            }
            if (totalVolume != null) {
                FormaCard(style = CardStyle.RAISED) {
                    KeyValueRow(
                        label = "Logged volume",
                        value = Formatters.weight(totalVolume, state.units) + " total",
                        valueColor = colors.accentText,
                    )
                    Text(
                        "Only sets with a recorded weight are counted.",
                        style = bodyFont(10.5f),
                        color = colors.textTertiary,
                    )
                }
            }
            if (order.isEmpty()) {
                FormaEmptyState(
                    icon = "list.bullet.clipboard",
                    title = "No sets recorded",
                    message = "This session was saved without completed sets.",
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(title = "Exercises")
                    order.forEach { exerciseId ->
                        val sets = grouped[exerciseId].orEmpty().sortedBy { it.setNumber }
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(Radius.md))
                                .background(colors.surface)
                                .border(1.dp, colors.border, RoundedCornerShape(Radius.md))
                                .padding(Spacing.md),
                            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                        ) {
                            Text(
                                exerciseName(exerciseId, state),
                                style = bodyFont(14f, FontWeight.SemiBold),
                                color = colors.text,
                            )
                            sets.forEach { set ->
                                Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        "Set ${set.setNumber}",
                                        style = bodyFont(12f),
                                        color = colors.textTertiary,
                                        modifier = Modifier.width(56.dp),
                                    )
                                    Text("${set.reps} reps", style = bodyFont(12f, FontWeight.Medium), color = colors.text)
                                    Spacer(Modifier.weight(1f))
                                    Text(
                                        set.weightKg?.let { Formatters.weight(it, state.units) } ?: "—",
                                        style = bodyFont(12f),
                                        color = if (set.weightKg != null) colors.textSecondary else colors.textTertiary,
                                    )
                                }
                            }
                        }
                    }
                }
            }
            session.notes?.takeIf { it.isNotEmpty() }?.let { notes ->
                FormaCard {
                    Overline(text = "Notes")
                    Text(notes, style = bodyFont(13f), color = colors.textSecondary)
                }
            }
        }
    }
}

private fun endedLabel(session: WorkoutSession): String {
    val start = Formatters.time(session.startedAt)
    val ended = session.endedAt ?: return start
    return "$start – ${Formatters.time(ended)}"
}

private fun exerciseName(id: String, state: FormaUiState): String =
    state.exercises.firstOrNull { it.id == id }?.name ?: com.gymapp.android.domain.ExerciseCatalog.name(id)
