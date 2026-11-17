import AVFoundation
import Observation

enum CameraPermissionStatus: String, Equatable, Sendable {
    case notDetermined, authorized, denied, restricted, unavailable

    var title: String {
        switch self {
        case .notDetermined: return "Camera access needed"
        case .authorized: return "Camera ready"
        case .denied: return "Camera access denied"
        case .restricted: return "Camera access restricted"
        case .unavailable: return "Camera unavailable"
        }
    }

    var message: String {
        switch self {
        case .notDetermined:
            return "Form analysis uses the camera on this device only. Video frames are analysed in memory with Apple Vision and are never uploaded or saved."
        case .authorized:
            return "Camera access is granted."
        case .denied:
            return "Camera access is off. You can enable it in Settings > Forma > Camera. The rest of the app still works without it."
        case .restricted:
            return "Camera access is restricted on this device, so form analysis cannot run. All other features still work."
        case .unavailable:
            return "No camera is available on this device. The Simulator cannot test camera or pose analysis."
        }
    }
}

protocol CameraAuthorizing: Sendable {
    var currentStatus: CameraPermissionStatus { get }
    func requestAccess() async -> Bool
}

struct SystemCameraAuthorizer: CameraAuthorizing {
    var currentStatus: CameraPermissionStatus {
        let hasCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        guard hasCamera else { return .unavailable }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

@MainActor
@Observable
final class CameraPermissionManager {
    private(set) var status: CameraPermissionStatus
    private let authorizer: CameraAuthorizing

    init(authorizer: CameraAuthorizing = SystemCameraAuthorizer()) {
        self.authorizer = authorizer
        self.status = authorizer.currentStatus
    }

    func refresh() {
        status = authorizer.currentStatus
    }

    /// Requests access only while the system still allows a prompt.
    func requestIfNeeded() async -> CameraPermissionStatus {
        refresh()
        guard status == .notDetermined else { return status }
        _ = await authorizer.requestAccess()
        refresh()
        return status
    }
}
