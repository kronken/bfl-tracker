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
    /// Purchases in each of the last 12 calendar months, oldest first,
    /// ending with this month; each purchase counts 1.
    var purchasesPerMonth: [(monthStart: Date, count: Int)]
    /// Whether anything was bought before (or in) these 12 months at all.
    var hasPurchases: Bool { lastPurchase != nil }
    var lastPurchase: Purchase?

    static func == (a: BuyLessStats, b: BuyLessStats) -> Bool {
        a.currentStreakDays == b.currentStreakDays && a.longestStreakDays == b.longestStreakDays
            && a.spentThisMonthCents == b.spentThisMonthCents && a.spentThisYearCents == b.spentThisYearCents
            && a.boughtThisMonth == b.boughtThisMonth && a.boughtThisYear == b.boughtThisYear
            && a.purchasesPerMonth.map(\.monthStart) == b.purchasesPerMonth.map(\.monthStart)
            && a.purchasesPerMonth.map(\.count) == b.purchasesPerMonth.map(\.count)
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

        let thisMonthStart = calendar.date(from: month) ?? today
        let monthStarts = (0..<12).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonthStart) }
        var counts: [Date: Int] = [:]
        for purchase in purchases {
            if let start = calendar.date(from: calendar.dateComponents([.year, .month], from: purchase.date)) {
                counts[start, default: 0] += 1
            }
        }
        purchasesPerMonth = monthStarts.map { ($0, counts[$0] ?? 0) }
    }

    func isGoalReached(goalDays: Int) -> Bool { currentStreakDays >= goalDays }
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

    /// e.g. "4 things in the last 12 months. Last buy: Merino tee, Aug 2026."
    static func monthSummary(_ stats: BuyLessStats) -> String {
        let total = stats.purchasesPerMonth.reduce(0) { $0 + $1.count }
        var parts = [total == 0 ? "Nothing bought in the last 12 months."
                     : total == 1 ? "1 thing in the last 12 months."
                     : "\(total) things in the last 12 months."]
        if let last = stats.lastPurchase {
            parts.append("Last buy: \(last.name), \(last.date.formatted(.dateTime.month(.abbreviated).year())).")
        }
        return parts.joined(separator: " ")
    }
}

extension Item {
    /// The purchases this item stands for: its own purchase, or for identical
    /// pieces each "bought" entry in the log. Gifts aren't purchases.
    var purchases: [Purchase] {
        if isMultiPiece {
            return (pieceEvents ?? []).filter { $0.kind == .bought && !$0.isGift }
                .map { Purchase(date: $0.date, cents: $0.priceCents ?? 0, name: name) }
        }
        return isGift ? [] : [Purchase(date: purchaseDate, cents: purchasePriceCents, name: name)]
    }
}
