package com.gymapp.android.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.gymapp.android.domain.Exercise
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.FormaTextField
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.SheetHeading
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont

/** Sheet body shared by onboarding and profile editing. Mirrors `AvoidExerciseSheet.swift`. */
@Composable
fun AvoidExerciseSheetContent(
    exercises: List<Exercise>,
    selected: List<String>,
    onToggle: (String) -> Unit,
    onClose: () -> Unit,
) {
    val colors = FormaTheme.colors
    var query by remember { mutableStateOf("") }

    val filtered = remember(query, exercises) {
        val text = query.trim().lowercase()
        if (text.isEmpty()) {
            exercises
        } else {
            exercises.filter { exercise ->
                exercise.name.lowercase().contains(text) ||
                    exercise.primaryMuscles.any { muscle ->
                        muscle.searchTerms.any { it.lowercase().contains(text) }
                    }
            }
        }
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        SheetHeading(
            title = "Exercises to skip",
            subtitle = "Your plan will not include these. You can change this at any time.",
            onClose = onClose,
        )
        FormaTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = "Search exercises",
            capitalization = KeyboardCapitalization.None,
        )
        if (filtered.isEmpty()) {
            Text(
                "No exercises match that search.",
                style = bodyFont(12f),
                color = colors.textTertiary,
                modifier = Modifier.padding(vertical = Spacing.xxl),
            )
        } else {
            LazyColumn(Modifier.heightIn(max = 380.dp)) {
                items(filtered, key = { it.id }) { exercise ->
                    val active = selected.contains(exercise.id)
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .formaClickable { onToggle(exercise.id) }
                            .padding(vertical = 11.dp),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier
                                .size(22.dp)
                                .clip(RoundedCornerShape(7.dp))
                                .background(if (active) colors.accent else Color.Transparent)
                                .border(
                                    width = if (active) 0.dp else 1.4.dp,
                                    color = if (active) Color.Transparent else colors.borderStrong,
                                    shape = RoundedCornerShape(7.dp),
                                ),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (active) FormaIcon("checkmark", size = 12.dp, tint = colors.accentInk)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(exercise.name, style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
                            Text(
                                exercise.primaryMuscles.joinToString(" · ") { it.label },
                                style = bodyFont(11f),
                                color = colors.textTertiary,
                            )
                        }
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
                }
            }
        }
        PrimaryButton(
            title = if (selected.isEmpty()) "Done" else "Done · ${selected.size} selected",
            onClick = onClose,
        )
    }
}
