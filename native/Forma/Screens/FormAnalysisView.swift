import SwiftUI

struct FormAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel

    @State private var viewModel: FormAnalysisViewModel
    @State private var confirmEnd = false

    init(preferredExercise: FormAnalysisExercise? = nil) {
        _viewModel = State(initialValue: FormAnalysisViewModel(exercise: preferredExercise ?? .squat))
    }

    var body: some View {
        content
            .interactiveDismissDisabled(blocksDismissal)
            .confirmationDialog("End form analysis?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End and review", role: .destructive) {
                    Task { await viewModel.endAndSave(using: appModel) }
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("The camera will stop. The measured summary is saved to your workout history.")
            }
            .onChange(of: scenePhase) { _, newPhase in
                viewModel.handleScenePhase(newPhase)
            }
            .onDisappear {
                Task { await viewModel.shutdown() }
            }
    }

    private var blocksDismissal: Bool {
        switch viewModel.phase {
        case .running, .paused, .startingCamera, .finishing:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .setup, .requestingPermission, .permissionDenied, .cameraUnavailable, .failed:
            FormAnalysisSetupView(
                viewModel: viewModel,
                dismiss: { dismiss() },
                start: { Task { await viewModel.start() } }
            )
        case .startingCamera:
            FormAnalysisLoadingView(
                title: "Starting camera…",
                detail: "The first launch can take a moment while iOS prepares the camera.",
                cancel: {
                    Task {
                        await viewModel.shutdown()
                        dismiss()
                    }
                }
            )
        case .running, .paused:
            FormAnalysisLiveView(
                viewModel: viewModel,
                onEnd: { confirmEnd = true },
                onClose: { confirmEnd = true }
            )
        case .finishing:
            FormAnalysisLoadingView(title: "Preparing your summary…", detail: nil, cancel: nil)
        case .summary:
            if let summary = viewModel.summary {
                FormAnalysisSessionSummaryView(
                    summary: summary,
                    saveState: viewModel.saveState,
                    retrySave: { Task { await viewModel.save(using: appModel) } },
                    dismiss: { dismiss() }
                )
            } else {
                FormAnalysisLoadingView(title: "Preparing your summary…", detail: nil, cancel: nil)
            }
        }
    }
}

// MARK: - Setup

private struct FormAnalysisSetupView: View {
    let viewModel: FormAnalysisViewModel
    let dismiss: () -> Void
    let start: () -> Void

    @Environment(\.formaPalette) private var palette
    @Environment(\.openURL) private var openURL

    private var startTitle: String {
        switch viewModel.permission {
        case .notDetermined: return "Allow camera & start"
        case .authorized: return "Start analysis"
        default: return "Start analysis"
        }
    }

    private var isWorking: Bool {
        viewModel.phase == .requestingPermission
    }

    var body: some View {
        ZStack {
            FormaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    HStack {
                        Wordmark()
                        Spacer()
                        IconButton(systemImage: "xmark", label: "Close form analysis") {
                            dismiss()
                        }
                    }

                    PageHeading(
                        eyebrow: "Form analysis",
                        title: "Check your form",
                        subtitle: "Real-time body tracking on this iPhone. Frames are analysed in memory and never uploaded."
                    )

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    permissionSection
                    exerciseSection
                    cameraSection
                    setupSection
                    privacySection

                    if viewModel.permission == .denied || viewModel.permission == .restricted {
                        SecondaryButton(title: "Open Settings", systemImage: "gearshape") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }

                    PrimaryButton(
                        title: startTitle,
                        systemImage: "camera.fill",
                        isLoading: isWorking,
                        isDisabled: !viewModel.canStart || isWorking
                    ) {
                        start()
                    }

                    Text("Stand 2–3 m from the phone. You can pause or end the session at any time.")
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { viewModel.refreshPermission() }
    }

    @ViewBuilder
    private var permissionSection: some View {
        switch viewModel.permission {
        case .notDetermined:
            NoticeBanner(message: viewModel.permission.message, systemImage: "camera.badge.ellipsis")
        case .authorized:
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.accentText)
                Text("Camera access granted")
                    .font(FormaFont.bodyFont(12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        case .denied, .restricted:
            ErrorBanner(message: viewModel.permission.message)
        case .unavailable:
            NoticeBanner(message: viewModel.permission.message, systemImage: "video.slash")
        }
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Exercise")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
                spacing: Spacing.md
            ) {
                ForEach(FormAnalysisExercise.allCases) { exercise in
                    exerciseCard(exercise)
                }
            }
        }
    }

    private func exerciseCard(_ exercise: FormAnalysisExercise) -> some View {
        let selected = viewModel.exercise == exercise
        return Button {
            Haptics.selection()
            viewModel.selectExercise(exercise)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: exercise.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.accentText)
                        .frame(width: 34, height: 34)
                        .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(palette.accentText)
                    }
                }
                Text(exercise.title)
                    .font(FormaFont.bodyFont(13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(exercise.framingHint)
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(selected ? palette.accentSoft : palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(selected ? palette.accentBorder : palette.border, lineWidth: 1)
            }
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(!viewModel.canConfigure)
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Camera")
            HStack(spacing: Spacing.md) {
                ForEach(FormCameraPosition.allCases) { position in
                    let selected = viewModel.cameraPosition == position
                    Button {
                        Haptics.selection()
                        viewModel.selectCameraPosition(position)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(position.label)
                                .font(FormaFont.bodyFont(12.5, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text(position.detail)
                                .font(FormaFont.bodyFont(10.5))
                                .foregroundStyle(palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .background(selected ? palette.accentSoft : palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(selected ? palette.accentBorder : palette.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(PressableScaleStyle())
                    .disabled(!viewModel.canConfigure)
                }
            }
        }
    }

    private var setupSection: some View {
        FormaCard {
            Overline(text: "Camera placement")
            ForEach(Array(viewModel.exercise.setupSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Spacing.md) {
                    Text("\(index + 1)")
                        .font(FormaFont.bodyFont(10.5, weight: .semibold))
                        .foregroundStyle(palette.accentText)
                        .frame(width: 22, height: 22)
                        .background(palette.accentSoft, in: Circle())
                    Text(step)
                        .font(FormaFont.bodyFont(12.5))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.accentText)
                    .padding(.top, 2)
                Text(viewModel.exercise.framingHint)
                    .font(FormaFont.bodyFont(11.5))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacySection: some View {
        FormaCard(style: .raised) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.accentText)
                Overline(text: "Privacy")
            }
            privacyLine("Frames are processed in memory with Apple's on-device Vision framework.")
            privacyLine("No video or audio is recorded, saved or written to disk.")
            privacyLine("Frames and joint coordinates are never uploaded, saved, or shared.")
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Circle()
                .fill(palette.accentText)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(text)
                .font(FormaFont.bodyFont(11.5))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Live

private struct FormAnalysisLiveView: View {
    let viewModel: FormAnalysisViewModel
    let onEnd: () -> Void
    let onClose: () -> Void

    @Environment(\.formaPalette) private var palette

    private let lime = Color(hex: 0xC7FA4F)
    private let amber = Color(hex: 0xF2C46B)
    private let salmon = Color(hex: 0xFFB199)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(
                previewLayer: viewModel.previewLayer,
                poseFrame: viewModel.poseFrame,
                isLimited: viewModel.tracking != .tracking
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomPanel
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)

            if viewModel.phase == .paused {
                pausedOverlay
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Button {
                Haptics.light()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.38), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel("End form analysis")

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.exercise.title)
                    .font(FormaFont.displayFont(19, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(viewModel.cameraPosition.label) · \(timeText)")
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor(viewModel.tracking))
                    .frame(width: 6, height: 6)
                Text(viewModel.tracking.label.uppercased())
                    .font(FormaFont.bodyFont(8.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.black.opacity(0.38), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("REPS")
                        .font(FormaFont.bodyFont(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.55))
                    if viewModel.repCountingReliable {
                        Text("\(viewModel.repCount)")
                            .font(FormaFont.displayFont(58, weight: .bold))
                            .foregroundStyle(lime)
                            .contentTransition(.numericText())
                    } else {
                        Text("—")
                            .font(FormaFont.displayFont(58, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(viewModel.repCountingReliable ? "Rep counting active" : "Rep counting paused")
                        .font(FormaFont.bodyFont(10.5, weight: .semibold))
                        .foregroundStyle(viewModel.repCountingReliable ? lime : amber)
                    if let observation = viewModel.latestObservation {
                        statusBadge(observation.status)
                    }
                }
                .padding(.top, 4)
            }

            if !viewModel.repCountingReliable {
                Text(FormAnalysisText.repCountingPaused)
                    .font(FormaFont.bodyFont(11.5))
                    .foregroundStyle(amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            feedbackCard

            HStack(spacing: Spacing.md) {
                Button {
                    Haptics.light()
                    Task {
                        if viewModel.phase == .paused {
                            await viewModel.resume()
                        } else {
                            viewModel.pause()
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: viewModel.phase == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(viewModel.phase == .paused ? "Resume" : "Pause")
                            .font(FormaFont.bodyFont(13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }
                }
                .buttonStyle(PressableScaleStyle())

                Button {
                    Haptics.light()
                    onEnd()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("End")
                            .font(FormaFont.bodyFont(13, weight: .semibold))
                    }
                    .foregroundStyle(palette.accentInk)
                    .frame(width: 118)
                    .frame(height: 46)
                    .background(palette.accentGradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle())
            }

            if let note = viewModel.performanceNote ?? viewModel.thermalNote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text(note)
                        .font(FormaFont.bodyFont(10.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(Spacing.lg)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var feedbackCard: some View {
        if let observation = viewModel.latestObservation {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(observation.status))
                        .frame(width: 5, height: 5)
                    Text(observation.status.label.uppercased())
                        .font(FormaFont.bodyFont(8.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(observation.text)
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let limitation = observation.limitation {
                    Text(limitation)
                        .font(FormaFont.bodyFont(10.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            Text("Move your whole body into the frame to begin.")
                .font(FormaFont.bodyFont(12.5))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var pausedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(palette.accentText)
                Text("Analysis paused")
                    .font(FormaFont.displayFont(24, weight: .bold))
                    .foregroundStyle(palette.text)
                Text(viewModel.interruptionMessage ?? "The camera is paused. Reps counted so far are kept.")
                    .font(FormaFont.bodyFont(12.5))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Resume", systemImage: "play.fill") {
                    Task { await viewModel.resume() }
                }
                .padding(.top, Spacing.xs)
                TextButton(title: "End session", action: onEnd)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 380)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
            .padding(Spacing.xl)
        }
    }

    private var timeText: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func statusColor(_ state: FormTrackingState) -> Color {
        switch state {
        case .tracking: return lime
        case .limited: return amber
        case .noBody, .multiplePeople: return salmon
        case .paused, .starting: return .white.opacity(0.65)
        }
    }

    private func statusColor(_ status: FeedbackStatus) -> Color {
        switch status {
        case .reliable: return lime
        case .limited: return amber
        case .unavailable: return salmon
        }
    }

    private func statusBadge(_ status: FeedbackStatus) -> some View {
        Text(status.label.uppercased())
            .font(FormaFont.bodyFont(8, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.14), in: Capsule())
    }
}

// MARK: - Summary

struct FormAnalysisSessionSummaryView: View {
    let summary: FormAnalysisSessionSummary
    let saveState: FormSessionSaveState
    let retrySave: () -> Void
    let dismiss: () -> Void

    @Environment(\.formaPalette) private var palette

    var body: some View {
        ZStack {
            FormaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    HStack {
                        Wordmark()
                        Spacer()
                        IconButton(systemImage: "xmark", label: "Close summary") {
                            dismiss()
                        }
                    }

                    PageHeading(
                        eyebrow: "Session complete",
                        title: summary.exercise.title,
                        subtitle: "\(summary.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(summary.cameraPosition.label.lowercased())"
                    )

                    saveStateBanner
                    repCard
                    statsRow
                    observationsSection
                    limitationsSection

                    PrimaryButton(title: "Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var saveStateBanner: some View {
        switch saveState {
        case .idle, .saving:
            NoticeBanner(message: "Saving this session to your workout history…", systemImage: "arrow.triangle.2.circlepath")
        case .saved:
            NoticeBanner(message: "Saved to your workout history.", systemImage: "checkmark.circle")
        case .queued:
            NoticeBanner(
                message: "Saved on this iPhone. The upload failed, so this session will retry automatically. No measured data was lost.",
                systemImage: "wifi.slash"
            )
        case .failed(let message):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ErrorBanner(message: message)
                SecondaryButton(title: "Try saving again", systemImage: "arrow.clockwise") {
                    retrySave()
                }
            }
        }
    }

    private var repCard: some View {
        FormaCard(style: .accent) {
            Overline(text: "Repetitions")
            if let count = summary.repCount {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text("\(count)")
                        .font(FormaFont.displayFont(54, weight: .bold))
                        .foregroundStyle(palette.text)
                    Text("counted")
                        .font(FormaFont.bodyFont(13, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                Text("Counted only after a settled start, a held bottom position and a full return.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                if !summary.repCountingReliable {
                    Text("Tracking was reliable for less than half of the session, so this count may be incomplete.")
                        .font(FormaFont.bodyFont(11.5))
                        .foregroundStyle(palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(FormAnalysisText.repCountingUnavailable)
                    .font(FormaFont.bodyFont(14, weight: .semibold))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No number is shown because no reliable tracking was available.")
                    .font(FormaFont.bodyFont(11.5))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statsRow: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
            spacing: Spacing.md
        ) {
            summaryStat(value: durationText, label: "duration")
            summaryStat(value: summary.availability.label, label: "analysis quality")
            summaryStat(value: coverageText, label: "reliable frames")
            summaryStat(value: "\(summary.trackingInterruptions)", label: "tracking gaps")
        }
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(FormaFont.displayFont(19, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(FormaFont.bodyFont(10.5))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private var observationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "What the camera measured")
            if summary.observations.isEmpty {
                FormaEmptyState(
                    systemImage: "eye.slash",
                    title: "No reliable observations",
                    message: "The camera did not see enough reliable frames to describe this session. No estimate is shown instead."
                )
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(summary.observations) { observation in
                        FormAnalysisObservationRow(observation: observation)
                    }
                }
            }
        }
    }

    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "What this could not assess")
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(summary.limitations, id: \.self) { limitation in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 3)
                        Text(limitation)
                            .font(FormaFont.bodyFont(11.5))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("No video, frames or joint coordinates were recorded, saved or uploaded during this session.")
                .font(FormaFont.bodyFont(10.5))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var durationText: String {
        let seconds = Int(summary.duration.rounded())
        if seconds >= 60 {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
        return "\(seconds)s"
    }

    private var coverageText: String {
        guard let coverage = summary.coverage else { return "—" }
        return "\(Int((coverage * 100).rounded()))%"
    }
}

struct FormAnalysisObservationRow: View {
    let observation: FormObservation
    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(observation.status.label.uppercased())
                    .font(FormaFont.bodyFont(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(observation.kind == .rep ? "REP" : "TRACKING")
                    .font(FormaFont.bodyFont(8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(observation.text)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let measurements = observation.measurementSummary {
                Text("Measured: \(measurements)")
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !observation.joints.isEmpty {
                Text("Body points: \(observation.joints.map(\.displayName).joined(separator: ", "))")
                    .font(FormaFont.bodyFont(10))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let limitation = observation.limitation {
                Text(limitation)
                    .font(FormaFont.bodyFont(10.5))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var tint: Color {
        switch observation.status {
        case .reliable: return palette.accentText
        case .limited: return palette.warning
        case .unavailable: return palette.danger
        }
    }
}

// MARK: - Consent and loading

private struct FormAnalysisLoadingView: View {
    let title: String
    let detail: String?
    let cancel: (() -> Void)?

    @Environment(\.formaPalette) private var palette

    var body: some View {
        ZStack {
            FormaBackground()
            VStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(palette.accentText)
                Text(title)
                    .font(FormaFont.displayFont(20, weight: .semibold))
                    .foregroundStyle(palette.text)
                if let detail {
                    Text(detail)
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let cancel {
                    TextButton(title: "Cancel", action: cancel)
                        .padding(.top, Spacing.sm)
                }
            }
            .padding(Spacing.xl)
        }
    }
}
