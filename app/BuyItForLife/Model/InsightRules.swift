import Foundation

// The rules behind daily insights. Each looks at the context and returns at
// most one candidate. Copy: short, dry, warm; no exclamation marks; never
// shames. All wording lives in `InsightCopy` at the bottom.

nonisolated enum InsightRules {
    static let all: [any InsightRule] = starter + kindsAndCare

    static let starter: [any InsightRule] = [
        // Value & milestones
        PaidOffTodayRule(), CloseToTargetRule(), RoundWearsRule(), AnniversaryRule(), CostPerDayTrendRule(),
        CheapestPerWearRule(),
        // Habits
        WorkhorseRule(), StreakRule(), CombinationRule(), WeekdayPatternRule(), RotationRule(), ForgottenFavoriteRule(),
        // Weather
        WeatherBandRule(), LastTimeThisColdRule(), SeasonalRestRule(),
        // Brands & origin
        MostWornBrandRule(), MostOwnedBrandRule(), MadeInRegionRule(), OriginMismatchRule(),
        // Care, second-hand & gifts
        RepairPaybackRule(), SecondHandRule(), MostWornGiftRule(), DailyDriverLongevityRule(),
        // Buy less
        BuyLessStreakRule(), UnderBudgetRule(),
    ]
}

// MARK: - Helpers

nonisolated extension InsightContext {
    var startOfToday: Date { calendar.startOfDay(for: now) }

    func days(between earlier: Date, and later: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: earlier), to: calendar.startOfDay(for: later)).day ?? 0
    }

    /// Owned, worn on purpose (not daily drivers or inactive items).
    var clothes: [InsightItem] { owned.filter { !$0.isDailyDriver && !$0.isInactive } }

    /// The temperature to compare against for tomorrow.
    var tomorrowTempC: Double? { tomorrow.map { ($0.lowC + $0.highC) / 2 } }

    var yearKeyPrefix: String { String(todayKey.prefix(4)) }
}

nonisolated extension InsightItem {
    func wasWorn(on dayKey: String) -> Bool { stats.loggedDayKeys.contains(dayKey) }
}

/// Wording for every rule, in one place so it can be localised.
nonisolated enum InsightCopy {
    static func money(_ cents: Int) -> String { Money.format(cents: cents) }
    static func money(fractional cents: Double) -> String { Money.format(fractionalCents: cents) }
    static func temperature(_ celsius: Double) -> String { Temperature.format(celsius: celsius) }
    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
    static func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n.formatted()) \(many)" }

    /// "six" for small numbers, digits otherwise.
    static func spelled(_ n: Int) -> String {
        guard (0...12).contains(n) else { return n.formatted() }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en")
        return formatter.string(from: NSNumber(value: n)) ?? n.formatted()
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    static func weekday(_ date: Date, calendar: Calendar) -> String {
        calendar.standaloneWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }
}

// MARK: - Value & milestones

/// An item drops under the paid-off target with today's wear.
nonisolated struct PaidOffTodayRule: InsightRule {
    let id = "paidOffToday"
    let category = InsightCategory.value
    let minimumData = DataRequirement.none

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let target = Double(c.paidOffTargetCents)
        guard target > 0 else { return nil }
        let crossed = c.owned.filter { item in
            guard item.wasWorn(on: c.todayKey) else { return false }
            let wears = Double(item.stats.wearCount), net = Double(item.stats.netCostCents)
            guard wears > 1 else { return false }
            return net / (wears - 1) >= target && net / wears < target
        }
        guard let item = crossed.max(by: { $0.stats.netCostCents < $1.stats.netCostCents }) else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "paidOff:\(item.id)",
            title: "The \(item.name) dropped under \(InsightCopy.money(c.paidOffTargetCents)) a wear today.",
            detail: "Paid off, \(InsightCopy.count(item.stats.wearCount, "wear", "wears")) in.",
            score: 60, isTimely: true, isMilestone: true, mentionsMoney: true, relatedItemId: item.id)
    }
}

/// Ten wears or fewer to the paid-off target.
nonisolated struct CloseToTargetRule: InsightRule {
    let id = "closeToTarget"
    let category = InsightCategory.value
    let minimumData = DataRequirement.none
    static let maxWears = 10

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let close = c.owned.compactMap { item -> (InsightItem, Int)? in
            guard !item.stats.isPaidOff(targetCents: c.paidOffTargetCents), item.stats.wearCount > 0,
                  let left = item.stats.wearsUntilPaidOff(targetCents: c.paidOffTargetCents),
                  (1...Self.maxWears).contains(left) else { return nil }
            return (item, left)
        }
        guard let (item, left) = close.min(by: { $0.1 < $1.1 }) else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "close:\(item.id)",
            title: "\(InsightCopy.count(left, "more wear", "more wears")) and the \(item.name) drops under \(InsightCopy.money(c.paidOffTargetCents)).",
            detail: nil, score: 40, mentionsMoney: true, relatedItemId: item.id)
    }
}

/// 100, 250, 500, 1,000… wears reached today.
nonisolated struct RoundWearsRule: InsightRule {
    let id = "roundWears"
    let category = InsightCategory.value
    let minimumData = DataRequirement.none

    static func isRound(_ n: Int) -> Bool {
        [100, 250, 500, 750].contains(n) || (n >= 1_000 && n % 500 == 0)
    }

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        guard let item = c.owned.filter({ $0.wasWorn(on: c.todayKey) && Self.isRound($0.stats.wearCount) })
            .max(by: { $0.stats.wearCount < $1.stats.wearCount }) else { return nil }
        let wears = item.stats.wearCount
        return InsightCandidate(
            ruleId: id, category: category, key: "wears:\(item.id):\(wears)",
            title: "The \(item.name) reached \(wears.formatted()) wears today.",
            detail: "Bought \(item.purchaseDate.formatted(.dateTime.month(.wide).year())).",
            score: 50, isTimely: true, isMilestone: true, relatedItemId: item.id)
    }
}

/// A purchase anniversary within three days.
nonisolated struct AnniversaryRule: InsightRule {
    let id = "anniversary"
    let category = InsightCategory.value
    let minimumData = DataRequirement.none

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let found = c.owned.compactMap { item -> (InsightItem, years: Int, offset: Int, date: Date)? in
            let bought = c.calendar.startOfDay(for: item.purchaseDate)
            // The anniversary nearest today: this year's, or last/next year's around New Year.
            let years = c.calendar.dateComponents([.year], from: bought, to: c.startOfToday).year ?? 0
            for candidate in [years, years + 1] where candidate >= 1 {
                guard let date = c.calendar.date(byAdding: .year, value: candidate, to: bought) else { continue }
                let offset = c.days(between: c.startOfToday, and: date)
                if abs(offset) <= 3 { return (item, candidate, offset, date) }
            }
            return nil
        }
        guard let pick = found.min(by: { abs($0.offset) != abs($1.offset) ? abs($0.offset) < abs($1.offset)
                                         : $0.years > $1.years }) else { return nil }
        let name = pick.0.name
        let age = InsightCopy.spelled(pick.years)
        let title: String
        switch pick.offset {
        case 0: title = "The \(name) is \(age) \(pick.years == 1 ? "year" : "years") old today."
        case 1: title = "The \(name) turns \(age) tomorrow."
        case 2...: title = "The \(name) turns \(age) on \(InsightCopy.weekday(pick.date, calendar: c.calendar))."
        default: title = "The \(name) turned \(age) on \(InsightCopy.weekday(pick.date, calendar: c.calendar))."
        }
        return InsightCandidate(
            ruleId: id, category: category, key: "anniversary:\(pick.0.id):\(pick.years)",
            title: title,
            detail: "\(InsightCopy.count(pick.0.stats.wearCount, "wear", "wears")) since \(pick.0.purchaseDate.formatted(.dateTime.month(.wide).year())).",
            score: 35, isTimely: pick.offset == 0 || pick.offset == 1, isMilestone: true, relatedItemId: pick.0.id)
    }
}

/// Wardrobe cost per day against the end of last year.
nonisolated struct CostPerDayTrendRule: InsightRule {
    let id = "costPerDayTrend"
    let category = InsightCategory.value
    let minimumData = DataRequirement.none

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let history = WardrobeStats(items: c.items.map(\.stats)).costPerDayHistory(now: c.now, calendar: c.calendar)
        guard history.count >= 2, let now = history.last, let lastYear = history.dropLast().last,
              lastYear.year == now.year - 1 else { return nil }
        let change = now.cents - lastYear.cents
        guard abs(change) >= 1 else { return nil }
        let title = "Your wardrobe costs \(InsightCopy.money(fractional: now.cents)) a day, "
            + "\(change < 0 ? "down" : "up") \(InsightCopy.money(fractional: abs(change))) on last year."
        return InsightCandidate(
            ruleId: id, category: category, key: "trend:\(now.year)", title: title,
            detail: change < 0 ? "Every wear brings it lower." : "New things raise it at first. Wearing them brings it down.",
            score: 25, mentionsMoney: true, isSlow: true)
    }
}

/// The lowest cost per wear, among items with at least 30 wears.
nonisolated struct CheapestPerWearRule: InsightRule {
    let id = "cheapestPerWear"
    let category = InsightCategory.value
    let minimumData = DataRequirement.none
    static let minWears = 30

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let worn = c.owned.filter { $0.stats.wearCount >= Self.minWears && $0.stats.costPerWearCents != nil }
        guard worn.count >= 3, let best = worn.min(by: { $0.stats.costPerWearCents! < $1.stats.costPerWearCents! }),
              let cpw = best.stats.costPerWearCents else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "cheapest:\(best.id)",
            title: "The \(best.name) is your best value, at \(InsightCopy.money(fractional: cpw)) a wear.",
            detail: "\(InsightCopy.count(best.stats.wearCount, "wear", "wears")) for \(InsightCopy.money(best.stats.totalCostCents)).",
            score: 20, mentionsMoney: true, relatedItemId: best.id)
    }
}

// MARK: - Habits

/// The item worn on the largest share of this year's logged days.
nonisolated struct WorkhorseRule: InsightRule {
    let id = "workhorse"
    let category = InsightCategory.habits
    let minimumData = DataRequirement.daysLogged(30)
    static let minShare = 0.4

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let year = c.yearKeyPrefix
        let thisYear = c.days.filter { $0.dayKey.hasPrefix(year) }
        guard thisYear.count >= 20 else { return nil }
        let shares = c.clothes.map { item in
            (item, Double(thisYear.count { $0.itemIDs.contains(item.id) }) / Double(thisYear.count))
        }
        guard let (item, share) = shares.max(by: { $0.1 < $1.1 }), share >= Self.minShare else { return nil }
        let worn = Int((share * Double(thisYear.count)).rounded())
        return InsightCandidate(
            ruleId: id, category: category, key: "workhorse:\(item.id):\(year)",
            title: "The \(item.name) on \(InsightCopy.percent(share)) of days this year.",
            detail: "Your hardest-working piece: \(worn) of \(thisYear.count) logged days.",
            score: 40, relatedItemId: item.id)
    }
}

/// Worn several days in a row, up to today or yesterday.
nonisolated struct StreakRule: InsightRule {
    let id = "streak"
    let category = InsightCategory.habits
    let minimumData = DataRequirement.daysLogged(30)
    static let minDays = 5

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        func streak(_ item: InsightItem) -> (Int, String) {
            var day = c.startOfToday
            if !item.wasWorn(on: DayKey.make(for: day, calendar: c.calendar)) {
                day = c.calendar.date(byAdding: .day, value: -1, to: day) ?? day
            }
            var count = 0
            var start = DayKey.make(for: day, calendar: c.calendar)
            while item.wasWorn(on: DayKey.make(for: day, calendar: c.calendar)) {
                count += 1
                start = DayKey.make(for: day, calendar: c.calendar)
                guard let previous = c.calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = previous
            }
            return (count, start)
        }
        let streaks = c.clothes.map { ($0, streak($0)) }
        guard let (item, (days, start)) = streaks.max(by: { $0.1.0 < $1.1.0 }), days >= Self.minDays else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "streak:\(item.id):\(start)",
            title: "The \(item.name), \(days) days in a row.",
            detail: "Some things just work.", score: 35, relatedItemId: item.id)
    }
}

/// The same three items worn together again and again.
nonisolated struct CombinationRule: InsightRule {
    let id = "combination"
    let category = InsightCategory.habits
    let minimumData = DataRequirement.daysLogged(30)
    static let minTimes = 10

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let clothes = Dictionary(uniqueKeysWithValues: c.clothes.map { ($0.id, $0) })
        var counts: [[UUID]: Int] = [:]
        for day in c.days {
            let worn = day.itemIDs.filter { clothes[$0] != nil }.sorted { $0.uuidString < $1.uuidString }
            guard worn.count >= 3, worn.count <= 10 else { continue }
            for i in 0..<worn.count {
                for j in (i + 1)..<worn.count {
                    for k in (j + 1)..<worn.count {
                        counts[[worn[i], worn[j], worn[k]], default: 0] += 1
                    }
                }
            }
        }
        guard let (trio, times) = counts.max(by: { $0.value != $1.value ? $0.value < $1.value
                                                  : $0.key.map(\.uuidString).joined() > $1.key.map(\.uuidString).joined() }),
              times >= Self.minTimes else { return nil }
        let names = trio.compactMap { clothes[$0]?.name }
        return InsightCandidate(
            ruleId: id, category: category, key: "combo:" + trio.map(\.uuidString).joined(separator: ":"),
            title: "\(names.formatted(.list(type: .and))): together \(times) times.",
            detail: "Your most-worn combination.", score: 30)
    }
}

/// An item worn on most of one weekday.
nonisolated struct WeekdayPatternRule: InsightRule {
    let id = "weekdayPattern"
    let category = InsightCategory.habits
    let minimumData = DataRequirement.daysLogged(30)
    static let minShare = 0.6
    static let minWeekdays = 8

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        var best: (InsightItem, weekday: Int, share: Double)?
        for weekday in 1...7 {
            let days = c.days.filter { c.calendar.component(.weekday, from: $0.date) == weekday }
            guard days.count >= Self.minWeekdays else { continue }
            for item in c.clothes {
                let share = Double(days.count { $0.itemIDs.contains(item.id) }) / Double(days.count)
                if share >= Self.minShare, share > (best?.share ?? 0) { best = (item, weekday, share) }
            }
        }
        guard let best else { return nil }
        let name = c.calendar.standaloneWeekdaySymbols[best.weekday - 1]
        let tomorrow = c.calendar.date(byAdding: .day, value: 1, to: c.startOfToday).map { c.calendar.component(.weekday, from: $0) }
        return InsightCandidate(
            ruleId: id, category: category, key: "weekday:\(best.0.id):\(best.weekday)",
            title: "The \(best.0.name) on \(InsightCopy.percent(best.share)) of your \(name)s.",
            detail: tomorrow == best.weekday ? "Tomorrow is a \(name)." : nil,
            score: 25, relatedItemId: best.0.id)
    }
}

/// How much of the wardrobe was worn in the last 30 days.
nonisolated struct RotationRule: InsightRule {
    let id = "rotation"
    let category = InsightCategory.habits
    let minimumData = DataRequirement.daysLogged(30)

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let clothes = c.clothes
        guard clothes.count >= 5, let start = c.calendar.date(byAdding: .day, value: -29, to: c.startOfToday) else { return nil }
        let recent = Set(c.days.filter { $0.date >= start }.flatMap(\.itemIDs))
        let worn = clothes.count { recent.contains($0.id) }
        guard worn > 0 else { return nil }
        let share = Double(worn) / Double(clothes.count)
        let month = String(c.todayKey.prefix(7))
        return InsightCandidate(
            ruleId: id, category: category, key: "rotation:\(month)",
            title: "You wore \(worn) of your \(clothes.count) pieces in the last 30 days.",
            detail: share >= 0.6 ? "A well-used wardrobe." : "The rest are waiting their turn.",
            score: 15)
    }
}

/// A favorite unworn for a while, when the weather suits it.
nonisolated struct ForgottenFavoriteRule: InsightRule {
    let id = "forgottenFavorite"
    let category = InsightCategory.habits
    let minimumData = DataRequirement.daysLogged(30)
    static let minDays = 45

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        guard let temp = c.tomorrowTempC ?? c.currentTempC else { return nil }
        let isTomorrow = c.tomorrowTempC != nil
        let found = c.clothes.compactMap { item -> (InsightItem, Int)? in
            guard item.isFavorite, temp >= Double(item.minTempC), temp <= Double(item.maxTempC) else { return nil }
            let last = item.stats.lastWornDayKey.flatMap { DayKey.date(from: $0, calendar: c.calendar) } ?? item.createdAt
            let days = c.days(between: last, and: c.now)
            return days >= Self.minDays ? (item, days) : nil
        }
        guard let (item, days) = found.max(by: { $0.1 < $1.1 }) else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "forgotten:\(item.id)",
            title: "The \(item.name) hasn’t been out in \(days) days.",
            detail: "\(isTomorrow ? "Tomorrow’s" : "Today’s") \(InsightCopy.temperature(temp)) suits it.",
            score: 30, isTimely: true, relatedItemId: item.id)
    }
}

// MARK: - Weather

/// What's worn in cold, wet or warm weather, from the logged days' weather.
nonisolated struct WeatherBandRule: InsightRule {
    let id = "weatherBand"
    let category = InsightCategory.weather
    let minimumData = DataRequirement.daysLogged(20)
    static let minDays = 20
    static let minShare = 0.8

    enum Band: String, CaseIterable {
        case cold, wet, warm

        func contains(temperatureC: Double?, conditions: WeatherConditions?) -> Bool {
            switch self {
            case .cold: (temperatureC ?? .infinity) < 0
            case .wet: !(conditions ?? []).isDisjoint(with: [.rain, .snow])
            case .warm: (temperatureC ?? -.infinity) > 20
            }
        }

        var phrase: String {
            switch self {
            case .cold: "Below \(InsightCopy.temperature(0))"
            case .wet: "On wet days"
            case .warm: "Above \(InsightCopy.temperature(20))"
            }
        }
    }

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        var best: (Band, InsightItem, Double, timely: Bool)?
        for band in Band.allCases {
            let days = c.days.filter { band.contains(temperatureC: $0.temperatureC, conditions: $0.conditions) }
            guard days.count >= Self.minDays else { continue }
            let timely = c.tomorrow.map { band.contains(temperatureC: ($0.lowC + $0.highC) / 2, conditions: $0.conditions) } ?? false
            for item in c.clothes {
                let share = Double(days.count { $0.itemIDs.contains(item.id) }) / Double(days.count)
                guard share >= Self.minShare else { continue }
                // Timely bands first, then the highest share.
                if best == nil || (timely && !best!.timely) || (timely == best!.timely && share > best!.2) {
                    best = (band, item, share, timely)
                }
            }
        }
        guard let (band, item, share, timely) = best else { return nil }
        let title = share >= 0.995
            ? "\(band.phrase) you always wore the \(item.name)."
            : "\(band.phrase) you wore the \(item.name) \(InsightCopy.percent(share)) of the time."
        var detail: String?
        if timely, let tomorrow = c.tomorrow {
            detail = band == .wet ? "Wet weather tomorrow."
                : "It’s \(InsightCopy.temperature((tomorrow.lowC + tomorrow.highC) / 2)) tomorrow."
        }
        return InsightCandidate(
            ruleId: id, category: category, key: "band:\(band.rawValue):\(item.id)",
            title: title, detail: detail, score: 30, isTimely: timely, relatedItemId: item.id)
    }
}

/// Tomorrow is colder than any day in the last 60: what was worn last time.
nonisolated struct LastTimeThisColdRule: InsightRule {
    let id = "lastTimeThisCold"
    let category = InsightCategory.weather
    let minimumData = DataRequirement.daysLogged(20)

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        guard let tomorrow = c.tomorrowTempC,
              let since = c.calendar.date(byAdding: .day, value: -60, to: c.startOfToday) else { return nil }
        let recent = c.days.filter { $0.date >= since }.compactMap(\.temperatureC)
        guard recent.count >= 10, let coldest = recent.min(), tomorrow < coldest else { return nil }
        let clothes = Dictionary(uniqueKeysWithValues: c.clothes.map { ($0.id, $0) })
        guard let last = c.days.last(where: { ($0.temperatureC ?? .infinity) <= tomorrow + 2
                                              && $0.itemIDs.contains { clothes[$0] != nil } }) else { return nil }
        let names = last.itemIDs.compactMap { clothes[$0] }
            .sorted { $0.stats.wearCount > $1.stats.wearCount }.prefix(2).map { "the \($0.name)" }
        return InsightCandidate(
            ruleId: id, category: category, key: "coldest:\(c.todayKey)",
            title: "Tomorrow’s the coldest in 60 days, \(InsightCopy.temperature(tomorrow)).",
            detail: "Last time it was this cold you wore \(names.formatted(.list(type: .and))).",
            score: 45, isTimely: true)
    }
}

/// A warm-weather item resting through the cold months.
nonisolated struct SeasonalRestRule: InsightRule {
    let id = "seasonalRest"
    let category = InsightCategory.weather
    let minimumData = DataRequirement.daysLogged(20)

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        guard let temp = c.currentTempC ?? c.tomorrowTempC else { return nil }
        let resting = c.clothes.compactMap { item -> (InsightItem, Date)? in
            guard item.minTempC >= 15, temp < Double(item.minTempC) - 5,
                  let key = item.stats.lastWornDayKey, let last = DayKey.date(from: key, calendar: c.calendar),
                  c.days(between: last, and: c.now) >= 30 else { return nil }
            return (item, last)
        }
        guard let (item, last) = resting.max(by: { $0.0.stats.wearCount < $1.0.stats.wearCount }) else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "seasonal:\(item.id):\(c.yearKeyPrefix)",
            title: "The \(item.name) is resting until it’s warm again.",
            detail: "Last out in \(last.formatted(.dateTime.month(.wide))).",
            score: 10, relatedItemId: item.id, isSlow: true)
    }
}

// MARK: - Brands & origin

/// The brand with the largest share of wears.
nonisolated struct MostWornBrandRule: InsightRule {
    let id = "mostWornBrand"
    let category = InsightCategory.brands
    let minimumData = DataRequirement.itemsWithBrand(5)

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let total = c.owned.reduce(0) { $0 + $1.stats.wearCount }
        guard total > 0 else { return nil }
        let byBrand = Dictionary(grouping: c.owned.filter { $0.brand != nil }, by: { $0.brand! })
        guard let (brand, items) = byBrand.max(by: { a, b in
            a.value.reduce(0) { $0 + $1.stats.wearCount } < b.value.reduce(0) { $0 + $1.stats.wearCount } }) else { return nil }
        let wears = items.reduce(0) { $0 + $1.stats.wearCount }
        let share = Double(wears) / Double(total)
        guard share >= 0.15 else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "brandWears:\(brand.lowercased())",
            title: "\(brand) makes up \(InsightCopy.percent(share)) of your wears.",
            detail: "\(InsightCopy.count(items.count, "piece", "pieces")), \(wears.formatted()) wears between them.",
            score: 20, isSlow: true)
    }
}

/// The brand you own the most pieces of.
nonisolated struct MostOwnedBrandRule: InsightRule {
    let id = "mostOwnedBrand"
    let category = InsightCategory.brands
    let minimumData = DataRequirement.itemsWithBrand(5)

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let counts = Dictionary(grouping: c.owned.compactMap(\.brand), by: { $0 }).mapValues(\.count)
        let sorted = counts.sorted { $0.value > $1.value }
        guard let top = sorted.first, top.value >= 3, sorted.dropFirst().first?.value != top.value else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "brandCount:\(top.key.lowercased())",
            title: "You own more \(top.key) than any other brand: \(top.value) pieces.",
            detail: nil, score: 15, isSlow: true)
    }
}

/// Where most of the wardrobe was made, by continent.
nonisolated struct MadeInRegionRule: InsightRule {
    let id = "madeInRegion"
    let category = InsightCategory.brands
    let minimumData = DataRequirement.itemsWithBrand(5)

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let codes = c.owned.compactMap(\.madeIn)
        guard codes.count >= 5 else { return nil }
        let continents = codes.compactMap { Locale.Region($0).continent?.identifier }
        let counts = Dictionary(grouping: continents, by: { $0 }).mapValues(\.count)
        guard let top = counts.max(by: { $0.value < $1.value }),
              let name = Locale.current.localizedString(forRegionCode: top.key) else { return nil }
        let share = Double(top.value) / Double(codes.count)
        guard share >= 0.4 else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "madeIn:\(top.key)",
            title: "\(InsightCopy.percent(share)) of what you own was made in \(name).",
            detail: "Counting the \(codes.count) pieces with a country of manufacture.",
            score: 15, isSlow: true)
    }
}

/// Pieces made outside their brand's home country.
nonisolated struct OriginMismatchRule: InsightRule {
    let id = "originMismatch"
    let category = InsightCategory.brands
    let minimumData = DataRequirement.itemsWithBrand(5)

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let away = c.owned.filter { item in
            guard let home = item.brandCountry, let made = item.madeIn else { return false }
            return home != made
        }
        guard away.count >= 3, let example = away.max(by: { $0.stats.wearCount < $1.stats.wearCount }),
              let brand = example.brand, let home = example.brandCountry, let made = example.madeIn else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "mismatch:\(away.count)",
            title: "\(away.count) of your pieces were made outside their brand’s home country.",
            detail: "Like the \(example.name): \(brand) is from \(Countries.name(for: home)), made in \(Countries.name(for: made)).",
            score: 12, isSlow: true)
    }
}

// MARK: - Care, second-hand & gifts

/// Wears since a repair, and what the fix costs per wear.
nonisolated struct RepairPaybackRule: InsightRule {
    let id = "repairPayback"
    let category = InsightCategory.care
    let minimumData = DataRequirement.none
    static let minWears = 10

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        var best: (InsightItem, InsightItem.Repair, Int)?
        for item in c.owned {
            for repair in item.repairs {
                let since = DayKey.make(for: repair.date, calendar: c.calendar)
                let wears = item.stats.loggedDayKeys.count { $0 > since }
                if wears >= Self.minWears, wears > best?.2 ?? 0 { best = (item, repair, wears) }
            }
        }
        guard let (item, repair, wears) = best else { return nil }
        let what = repair.name.isEmpty ? "repair" : repair.name.lowercased()
        return InsightCandidate(
            ruleId: id, category: category, key: "repair:\(item.id):\(DayKey.make(for: repair.date, calendar: c.calendar))",
            title: "\(wears) wears since the \(item.name)’s \(what).",
            detail: "\(InsightCopy.money(fractional: Double(repair.cents) / Double(wears))) a wear for the fix so far.",
            score: 25, mentionsMoney: true, relatedItemId: item.id)
    }
}

/// How much of the wardrobe came pre-owned.
nonisolated struct SecondHandRule: InsightRule {
    let id = "secondHand"
    let category = InsightCategory.care
    let minimumData = DataRequirement.none

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let owned = c.owned
        let preOwned = owned.filter(\.isSecondHand)
        guard preOwned.count >= 3 else { return nil }
        let wears = preOwned.reduce(0) { $0 + $1.stats.wearCount }
        return InsightCandidate(
            ruleId: id, category: category, key: "secondHand:\(preOwned.count)",
            title: "\(preOwned.count) of your \(owned.count) pieces came to you pre-owned.",
            detail: "\(wears.formatted()) wears between them so far.", score: 12, isSlow: true)
    }
}

/// The most-worn gift.
nonisolated struct MostWornGiftRule: InsightRule {
    let id = "mostWornGift"
    let category = InsightCategory.care
    let minimumData = DataRequirement.none
    static let minWears = 30

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        guard let gift = c.owned.filter({ $0.isGift && $0.stats.wearCount >= Self.minWears })
            .max(by: { $0.stats.wearCount < $1.stats.wearCount }) else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "gift:\(gift.id):\(gift.stats.wearCount / 100)",
            title: "The \(gift.name) is your most-worn gift: \(gift.stats.wearCount.formatted()) wears.",
            detail: nil, score: 18, relatedItemId: gift.id)
    }
}

/// How long a daily driver has been along.
nonisolated struct DailyDriverLongevityRule: InsightRule {
    let id = "driverLongevity"
    let category = InsightCategory.care
    let minimumData = DataRequirement.none

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let drivers = c.owned.filter(\.isDailyDriver).map { ($0, c.days(between: $0.purchaseDate, and: c.now)) }
        guard let (item, days) = drivers.max(by: { $0.1 < $1.1 }), days >= 365 else { return nil }
        let isRound = days % 100 == 0
        return InsightCandidate(
            ruleId: id, category: category, key: "longevity:\(item.id):\(days / 100)",
            title: "The \(item.name) has been with you \(days.formatted()) days.",
            detail: "Every one of them, most likely.", score: 15, isTimely: isRound, isMilestone: isRound,
            relatedItemId: item.id)
    }
}

// MARK: - Buy less

/// 30, 60, 90, 180 and 365 days without buying.
nonisolated struct BuyLessStreakRule: InsightRule {
    let id = "buyLessStreak"
    let category = InsightCategory.buyLess
    let minimumData = DataRequirement.buyLessGoals
    static let milestones = [30, 60, 90, 180, 365]

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        guard let stats = c.buyLess?.stats, Self.milestones.contains(stats.currentStreakDays) else { return nil }
        let days = stats.currentStreakDays
        return InsightCandidate(
            ruleId: id, category: category, key: "buyLess:\(days):\(c.todayKey)",
            title: "\(days) days without buying anything new.",
            detail: days >= stats.longestStreakDays ? "Your longest streak yet." : nil,
            score: 60, isTimely: true, isMilestone: true)
    }
}

/// Late in the month and still under the monthly limit.
nonisolated struct UnderBudgetRule: InsightRule {
    let id = "underBudget"
    let category = InsightCategory.buyLess
    let minimumData = DataRequirement.buyLessGoals

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        guard let buyLess = c.buyLess, buyLess.monthlyLimitCents > 0,
              buyLess.stats.spentThisMonthCents < buyLess.monthlyLimitCents,
              let range = c.calendar.range(of: .day, in: .month, for: c.now) else { return nil }
        let day = c.calendar.component(.day, from: c.now)
        guard day >= 20 else { return nil }
        let left = buyLess.monthlyLimitCents - buyLess.stats.spentThisMonthCents
        let daysLeft = range.count - day
        return InsightCandidate(
            ruleId: id, category: category, key: "budget:\(c.todayKey.prefix(7))",
            title: "\(InsightCopy.money(left)) of your \(InsightCopy.money(buyLess.monthlyLimitCents)) monthly limit left.",
            detail: daysLeft == 0 ? "Last day of the month." : "\(InsightCopy.count(daysLeft, "day", "days")) to go.",
            score: 20, mentionsMoney: true)
    }
}
