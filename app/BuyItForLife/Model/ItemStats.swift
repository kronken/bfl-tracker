import Foundation

/// Cost and wear figures for one item. A plain value type so the maths can be
/// tested without SwiftData.
nonisolated struct ItemStats: Equatable, Sendable {
    var purchaseDate: Date
    var purchasePriceCents: Int
    var priorWearCount: Int
    var loggedDayKeys: Set<String>
    var soldDate: Date?
    var soldPriceCents: Int?

    /// Estimated earlier wears plus logged days.
    var wearCount: Int { max(0, priorWearCount) + loggedDayKeys.count }

    /// Purchase price minus sale price, never below zero.
    var netCostCents: Int { max(0, purchasePriceCents - (soldPriceCents ?? 0)) }

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

/// Wardrobe-level figures across all items, owned and sold.
nonisolated struct WardrobeStats: Equatable, Sendable {
    var items: [ItemStats]

    var totalSpentCents: Int { items.reduce(0) { $0 + $1.purchasePriceCents } }
    var backFromSalesCents: Int { items.reduce(0) { $0 + ($1.soldPriceCents ?? 0) } }
    var netCostCents: Int { items.reduce(0) { $0 + $1.netCostCents } }
    var wearCount: Int { items.reduce(0) { $0 + $1.wearCount } }

    var averageCostPerWearCents: Double? {
        wearCount > 0 ? Double(netCostCents) / Double(wearCount) : nil
    }

    /// Days since the earliest purchase, at least 1 once there is an item.
    func daysTracked(now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let first = items.map(\.purchaseDate).min() else { return 0 }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: now)
        ).day ?? 0
        return max(1, days)
    }

    /// Net cost of everything bought, spread over the days since the first purchase.
    func costPerDayCents(now: Date = .now, calendar: Calendar = .current) -> Double? {
        let days = daysTracked(now: now, calendar: calendar)
        return days > 0 ? Double(netCostCents) / Double(days) : nil
    }
}
