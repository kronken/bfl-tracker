import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

@MainActor
struct GiftTests {
    private let context: ModelContext
    private let calendar = Calendar.current

    init() throws {
        let schema = Schema([Item.self, DayLog.self, Repair.self, PieceEvent.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: .now)! }

    private func watch(gift: Bool) -> Item {
        let item = Item(name: "Field watch", category: .accessories, purchaseDate: daysAgo(400),
                        purchasePriceCents: 49_500, priorWearCount: 495)
        item.isGift = gift
        context.insert(item)
        return item
    }

    @Test func giftValueSetsCostPerWearButIsNotSpending() {
        let stats = watch(gift: true).stats
        #expect(stats.totalCostCents == 49_500)
        #expect(stats.costPerWearCents == 100)        // item-level: value / wears
        #expect(stats.spendCents == 0)                // spending: nothing paid
        #expect(stats.netSpendCents == 0)
    }

    @Test func repairsOnGiftsAreRealSpending() {
        let item = watch(gift: true)
        let service = Repair(name: "Service", date: daysAgo(30), priceCents: 12_000)
        context.insert(service)
        service.item = item
        #expect(item.stats.totalCostCents == 61_500)
        #expect(item.stats.spendCents == 12_000)
        let wardrobe = WardrobeStats(items: [item.stats])
        #expect(wardrobe.totalSpentCents == 12_000)
        #expect(wardrobe.repairsCents == 12_000)
    }

    @Test func wardrobeSpendingExcludesGifts() {
        let bought = watch(gift: false)
        bought.name = "Bought watch"
        let gifted = watch(gift: true)
        let wardrobe = WardrobeStats(items: [bought.stats, gifted.stats])
        #expect(wardrobe.totalSpentCents == 49_500)
        #expect(wardrobe.netSpendCents == 49_500)
        let thisYear = calendar.component(.year, from: daysAgo(400))
        let year = wardrobe.spendPerYear().first { $0.year == thisYear }
        #expect(year?.cents == 49_500)
    }

    @Test func giftsAreNotPurchasesForBuyLess() {
        let gifted = watch(gift: true)
        gifted.purchaseDate = daysAgo(2)
        #expect(gifted.purchases.isEmpty)
        let stats = BuyLessStats(purchases: [gifted].flatMap(\.purchases), enabledDate: daysAgo(40))
        #expect(stats.currentStreakDays == 40)   // receiving a gift doesn't reset the streak
        #expect(stats.spentThisYearCents == 0)
    }

    @Test func giftedSetFirstEventIsGiftButAddMoreIsAPurchase() {
        let socks = Item(name: "Wool socks", category: .underwear, purchaseDate: daysAgo(100), purchasePriceCents: 0)
        socks.isMultiPiece = true
        socks.isGift = true
        context.insert(socks)
        let first = PieceEvent(kind: .bought, quantity: 3, date: daysAgo(100), priceCents: 4_500)
        first.isGift = true
        let more = PieceEvent(kind: .bought, quantity: 2, date: daysAgo(10), priceCents: 3_000)
        for event in [first, more] {
            context.insert(event)
            event.item = socks
        }
        socks.syncFromPieceEvents()
        #expect(socks.stats.totalCostCents == 7_500)   // both count for cost per wear
        #expect(socks.stats.spendCents == 3_000)       // only the bought pair is spending
        #expect(socks.purchases.map(\.cents) == [3_000])
    }
}
