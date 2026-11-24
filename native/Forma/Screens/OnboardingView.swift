import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    @State private var name = ""
    @State private var age = 28
    @State private var experience: Experience = .beginner
    @State private var environment: TrainingEnvironment = .both
    @State private var goals: [Goal] = [.general]
    @State private var days: Set<Int> = [1, 3, 5]
    @State private var minutes = 45
    @State private var equipment: Set<Equipment> = [.bodyweight, .dumbbells, .bench]
    @State private var avoid: [String] = []
    @State private var limitations = ""
    @State private var reminderTime = "18:00"
    @State private var remindersOn = true
    @State private var showAvoidSheet = false
    @State private var didHydrate = false
    @State private var error: String?
    @State private var finishing = false

    private var totalSteps: Int { communityStepAvailable ? 8 : 7 }
    private var communityStepAvailable: Bool {
        model.communityService != nil && model.remoteAccount != nil
    }
    private static let durations = [20, 30, 45, 60, 75]
    private static let reminderTimes = ["07:00", "08:00", "12:00", "17:30", "18:00", "19:00", "20:00"]

    var body: some View {
        Group {
            if let outcome = model.pendingOnboardingOutcome {
                PlanReadyView(outcome: outcome)
            } else {
                flow
            }
        }
        .onAppear { hydrate() }
    }

    // MARK: - Layout

    private var flow: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        Color.clear.frame(height: 0).id("top")
                        stepContent
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.xxxl)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: step)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: step) { _, _ in
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            footer
        }
        .sheet(isPresented: $showAvoidSheet) {
            AvoidExerciseSheet(exercises: model.exercises, selected: $avoid)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.background)
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                if step > 0 {
                    IconButton(systemImage: "chevron.left", label: "Previous step") { back() }
                } else {
                    Wordmark()
                }
                Spacer()
                Text(String(format: "%02d / %02d", step + 1, totalSteps))
                    .font(FormaFont.bodyFont(11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textSecondary)
                    .contentTransition(.numericText())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.surfaceRaised)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(8, geometry.size.width * CGFloat(step + 1) / CGFloat(totalSteps)))
                        .animation(.smooth(duration: 0.35), value: step)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            if let helper {
                Text(helper)
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if let error {
                ErrorBanner(message: error)
            }
            PrimaryButton(
                title: step == totalSteps - 1 ? "Build my plan" : "Continue",
                systemImage: step == totalSteps - 1 ? "sparkles" : "arrow.right",
                isLoading: finishing,
                isDisabled: !canContinue
            ) {
                advance()
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background {
            palette.background
                .opacity(0.97)
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.border).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: aboutStep
        case 1: experienceStep
        case 2: directionStep
        case 3: scheduleStep
        case 4: equipmentStep
        case 5: preferencesStep
        case 6:
            if communityStepAvailable, let service = model.communityService {
                OnboardingCommunityStep(service: service)
            } else {
                reviewStep
            }
        default: reviewStep
        }
    }

    // MARK: - Steps

    private var aboutStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StepIntro(
                eyebrow: "About you",
                title: "Let's make this yours.",
                subtitle: "A few honest answers now saves guesswork later. Nothing here is shared publicly."
            )
            FormaTextField(
                label: "Name",
                placeholder: "What should we call you?",
                text: $name,
                capitalization: .words,
                contentType: .name
            )
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Age")
                    .font(FormaFont.bodyFont(12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                StepperControl(value: age, range: 13...90, suffix: "years") { age = $0 }
            }
            .frame(maxWidth: 240, alignment: .leading)
            OnboardingNote(
                icon: "checkmark.shield",
                text: "Your age helps calibrate sensible training loads. It is not used for body-image scoring or anything public."
            )
        }
    }

    private var experienceStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StepIntro(
                eyebrow: "Experience",
                title: "Where are you starting?",
                subtitle: "Be honest — the plan will meet you there and progress from it."
            )
            VStack(spacing: Spacing.sm) {
                ForEach(Experience.allCases) { option in
                    OnboardingOption(
                        title: option.label,
                        detail: experienceBody(option),
                        icon: experienceIcon(option),
                        selected: experience == option
                    ) {
                        experience = option
                    }
                }
            }
        }
    }

    private var directionStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StepIntro(
                eyebrow: "Direction",
                title: "What are you training for?",
                subtitle: "Pick up to three. You can change this whenever your focus shifts."
            )
            FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                ForEach(Goal.allCases) { goal in
                    FormaChip(label: goal.label, selected: goals.contains(goal)) {
                        toggleGoal(goal)
                    }
                }
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Where will you train?")
                    .font(FormaFont.bodyFont(11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textSecondary)
                ForEach(TrainingEnvironment.allCases) { option in
                    OnboardingOption(
                        title: option.label,
                        detail: environmentBody(option),
                        icon: environmentIcon(option),
                        selected: environment == option
                    ) {
                        environment = option
                    }
                }
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StepIntro(
                eyebrow: "Schedule",
                title: "Build the week around your life.",
                subtitle: "Choose the days you can realistically show up. Up to six training days; recovery stays in the plan."
            )
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Training days")
                    .font(FormaFont.bodyFont(11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textSecondary)
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        dayButton(day)
                    }
                }
                Text("\(days.count) day\(days.count == 1 ? "" : "s") selected · at least one recovery day stays open.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Session length")
                    .font(FormaFont.bodyFont(11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textSecondary)
                FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                    ForEach(Self.durations, id: \.self) { duration in
                        FormaChip(label: "\(duration) min", selected: minutes == duration) {
                            minutes = duration
                        }
                    }
                }
            }
            OnboardingNote(
                icon: "calendar",
                text: "Consistency beats intensity. Two or three focused sessions per week is a strong foundation."
            )
        }
    }

    private var equipmentStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StepIntro(
                eyebrow: "Equipment",
                title: "What do you have access to?",
                subtitle: "Your plan only uses movements you can actually do. Bodyweight is always included."
            )
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
            OnboardingNote(
                icon: "dumbbell",
                text: "Not sure? Choose fewer options. You can add equipment later and regenerate the plan."
            )
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StepIntro(
                eyebrow: "Preferences",
                title: "Anything to work around?",
                subtitle: "Optional. This helps the plan avoid movements you would rather skip."
            )
            VStack(alignment: .leading, spacing: Spacing.sm) {
                FormaTextEditor(
                    label: "Injuries or limitations (optional)",
                    placeholder: "e.g. left knee feels sensitive on deep squats",
                    text: $limitations
                )
                Text("Forma does not diagnose or treat injuries. For persistent pain, see a qualified professional.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
            }
            Button {
                Haptics.light()
                showAvoidSheet = true
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exercises to skip")
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text(avoid.isEmpty ? "None selected" : "\(avoid.count) selected")
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(Spacing.md)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                }
            }
            .buttonStyle(PressableScaleStyle())
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Preferred reminder time")
                    .font(FormaFont.bodyFont(11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textSecondary)
                FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                    ForEach(Self.reminderTimes, id: \.self) { time in
                        FormaChip(label: Formatters.timeOfDay(time), selected: reminderTime == time) {
                            reminderTime = time
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.accentText)
                    .frame(width: 36, height: 36)
                    .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Training reminders")
                        .font(FormaFont.bodyFont(14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("A local reminder on your training days. No spam, no guilt.")
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)
                Toggle("", isOn: $remindersOn)
                    .labelsHidden()
                    .tint(palette.accentText)
            }
            .padding(Spacing.md)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StepIntro(
                eyebrow: "Review",
                title: "Ready to build your base.",
                subtitle: "Your plan will be generated on-device from these answers. You can rebuild it any time."
            )
            FormaCard {
                reviewRow(icon: "sparkles", label: "Name", value: "\(name.trimmingCharacters(in: .whitespacesAndNewlines)), \(age)")
                FormaDivider()
                reviewRow(icon: "figure.strengthtraining.traditional", label: "Experience", value: experience.label)
                FormaDivider()
                reviewRow(icon: "mappin.and.ellipse", label: "Environment", value: environment.label)
                FormaDivider()
                reviewRow(
                    icon: "calendar",
                    label: "Schedule",
                    value: "\(days.sorted().map(Weekday.short).joined(separator: ", ")) · \(minutes) min"
                )
                FormaDivider()
                reviewRow(
                    icon: "dumbbell",
                    label: "Equipment",
                    value: Equipment.allCases.filter { equipment.contains($0) }.map(\.label).joined(separator: ", ")
                )
                FormaDivider()
                reviewRow(
                    icon: "bell",
                    label: "Reminder",
                    value: remindersOn ? "\(Formatters.timeOfDay(reminderTime)) on training days" : "Off"
                )
                if !avoid.isEmpty {
                    FormaDivider()
                    reviewRow(icon: "exclamationmark.triangle", label: "Skipping", value: "\(avoid.count) exercise\(avoid.count == 1 ? "" : "s")")
                }
            }
            NoticeBanner(
                message: "Forma provides general fitness guidance, not medical advice. Stop any activity that causes pain, dizziness, or unusual shortness of breath, and seek appropriate professional help.",
                systemImage: "heart.text.square",
                accent: true
            )
        }
    }

    // MARK: - Pieces

    private func dayButton(_ day: Int) -> some View {
        let selected = days.contains(day)
        return Button {
            Haptics.selection()
            toggleDay(day)
        } label: {
            Text(Weekday.short(day))
                .font(FormaFont.bodyFont(11.5, weight: .semibold))
                .foregroundStyle(selected ? palette.accentInk : palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    selected ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.surface),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(selected ? Color.clear : palette.border, lineWidth: 1)
                }
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(Formatters.weekdayFull(day))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func reviewRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 34, height: 34)
                .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                Text(value.isEmpty ? "—" : value)
                    .font(FormaFont.bodyFont(14, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Logic

    private var canContinue: Bool {
        switch step {
        case 0: return name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case 2: return !goals.isEmpty
        case 3: return !days.isEmpty
        case 4: return equipment.contains(.bodyweight) || !equipment.isEmpty
        default: return true
        }
    }

    private var helper: String? {
        guard !canContinue else { return nil }
        switch step {
        case 0: return "Add your name to continue."
        case 2: return "Choose at least one goal."
        case 3: return "Choose at least one training day."
        case 4: return "Choose at least one equipment option."
        default: return nil
        }
    }

    private func experienceBody(_ option: Experience) -> String {
        switch option {
        case .beginner: "New, or returning after a long break. We keep volume conservative and technique first."
        case .intermediate: "Training consistently for six months or more. Comfortable with the main movement patterns."
        case .advanced: "Years of structured training. You know your body and can manage higher intensity."
        }
    }

    private func experienceIcon(_ option: Experience) -> String {
        switch option {
        case .beginner: "figure.walk"
        case .intermediate: "dumbbell"
        case .advanced: "flame"
        }
    }

    private func environmentBody(_ option: TrainingEnvironment) -> String {
        switch option {
        case .gym: "Full equipment access, including machines and cables."
        case .home: "A mix of bodyweight, dumbbells, bands, or a small setup."
        case .both: "Sometimes at home, sometimes at the gym."
        }
    }

    private func environmentIcon(_ option: TrainingEnvironment) -> String {
        switch option {
        case .gym: "building.2"
        case .home: "house"
        case .both: "square.stack.3d.up"
        }
    }

    private func toggleGoal(_ goal: Goal) {
        if let index = goals.firstIndex(of: goal) {
            guard goals.count > 1 else { return }
            goals.remove(at: index)
        } else if goals.count < 3 {
            goals.append(goal)
        }
    }

    private func toggleDay(_ day: Int) {
        if days.contains(day) {
            guard days.count > 1 else { return }
            days.remove(day)
        } else {
            guard days.count < 6 else { return }
            days.insert(day)
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

    private func advance() {
        guard canContinue, !finishing else { return }
        if step == totalSteps - 1 {
            Task { await finish() }
        } else {
            error = nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { step += 1 }
        }
    }

    private func back() {
        error = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { step = max(0, step - 1) }
    }

    private func hydrate() {
        guard !didHydrate else { return }
        didHydrate = true
        if let existing = model.profile {
            if !existing.name.isEmpty { name = existing.name }
            if let existingAge = existing.age { age = existingAge }
            experience = existing.experience
            environment = existing.environment
            if !existing.goals.isEmpty { goals = existing.goals }
            if let value = existing.limitations { limitations = value }
        }
        if let preferences = model.preferences {
            if !preferences.workoutDays.isEmpty { days = Set(preferences.workoutDays) }
            minutes = preferences.sessionMinutes
            equipment = Set(preferences.equipment).union([.bodyweight])
            avoid = preferences.avoidExercises
            reminderTime = preferences.reminderTime
        }
    }

    @MainActor
    private func finish() async {
        guard let user = model.user else {
            error = "Your local profile could not be prepared. Restart the app and try again."
            return
        }
        guard !finishing else { return }
        finishing = true
        error = nil
        defer { finishing = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLimitations = limitations.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderedGoals = Goal.allCases.filter { goals.contains($0) }
        let orderedEquipment = Equipment.allCases.filter { $0 == .bodyweight || equipment.contains($0) }
        let orderedDays = days.sorted()

        let profile = Profile(
            id: user.id,
            name: trimmedName,
            age: age,
            experience: experience,
            environment: environment,
            goals: orderedGoals,
            limitations: trimmedLimitations.isEmpty ? nil : trimmedLimitations,
            onboardingCompleted: true,
            createdAt: model.profile?.createdAt ?? StoredTimestamp.now()
        )
        let preferences = Preferences(
            userId: user.id,
            workoutDays: orderedDays,
            sessionMinutes: minutes,
            equipment: orderedEquipment,
            avoidExercises: avoid,
            reminderTime: reminderTime,
            units: model.preferences?.units ?? .kg
        )
        var reminders = ReminderSettings.defaults(userId: user.id)
        reminders.enabled = remindersOn
        reminders.workoutTime = reminderTime
        reminders.days = orderedDays

        do {
            _ = try await model.completeOnboarding(profile: profile, preferences: preferences, reminders: reminders)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Optional community step

private struct OnboardingCommunityStep: View {
    var service: any CommunityServicing

    @Environment(\.formaPalette) private var palette
    @State private var query = ""
    @State private var gyms: [GymSummary] = []
    @State private var areas: [CommunityArea] = []
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var selection: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StepIntro(
                eyebrow: "Community (optional)",
                title: "Find people who train nearby.",
                subtitle: "Choose a gym or area to discover other members of the fitness community. Your selection does not reveal your live location or confirm that you are currently at that gym."
            )

            if let selection {
                NoticeBanner(
                    message: "Selected \(selection). You can change or remove this later in Community.",
                    systemImage: "checkmark.circle",
                    accent: true
                )
            }

            FormaTextField(
                label: "Search gyms",
                placeholder: "Gym name or city",
                text: $query,
                capitalization: .words
            )
            .onChange(of: query) { _, value in
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await searchGyms(value)
                }
            }

            if loading {
                LoadingCard(label: "Loading gyms and areas")
            } else {
                if gyms.isEmpty {
                    Text("No verified gyms match yet. You can request one later from Community settings.")
                        .font(FormaFont.bodyFont(13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(gyms.prefix(8)) { gym in
                            gymRow(gym)
                            if gym.id != gyms.prefix(8).last?.id {
                                FormaDivider()
                            }
                        }
                    }
                }

                if !areas.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Or choose an area")
                            .font(FormaFont.bodyFont(11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(palette.textSecondary)
                        FlowLayout(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                            ForEach(areas.prefix(12)) { area in
                                FormaChip(
                                    label: "\(area.area), \(area.city)",
                                    selected: selection == "\(area.area), \(area.city)"
                                ) {
                                    Task { await chooseArea(area) }
                                }
                            }
                        }
                    }
                }
            }

            if let error {
                ErrorBanner(message: error)
            }

            OnboardingNote(
                icon: "location.slash",
                text: "Community is optional. Skip this and choose a gym or area later. Forma does not request location permission for Community."
            )
        }
        .task { await load() }
    }

    private func gymRow(_ gym: GymSummary) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "building.2")
                .font(.system(size: 14))
                .foregroundStyle(palette.accentText)
                .frame(width: 32, height: 32)
                .background(palette.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(gym.name)
                    .font(FormaFont.bodyFont(14, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text([gym.area, gym.city].compactMap { $0 }.joined(separator: ", "))
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            if selection == gym.name {
                TagLabel(text: "Selected", color: palette.success)
            } else {
                Button {
                    Task { await join(gym) }
                } label: {
                    Group {
                        if busy {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("Choose")
                                .font(FormaFont.bodyFont(12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(palette.accentInk)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(palette.accent, in: Capsule())
                }
                .buttonStyle(PressableScaleStyle())
                .disabled(busy)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        loading = true
        do {
            async let bootstrap = service.communityBootstrap()
            async let results = service.communitySearchGyms(query: "", country: "", city: "", area: "", postalCode: "", limit: 30, offset: 0)
            areas = try await bootstrap.areas
            gyms = try await results
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func searchGyms(_ value: String) async {
        do {
            gyms = try await service.communitySearchGyms(query: value, country: "", city: "", area: "", postalCode: "", limit: 30, offset: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func join(_ gym: GymSummary) async {
        busy = true
        error = nil
        do {
            try await service.communityJoinGym(id: gym.id, isPrimary: true, membershipType: "member", visibility: "members")
            selection = gym.name
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func chooseArea(_ area: CommunityArea) async {
        busy = true
        error = nil
        do {
            try await service.communityLeaveGym()
            try await service.communitySetArea(city: area.city, area: area.area)
            selection = "\(area.area), \(area.city)"
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}

// MARK: - Plan ready

struct PlanReadyView: View {
    let outcome: OnboardingOutcome
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var nextDay: WorkoutDay? {
        if let today = PlanGenerator.planForDate(outcome.plan, date: Date()), !today.isRestDay {
            return today
        }
        return PlanGenerator.nextTrainingDay(outcome.plan, from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(palette.accentText)
                    .frame(width: 88, height: 88)
                    .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(palette.accentBorder, lineWidth: 1)
                    }
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, Spacing.xxxl)
                    .padding(.bottom, Spacing.sm)

                VStack(spacing: Spacing.sm) {
                    Overline(text: "Plan ready")
                    Text("Your base is built.")
                        .font(FormaFont.displayFont(32, weight: .bold))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                    Text("\(outcome.plan.name) is saved. Each session has a warm-up, structured sets, rest targets, and a cool-down.")
                        .font(FormaFont.bodyFont(14))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        readyStat(value: "\(outcome.plan.trainingDays.count)", label: "Days / week")
                        Rectangle().fill(palette.border).frame(width: 1, height: 32)
                        readyStat(value: "\(outcome.plan.sessionMinutes)m", label: "Per session")
                        Rectangle().fill(palette.border).frame(width: 1, height: 32)
                        readyStat(value: outcome.plan.goal.shortLabel, label: "Focus")
                    }
                    .padding(Spacing.lg)
                    if let nextDay {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NEXT SESSION")
                                .font(FormaFont.bodyFont(10, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(palette.textTertiary)
                            Text(nextDay.title)
                                .font(FormaFont.displayFont(19, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text("\(nextDay.exercises.count) exercises · \(nextDay.estimatedMinutes) min")
                                .font(FormaFont.bodyFont(12))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.lg)
                        .overlay(alignment: .top) {
                            Rectangle().fill(palette.border).frame(height: 1)
                        }
                    }
                }
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                }

                NoticeBanner(message: outcome.reminderMessage, systemImage: "bell", accent: true)

                Text("Generated on-device from your answers and stored in this device's database. Open Workouts to rebuild it whenever your schedule changes.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Enter Forma", systemImage: "arrow.right") {
                    model.dismissPlanReady()
                }
                .padding(.top, Spacing.sm)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05)) {
                appeared = true
            }
        }
    }

    private func readyStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(FormaFont.displayFont(24, weight: .bold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(FormaFont.bodyFont(10.5))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Builders

private struct StepIntro: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Overline(text: eyebrow)
            Text(title)
                .font(FormaFont.displayFont(30, weight: .bold))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(FormaFont.bodyFont(14))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, Spacing.xs)
    }
}

private struct OnboardingOption: View {
    var title: String
    var detail: String
    var icon: String
    var selected: Bool
    var action: () -> Void
    @Environment(\.formaPalette) private var palette

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? palette.accentInk : palette.accentText)
                    .frame(width: 38, height: 38)
                    .background(
                        selected ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.surfaceRaised),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(FormaFont.bodyFont(15, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(detail)
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(selected ? palette.accentText : palette.textTertiary)
                    .padding(.top, 2)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? palette.accentSoft : palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(selected ? palette.accentBorder : palette.border, lineWidth: 1)
            }
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct OnboardingNote: View {
    var icon: String
    var text: String
    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.accentText)
            Text(text)
                .font(FormaFont.bodyFont(12))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }
}
