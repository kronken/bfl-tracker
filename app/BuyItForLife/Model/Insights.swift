import Foundation

// Daily insights: one short, timely fact a day, picked at random (weighted by
// score) from what the rules in InsightRules.swift find. Everything here is
// plain values so it can be tested without SwiftData.

// MARK: - Categories

nonisolated enum InsightCategory: String, CaseIterable, Codable, Sendable {
    // `care` keeps its stored value; it's now titled for repairs, second-hand and gifts.
    case value, habits, weather, brands, care, types, careLog, buyLess

    var title: String {
        switch self {
        case .value: "Value & milestones"
        case .habits: "Habits"
        case .weather: "Weather"
        case .brands: "Brands & origin"
        case .care: "Repairs, second-hand & gifts"
        case .types: "Kinds of items"
        case .careLog: "Care"
        case .buyLess: "Buy less"
        }
    }

    /// Settings subtitle.
    var summary: String {
        switch self {
        case .value: "Cost per wear, paid off, anniversaries"
        case .habits: "Most worn, streaks, combinations"
        case .weather: "What you wear when it’s cold, wet or warm"
        case .brands: "Brands, brand countries, where things are made"
        case .care: "Repairs, pre-owned pieces, gifts"
        case .types: "How many of one kind, and which gets worn"
        case .careLog: "Washing, waxing, oiling and how often"
        case .buyLess: "Days without buying, budgets"
        }
    }

    /// Categories with their own switch in Settings. Buy less follows the
    /// buy-less goals instead.
    static let switchable: [InsightCategory] = [.value, .habits, .weather, .brands, .care, .types, .careLog]
}

// MARK: - Context

/// One item as the rules see it.
nonisolated struct InsightItem: Sendable {
    struct Repair: Sendable {
        var name: String
        var date: Date
        var cents: Int
    }

    struct CareEntry: Sendable {
        var actionID: UUID
        var actionName: String
        var isWashing: Bool
        var date: Date
    }

    var id: UUID
    /// The list name (without a leading brand).
    var name: String
    var categoryID: UUID?
    var categoryName = ""
    var typeID: UUID?
    /// Plural, as typed: "Denim jackets".
    var typeName: String?
    var isFavorite = false
    var isDailyDriver = false
    var isGift = false
    var isSecondHand = false
    var isInactive = false
    var isSold: Bool { stats.soldDate != nil }
    var createdAt: Date
    var stats: ItemStats
    var brand: String?
    var brandCountry: String?
    var madeIn: String?
    var minTempC = -30
    var maxTempC = 35
    var conditions: WeatherConditions = .all
    var repairs: [Repair] = []
    var careLog: [CareEntry] = []

    var purchaseDate: Date { stats.purchaseDate }
}

/// One logged day.
nonisolated struct InsightDay: Sendable {
    var dayKey: String
    var date: Date
    var itemIDs: Set<UUID>
    /// The weather stored with the day, if any.
    var temperatureC: Double?
    var conditions: WeatherConditions?
}

nonisolated struct InsightForecast: Sendable, Equatable {
    var lowC: Double
    var highC: Double
    var conditions: WeatherConditions
}

nonisolated struct InsightBuyLess: Sendable {
    var stats: BuyLessStats
    var monthlyLimitCents: Int
    var yearlyBudgetCents: Int
}

/// Everything the rules can look at.
nonisolated struct InsightContext: Sendable {
    var items: [InsightItem]
    /// Days with something logged, oldest first.
    var days: [InsightDay]
    var now: Date
    var calendar: Calendar = .current
    /// Today's weather, if loaded.
    var currentTempC: Double?
    var tomorrow: InsightForecast?
    var paidOffTargetCents: Int = 100
    /// Items unworn this long are under To sell.
    var sellSuggestionMonths: Int = 12
    /// nil when buy-less goals are off.
    var buyLess: InsightBuyLess?

    var owned: [InsightItem] { items.filter { !$0.isSold } }
    var todayKey: String { DayKey.make(for: now, calendar: calendar) }
    func item(_ id: UUID) -> InsightItem? { items.first { $0.id == id } }
}

/// What a rule needs before it is worth asking.
nonisolated enum DataRequirement: Sendable {
    case none
    case daysLogged(Int)
    case itemsWithBrand(Int)
    case buyLessGoals
    /// At least five owned items have a type. Per-type and per-action
    /// minimums are checked by the rules themselves.
    case typesInUse

    func isMet(by context: InsightContext) -> Bool {
        switch self {
        case .none: true
        case .daysLogged(let count): context.days.count >= count
        case .itemsWithBrand(let count): context.owned.count { $0.brand != nil } >= count
        case .buyLessGoals: context.buyLess != nil
        case .typesInUse: context.owned.count { $0.typeID != nil } >= 5
        }
    }
}

// MARK: - Rules and candidates

nonisolated struct InsightCandidate: Equatable, Sendable {
    var ruleId: String
    var category: InsightCategory
    /// The specific fact, e.g. "workhorse:<item>:2026", for repeat suppression.
    var key: String
    var title: String
    var detail: String?
    /// The rule's base priority; `InsightEngine.score` adds the bonuses.
    var score: Double
    /// About today or tomorrow (weather, an anniversary today).
    var isTimely = false
    var isMilestone = false
    var mentionsMoney = false
    var relatedItemId: UUID?
    /// Slow-changing facts (brands, trends) are kept away for 30 days, not 7.
    var isSlow = false
}

nonisolated protocol InsightRule: Sendable {
    var id: String { get }
    var category: InsightCategory { get }
    var minimumData: DataRequirement { get }
    func evaluate(_ context: InsightContext) -> InsightCandidate?
}

// MARK: - The stored pick

/// The insight for one day, stored as soon as it's picked. `key == nil` marks
/// a day with nothing to say, so it isn't worked out again on every open.
nonisolated struct DailyInsight: Codable, Equatable, Sendable {
    var date: String
    var ruleId: String?
    var key: String?
    var title: String?
    var detail: String?
    var category: InsightCategory?
    var relatedItemId: UUID?
    var isTimely = false
    var mentionsMoney = false
    /// Keys picked earlier today and then invalidated; never picked again today.
    var excludedKeys: [String] = []

    var isEmpty: Bool { key == nil }

    static func empty(date: String, excluding: [String] = []) -> DailyInsight {
        DailyInsight(date: date, candidate: nil, excludedKeys: excluding)
    }

    init(date: String, candidate: InsightCandidate? = nil, excludedKeys: [String] = []) {
        self.date = date
        self.excludedKeys = excludedKeys
        guard let candidate else { return }
        ruleId = candidate.ruleId
        key = candidate.key
        title = candidate.title
        detail = candidate.detail
        category = candidate.category
        relatedItemId = candidate.relatedItemId
        isTimely = candidate.isTimely
        mentionsMoney = candidate.mentionsMoney
    }
}

/// What can be shown, from Settings.
nonisolated struct InsightFilter: Equatable, Sendable {
    var disabledCategories: Set<InsightCategory> = []
    var feelGood = false
    var buyLessEnabled = false

    func allows(category: InsightCategory, mentionsMoney: Bool) -> Bool {
        if disabledCategories.contains(category) { return false }
        if category == .buyLess && !buyLessEnabled { return false }
        if feelGood && mentionsMoney { return false }
        return true
    }

    func allows(_ pick: DailyInsight) -> Bool {
        guard let category = pick.category else { return true }
        return allows(category: category, mentionsMoney: pick.mentionsMoney)
    }
}

// MARK: - Engine

nonisolated enum InsightEngine {
    static let timelyBonus = 50.0
    static let milestoneBonus = 30.0
    static let noveltyBonus = 10.0
    /// Timely insights get this much more weight in the draw, so they usually win.
    static let timelyWeight = 4.0

    /// Every candidate that may be shown today, with its final score.
    static func candidates(rules: [any InsightRule], context: InsightContext, filter: InsightFilter,
                           history: [DailyInsight], excluding excluded: Set<String> = []) -> [InsightCandidate] {
        let today = context.calendar.startOfDay(for: context.now)
        func daysAgo(_ pick: DailyInsight) -> Int? {
            guard let date = DayKey.date(from: pick.date, calendar: context.calendar) else { return nil }
            return context.calendar.dateComponents([.day], from: date, to: today).day
        }
        let past = history.filter { (daysAgo($0) ?? 0) > 0 }

        var found = rules
            .filter { $0.minimumData.isMet(by: context) && filter.allows(category: $0.category, mentionsMoney: false) }
            .compactMap { $0.evaluate(context) }
            .filter { filter.allows(category: $0.category, mentionsMoney: $0.mentionsMoney) && !excluded.contains($0.key) }
            .filter { candidate in
                // Not the same fact again too soon.
                let window = candidate.isSlow ? 30 : 7
                return !past.contains { $0.key == candidate.key && (daysAgo($0) ?? .max) <= window }
            }

        // Not the same kind as yesterday, unless nothing else is left.
        if let yesterday = past.first(where: { daysAgo($0) == 1 })?.category {
            let others = found.filter { $0.category != yesterday }
            if !others.isEmpty { found = others }
        }

        return found.map { candidate in
            var scored = candidate
            if candidate.isTimely { scored.score += timelyBonus }
            if candidate.isMilestone { scored.score += milestoneBonus }
            let shownRecently = past.contains { $0.ruleId == candidate.ruleId && (daysAgo($0) ?? .max) <= 14 }
            if !shownRecently { scored.score += noveltyBonus }
            return scored
        }
    }

    /// One candidate, at random but weighted by score. The same seed and the
    /// same candidates always give the same pick.
    static func pick(from candidates: [InsightCandidate], seed: UInt64) -> InsightCandidate? {
        let sorted = candidates.sorted { $0.key < $1.key }
        let weights = sorted.map { max(1, $0.score) * ($0.isTimely ? timelyWeight : 1) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var generator = SeededGenerator(seed: seed)
        var roll = Double.random(in: 0..<total, using: &generator)
        for (candidate, weight) in zip(sorted, weights) {
            if roll < weight { return candidate }
            roll -= weight
        }
        return sorted.last
    }

    /// The seed for a day: the date and a random ID made once per install.
    static func seed(dayKey: String, installID: String) -> UInt64 {
        // FNV-1a, so it's the same on every launch (Swift's Hasher isn't).
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(dayKey)|\(installID)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// SplitMix64: small, fast and the same everywhere.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
