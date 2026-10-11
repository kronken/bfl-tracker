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
        static let buyLessEnabled = "buyLessEnabled"
        static let buyLessEnabledDate = "buyLessEnabledDate"
        static let noBuyGoalDays = "noBuyGoalDays"
        static let monthlyLimitCents = "monthlyLimitCents"
        static let yearlyBudgetCents = "yearlyBudgetCents"
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
        didSet { if !isApplyingDebugOverrides { store.set(weatherLocation, forKey: Key.weatherLocation) } }
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
        didSet { if !isApplyingDebugOverrides { store.set(feelGoodMode, forKey: Key.feelGoodMode) } }
    }

    // Buy-less goals. Money is kept in whole cents like everywhere else.
    var buyLessEnabled: Bool {
        didSet {
            guard !isApplyingDebugOverrides else { return }
            store.set(buyLessEnabled, forKey: Key.buyLessEnabled)
            if buyLessEnabled && buyLessEnabledDate == nil { buyLessEnabledDate = .now }
        }
    }

    /// When buy-less goals were first turned on: the streak start if nothing
    /// has been bought.
    var buyLessEnabledDate: Date? {
        didSet {
            guard !isApplyingDebugOverrides else { return }
            store.set(buyLessEnabledDate?.timeIntervalSince1970, forKey: Key.buyLessEnabledDate)
        }
    }

    var noBuyGoalDays: Int {
        didSet { store.set(Int64(noBuyGoalDays), forKey: Key.noBuyGoalDays) }
    }

    var monthlyLimitCents: Int {
        didSet { store.set(Int64(monthlyLimitCents), forKey: Key.monthlyLimitCents) }
    }

    var yearlyBudgetCents: Int {
        didSet { store.set(Int64(yearlyBudgetCents), forKey: Key.yearlyBudgetCents) }
    }

    static let defaultNoBuyGoalDays = 90
    static let defaultMonthlyLimitCents = 5_000
    static let defaultYearlyBudgetCents = 30_000

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
    /// While true, changes aren't written to storage (debug launch overrides).
    @ObservationIgnored private var isApplyingDebugOverrides = false

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
        buyLessEnabled = store.bool(forKey: Key.buyLessEnabled)
        buyLessEnabledDate = (store.object(forKey: Key.buyLessEnabledDate) as? Double).map(Date.init(timeIntervalSince1970:))
        let goal = Int(store.longLong(forKey: Key.noBuyGoalDays))
        noBuyGoalDays = goal > 0 ? goal : Self.defaultNoBuyGoalDays
        monthlyLimitCents = store.object(forKey: Key.monthlyLimitCents) == nil
            ? Self.defaultMonthlyLimitCents : Int(store.longLong(forKey: Key.monthlyLimitCents))
        yearlyBudgetCents = store.object(forKey: Key.yearlyBudgetCents) == nil
            ? Self.defaultYearlyBudgetCents : Int(store.longLong(forKey: Key.yearlyBudgetCents))
        reminderEnabled = local.bool(forKey: Key.reminderEnabled)
        reminderMinutes = local.object(forKey: Key.reminderMinutes) as? Int ?? Self.defaultReminderMinutes
        #if DEBUG
        // Launch arguments for screenshots. They change what this run shows,
        // never what's stored: `-debugWeatherLocation fi.helsinki`,
        // `-debugFeelGood YES|NO`.
        isApplyingDebugOverrides = true
        if let override = UserDefaults.standard.string(forKey: "debugWeatherLocation") {
            weatherLocation = override
        }
        if UserDefaults.standard.object(forKey: "debugFeelGood") != nil {
            feelGoodMode = UserDefaults.standard.bool(forKey: "debugFeelGood")
        }
        // `-debugBuyLess YES` shows buy-less goals for this run.
        if UserDefaults.standard.object(forKey: "debugBuyLess") != nil {
            buyLessEnabled = UserDefaults.standard.bool(forKey: "debugBuyLess")
            if buyLessEnabledDate == nil { buyLessEnabledDate = Calendar.current.date(byAdding: .day, value: -20, to: .now) }
        }
        isApplyingDebugOverrides = false
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
        buyLessEnabled = store.bool(forKey: Key.buyLessEnabled)
        buyLessEnabledDate = (store.object(forKey: Key.buyLessEnabledDate) as? Double).map(Date.init(timeIntervalSince1970:))
        let goal = Int(store.longLong(forKey: Key.noBuyGoalDays))
        noBuyGoalDays = goal > 0 ? goal : Self.defaultNoBuyGoalDays
        monthlyLimitCents = store.object(forKey: Key.monthlyLimitCents) == nil
            ? Self.defaultMonthlyLimitCents : Int(store.longLong(forKey: Key.monthlyLimitCents))
        yearlyBudgetCents = store.object(forKey: Key.yearlyBudgetCents) == nil
            ? Self.defaultYearlyBudgetCents : Int(store.longLong(forKey: Key.yearlyBudgetCents))
    }
}
