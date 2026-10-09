import Foundation
import Testing
@testable import BuyItForLife

struct ItemStatsTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func stats(
        price: Int = 34_900,
        prior: Int = 0,
        days: Set<String> = [],
        bought: Date? = nil,
        soldDate: Date? = nil,
        soldPrice: Int? = nil
    ) -> ItemStats {
        ItemStats(
            purchaseDate: bought ?? date(2020, 3, 14),
            purchasePriceCents: price,
            priorWearCount: prior,
            loggedDayKeys: days,
            soldDate: soldDate,
            soldPriceCents: soldPrice
        )
    }

    @Test func wearCountAddsPriorEstimateAndLoggedDays() {
        let s = stats(prior: 300, days: ["2026-10-08", "2026-10-09"])
        #expect(s.wearCount == 302)
    }

    @Test func costPerWearIsNilBeforeFirstWear() {
        #expect(stats().costPerWearCents == nil)
    }

    @Test func costPerWearUsesNetCost() {
        // The design's boots: €349, 412 wears → €0.85 per wear.
        let s = stats(prior: 412)
        #expect(s.costPerWearCents?.rounded() == 85)
    }

    @Test func netCostSubtractsSalePrice() {
        let s = stats(price: 52_000, prior: 88, soldDate: date(2026, 3, 1), soldPrice: 33_500)
        #expect(s.netCostCents == 18_500)
    }

    @Test func netCostNeverGoesNegative() {
        let s = stats(price: 10_000, prior: 5, soldDate: date(2026, 3, 1), soldPrice: 15_000)
        #expect(s.netCostCents == 0)
        #expect(s.costPerWearCents == 0)
    }

    @Test func daysOwnedCountsUntilNowWhenOwned() {
        let s = stats(bought: date(2026, 10, 1))
        #expect(s.daysOwned(now: date(2026, 10, 9), calendar: calendar) == 8)
    }

    @Test func daysOwnedStopsAtSoldDate() {
        let s = stats(bought: date(2026, 1, 1), soldDate: date(2026, 1, 31), soldPrice: 0)
        #expect(s.daysOwned(now: date(2026, 10, 9), calendar: calendar) == 30)
    }

    @Test func daysOwnedIgnoresTimeOfDay() {
        let s = stats(bought: date(2026, 10, 1, hour: 23))
        #expect(s.daysOwned(now: date(2026, 10, 2, hour: 1), calendar: calendar) == 1)
    }

    @Test func lastWornIsLatestDay() {
        let s = stats(days: ["2026-09-30", "2026-10-08", "2026-10-02"])
        #expect(s.lastWornDayKey == "2026-10-08")
    }

    @Test func paidOffRequiresCostPerWearUnderTarget() {
        #expect(stats(prior: 349).isPaidOff(targetCents: 100) == false) // exactly €1.00
        #expect(stats(prior: 350).isPaidOff(targetCents: 100) == true)
        #expect(stats().isPaidOff(targetCents: 100) == false)            // never worn
    }

    @Test func paidOffAtWearIsFirstWearUnderTarget() {
        #expect(stats().paidOffAtWear(targetCents: 100) == 350)
        #expect(stats(price: 34_950).paidOffAtWear(targetCents: 100) == 350)
        #expect(stats().paidOffAtWear(targetCents: 0) == nil)
    }
}

struct WardrobeStatsTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var wardrobe: WardrobeStats {
        WardrobeStats(items: [
            ItemStats(purchaseDate: date(2020, 3, 14), purchasePriceCents: 34_900, priorWearCount: 412,
                      loggedDayKeys: [], soldDate: nil, soldPriceCents: nil),
            ItemStats(purchaseDate: date(2021, 6, 1), purchasePriceCents: 52_000, priorWearCount: 88,
                      loggedDayKeys: [], soldDate: date(2026, 3, 1), soldPriceCents: 33_500),
        ])
    }

    @Test func totalsIncludeSoldItems() {
        let w = wardrobe
        #expect(w.totalSpentCents == 86_900)
        #expect(w.backFromSalesCents == 33_500)
        #expect(w.netCostCents == 53_400)
        #expect(w.wearCount == 500)
        #expect(w.averageCostPerWearCents == 106.8)
    }

    @Test func costPerDaySpreadsNetCostSinceFirstPurchase() {
        let now = date(2020, 3, 24)
        #expect(wardrobe.daysTracked(now: now, calendar: calendar) == 10)
        #expect(wardrobe.costPerDayCents(now: now, calendar: calendar) == 5_340)
    }

    @Test func emptyWardrobeHasNoCosts() {
        let w = WardrobeStats(items: [])
        #expect(w.daysTracked(now: date(2026, 10, 9), calendar: calendar) == 0)
        #expect(w.costPerDayCents(now: date(2026, 10, 9), calendar: calendar) == nil)
        #expect(w.averageCostPerWearCents == nil)
    }
}
