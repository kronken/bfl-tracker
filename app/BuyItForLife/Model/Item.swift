import Foundation
import SwiftData

/// A piece of clothing. Every property is optional or defaulted, as required
/// for CloudKit sync.
@Model
final class Item {
    // Identity
    var id: UUID = UUID()
    var name: String = ""
    /// The `StarterCategory` this item had before categories became records.
    /// Kept for older app versions on other devices; `category` is what counts.
    var categoryRaw: String = StarterCategory.other.rawValue
    var category: ClothingCategory?
    /// Always one of `category`'s types, or nil.
    var itemType: ItemType?
    var notes: String = ""
    var createdAt: Date = Date.now
    var brand: Brand?
    /// Where it was made, ISO 3166-1 alpha-2 (e.g. "PT"). nil = not set.
    var madeInCountryCode: String?
    /// Free text: "M", "48", "W32 L34". nil when empty.
    var size: String?

    // Purchase
    var purchaseDate: Date = Date.now
    var purchasePriceCents: Int = 0
    /// Pre-owned, vintage or swapped.
    var boughtSecondHand: Bool = false
    /// Received as a gift: `purchasePriceCents` is then its value. Counts for
    /// cost per wear, but not as money spent.
    var isGift: Bool = false
    /// Estimated wears before the item was tracked in the app ("Worn so far").
    var priorWearCount: Int = 0

    // How it's used
    /// Listed first on Today among similar items.
    var isFavorite: Bool = false
    /// Worn every day regardless of weather (watch, belt, wallet): pre-selected
    /// on Today, never sorted by weather, never suggested for selling.
    var isDailyDriver: Bool = false
    /// Owned but not worn (wrong size, wrong style): never suggested on Today,
    /// but still in Wardrobe, Insights and To sell.
    var isInactive: Bool = false
    /// One item standing for several identical pieces (socks, boxers). Their
    /// purchases and retirements live in `pieceEvents`.
    var isMultiPiece: Bool = false

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
    @Relationship(deleteRule: .cascade, inverse: \Repair.item) var repairs: [Repair]? = []
    @Relationship(deleteRule: .cascade, inverse: \PieceEvent.item) var pieceEvents: [PieceEvent]? = []
    /// Where it's worn (see `Occasion`). Empty means Everyday.
    var occasions: [Occasion]? = []
    /// Care actions that can be logged for this item. None by default.
    var enabledCareActions: [CareAction]? = []
    @Relationship(deleteRule: .cascade, inverse: \CareLogEntry.item) var careLog: [CareLogEntry]? = []

    init(
        name: String,
        starter: StarterCategory = .other,
        purchaseDate: Date,
        purchasePriceCents: Int,
        priorWearCount: Int = 0,
        minTempC: Int = -30,
        maxTempC: Int = 35,
        conditions: WeatherConditions = .all,
        notes: String = ""
    ) {
        self.name = name
        self.categoryRaw = starter.rawValue
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
    /// Moves the item to `category`. The type is cleared unless it belongs there.
    func setCategory(_ newValue: ClothingCategory?) {
        if itemType?.category?.id != newValue?.id { itemType = nil }
        category = newValue
        categoryRaw = newValue?.seedKey ?? StarterCategory.other.rawValue
    }

    var categoryName: String { category?.name ?? StarterCategory(storedValue: categoryRaw).title }
    var categoryIconName: String { category?.iconName ?? StarterCategory(storedValue: categoryRaw).iconName }

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
        let repairs = repairs ?? []
        let purchases: [DatedCost] = isMultiPiece
            ? boughtEvents.map { DatedCost(date: $0.date, cents: $0.priceCents ?? 0) }
            : [DatedCost(date: purchaseDate, cents: purchasePriceCents)]
        // Spending leaves out what was received as a gift; repairs always count.
        let spentPurchases: [DatedCost] = isMultiPiece
            ? boughtEvents.filter { !$0.isGift }.map { DatedCost(date: $0.date, cents: $0.priceCents ?? 0) }
            : (isGift ? [] : purchases)
        let repairCosts = repairs.map { DatedCost(date: $0.date, cents: $0.priceCents) }
        return ItemStats(
            purchaseDate: purchaseDate,
            purchasePriceCents: purchasePriceCents,
            priorWearCount: priorWearCount,
            loggedDayKeys: loggedDayKeys,
            soldDate: soldDate,
            soldPriceCents: soldPriceCents,
            repairsCents: repairs.reduce(0) { $0 + $1.priceCents },
            datedCosts: purchases + repairCosts,
            spendCosts: spentPurchases + repairCosts
        )
    }

    // MARK: Repairs and identical pieces

    /// Repairs, newest first.
    var sortedRepairs: [Repair] { (repairs ?? []).sorted { $0.date > $1.date } }

    /// Piece purchases and retirements, newest first.
    var sortedPieceEvents: [PieceEvent] { (pieceEvents ?? []).sorted { $0.date > $1.date } }

    private var boughtEvents: [PieceEvent] { (pieceEvents ?? []).filter { $0.kind == .bought } }

    var piecesBought: Int { boughtEvents.reduce(0) { $0 + $1.quantity } }
    var piecesRetired: Int { (pieceEvents ?? []).filter { $0.kind == .retired }.reduce(0) { $0 + $1.quantity } }
    /// Pieces still in use; 0 means all retired.
    var piecesInUse: Int { max(0, piecesBought - piecesRetired) }

    /// For identical pieces, the purchase price and date follow the log: the
    /// sum of all purchases and the first purchase. Call after changing it.
    func syncFromPieceEvents() {
        guard isMultiPiece else { return }
        let bought = boughtEvents
        guard !bought.isEmpty else { return }
        purchasePriceCents = bought.reduce(0) { $0 + ($1.priceCents ?? 0) }
        if let first = bought.map(\.date).min() { purchaseDate = first }
    }

    /// Whether the item suits the given weather: the temperature is within its
    /// range and it's marked for at least one of the conditions.
    func suits(temperatureC: Double, conditions weather: WeatherConditions) -> Bool {
        let inRange = temperatureC >= Double(minTempC) && temperatureC <= Double(maxTempC)
        return inRange && !conditions.isDisjoint(with: weather)
    }

    /// Why the item isn't suggested for this weather, e.g. "Best above 18°C".
    func unsuitedReason(temperatureC: Double, conditions weather: WeatherConditions) -> String {
        if temperatureC < Double(minTempC) { return "Best above \(Temperature.format(celsius: minTempC))" }
        if temperatureC > Double(maxTempC) { return "Best below \(Temperature.format(celsius: maxTempC))" }
        let names = WeatherConditions.options.filter { weather.contains($0.condition) }.map { $0.title.lowercased() }
        return names.isEmpty ? "Not for this weather" : "Not for \(names.joined(separator: " or "))"
    }

    /// Whether Today should offer the item on `day`: owned then and not inactive.
    func isOfferedOnToday(on day: Date, calendar: Calendar = .current) -> Bool {
        !isInactive && !(isMultiPiece && piecesInUse == 0) && wasOwned(on: day, calendar: calendar)
    }

    /// Whether the item was in the wardrobe on `day`: bought on or before it,
    /// and not sold before it.
    func wasOwned(on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard calendar.startOfDay(for: purchaseDate) <= start else { return false }
        guard let soldDate else { return true }
        return calendar.startOfDay(for: soldDate) >= start
    }

    /// Days since the item was last logged as worn, or since it was added if
    /// it never has been. nil for sold items.
    func daysUnworn(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard !isSold else { return nil }
        let lastWorn = stats.lastWornDayKey.flatMap { DayKey.date(from: $0, calendar: calendar) }
        let since = max(lastWorn ?? .distantPast, calendar.startOfDay(for: createdAt))
        return max(0, calendar.dateComponents([.day], from: since, to: calendar.startOfDay(for: now)).day ?? 0)
    }

    /// Since when the item hasn't been worn: its last logged wear, or the day
    /// it was added to the app if it has never been logged. (Not the purchase
    /// date: "worn so far" estimates have no dates, so an old item added today
    /// shouldn't count as unworn for years.)
    func unwornSince(calendar: Calendar = .current) -> Date {
        if let key = stats.lastWornDayKey, let day = DayKey.date(from: key, calendar: calendar) { return day }
        return calendar.startOfDay(for: max(createdAt, purchaseDate))
    }

    /// Whole months since `unwornSince`.
    func monthsUnworn(now: Date = .now, calendar: Calendar = .current) -> Int {
        let months = calendar.dateComponents([.month], from: unwornSince(calendar: calendar),
                                             to: calendar.startOfDay(for: now)).month ?? 0
        return max(0, months)
    }

    /// Owned, not a daily driver, and unworn for at least `months` months.
    func isSellSuggestion(months: Int, now: Date = .now, calendar: Calendar = .current) -> Bool {
        !isSold && !isDailyDriver && monthsUnworn(now: now, calendar: calendar) >= months
    }
}
