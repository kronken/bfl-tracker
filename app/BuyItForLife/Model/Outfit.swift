import Foundation

/// Today's sections, top to toe. Any number of items can be picked in each.
nonisolated enum OutfitGroup: String, CaseIterable, Identifiable, Sendable {
    case headwear, outerwear, tops, bottoms, footwear, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .headwear: "Headwear"
        case .outerwear: "Outerwear"
        case .tops: "Tops"
        case .bottoms: "Pants"
        case .footwear: "Shoes"
        case .more: "More"
        }
    }

    init(category: ItemCategory) {
        self = switch category {
        case .headwear: .headwear
        case .outerwear: .outerwear
        case .tops, .knitwear: .tops
        case .bottoms: .bottoms
        case .footwear: .footwear
        case .underwear, .accessories, .other: .more
        }
    }
}

/// Selection rules for a day's outfit, on item IDs so they can be tested
/// without SwiftData.
nonisolated enum OutfitRules {
    /// What counts as worn on a day: what was saved, or, for a day nobody has
    /// edited yet, that plus every daily driver.
    static func effectiveSelection(saved: Set<UUID>, isSaved: Bool, dailyDrivers: Set<UUID>) -> Set<UUID> {
        isSaved ? saved : saved.union(dailyDrivers)
    }

    /// Tapping `item` selects it, or deselects it if it was selected. Other
    /// items are never affected.
    static func toggle(_ item: UUID, in selection: Set<UUID>) -> Set<UUID> {
        selection.symmetricDifference([item])
    }

    /// Favorites first, then most worn.
    static func isOrderedBefore(favoriteA: Bool, wearsA: Int, favoriteB: Bool, wearsB: Int) -> Bool {
        if favoriteA != favoriteB { return favoriteA }
        return wearsA > wearsB
    }
}

/// When the daily reminder should next fire. iOS can't check "has anything
/// been logged?" at delivery time, so one notification is scheduled for the
/// next time it should go off, and rescheduled whenever that could change.
nonisolated enum ReminderPlanner {
    static func nextFireDate(now: Date, minutes: Int, loggedToday: Bool, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let todayAtTime = calendar.date(byAdding: .minute, value: minutes, to: today) ?? now
        if !loggedToday && todayAtTime > now { return todayAtTime }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return calendar.date(byAdding: .minute, value: minutes, to: tomorrow) ?? now
    }

    /// "20:00" style label, in the device's 12/24-hour format.
    static func timeLabel(minutes: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: .now)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
