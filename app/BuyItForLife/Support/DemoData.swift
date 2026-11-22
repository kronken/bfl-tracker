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
        let schema = Schema(AppSchema.models)
        let configuration: ModelConfiguration
        if isLarge {
            let url = URL.temporaryDirectory.appending(path: "demo-\(UUID().uuidString).store")
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        insertSamples(into: container.mainContext)
        if UserDefaults.standard.bool(forKey: "demoOccasions") { insertOccasions(into: container.mainContext) }
        if UserDefaults.standard.bool(forKey: "demoBrands") { insertBrands(into: container.mainContext) }
        if UserDefaults.standard.bool(forKey: "demoStores") { insertStores(into: container.mainContext) }
        // Categories from the items' starter categories, as for an upgrading user.
        ClothingCategory.ensureSetup(in: container.mainContext, defaults: UserDefaults(suiteName: "demo-\(UUID())")!)
        if UserDefaults.standard.bool(forKey: "demoCare") { insertTypesAndCare(into: container.mainContext) }
        if isLarge { insertLargeWardrobe(into: container.mainContext) }
        try? container.mainContext.save()
        return container
    }

    /// Fills up to 43 items and gives every item a generated photo of
    /// realistic size (1200 px original, cutout and 600 px thumbnail).
    private static func insertLargeWardrobe(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let categories: [StarterCategory] = [.tops, .knitwear, .bottoms, .outerwear, .footwear, .headwear, .underwear]
        for index in existing.count..<43 {
            let item = Item(name: "Demo item \(index + 1)", starter: categories[index % categories.count],
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
        let samples: [(String, StarterCategory, Date, Int, Int, Int, Int, WeatherConditions, String)] = [
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
            let item = Item(name: name, starter: category, purchaseDate: bought, purchasePriceCents: price * 100,
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
            let jeans = Item(name: name, starter: .bottoms, purchaseDate: date(2024, 4), purchasePriceCents: price * 100,
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
            let item = Item(name: name, starter: .accessories, purchaseDate: date(2020, 6), purchasePriceCents: price * 100,
                            priorWearCount: wears)
            item.tintHex = tint
            item.isDailyDriver = true
            context.insert(item)
            drivers.append(item)
        }
        drivers[0].isGift = true // the watch was a present
        // Repairs on the boots.
        for (name, details, when, price) in [("Resole", "Vibram 430 mini-lug sole and new heel", date(2024, 11, 12), 120),
                                             ("New laces", "Original leather laces", date(2023, 3, 3), 12)] {
            let repair = Repair(name: name, details: details, date: when, priceCents: price * 100)
            context.insert(repair)
            repair.item = owned[0]
        }
        // Identical pieces: a set of boxers.
        let boxers = Item(name: "Cotton boxers", starter: .underwear, purchaseDate: date(2023, 1, 14),
                          purchasePriceCents: 0, priorWearCount: 600)
        boxers.isMultiPiece = true
        boxers.tintHex = "#1D1F26"
        context.insert(boxers)
        for event in [PieceEvent(kind: .bought, quantity: 5, date: date(2023, 1, 14), priceCents: 15_000),
                      PieceEvent(kind: .bought, quantity: 2, date: date(2024, 9, 2), priceCents: 6_400),
                      PieceEvent(kind: .retired, quantity: 1, date: date(2026, 6, 18), reason: "Worn out")] {
            context.insert(event)
            event.item = boxers
        }
        boxers.syncFromPieceEvents()

        // Recent purchases, so the monthly spend chart has something to show.
        for (name, category, monthsAgo, price) in [("Merino tee", StarterCategory.tops, 2, 85), ("Wool beanie", .headwear, 5, 45)] {
            let recent = Item(name: name, starter: category,
                              purchaseDate: Calendar.current.date(byAdding: .month, value: -monthsAgo, to: .now)!,
                              purchasePriceCents: price * 100, priorWearCount: 10, minTempC: -20, maxTempC: 20)
            context.insert(recent)
        }

        // Not worn since it was added over a year ago: a sell suggestion.
        let chinos = Item(name: "Stone chinos", starter: .bottoms, purchaseDate: date(2023, 5), purchasePriceCents: 9_500,
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
            let item = Item(name: name, starter: .footwear, purchaseDate: bought, purchasePriceCents: price * 100,
                            priorWearCount: wears, minTempC: -20, maxTempC: 15)
            item.soldDate = soldOn
            item.soldPriceCents = soldFor * 100
            item.tintHex = tint
            context.insert(item)
        }
    }

    /// `-demoOccasions YES`: Everyday, Office on weekdays and Gym, like the
    /// designs. Office gets the boots, jeans, sweater and rain shell; Gym is
    /// empty, to show its empty card.
    private static func insertOccasions(into context: ModelContext) {
        let everyday = Occasion.ensureBuiltIn(in: context)
        let office = Occasion(name: "Office", weekdays: .workweek, sortOrder: 1)
        let gym = Occasion(name: "Gym", sortOrder: 2)
        context.insert(office)
        context.insert(gym)
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let officeNames: Set = ["Leather work boots", "Raw denim jeans", "Selvedge jeans", "Aran wool sweater",
                                "Rain shell", "Field watch", "Leather belt", "Linen shirt", "Cotton boxers"]
        for item in items where officeNames.contains(item.name) {
            item.occasions = item.name == "Selvedge jeans" ? [office] : [everyday, office]
        }
    }

    /// `-demoBrands YES`: made-up brands with home countries, plus where
    /// items were made and their sizes.
    private static func insertBrands(into context: ModelContext) {
        let brands: [String: Brand] = [
            "Northfield": Brand(name: "Northfield", countryCode: "US"),
            "Harlow & Sons": Brand(name: "Harlow & Sons", countryCode: "GB"),
            "Fjell": Brand(name: "Fjell", countryCode: "NO"),
            "Atelier Brun": Brand(name: "Atelier Brun", countryCode: "FR"),
            "Kettle Island": Brand(name: "Kettle Island", countryCode: "IE"),
            "Uhrwerk": Brand(name: "Uhrwerk", countryCode: "CH"),
            "Selva": Brand(name: "Selva", countryCode: "IT"),
            "Polar Mill": Brand(name: "Polar Mill", countryCode: nil),
        ]
        brands.values.forEach(context.insert)
        let assignments: [String: (brand: String, madeIn: String?, size: String?)] = [
            "Leather work boots": ("Northfield", "US", "9.5 D"),
            "Raw denim jeans": ("Northfield", "JP", "W32 L34"),
            "Selvedge jeans": ("Atelier Brun", "JP", "W32 L32"),
            "Wool mackinaw jacket": ("Northfield", "US", "M"),
            "Waxed cotton jacket": ("Harlow & Sons", "GB", "40"),
            "Rain shell": ("Fjell", "VN", "M"),
            "Aran wool sweater": ("Kettle Island", "IE", "M"),
            "Leather sandals": ("Selva", "IT", "43"),
            "Linen shirt": ("Atelier Brun", "PT", "M"),
            "Field watch": ("Uhrwerk", "CH", nil),
            "Leather belt": ("Harlow & Sons", "GB", "85"),
            "Cotton boxers": ("Polar Mill", "PT", "M"),
        ]
        for item in (try? context.fetch(FetchDescriptor<Item>())) ?? [] {
            guard let assignment = assignments[item.name] else { continue }
            item.brand = brands[assignment.brand]
            item.madeInCountryCode = assignment.madeIn
            item.size = assignment.size
        }
    }

    /// `-demoStores YES`: made-up stores; most items get one, gifts never.
    private static func insertStores(into context: ModelContext) {
        let stores = ["Northside Supply", "Harbor & Pine", "Kallio Vintage", "Linden Department Store", "Second Loop"]
            .map { Store(name: $0) }
        stores.forEach(context.insert)
        let items = ((try? context.fetch(FetchDescriptor<Item>())) ?? []).sorted { $0.name < $1.name }
        // Every sixth item is left without a store.
        for (index, item) in items.enumerated() where !item.isGift && index % 6 != 5 {
            item.store = stores[index % stores.count]
        }
    }

    /// `-demoCare YES`: a few types, and oiling and waxing logged on the boots
    /// and the waxed jacket.
    private static func insertTypesAndCare(into context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<ClothingCategory>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        func item(_ name: String) -> Item? { items.first { $0.name == name } }
        func category(_ seed: StarterCategory) -> ClothingCategory? { categories.first { $0.seedKey == seed.rawValue } }

        if let footwear = category(.footwear) {
            let boots = ItemType.create(name: "Leather boots", in: footwear, context: context)
            let sandals = ItemType.create(name: "Sandals", in: footwear, context: context)
            for name in ["Leather work boots", "Service boots", "Black leather boots"] { item(name)?.itemType = boots }
            item("Leather sandals")?.itemType = sandals
        }
        if let bottoms = category(.bottoms) {
            let jeans = ItemType.create(name: "Jeans", in: bottoms, context: context)
            for name in ["Raw denim jeans", "Selvedge jeans", "Black jeans"] { item(name)?.itemType = jeans }
        }
        if let outerwear = category(.outerwear) {
            let waxed = ItemType.create(name: "Waxed jackets", in: outerwear, context: context)
            _ = ItemType.create(name: "Wool jackets", in: outerwear, context: context)
            item("Waxed cotton jacket")?.itemType = waxed
        }

        let washing = CareAction.ensureWashing(in: context)
        let oiling = CareAction.create(name: "Oiling", in: context)
        let waxing = CareAction.create(name: "Waxing", in: context)
        let log: [(String, CareAction, [Int], String?)] = [
            ("Leather work boots", oiling, [25, 90, 160, 230, 300], "Mink oil, two thin coats"),
            ("Waxed cotton jacket", waxing, [40, 400], nil),
            ("Linen shirt", washing, [3, 10], nil),
        ]
        for (name, action, daysAgo, note) in log {
            guard let target = item(name) else { continue }
            target.enabledCareActions = (target.enabledCareActions ?? []) + [action]
            for (index, days) in daysAgo.enumerated() {
                let entry = CareLogEntry(date: Calendar.current.date(byAdding: .day, value: -days, to: .now)!,
                                         note: index == 0 ? note : nil)
                context.insert(entry)
                entry.item = target
                entry.action = action
            }
        }
        item("Leather work boots")?.enabledCareActions?.append(waxing)
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
                // Helsinki-like noon temperatures, so weather insights have history.
                let monthTemps = [-5.0, -6, -2, 4, 11, 16, 19, 17, 12, 6, 1, -3]
                let temperature = monthTemps[calendar.component(.month, from: date) - 1] + Double(day % 5 - 2)
                log.store(WeatherSnapshot(temperatureC: temperature, feelsLikeC: temperature - 3,
                                          conditionRaw: day % 4 == 0 ? "rain" : "cloudy", symbolName: "cloud",
                                          placeName: "Helsinki"))
            }
        }
    }
}
#endif
