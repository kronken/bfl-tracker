import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

struct RepairPriceTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var boots: ItemStats {
        ItemStats(purchaseDate: date(2020, 3, 14), purchasePriceCents: 34_900, priorWearCount: 412,
                  loggedDayKeys: [], soldDate: nil, soldPriceCents: nil, repairsCents: 13_200,
                  datedCosts: [DatedCost(date: date(2020, 3, 14), cents: 34_900),
                               DatedCost(date: date(2023, 3, 3), cents: 1_200),
                               DatedCost(date: date(2024, 11, 12), cents: 12_000)])
    }

    @Test func repairsAddToTotalCostAndCostPerWear() {
        #expect(boots.totalCostCents == 48_100)
        #expect(boots.costPerWearCents?.rounded() == 117) // €481 over 412 wears
        #expect(!boots.isPaidOff(targetCents: 100))
    }

    @Test func saleIsSubtractedFromTotalCost() {
        var sold = boots
        sold.soldDate = date(2026, 1, 1)
        sold.soldPriceCents = 20_000
        #expect(sold.netCostCents == 28_100)
    }

    @Test func repairsCountInTheYearTheyWereMade() {
        let wardrobe = WardrobeStats(items: [boots])
        let years = wardrobe.spendPerYear(now: date(2026, 10, 11), calendar: calendar)
        let byYear = Dictionary(uniqueKeysWithValues: years.map { ($0.year, Int($0.cents)) })
        #expect(byYear[2020] == 34_900)
        #expect(byYear[2023] == 1_200)
        #expect(byYear[2024] == 12_000)
        #expect(wardrobe.totalSpentCents == 48_100)
        #expect(wardrobe.repairsCents == 13_200)
    }

    @Test func spendPerMonthCoversTwelveMonthsWithRepairsInTheirMonth() {
        let wardrobe = WardrobeStats(items: [boots])
        let months = wardrobe.spendPerMonth(now: date(2025, 10, 11), calendar: calendar)
        #expect(months.count == 12)
        #expect(DayKey.make(for: months.first!.monthStart, calendar: calendar) == "2024-11-01")
        #expect(months.first!.cents == 12_000) // the resole in Nov 2024
        #expect(months.dropFirst().allSatisfy { $0.cents == 0 })
    }

    @Test func costPerDayOnlyIncludesRepairsMadeByThen() {
        let wardrobe = WardrobeStats(items: [boots])
        let before = wardrobe.costPerDayCents(asOf: date(2022, 12, 31), calendar: calendar)!
        let days = Double(wardrobe.daysTracked(asOf: date(2022, 12, 31), calendar: calendar))
        #expect(before == 34_900 / days)
    }
}

@MainActor
struct IdenticalPiecesTests {
    private let context: ModelContext

    init() throws {
        let schema = Schema([Item.self, DayLog.self, Repair.self, PieceEvent.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func boxers() -> Item {
        let item = Item(name: "Cotton boxers", category: .underwear, purchaseDate: .now, purchasePriceCents: 0)
        item.isMultiPiece = true
        context.insert(item)
        let calendar = Calendar.current
        for event in [
            PieceEvent(kind: .bought, quantity: 5, date: calendar.date(byAdding: .year, value: -3, to: .now)!, priceCents: 15_000),
            PieceEvent(kind: .bought, quantity: 2, date: calendar.date(byAdding: .year, value: -2, to: .now)!, priceCents: 6_400),
            PieceEvent(kind: .retired, quantity: 1, date: calendar.date(byAdding: .month, value: -4, to: .now)!, reason: "Worn out"),
        ] {
            context.insert(event)
            event.item = item
        }
        item.syncFromPieceEvents()
        return item
    }

    @Test func piecesAndPriceFollowTheLog() {
        let item = boxers()
        #expect(item.piecesBought == 7)
        #expect(item.piecesRetired == 1)
        #expect(item.piecesInUse == 6)
        #expect(item.purchasePriceCents == 21_400)
        // Purchase date is the first purchase.
        #expect(item.purchaseDate == item.sortedPieceEvents.last!.date)
    }

    @Test func retiredPiecesKeepTheirCost() {
        let item = boxers()
        let costBefore = item.stats.totalCostCents
        let retire = PieceEvent(kind: .retired, quantity: 2, date: .now, reason: "Lost")
        context.insert(retire)
        retire.item = item
        item.syncFromPieceEvents()
        #expect(item.piecesInUse == 4)
        #expect(item.stats.totalCostCents == costBefore)
    }

    @Test func eachPurchaseCountsInItsOwnYear() {
        let stats = boxers().stats
        #expect(stats.costTimeline.map(\.cents).sorted() == [6_400, 15_000])
    }

    @Test func allRetiredIsNotOfferedOnToday() {
        let item = boxers()
        #expect(item.isOfferedOnToday(on: .now))
        let retire = PieceEvent(kind: .retired, quantity: 6, date: .now, reason: "Worn out")
        context.insert(retire)
        retire.item = item
        #expect(item.piecesInUse == 0)
        #expect(!item.isOfferedOnToday(on: .now))
    }

    @Test func identicalPiecesGoUnderBasics() {
        let item = boxers()
        item.category = .tops
        #expect(OutfitGroup(item: item) == .basics)
        #expect(OutfitGroup(category: .underwear) == .basics)
    }
}
