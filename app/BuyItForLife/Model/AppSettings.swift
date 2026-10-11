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
        static let sellSuggestionMonths = "sellSuggestionMonths"
        static let feelGoodMode = "feelGoodMode"
        // Kept on this device only: notifications and their permission are per device.
        static let reminderEnabled = "reminderEnabled"
        static let reminderMinutes = "reminderMinutes"
    }

    static let defaultSellSuggestionMonths = 12
    static let defaultReminderMinutes = 20 * 60

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

    /// Unworn items are suggested for selling after this many months.
    var sellSuggestionMonths: Int {
        didSet { store.set(Int64(sellSuggestionMonths), forKey: Key.sellSuggestionMonths) }
    }

    /// Feel-good mode: hides big money totals (total spent, back from sales,
    /// wardrobe value, yearly spend). Display only; nothing is recalculated.
    var feelGoodMode: Bool {
        didSet { store.set(feelGoodMode, forKey: Key.feelGoodMode) }
    }

    /// The one place screens ask whether to hide money totals.
    var hidesTotals: Bool { feelGoodMode }

    /// Daily "nothing logged yet" reminder. Stored on this device only.
    var reminderEnabled: Bool {
        didSet { local.set(reminderEnabled, forKey: Key.reminderEnabled) }
    }

    /// Reminder time as minutes after midnight, e.g. 1200 = 20:00.
    var reminderMinutes: Int {
        didSet { local.set(reminderMinutes, forKey: Key.reminderMinutes) }
    }

    @ObservationIgnored private let local: UserDefaults

    init(store: NSUbiquitousKeyValueStore = .default, local: UserDefaults = .standard) {
        self.store = store
        self.local = local
        store.synchronize()
        weatherLocation = store.string(forKey: Key.weatherLocation)
        let target = Int(store.longLong(forKey: Key.paidOffTargetCents))
        paidOffTargetCents = target > 0 ? target : 100
        onboardingCompleted = store.bool(forKey: Key.onboardingCompleted)
        let months = Int(store.longLong(forKey: Key.sellSuggestionMonths))
        sellSuggestionMonths = months > 0 ? months : Self.defaultSellSuggestionMonths
        feelGoodMode = store.bool(forKey: Key.feelGoodMode)
        reminderEnabled = local.bool(forKey: Key.reminderEnabled)
        reminderMinutes = local.object(forKey: Key.reminderMinutes) as? Int ?? Self.defaultReminderMinutes
        #if DEBUG
        // `-debugWeatherLocation fi.helsinki` for screenshots; never saved.
        if let override = UserDefaults.standard.string(forKey: "debugWeatherLocation") {
            weatherLocation = override
        }
        // `-debugFeelGood YES` turns feel-good mode on for screenshots; never saved.
        if UserDefaults.standard.bool(forKey: "debugFeelGood") { feelGoodMode = true }
        #endif

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
        let months = Int(store.longLong(forKey: Key.sellSuggestionMonths))
        sellSuggestionMonths = months > 0 ? months : Self.defaultSellSuggestionMonths
        feelGoodMode = store.bool(forKey: Key.feelGoodMode)
    }
}
