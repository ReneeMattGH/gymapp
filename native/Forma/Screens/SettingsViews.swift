import SwiftUI
import UIKit
import UserNotifications

// MARK: - Reminders

struct RemindersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette

    @State private var enabled = false
    @State private var workoutTime = Date()
    @State private var days: Set<Int> = [1, 3, 5]
    @State private var restDayReminders = true
    @State private var hydrationReminders = false
    @State private var weeklyProgressReminder = true
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?
    @State private var didHydrate = false

    private var timeString: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: workoutTime)
        return String(format: "%02d:%02d", parts.hour ?? 18, parts.minute ?? 0)
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var daysValid: Bool { !enabled || !days.isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    PageHeading(
                        eyebrow: "Reminders",
                        title: "Show up on purpose",
                        subtitle: "Local notifications scheduled on this iPhone. Nothing is sent from a server."
                    )
                    .id("top")
                    if let error {
                        ErrorBanner(message: error)
                    }
                    if let notice {
                        NoticeBanner(message: notice, systemImage: "checkmark.seal", accent: true)
                    }
                    permissionCard
                    scheduleCard
                    optionsCard
                    PrimaryButton(
                        title: "Save reminders",
                        systemImage: "bell.badge",
                        isLoading: saving,
                        isDisabled: !daysValid
                    ) {
                        save()
                    }
                    NoticeBanner(
                        message: "iOS may defer or silence notifications depending on Focus modes and system settings. Forma reports what the system confirmed, not what it hopes was scheduled.",
                        systemImage: "info.circle"
                    )
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxxl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(FormaBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await hydrate() }
            .onChange(of: notice) { _, next in
                guard next != nil else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    private var permissionCard: some View {
        FormaCard(style: .raised) {
            HStack {
                Overline(text: "Permission")
                Spacer()
                TagLabel(
                    text: statusText,
                    color: status == .authorized || status == .provisional ? palette.accentText : palette.warning
                )
            }
            Text(permissionMessage)
                .font(FormaFont.bodyFont(12.5))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if status == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("Open iOS Settings")
                        .font(FormaFont.bodyFont(13, weight: .semibold))
                        .foregroundStyle(palette.accentInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
                Text("\(pendingCount) Forma reminder\(pendingCount == 1 ? "" : "s") currently scheduled")
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var permissionMessage: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            "Notifications are allowed. Saving replaces every existing Forma reminder with the schedule below."
        case .denied:
            "Notifications are denied for Forma. Nothing will be scheduled until you allow them in iOS Settings."
        default:
            "Saving with reminders on will ask iOS for permission. If you decline, nothing is scheduled and we will say so."
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Schedule")
            VStack(alignment: .leading, spacing: Spacing.md) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Training reminders")
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text("A weekly nudge on your training days")
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .tint(palette.accentText)

                if enabled {
                    FormaDivider()
                    DatePicker("Time", selection: $workoutTime, displayedComponents: .hourAndMinute)
                        .font(FormaFont.bodyFont(13))
                        .tint(palette.accentText)
                    FormaDivider()
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Days")
                            .font(FormaFont.bodyFont(11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(palette.textSecondary)
                        HStack(spacing: 6) {
                            ForEach(1...7, id: \.self) { day in
                                dayButton(day)
                            }
                        }
                        if days.isEmpty {
                            Text("Choose at least one day.")
                                .font(FormaFont.bodyFont(11))
                                .foregroundStyle(palette.warning)
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let selected = days.contains(day)
        return Button {
            Haptics.selection()
            if selected {
                days.remove(day)
            } else {
                days.insert(day)
            }
        } label: {
            Text(Weekday.short(day))
                .font(FormaFont.bodyFont(11, weight: .semibold))
                .foregroundStyle(selected ? palette.accentInk : palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    selected ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.surfaceRaised),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                )
        }
        .buttonStyle(PressableScaleStyle())
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Also remind me")
            VStack(spacing: 0) {
                optionToggle(
                    title: "Recovery days",
                    detail: "10:00 on days without a session",
                    isOn: $restDayReminders
                )
                FormaDivider()
                optionToggle(
                    title: "Hydration",
                    detail: "11:00 and 16:00, daily",
                    isOn: $hydrationReminders
                )
                FormaDivider()
                optionToggle(
                    title: "Weekly review",
                    detail: "Sunday at 18:00",
                    isOn: $weeklyProgressReminder
                )
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
        }
    }

    private func optionToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FormaFont.bodyFont(13.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .tint(palette.accentText)
        .padding(.vertical, Spacing.sm)
    }

    private func hydrate() async {
        guard !didHydrate else { return }
        didHydrate = true
        let settings = model.reminders ?? ReminderSettings.defaults(userId: model.user?.id ?? "local")
        enabled = settings.enabled
        workoutTime = date(for: settings.workoutTime)
        days = Set(settings.days.isEmpty ? [1, 3, 5] : settings.days)
        restDayReminders = settings.restDayReminders
        hydrationReminders = settings.hydrationReminders
        weeklyProgressReminder = settings.weeklyProgressReminder
        status = await NotificationService.shared.authorizationStatus()
        pendingCount = await NotificationService.shared.pendingAppOwnedCount()
    }

    private func date(for value: String) -> Date {
        let parts = Formatters.hourMinute(value)
        return Calendar.current.date(bySettingHour: parts.hour, minute: parts.minute, second: 0, of: Date()) ?? Date()
    }

    private func save() {
        guard daysValid else {
            error = "Choose at least one day for training reminders."
            return
        }
        error = nil
        notice = nil
        saving = true
        var settings = model.reminders ?? ReminderSettings.defaults(userId: model.user?.id ?? "local")
        settings.enabled = enabled
        settings.workoutTime = timeString
        settings.days = days.sorted()
        settings.restDayReminders = restDayReminders
        settings.hydrationReminders = hydrationReminders
        settings.weeklyProgressReminder = weeklyProgressReminder

        Task { @MainActor in
            do {
                let result = try await model.saveReminders(settings)
                notice = result.message
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
            }
            status = await NotificationService.shared.authorizationStatus()
            pendingCount = await NotificationService.shared.pendingAppOwnedCount()
            saving = false
        }
    }
}

// MARK: - Health

struct HealthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var confirmDisconnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PageHeading(
                    eyebrow: "Apple Health",
                    title: "Optional context",
                    subtitle: "Read-only access to workouts, energy, steps, and heart rate. Forma never writes to Health."
                )
                if !model.healthAvailable {
                    NoticeBanner(
                        message: "HealthKit is not available on this device. Forma works fully without it.",
                        systemImage: "exclamationmark.triangle",
                        accent: false
                    )
                }
                if let error = model.healthError {
                    ErrorBanner(message: error)
                }
                connectionCard
                if model.healthOptIn {
                    summarySection
                    workoutSection
                }
                NoticeBanner(
                    message: "HealthKit does not disclose whether read permission was granted. Data appears only when the system returns it, and it is used for display in this app rather than uploaded.",
                    systemImage: "lock.shield"
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(FormaBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if model.healthOptIn && !model.healthFetched {
                await model.loadHealth()
            }
        }
        .confirmationDialog(
            "Disconnect Apple Health?",
            isPresented: $confirmDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                model.disableHealth()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Forma stops reading Health data and clears what it last showed. Your Health records are untouched, and iOS permissions can be changed in Settings.")
        }
    }

    private var connectionCard: some View {
        FormaCard(style: .raised) {
            HStack {
                Overline(text: "Connection")
                Spacer()
                TagLabel(
                    text: model.healthOptIn ? "Opted in" : "Not connected",
                    color: model.healthOptIn ? palette.accentText : palette.textTertiary
                )
            }
            Text(model.healthOptIn
                 ? "Forma will request read access once and then fetch the last seven days when you refresh."
                 : "Connect Apple Health to see recent workouts, active energy, steps, and heart rate alongside Forma.")
                .font(FormaFont.bodyFont(12.5))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.healthOptIn {
                HStack(spacing: Spacing.sm) {
                    PrimaryButton(title: "Refresh data", systemImage: "arrow.clockwise", isLoading: model.healthBusy) {
                        Task { await model.loadHealth() }
                    }
                    SecondaryButton(title: "Disconnect") {
                        confirmDisconnect = true
                    }
                }
            } else {
                PrimaryButton(title: "Connect Apple Health", systemImage: "heart.text.square", isLoading: model.healthBusy, isDisabled: !model.healthAvailable) {
                    Task { await model.requestHealthAccess() }
                }
            }
            if let fetchedAt = model.healthSummary?.fetchedAt {
                Text("Last fetched \(Formatters.time(fetchedAt)) on \(Formatters.shortDate(fetchedAt))")
                    .font(FormaFont.bodyFont(10))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
                Text("Apple Health data stays on this device. It is shown only here and is never uploaded to Forma's servers or shared with the community.")
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Last seven days")
            if model.healthBusy && model.healthSummary == nil {
                LoadingCard(label: "Reading Apple Health")
            } else if let summary = model.healthSummary {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    healthTile(
                        value: "\(summary.workouts.count)",
                        label: "Workouts",
                        detail: "Source: Apple Health"
                    )
                    healthTile(
                        value: summary.activeEnergyKcal.map { "\(Int($0.rounded())) kcal" } ?? "—",
                        label: "Active energy",
                        detail: summary.activeEnergyKcal == nil ? "No data returned" : "Source: Apple Health"
                    )
                    healthTile(
                        value: summary.steps.map { $0.formatted() } ?? "—",
                        label: "Steps",
                        detail: summary.steps == nil ? "No data returned" : "Source: Apple Health"
                    )
                    healthTile(
                        value: summary.latestHeartRate.map { "\(Int($0.bpm.rounded())) bpm" } ?? "—",
                        label: "Latest heart rate",
                        detail: summary.latestHeartRate.map { "Source: Apple Health · \(Formatters.time($0.date))" } ?? "No data returned"
                    )
                }
                if summary.workouts.isEmpty && summary.steps == nil && summary.activeEnergyKcal == nil && summary.latestHeartRate == nil {
                    NoticeBanner(
                        message: "Apple Health returned no data. That can mean no records in the period or that read access is not enabled.",
                        systemImage: "questionmark.circle"
                    )
                }
            } else {
                Text("Refresh to load data from Apple Health.")
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func healthTile(value: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(FormaFont.displayFont(21, weight: .bold))
                .foregroundStyle(palette.text)
            Text(label.uppercased())
                .font(FormaFont.bodyFont(9.5, weight: .semibold))
                .tracking(1)
                .foregroundStyle(palette.textTertiary)
            Text(detail)
                .font(FormaFont.bodyFont(9.5))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Health workouts")
            if let workouts = model.healthSummary?.workouts, !workouts.isEmpty {
                VStack(spacing: Spacing.sm) {
                    ForEach(workouts) { workout in
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.accentText)
                                .frame(width: 36, height: 36)
                                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.activity)
                                    .font(FormaFont.bodyFont(13.5, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text("\(Formatters.shortDate(workout.start)) · \(Formatters.minutesLabel(Int(workout.duration)))"
                                     + (workout.energyKcal.map { " · \(Int($0.rounded())) kcal" } ?? ""))
                                    .font(FormaFont.bodyFont(10.5))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                            TagLabel(text: "Health", color: palette.textTertiary)
                        }
                        .padding(Spacing.md)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.border, lineWidth: 1)
                        }
                    }
                }
            } else {
                Text("No Health workouts in the last seven days.")
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}
