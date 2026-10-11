#if DEBUG
import Foundation
import SwiftData
import UIKit

/// Debug-only sample wardrobe based on the designs (generic names, no brands,
/// so it can be used in App Store screenshots), for trying
/// things out. Enable with the launch argument `-demoData YES`; it lives in an
/// in-memory store and never touches real data or iCloud.
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "demoData") }

    /// `-demoLarge YES`: a 43-item wardrobe with real-sized photos in an
    /// on-disk store, like a real phone, for measuring performance.
    static var isLarge: Bool { UserDefaults.standard.bool(forKey: "demoLarge") }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([Item.self, DayLog.self, Repair.self, PieceEvent.self])
        let configuration: ModelConfiguration
        if isLarge {
            let url = URL.temporaryDirectory.appending(path: "demo-\(UUID().uuidString).store")
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        insertSamples(into: container.mainContext)
        if isLarge { insertLargeWardrobe(into: container.mainContext) }
        try? container.mainContext.save()
        return container
    }

    /// Fills up to 43 items and gives every item a generated photo of
    /// realistic size (1200 px original, cutout and 600 px thumbnail).
    private static func insertLargeWardrobe(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let categories: [ItemCategory] = [.tops, .knitwear, .bottoms, .outerwear, .footwear, .headwear, .underwear]
        for index in existing.count..<43 {
            let item = Item(name: "Demo item \(index + 1)", category: categories[index % categories.count],
                            purchaseDate: date(2022, 1 + index % 12), purchasePriceCents: 5_000 + index * 700,
                            priorWearCount: index * 3)
            context.insert(item)
        }
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        for (index, item) in all.enumerated() {
            let image = sampleImage(seed: index)
            guard let full = PhotoProcessor.render(image, maxSide: PhotoProcessor.fullSize, opaque: true),
                  let thumb = PhotoProcessor.render(image, maxSide: PhotoProcessor.thumbnailSize, opaque: false)
            else { continue }
            item.photoOriginal = PhotoProcessor.encode(full, hasAlpha: false)
            item.photoCutout = PhotoProcessor.encode(full, hasAlpha: true)
            item.thumbnail = PhotoProcessor.encode(thumb, hasAlpha: true)
            item.usesCutout = true
        }
    }

    /// A noisy gradient, so the encoded photo is about as large as a real one.
    private static func sampleImage(seed: Int) -> UIImage {
        let size = CGSize(width: 1500, height: 2000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            var generator = SystemRandomNumberGenerator()
            for row in stride(from: 0, to: Int(size.height), by: 8) {
                for column in stride(from: 0, to: Int(size.width), by: 8) {
                    let hue = (Double(seed) * 0.13 + Double(row) / 4000).truncatingRemainder(dividingBy: 1)
                    UIColor(hue: hue, saturation: 0.5, brightness: Double.random(in: 0.3...0.9, using: &generator),
                            alpha: 1).setFill()
                    context.fill(CGRect(x: column, y: row, width: 8, height: 8))
                }
            }
        }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func insertSamples(into context: ModelContext) {
        let samples: [(String, ItemCategory, Date, Int, Int, Int, Int, WeatherConditions, String)] = [
            ("Leather work boots", .footwear, date(2020, 3, 14), 349, 243, -25, 15, .all, "#2A1F16"),
            ("Raw denim jeans", .bottoms, date(2020, 5), 110, 298, -30, 25, .all, "#151B2B"),
            ("Wool mackinaw jacket", .outerwear, date(2021, 1), 395, 141, -20, 10, [.sun, .cloudy, .snow, .wind], "#2B1B1B"),
            ("Waxed cotton jacket", .outerwear, date(2021, 9), 389, 210, -5, 15, .all, "#1F2119"),
            ("Rain shell", .outerwear, date(2023, 2), 600, 96, -15, 20, [.rain, .snow, .wind, .cloudy], "#1C2216"),
            ("Aran wool sweater", .knitwear, date(2023, 10), 420, 58, -20, 10, .all, "#25231D"),
            ("Leather sandals", .footwear, date(2022, 6), 120, 64, 20, 35, [.sun, .cloudy], "#2A2219"),
            ("Linen shirt", .tops, date(2024, 5), 165, 9, 20, 35, [.sun, .cloudy], "#22221E"),
        ]
        var owned: [Item] = []
        for (name, category, bought, price, wears, low, high, conditions, tint) in samples {
            let item = Item(name: name, category: category, purchaseDate: bought, purchasePriceCents: price * 100,
                            priorWearCount: wears, minTempC: low, maxTempC: high, conditions: conditions)
            item.tintHex = tint
            context.insert(item)
            owned.append(item)
        }
        owned[0].notes = "Resoled with Vibram 430, Nov 2024. Conditioned every autumn."
        owned[0].isFavorite = true
        owned[1].isFavorite = true
        owned[2].boughtSecondHand = true
        owned[3].boughtSecondHand = true

        // More jeans, so Pants has something to pick between.
        for (name, price, wears, tint) in [("Selvedge jeans", 200, 41, "#141A26"), ("Black jeans", 140, 23, "#161C22")] {
            let jeans = Item(name: name, category: .bottoms, purchaseDate: date(2024, 4), purchasePriceCents: price * 100,
                             priorWearCount: wears, minTempC: -30, maxTempC: 25)
            jeans.tintHex = tint
            context.insert(jeans)
            owned.append(jeans)
        }
        // Owned but not worn: hidden on Today.
        owned[owned.count - 1].isInactive = true
        // Daily drivers: worn every day, any weather.
        var drivers: [Item] = []
        for (name, price, wears, tint) in [("Field watch", 495, 1620, "#2A2A2E"), ("Leather belt", 130, 1400, "#2A1D14"),
                                           ("Card wallet", 89, 2100, "#1E1A17")] {
            let item = Item(name: name, category: .accessories, purchaseDate: date(2020, 6), purchasePriceCents: price * 100,
                            priorWearCount: wears)
            item.tintHex = tint
            item.isDailyDriver = true
            context.insert(item)
            drivers.append(item)
        }
        // Not worn since it was added over a year ago: a sell suggestion.
        let chinos = Item(name: "Stone chinos", category: .bottoms, purchaseDate: date(2023, 5), purchasePriceCents: 9_500,
                          priorWearCount: 12, minTempC: 5, maxTempC: 28)
        chinos.tintHex = "#25231D"
        context.insert(chinos)

        insertWearLog(boots: owned[0], jeans: owned[1], into: context)
        // Today's outfit so far: boots, jeans, the sweater and the daily drivers.
        let today = DayLog(dayKey: DayKey.make(for: .now))
        context.insert(today)
        today.items = [owned[0], owned[1], owned[5]] + drivers
        today.userEdited = true
        // Everything was "added" long ago, so Insights can show an unworn item.
        for item in owned + drivers { item.createdAt = Calendar.current.date(byAdding: .day, value: -140, to: .now)! }
        chinos.createdAt = Calendar.current.date(byAdding: .month, value: -14, to: .now)!

        let sold: [(String, Date, Int, Int, Date, Int, String)] = [
            ("Service boots", date(2021, 4), 520, 88, date(2026, 3, 10), 335, "#261C14"),
            ("Black leather boots", date(2020, 2), 170, 230, date(2025, 6, 2), 45, "#1C1714"),
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

    /// A year of logged wears for the boots and jeans, heaviest in winter,
    /// like the item detail design.
    private static func insertWearLog(boots: Item, jeans: Item, into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date.now
        let perMonth = [7, 14, 3, 1, 2, 6, 15, 21, 25, 27, 26, 22] // this month first, going back
        for (offset, count) in perMonth.enumerated() {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: now),
                  let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
            else { continue }
            for day in 0..<count {
                guard let date = calendar.date(byAdding: .day, value: day, to: start), date <= now else { continue }
                let log = DayLog(dayKey: DayKey.make(for: date))
                context.insert(log)
                log.items = [boots, jeans]
            }
        }
    }
}
#endif
