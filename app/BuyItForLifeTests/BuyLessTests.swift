import Foundation
import Testing
@testable import BuyItForLife

struct BuyLessTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var now: Date { date(2026, 10, 11) }

    private func stats(_ purchases: [Purchase], enabled: Date? = nil) -> BuyLessStats {
        BuyLessStats(purchases: purchases, enabledDate: enabled ?? date(2026, 1, 1), now: now, calendar: calendar)
    }

    @Test func streakCountsFromLastPurchase() {
        let s = stats([Purchase(date: date(2026, 9, 1), cents: 100, name: "Tee"),
                       Purchase(date: date(2026, 10, 1), cents: 100, name: "Jeans")])
        #expect(s.currentStreakDays == 10)
        #expect(s.lastPurchase?.name == "Jeans")
    }

    @Test func withoutPurchasesStreakStartsWhenEnabled() {
        let s = stats([], enabled: date(2026, 10, 1))
        #expect(s.currentStreakDays == 10)
        #expect(s.purchasesPerYear.isEmpty)
    }

    @Test func futurePurchasesDontResetTheStreak() {
        let s = stats([Purchase(date: date(2026, 9, 1), cents: 100, name: "Tee"),
                       Purchase(date: date(2026, 12, 24), cents: 100, name: "Gift")])
        #expect(s.currentStreakDays == 40)
    }

    @Test func longestIncludesPastGapsAndCurrent() {
        let s = stats([Purchase(date: date(2024, 1, 1), cents: 100, name: "A"),
                       Purchase(date: date(2025, 1, 1), cents: 100, name: "B"),
                       Purchase(date: date(2026, 10, 1), cents: 100, name: "C")])
        #expect(s.longestStreakDays == 638) // 1 Jan 2025 → 1 Oct 2026
        #expect(s.currentStreakDays == 10)
    }

    @Test func monthAndYearSpendAndCounts() {
        let s = stats([Purchase(date: date(2026, 10, 2), cents: 4_000, name: "A"),
                       Purchase(date: date(2026, 3, 2), cents: 10_000, name: "B"),
                       Purchase(date: date(2025, 10, 2), cents: 9_999, name: "C")])
        #expect(s.spentThisMonthCents == 4_000)
        #expect(s.spentThisYearCents == 14_000)
        #expect(s.boughtThisMonth == 1)
        #expect(s.purchasesPerYear.map(\.year) == [2025, 2026])
        #expect(s.purchasesPerYear.map(\.count) == [1, 2])
    }

    @Test func bestYearWhenThisYearIsLowest() {
        let s = stats([Purchase(date: date(2024, 2, 2), cents: 1, name: "A"),
                       Purchase(date: date(2024, 3, 2), cents: 1, name: "B"),
                       Purchase(date: date(2025, 2, 2), cents: 1, name: "C")])
        #expect(s.purchasesPerYear.map(\.count) == [2, 1, 0])
        #expect(s.isBestYear)
        #expect(BuyLessCopy.yearSummary(s).hasPrefix("From 2 a year to none this year."))
    }

    @Test func cheersNeverScold() {
        #expect(BuyLessCopy.cheer(streak: 400, goalDays: 90) == "Over a year. Your wardrobe is doing its job.")
        #expect(BuyLessCopy.cheer(streak: 95, goalDays: 90) == "Goal reached. Keep it going.")
        #expect(BuyLessCopy.cheer(streak: 3, goalDays: 90) == "New streak: 3 days. Make it count.")
        #expect(BuyLessCopy.status(streak: 42, longest: 100, goalDays: 90) == "48 days to your 90-day goal")
        #expect(BuyLessCopy.status(streak: 120, longest: 120, goalDays: 90) == "Goal of 90 days reached · longest streak yet")
    }
}
