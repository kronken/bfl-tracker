import Foundation

/// Something bought: a new item, or an "Add more" on identical pieces.
/// Repairs, sales, retirements and edits are not purchases.
nonisolated struct Purchase: Equatable, Sendable {
    var date: Date
    var cents: Int
    var name: String
}

/// Everything the buy-less card shows, worked out from purchases. Shared so
/// Insights (and later widgets) use the same numbers.
nonisolated struct BuyLessStats: Equatable, Sendable {
    /// Days since the last purchase (or since the feature was turned on).
    var currentStreakDays: Int
    /// Longest gap between purchases, the current streak included.
    var longestStreakDays: Int
    var spentThisMonthCents: Int
    var spentThisYearCents: Int
    var boughtThisMonth: Int
    var boughtThisYear: Int
    /// Purchases per calendar year, oldest first; each purchase counts 1.
    var purchasesPerYear: [(year: Int, count: Int)]
    var lastPurchase: Purchase?

    static func == (a: BuyLessStats, b: BuyLessStats) -> Bool {
        a.currentStreakDays == b.currentStreakDays && a.longestStreakDays == b.longestStreakDays
            && a.spentThisMonthCents == b.spentThisMonthCents && a.spentThisYearCents == b.spentThisYearCents
            && a.boughtThisMonth == b.boughtThisMonth && a.boughtThisYear == b.boughtThisYear
            && a.purchasesPerYear.map(\.year) == b.purchasesPerYear.map(\.year)
            && a.purchasesPerYear.map(\.count) == b.purchasesPerYear.map(\.count)
            && a.lastPurchase == b.lastPurchase
    }

    init(purchases all: [Purchase], enabledDate: Date, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        // Purchases dated in the future don't count until their day arrives.
        let purchases = all.filter { calendar.startOfDay(for: $0.date) <= today }.sorted { $0.date < $1.date }
        let days = { (from: Date, to: Date) in
            max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                           to: calendar.startOfDay(for: to)).day ?? 0)
        }

        lastPurchase = purchases.last
        currentStreakDays = days(lastPurchase?.date ?? enabledDate, today)

        var longest = currentStreakDays
        for (earlier, later) in zip(purchases, purchases.dropFirst()) {
            longest = max(longest, days(earlier.date, later.date))
        }
        longestStreakDays = longest

        let month = calendar.dateComponents([.year, .month], from: now)
        let thisMonth = purchases.filter { calendar.dateComponents([.year, .month], from: $0.date) == month }
        let thisYear = purchases.filter { calendar.component(.year, from: $0.date) == month.year }
        spentThisMonthCents = thisMonth.reduce(0) { $0 + $1.cents }
        spentThisYearCents = thisYear.reduce(0) { $0 + $1.cents }
        boughtThisMonth = thisMonth.count
        boughtThisYear = thisYear.count

        if let first = purchases.first.map({ calendar.component(.year, from: $0.date) }), let current = month.year {
            var counts: [Int: Int] = [:]
            for purchase in purchases { counts[calendar.component(.year, from: purchase.date), default: 0] += 1 }
            purchasesPerYear = (first...max(first, current)).map { ($0, counts[$0] ?? 0) }
        } else {
            purchasesPerYear = []
        }
    }

    func isGoalReached(goalDays: Int) -> Bool { currentStreakDays >= goalDays }

    /// The current year's count is the lowest of all years so far.
    var isBestYear: Bool {
        guard let current = purchasesPerYear.last, purchasesPerYear.count > 1 else { return false }
        return purchasesPerYear.dropLast().allSatisfy { current.count < $0.count }
    }
}

/// The short, warm lines on the buy-less card. Never scolds.
nonisolated enum BuyLessCopy {
    static func cheer(streak: Int, goalDays: Int) -> String {
        switch streak {
        case 365...: "Over a year. Your wardrobe is doing its job."
        case goalDays...: "Goal reached. Keep it going."
        case 30...: "A month and counting."
        case 7...: "A week and counting."
        case 1: "New streak: 1 day. Make it count."
        default: "New streak: \(streak) days. Make it count."
        }
    }

    static func status(streak: Int, longest: Int, goalDays: Int) -> String {
        if streak >= goalDays {
            return "Goal of \(goalDays) days reached" + (streak >= longest ? " · longest streak yet" : "")
        }
        let left = goalDays - streak
        return "\(left) \(left == 1 ? "day" : "days") to your \(goalDays)-day goal"
    }

    /// e.g. "From 5 a year to none. Last buy: Raw denim jeans, Aug 2025."
    static func yearSummary(_ stats: BuyLessStats) -> String {
        var parts: [String] = []
        if let first = stats.purchasesPerYear.first, let current = stats.purchasesPerYear.last,
           stats.purchasesPerYear.count > 1 {
            let peak = stats.purchasesPerYear.map(\.count).max() ?? first.count
            let now = current.count == 0 ? "none" : "\(current.count)"
            if current.count < peak { parts.append("From \(peak) a year to \(now) this year.") }
        }
        if let last = stats.lastPurchase {
            parts.append("Last buy: \(last.name), \(last.date.formatted(.dateTime.month(.abbreviated).year())).")
        }
        return parts.joined(separator: " ")
    }
}

extension Item {
    /// The purchases this item stands for: its own purchase, or for identical
    /// pieces each "bought" entry in the log.
    var purchases: [Purchase] {
        if isMultiPiece {
            return (pieceEvents ?? []).filter { $0.kind == .bought }
                .map { Purchase(date: $0.date, cents: $0.priceCents ?? 0, name: name) }
        }
        return [Purchase(date: purchaseDate, cents: purchasePriceCents, name: name)]
    }
}
