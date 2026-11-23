import SwiftUI
import UIKit
import PhotosUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var busy = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    profileHeader
                    if let error {
                        ErrorBanner(message: error)
                    }
                    profilesSection
                    accountCard
                    accountSection
                    trainingSection
                    appearanceCard
                    appSection
                    NoticeBanner(
                        message: "Forma gives general fitness guidance, not medical advice. It cannot diagnose injuries or replace a clinician.",
                        systemImage: "heart.text.square"
                    )
                    dangerZone
                    Text("Forma \(version) · Local database")
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(FormaBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog(
            "Delete this profile?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete profile", role: .destructive) {
                Task {
                    busy = true
                    error = nil
                    let ok = await model.deleteActiveProfile()
                    if !ok, let profileError = model.profileError {
                        error = profileError
                    }
                    busy = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases this profile's plans, workout history, check-ins and reminders from this device. It cannot be undone.")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await updatePhoto(from: item) }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: Spacing.lg) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ProfileAvatar(profile: model.profile, size: 72, showsCameraBadge: true)
            }
            .buttonStyle(.plain)
            .disabled(photoBusy)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.profile?.name ?? "Your profile")
                    .font(FormaFont.displayFont(26, weight: .bold))
                    .foregroundStyle(palette.text)
                Text("Stored on this device")
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 6) {
                    if let profile = model.profile {
                        TagLabel(text: profile.experience.label, color: palette.textSecondary)
                        TagLabel(text: profile.environment.label, color: palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Profiles")
            ForEach(model.localProfiles, id: \.id) { profile in
                Button {
                    guard profile.id != model.user?.id else { return }
                    Task { await model.switchProfile(to: profile.id) }
                } label: {
                    HStack(spacing: Spacing.md) {
                        ProfileAvatar(profile: profile, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name.isEmpty ? "Unnamed profile" : profile.name)
                                .font(FormaFont.bodyFont(14, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text(profile.experience.label + " · " + profile.environment.label)
                                .font(FormaFont.bodyFont(11))
                                .foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        if profile.id == model.user?.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(palette.accentText)
                        }
                    }
                    .padding(Spacing.md)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(profile.id == model.user?.id ? palette.accent.opacity(0.5) : palette.border, lineWidth: 1)
                    }
                }
                .buttonStyle(PressableScaleStyle())
            }
            Button {
                Task { await model.beginNewProfile() }
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.accentText)
                        .frame(width: 40, height: 40)
                        .background(palette.accentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add profile")
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text("Start fresh for another person on this device")
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                .padding(Spacing.md)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                }
            }
            .buttonStyle(PressableScaleStyle())
        }
    }

    private func updatePhoto(from item: PhotosPickerItem) async {
        photoBusy = true
        error = nil
        defer {
            photoBusy = false
            photoItem = nil
        }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw),
                  let jpeg = image.jpegData(compressionQuality: 0.85),
                  var next = model.profile else {
                error = "That image could not be read."
                return
            }
            let name = try ProfilePhotoStore.save(jpeg, replacing: next.photoPath)
            next.photoPath = name
            try await model.saveProfile(next)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var accountCard: some View {
        FormaCard {
            HStack {
                Overline(text: "Local profile")
                Spacer()
                TagLabel(text: "On device", color: palette.accentText)
            }
            KeyValueRow(label: "Age", value: model.profile?.age.map(String.init) ?? "—")
            FormaDivider()
            KeyValueRow(label: "Plan", value: model.plan?.name ?? "None yet")
            FormaDivider()
            KeyValueRow(label: "Goals", value: model.profile?.goals.map(\.shortLabel).joined(separator: " · ") ?? "—")
            if let limitations = model.profile?.limitations, !limitations.isEmpty {
                FormaDivider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Limitations")
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textTertiary)
                    Text(limitations)
                        .font(FormaFont.bodyFont(12.5))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Forma account")
            NavigationLink {
                AccountView()
            } label: {
                settingsRow(icon: "person.crop.circle.badge.checkmark", title: accountTitle, detail: accountDetail)
            }
            .buttonStyle(PressableScaleStyle())
        }
    }

    private var accountTitle: String {
        model.remoteAccount?.email ?? "Connect account"
    }

    private var accountDetail: String {
        guard model.isAccountAvailable else { return "Backend not connected in this build" }
        guard let account = model.remoteAccount else { return "Sign in for Community and sync" }
        return account.emailVerified ? "Signed in · verified" : "Signed in · email unconfirmed"
    }

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Training")
            NavigationLink {
                PreferencesView()
            } label: {
                settingsRow(icon: "slider.horizontal.3", title: "Training profile", detail: "Schedule, equipment, goals, units")
            }
            .buttonStyle(PressableScaleStyle())
            NavigationLink {
                RemindersView()
            } label: {
                settingsRow(icon: "bell", title: "Reminders", detail: remindersDetail)
            }
            .buttonStyle(PressableScaleStyle())
            NavigationLink {
                HealthView()
            } label: {
                settingsRow(icon: "heart.text.square", title: "Apple Health", detail: model.healthOptIn ? "Opted in · read-only" : "Not connected")
            }
            .buttonStyle(PressableScaleStyle())
        }
    }

    private var remindersDetail: String {
        guard let reminders = model.reminders, reminders.enabled else { return "Off" }
        return "\(Formatters.timeOfDay(reminders.workoutTime)) · \(reminders.days.map(Weekday.short).joined(separator: ", "))"
    }

    private var appearanceCard: some View {
        FormaCard {
            Overline(text: "Appearance")
            HStack(spacing: Spacing.sm) {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.2)) { model.themeMode = mode }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 15, weight: .medium))
                            Text(mode.label)
                                .font(FormaFont.bodyFont(11, weight: .medium))
                        }
                        .foregroundStyle(model.themeMode == mode ? palette.accentInk : palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            model.themeMode == mode ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.surfaceRaised),
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        )
                    }
                    .buttonStyle(PressableScaleStyle())
                }
            }
            HStack {
                Text("Units")
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(UnitSystem.allCases) { unit in
                        Button {
                            guard model.units != unit else { return }
                            Task {
                                do { try await model.saveUnits(unit) } catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            Text(unit.abbreviation.uppercased())
                                .font(FormaFont.bodyFont(11, weight: .semibold))
                                .foregroundStyle(model.units == unit ? palette.accentInk : palette.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    model.units == unit ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.surfaceRaised),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "App")
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    settingsRow(icon: "gearshape", title: "iOS Settings", detail: "Notifications, Health, camera permissions")
                }
                .buttonStyle(PressableScaleStyle())
            }
        }
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Danger zone")
            Button {
                confirmDelete = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete this profile")
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.danger)
                        Text("Erase plans, sessions, check-ins and reminders")
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    if busy {
                        ProgressView().tint(palette.danger)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.danger)
                    }
                }
                .padding(Spacing.md)
                .background(palette.dangerSoft, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.danger.opacity(0.25), lineWidth: 1)
                }
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(busy)
        }
    }

    private func settingsRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.accentText)
                .frame(width: 38, height: 38)
                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FormaFont.bodyFont(14, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Training profile

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette

    @State private var name = ""
    @State private var age = 28
    @State private var experience: Experience = .beginner
    @State private var environment: TrainingEnvironment = .both
    @State private var goals: [Goal] = [.general]
    @State private var limitations = ""
    @State private var days: Set<Int> = [1, 3, 5]
    @State private var minutes = 45
    @State private var equipment: Set<Equipment> = [.bodyweight]
    @State private var units: UnitSystem = .kg
    @State private var avoid: [String] = []
    @State private var showAvoid = false
    @State private var showBuilder = false
    @State private var didHydrate = false
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PageHeading(
                    eyebrow: "Training",
                    title: "Training profile",
                    subtitle: "These answers shape your plan, equipment choices, and schedule."
                )
                if let error {
                    ErrorBanner(message: error)
                }
                if let notice {
                    NoticeBanner(message: notice, systemImage: "checkmark.seal", accent: true)
                    SecondaryButton(title: "Rebuild my plan now", systemImage: "sparkles") {
                        showBuilder = true
                    }
                }

                section("About you") {
                    FormaTextField(label: "Name", placeholder: "Your name", text: $name, capitalization: .words, contentType: .name)
                    HStack {
                        Text("Age")
                            .font(FormaFont.bodyFont(12, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        StepperControl(value: age, range: 13...90, suffix: "years") { age = $0 }
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        label("Experience")
                        FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                            ForEach(Experience.allCases) { option in
                                FormaChip(label: option.label, selected: experience == option) { experience = option }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        label("Environment")
                        FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                            ForEach(TrainingEnvironment.allCases) { option in
                                FormaChip(label: option.label, selected: environment == option) { environment = option }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        label("Goals · up to three")
                        FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                            ForEach(Goal.allCases) { goal in
                                FormaChip(label: goal.shortLabel, selected: goals.contains(goal)) { toggleGoal(goal) }
                            }
                        }
                    }
                    FormaTextEditor(
                        label: "Injuries or limitations (optional)",
                        placeholder: "e.g. right shoulder is sensitive overhead",
                        text: $limitations
                    )
                }

                section("Schedule") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        label("Training days · up to six")
                        HStack(spacing: 6) {
                            ForEach(1...7, id: \.self) { day in
                                dayButton(day)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        label("Session length")
                        FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                            ForEach([20, 30, 45, 60, 75], id: \.self) { duration in
                                FormaChip(label: "\(duration) min", selected: minutes == duration) { minutes = duration }
                            }
                        }
                    }
                }

                section("Equipment") {
                    FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                        ForEach(Equipment.allCases) { item in
                            FormaChip(
                                label: item.label,
                                selected: item == .bodyweight || equipment.contains(item),
                                disabled: item == .bodyweight
                            ) {
                                toggleEquipment(item)
                            }
                        }
                    }
                    HStack {
                        Text("Units")
                            .font(FormaFont.bodyFont(12, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        ForEach(UnitSystem.allCases) { unit in
                            FormaChip(label: unit.abbreviation.uppercased(), selected: units == unit) { units = unit }
                                .frame(width: 54)
                        }
                    }
                }

                section("Avoid") {
                    Button {
                        showAvoid = true
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Exercises to skip")
                                    .font(FormaFont.bodyFont(13.5, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text(avoid.isEmpty ? "None selected" : "\(avoid.count) selected")
                                    .font(FormaFont.bodyFont(10.5))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                PrimaryButton(title: "Save changes", systemImage: "checkmark", isLoading: saving, isDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2) {
                    save()
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(FormaBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAvoid) {
            AvoidExerciseSheet(exercises: model.exercises, selected: $avoid)
                .presentationDetents([.large])
                .presentationBackground(palette.background)
        }
        .sheet(isPresented: $showBuilder) {
            PlanBuilderView()
                .presentationDetents([.large])
                .presentationBackground(palette.background)
        }
        .task { hydrate() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: Spacing.md) {
                content()
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(FormaFont.bodyFont(11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(palette.textSecondary)
    }

    private func dayButton(_ day: Int) -> some View {
        let selected = days.contains(day)
        return Button {
            Haptics.selection()
            if selected {
                guard days.count > 1 else { return }
                days.remove(day)
            } else {
                guard days.count < 6 else { return }
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

    private func toggleGoal(_ goal: Goal) {
        if let index = goals.firstIndex(of: goal) {
            guard goals.count > 1 else { return }
            goals.remove(at: index)
        } else if goals.count < 3 {
            goals.append(goal)
        }
    }

    private func toggleEquipment(_ item: Equipment) {
        guard item != .bodyweight else { return }
        if equipment.contains(item) {
            equipment.remove(item)
        } else {
            equipment.insert(item)
        }
    }

    private func hydrate() {
        guard !didHydrate else { return }
        didHydrate = true
        if let profile = model.profile {
            name = profile.name
            age = profile.age ?? 28
            experience = profile.experience
            environment = profile.environment
            goals = profile.goals.isEmpty ? [.general] : profile.goals
            limitations = profile.limitations ?? ""
        }
        if let preferences = model.preferences {
            days = Set(preferences.workoutDays.isEmpty ? [1, 3, 5] : preferences.workoutDays)
            minutes = preferences.sessionMinutes
            equipment = Set(preferences.equipment).union([.bodyweight])
            units = preferences.units
            avoid = preferences.avoidExercises
        }
    }

    private func save() {
        guard let user = model.user, let existing = model.profile else {
            error = "Your profile could not be loaded. Restart the app and try again."
            return
        }
        error = nil
        notice = nil
        saving = true
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLimitations = limitations.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderedGoals = Goal.allCases.filter { goals.contains($0) }
        let orderedEquipment = Equipment.allCases.filter { $0 == .bodyweight || equipment.contains($0) }
        let profile = Profile(
            id: user.id,
            name: trimmed,
            age: age,
            experience: experience,
            environment: environment,
            goals: orderedGoals,
            limitations: trimmedLimitations.isEmpty ? nil : trimmedLimitations,
            onboardingCompleted: true,
            createdAt: existing.createdAt
        )
        let preferences = Preferences(
            userId: user.id,
            workoutDays: days.sorted(),
            sessionMinutes: minutes,
            equipment: orderedEquipment,
            avoidExercises: avoid,
            reminderTime: model.preferences?.reminderTime ?? "18:00",
            units: units
        )
        Task { @MainActor in
            do {
                try await model.saveProfile(profile)
                try await model.savePreferences(preferences)
                Haptics.success()
                notice = "Saved. Rebuild your plan if the schedule or equipment changed."
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}

// MARK: - Avatar

struct ProfileAvatar: View {
    var profile: Profile?
    var size: CGFloat
    var showsCameraBadge = false

    @Environment(\.formaPalette) private var palette

    private var image: UIImage? {
        guard let name = profile?.photoPath, let url = ProfilePhotoStore.url(for: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var initial: String {
        let name = profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.first.map { String($0).uppercased() } ?? "F"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(initial)
                        .font(FormaFont.displayFont(size * 0.4, weight: .bold))
                        .foregroundStyle(palette.accentInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(palette.accent)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if showsCameraBadge {
                Image(systemName: "camera.fill")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(palette.accentInk)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .background(palette.accent, in: Circle())
                    .overlay {
                        Circle().strokeBorder(palette.background, lineWidth: 2)
                    }
            }
        }
        .accessibilityLabel(profile?.name.isEmpty == false ? "\(profile!.name) profile picture" : "Profile picture")
    }
}
