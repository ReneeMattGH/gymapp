package com.gymapp.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.domain.Exercise
import com.gymapp.android.domain.ExerciseCategory
import com.gymapp.android.domain.ExerciseFilters
import com.gymapp.android.domain.ExerciseService
import com.gymapp.android.domain.MuscleGroup
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.ExerciseGlyph
import com.gymapp.android.ui.components.FormaChip
import com.gymapp.android.ui.components.FormaEmptyState
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.FormaTextField
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.PageHeading
import com.gymapp.android.ui.components.SecondaryButton
import com.gymapp.android.ui.components.SectionHeader
import com.gymapp.android.ui.components.SubScreenHeader
import com.gymapp.android.ui.components.TagLabel
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont

@Composable
fun LibraryScreen(
    model: FormaViewModel,
    state: FormaUiState,
    onOpenExercise: (String) -> Unit,
) {
    val colors = FormaTheme.colors
    var query by remember { mutableStateOf("") }
    var selectedCategory by remember { mutableStateOf<ExerciseCategory?>(null) }
    var selectedMuscle by remember { mutableStateOf<MuscleGroup?>(null) }
    var onlyFavorites by remember { mutableStateOf(false) }
    var visibleCount by remember { mutableIntStateOf(30) }

    val filters = ExerciseFilters(
        query = query,
        category = selectedCategory,
        muscle = selectedMuscle,
        onlyFavorites = onlyFavorites,
        favoriteIDs = state.favoriteExercises,
    )
    val page = remember(filters, state.exercises, visibleCount) {
        ExerciseService.search(state.exercises, filters, limit = visibleCount)
    }
    val hasFilters = query.isNotEmpty() || onlyFavorites || selectedCategory != null || selectedMuscle != null
    val recent = state.recentExercises.mapNotNull { id -> state.exercises.firstOrNull { it.id == id } }

    LaunchedEffect(filters, visibleCount) { }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(horizontal = Spacing.xl)
            .padding(top = Spacing.sm, bottom = Spacing.xxxl),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg),
    ) {
        PageHeading(
            eyebrow = "Library",
            title = "Exercises",
            subtitle = "${state.exercises.size} verified movements with instructions, cues, and common mistakes.",
        )

        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
            FormaTextField(
                value = query,
                onValueChange = {
                    query = it
                    visibleCount = 30
                },
                placeholder = "Search exercises",
                capitalization = KeyboardCapitalization.None,
                modifier = Modifier.weight(1f),
            )
            MuscleFilterButton(selected = selectedMuscle, onSelect = {
                selectedMuscle = it
                visibleCount = 30
            })
        }

        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            FormaChip(
                label = "All",
                selected = !onlyFavorites && selectedCategory == null,
                onClick = {
                    onlyFavorites = false
                    selectedCategory = null
                    visibleCount = 30
                },
            )
            ExerciseCategory.entries.forEach { category ->
                FormaChip(
                    label = category.label,
                    selected = selectedCategory == category,
                    onClick = {
                        selectedCategory = if (selectedCategory == category) null else category
                        visibleCount = 30
                    },
                )
            }
            FormaChip(
                label = "Favourites",
                selected = onlyFavorites,
                onClick = {
                    onlyFavorites = !onlyFavorites
                    visibleCount = 30
                },
            )
        }

        if (!hasFilters && recent.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                SectionHeader(title = "Recently viewed")
                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    recent.forEach { exercise ->
                        Column(
                            Modifier
                                .width(128.dp)
                                .clip(RoundedCornerShape(Radius.lg))
                                .background(colors.surface)
                                .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
                                .formaClickable { onOpenExercise(exercise.id) }
                                .padding(Spacing.md),
                            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                        ) {
                            ExerciseGlyph(exercise = exercise, size = 36.dp)
                            Text(
                                exercise.name,
                                style = bodyFont(12f, FontWeight.SemiBold),
                                color = colors.text,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                exercise.primaryMuscles.take(1).joinToString { it.label },
                                style = bodyFont(10f),
                                color = colors.textTertiary,
                            )
                        }
                    }
                }
            }
        }

        if (page.items.isEmpty()) {
            val favouritesOnlyActive = onlyFavorites && query.isEmpty() && selectedCategory == null && selectedMuscle == null
            FormaEmptyState(
                icon = "magnifyingglass",
                title = if (favouritesOnlyActive) "No favourites yet" else "No matches",
                message = if (favouritesOnlyActive) {
                    "Tap the star on any exercise to keep it close."
                } else {
                    "Try a different search or clear the filters."
                },
            )
            if (hasFilters) {
                SecondaryButton(
                    title = "Clear filters",
                    icon = "xmark",
                    onClick = {
                        query = ""
                        onlyFavorites = false
                        selectedCategory = null
                        selectedMuscle = null
                        visibleCount = 30
                    },
                )
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                page.items.forEach { exercise ->
                    LibraryRow(
                        exercise = exercise,
                        favorite = state.favoriteExercises.contains(exercise.id),
                        onOpen = { onOpenExercise(exercise.id) },
                        onToggleFavorite = { model.toggleFavorite(exercise.id) },
                    )
                }
            }
            if (page.hasMore) {
                SecondaryButton(
                    title = "Show more (${page.total - page.items.size} remaining)",
                    icon = "chevron.down",
                    onClick = { visibleCount += 30 },
                )
            }
        }
    }
}

@Composable
private fun MuscleFilterButton(selected: MuscleGroup?, onSelect: (MuscleGroup?) -> Unit) {
    val colors = FormaTheme.colors
    var expanded by remember { mutableStateOf(false) }
    Box {
        Column(
            Modifier
                .size(width = 64.dp, height = 48.dp)
                .clip(RoundedCornerShape(Radius.sm))
                .background(colors.surface)
                .border(
                    1.dp,
                    if (selected == null) colors.border else colors.accentBorder,
                    RoundedCornerShape(Radius.sm),
                )
                .formaClickable { expanded = true },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            FormaIcon(
                if (selected == null) "line.3.horizontal.decrease" else "line.3.horizontal.decrease.circle.fill",
                size = 15.dp,
                tint = if (selected == null) colors.textSecondary else colors.accentText,
            )
            Text(
                selected?.label ?: "Muscle",
                style = bodyFont(8.5f, FontWeight.Medium),
                color = if (selected == null) colors.textSecondary else colors.accentText,
                maxLines = 1,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            containerColor = colors.surfaceRaised,
        ) {
            DropdownMenuItem(
                text = { Text("All muscles", style = bodyFont(13f), color = colors.text) },
                onClick = {
                    expanded = false
                    onSelect(null)
                },
            )
            MuscleGroup.entries.forEach { group ->
                DropdownMenuItem(
                    text = { Text(group.label, style = bodyFont(13f), color = colors.text) },
                    onClick = {
                        expanded = false
                        onSelect(group)
                    },
                )
            }
        }
    }
}

@Composable
private fun LibraryRow(
    exercise: Exercise,
    favorite: Boolean,
    onOpen: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Row(
            Modifier
                .weight(1f)
                .formaClickable(onClick = onOpen),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            ExerciseGlyph(exercise = exercise, size = 44.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(exercise.name, style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
                Text(
                    exercise.primaryMuscles.joinToString(" · ") { it.label },
                    style = bodyFont(11f),
                    color = colors.textTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        exercise.category.label,
                        style = bodyFont(9.5f, FontWeight.SemiBold).copy(letterSpacing = 0.5.sp),
                        color = colors.accentText,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(colors.accentSoft)
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                    Text(exercise.difficulty.label, style = bodyFont(9.5f, FontWeight.Medium), color = colors.textTertiary)
                }
            }
            FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
        }
        Box(
            Modifier
                .size(36.dp)
                .formaClickable(onClick = onToggleFavorite),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon(
                if (favorite) "star.fill" else "star",
                size = 14.dp,
                tint = if (favorite) colors.accentText else colors.textTertiary,
            )
        }
    }
}

// MARK: - Detail

@Composable
fun ExerciseDetailScreen(
    model: FormaViewModel,
    state: FormaUiState,
    exerciseId: String,
    onBack: () -> Unit,
    onOpenExercise: (String) -> Unit,
) {
    val colors = FormaTheme.colors
    val exercise = state.exercises.firstOrNull { it.id == exerciseId }

    LaunchedEffect(exerciseId) {
        if (exercise != null) model.recordExerciseView(exercise.id)
    }

    Column(Modifier.fillMaxSize()) {
        SubScreenHeader(
            onBack = onBack,
            trailing = {
                if (exercise != null) {
                    val favorite = state.favoriteExercises.contains(exercise.id)
                    Box(
                        Modifier
                            .size(36.dp)
                            .formaClickable { model.toggleFavorite(exercise.id) },
                        contentAlignment = Alignment.Center,
                    ) {
                        FormaIcon(
                            if (favorite) "star.fill" else "star",
                            size = 18.dp,
                            tint = if (favorite) colors.accentText else colors.textSecondary,
                        )
                    }
                }
            },
        )
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.sm, bottom = Spacing.xxxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.xl),
        ) {
            if (exercise == null) {
                FormaEmptyState(
                    icon = "questionmark.circle",
                    title = "Exercise unavailable",
                    message = "This movement is not in the current library. Refresh and try again.",
                )
                return@Column
            }

            Column(verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
                    ExerciseGlyph(exercise = exercise, size = 72.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        Text(
                            exercise.category.label.uppercase(),
                            style = bodyFont(10f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
                            color = colors.accentText,
                        )
                        Text(exercise.name, style = displayFont(28f, FontWeight.Bold), color = colors.text)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            TagLabel(text = exercise.difficulty.label, color = colors.textSecondary)
                            if (exercise.isUnilateral) {
                                TagLabel(text = "One side", color = colors.textTertiary)
                            }
                        }
                    }
                }
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    exercise.primaryMuscles.forEach { muscle -> MuscleChip(muscle.label, primary = true) }
                    exercise.secondaryMuscles.forEach { muscle -> MuscleChip(muscle.label, primary = false) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    FormaIcon("dumbbell", size = 12.dp, tint = colors.textTertiary)
                    Text(
                        if (exercise.equipment.isEmpty()) "No equipment listed"
                        else exercise.equipment.joinToString(" · ") { it.label },
                        style = bodyFont(11.5f),
                        color = colors.textSecondary,
                    )
                }
                exercise.source?.let { source ->
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        FormaIcon("checkmark.seal", size = 11.dp, tint = colors.textTertiary)
                        Text(source, style = bodyFont(10.5f), color = colors.textTertiary)
                    }
                }
            }

            if (exercise.instructions.isNotEmpty()) {
                NumberedCard(title = "How to perform", icon = "list.number", items = exercise.instructions)
            }
            if (exercise.cues.isNotEmpty()) {
                BulletListCard(title = "Coaching cues", icon = "target", items = exercise.cues, tint = colors.accentText)
            }
            if (exercise.mistakes.isNotEmpty()) {
                BulletListCard(
                    title = "Common mistakes",
                    icon = "exclamationmark.triangle",
                    items = exercise.mistakes,
                    tint = colors.warning,
                )
            }

            val alternatives = exercise.alternatives.mapNotNull { id ->
                state.exercises.firstOrNull { it.id == id }
            }
            if (alternatives.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    SectionHeader(title = "Alternatives")
                    alternatives.forEach { option ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(Radius.md))
                                .background(colors.surface)
                                .border(1.dp, colors.border, RoundedCornerShape(Radius.md))
                                .formaClickable { onOpenExercise(option.id) }
                                .padding(Spacing.md),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                        ) {
                            ExerciseGlyph(exercise = option, size = 38.dp)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(option.name, style = bodyFont(13.5f, FontWeight.SemiBold), color = colors.text)
                                Text(
                                    option.equipment.joinToString(" · ") { it.label },
                                    style = bodyFont(10.5f),
                                    color = colors.textTertiary,
                                )
                            }
                            FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
                        }
                    }
                }
            }

            NoticeBanner(
                message = "General guidance only. Stop if a movement causes pain, dizziness, or unusual shortness of breath. Persistent issues deserve a qualified professional.",
                icon = "heart.text.square",
            )
        }
    }
}

@Composable
private fun MuscleChip(label: String, primary: Boolean) {
    val colors = FormaTheme.colors
    Text(
        label,
        style = bodyFont(10.5f, FontWeight.Medium),
        color = if (primary) colors.text else colors.textTertiary,
        modifier = Modifier
            .clip(CircleShape)
            .background(if (primary) colors.surfaceRaised else colors.surface)
            .border(1.dp, if (primary) Color.Transparent else colors.border, CircleShape)
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}

@Composable
private fun NumberedCard(title: String, icon: String, items: List<String>) {
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
        CardTitle(title = title, icon = icon)
        items.forEachIndexed { index, item ->
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
                Box(
                    Modifier
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(colors.accentSoft),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("${index + 1}", style = displayFont(11f, FontWeight.SemiBold), color = colors.accentText)
                }
                Text(item, style = bodyFont(13f), color = colors.textSecondary)
            }
        }
    }
}

@Composable
private fun BulletListCard(title: String, icon: String, items: List<String>, tint: Color) {
    val colors = FormaTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        CardTitle(title = title, icon = icon)
        items.forEach { item ->
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Box(
                    Modifier
                        .padding(top = 6.dp)
                        .size(4.dp)
                        .clip(CircleShape)
                        .background(tint),
                )
                Text(item, style = bodyFont(13f), color = colors.textSecondary)
            }
        }
    }
}

@Composable
private fun CardTitle(title: String, icon: String) {
    val colors = FormaTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        FormaIcon(icon, size = 12.dp, tint = colors.textSecondary)
        Text(
            title.uppercase(),
            style = bodyFont(10.5f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
            color = colors.textSecondary,
        )
    }
}
