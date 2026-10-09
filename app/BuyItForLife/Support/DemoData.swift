#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample wardrobe from the designs, for screenshots and trying
/// things out. Enable with the launch argument `-demoData YES`; it lives in an
/// in-memory store and never touches real data or iCloud.
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "demoData") }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([Item.self, DayLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        insertSamples(into: container.mainContext)
        return container
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func insertSamples(into context: ModelContext) {
        let samples: [(String, ItemCategory, Date, Int, Int, Int, Int, WeatherConditions, String)] = [
            ("Red Wing Iron Ranger 8111", .footwear, date(2020, 3, 14), 349, 412, -25, 15, .all, "#2A1F16"),
            ("Levi’s 501 Shrink-to-Fit", .bottoms, date(2020, 5), 110, 298, -30, 25, .all, "#151B2B"),
            ("Filson Mackinaw Cruiser", .outerwear, date(2021, 1), 395, 141, -20, 10, [.sun, .cloudy, .snow, .wind], "#2B1B1B"),
            ("Barbour Bedale", .outerwear, date(2021, 9), 389, 210, -5, 15, .all, "#1F2119"),
            ("Arc’teryx Beta AR", .outerwear, date(2023, 2), 600, 96, -15, 20, [.rain, .snow, .wind, .cloudy], "#1C2216"),
            ("Inis Meáin Aran crewneck", .knitwear, date(2023, 10), 420, 58, -20, 10, .all, "#25231D"),
            ("Birkenstock Arizona", .footwear, date(2022, 6), 120, 64, 20, 35, [.sun, .cloudy], "#2A2219"),
            ("Sunspel linen shirt", .tops, date(2024, 5), 165, 9, 20, 35, [.sun, .cloudy], "#22221E"),
        ]
        for (name, category, bought, price, wears, low, high, conditions, tint) in samples {
            let item = Item(name: name, category: category, purchaseDate: bought, purchasePriceCents: price * 100,
                            priorWearCount: wears, minTempC: low, maxTempC: high, conditions: conditions)
            item.tintHex = tint
            context.insert(item)
        }

        let sold: [(String, Date, Int, Int, Date, Int, String)] = [
            ("Viberg Service Boot", date(2021, 4), 520, 88, date(2026, 3, 10), 335, "#261C14"),
            ("Dr. Martens 1460", date(2020, 2), 170, 230, date(2025, 6, 2), 45, "#1C1714"),
        ]
        for (name, bought, price, wears, soldOn, soldFor, tint) in sold {
            let item = Item(name: name, category: .footwear, purchaseDate: bought, purchasePriceCents: price * 100,
                            priorWearCount: wears, minTempC: -20, maxTempC: 15)
            item.soldDate = soldOn
            item.soldPriceCents = soldFor * 100
            item.tintHex = tint
            context.insert(item)
        }
    }
}
#endif
