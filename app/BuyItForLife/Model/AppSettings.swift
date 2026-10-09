import Foundation
import Observation

/// User settings, synced through the iCloud key-value store so they follow the
/// user to a new device.
@MainActor
@Observable
final class AppSettings {
    /// `weatherLocation` value meaning "use the device's location".
    static let currentLocation = "current"

    private enum Key {
        static let weatherLocation = "weatherLocation"
        static let paidOffTargetCents = "paidOffTargetCents"
        static let onboardingCompleted = "onboardingCompleted"
    }

    private let store: NSUbiquitousKeyValueStore
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// `AppSettings.currentLocation` or a city ID like "fi.helsinki"; nil until chosen.
    var weatherLocation: String? {
        didSet { store.set(weatherLocation, forKey: Key.weatherLocation) }
    }

    var paidOffTargetCents: Int {
        didSet { store.set(Int64(paidOffTargetCents), forKey: Key.paidOffTargetCents) }
    }

    var onboardingCompleted: Bool {
        didSet { store.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
    }

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        store.synchronize()
        weatherLocation = store.string(forKey: Key.weatherLocation)
        let target = Int(store.longLong(forKey: Key.paidOffTargetCents))
        paidOffTargetCents = target > 0 ? target : 100
        onboardingCompleted = store.bool(forKey: Key.onboardingCompleted)

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Picks up changes made on another device.
    private func reload() {
        weatherLocation = store.string(forKey: Key.weatherLocation)
        let target = Int(store.longLong(forKey: Key.paidOffTargetCents))
        paidOffTargetCents = target > 0 ? target : 100
        onboardingCompleted = store.bool(forKey: Key.onboardingCompleted)
    }
}
