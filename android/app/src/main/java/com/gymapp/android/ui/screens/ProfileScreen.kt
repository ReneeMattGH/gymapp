package com.gymapp.android.ui.screens

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.BuildConfig
import com.gymapp.android.core.Formatters
import com.gymapp.android.core.ProfilePhotoStore
import com.gymapp.android.domain.Equipment
import com.gymapp.android.domain.Experience
import com.gymapp.android.domain.Goal
import com.gymapp.android.domain.Profile
import com.gymapp.android.domain.Preferences
import com.gymapp.android.domain.ThemeMode
import com.gymapp.android.domain.TrainingEnvironment
import com.gymapp.android.domain.UnitSystem
import com.gymapp.android.domain.Weekday
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaConfirmDialog
import com.gymapp.android.ui.components.FormaChip
import com.gymapp.android.ui.components.FormaDivider
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.FormaTextField
import com.gymapp.android.ui.components.FormaTextEditor
import com.gymapp.android.ui.components.KeyValueRow
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PageHeading
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.ProfileAvatar
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ProfileScreen(
    model: FormaViewModel,
    state: FormaUiState,
    onOpenAccount: () -> Unit,
    onOpenPreferences: () -> Unit,
    onOpenReminders: () -> Unit,
) {
    val colors = FormaTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var pendingPhoto by remember { mutableStateOf<Uri?>(null) }
    var photoBusy by remember { mutableStateOf(false) }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) pendingPhoto = uri
    }

    LaunchedEffect(pendingPhoto) {
        val uri = pendingPhoto ?: return@LaunchedEffect
        pendingPhoto = null
        val existing = state.profile ?: return@LaunchedEffect
        photoBusy = true
        error = null
        try {
            val name = withContext(Dispatchers.IO) { ProfilePhotoStore.save(context, uri, existing.photoPath) }
            model.saveProfile(existing.copy(photoPath = name)) { message ->
                if (message != null) error = message
            }
        } catch (exception: Exception) {
            error = exception.message ?: "That image could not be read."
        }
        photoBusy = false
    }

    Box(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .padding(horizontal = Spacing.xl)
                .padding(top = Spacing.md, bottom = Spacing.xxxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.xl),
        ) {
            profileHeader(
                profile = state.profile,
                photoBusy = photoBusy,
                onPickPhoto = {
                    photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                },
            )
            error?.let { ErrorBanner(message = it) }

            profilesSection(model, state)

            localProfileCard(state)

            VStackSection(title = "Forma account") {
                SettingsRow(
                    icon = "person.crop.circle.badge.checkmark",
                    title = accountTitle(state),
                    detail = accountDetail(state),
                    onClick = onOpenAccount,
                )
            }

            VStackSection(title = "Training") {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    SettingsRow(
                        icon = "slider.horizontal.3",
                        title = "Training profile",
                        detail = "Schedule, equipment, goals, units",
                        onClick = onOpenPreferences,
                    )
                    SettingsRow(
                        icon = "bell",
                        title = "Reminders",
                        detail = remindersDetail(state),
                        onClick = onOpenReminders,
                    )
                }
            }

            appearanceCard(model, state)

            VStackSection(title = "App") {
                SettingsRow(
                    icon = "gearshape",
                    title = "App settings",
                    detail = "Notifications and app permissions",
                    onClick = { openNotificationSettings(context) },
                )
            }

            NoticeBanner(
                message = "Forma gives general fitness guidance, not medical advice. It cannot diagnose injuries or replace a clinician.",
                icon = "heart.text.square",
            )

            dangerZone(
                busy = busy,
                onDelete = { confirmDelete = true },
            )

            Text(
                "Forma ${BuildConfig.VERSION_NAME} · Local database",
                style = bodyFont(10f),
                color = colors.textTertiary,
                modifier = Modifier.fillMaxWidth(),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }

    if (confirmDelete) {
        FormaConfirmDialog(
            title = "Delete this profile?",
            message = "This erases this profile's plans, workout history, check-ins and reminders from this device. It cannot be undone.",
            confirmLabel = "Delete profile",
            destructive = true,
            onConfirm = {
                confirmDelete = false
                busy = true
                error = null
                scope.launch {
                    model.deleteActiveProfile { message -> if (message != null) error = message }
                    busy = false
                }
            },
            onDismiss = { confirmDelete = false },
        )
    }
}

// MARK: - Header

@Composable
private fun ProfilePhoto(name: String, photoPath: String?, size: Dp, showCameraBadge: Boolean = false) {
    val context = LocalContext.current
    val bitmap by produceState<Bitmap?>(initialValue = null, photoPath) {
        value = withContext(Dispatchers.IO) { ProfilePhotoStore.load(context, photoPath) }
    }
    ProfileAvatar(name = name, size = size, photo = bitmap, showCameraBadge = showCameraBadge)
}

@Composable
private fun profileHeader(profile: Profile?, photoBusy: Boolean, onPickPhoto: () -> Unit) {
    val colors = FormaTheme.colors
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.formaClickable(enabled = !photoBusy, onClick = onPickPhoto),
        ) {
            ProfilePhoto(
                name = profile?.name.orEmpty(),
                photoPath = profile?.photoPath,
                size = 72.dp,
                showCameraBadge = true,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                profile?.name?.takeIf { it.isNotBlank() } ?: "Your profile",
                style = displayFont(26f, FontWeight.Bold),
                color = colors.text,
            )
            Text("Stored on this device", style = bodyFont(12f), color = colors.textTertiary)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (profile != null) {
                    TagLabel(text = profile.experience.label, color = colors.textSecondary)
                    TagLabel(text = profile.environment.label, color = colors.textTertiary)
                }
            }
        }
        Spacer(Modifier.weight(1f))
    }
}

// MARK: - Profiles

@Composable
private fun profilesSection(model: FormaViewModel, state: FormaUiState) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(title = "Profiles")
        state.localProfiles.forEach { profile ->
            val active = profile.id == state.userId
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radius.md))
                    .background(colors.surface)
                    .border(1.dp, if (active) colors.accentBorder else colors.border, RoundedCornerShape(Radius.md))
                    .formaClickable(enabled = !active) { model.switchProfile(profile.id) }
                    .padding(Spacing.md),
                horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ProfilePhoto(
                    name = profile.name,
                    photoPath = profile.photoPath,
                    size = 40.dp,
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        profile.name.takeIf { it.isNotBlank() } ?: "Unnamed profile",
                        style = bodyFont(14f, FontWeight.SemiBold),
                        color = colors.text,
                    )
                    Text(
                        "${profile.experience.label} · ${profile.environment.label}",
                        style = bodyFont(11f),
                        color = colors.textTertiary,
                    )
                }
                Spacer(Modifier.weight(1f))
                if (active) {
                    FormaIcon("checkmark.circle.fill", size = 16.dp, tint = colors.accentText)
                }
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radius.md))
                .background(colors.surface)
                .border(1.dp, colors.border, RoundedCornerShape(Radius.md))
                .formaClickable { model.beginNewProfile() }
                .padding(Spacing.md),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(colors.accentSoft),
                contentAlignment = Alignment.Center,
            ) {
                FormaIcon("plus", size = 15.dp, tint = colors.accentText)
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Add profile", style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
                Text(
                    "Start fresh for another person on this device",
                    style = bodyFont(11f),
                    color = colors.textTertiary,
                )
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun localProfileCard(state: FormaUiState) {
    val colors = FormaTheme.colors
    FormaCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Overline(text = "Local profile")
            Spacer(Modifier.weight(1f))
            TagLabel(text = "On device", color = colors.accentText)
        }
        KeyValueRow(label = "Age", value = state.profile?.age?.toString() ?: "—")
        FormaDivider()
        KeyValueRow(label = "Plan", value = state.plan?.name ?: "None yet")
        FormaDivider()
        KeyValueRow(
            label = "Goals",
            value = state.profile?.goals?.map { it.shortLabel }?.joinToString(" · ") ?: "—",
        )
        val limitations = state.profile?.limitations
        if (!limitations.isNullOrBlank()) {
            FormaDivider()
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Limitations", style = bodyFont(11f), color = colors.textTertiary)
                Text(
                    limitations,
                    style = bodyFont(12.5f),
                    color = colors.textSecondary,
                )
            }
        }
    }
}

// MARK: - Account rows

private fun accountTitle(state: FormaUiState): String =
    state.account?.email ?: "Connect account"

private fun accountDetail(state: FormaUiState): String {
    if (!state.accountConfigured) return "Backend not connected in this build"
    val account = state.account ?: return "Sign in for Community and sync"
    return if (account.emailVerified) "Signed in · verified" else "Signed in · email unconfirmed"
}

private fun remindersDetail(state: FormaUiState): String {
    val reminders = state.reminders
    if (reminders == null || !reminders.enabled) return "Off"
    return "${Formatters.timeOfDay(reminders.workoutTime)} · ${reminders.days.map { Weekday.short(it) }.joinToString(", ")}"
}

// MARK: - Appearance

@Composable
private fun appearanceCard(model: FormaViewModel, state: FormaUiState) {
    val colors = FormaTheme.colors
    FormaCard {
        Overline(text = "Appearance")
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            ThemeMode.entries.forEach { mode ->
                val selected = state.themeMode == mode
                Column(
                    Modifier
                        .weight(1f)
                        .height(58.dp)
                        .clip(RoundedCornerShape(Radius.md))
                        .background(if (selected) colors.accent else colors.surfaceRaised)
                        .formaClickable { model.setThemeMode(mode) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    FormaIcon(
                        themeIcon(mode),
                        size = 15.dp,
                        tint = if (selected) colors.accentInk else colors.textSecondary,
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        mode.label,
                        style = bodyFont(11f, FontWeight.Medium),
                        color = if (selected) colors.accentInk else colors.textSecondary,
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Units", style = bodyFont(12f), color = colors.textSecondary)
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                UnitSystem.entries.forEach { unit ->
                    val selected = state.units == unit
                    Text(
                        unit.abbreviation.uppercase(),
                        style = bodyFont(11f, FontWeight.SemiBold),
                        color = if (selected) colors.accentInk else colors.textSecondary,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(if (selected) colors.accent else colors.surfaceRaised)
                            .formaClickable(enabled = !selected) {
                                model.setUnits(unit)
                            }
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                }
            }
        }
    }
}

private fun themeIcon(mode: ThemeMode): String = when (mode) {
    ThemeMode.DARK -> "moon.stars"
    ThemeMode.LIGHT -> "sun.max"
    ThemeMode.SYSTEM -> "circle.lefthalf.filled"
}

// MARK: - Danger zone

@Composable
private fun dangerZone(busy: Boolean, onDelete: () -> Unit) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(title = "Danger zone")
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radius.md))
                .background(colors.dangerSoft)
                .border(1.dp, colors.danger.copy(alpha = 0.25f), RoundedCornerShape(Radius.md))
                .formaClickable(enabled = !busy, onClick = onDelete)
                .padding(Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Delete this profile", style = bodyFont(14f, FontWeight.SemiBold), color = colors.danger)
                Text(
                    "Erase plans, sessions, check-ins and reminders",
                    style = bodyFont(11f),
                    color = colors.textTertiary,
                )
            }
            Spacer(Modifier.weight(1f))
            if (busy) {
                androidx.compose.material3.CircularProgressIndicator(
                    Modifier.size(16.dp),
                    color = colors.danger,
                    strokeWidth = 2.dp,
                )
            } else {
                FormaIcon("trash", size = 13.dp, tint = colors.danger)
            }
        }
    }
}

@Composable
private fun VStackSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(title = title)
        content()
    }
}

@Composable
private fun SettingsRow(icon: String, title: String, detail: String, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(Radius.md))
            .formaClickable(onClick = onClick)
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(38.dp)
                .clip(RoundedCornerShape(11.dp))
                .background(colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon(icon, size = 15.dp, tint = colors.accentText)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
            Text(
                detail,
                style = bodyFont(11f),
                color = colors.textTertiary,
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            )
        }
        FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
    }
}

private fun openNotificationSettings(context: Context) {
    val notification = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        .setData(Uri.fromParts("package", context.packageName, null))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(notification) }
        .onFailure { runCatching { context.startActivity(fallback) } }
}

// MARK: - Training profile

@Composable
fun PreferencesScreen(
    model: FormaViewModel,
    state: FormaUiState,
    onBack: () -> Unit,
    onOpenBuilder: () -> Unit,
) {
    val colors = FormaTheme.colors

    var name by remember { mutableStateOf("") }
    var age by remember { mutableStateOf(28) }
    var experience by remember { mutableStateOf(Experience.BEGINNER) }
    var environment by remember { mutableStateOf(TrainingEnvironment.BOTH) }
    var goals by remember { mutableStateOf(listOf(Goal.GENERAL)) }
    var limitations by remember { mutableStateOf("") }
    var days by remember { mutableStateOf(setOf(1, 3, 5)) }
    var minutes by remember { mutableStateOf(45) }
    var equipment by remember { mutableStateOf(setOf(Equipment.BODYWEIGHT)) }
    var units by remember { mutableStateOf(UnitSystem.KG) }
    var avoid by remember { mutableStateOf(listOf<String>()) }
    var showAvoid by remember { mutableStateOf(false) }
    var didHydrate by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        if (didHydrate) return@LaunchedEffect
        didHydrate = true
        state.profile?.let { profile ->
            name = profile.name
            age = profile.age ?: 28
            experience = profile.experience
            environment = profile.environment
            goals = profile.goals.ifEmpty { listOf(Goal.GENERAL) }
            limitations = profile.limitations.orEmpty()
        }
        state.preferences?.let { preferences ->
            days = preferences.workoutDays.ifEmpty { listOf(1, 3, 5) }.toSet()
            minutes = preferences.sessionMinutes
            equipment = preferences.equipment.toSet() + Equipment.BODYWEIGHT
            units = preferences.units
            avoid = preferences.avoidExercises
        }
    }

    fun toggleGoal(goal: Goal) {
        goals = when {
            goals.contains(goal) -> if (goals.size <= 1) goals else goals - goal
            goals.size < 3 -> goals + goal
            else -> goals
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

    fun save() {
        val existing = state.profile
        if (existing == null) {
            error = "Your profile could not be loaded. Restart the app and try again."
            return
        }
        val trimmed = name.trim()
        if (trimmed.length < 2) {
            error = "Add your name to continue."
            return
        }
        error = null
        notice = null
        saving = true
        val nextProfile = existing.copy(
            name = trimmed,
            age = age,
            experience = experience,
            environment = environment,
            goals = Goal.entries.filter { goals.contains(it) },
            limitations = limitations.trim().takeIf { it.isNotEmpty() },
        )
        val nextPreferences = (state.preferences ?: Preferences(userId = state.userId)).copy(
            workoutDays = days.sorted(),
            sessionMinutes = minutes,
            equipment = Equipment.entries.filter { it == Equipment.BODYWEIGHT || equipment.contains(it) },
            avoidExercises = avoid,
            units = units,
        )
        model.saveTrainingProfile(nextProfile, nextPreferences) { message ->
            saving = false
            if (message != null) {
                error = message
            } else {
                notice = "Saved. Rebuild your plan if the schedule or equipment changed."
            }
        }
    }

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
                eyebrow = "Training",
                title = "Training profile",
                subtitle = "These answers shape your plan, equipment choices, and schedule.",
            )
            error?.let { ErrorBanner(message = it) }
            if (notice != null) {
                NoticeBanner(message = notice!!, icon = "checkmark.seal", accent = true)
                SecondaryButton(title = "Rebuild my plan now", icon = "sparkles", onClick = onOpenBuilder)
            }

            PreferenceSection(title = "About you") {
                FormaTextField(
                    value = name,
                    onValueChange = { name = it },
                    placeholder = "Your name",
                    label = "Name",
                    capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Words,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Age", style = bodyFont(12f, FontWeight.Medium), color = colors.textSecondary)
                    Spacer(Modifier.weight(1f))
                    StepperControl(value = age, range = 13..90, suffix = "years") { age = it }
                }
                FieldLabel("Experience")
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Experience.entries.forEach { option ->
                        FormaChip(
                            label = option.label,
                            selected = experience == option,
                            onClick = { experience = option },
                        )
                    }
                }
                FieldLabel("Environment")
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    TrainingEnvironment.entries.forEach { option ->
                        FormaChip(
                            label = option.label,
                            selected = environment == option,
                            onClick = { environment = option },
                        )
                    }
                }
                FieldLabel("Goals · up to three")
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Goal.entries.forEach { goal ->
                        FormaChip(
                            label = goal.shortLabel,
                            selected = goals.contains(goal),
                            onClick = { toggleGoal(goal) },
                        )
                    }
                }
                FormaTextEditor(
                    value = limitations,
                    onValueChange = { limitations = it },
                    label = "Injuries or limitations (optional)",
                    placeholder = "e.g. right shoulder is sensitive overhead",
                )
            }

            PreferenceSection(title = "Schedule") {
                FieldLabel("Training days · up to six")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    (1..7).forEach { day ->
                        DayButton(
                            day = day,
                            selected = days.contains(day),
                            modifier = Modifier.weight(1f),
                        ) { toggleDay(day) }
                    }
                }
                FieldLabel("Session length")
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    listOf(20, 30, 45, 60, 75).forEach { duration ->
                        FormaChip(
                            label = "$duration min",
                            selected = minutes == duration,
                            onClick = { minutes = duration },
                        )
                    }
                }
            }

            PreferenceSection(title = "Equipment") {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Equipment.entries.forEach { item ->
                        FormaChip(
                            label = item.label,
                            selected = item == Equipment.BODYWEIGHT || equipment.contains(item),
                            disabled = item == Equipment.BODYWEIGHT,
                            onClick = { toggleEquipment(item) },
                        )
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Units", style = bodyFont(12f, FontWeight.Medium), color = colors.textSecondary)
                    Spacer(Modifier.weight(1f))
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        UnitSystem.entries.forEach { unit ->
                            Box(Modifier.width(54.dp)) {
                                FormaChip(
                                    label = unit.abbreviation.uppercase(),
                                    selected = units == unit,
                                    onClick = { units = unit },
                                )
                            }
                        }
                    }
                }
            }

            PreferenceSection(title = "Avoid") {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .formaClickable { showAvoid = true }
                        .padding(vertical = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        Modifier
                            .size(34.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(colors.surfaceRaised),
                        contentAlignment = Alignment.Center,
                    ) {
                        FormaIcon("exclamationmark.triangle", size = 14.dp, tint = colors.textSecondary)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("Exercises to skip", style = bodyFont(13.5f, FontWeight.SemiBold), color = colors.text)
                        Text(
                            if (avoid.isEmpty()) "None selected" else "${avoid.size} selected",
                            style = bodyFont(10.5f),
                            color = colors.textTertiary,
                        )
                    }
                    Spacer(Modifier.weight(1f))
                    FormaIcon("chevron.right", size = 11.dp, tint = colors.textTertiary)
                }
            }

            PrimaryButton(
                title = "Save changes",
                icon = "checkmark",
                isLoading = saving,
                isDisabled = name.trim().length < 2,
                onClick = { save() },
            )
        }
    }

    if (showAvoid) {
        AvoidExerciseSheet(
            exercises = state.exercises,
            selected = avoid,
            onToggle = { id ->
                avoid = if (avoid.contains(id)) avoid - id else avoid + id
            },
            onDismiss = { showAvoid = false },
        )
    }
}

@Composable
private fun PreferenceSection(title: String, content: @Composable () -> Unit) {
    val colors = FormaTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(title = title)
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radius.lg))
                .background(colors.surface)
                .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
                .padding(Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            content()
        }
    }
}

@Composable
private fun FieldLabel(text: String) {
    Text(
        text,
        style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.2.sp),
        color = FormaTheme.colors.textSecondary,
    )
}

@Composable
private fun DayButton(day: Int, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    Box(
        modifier
            .height(42.dp)
            .clip(RoundedCornerShape(Radius.sm))
            .background(if (selected) colors.accent else colors.surfaceRaised)
            .formaClickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            Weekday.short(day),
            style = bodyFont(11f, FontWeight.SemiBold),
            color = if (selected) colors.accentInk else colors.textSecondary,
        )
    }
}

// MARK: - Avoid sheet

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AvoidExerciseSheet(
    exercises: List<com.gymapp.android.domain.Exercise>,
    selected: List<String>,
    onToggle: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = FormaTheme.colors
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
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
                title = "Exercises to skip",
                subtitle = "Your plan will not include these. You can change this at any time.",
                onClose = onDismiss,
            )
            FormaTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = "Search exercises",
                capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.None,
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
                                    .background(if (active) colors.accent else androidx.compose.ui.graphics.Color.Transparent)
                                    .border(
                                        width = if (active) 0.dp else 1.4.dp,
                                        color = if (active) androidx.compose.ui.graphics.Color.Transparent else colors.borderStrong,
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
                onClick = onDismiss,
            )
        }
    }
}
