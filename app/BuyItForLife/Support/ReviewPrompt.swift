import Foundation

/// When to ask for an App Store rating: after a week of logging every day,
/// at most once per app version. iOS itself also limits how often the
/// dialog really appears (about three times a year).
nonisolated enum ReviewPrompt {
    static let streakNeeded = 7
    private static let askedVersionKey = "reviewRequestedVersion"

    /// Consecutive days with something logged, ending today (0 if today
    /// isn't logged).
    static func streak(loggedDayKeys: Set<String>, today: Date, calendar: Calendar = .current) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: today)
        while loggedDayKeys.contains(DayKey.make(for: day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func shouldAsk(streak: Int, askedVersion: String?, currentVersion: String) -> Bool {
        streak >= streakNeeded && askedVersion != currentVersion
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var askedVersion: String? {
        get { UserDefaults.standard.string(forKey: askedVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedVersionKey) }
    }
}
