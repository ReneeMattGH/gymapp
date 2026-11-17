import AVFoundation
import XCTest
@testable import Forma

@MainActor
final class FormAnalysisViewModelTests: XCTestCase {
    private final class FakeAuthorizer: CameraAuthorizing, @unchecked Sendable {
        var status: CameraPermissionStatus
        var grantsOnRequest: Bool

        init(status: CameraPermissionStatus, grantsOnRequest: Bool = true) {
            self.status = status
            self.grantsOnRequest = grantsOnRequest
        }

        var currentStatus: CameraPermissionStatus { status }

        func requestAccess() async -> Bool {
            if grantsOnRequest, status == .notDetermined {
                status = .authorized
            }
            return grantsOnRequest
        }
    }

    private final class FakeCamera: CameraCapturing {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var onFrame: ((CameraVideoFrame) -> Void)?
        var onInterruption: ((CameraInterruption) -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var isRunning = false
        private(set) var lastPosition: FormCameraPosition?
        var startError: Error?

        func start(position: FormCameraPosition) async throws {
            lastPosition = position
            startCount += 1
            if let startError { throw startError }
            isRunning = true
        }

        func stop() async {
            stopCount += 1
            isRunning = false
        }

        func setAnalysisInterval(_ interval: TimeInterval) {}
    }

    private func makeViewModel(
        permission: CameraPermissionStatus,
        camera: FakeCamera = FakeCamera()
    ) -> FormAnalysisViewModel {
        FormAnalysisViewModel(
            exercise: .squat,
            camera: camera,
            permissionManager: CameraPermissionManager(
                authorizer: FakeAuthorizer(status: permission)
            )
        )
    }

    func testDeniedPermissionNeverStartsCamera() async {
        let camera = FakeCamera()
        let viewModel = makeViewModel(permission: .denied, camera: camera)

        await viewModel.start()

        XCTAssertEqual(viewModel.phase, .permissionDenied)
        XCTAssertEqual(camera.startCount, 0)
        XCTAssertFalse(viewModel.isCameraRunning)
        await viewModel.shutdown()
    }

    func testUnavailableCameraIsReportedHonestly() async {
        let viewModel = makeViewModel(permission: .unavailable)

        await viewModel.start()

        XCTAssertEqual(viewModel.phase, .cameraUnavailable)
        XCTAssertFalse(viewModel.canStart)
        await viewModel.shutdown()
    }

    func testAuthorizedStartLaunchesCameraAndShutdownReleasesIt() async {
        let camera = FakeCamera()
        let viewModel = makeViewModel(permission: .authorized, camera: camera)

        await viewModel.start()

        XCTAssertEqual(viewModel.phase, .running)
        XCTAssertTrue(viewModel.isCameraRunning)
        XCTAssertEqual(camera.startCount, 1)
        XCTAssertEqual(camera.lastPosition, .front)
        XCTAssertNotNil(camera.onFrame)

        await viewModel.shutdown()

        XCTAssertFalse(viewModel.isCameraRunning)
        XCTAssertEqual(camera.stopCount, 1)
        XCTAssertNil(camera.onFrame)
        XCTAssertNil(camera.onInterruption)
    }

    func testNotDeterminedPermissionCanBePrompted() async {
        let camera = FakeCamera()
        let viewModel = makeViewModel(permission: .notDetermined, camera: camera)

        XCTAssertTrue(viewModel.canStart)
        await viewModel.start()

        XCTAssertEqual(viewModel.phase, .running)
        XCTAssertEqual(camera.startCount, 1)
        await viewModel.shutdown()
    }

    func testCameraStartFailureBecomesVisibleFailure() async {
        let camera = FakeCamera()
        camera.startError = CameraCaptureError.configurationFailed("synthetic")
        let viewModel = makeViewModel(permission: .authorized, camera: camera)

        await viewModel.start()

        guard case .failed(let message) = viewModel.phase else {
            return XCTFail("Expected a failed phase, got \(viewModel.phase)")
        }
        XCTAssertTrue(message.contains("synthetic"))
        XCTAssertFalse(viewModel.isCameraRunning)
        await viewModel.shutdown()
    }

    func testPauseAndResumeTransitionAndKeepCameraStateHonest() async {
        let camera = FakeCamera()
        let viewModel = makeViewModel(permission: .authorized, camera: camera)
        await viewModel.start()

        viewModel.pause()
        XCTAssertEqual(viewModel.phase, .paused)
        XCTAssertTrue(viewModel.isCameraRunning)

        await viewModel.resume()
        XCTAssertEqual(viewModel.phase, .running)
        XCTAssertEqual(camera.startCount, 1)
        await viewModel.shutdown()
    }

    func testBackgroundingPausesAndStopsTheCamera() async {
        let camera = FakeCamera()
        let viewModel = makeViewModel(permission: .authorized, camera: camera)
        await viewModel.start()

        viewModel.handleScenePhase(.background)
        XCTAssertEqual(viewModel.phase, .paused)
        XCTAssertNotNil(viewModel.interruptionMessage)

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(viewModel.isCameraRunning)
        XCTAssertEqual(camera.stopCount, 1)
        await viewModel.shutdown()
    }

    func testEndingWithoutReliableFramesProducesAnHonestSummary() async {
        let camera = FakeCamera()
        let viewModel = makeViewModel(permission: .authorized, camera: camera)
        await viewModel.start()

        await viewModel.end()

        XCTAssertEqual(viewModel.phase, .summary)
        let summary = try? XCTUnwrap(viewModel.summary)
        XCTAssertNotNil(summary)
        XCTAssertNil(summary?.repCount)
        XCTAssertEqual(summary?.exercise, .squat)
        XCTAssertFalse(camera.isRunning)
        await viewModel.shutdown()
    }

    func testExerciseAndCameraCanOnlyChangeBeforeRunning() async {
        let camera = FakeCamera()
        let viewModel = makeViewModel(permission: .authorized, camera: camera)

        viewModel.selectExercise(.pushUp)
        viewModel.selectCameraPosition(.back)
        XCTAssertEqual(viewModel.exercise, .pushUp)
        XCTAssertEqual(viewModel.cameraPosition, .back)

        await viewModel.start()
        XCTAssertEqual(camera.lastPosition, .back)

        viewModel.selectExercise(.jumpingJack)
        viewModel.selectCameraPosition(.front)
        XCTAssertEqual(viewModel.exercise, .pushUp)
        XCTAssertEqual(viewModel.cameraPosition, .back)
        await viewModel.shutdown()
    }
}
