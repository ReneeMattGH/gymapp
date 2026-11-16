import SwiftUI

struct WorkoutsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var showBuilder = false
    @State private var startError: String?

    private var todayTrainingDay: WorkoutDay? {
        guard let day = model.todayDay, !day.isRestDay else { return nil }
        return day
    }

    private var orderedDays: [WorkoutDay] {
        model.plan?.days.sorted { $0.dayIndex < $1.dayIndex } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    PageHeading(
                        eyebrow: "Training",
                        title: "Your week",
                        subtitle: model.plan?.name ?? "No active plan yet."
                    )
                    if model.isPreview {
                        NoticeBanner(
                            message: "Preview build: the plan is stored on this device. AI regeneration needs a connected Supabase project.",
                            systemImage: "testtube.2"
                        )
                    }
                    if let startError {
                        ErrorBanner(message: startError)
                    }
                    planCard
                    if !orderedDays.isEmpty {
                        scheduleSection
                        sessionsSection
                    }
                    libraryCard
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
        .sheet(isPresented: $showBuilder) {
            PlanBuilderView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.background)
        }
    }

    // MARK: - Plan card

    private var planCard: some View {
        FormaCard(style: .raised) {
            HStack {
                Overline(text: model.plan == nil ? "Plan" : "Active plan")
                Spacer()
                if let plan = model.plan {
                    TagLabel(text: plan.source.label)
                }
            }
            if let plan = model.plan {
                Text(plan.name)
                    .font(FormaFont.displayFont(24, weight: .bold))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.lg) {
                    planStat(value: "\(plan.daysPerWeek)", label: "days / week")
                    planStat(value: "\(plan.sessionMinutes)m", label: "per session")
                    planStat(value: "\(plan.totalExercises)", label: "exercises")
                }
                if let day = todayTrainingDay {
                    PrimaryButton(title: model.activeWorkout != nil ? "Resume workout" : "Start today's session", systemImage: "play.fill") {
                        start(day)
                    }
                    .padding(.top, Spacing.xs)
                }
                HStack(spacing: Spacing.sm) {
                    SecondaryButton(title: "Rebuild plan", systemImage: model.prefersAI ? "sparkles" : "arrow.triangle.2.circlepath") {
                        showBuilder = true
                    }
                }
            } else {
                Text("Answer a few questions and Forma will build a schedule you can actually keep.")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Build my plan", systemImage: "sparkles") {
                    showBuilder = true
                }
            }
        }
    }

    private func planStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(FormaFont.displayFont(18, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(FormaFont.bodyFont(10))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Week schedule")
            VStack(spacing: 0) {
                ForEach(Array(orderedDays.enumerated()), id: \.element.id) { index, day in
                    if day.isRestDay {
                        scheduleRow(day, isRest: true)
                    } else {
                        NavigationLink {
                            PlanDayDetailView(day: day)
                        } label: {
                            scheduleRow(day, isRest: false)
                        }
                        .buttonStyle(.plain)
                    }
                    if index != orderedDays.count - 1 {
                        FormaDivider().padding(.leading, 56)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
        }
    }

    private func scheduleRow(_ day: WorkoutDay, isRest: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            Text(day.weekday.map(Weekday.short) ?? "—")
                .font(FormaFont.bodyFont(11, weight: .semibold))
                .foregroundStyle(isRest ? palette.textTertiary : palette.accentText)
                .frame(width: 40, height: 36)
                .background(isRest ? palette.surfaceRaised : palette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(isRest ? "Recovery" : day.title)
                    .font(FormaFont.bodyFont(14, weight: .semibold))
                    .foregroundStyle(isRest ? palette.textSecondary : palette.text)
                Text(isRest ? (day.restNote ?? "Rest and recover.") : "\(day.exercises.count) exercises · \(day.estimatedMinutes) min")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !isRest {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Sessions")
            if let plan = model.plan {
                VStack(spacing: Spacing.sm) {
                    ForEach(plan.trainingDays) { day in
                        NavigationLink {
                            PlanDayDetailView(day: day)
                        } label: {
                            sessionCard(day)
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
        }
    }

    private func sessionCard(_ day: WorkoutDay) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.accentText)
                .frame(width: 42, height: 42)
                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(day.title)
                    .font(FormaFont.bodyFont(15, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("\(day.exercises.count) exercises · \(day.estimatedMinutes) min · \(day.exercises.reduce(0) { $0 + $1.sets }) sets")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    // MARK: - Library

    private var libraryCard: some View {
        NavigationLink {
            ExerciseLibraryView()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.text)
                    .frame(width: 42, height: 42)
                    .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exercise library")
                        .font(FormaFont.bodyFont(14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("\(model.exercises.count) verified movements with form cues")
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
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
    }

    private func start(_ day: WorkoutDay) {
        startError = nil
        Task {
            guard model.activeWorkout == nil else { return }
            do {
                try await model.startWorkout(day: day)
            } catch {
                startError = error.localizedDescription
            }
        }
    }
}

// MARK: - Plan builder

struct PlanBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette

    @State private var draft: WorkoutPlan?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var notice: String?
    @State private var didBuild = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(
                title: "Build a plan",
                subtitle: "Review the draft before saving. Nothing changes until you save.",
                onClose: { dismiss() }
            )
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let error {
                        ErrorBanner(message: error)
                    }
                    if let notice {
                        NoticeBanner(message: notice, systemImage: "checkmark.seal", accent: true)
                    }
                    if isLoading || (draft == nil && error == nil) {
                        LoadingCard(label: "Building a balanced week")
                            .padding(.top, Spacing.xxl)
                    } else if let draft {
                        draftContent(draft)
                    }
                    NoticeBanner(
                        message: model.prefersAI
                            ? "The AI coach returns a structured plan that is validated against the exercise library, your equipment, and your schedule before it can be saved."
                            : "The built-in template uses your goals, equipment, and schedule. AI regeneration appears when Supabase is connected.",
                        systemImage: "shield.lefthalf.filled"
                    )
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: Spacing.sm) {
                if model.prefersAI {
                    SecondaryButton(
                        title: model.isGeneratingPlan ? "Asking the AI coach…" : "Rebuild with AI coach",
                        systemImage: "sparkles",
                        isDisabled: isSaving || model.isGeneratingPlan
                    ) {
                        generateWithAI()
                    }
                }
                SecondaryButton(title: "Use built-in template", systemImage: "arrow.triangle.2.circlepath", isDisabled: isSaving || model.isGeneratingPlan) {
                    rebuildLocally()
                }
                PrimaryButton(title: "Save plan", systemImage: "checkmark", isLoading: isSaving, isDisabled: draft == nil || isLoading) {
                    save()
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
            .background {
                palette.background
                    .opacity(0.97)
                    .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(FormaBackground())
        .task {
            guard !didBuild else { return }
            didBuild = true
            rebuildLocally()
        }
    }

    private func draftContent(_ draft: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FormaCard(style: .raised) {
                HStack {
                    Overline(text: "Draft")
                    Spacer()
                    TagLabel(text: draft.source.label)
                }
                Text(draft.name)
                    .font(FormaFont.displayFont(22, weight: .bold))
                    .foregroundStyle(palette.text)
                HStack(spacing: Spacing.lg) {
                    builderStat(value: "\(draft.daysPerWeek)", label: "days")
                    builderStat(value: "\(draft.sessionMinutes)m", label: "session")
                    builderStat(value: "\(draft.totalExercises)", label: "exercises")
                    builderStat(value: draft.goal.shortLabel, label: "focus")
                }
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Training days")
                ForEach(draft.trainingDays) { day in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Text(day.weekday.map(Weekday.short) ?? "—")
                            .font(FormaFont.bodyFont(11, weight: .semibold))
                            .foregroundStyle(palette.accentText)
                            .frame(width: 40, height: 32)
                            .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.title)
                                .font(FormaFont.bodyFont(13.5, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text(day.exercises.map { model.exerciseName($0.exerciseId) }.joined(separator: ", "))
                                .font(FormaFont.bodyFont(11))
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
            Text("You can fine-tune sets, reps, rest, and exercise choices after saving from any training day.")
                .font(FormaFont.bodyFont(11))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func builderStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(FormaFont.displayFont(17, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(FormaFont.bodyFont(10))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func rebuildLocally() {
        error = nil
        notice = nil
        isLoading = true
        Task { @MainActor in
            do {
                draft = try model.buildLocalPlanDraft()
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func generateWithAI() {
        error = nil
        notice = nil
        Task { @MainActor in
            do {
                let plan = try await model.requestAIPlan()
                draft = plan
                notice = "The AI plan passed validation. Review it before saving."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let draft else { return }
        error = nil
        isSaving = true
        Task { @MainActor in
            do {
                try await model.adoptPlan(draft)
                Haptics.success()
                isSaving = false
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isSaving = false
            }
        }
    }
}

// MARK: - Day detail

struct PlanDayDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var day: WorkoutDay
    @State private var error: String?
    @State private var sheet: DaySheet?
    @State private var removing: WorkoutExercise?
    @State private var isSaving = false

    private enum DaySheet: Identifiable {
        case edit(WorkoutExercise)
        case replace(WorkoutExercise)

        var id: String {
            switch self {
            case .edit(let exercise): "edit-\(exercise.id)"
            case .replace(let exercise): "replace-\(exercise.id)"
            }
        }
    }

    init(day: WorkoutDay) {
        _day = State(initialValue: day)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PageHeading(
                    eyebrow: "Session",
                    title: day.title,
                    subtitle: "\(day.exercises.count) exercises · about \(day.estimatedMinutes) minutes"
                )
                if let error {
                    ErrorBanner(message: error)
                }
                PrimaryButton(
                    title: model.activeWorkout != nil ? "Workout in progress" : "Start workout",
                    systemImage: "play.fill",
                    isDisabled: model.activeWorkout != nil
                ) {
                    start()
                }
                if !day.warmup.isEmpty {
                    bulletCard(title: "Warm-up", icon: "flame", items: day.warmup)
                }
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(title: "Exercises")
                    if day.exercises.isEmpty {
                        FormaEmptyState(
                            systemImage: "dumbbell",
                            title: "No exercises",
                            message: "Replace or rebuild the plan to add movements to this day."
                        )
                    } else {
                        VStack(spacing: Spacing.sm) {
                            ForEach(day.exercises.sorted { $0.position < $1.position }) { item in
                                exerciseRow(item)
                            }
                        }
                    }
                }
                if !day.cooldown.isEmpty {
                    bulletCard(title: "Cool-down", icon: "wind", items: day.cooldown)
                }
                NoticeBanner(
                    message: "Stop any movement that causes sharp pain, dizziness, or unusual shortness of breath. Forma does not diagnose injuries.",
                    systemImage: "heart.text.square"
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
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit(let exercise):
                EditTargetsSheet(exercise: exercise) { updated in
                    applyTargets(updated)
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(palette.background)
            case .replace(let exercise):
                ReplaceExerciseSheet(current: exercise, exercises: model.exercises) { newId in
                    applyReplacement(exercise, newId: newId)
                }
                .presentationDetents([.large])
                .presentationBackground(palette.background)
            }
        }
        .confirmationDialog(
            "Remove this exercise?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove exercise", role: .destructive) {
                if let removing { applyRemoval(removing) }
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("The sets you log for this movement will no longer appear in the session.")
        }
    }

    private func exerciseRow(_ item: WorkoutExercise) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            NavigationLink {
                ExerciseDetailView(exercise: model.exercise(item.exerciseId))
            } label: {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Text("\(item.position + 1)")
                        .font(FormaFont.displayFont(13, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(palette.surfaceRaised, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.exerciseName(item.exerciseId))
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .multilineTextAlignment(.leading)
                        Text("\(item.sets) sets · \(item.repsMin)–\(item.repsMax) reps · \(item.restSeconds)s rest")
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                        if let notes = item.notes, !notes.isEmpty {
                            Text(notes)
                                .font(FormaFont.bodyFont(11))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    sheet = .edit(item)
                } label: {
                    Label("Edit targets", systemImage: "slider.horizontal.3")
                }
                Button {
                    sheet = .replace(item)
                } label: {
                    Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) {
                    removing = item
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(palette.surfaceRaised, in: Circle())
            }
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private func bulletCard(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accentText)
                Text(title.uppercased())
                    .font(FormaFont.bodyFont(11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textSecondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)
                    Text(item)
                        .font(FormaFont.bodyFont(12.5))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private func start() {
        error = nil
        Task {
            guard model.activeWorkout == nil else { return }
            do {
                try await model.startWorkout(day: day)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: Editing

    private func applyTargets(_ updated: WorkoutExercise) {
        guard var exercises = currentExercises(), let index = exercises.firstIndex(where: { $0.id == updated.id }) else { return }
        exercises[index] = updated
        persist(exercises)
    }

    private func applyReplacement(_ exercise: WorkoutExercise, newId: String) {
        guard let index = day.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        var exercises = day.exercises
        exercises[index].exerciseId = newId
        persist(exercises)
    }

    private func applyRemoval(_ exercise: WorkoutExercise) {
        removing = nil
        guard day.exercises.count > 1 else {
            error = "A session needs at least one exercise. Rebuild the plan instead."
            return
        }
        let exercises = day.exercises.filter { $0.id != exercise.id }
        persist(exercises)
    }

    private func currentExercises() -> [WorkoutExercise]? {
        guard let plan = model.plan,
              let found = plan.days.first(where: { $0.dayIndex == day.dayIndex }) else {
            return day.exercises
        }
        return found.exercises.sorted { $0.position < $1.position }
    }

    private func persist(_ exercises: [WorkoutExercise]) {
        guard var plan = model.plan,
              let index = plan.days.firstIndex(where: { $0.dayIndex == day.dayIndex }) else {
            error = "The plan could not be found. Refresh and try again."
            return
        }
        isSaving = true
        var updatedDay = plan.days[index]
        updatedDay.exercises = exercises.enumerated().map { position, item in
            var copy = item
            copy.position = position
            copy.dayId = updatedDay.id
            return copy
        }
        plan.days[index] = updatedDay
        Task { @MainActor in
            do {
                _ = try await model.saveEditedPlan(plan)
                if let saved = model.plan?.days.first(where: { $0.dayIndex == day.dayIndex }) {
                    day = saved
                }
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Edit targets sheet

struct EditTargetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    let exercise: WorkoutExercise
    let onSave: (WorkoutExercise) -> Void

    @State private var sets: Int
    @State private var repsMin: Int
    @State private var repsMax: Int
    @State private var rest: Int

    init(exercise: WorkoutExercise, onSave: @escaping (WorkoutExercise) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _sets = State(initialValue: exercise.sets)
        _repsMin = State(initialValue: exercise.repsMin)
        _repsMax = State(initialValue: exercise.repsMax)
        _rest = State(initialValue: exercise.restSeconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(
                title: "Edit targets",
                subtitle: "Adjust this movement in the plan. Changes apply when you tap Apply.",
                onClose: { dismiss() }
            )
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    HStack {
                        Text("Sets")
                            .font(FormaFont.bodyFont(12, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        StepperControl(value: sets, range: 1...8) { sets = $0 }
                    }
                    FormaDivider()
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Reps range")
                            .font(FormaFont.bodyFont(12, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                        StepperControl(value: repsMin, range: 1...30, suffix: "min reps") {
                            repsMin = $0
                            repsMax = max(repsMax, $0)
                        }
                        StepperControl(value: repsMax, range: 1...40, suffix: "max reps") {
                            repsMax = $0
                            repsMin = min(repsMin, $0)
                        }
                    }
                    FormaDivider()
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Rest between sets")
                            .font(FormaFont.bodyFont(12, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                        HStack(spacing: Spacing.lg) {
                            adjustButton("minus") { rest = max(0, rest - 15) }
                            Text(rest == 0 ? "No rest" : "\(rest) sec")
                                .font(FormaFont.displayFont(20, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .frame(minWidth: 96)
                                .contentTransition(.numericText())
                            adjustButton("plus") { rest = min(300, rest + 15) }
                        }
                    }
                }
                .padding(Spacing.xl)
            }
            .scrollIndicators(.hidden)

            PrimaryButton(title: "Apply changes", systemImage: "checkmark") {
                var updated = exercise
                updated.sets = sets
                updated.repsMin = min(repsMin, repsMax)
                updated.repsMax = max(repsMin, repsMax)
                updated.restSeconds = rest
                onSave(updated)
                Haptics.success()
                dismiss()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
        .background(FormaBackground())
    }

    private func adjustButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.15)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 38, height: 38)
                .background(palette.surfaceRaised, in: Circle())
                .overlay { Circle().strokeBorder(palette.border, lineWidth: 1) }
        }
        .buttonStyle(PressableScaleStyle())
    }
}

// MARK: - Replace exercise sheet

struct ReplaceExerciseSheet: View {
    let current: WorkoutExercise
    let exercises: [Exercise]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var query = ""

    private var candidates: [Exercise] {
        let original = exercises.first { $0.id == current.exerciseId }
        let alternates = Set(original?.alternatives ?? [])
        let muscles = Set(original?.primaryMuscles ?? [])
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return exercises
            .filter { $0.id != current.exerciseId }
            .filter { exercise in
                guard !text.isEmpty else { return true }
                return exercise.name.lowercased().contains(text)
                    || exercise.primaryMuscles.contains { $0.label.lowercased().contains(text) }
            }
            .sorted { lhs, rhs in
                let lhsRank = alternates.contains(lhs.id) ? 0 : (lhs.primaryMuscles.contains(where: muscles.contains) ? 1 : 2)
                let rhsRank = alternates.contains(rhs.id) ? 0 : (rhs.primaryMuscles.contains(where: muscles.contains) ? 1 : 2)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.name < rhs.name
            }
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            SheetHeading(
                title: "Replace exercise",
                subtitle: "Alternatives for \(ExerciseCatalog.name(current.exerciseId)) are listed first.",
                onClose: { dismiss() }
            )
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            FormaTextField(placeholder: "Search exercises", text: $query, capitalization: .never)
                .padding(.horizontal, Spacing.xl)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(candidates) { exercise in
                        Button {
                            Haptics.selection()
                            onSelect(exercise.id)
                            dismiss()
                        } label: {
                            HStack(spacing: Spacing.md) {
                                ExerciseGlyph(exercise: exercise, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                        .font(FormaFont.bodyFont(14, weight: .semibold))
                                        .foregroundStyle(palette.text)
                                    Text(exercise.primaryMuscles.map(\.label).joined(separator: " · "))
                                        .font(FormaFont.bodyFont(11))
                                        .foregroundStyle(palette.textTertiary)
                                }
                                Spacer(minLength: 0)
                                if exercise.equipment.allSatisfy({ $0 == .bodyweight }) {
                                    TagLabel(text: "Bodyweight", color: palette.textTertiary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, Spacing.xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(palette.border).frame(height: 1).padding(.leading, Spacing.xl)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if candidates.isEmpty {
                        Text("No exercises match that search.")
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textTertiary)
                            .padding(.vertical, Spacing.xxl)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(FormaBackground())
    }
}
