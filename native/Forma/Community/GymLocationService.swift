import CoreLocation
import Foundation

/// One-shot location lookup used only to find gyms near the member. It asks
/// for when-in-use permission on demand, requests a single fix and stops.
/// There is no background monitoring, no continuous tracking and the
/// coordinate never leaves the device except as a gym-search parameter.
@MainActor
final class GymLocationService: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError, Equatable {
        case servicesDisabled
        case denied
        case restricted
        case unavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .servicesDisabled:
                "Location services are turned off. Search for your gym by name or city instead."
            case .denied:
                "Location access is off for Forma. You can still search for your gym by name or city."
            case .restricted:
                "Location access is restricted on this device. Search for your gym by name or city instead."
            case .unavailable:
                "Your location could not be determined right now. Try again or search by name."
            case .timedOut:
                "Finding your location took too long. Try again or search by name."
            }
        }
    }

    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var timeoutTask: Task<Void, Never>?

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.servicesDisabled
        }
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .denied: throw LocationError.denied
        case .restricted: throw LocationError.restricted
        default: break
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            self.manager = manager
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(LocationError.timedOut))
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard continuation != nil else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.stopUpdatingLocation()
        manager = nil
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            switch status {
            case .denied:
                self.finish(.failure(LocationError.denied))
            case .restricted:
                self.finish(.failure(LocationError.restricted))
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager?.requestLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor [weak self] in
            self?.finish(.success(coordinate))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(.failure(LocationError.unavailable))
        }
    }
}
