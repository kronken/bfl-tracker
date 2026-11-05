import Foundation

// Daily insight rules about kinds of items (types) and care logs. Same voice
// as InsightRules.swift: short, dry, warm; low use is never "wasted".

extension InsightRules {
    static let kindsAndCare: [any InsightRule] = [
        MostOwnedKindRule(), FavouriteOfTheBunchRule(), TakenOverRule(), KindCostPerWearRule(), KindSpendShareRule(),
        KindOfTheDayRule(), WeatherKindRule(), OnlyOneOfItsKindRule(), KindMilestoneRule(), OldFaithfulRule(),
        NumberNRule(),
        CareDueByHabitRule(), CareMilestoneRule(), CareAnniversaryRule(), WellKeptRule(),
    ]
}

// MARK: - Helpers

nonisolated extension InsightCopy {
    /// A plural type name inside a sentence: "denim jackets", but "T-shirts"
    /// keeps its capital (an initial before a hyphen, or capitals later on).
    static func midSentence(_ typeName: String) -> String {
        let firstWord = typeName.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? typeName
        if typeName.dropFirst().contains(where: \.isUppercase) || firstWord.count == 1 { return typeName }
        return typeName.prefix(1).lowercased() + typeName.dropFirst()
    }

    /// "tenth", "twenty-fifth".
    static func ordinal(_ n: Int) -> String {
        let ordinals = [10: "tenth", 25: "twenty-fifth", 50: "fiftieth"]
        return ordinals[n] ?? "\(n)th"
    }

    /// "a quarter", "a third", "half", or a percentage.
    static func fraction(_ share: Double) -> String {
        switch share {
        case 0.24..<0.27: "a quarter"
        case 0.32..<0.35: "a third"
        case 0.48..<0.53: "half"
        case 0.65..<0.68: "two thirds"
        default: percent(share)
        }
    }
}

nonisolated extension InsightContext {
    /// Owned items with a type, by type.
    var ownedByType: [UUID: [InsightItem]] {
        Dictionary(grouping: owned.filter { $0.typeID != nil }) { $0.typeID! }
    }

    func dayKey(daysAgo: Int) -> String {
        DayKey.make(for: calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday) ?? now, calendar: calendar)
    }

    /// Logged wears since `daysAgo` days ago, today included.
    func wears(of item: InsightItem, inLast days: Int) -> Int {
        let since = dayKey(daysAgo: days - 1)
        return item.stats.loggedDayKeys.count { $0 >= since }
    }
}

nonisolated extension Array where Element == InsightItem {
    var typeName: String { first?.typeName ?? "" }
    var totalWears: Int { reduce(0) { $0 + $1.stats.wearCount } }
}

// MARK: - Kinds of items

/// The type with the most owned items, with a clear lead.
nonisolated struct MostOwnedKindRule: InsightRule {
    let id = "mostOwnedKind"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let sorted = c.ownedByType.sorted { $0.value.count > $1.value.count }
        guard let top = sorted.first, top.value.count >= 3,
              top.value.count >= (sorted.dropFirst().first?.value.count ?? 0) + 1 else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "kindCount:\(top.key)",
            title: "\(top.value.typeName) are your biggest group: \(top.value.count) pieces.",
            detail: "Worn \(top.value.totalWears.formatted()) times between them.", score: 25, isSlow: true)
    }
}

/// One item gets most of a type's recent wears.
nonisolated struct FavouriteOfTheBunchRule: InsightRule {
    let id = "favouriteOfTheBunch"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        var best: (typeID: UUID, items: [InsightItem], top: InsightItem, share: Double)?
        for (typeID, items) in c.ownedByType where items.count >= 3 {
            let wears = items.map { ($0, c.wears(of: $0, inLast: 90)) }
            let total = wears.reduce(0) { $0 + $1.1 }
            guard total >= 30, let top = wears.max(by: { $0.1 < $1.1 }) else { continue }
            let share = Double(top.1) / Double(total)
            if share >= 0.6, share > best?.share ?? 0 { best = (typeID, items, top.0, share) }
        }
        guard let best else { return nil }
        let tens = Int((best.share * 10).rounded())
        return InsightCandidate(
            ruleId: id, category: category, key: "bunch:\(best.typeID):\(best.top.id)",
            title: "Of your \(best.items.count) \(InsightCopy.midSentence(best.items.typeName)), the \(best.top.name) gets \(tens) of every 10 wears.",
            detail: "Counting the last 90 days.", score: 25, relatedItemId: best.top.id)
    }
}

/// One item of a type rests while another does the work.
nonisolated struct TakenOverRule: InsightRule {
    let id = "takenOver"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let sellAfterDays = c.sellSuggestionMonths * 30
        for (_, items) in c.ownedByType.sorted(by: { $0.key.uuidString < $1.key.uuidString }) where items.count >= 2 {
            let clothes = items.filter { !$0.isDailyDriver && !$0.isInactive }
            guard let busy = clothes.max(by: { c.wears(of: $0, inLast: 60) < c.wears(of: $1, inLast: 60) }),
                  c.wears(of: busy, inLast: 60) >= 10 else { continue }
            let resting = clothes.compactMap { item -> (InsightItem, Date, Int)? in
                guard item.id != busy.id else { return nil }
                let last = item.stats.lastWornDayKey.flatMap { DayKey.date(from: $0, calendar: c.calendar) } ?? item.createdAt
                let days = c.days(between: last, and: c.now)
                // Long unworn ones are already under To sell.
                guard days >= 60, days < sellAfterDays else { return nil }
                return (item, last, days)
            }
            guard let (item, last, _) = resting.max(by: { $0.2 < $1.2 }) else { continue }
            return InsightCandidate(
                ruleId: id, category: category, key: "takenOver:\(item.id)",
                title: "The \(item.name) has sat out since \(last.formatted(.dateTime.month(.wide))) while the \(busy.name) took the shifts.",
                detail: nil, score: 40, relatedItemId: item.id)
        }
        return nil
    }
}

/// Two types in one category, side by side by cost per wear.
nonisolated struct KindCostPerWearRule: InsightRule {
    let id = "kindCostPerWear"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let eligible = c.ownedByType.filter { $0.value.count >= 2 && $0.value.totalWears >= 30 }
        let byCategory = Dictionary(grouping: eligible) { $0.value.first?.categoryID }
        for (_, types) in byCategory.sorted(by: { ($0.key?.uuidString ?? "") < ($1.key?.uuidString ?? "") }) where types.count >= 2 {
            let ranked = types.sorted { $0.value.totalWears > $1.value.totalWears }.prefix(2)
            let parts = ranked.map { entry -> (String, Double) in
                let net = entry.value.reduce(0) { $0 + $1.stats.netCostCents }
                return (InsightCopy.midSentence(entry.value.typeName), Double(net) / Double(entry.value.totalWears))
            }
            let a = parts[0], b = parts[1]
            return InsightCandidate(
                ruleId: id, category: category, key: "kindCPW:" + ranked.map(\.key.uuidString).sorted().joined(separator: ":"),
                title: "Your \(a.0) cost \(InsightCopy.money(fractional: a.1)) per wear, your \(b.0) \(InsightCopy.money(fractional: b.1)).",
                detail: nil, score: 25, mentionsMoney: true, isSlow: true)
        }
        return nil
    }
}

/// A type that is a large share of what was spent.
nonisolated struct KindSpendShareRule: InsightRule {
    let id = "kindSpendShare"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let total = c.owned.reduce(0) { $0 + $1.stats.spendCents }
        guard total > 0 else { return nil }
        let shares = c.ownedByType.map { ($0.key, $0.value, Double($0.value.reduce(0) { $0 + $1.stats.spendCents }) / Double(total)) }
        guard let (typeID, items, share) = shares.max(by: { $0.2 < $1.2 }), share >= 0.25 else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "spendShare:\(typeID)",
            title: "\(items.typeName) make up \(InsightCopy.fraction(share)) of what your wardrobe cost.",
            detail: nil, score: 25, mentionsMoney: true, isSlow: true)
    }
}

/// A type worn on most logged days this year.
nonisolated struct KindOfTheDayRule: InsightRule {
    let id = "kindOfTheDay"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let days = c.days.filter { $0.dayKey.hasPrefix(c.yearKeyPrefix) }
        guard days.count >= 60 else { return nil }
        let typeOf = Dictionary(uniqueKeysWithValues: c.items.compactMap { item in item.typeID.map { (item.id, $0) } })
        var counts: [UUID: Int] = [:]
        for day in days {
            for typeID in Set(day.itemIDs.compactMap { typeOf[$0] }) { counts[typeID, default: 0] += 1 }
        }
        guard let (typeID, count) = counts.max(by: { $0.value < $1.value }),
              let name = c.items.first(where: { $0.typeID == typeID })?.typeName else { return nil }
        let share = Double(count) / Double(days.count)
        guard share >= 0.7 else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "kindDay:\(typeID):\(c.yearKeyPrefix)",
            title: "\(name) on \(InsightCopy.percent(share)) of the days you logged this year.",
            detail: nil, score: 25)
    }
}

/// The type reached for in cold, wet or warm weather.
nonisolated struct WeatherKindRule: InsightRule {
    let id = "weatherKind"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    enum Band: String, CaseIterable {
        case cold, wet, warm

        func contains(temperatureC: Double?, conditions: WeatherConditions?) -> Bool {
            switch self {
            case .cold: (temperatureC ?? .infinity) < 5
            case .wet: !(conditions ?? []).isDisjoint(with: [.rain])
            case .warm: (temperatureC ?? -.infinity) > 20
            }
        }

        var phrase: String {
            switch self {
            case .cold: "Below \(InsightCopy.temperature(5))"
            case .wet: "On rainy days"
            case .warm: "Above \(InsightCopy.temperature(20))"
            }
        }
    }

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let typeOf = Dictionary(uniqueKeysWithValues: c.items.compactMap { item in item.typeID.map { (item.id, $0) } })
        var best: (Band, UUID, Double, timely: Bool)?
        for band in Band.allCases {
            let days = c.days.filter { band.contains(temperatureC: $0.temperatureC, conditions: $0.conditions) }
            guard days.count >= 20 else { continue }
            let timely = c.tomorrow.map { band.contains(temperatureC: ($0.lowC + $0.highC) / 2, conditions: $0.conditions) } ?? false
            var counts: [UUID: Int] = [:]
            for day in days {
                for typeID in Set(day.itemIDs.compactMap { typeOf[$0] }) { counts[typeID, default: 0] += 1 }
            }
            for (typeID, count) in counts {
                let share = Double(count) / Double(days.count)
                guard share >= 0.75 else { continue }
                if best == nil || (timely && !best!.timely) || (timely == best!.timely && share > best!.2) {
                    best = (band, typeID, share, timely)
                }
            }
        }
        guard let (band, typeID, share, timely) = best,
              let name = c.items.first(where: { $0.typeID == typeID })?.typeName else { return nil }
        let tens = Int((share * 10).rounded())
        return InsightCandidate(
            ruleId: id, category: category, key: "weatherKind:\(band.rawValue):\(typeID)",
            title: "\(band.phrase) you reach for \(InsightCopy.midSentence(name)) \(tens == 10 ? "every time" : "\(tens) times out of 10").",
            detail: timely ? "Tomorrow looks like one of those days." : nil,
            score: timely ? 60 : 25, isTimely: timely)
    }
}

/// The only owned item of its type, well worn.
nonisolated struct OnlyOneOfItsKindRule: InsightRule {
    let id = "onlyOneOfItsKind"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let singles = c.ownedByType.values.compactMap { $0.count == 1 ? $0[0] : nil }.filter { $0.stats.wearCount >= 100 }
        guard let item = singles.max(by: { $0.stats.wearCount < $1.stats.wearCount }),
              let typeName = item.typeName else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "onlyOne:\(item.id):\(item.stats.wearCount / 100)",
            title: "The \(item.name) is all your \(InsightCopy.midSentence(typeName)) in one, at \(item.stats.wearCount.formatted()) wears.",
            detail: nil, score: 40, relatedItemId: item.id)
    }
}

/// A type's wears together pass a round number today.
nonisolated struct KindMilestoneRule: InsightRule {
    let id = "kindMilestone"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse
    static let milestones = [250, 500, 1_000, 2_500]

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        for (typeID, items) in c.ownedByType.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            let now = items.totalWears
            let before = now - items.count { $0.wasWorn(on: c.todayKey) }
            guard let milestone = Self.milestones.first(where: { before < $0 && now >= $0 }) else { continue }
            return InsightCandidate(
                ruleId: id, category: category, key: "kindWears:\(typeID):\(milestone)",
                title: "Your \(InsightCopy.midSentence(items.typeName)) just passed \(milestone.formatted()) wears together.",
                detail: nil, score: 40, isTimely: true, isMilestone: true)
        }
        return nil
    }
}

/// The oldest of a type still out-wears the newest.
nonisolated struct OldFaithfulRule: InsightRule {
    let id = "oldFaithful"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        for (typeID, items) in c.ownedByType.sorted(by: { $0.key.uuidString < $1.key.uuidString }) where items.count >= 2 {
            guard let oldest = items.min(by: { $0.purchaseDate < $1.purchaseDate }),
                  let newest = items.max(by: { $0.purchaseDate < $1.purchaseDate }),
                  oldest.id != newest.id,
                  c.wears(of: oldest, inLast: 90) > c.wears(of: newest, inLast: 90) else { continue }
            let year = c.calendar.component(.year, from: oldest.purchaseDate)
            return InsightCandidate(
                ruleId: id, category: category, key: "oldFaithful:\(typeID):\(oldest.id)",
                title: "Your oldest \(InsightCopy.midSentence(items.typeName)), the \(oldest.name) (\(year)), still out-wear the newest.",
                detail: "Counting the last 90 days.", score: 25, relatedItemId: oldest.id)
        }
        return nil
    }
}

/// An item added yesterday to a type that already had three or more.
nonisolated struct NumberNRule: InsightRule {
    let id = "numberN"
    let category = InsightCategory.types
    let minimumData = DataRequirement.typesInUse

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        guard c.buyLess != nil else { return nil }
        let yesterday = c.dayKey(daysAgo: 1)
        for item in c.owned where DayKey.make(for: item.createdAt, calendar: c.calendar) == yesterday {
            guard let typeID = item.typeID, let others = c.ownedByType[typeID]?.filter({ $0.id != item.id }),
                  others.count >= 3, let typeName = item.typeName else { continue }
            let perYear = others.map { other -> Double in
                let years = max(1, Double(c.days(between: other.purchaseDate, and: c.now)) / 365)
                return Double(other.stats.wearCount) / years
            }
            let average = Int((perYear.reduce(0, +) / Double(perYear.count)).rounded())
            return InsightCandidate(
                ruleId: id, category: category, key: "numberN:\(item.id)",
                title: "That makes \(others.count + 1) \(InsightCopy.midSentence(typeName)).",
                detail: "The other \(InsightCopy.spelled(others.count)) average \(average) wears a year.",
                score: 40, relatedItemId: item.id)
        }
        return nil
    }
}

// MARK: - Care

nonisolated extension InsightItem {
    /// Log dates per action, oldest first.
    var careByAction: [UUID: [InsightItem.CareEntry]] {
        Dictionary(grouping: careLog, by: \.actionID).mapValues { $0.sorted { $0.date < $1.date } }
    }

    /// Days worn after `from` and up to and including `to` (day keys).
    func wears(after from: String, upTo to: String? = nil) -> Int {
        stats.loggedDayKeys.count { day in day > from && (to.map { day <= $0 } ?? true) }
    }
}

/// More wears than usual since the last time.
nonisolated struct CareDueByHabitRule: InsightRule {
    let id = "careDueByHabit"
    let category = InsightCategory.careLog
    let minimumData = DataRequirement.none

    static func median(_ values: [Int]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? Double(sorted[mid - 1] + sorted[mid]) / 2 : Double(sorted[mid])
    }

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        var best: (InsightItem, InsightItem.CareEntry, since: Int, usual: Int)?
        for item in c.owned {
            for (_, entries) in item.careByAction where entries.count >= 3 {
                let keys = entries.map { DayKey.make(for: $0.date, calendar: c.calendar) }
                let gaps = zip(keys, keys.dropFirst()).map { item.wears(after: $0.0, upTo: $0.1) }
                let usual = Self.median(gaps)
                let since = item.wears(after: keys.last!)
                guard usual >= 1, Double(since) >= 1.5 * usual else { continue }
                if since > best?.since ?? 0 { best = (item, entries.last!, since, Int(usual.rounded())) }
            }
        }
        guard let (item, last, since, usual) = best else { return nil }
        let dry = c.tomorrow.map { $0.conditions.isDisjoint(with: [.rain, .snow]) } ?? false
        let timely = dry && !last.isWashing
        let action = last.actionName.lowercased()
        return InsightCandidate(
            ruleId: id, category: category, key: "due:\(item.id):\(last.actionID):\(DayKey.make(for: last.date, calendar: c.calendar))",
            title: "\(since) wears since the \(item.name)’s last \(action).",
            detail: "Usually it’s about every \(usual)." + (timely ? " Tomorrow looks dry." : ""),
            score: 60, isTimely: timely, relatedItemId: item.id)
    }
}

/// The 10th, 25th or 50th log, logged today.
nonisolated struct CareMilestoneRule: InsightRule {
    let id = "careMilestone"
    let category = InsightCategory.careLog
    let minimumData = DataRequirement.none

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        for item in c.owned {
            for (actionID, entries) in item.careByAction where [10, 25, 50].contains(entries.count) {
                guard let last = entries.last, DayKey.make(for: last.date, calendar: c.calendar) == c.todayKey else { continue }
                return InsightCandidate(
                    ruleId: id, category: category, key: "careMilestone:\(item.id):\(actionID):\(entries.count)",
                    title: "\(InsightCopy.capitalized(InsightCopy.ordinal(entries.count))) \(last.actionName.lowercased()) for the \(item.name).",
                    detail: nil, score: 40, isTimely: true, isMilestone: true, relatedItemId: item.id)
            }
        }
        return nil
    }
}

/// Cared for a year ago, and not in the last 30 days.
nonisolated struct CareAnniversaryRule: InsightRule {
    let id = "careAnniversary"
    let category = InsightCategory.careLog
    let minimumData = DataRequirement.none

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        for item in c.owned {
            for (actionID, entries) in item.careByAction {
                let recent = entries.contains { c.days(between: $0.date, and: c.now) <= 30 }
                guard !recent, let match = entries.first(where: { abs(c.days(between: $0.date, and: c.now) - 365) <= 3 })
                else { continue }
                return InsightCandidate(
                    ruleId: id, category: category,
                    key: "careAnniversary:\(item.id):\(actionID):\(c.calendar.component(.year, from: match.date))",
                    title: "This time last year: \(match.actionName.lowercased()) for the \(item.name).",
                    detail: nil, score: 25, relatedItemId: item.id)
            }
        }
        return nil
    }
}

/// The most cared-for item of the year is also among the most worn.
nonisolated struct WellKeptRule: InsightRule {
    let id = "wellKept"
    let category = InsightCategory.careLog
    let minimumData = DataRequirement.none

    func evaluate(_ c: InsightContext) -> InsightCandidate? {
        let logs = c.owned.map { item in (item, item.careLog.count { c.days(between: $0.date, and: c.now) <= 365 }) }
        guard let (item, count) = logs.max(by: { $0.1 < $1.1 }), count >= 4 else { return nil }
        let wears = c.wears(of: item, inLast: 365)
        guard wears >= 100 else { return nil }
        return InsightCandidate(
            ruleId: id, category: category, key: "wellKept:\(item.id):\(c.yearKeyPrefix)",
            title: "The \(item.name) got the most care this year, and \(wears) wears.",
            detail: nil, score: 25, relatedItemId: item.id)
    }
}
