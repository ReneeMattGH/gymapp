import AVFoundation
import Observation
import SwiftUI

enum FormAnalysisPhase: Equatable {
    case setup
    case requestingPermission
    case startingCamera
    case running
    case paused
    case finishing
    case summary
    case permissionDenied
    case cameraUnavailable
    case failed(String)
}

@MainActor
@Observable
final class FormAnalysisViewModel {
    private(set) var exercise: FormAnalysisExercise
    private(set) var cameraPosition: FormCameraPosition = .front
    private(set) var phase: FormAnalysisPhase = .setup
    private(set) var permission: CameraPermissionStatus

    private(set) var tracking: FormTrackingState = .starting
    private(set) var poseFrame: PoseFrame?
    private(set) var analysis: MovementAnalysis?
    private(set) var repCount = 0
    private(set) var repPhase: RepPhase = .ready
    private(set) var canCountReps = false
    private(set) var observations: [FormObservation] = []
    private(set) var elapsed: TimeInterval = 0
    private(set) var analyzedFrames = 0
    private(set) var reliableFrames = 0
    private(set) var summary: FormAnalysisSessionSummary?
    private(set) var errorMessage: String?
    private(set) var interruptionMessage: String?
    private(set) var performanceNote: String?
    private(set) var thermalNote: String?
    private(set) var isCameraRunning = false
    private(set) var trackingInterruptions = 0
    private(set) var saveState: FormSessionSaveState = .idle
    let sessionID = IDs.uuid()

    @ObservationIgnored private let permissionManager: CameraPermissionManager
    @ObservationIgnored private let camera: CameraCapturing
    @ObservationIgnored private var pipeline: FormAnalysisPipeline?
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?
    @ObservationIgnored private var slowFrameStreak = 0
    @ObservationIgnored private var previousTracking: FormTrackingState = .starting

    init(
        exercise: FormAnalysisExercise = .squat,
        camera: CameraCapturing = CameraCaptureService(),
        permissionManager: CameraPermissionManager? = nil
    ) {
        let manager = permissionManager ?? CameraPermissionManager()
        self.exercise = exercise
        self.camera = camera
        self.permissionManager = manager
        self.permission = manager.status
        observeThermalState()
    }

    // MARK: - Presentation

    var previewLayer: AVCaptureVideoPreviewLayer { camera.previewLayer }

    var coverage: Double? {
        guard analyzedFrames > 0 else { return nil }
        return Double(reliableFrames) / Double(analyzedFrames)
    }

    var repCountingReliable: Bool {
        tracking == .tracking && canCountReps
    }

    var latestObservation: FormObservation? {
        observations.last
    }

    var canConfigure: Bool {
        switch phase {
        case .setup, .permissionDenied, .cameraUnavailable, .failed:
            return true
        default:
            return false
        }
    }

    var canStart: Bool {
        guard canConfigure else { return false }
        switch permission {
        case .unavailable, .denied, .restricted:
            return false
        case .authorized, .notDetermined:
            return true
        }
    }

    func refreshPermission() {
        permissionManager.refresh()
        permission = permissionManager.status
        if phase == .cameraUnavailable, permission != .unavailable {
            phase = .setup
        }
    }

    func selectExercise(_ newExercise: FormAnalysisExercise) {
        guard canConfigure else { return }
        exercise = newExercise
    }

    func selectCameraPosition(_ position: FormCameraPosition) {
        guard canConfigure else { return }
        cameraPosition = position
    }

    // MARK: - Lifecycle

    func start() async {
        guard canConfigure else { return }
        summary = nil
        errorMessage = nil
        interruptionMessage = nil
        performanceNote = nil
        slowFrameStreak = 0
        observations = []
        poseFrame = nil
        repCount = 0
        analyzedFrames = 0
        reliableFrames = 0
        elapsed = 0
        tracking = .starting
        previousTracking = .starting
        trackingInterruptions = 0
        saveState = .idle

        phase = .requestingPermission
        let status = await permissionManager.requestIfNeeded()
        permission = status

        switch status {
        case .authorized:
            await launchCamera()
        case .denied, .restricted:
            phase = .permissionDenied
        case .unavailable:
            phase = .cameraUnavailable
        case .notDetermined:
            phase = .setup
        }
    }

    func pause() {
        guard phase == .running else { return }
        pipeline?.setPaused(true)
        phase = .paused
        interruptionMessage = nil
    }

    func resume() async {
        guard phase == .paused else { return }
        if !isCameraRunning {
            do {
                try await camera.start(position: cameraPosition)
                isCameraRunning = true
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }
        pipeline?.setPaused(false)
        interruptionMessage = nil
        phase = .running
    }

    func end() async {
        guard phase == .running || phase == .paused else { return }
        phase = .finishing
        pipeline?.setPaused(true)
        camera.onFrame = nil
        camera.onInterruption = nil
        if isCameraRunning {
            await camera.stop()
            isCameraRunning = false
        }
        if let pipeline {
            summary = pipeline.finish(trackingInterruptions: trackingInterruptions)
            self.pipeline = nil
        }
        poseFrame = nil
        analysis = nil
        phase = .summary
    }

    func endAndSave(using model: AppModel) async {
        await end()
        await save(using: model)
    }

    func save(using model: AppModel) async {
        guard let summary, saveState != .saving else { return }
        saveState = .saving
        saveState = await model.saveFormAnalysisSession(summary, sessionID: sessionID)
    }

    func shutdown() async {
        pipeline?.setPaused(true)
        camera.onFrame = nil
        camera.onInterruption = nil
        if isCameraRunning {
            await camera.stop()
            isCameraRunning = false
        }
        pipeline = nil
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
    }

    func handleScenePhase(_ newPhase: ScenePhase) {
        switch newPhase {
        case .inactive, .background:
            guard phase == .running else { return }
            pause()
            interruptionMessage = "Camera paused while the app is in the background. Tap Resume when you are ready."
            Task {
                await camera.stop()
                isCameraRunning = false
            }
        default:
            break
        }
    }

    // MARK: - Camera

    private func launchCamera() async {
        phase = .startingCamera
        errorMessage = nil

        let pipeline = FormAnalysisPipeline(exercise: exercise, cameraPosition: cameraPosition)
        pipeline.onUpdate = { [weak self] update in
            Task { @MainActor [weak self] in
                self?.apply(update)
            }
        }
        self.pipeline = pipeline

        camera.onFrame = { [weak pipeline] frame in
            pipeline?.process(frame)
        }
        camera.onInterruption = { [weak self] interruption in
            Task { @MainActor [weak self] in
                self?.handle(interruption)
            }
        }
        applyThermalState()

        do {
            try await camera.start(position: cameraPosition)
            isCameraRunning = true
            tracking = .starting
            phase = .running
        } catch {
            isCameraRunning = false
            self.pipeline = nil
            camera.onFrame = nil
            camera.onInterruption = nil
            if let captureError = error as? CameraCaptureError, case .permissionDenied = captureError {
                phase = .permissionDenied
            } else if let captureError = error as? CameraCaptureError, case .deviceUnavailable = captureError {
                phase = .cameraUnavailable
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ update: FormAnalysisUpdate) {
        guard phase == .running || phase == .paused || phase == .startingCamera else { return }

        if previousTracking == .tracking, update.tracking != .tracking {
            trackingInterruptions += 1
        }
        previousTracking = update.tracking
        tracking = update.tracking
        poseFrame = update.poseFrame
        analysis = update.analysis
        repCount = update.repCount
        repPhase = update.phase
        canCountReps = update.canCountReps
        observations = update.recentObservations
        elapsed = update.elapsed
        analyzedFrames = update.analyzedFrames
        reliableFrames = update.reliableFrames
        if let message = update.message {
            errorMessage = message
        }

        if update.slowProcessing {
            slowFrameStreak += 1
            if slowFrameStreak >= 5 {
                performanceNote = "Analysis is running slowly on this device. Frames are being dropped to keep the preview responsive."
            }
        } else {
            slowFrameStreak = 0
            performanceNote = nil
        }
    }

    private func handle(_ interruption: CameraInterruption) {
        switch interruption {
        case .began(let reason):
            guard phase == .running else { return }
            trackingInterruptions += 1
            pipeline?.setPaused(true)
            phase = .paused
            interruptionMessage = "\(reason) Analysis is paused until the camera returns."
        case .ended:
            guard phase == .paused, interruptionMessage != nil else { return }
            pipeline?.setPaused(false)
            interruptionMessage = nil
            phase = .running
        case .runtimeError(let message):
            errorMessage = message
            if phase == .running {
                trackingInterruptions += 1
                pipeline?.setPaused(true)
                phase = .paused
            }
            interruptionMessage = "The camera stopped: \(message)"
        }
    }

    // MARK: - Device state

    private func observeThermalState() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyThermalState()
            }
        }
    }

    private func applyThermalState() {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            camera.setAnalysisInterval(0.25)
            thermalNote = "The device is warm. Analysis was slowed to protect performance."
        default:
            camera.setAnalysisInterval(0.1)
            thermalNote = nil
        }
    }
}
