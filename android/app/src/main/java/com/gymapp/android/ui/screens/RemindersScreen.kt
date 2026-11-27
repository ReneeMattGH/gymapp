package com.gymapp.android.ui.screens

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.core.Formatters
import com.gymapp.android.domain.ReminderSettings
import com.gymapp.android.domain.Weekday
import com.gymapp.android.notifications.ReminderScheduler
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaDivider
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.FormaToggle
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PageHeading
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.SectionHeader
import com.gymapp.android.ui.components.SubScreenHeader
import com.gymapp.android.ui.components.TagLabel
import com.gymapp.android.ui.components.formaClickable
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RemindersScreen(
    model: FormaViewModel,
    state: FormaUiState,
    onBack: () -> Unit,
) {
    val colors = FormaTheme.colors
    val context = LocalContext.current
    val scheduler = remember { ReminderScheduler(context) }

    var enabled by remember { mutableStateOf(false) }
    var hour by remember { mutableIntStateOf(18) }
    var minute by remember { mutableIntStateOf(0) }
    var days by remember { mutableStateOf(setOf(1, 3, 5)) }
    var restDayReminders by remember { mutableStateOf(true) }
    var hydrationReminders by remember { mutableStateOf(false) }
    var weeklyProgressReminder by remember { mutableStateOf(true) }
    var didHydrate by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var showTimePicker by remember { mutableStateOf(false) }
    var permissionGranted by remember { mutableStateOf(scheduler.canNotify()) }
    var pendingCount by remember { mutableIntStateOf(scheduler.pendingCount()) }
    var pendingSave by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        permissionGranted = scheduler.canNotify()
        if (pendingSave) {
            pendingSave = false
            commit(
                model = model,
                scheduler = scheduler,
                settings = buildSettings(state.userId, enabled, hour, minute, days, restDayReminders, hydrationReminders, weeklyProgressReminder),
                onSaving = { saving = it },
                onError = { error = it },
                onSuccess = { message ->
                    notice = message
                    pendingCount = scheduler.pendingCount()
                },
            )
        }
    }

    LaunchedEffect(Unit) {
        if (didHydrate) return@LaunchedEffect
        didHydrate = true
        val settings = state.reminders ?: ReminderSettings.defaults(state.userId)
        enabled = settings.enabled
        val parts = Formatters.hourMinute(settings.workoutTime)
        hour = parts.first
        minute = parts.second
        days = settings.days.ifEmpty { listOf(1, 3, 5) }.toSet()
        restDayReminders = settings.restDayReminders
        hydrationReminders = settings.hydrationReminders
        weeklyProgressReminder = settings.weeklyProgressReminder
        permissionGranted = scheduler.canNotify()
        pendingCount = scheduler.pendingCount()
    }

    fun save() {
        error = null
        notice = null
        if (enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !scheduler.canNotify()) {
            pendingSave = true
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        commit(
            model = model,
            scheduler = scheduler,
            settings = buildSettings(state.userId, enabled, hour, minute, days, restDayReminders, hydrationReminders, weeklyProgressReminder),
            onSaving = { saving = it },
            onError = { error = it },
            onSuccess = { message ->
                notice = message
                pendingCount = scheduler.pendingCount()
            },
        )
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
                eyebrow = "Reminders",
                title = "Show up on purpose",
                subtitle = "Local notifications scheduled on this Android device. Nothing is sent from a server.",
            )
            error?.let { ErrorBanner(message = it) }
            notice?.let { NoticeBanner(message = it, icon = "checkmark.seal", accent = true) }

            // Permission
            FormaCard(style = com.gymapp.android.ui.components.CardStyle.RAISED) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Overline(text = "Permission")
                    Spacer(Modifier.weight(1f))
                    TagLabel(
                        text = if (permissionGranted) "Allowed" else "Not granted",
                        color = if (permissionGranted) colors.accentText else colors.warning,
                    )
                }
                Text(
                    if (permissionGranted) {
                        "Notifications are allowed. Saving replaces every existing Forma reminder with the schedule below."
                    } else {
                        "Notifications are not allowed for Forma. Nothing is scheduled until you allow notifications in Android settings."
                    },
                    style = bodyFont(12.5f),
                    color = colors.textSecondary,
                )
                if (!permissionGranted) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(42.dp)
                            .clip(RoundedCornerShape(Radius.md))
                            .background(colors.accent)
                            .formaClickable { openNotificationSettings(context) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "Open Android settings",
                            style = bodyFont(13f, FontWeight.SemiBold),
                            color = colors.accentInk,
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                    FormaIcon("checkmark.circle", size = 12.dp, tint = colors.textTertiary)
                    Text(
                        "$pendingCount Forma reminder${if (pendingCount == 1) "" else "s"} currently scheduled",
                        style = bodyFont(10.5f),
                        color = colors.textTertiary,
                    )
                }
            }

            // Schedule
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(title = "Schedule")
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(Radius.lg))
                        .background(colors.surface)
                        .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
                        .padding(Spacing.lg),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md),
                ) {
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("Training reminders", style = bodyFont(14f, FontWeight.SemiBold), color = colors.text)
                            Text(
                                "A weekly nudge on your training days",
                                style = bodyFont(11f),
                                color = colors.textTertiary,
                            )
                        }
                        FormaToggle(checked = enabled, onCheckedChange = { enabled = it })
                    }

                    if (enabled) {
                        FormaDivider()
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .formaClickable { showTimePicker = true },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("Time", style = bodyFont(13f), color = colors.textSecondary)
                            Spacer(Modifier.weight(1f))
                            Text(
                                String.format("%02d:%02d", hour, minute),
                                style = bodyFont(15f, FontWeight.SemiBold),
                                color = colors.text,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(Radius.sm))
                                    .background(colors.input)
                                    .padding(horizontal = 12.dp, vertical = 6.dp),
                            )
                        }
                        FormaDivider()
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            Text(
                                "Days",
                                style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.2.sp),
                                color = colors.textSecondary,
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                (1..7).forEach { day ->
                                    val selected = days.contains(day)
                                    Box(
                                        Modifier
                                            .weight(1f)
                                            .height(42.dp)
                                            .clip(RoundedCornerShape(Radius.sm))
                                            .background(if (selected) colors.accent else colors.surfaceRaised)
                                            .formaClickable {
                                                days = if (selected) days - day else days + day
                                            },
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            Weekday.short(day),
                                            style = bodyFont(11f, FontWeight.SemiBold),
                                            color = if (selected) colors.accentInk else colors.textSecondary,
                                        )
                                    }
                                }
                            }
                            if (days.isEmpty()) {
                                Text(
                                    "Choose at least one day.",
                                    style = bodyFont(11f),
                                    color = colors.warning,
                                )
                            }
                        }
                    }
                }
            }

            // Also remind me
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(title = "Also remind me")
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(Radius.lg))
                        .background(colors.surface)
                        .border(1.dp, colors.border, RoundedCornerShape(Radius.lg))
                        .padding(horizontal = Spacing.lg)
                        .padding(vertical = Spacing.xs),
                ) {
                    OptionToggle(
                        title = "Recovery days",
                        detail = "10:00 on days without a session",
                        checked = restDayReminders,
                        onCheckedChange = { restDayReminders = it },
                    )
                    FormaDivider()
                    OptionToggle(
                        title = "Hydration",
                        detail = "11:00 and 16:00, daily",
                        checked = hydrationReminders,
                        onCheckedChange = { hydrationReminders = it },
                    )
                    FormaDivider()
                    OptionToggle(
                        title = "Weekly review",
                        detail = "Sunday at 18:00",
                        checked = weeklyProgressReminder,
                        onCheckedChange = { weeklyProgressReminder = it },
                    )
                }
            }

            PrimaryButton(
                title = "Save reminders",
                icon = "bell.badge",
                isLoading = saving,
                isDisabled = enabled && days.isEmpty(),
                onClick = { save() },
            )

            NoticeBanner(
                message = "Android may delay or silence reminders because of Do Not Disturb, battery optimisation, or notification settings. Forma reports what the system confirmed, not what it hopes was scheduled.",
                icon = "info.circle",
            )
        }
    }

    if (showTimePicker) {
        val pickerState = rememberTimePickerState(initialHour = hour, initialMinute = minute, is24Hour = true)
        AlertDialog(
            onDismissRequest = { showTimePicker = false },
            containerColor = colors.surfaceRaised,
            title = { Text("Training time", style = bodyFont(16f, FontWeight.SemiBold), color = colors.text) },
            text = { TimePicker(state = pickerState) },
            confirmButton = {
                TextButton(onClick = {
                    hour = pickerState.hour
                    minute = pickerState.minute
                    showTimePicker = false
                }) {
                    Text("Set", style = bodyFont(14f, FontWeight.Medium), color = colors.accentText)
                }
            },
            dismissButton = {
                TextButton(onClick = { showTimePicker = false }) {
                    Text("Cancel", style = bodyFont(14f), color = colors.textSecondary)
                }
            },
        )
    }
}

@Composable
private fun OptionToggle(
    title: String,
    detail: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = bodyFont(13.5f, FontWeight.SemiBold), color = colors.text)
            Text(detail, style = bodyFont(10.5f), color = colors.textTertiary)
        }
        FormaToggle(checked = checked, onCheckedChange = onCheckedChange)
    }
}

private fun buildSettings(
    userId: String,
    enabled: Boolean,
    hour: Int,
    minute: Int,
    days: Set<Int>,
    restDayReminders: Boolean,
    hydrationReminders: Boolean,
    weeklyProgressReminder: Boolean,
): ReminderSettings = ReminderSettings(
    userId = userId,
    enabled = enabled,
    workoutTime = String.format(java.util.Locale.US, "%02d:%02d", hour, minute),
    days = days.sorted(),
    restDayReminders = restDayReminders,
    hydrationReminders = hydrationReminders,
    weeklyProgressReminder = weeklyProgressReminder,
)

private fun commit(
    model: FormaViewModel,
    scheduler: ReminderScheduler,
    settings: ReminderSettings,
    onSaving: (Boolean) -> Unit,
    onError: (String) -> Unit,
    onSuccess: (String) -> Unit,
) {
    if (settings.enabled && settings.days.isEmpty()) {
        onError("Choose at least one day for training reminders.")
        return
    }
    onSaving(true)
    model.saveReminders(settings) { message ->
        onSaving(false)
        if (message != null) {
            onError(message)
        } else if (!settings.enabled) {
            onSuccess("Reminders are off. Nothing is scheduled.")
        } else {
            val count = model.state.value.reminders?.scheduledIds?.size ?: scheduler.pendingCount()
            onSuccess("$count reminder${if (count == 1) "" else "s"} scheduled on this device.")
        }
    }
}

private fun openNotificationSettings(context: android.content.Context) {
    val notification = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        .setData(Uri.fromParts("package", context.packageName, null))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(notification) }
        .onFailure { runCatching { context.startActivity(fallback) } }
}
