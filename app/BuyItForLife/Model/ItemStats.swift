import Foundation

/// A cost on a date: a purchase or a repair. Insights counts each in its own year.
nonisolated struct DatedCost: Equatable, Sendable {
    var date: Date
    var cents: Int
}

/// Cost and wear figures for one item. A plain value type so the maths can be
/// tested without SwiftData. All price maths in the app goes through here.
nonisolated struct ItemStats: Equatable, Sendable {
    var purchaseDate: Date
    /// The original price: what was paid for the item (for identical pieces,
    /// all purchases together), without repairs.
    var purchasePriceCents: Int
    var priorWearCount: Int
    var loggedDayKeys: Set<String>
    var soldDate: Date?
    var soldPriceCents: Int?
    /// Sum of the item's repairs.
    var repairsCents: Int = 0
    /// Every purchase and repair on its own date. Empty means one purchase of
    /// `purchasePriceCents` on `purchaseDate`.
    var datedCosts: [DatedCost] = []
    /// What was actually spent, dated: like `datedCosts` but without the value
    /// of gifts (repairs on gifts still count). nil means the same as
    /// `costTimeline`.
    var spendCosts: [DatedCost]? = nil

    /// Original price plus repairs.
    var totalCostCents: Int { purchasePriceCents + repairsCents }

    /// Costs with their dates, falling back to the single purchase.
    var costTimeline: [DatedCost] {
        datedCosts.isEmpty ? [DatedCost(date: purchaseDate, cents: totalCostCents)] : datedCosts
    }

    /// Estimated earlier wears plus logged days.
    var wearCount: Int { max(0, priorWearCount) + loggedDayKeys.count }

    /// Money actually spent, dated. Every spending figure reads this, never
    /// `totalCostCents`, so gifts don't count as spending.
    var spendTimeline: [DatedCost] { spendCosts ?? costTimeline }
    var spendCents: Int { spendTimeline.reduce(0) { $0 + $1.cents } }
    /// Spend minus sale price, never below zero.
    var netSpendCents: Int { max(0, spendCents - (soldPriceCents ?? 0)) }

    /// Total cost (original price plus repairs) minus sale price, never below zero.
    var netCostCents: Int { max(0, totalCostCents - (soldPriceCents ?? 0)) }

    /// nil until the item has been worn at least once.
    var costPerWearCents: Double? {
        wearCount > 0 ? Double(netCostCents) / Double(wearCount) : nil
    }

    /// Whole days from purchase until sold, or until `now` if still owned.
    func daysOwned(now: Date = .now, calendar: Calendar = .current) -> Int {
        let end = soldDate ?? now
        let start = calendar.startOfDay(for: purchaseDate)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: end)).day ?? 0
        return max(0, days)
    }

    var lastWornDayKey: String? { loggedDayKeys.max() }

    /// Days since the last logged wear: 0 = today. nil if never logged.
    func daysSinceLastWorn(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let key = lastWornDayKey, let day = DayKey.date(from: key, calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// Logged wears per calendar month for the last `months` months, oldest
    /// first, ending with the month of `now`. Estimated earlier wears have no
    /// dates, so they aren't included.
    func wearsPerMonth(months: Int = 12, now: Date = .now, calendar: Calendar = .current) -> [MonthCount] {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let starts = (0..<months).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: thisMonth)
        }
        var counts: [String: Int] = [:]
        for key in loggedDayKeys {
            counts[String(key.prefix(7)), default: 0] += 1 // "yyyy-MM"
        }
        return starts.map { start in
            let monthKey = String(DayKey.make(for: start, calendar: calendar).prefix(7))
            return MonthCount(monthStart: start, count: counts[monthKey] ?? 0)
        }
    }

    /// Wears still needed before the item is paid off; 0 when it already is.
    func wearsUntilPaidOff(targetCents: Int) -> Int? {
        guard let target = paidOffAtWear(targetCents: targetCents) else { return nil }
        return max(0, target - wearCount)
    }

    /// Paid off means the cost per wear is under the target.
    func isPaidOff(targetCents: Int) -> Bool {
        guard let cpw = costPerWearCents, targetCents > 0 else { return false }
        return cpw < Double(targetCents)
    }

    /// The wear at which the cost per wear first drops under the target,
    /// e.g. "Under your €1.00 target since wear 350".
    func paidOffAtWear(targetCents: Int) -> Int? {
        guard targetCents > 0 else { return nil }
        return netCostCents / targetCents + 1
    }
}

nonisolated struct MonthCount: Equatable, Sendable {
    var monthStart: Date
    var count: Int
}

/// Wardrobe-level figures across all items, owned and sold.
nonisolated struct WardrobeStats: Equatable, Sendable {
    var items: [ItemStats]

    /// Everything paid, repairs included, gifts excluded.
    var totalSpentCents: Int { items.reduce(0) { $0 + $1.spendCents } }
    var repairsCents: Int { items.reduce(0) { $0 + $1.repairsCents } }
    var backFromSalesCents: Int { items.reduce(0) { $0 + ($1.soldPriceCents ?? 0) } }
    /// Spent minus money back from sales (gifts excluded).
    var netSpendCents: Int { items.reduce(0) { $0 + $1.netSpendCents } }
    var wearCount: Int { items.reduce(0) { $0 + $1.wearCount } }

    var averageCostPerWearCents: Double? {
        wearCount > 0 ? Double(netSpendCents) / Double(wearCount) : nil
    }

    /// Days from the earliest purchase to `date`, at least 1 once an item
    /// had been bought by then; 0 before that.
    func daysTracked(asOf date: Date = .now, calendar: Calendar = .current) -> Int {
        let day = calendar.startOfDay(for: date)
        guard let first = items.map({ calendar.startOfDay(for: $0.purchaseDate) }).filter({ $0 <= day }).min() else {
            return 0
        }
        return max(1, calendar.dateComponents([.day], from: first, to: day).day ?? 0)
    }

    /// Net cost of what had been bought by `date` (minus sales made by then),
    /// spread over the days since the first purchase. nil before any purchase.
    func costPerDayCents(asOf date: Date = .now, calendar: Calendar = .current) -> Double? {
        let day = calendar.startOfDay(for: date)
        let days = daysTracked(asOf: date, calendar: calendar)
        guard days > 0 else { return nil }
        let net = items.reduce(0) { total, item in
            guard calendar.startOfDay(for: item.purchaseDate) <= day else { return total }
            // Purchases and repairs count from their own dates.
            let paid = item.spendTimeline.filter { calendar.startOfDay(for: $0.date) <= day }.reduce(0) { $0 + $1.cents }
            let soldByThen = item.soldDate.map { calendar.startOfDay(for: $0) <= day } ?? false
            return total + max(0, paid - (soldByThen ? item.soldPriceCents ?? 0 : 0))
        }
        return Double(net) / Double(days)
    }

    /// Cost per day at the end of each year since the first purchase, ending
    /// with `now`. At most `limit` points, most recent kept.
    func costPerDayHistory(now: Date = .now, limit: Int = 7, calendar: Calendar = .current) -> [YearPoint] {
        guard let first = items.map(\.purchaseDate).min() else { return [] }
        let firstYear = calendar.component(.year, from: first)
        let thisYear = calendar.component(.year, from: now)
        var points: [YearPoint] = []
        for year in firstYear..<thisYear {
            guard let lastDay = calendar.date(from: DateComponents(year: year, month: 12, day: 31)),
                  let value = costPerDayCents(asOf: lastDay, calendar: calendar)
            else { continue }
            points.append(YearPoint(year: year, isNow: false, cents: value))
        }
        if let value = costPerDayCents(asOf: now, calendar: calendar) {
            points.append(YearPoint(year: thisYear, isNow: true, cents: value))
        }
        return Array(points.suffix(limit))
    }

    /// Money spent on purchases in each calendar year, from the first purchase
    /// year to this year. At most `limit` years, most recent kept.
    func spendPerYear(now: Date = .now, limit: Int = 7, calendar: Calendar = .current) -> [YearPoint] {
        guard let first = items.map(\.purchaseDate).min() else { return [] }
        let firstYear = calendar.component(.year, from: first)
        let thisYear = max(firstYear, calendar.component(.year, from: now))
        var totals: [Int: Int] = [:]
        for item in items {
            for cost in item.spendTimeline {
                totals[calendar.component(.year, from: cost.date), default: 0] += cost.cents
            }
        }
        let points = (firstYear...thisYear).map {
            YearPoint(year: $0, isNow: $0 == thisYear, cents: Double(totals[$0] ?? 0))
        }
        return Array(points.suffix(limit))
    }
}

nonisolated extension WardrobeStats {
    /// Money spent (purchases and repairs, each on its own date) in each of
    /// the last `months` calendar months, oldest first, ending with this month.
    func spendPerMonth(months: Int = 12, now: Date = .now, calendar: Calendar = .current) -> [MonthSpend] {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let starts = (0..<months).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        var totals: [Date: Int] = [:]
        for item in items {
            for cost in item.spendTimeline {
                guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: cost.date)) else { continue }
                totals[month, default: 0] += cost.cents
            }
        }
        return starts.map { MonthSpend(monthStart: $0, cents: Double(totals[$0] ?? 0)) }
    }
}

nonisolated struct MonthSpend: Equatable, Sendable {
    var monthStart: Date
    var cents: Double
}

nonisolated struct YearPoint: Equatable, Sendable {
    var year: Int
    /// The last point is "now" rather than the end of the year.
    var isNow: Bool
    var cents: Double
}
