import Foundation
import SwiftData

/// A piece of clothing. Every property is optional or defaulted, as required
/// for CloudKit sync.
@Model
final class Item {
    // Identity
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = ItemCategory.other.rawValue
    var notes: String = ""
    var createdAt: Date = Date.now

    // Purchase
    var purchaseDate: Date = Date.now
    var purchasePriceCents: Int = 0
    /// Estimated wears before the item was tracked in the app ("Worn so far").
    var priorWearCount: Int = 0

    // Weather it's for
    var minTempC: Int = -30
    var maxTempC: Int = 35
    var conditionsRaw: Int = WeatherConditions.all.rawValue

    // Photo
    /// HEIC, 1200 px on the long side.
    @Attribute(.externalStorage) var photoOriginal: Data?
    /// HEIC with transparency; nil when no subject could be found.
    @Attribute(.externalStorage) var photoCutout: Data?
    /// HEIC, 600 px, of whichever version is chosen.
    @Attribute(.externalStorage) var thumbnail: Data?
    var usesCutout: Bool = false
    /// Darkened average colour of the photo, e.g. "#2A1F16".
    var tintHex: String?

    // Sold
    /// nil while the item is still owned.
    var soldDate: Date?
    var soldPriceCents: Int?

    // Wear log
    @Relationship(inverse: \DayLog.items) var wornOn: [DayLog]? = []

    init(
        name: String,
        category: ItemCategory,
        purchaseDate: Date,
        purchasePriceCents: Int,
        priorWearCount: Int = 0,
        minTempC: Int = -30,
        maxTempC: Int = 35,
        conditions: WeatherConditions = .all,
        notes: String = ""
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.purchaseDate = purchaseDate
        self.purchasePriceCents = purchasePriceCents
        self.priorWearCount = priorWearCount
        self.minTempC = minTempC
        self.maxTempC = maxTempC
        self.conditionsRaw = conditions.rawValue
        self.notes = notes
    }
}

extension Item {
    var category: ItemCategory {
        get { ItemCategory(storedValue: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var conditions: WeatherConditions {
        get { WeatherConditions(rawValue: conditionsRaw) }
        set { conditionsRaw = newValue.rawValue }
    }

    var isSold: Bool { soldDate != nil }

    /// Distinct days this item was logged as worn. Duplicate day logs from
    /// sync count once.
    var loggedDayKeys: Set<String> {
        Set((wornOn ?? []).map(\.dayKey))
    }

    var stats: ItemStats {
        ItemStats(
            purchaseDate: purchaseDate,
            purchasePriceCents: purchasePriceCents,
            priorWearCount: priorWearCount,
            loggedDayKeys: loggedDayKeys,
            soldDate: soldDate,
            soldPriceCents: soldPriceCents
        )
    }

    /// Whether the item suits the given weather: the temperature is within its
    /// range and the condition is one it's marked for.
    func suits(temperatureC: Double, condition: WeatherConditions) -> Bool {
        let inRange = temperatureC >= Double(minTempC) && temperatureC <= Double(maxTempC)
        return inRange && conditions.contains(condition)
    }
}
