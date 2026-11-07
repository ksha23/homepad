import CoreLocation
import Foundation
import HomePadCore

/// One-shot "where is this iPad" for weather. Asks for when-in-use permission
/// only when called, which happens after the person chose "Use My Location".
@MainActor
final class LocationResolver: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: "Location access is off. Choose a city instead, or allow location in Settings."
            case .unavailable: "This iPad could not find its location."
            }
        }
    }

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// Current location as a weather place, named by reverse geocoding.
    func currentPlace() async throws -> WeatherPlace {
        let location = try await currentLocation()
        return await PlaceSearch.place(for: location)
    }

    private func currentLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        guard !isDenied else { throw LocationError.denied }
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -900 { return recent }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            authorizationWaiters.forEach { $0.resume() }
            authorizationWaiters.removeAll()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            locationWaiters.forEach { $0.resume(returning: location) }
            locationWaiters.removeAll()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            locationWaiters.forEach { $0.resume(throwing: LocationError.unavailable) }
            locationWaiters.removeAll()
        }
    }
}
