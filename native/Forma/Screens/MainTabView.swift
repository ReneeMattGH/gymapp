import SwiftUI

enum AppTab: Hashable {
    case home, workouts, coach, progress, profile
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView(selection: $selection)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            WorkoutsView()
                .tabItem { Label("Workouts", systemImage: "dumbbell") }
                .tag(AppTab.workouts)

            CoachView()
                .tabItem { Label("Coach", systemImage: "sparkles") }
                .tag(AppTab.coach)

            ProgressView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(palette.accent)
        .toolbarBackground(palette.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .fullScreenCover(isPresented: workoutBinding) {
            ActiveWorkoutView()
                .interactiveDismissDisabled()
        }
        .sheet(item: summaryBinding, onDismiss: { model.dismissSummary() }) { session in
            WorkoutSummaryView(session: session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.background)
        }
    }

    private var workoutBinding: Binding<Bool> {
        Binding(
            get: { model.activeWorkout != nil },
            set: { _ in }
        )
    }

    private var summaryBinding: Binding<WorkoutSession?> {
        Binding(
            get: { model.workoutSummary },
            set: { next in
                if next == nil { model.dismissSummary() }
            }
        )
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @Binding var selection: AppTab
    @State private var startError: String?

    private var firstName: String {
        let trimmed = model.profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var weekCount: Int {
        TrainingStats.currentWeekCount(model.sessions)
    }

    private var weeklyTarget: Int {
        max(1, model.plan?.daysPerWeek ?? model.preferences?.workoutDays.count ?? 3)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    if model.isPreview {
                        NoticeBanner(
                            message: "Preview build: data stays on this device. Connect Supabase to sync and enable the live AI coach.",
                            systemImage: "testtube.2"
                        )
                    }
                    if let startError {
                        ErrorBanner(message: startError)
                    }
                    todaySection
                    weekSection
                    if model.prefersAI {
                        insightSection
                    }
                    quickActions
                    recentSection
                    Text("Forma provides general fitness guidance, not medical advice. Stop if you feel pain, dizziness, or unusual shortness of breath.")
                        .font(FormaFont.bodyFont(10.5))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, Spacing.sm)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(Formatters.longDate(Date()).uppercased())
                        .font(FormaFont.bodyFont(11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(palette.accentText)
                    syncBadge
                }
                Text("\(Formatters.greeting()), \(firstName).")
                    .font(FormaFont.displayFont(30, weight: .bold))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.md)
            BrandMark(size: 34, color: palette.accent)
                .padding(9)
                .background(palette.surface, in: Circle())
                .overlay { Circle().strokeBorder(palette.border, lineWidth: 1) }
        }
    }

    private var syncBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(syncTint)
                .frame(width: 5, height: 5)
            Text(model.syncState.label.uppercased())
                .font(FormaFont.bodyFont(8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(palette.surfaceRaised, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sync status: \(model.syncState.detail)")
    }

    private var syncTint: Color {
        switch model.syncState {
        case .live: palette.accent
        case .syncing: palette.warning
        case .offline: palette.warning
        case .cached: palette.textTertiary
        case .local: palette.textTertiary
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todaySection: some View {
        if let day = model.todayDay {
            if day.isRestDay {
                restCard(day)
            } else {
                workoutCard(day)
            }
        } else {
            FormaCard {
                Overline(text: "Get started")
                Text("No plan yet")
                    .font(FormaFont.displayFont(22, weight: .bold))
                    .foregroundStyle(palette.text)
                Text("Build a plan in Workouts, then today's session will show up here.")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                SecondaryButton(title: "Open Workouts", systemImage: "dumbbell") {
                    selection = .workouts
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private func workoutCard(_ day: WorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Overline(text: model.activeWorkout != nil ? "In progress" : "Today's session")
                Spacer()
                if let plan = model.plan {
                    TagLabel(text: plan.source.label)
                }
            }
            Text(day.title)
                .font(FormaFont.displayFont(27, weight: .bold))
                .foregroundStyle(palette.text)
            if !day.focus.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(day.focus, id: \.self) { muscle in
                        Text(muscle.label)
                            .font(FormaFont.bodyFont(10.5, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(palette.surfaceRaised, in: Capsule())
                    }
                }
            }
            HStack(spacing: Spacing.xl) {
                todayStat(value: "\(day.exercises.count)", label: "exercises")
                todayStat(value: "\(day.exercises.reduce(0) { $0 + $1.sets })", label: "sets")
                todayStat(value: "\(day.estimatedMinutes)", label: "minutes")
            }
            .padding(.top, 2)
            PrimaryButton(
                title: model.activeWorkout != nil ? "Resume workout" : "Start workout",
                systemImage: "play.fill"
            ) {
                start(day)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.surface)
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.accentSoft)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.accentBorder, lineWidth: 1)
        }
    }

    private func restCard(_ day: WorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Overline(text: "Recovery")
            HStack(spacing: Spacing.md) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(palette.accentText)
                    .frame(width: 42, height: 42)
                    .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rest day")
                        .font(FormaFont.displayFont(22, weight: .bold))
                        .foregroundStyle(palette.text)
                    Text(day.restNote ?? "Recovery is part of the programme. Keep today easy.")
                        .font(FormaFont.bodyFont(12.5))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Spacing.sm) {
                NavigationLink {
                    RecoveryView()
                } label: {
                    Text("Open recovery")
                        .font(FormaFont.bodyFont(13, weight: .semibold))
                        .foregroundStyle(palette.accentInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle())
                if let next = model.nextDay {
                    Button {
                        selection = .workouts
                    } label: {
                        Text("Next: \(next.title)")
                            .font(FormaFont.bodyFont(13, weight: .medium))
                            .foregroundStyle(palette.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(palette.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(PressableScaleStyle())
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private func todayStat(value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(FormaFont.displayFont(17, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(FormaFont.bodyFont(11))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Week

    private var weekSection: some View {
        FormaCard {
            HStack(spacing: Spacing.lg) {
                ProgressRing(
                    progress: Double(weekCount) / Double(weeklyTarget),
                    size: 92,
                    lineWidth: 9,
                    label: "\(weekCount)/\(weeklyTarget)",
                    caption: "this week"
                )
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly rhythm")
                            .font(FormaFont.displayFont(18, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text(weekCount >= weeklyTarget ? "Target hit — anything else is a bonus." : "\(weeklyTarget - weekCount) session\(weeklyTarget - weekCount == 1 ? "" : "s") to go.")
                            .font(FormaFont.bodyFont(11.5))
                            .foregroundStyle(palette.textSecondary)
                    }
                    HStack(spacing: Spacing.lg) {
                        miniStat(value: "\(TrainingStats.currentStreak(model.sessions))", label: "day streak")
                        miniStat(value: "\(model.completedSessions.count)", label: "total")
                        miniStat(value: "\(TrainingStats.totalReps(model.completedSessions.flatMap(\.sets)))", label: "reps")
                    }
                }
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(FormaFont.displayFont(17, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(FormaFont.bodyFont(10))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Insight

    private var insightSection: some View {
        FormaCard(style: .raised) {
            HStack {
                Overline(text: "Coach insight")
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.accentText)
            }
            if let insight = model.dailyInsight, !insight.isEmpty {
                Text(insight)
                    .font(FormaFont.bodyFont(13.5))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                TextButton(title: model.insightBusy ? "Refreshing…" : "Refresh insight") {
                    Task { await model.requestDailyInsight() }
                }
            } else if model.insightBusy {
                HStack(spacing: Spacing.sm) {
                    ProgressView().tint(palette.accentText)
                    Text("Reading your training week…")
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                Text("A short, context-aware read on your training week from the AI coach.")
                    .font(FormaFont.bodyFont(12.5))
                    .foregroundStyle(palette.textSecondary)
                SecondaryButton(title: "Get today's insight", systemImage: "sparkles") {
                    Task { await model.requestDailyInsight() }
                }
            }
            if let error = model.insightError {
                Text(error)
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: Spacing.md) {
            NavigationLink {
                ExerciseLibraryView()
            } label: {
                quickAction(icon: "figure.strengthtraining.traditional", title: "Exercise library", detail: "Form guides")
            }
            .buttonStyle(PressableScaleStyle())
            NavigationLink {
                RecoveryView()
            } label: {
                quickAction(icon: "leaf", title: "Recovery", detail: "Mobility & rest")
            }
            .buttonStyle(PressableScaleStyle())
        }
    }

    private func quickAction(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.accentText)
                .frame(width: 36, height: 36)
                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title)
                .font(FormaFont.bodyFont(13, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(detail)
                .font(FormaFont.bodyFont(10.5))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Recent sessions", action: (label: "See all", action: { selection = .progress }))
            if model.completedSessions.isEmpty {
                FormaEmptyState(
                    systemImage: "calendar.badge.clock",
                    title: "No sessions yet",
                    message: "Finish your first workout and it will appear here with the sets you actually logged."
                )
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(model.completedSessions.prefix(3)) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(palette.accentText)
                .frame(width: 38, height: 38)
                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(FormaFont.bodyFont(14, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("\(Formatters.shortDate(session.startedAt)) · \(Formatters.minutesLabel(session.durationSeconds)) · \(session.sets.count) sets")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
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

    // MARK: - Actions

    private func start(_ day: WorkoutDay) {
        startError = nil
        Task {
            if model.activeWorkout != nil { return }
            do {
                try await model.startWorkout(day: day)
            } catch {
                startError = error.localizedDescription
            }
        }
    }
}
