import AVFoundation
import CoreGraphics
import Foundation

enum FormCameraPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case front, back

    var id: String { rawValue }

    var label: String {
        switch self {
        case .front: return "Front camera"
        case .back: return "Back camera"
        }
    }

    var detail: String {
        switch self {
        case .front: return "Use when the screen faces you on a stand."
        case .back: return "Use when someone holds the phone facing you."
        }
    }

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back: return .back
        }
    }
}

struct CameraVideoFrame: @unchecked Sendable {
    var pixelBuffer: CVPixelBuffer
    var timestamp: TimeInterval
    var orientation: CGImagePropertyOrientation
    /// Size of the oriented (portrait) image used for skeleton alignment.
    var videoSize: CGSize
}

enum CameraInterruption: Equatable, Sendable {
    case began(String)
    case ended
    case runtimeError(String)
}

enum CameraCaptureError: LocalizedError {
    case permissionDenied
    case deviceUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera access has not been granted."
        case .deviceUnavailable: return "No camera is available on this device."
        case .configurationFailed(let detail): return "The camera could not start: \(detail)"
        }
    }
}

protocol CameraCapturing: AnyObject {
    var previewLayer: AVCaptureVideoPreviewLayer { get }
    var onFrame: ((CameraVideoFrame) -> Void)? { get set }
    var onInterruption: ((CameraInterruption) -> Void)? { get set }

    func start(position: FormCameraPosition) async throws
    func stop() async
    func setAnalysisInterval(_ interval: TimeInterval)
}

/// AVFoundation capture with a 720p video-data output. Buffers stay in the
/// sensor orientation; Vision receives the matching image orientation. The
/// preview is rotated to portrait and left unmirrored so the skeleton maps
/// onto it deterministically.
final class CameraCaptureService: NSObject, CameraCapturing, @unchecked Sendable {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "coforma.camera.session")
    private let videoQueue = DispatchQueue(label: "coforma.camera.video", qos: .userInitiated)
    private let stateLock = NSLock()

    private var output: AVCaptureVideoDataOutput?
    private var configuredPosition: FormCameraPosition?
    private let analysisFrameIntervalLock = NSLock()
    private var analysisInterval: TimeInterval = 0.1
    private var lastDeliveredAt: TimeInterval = 0

    private var frameHandler: ((CameraVideoFrame) -> Void)?
    private var interruptionHandler: ((CameraInterruption) -> Void)?

    override init() {
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
        registerNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var onFrame: ((CameraVideoFrame) -> Void)? {
        get { withLock { frameHandler } }
        set { withLock { frameHandler = newValue } }
    }

    var onInterruption: ((CameraInterruption) -> Void)? {
        get { withLock { interruptionHandler } }
        set { withLock { interruptionHandler = newValue } }
    }

    func setAnalysisInterval(_ interval: TimeInterval) {
        analysisFrameIntervalLock.lock()
        analysisInterval = max(0.05, interval)
        analysisFrameIntervalLock.unlock()
    }

    func start(position: FormCameraPosition) async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraCaptureError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configure(position: position)
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    DispatchQueue.main.async {
                        self.configurePreviewLayer()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.output?.setSampleBufferDelegate(nil, queue: nil)
                self.session.beginConfiguration()
                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                for output in self.session.outputs {
                    self.session.removeOutput(output)
                }
                self.output = nil
                self.configuredPosition = nil
                self.session.commitConfiguration()
                self.withLock { self.lastDeliveredAt = 0 }
                DispatchQueue.main.async {
                    self.previewLayer.session = nil
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Configuration

    private func configure(position: FormCameraPosition) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        if let existing = session.inputs.first as? AVCaptureDeviceInput {
            if configuredPosition == position {
                return
            }
            session.removeInput(existing)
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.avPosition) else {
            throw CameraCaptureError.deviceUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraCaptureError.configurationFailed(error.localizedDescription)
        }
        guard session.canAddInput(input) else {
            throw CameraCaptureError.configurationFailed("The camera input could not be added.")
        }
        session.addInput(input)

        if output == nil {
            let dataOutput = AVCaptureVideoDataOutput()
            dataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(dataOutput) else {
                throw CameraCaptureError.configurationFailed("The video output could not be added.")
            }
            session.addOutput(dataOutput)
            output = dataOutput
        }

        if let connection = output?.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        configuredPosition = position
    }

    private func configurePreviewLayer() {
        previewLayer.videoGravity = .resizeAspectFill
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    // MARK: - Notifications

    private func registerNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sessionWasInterrupted(_:)), name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)), name: AVCaptureSession.interruptionEndedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionRuntimeError(_:)), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        let reasonNumber = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
        let reason = reasonNumber.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
        let message: String
        switch reason {
        case .videoDeviceInUseByAnotherClient:
            message = "The camera is being used by another app."
        case .videoDeviceNotAvailableInBackground:
            message = "The camera paused while the app was in the background."
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            message = "The camera paused because the app is sharing the screen."
        case .videoDeviceNotAvailableDueToSystemPressure:
            message = "The camera paused because the device is under pressure."
        default:
            message = "The camera was interrupted."
        }
        interruptionHandler?(.began(message))
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        interruptionHandler?(.ended)
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        interruptionHandler?(.runtimeError(error?.localizedDescription ?? "The camera stopped unexpectedly."))
    }

    // MARK: - Locking helper

    private func withLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        analysisFrameIntervalLock.lock()
        let interval = analysisInterval
        analysisFrameIntervalLock.unlock()

        let shouldDeliver: Bool = withLock {
            guard now - lastDeliveredAt >= interval else { return false }
            lastDeliveredAt = now
            return true
        }
        guard shouldDeliver else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let presentation = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let timestamp = presentation.isFinite && presentation > 0 ? presentation : now
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        let isLandscapeBuffer = width > height
        let videoSize = isLandscapeBuffer
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
        let orientation: CGImagePropertyOrientation = isLandscapeBuffer ? .right : .up

        let frame = CameraVideoFrame(
            pixelBuffer: buffer,
            timestamp: timestamp,
            orientation: orientation,
            videoSize: videoSize
        )
        onFrame?(frame)
    }
}
