import CoreLocation
import Foundation
import Observation

/// One-shot access to the device's approximate location, only while the app
/// is in use. Reuses a fix from the last 30 minutes when there is one.
@MainActor
@Observable
final class LocationProvider: NSObject {
    enum LocationError: Error {
        case denied
        case unavailable
    }

    static let maxAge: TimeInterval = 30 * 60

    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    @ObservationIgnored private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Weather needs a city-sized area, not a street address.
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// Asks for "While Using" permission if it hasn't been asked yet.
    func requestAuthorization() async -> CLAuthorizationStatus {
        guard manager.authorizationStatus == .notDetermined else { return manager.authorizationStatus }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// A position no older than 30 minutes: the system's last fix if recent
    /// enough, otherwise a fresh one.
    func currentLocation() async throws -> CLLocation {
        let status = await requestAuthorization()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { throw LocationError.denied }

        if let recent = manager.location, -recent.timestamp.timeIntervalSinceNow < Self.maxAge {
            LocationCache.save(recent)
            return recent
        }
        let fresh = try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
        LocationCache.save(fresh)
        return fresh
    }

    private func resumeLocationWaiters(with result: Result<CLLocation, Error>) {
        let waiters = locationWaiters
        locationWaiters = []
        for waiter in waiters { waiter.resume(with: result) }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            guard status != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters = []
            for waiter in waiters { waiter.resume(returning: status) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated { resumeLocationWaiters(with: .success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { resumeLocationWaiters(with: .failure(LocationError.unavailable)) }
    }
}

/// The last known position, kept on this device only, so the weather can be
/// shown when a fresh fix isn't available.
nonisolated enum LocationCache {
    private static let key = "lastLocation"

    static func save(_ location: CLLocation) {
        UserDefaults.standard.set(
            [location.coordinate.latitude, location.coordinate.longitude, location.timestamp.timeIntervalSince1970],
            forKey: key
        )
    }

    static func load() -> CLLocation? {
        guard let values = UserDefaults.standard.array(forKey: key) as? [Double], values.count == 3 else { return nil }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: values[0], longitude: values[1]),
            altitude: 0, horizontalAccuracy: 3000, verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: values[2])
        )
    }
}
