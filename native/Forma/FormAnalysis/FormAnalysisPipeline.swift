import Foundation
import QuartzCore

enum FormTrackingState: String, Equatable, Sendable {
    case starting, noBody, tracking, limited, multiplePeople, paused

    var label: String {
        switch self {
        case .starting: return "Starting camera"
        case .noBody: return "No body detected"
        case .tracking: return "Tracking"
        case .limited: return "Limited tracking"
        case .multiplePeople: return "More than one person"
        case .paused: return "Paused"
        }
    }
}

struct FormAnalysisUpdate: Equatable, Sendable {
    var poseFrame: PoseFrame?
    var analysis: MovementAnalysis?
    var repCount: Int
    var phase: RepPhase
    var tracking: FormTrackingState
    var canCountReps: Bool
    var recentObservations: [FormObservation]
    var analyzedFrames: Int
    var reliableFrames: Int
    var elapsed: TimeInterval
    var processingTime: TimeInterval
    var slowProcessing: Bool
    var message: String?
}

/// Runs detection → smoothing → exercise analysis → rep counting → feedback on a
/// serial queue. Frames arrive at a throttled rate from the capture service, and
/// the queue itself provides backpressure: a slow frame simply causes the camera
/// to drop later frames instead of building a backlog.
final class FormAnalysisPipeline: @unchecked Sendable {
    var onUpdate: ((FormAnalysisUpdate) -> Void)?

    private let detector: PoseDetecting
    private let analyzer: ExerciseMovementAnalyzing
    private let smoother = PoseSmoothingService()
    private let repEngine: RepCountingEngine
    private let feedback = FormFeedbackEngine()
    private let recorder: FormAnalysisSessionRecorder
    private let processQueue = DispatchQueue(label: "coforma.formanalysis.pipeline", qos: .userInitiated)
    private let stateLock = NSLock()

    private let startedAt: Date
    private let cameraPosition: FormCameraPosition

    private var paused = false
    private var pendingReset = false
    private var lastProcessingTime: TimeInterval = 0
    private var recent: [FormObservation] = []

    private var currentRepMetrics = RepMetricSummary()
    private var currentRepFrames = 0
    private var currentRepReliableFrames = 0
    private var currentRepConfidences: [Double] = []
    private var lastRejectionAt: TimeInterval = -.infinity
    private var lastErrorAt: TimeInterval = -.infinity
    private var lastTimestamp: TimeInterval = 0

    init(
        exercise: FormAnalysisExercise,
        cameraPosition: FormCameraPosition,
        detector: PoseDetecting = VisionPoseDetector(),
        startedAt: Date = Date()
    ) {
        self.detector = detector
        self.analyzer = ExerciseAnalyzerFactory.make(for: exercise)
        self.repEngine = RepCountingEngine(configuration: exercise.repConfiguration)
        self.recorder = FormAnalysisSessionRecorder(exercise: exercise, cameraPosition: cameraPosition, startedAt: startedAt)
        self.startedAt = startedAt
        self.cameraPosition = cameraPosition
    }

    var exercise: FormAnalysisExercise { analyzer.exercise }

    func setPaused(_ value: Bool) {
        stateLock.lock()
        paused = value
        if !value {
            pendingReset = true
        }
        stateLock.unlock()
    }

    func process(_ cameraFrame: CameraVideoFrame) {
        processQueue.sync {
            stateLock.lock()
            let isPaused = paused
            let needsReset = pendingReset
            pendingReset = false
            stateLock.unlock()

            guard !isPaused else { return }
            if needsReset {
                smoother.reset()
                repEngine.reset(keepingCount: true)
                feedback.reset()
                beginRepMetrics()
                recent.removeAll()
            }

            let start = CACurrentMediaTime()
            do {
                let raw = try detector.detect(
                    pixelBuffer: cameraFrame.pixelBuffer,
                    orientation: cameraFrame.orientation,
                    videoSize: cameraFrame.videoSize,
                    timestamp: cameraFrame.timestamp
                )
                let smoothed = smoother.smooth(raw)
                handle(pose: smoothed)
            } catch {
                handleError(error, timestamp: cameraFrame.timestamp)
            }
            let duration = CACurrentMediaTime() - start
            lastProcessingTime = lastProcessingTime == 0 ? duration : lastProcessingTime * 0.85 + duration * 0.15
        }
    }

    func finish(trackingInterruptions: Int = 0) -> FormAnalysisSessionSummary {
        processQueue.sync {
            recorder.summary(
                endedAt: Date(),
                repCount: repEngine.count,
                trackingInterruptions: trackingInterruptions
            )
        }
    }

    // MARK: - Processing

    private func handle(pose: PoseFrame) {
        lastTimestamp = pose.timestamp
        let analysis = analyzer.analyze(pose)
        recorder.record(frame: analysis)

        let phaseBefore = repEngine.phase
        let signal = analysis.canCountReps ? analysis.signal : nil
        let confidence = analysis.canCountReps ? analysis.signalConfidence : 0
        let update = repEngine.update(signal: signal, confidence: confidence, timestamp: pose.timestamp)
        let phaseAfter = repEngine.phase

        if phaseBefore == .ready, phaseAfter == .descending {
            beginRepMetrics()
        }
        if analysis.signal != nil, phaseAfter != .ready || update.completed != nil {
            accumulate(analysis)
        }
        if let boundary = update.completed {
            completeRep(boundary: boundary)
        }
        if update.rejectedIncompleteRep {
            reportRejectedMovement(timestamp: pose.timestamp)
        }

        if let tracking = feedback.trackingObservation(for: analysis) {
            append([tracking])
        }

        let state = trackingState(pose: pose, analysis: analysis)
        let displayPose = state == .tracking || state == .limited ? pose : nil
        publish(
            FormAnalysisUpdate(
                poseFrame: displayPose,
                analysis: analysis,
                repCount: repEngine.count,
                phase: phaseAfter,
                tracking: state,
                canCountReps: analysis.canCountReps,
                recentObservations: recent,
                analyzedFrames: recorder.analyzedFrames,
                reliableFrames: recorder.reliableFrames,
                elapsed: Date().timeIntervalSince(startedAt),
                processingTime: lastProcessingTime,
                slowProcessing: lastProcessingTime > 0.18,
                message: nil
            )
        )
    }

    private func handleError(_ error: Error, timestamp: TimeInterval) {
        let now = CACurrentMediaTime()
        guard now - lastErrorAt >= 3 else { return }
        lastErrorAt = now
        let observation = FormObservation(
            id: "pipeline-error-\(Int(now))",
            status: .unavailable,
            text: "Pose analysis failed on a frame. Tracking will retry with the next frame.",
            joints: [],
            limitation: error.localizedDescription,
            timestamp: timestamp,
            kind: .tracking,
            exercise: analyzer.exercise
        )
        append([observation])
        publish(
            FormAnalysisUpdate(
                poseFrame: nil,
                analysis: nil,
                repCount: repEngine.count,
                phase: repEngine.phase,
                tracking: .limited,
                canCountReps: false,
                recentObservations: recent,
                analyzedFrames: recorder.analyzedFrames,
                reliableFrames: recorder.reliableFrames,
                elapsed: Date().timeIntervalSince(startedAt),
                processingTime: lastProcessingTime,
                slowProcessing: lastProcessingTime > 0.18,
                message: "Pose analysis hit an error and will retry."
            )
        )
    }

    private func trackingState(pose: PoseFrame, analysis: MovementAnalysis) -> FormTrackingState {
        if pose.hasAmbiguousPeople { return .multiplePeople }
        switch analysis.reliability {
        case .reliable: return .tracking
        case .limited: return .limited
        case .unavailable:
            return pose.usableJointCount == 0 ? .noBody : .limited
        }
    }

    private func completeRep(boundary: CompletedRepBoundary) {
        let averageConfidence = currentRepConfidences.isEmpty
            ? 0
            : currentRepConfidences.reduce(0, +) / Double(currentRepConfidences.count)
        let rep = RepObservation(
            exercise: analyzer.exercise,
            boundary: boundary,
            metrics: currentRepMetrics,
            averageConfidence: averageConfidence,
            totalFrameCount: max(1, currentRepFrames),
            reliableFrameCount: currentRepReliableFrames,
            measuredJoints: analyzer.exercise.requiredJoints,
            hadTrackingLoss: currentRepReliableFrames < currentRepFrames
        )
        recorder.record(rep: rep)
        append(feedback.observations(for: rep))
        beginRepMetrics()
    }

    private func accumulate(_ analysis: MovementAnalysis) {
        currentRepMetrics.record(analysis.metrics)
        currentRepFrames += 1
        if analysis.reliability == .reliable {
            currentRepReliableFrames += 1
        }
        if let signal = analysis.signal, signal.isFinite {
            currentRepConfidences.append(analysis.signalConfidence)
        }
    }

    private func beginRepMetrics() {
        currentRepMetrics = RepMetricSummary()
        currentRepFrames = 0
        currentRepReliableFrames = 0
        currentRepConfidences = []
    }

    private func reportRejectedMovement(timestamp: TimeInterval) {
        guard timestamp - lastRejectionAt >= 2 else { return }
        lastRejectionAt = timestamp
        beginRepMetrics()
        let observation = FormObservation(
            id: "rejected-\(Int(timestamp * 10))",
            status: .limited,
            text: "A movement was detected but did not complete a full range, so it was not counted.",
            joints: analyzer.exercise.requiredJoints,
            limitation: "A rep counts only after a settled start, a held bottom position and a return to the top.",
            timestamp: timestamp,
            kind: .rep,
            exercise: analyzer.exercise
        )
        append([observation])
    }

    private func append(_ observations: [FormObservation]) {
        guard !observations.isEmpty else { return }
        recorder.record(observations: observations)
        recent.append(contentsOf: observations)
        if recent.count > 6 {
            recent.removeFirst(recent.count - 6)
        }
    }

    private func publish(_ update: FormAnalysisUpdate) {
        onUpdate?(update)
    }
}
