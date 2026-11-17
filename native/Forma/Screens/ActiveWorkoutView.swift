import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase

    @State private var now = Date()
    @State private var repsText = ""
    @State private var weightText = ""
    @State private var showWarmup = false
    @State private var showReplace = false
    @State private var formCheckExercise: FormAnalysisExercise?
    @State private var error: String?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var lastExerciseId: String?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            FormaBackground()
            if let workout = model.activeWorkout {
                content(workout)
            } else {
                VStack(spacing: Spacing.md) {
                    ProgressView().tint(palette.accentText)
                    Text("Closing session…")
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .onReceive(timer) { tick in
            now = tick
            Task { await model.tickRest() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .onAppear {
            now = Date()
            syncInputs()
        }
        .sheet(isPresented: $showReplace) {
            if let exercise = model.activeWorkout?.currentExercise {
                ReplaceExerciseSheet(current: exercise, exercises: model.exercises) { newId in
                    Task {
                        await model.replaceExercise(exercise, withId: newId)
                        syncInputs(force: true)
                    }
                }
                .presentationDetents([.large])
                .presentationBackground(palette.background)
            }
        }
        .fullScreenCover(item: $formCheckExercise) { exercise in
            FormAnalysisView(preferredExercise: exercise)
        }
        .confirmationDialog(
            "Finish and save this workout?",
            isPresented: $confirmFinish,
            titleVisibility: .visible
        ) {
            Button("Finish & save") {
                Task { await finish() }
            }
            Button("Keep training", role: .cancel) {}
        } message: {
            if let workout = model.activeWorkout {
                Text("\(workout.sets.count) sets will be saved from the numbers you logged.")
            }
        }
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard workout", role: .destructive) {
                Task { await model.discardWorkout() }
            }
            Button("Keep training", role: .cancel) {}
        } message: {
            Text("Nothing from this session will be saved.")
        }
    }

    // MARK: - Content

    private func content(_ workout: ActiveWorkout) -> some View {
        VStack(spacing: 0) {
            header(workout)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let error {
                        ErrorBanner(message: error)
                    }
                    if let workoutError = model.workoutError {
                        ErrorBanner(message: workoutError)
                    }
                    if workout.status == .paused {
                        NoticeBanner(
                            message: "Workout paused. The elapsed timer and rest timer are frozen.",
                            systemImage: "pause.circle",
                            accent: true
                        )
                    }
                    progressStrip(workout)
                    if let exercise = workout.currentExercise {
                        currentExerciseCard(workout, exercise: exercise)
                    } else {
                        completionCard(workout)
                    }
                    if let next = nextExercise(workout) {
                        nextCard(next)
                    }
                    warmupCard(workout)
                    exercisePicker(workout)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxxl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            footer(workout)
        }
    }

    // MARK: - Header

    private func header(_ workout: ActiveWorkout) -> some View {
        VStack(spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Wordmark(compact: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workout.title)
                        .font(FormaFont.displayFont(16, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(statusLabel(workout))
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: Spacing.sm)
                Text(Formatters.clock(workout.elapsedSeconds(at: now)))
                    .font(FormaFont.displayFont(22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(workout.status == .paused ? palette.textTertiary : palette.text)
                    .contentTransition(.numericText())
                Menu {
                    Button {
                        Task {
                            if workout.status == .paused {
                                await model.resumeWorkout()
                            } else {
                                await model.pauseWorkout()
                            }
                        }
                    } label: {
                        Label(workout.status == .paused ? "Resume workout" : "Pause workout",
                              systemImage: workout.status == .paused ? "play.fill" : "pause.fill")
                    }
                    Button {
                        confirmFinish = true
                    } label: {
                        Label("Finish & save", systemImage: "checkmark.circle")
                    }
                    .disabled(workout.sets.isEmpty)
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Label("Discard", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .frame(width: 38, height: 38)
                        .background(palette.surface, in: Circle())
                        .overlay { Circle().strokeBorder(palette.border, lineWidth: 1) }
                }
                .accessibilityLabel("Workout options")
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.surfaceRaised)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(4, geometry.size.width * completion(workout)))
                        .animation(.smooth(duration: 0.35), value: completion(workout))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .background(palette.background.opacity(0.96))
    }

    private func statusLabel(_ workout: ActiveWorkout) -> String {
        if workout.status == .paused { return "Paused" }
        if let rest = workout.rest {
            return "Resting · \(rest.remaining(at: now))s left"
        }
        return "Set \(min(workout.sets.count + 1, workout.totalPlannedSets)) of \(workout.totalPlannedSets)"
    }

    private func completion(_ workout: ActiveWorkout) -> Double {
        guard workout.totalPlannedSets > 0 else { return 0 }
        return min(1, Double(workout.sets.count) / Double(workout.totalPlannedSets))
    }

    // MARK: - Progress strip

    private func progressStrip(_ workout: ActiveWorkout) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(palette.accentText)
            Text("\(workout.sets.count) of \(workout.totalPlannedSets) sets logged")
                .font(FormaFont.bodyFont(12, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            if let rest = workout.rest {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                    Text(Formatters.clock(rest.remaining(at: now)))
                        .monospacedDigit()
                }
                .font(FormaFont.bodyFont(12, weight: .semibold))
                .foregroundStyle(palette.accentText)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    // MARK: - Current exercise

    private func currentExerciseCard(_ workout: ActiveWorkout, exercise: WorkoutExercise) -> some View {
        let detail = model.exercise(exercise.exerciseId)
        let completed = workout.sets(for: exercise).count
        let isComplete = completed >= exercise.sets

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Overline(text: isComplete ? "Exercise complete" : "Current exercise")
                    Text(model.exerciseName(exercise.exerciseId))
                        .font(FormaFont.displayFont(25, weight: .bold))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let detail {
                    ExerciseGlyph(exercise: detail, size: 48)
                }
            }
            if let detail {
                HStack(spacing: 6) {
                    ForEach(detail.primaryMuscles.prefix(3), id: \.self) { muscle in
                        Text(muscle.label)
                            .font(FormaFont.bodyFont(10, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(palette.surfaceRaised, in: Capsule())
                    }
                }
                if let cue = detail.cues.first {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "target")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.accentText)
                            .padding(.top, 2)
                        Text(cue)
                            .font(FormaFont.bodyFont(11.5))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: Spacing.md) {
                targetPill("\(exercise.sets)", "sets")
                targetPill("\(exercise.repsMin)–\(exercise.repsMax)", "reps")
                targetPill(exercise.restSeconds == 0 ? "—" : "\(exercise.restSeconds)s", "rest")
                Spacer()
                SetDots(total: exercise.sets, completed: completed)
            }

            if let rest = workout.rest, !isComplete || rest.exerciseId == exercise.exerciseId {
                restCard(rest, duration: exercise.restSeconds)
            } else if isComplete {
                NoticeBanner(
                    message: "All sets logged for this movement. Pick another exercise or finish the session.",
                    systemImage: "checkmark.circle",
                    accent: true
                )
            } else if workout.status == .active {
                inputRow(workout, exercise: exercise, nextSet: completed + 1)
                PrimaryButton(title: "Log set \(completed + 1) of \(exercise.sets)", systemImage: "checkmark") {
                    logSet(workout, exercise: exercise)
                }
                if completed > 0 {
                    TextButton(title: "Remove last set", destructive: true) {
                        Task {
                            await model.removeLastSet(for: exercise)
                            syncInputs()
                        }
                    }
                }
            }

            HStack(spacing: Spacing.sm) {
                SecondaryButton(title: "Replace", systemImage: "arrow.triangle.2.circlepath", isDisabled: workout.status == .paused) {
                    showReplace = true
                }
                SecondaryButton(title: "Skip", systemImage: "forward.end", isDisabled: workout.status == .paused) {
                    Task { await model.skipExercise() }
                }
            }
            formCheckRow(exercise: exercise)
        }
        .padding(Spacing.lg)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.accentBorder, lineWidth: 1)
        }
    }

    private func formCheckRow(exercise: WorkoutExercise) -> some View {
        let support = FormAnalysisExercise.matching(catalogID: exercise.exerciseId)
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(support == nil ? palette.textTertiary : palette.accentText)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                if let support {
                    Button {
                        formCheckExercise = support
                    } label: {
                        HStack(spacing: 4) {
                            Text("Check form with the camera")
                                .font(FormaFont.bodyFont(12.5, weight: .semibold))
                                .foregroundStyle(palette.accentText)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.accentText)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("\(support.shortTitle) analysis runs fully on this device. Rest timers keep running in the background.")
                        .font(FormaFont.bodyFont(10.5))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Camera form analysis is available for squats, push-ups, lunges and jumping jacks. It is not available for this movement.")
                        .font(FormaFont.bodyFont(10.5))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func targetPill(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(FormaFont.displayFont(15, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(FormaFont.bodyFont(10))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(palette.surfaceRaised, in: Capsule())
    }

    private func restCard(_ rest: ActiveRest, duration: Int) -> some View {
        let remaining = rest.remaining(at: now)
        let total = max(1, duration)
        return HStack(spacing: Spacing.lg) {
            ProgressRing(
                progress: Double(remaining) / Double(total),
                size: 82,
                lineWidth: 8,
                label: Formatters.clock(remaining),
                caption: rest.isPaused ? "paused" : "rest"
            )
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(rest.isPaused ? "Rest paused" : "Resting")
                    .font(FormaFont.displayFont(18, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("Breathe. The next set starts when you are ready.")
                    .font(FormaFont.bodyFont(11.5))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.sm) {
                    Button {
                        Task {
                            if rest.isPaused {
                                await model.resumeRest()
                            } else {
                                await model.pauseRest()
                            }
                        }
                    } label: {
                        Text(rest.isPaused ? "Resume" : "Pause")
                            .font(FormaFont.bodyFont(12, weight: .semibold))
                            .foregroundStyle(palette.accentInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(palette.accent, in: Capsule())
                    }
                    Button {
                        Task { await model.skipRest() }
                    } label: {
                        Text("Skip rest")
                            .font(FormaFont.bodyFont(12, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(palette.surfaceRaised, in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.accentBorder, lineWidth: 1)
        }
    }

    private func inputRow(_ workout: ActiveWorkout, exercise: WorkoutExercise, nextSet: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reps")
                    .font(FormaFont.bodyFont(11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                TextField("\(exercise.repsMax)", text: $repsText)
                    .font(FormaFont.displayFont(22, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .background(palette.input, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Weight (\(model.units.abbreviation))")
                    .font(FormaFont.bodyFont(11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                TextField("Optional", text: $weightText)
                    .font(FormaFont.displayFont(22, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .background(palette.input, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    }
            }
        }
        .onAppear {
            if repsText.isEmpty { repsText = "\(exercise.repsMax)" }
        }
    }

    // MARK: - Next / warmup / picker

    private func nextExercise(_ workout: ActiveWorkout) -> WorkoutExercise? {
        let index = workout.currentExerciseIndex
        return workout.exercises
            .filter { $0.position > (workout.exercises.indices.contains(index) ? workout.exercises[index].position : -1) }
            .first { !workout.allSetsComplete(for: $0) }
    }

    private func nextCard(_ exercise: WorkoutExercise) -> some View {
        HStack(spacing: Spacing.md) {
            Text("NEXT")
                .font(FormaFont.bodyFont(9.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Text(model.exerciseName(exercise.exerciseId))
                .font(FormaFont.bodyFont(13, weight: .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(exercise.sets) × \(exercise.repsMin)–\(exercise.repsMax)")
                .font(FormaFont.bodyFont(11))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func warmupCard(_ workout: ActiveWorkout) -> some View {
        Group {
            if !workout.warmup.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showWarmup.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: "flame")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.accentText)
                            Text("Warm-up · \(workout.warmup.count) steps")
                                .font(FormaFont.bodyFont(12, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Image(systemName: showWarmup ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if showWarmup {
                        ForEach(workout.warmup, id: \.self) { step in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Circle().fill(palette.accent).frame(width: 4, height: 4).padding(.top, 6)
                                Text(step)
                                    .font(FormaFont.bodyFont(11.5))
                                    .foregroundStyle(palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(Spacing.md)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private func exercisePicker(_ workout: ActiveWorkout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Exercises")
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                        let done = workout.allSetsComplete(for: exercise)
                        let current = index == workout.currentExerciseIndex
                        Button {
                            Task { await model.selectExercise(index: index) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: done ? "checkmark.circle.fill" : (current ? "circle.inset.filled" : "circle"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(done || current ? palette.accentText : palette.textTertiary)
                                    Text("\(index + 1)")
                                        .font(FormaFont.bodyFont(9.5, weight: .semibold))
                                        .foregroundStyle(palette.textTertiary)
                                }
                                Text(model.exerciseName(exercise.exerciseId))
                                    .font(FormaFont.bodyFont(11.5, weight: .semibold))
                                    .foregroundStyle(current ? palette.text : palette.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 108, alignment: .leading)
                            }
                            .padding(Spacing.sm)
                            .background(
                                current ? palette.accentSoft : palette.surface,
                                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(current ? palette.accentBorder : palette.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func completionCard(_ workout: ActiveWorkout) -> some View {
        FormaCard(style: .accent) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28))
                .foregroundStyle(palette.accentText)
            Text("Every set is logged")
                .font(FormaFont.displayFont(22, weight: .bold))
                .foregroundStyle(palette.text)
            Text("Finish to save \(workout.sets.count) sets and \(Formatters.minutesLabel(workout.elapsedSeconds(at: now))) of work.")
                .font(FormaFont.bodyFont(12.5))
                .foregroundStyle(palette.textSecondary)
            PrimaryButton(title: "Finish & save", systemImage: "checkmark") {
                confirmFinish = true
            }
        }
    }

    // MARK: - Footer

    private func footer(_ workout: ActiveWorkout) -> some View {
        VStack(spacing: Spacing.sm) {
            if workout.status == .paused {
                PrimaryButton(title: "Resume workout", systemImage: "play.fill") {
                    Task { await model.resumeWorkout() }
                }
            } else {
                PrimaryButton(
                    title: model.isSavingWorkout ? "Saving…" : "Finish workout",
                    systemImage: "flag.checkered",
                    isLoading: model.isSavingWorkout,
                    isDisabled: workout.sets.isEmpty
                ) {
                    confirmFinish = true
                }
            }
            if workout.sets.isEmpty {
                Text("Log at least one set to save the session.")
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background {
            palette.background
                .opacity(0.97)
                .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Actions

    private func logSet(_ workout: ActiveWorkout, exercise: WorkoutExercise) {
        guard workout.status == .active else { return }
        let reps = Int(repsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? exercise.repsMax
        guard reps > 0 else {
            error = "Enter the reps you completed."
            return
        }
        var weightKg: Double?
        let weightTrimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if !weightTrimmed.isEmpty {
            guard let entered = Double(weightTrimmed), entered >= 0, entered < 1000 else {
                error = "Enter a valid weight in \(model.units.abbreviation), or leave it blank."
                return
            }
            weightKg = model.units == .kg ? entered : entered / 2.2046226218
        }
        error = nil
        Task {
            await model.completeSet(exercise: exercise, reps: reps, weightKg: weightKg)
            repsText = "\(exercise.repsMax)"
        }
    }

    private func finish() async {
        await model.finishWorkout()
        if let message = model.workoutError {
            error = message
        }
    }

    private func syncInputs(force: Bool = false) {
        guard let exercise = model.activeWorkout?.currentExercise else { return }
        if force || lastExerciseId != exercise.id {
            lastExerciseId = exercise.id
            repsText = "\(exercise.repsMax)"
            if let kg = lastWeight(for: exercise.exerciseId) {
                let value = model.units == .kg ? kg : kg * 2.2046226218
                weightText = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
            } else {
                weightText = ""
            }
        }
    }

    private func lastWeight(for exerciseId: String) -> Double? {
        for session in model.completedSessions {
            if let set = session.sets.last(where: { $0.exerciseId == exerciseId && $0.weightKg != nil }) {
                return set.weightKg
            }
        }
        return nil
    }
}

// MARK: - Summary

struct WorkoutSummaryView: View {
    let session: WorkoutSession
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var appeared = false

    private var exerciseCount: Int {
        Set(session.sets.map(\.exerciseId)).count
    }

    private var volume: Double? {
        let values = session.sets.compactMap { set in set.weightKg.map { $0 * Double(set.reps) } }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var durationText: String {
        session.durationSeconds < 60
            ? Formatters.clock(session.durationSeconds)
            : Formatters.minutesLabel(session.durationSeconds)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(palette.accentText)
                    .frame(width: 76, height: 76)
                    .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(palette.accentBorder, lineWidth: 1)
                    }
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, Spacing.xl)

                VStack(spacing: Spacing.sm) {
                    Overline(text: "Saved")
                    Text(session.title)
                        .font(FormaFont.displayFont(27, weight: .bold))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                    Text("\(Formatters.longDate(session.startedAt)) · \(Formatters.time(session.startedAt))")
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textSecondary)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    StatTile(value: durationText, label: "Duration")
                    StatTile(value: "\(session.sets.count)", label: "Sets")
                    StatTile(value: "\(TrainingStats.totalReps(session.sets))", label: "Reps")
                    StatTile(value: "\(exerciseCount)", label: "Exercises", accent: true)
                }

                if let volume {
                    FormaCard(style: .raised) {
                        KeyValueRow(
                            label: "Logged volume",
                            value: Formatters.weight(kilograms: volume, units: model.units) + " total",
                            valueColor: palette.accentText
                        )
                        Text("Only sets with a recorded weight are counted. Forma never estimates calories or heart rate.")
                            .font(FormaFont.bodyFont(10.5))
                            .foregroundStyle(palette.textTertiary)
                    }
                }

                PrimaryButton(title: "Done", systemImage: "checkmark") {
                    dismiss()
                }
                .padding(.top, Spacing.sm)

                Text(model.isPreview
                     ? "Saved on this device. Open Progress to see it in your history."
                     : "Saved to your account. Open Progress to see it in your history.")
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(FormaBackground())
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { appeared = true }
        }
    }
}
