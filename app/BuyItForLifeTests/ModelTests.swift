import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

struct DayKeyTests {
    private let helsinki: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return c
    }()

    @Test func formatsWithZeroPadding() {
        let date = helsinki.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 9))!
        #expect(DayKey.make(for: date, calendar: helsinki) == "2026-03-05")
    }

    @Test func usesTheCalendarsTimeZone() {
        // 23:30 in Helsinki is still the 9th there, but already the 10th in Tokyo.
        let date = helsinki.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 30))!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(DayKey.make(for: date, calendar: helsinki) == "2026-10-09")
        #expect(DayKey.make(for: date, calendar: tokyo) == "2026-10-10")
    }

    @Test func roundTrips() {
        let date = DayKey.date(from: "2026-10-09", calendar: helsinki)!
        #expect(DayKey.make(for: date, calendar: helsinki) == "2026-10-09")
    }

    @Test func rejectsMalformedKeys() {
        #expect(DayKey.date(from: "2026-10", calendar: helsinki) == nil)
        #expect(DayKey.date(from: "", calendar: helsinki) == nil)
    }
}

struct CategoryAndConditionTests {
    @Test func unknownCategoryFallsBackToOther() {
        #expect(ItemCategory(storedValue: "swimwear") == .other)
        #expect(ItemCategory(storedValue: "knitwear") == .knitwear)
    }

    @Test func conditionBitsAreStable() {
        // Stored values must never change once data exists.
        #expect(WeatherConditions.sun.rawValue == 1)
        #expect(WeatherConditions.cloudy.rawValue == 2)
        #expect(WeatherConditions.rain.rawValue == 4)
        #expect(WeatherConditions.snow.rawValue == 8)
        #expect(WeatherConditions.wind.rawValue == 16)
        #expect(WeatherConditions.all.rawValue == 31)
    }
}

@MainActor
struct ItemAndDayLogTests {
    private let context: ModelContext

    init() throws {
        let schema = Schema([Item.self, DayLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func makeItem(min: Int = -25, max: Int = 15, conditions: WeatherConditions = .all) -> Item {
        let item = Item(name: "Red Wing Iron Ranger 8111", category: .footwear, purchaseDate: .now,
                        purchasePriceCents: 34_900, minTempC: min, maxTempC: max, conditions: conditions)
        context.insert(item)
        return item
    }

    @Test func suitsChecksRangeAndCondition() {
        let shell = makeItem(min: -15, max: 18, conditions: [.rain, .wind])
        #expect(shell.suits(temperatureC: 5, conditions: .rain))
        #expect(shell.suits(temperatureC: 18, conditions: .rain))   // range is inclusive
        #expect(!shell.suits(temperatureC: 5, conditions: .sun))    // wrong condition
        #expect(!shell.suits(temperatureC: 20, conditions: .rain))  // too warm
    }

    @Test func toggleAddsAndRemovesItem() throws {
        let item = makeItem()
        let day = try DayLog.fetchOrCreate(dayKey: "2026-10-09", in: context)
        day.toggle(item)
        #expect(day.isWorn(item))
        #expect(item.stats.wearCount == 1)
        day.toggle(item)
        #expect(!day.isWorn(item))
        #expect(item.stats.wearCount == 0)
    }

    @Test func fetchOrCreateReturnsExistingDay() throws {
        let first = try DayLog.fetchOrCreate(dayKey: "2026-10-09", in: context)
        let second = try DayLog.fetchOrCreate(dayKey: "2026-10-09", in: context)
        #expect(first === second)
    }

    @Test func fetchOrCreateMergesSyncDuplicates() throws {
        let boots = makeItem()
        let jeans = makeItem()
        let a = DayLog(dayKey: "2026-10-09")
        let b = DayLog(dayKey: "2026-10-09")
        b.temperatureC = 3
        b.conditionRaw = "drizzle"
        context.insert(a)
        context.insert(b)
        a.items = [boots]
        b.items = [boots, jeans]
        try context.save()

        let merged = try DayLog.fetchOrCreate(dayKey: "2026-10-09", in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<DayLog>())
        #expect(all.count == 1)
        #expect(merged.items?.count == 2)
        #expect(merged.temperatureC == 3)
        #expect(merged.conditionRaw == "drizzle")
    }

    @Test func duplicateDaysCountOnceForWears() {
        let boots = makeItem()
        let a = DayLog(dayKey: "2026-10-09")
        let b = DayLog(dayKey: "2026-10-09")
        context.insert(a)
        context.insert(b)
        a.items = [boots]
        b.items = [boots]
        #expect(boots.stats.wearCount == 1)
    }
}
