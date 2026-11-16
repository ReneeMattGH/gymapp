import Charts
import SwiftUI

struct ProgressView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var showCheckIn = false

    private var weeks: [TrainingStats.WeekCount] {
        TrainingStats.lastWeeksCounts(model.sessions, weeks: 8)
    }

    private var sessionPoints: [WorkoutSession] {
        Array(model.completedSessions.sorted { $0.startedAt < $1.startedAt }.suffix(10))
    }

    private var weightRecords: [ProgressRecord] {
        model.progressRecords
            .filter { $0.bodyweightKg != nil }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    private var totalSeconds: Int {
        model.completedSessions.reduce(0) { $0 + $1.durationSeconds }
    }

    private var timeTrainedText: String {
        totalSeconds > 0 && totalSeconds < 60
            ? "<1 min"
            : Formatters.minutesLabel(totalSeconds)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    PageHeading(
                        eyebrow: "Progress",
                        title: "The work adds up",
                        subtitle: "Charts use only sessions and sets you have actually logged."
                    )
                    statGrid
                    weeklyChart
                    repsChart
                    checkInSection
                    historySection
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
        .sheet(isPresented: $showCheckIn) {
            CheckInView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.background)
        }
    }

    // MARK: - Stats

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
            StatTile(value: "\(model.completedSessions.count)", label: "Sessions", detail: "completed")
            StatTile(value: "\(TrainingStats.currentStreak(model.sessions))", label: "Streak", detail: "days", accent: true)
            StatTile(value: "\(TrainingStats.totalReps(model.completedSessions.flatMap(\.sets)))", label: "Reps", detail: "logged")
            StatTile(value: timeTrainedText, label: "Time", detail: "trained")
        }
    }

    // MARK: - Charts

    private var weeklyChart: some View {
        chartCard(
            title: "Sessions per week",
            subtitle: "Last eight weeks",
            empty: model.completedSessions.isEmpty,
            emptyMessage: "Finish a session to start the chart."
        ) {
            Chart(weeks) { week in
                BarMark(
                    x: .value("Week", week.label),
                    y: .value("Sessions", week.value)
                )
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: 0xD8FF76), Color(hex: 0xAEEB3E)], startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(palette.border)
                    AxisValueLabel().foregroundStyle(palette.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(palette.textTertiary)
                }
            }
            .frame(height: 160)
        }
    }

    private var repsChart: some View {
        chartCard(
            title: "Reps per session",
            subtitle: "Last ten sessions",
            empty: sessionPoints.isEmpty,
            emptyMessage: "Your logged reps will appear here."
        ) {
            Chart(sessionPoints) { session in
                let reps = TrainingStats.totalReps(session.sets)
                LineMark(
                    x: .value("Date", session.startedAt),
                    y: .value("Reps", reps)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(palette.accentText)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                AreaMark(
                    x: .value("Date", session.startedAt),
                    y: .value("Reps", reps)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.accent.opacity(0.24), palette.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                PointMark(
                    x: .value("Date", session.startedAt),
                    y: .value("Reps", reps)
                )
                .foregroundStyle(palette.accent)
                .symbolSize(24)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(palette.border)
                    AxisValueLabel().foregroundStyle(palette.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(palette.textTertiary)
                }
            }
            .frame(height: 150)
        }
    }

    @ViewBuilder
    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        empty: Bool,
        emptyMessage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(FormaFont.displayFont(17, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text(subtitle)
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textTertiary)
            }
            if empty {
                VStack(spacing: 6) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 20))
                        .foregroundStyle(palette.textTertiary)
                    Text(emptyMessage)
                        .font(FormaFont.bodyFont(11.5))
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            } else {
                content()
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    // MARK: - Check-ins

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Check-ins", action: (label: "Log check-in", action: { showCheckIn = true }))
            if let latest = model.latestCheckIn {
                FormaCard(style: .raised) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(latest.bodyweightKg.map { Formatters.bodyWeight(kilograms: $0, units: model.units) } ?? "No weight logged")
                                .font(FormaFont.displayFont(28, weight: .bold))
                                .foregroundStyle(palette.text)
                            Text(Formatters.longDate(latest.recordedAt))
                                .font(FormaFont.bodyFont(11))
                                .foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        if let change = weightChange {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(change)
                                    .font(FormaFont.bodyFont(13, weight: .semibold))
                                    .foregroundStyle(palette.accentText)
                                Text("since first")
                                    .font(FormaFont.bodyFont(9.5))
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                    if let notes = latest.notes, !notes.isEmpty {
                        Text(notes)
                            .font(FormaFont.bodyFont(12.5))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if weightRecords.count >= 2 {
                    checkInChart
                }
            } else {
                FormaEmptyState(
                    systemImage: "scalemass",
                    title: "No check-ins yet",
                    message: "Log bodyweight and a short note whenever you want a reference point. This is optional.",
                    actionTitle: "Log check-in",
                    action: { showCheckIn = true }
                )
            }
        }
    }

    private var weightChange: String? {
        guard let first = weightRecords.first?.bodyweightKg,
              let latest = weightRecords.last?.bodyweightKg,
              first > 0, weightRecords.count >= 2 else { return nil }
        let delta = latest - first
        guard abs(delta) >= 0.1 else { return "No change" }
        let sign = delta > 0 ? "+" : "−"
        if model.units == .kg {
            return "\(sign)\(String(format: "%.1f", abs(delta))) kg"
        }
        return "\(sign)\(String(format: "%.1f", abs(delta) * 2.2046226218)) lb"
    }

    private var checkInChart: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Bodyweight")
                    .font(FormaFont.displayFont(16, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text(model.units.abbreviation.uppercased())
                    .font(FormaFont.bodyFont(9.5, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
            }
            Chart(weightRecords.suffix(12)) { record in
                let value: Double = {
                    guard let kg = record.bodyweightKg else { return 0 }
                    return model.units == .kg ? kg : kg * 2.2046226218
                }()
                LineMark(
                    x: .value("Date", record.recordedAt),
                    y: .value("Weight", value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(palette.accentText)
                PointMark(
                    x: .value("Date", record.recordedAt),
                    y: .value("Weight", value)
                )
                .foregroundStyle(palette.accent)
                .symbolSize(22)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(palette.border)
                    AxisValueLabel().foregroundStyle(palette.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(palette.textTertiary)
                }
            }
            .frame(height: 130)
        }
        .padding(Spacing.lg)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Session history")
            if model.completedSessions.isEmpty {
                FormaEmptyState(
                    systemImage: "calendar",
                    title: "Nothing logged",
                    message: "Completed workouts appear here with the sets you actually recorded."
                )
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(model.completedSessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                VStack(spacing: 1) {
                                    Text(session.startedAt.formatted(.dateTime.day()))
                                        .font(FormaFont.displayFont(17, weight: .bold))
                                        .foregroundStyle(palette.text)
                                    Text(session.startedAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                                        .font(FormaFont.bodyFont(8.5, weight: .semibold))
                                        .foregroundStyle(palette.textTertiary)
                                }
                                .frame(width: 42, height: 42)
                                .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(FormaFont.bodyFont(14, weight: .semibold))
                                        .foregroundStyle(palette.text)
                                    Text("\(Formatters.minutesLabel(session.durationSeconds)) · \(session.sets.count) sets · \(TrainingStats.totalReps(session.sets)) reps")
                                        .font(FormaFont.bodyFont(10.5))
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
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Check-in

struct CheckInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var weight = ""
    @State private var notes = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(
                title: "Log check-in",
                subtitle: "Optional. Bodyweight is a reference point, not a score.",
                onClose: { dismiss() }
            )
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let error {
                        ErrorBanner(message: error)
                    }
                    FormaTextField(
                        label: "Bodyweight (\(model.units.abbreviation))",
                        placeholder: "Optional",
                        text: $weight,
                        keyboard: .decimalPad,
                        suffix: model.units.abbreviation
                    )
                    FormaTextEditor(
                        label: "Notes (optional)",
                        placeholder: "Energy, sleep, appetite, anything worth remembering",
                        text: $notes
                    )
                    NoticeBanner(
                        message: "Forma does not give diet plans or weight-loss targets. If bodyweight is complicated for you, skip this and focus on how you feel and perform.",
                        systemImage: "info.circle"
                    )
                }
                .padding(Spacing.xl)
            }
            .scrollIndicators(.hidden)

            PrimaryButton(title: "Save check-in", systemImage: "checkmark", isLoading: saving) {
                save()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
        .background(FormaBackground())
        .onAppear {
            if weight.isEmpty, let latest = model.latestCheckIn?.bodyweightKg {
                let value = model.units == .kg ? latest : latest * 2.2046226218
                weight = String(format: "%.1f", value)
            }
        }
    }

    private func save() {
        error = nil
        var kilograms: Double?
        let trimmed = weight.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if !trimmed.isEmpty {
            guard let entered = Double(trimmed), entered > 20, entered < 400 else {
                error = "Enter a bodyweight in \(model.units.abbreviation) or leave it blank."
                return
            }
            kilograms = model.units == .kg ? entered : entered / 2.2046226218
        }
        saving = true
        Task { @MainActor in
            do {
                _ = try await model.addCheckIn(weightKg: kilograms, notes: notes)
                Haptics.success()
                saving = false
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette

    private var grouped: [(exerciseId: String, sets: [CompletedSet])] {
        var order: [String] = []
        var dict: [String: [CompletedSet]] = [:]
        for set in session.sets {
            if dict[set.exerciseId] == nil { order.append(set.exerciseId) }
            dict[set.exerciseId, default: []].append(set)
        }
        return order.map { ($0, dict[$0]?.sorted { $0.setNumber < $1.setNumber } ?? []) }
    }

    private var totalVolume: Double? {
        let values = session.sets.compactMap { set in
            set.weightKg.map { $0 * Double(set.reps) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PageHeading(
                    eyebrow: Formatters.longDate(session.startedAt),
                    title: session.title,
                    subtitle: endedLabel
                )
                HStack(spacing: Spacing.sm) {
                    StatTile(value: Formatters.minutesLabel(session.durationSeconds), label: "Duration")
                    StatTile(value: "\(session.sets.count)", label: "Sets")
                    StatTile(value: "\(TrainingStats.totalReps(session.sets))", label: "Reps")
                }
                if let totalVolume {
                    FormaCard(style: .raised) {
                        KeyValueRow(
                            label: "Logged volume",
                            value: Formatters.weight(kilograms: totalVolume, units: model.units).replacingOccurrences(of: " kg", with: " kg total").replacingOccurrences(of: " lb", with: " lb total"),
                            valueColor: palette.accentText
                        )
                        Text("Only sets with a recorded weight are counted.")
                            .font(FormaFont.bodyFont(10.5))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if grouped.isEmpty {
                    FormaEmptyState(
                        systemImage: "list.bullet.clipboard",
                        title: "No sets recorded",
                        message: "This session was saved without completed sets."
                    )
                } else {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SectionHeader(title: "Exercises")
                        ForEach(grouped, id: \.exerciseId) { group in
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(model.exerciseName(group.exerciseId))
                                    .font(FormaFont.bodyFont(14, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                ForEach(group.sets) { set in
                                    HStack {
                                        Text("Set \(set.setNumber)")
                                            .font(FormaFont.bodyFont(12))
                                            .foregroundStyle(palette.textTertiary)
                                            .frame(width: 56, alignment: .leading)
                                        Text("\(set.reps) reps")
                                            .font(FormaFont.bodyFont(12, weight: .medium))
                                            .foregroundStyle(palette.text)
                                        Spacer()
                                        if let weightKg = set.weightKg {
                                            Text(Formatters.weight(kilograms: weightKg, units: model.units))
                                                .font(FormaFont.bodyFont(12))
                                                .foregroundStyle(palette.textSecondary)
                                        } else {
                                            Text("—")
                                                .font(FormaFont.bodyFont(12))
                                                .foregroundStyle(palette.textTertiary)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                }
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(palette.border, lineWidth: 1)
                            }
                        }
                    }
                }
                if let notes = session.notes, !notes.isEmpty {
                    FormaCard {
                        Overline(text: "Notes")
                        Text(notes)
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
    }

    private var endedLabel: String {
        let start = Formatters.time(session.startedAt)
        guard let endedAt = session.endedAt else { return start }
        return "\(start) – \(Formatters.time(endedAt))"
    }
}
