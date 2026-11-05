import Foundation
import Testing
@testable import BuyItForLife

/// Builds fixture wardrobes for the insight rules.
private struct Fixture {
    let calendar = Calendar.current
    /// A Thursday at noon.
    let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!

    func date(daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))! }
    func key(daysAgo: Int) -> String { DayKey.make(for: date(daysAgo: daysAgo)) }

    func item(_ name: String = "Tee", price: Int = 2_000, prior: Int = 0, wornDaysAgo: [Int] = [],
              bought: Date? = nil, configure: (inout InsightItem) -> Void = { _ in }) -> InsightItem {
        var item = InsightItem(
            id: UUID(), name: name, createdAt: date(daysAgo: 400),
            stats: ItemStats(purchaseDate: bought ?? date(daysAgo: 400), purchasePriceCents: price, priorWearCount: prior,
                             loggedDayKeys: Set(wornDaysAgo.map { key(daysAgo: $0) }), soldDate: nil, soldPriceCents: nil))
        configure(&item)
        return item
    }

    /// Days come from the items' logged keys, plus `weather` by days ago.
    func context(_ items: [InsightItem], extraDays: [Int] = [], weather: [Int: Double] = [:],
                 tomorrow: InsightForecast? = nil, currentTempC: Double? = nil, buyLess: InsightBuyLess? = nil) -> InsightContext {
        var days: [String: InsightDay] = [:]
        for item in items {
            for key in item.stats.loggedDayKeys {
                let date = DayKey.date(from: key)!
                days[key, default: InsightDay(dayKey: key, date: date, itemIDs: [])].itemIDs.insert(item.id)
            }
        }
        for ago in extraDays where days[key(daysAgo: ago)] == nil {
            days[key(daysAgo: ago)] = InsightDay(dayKey: key(daysAgo: ago), date: date(daysAgo: ago), itemIDs: [UUID()])
        }
        for (ago, temperature) in weather {
            days[key(daysAgo: ago)]?.temperatureC = temperature
        }
        return InsightContext(items: items, days: days.values.sorted { $0.dayKey < $1.dayKey }, now: now,
                              calendar: calendar, currentTempC: currentTempC, tomorrow: tomorrow,
                              paidOffTargetCents: 100, buyLess: buyLess)
    }
}

struct InsightRuleTests {
    private let f = Fixture()

    // MARK: Value & milestones

    @Test func paidOffTodayNeedsTodaysWearToCrossTheTarget() {
        // €10 net: 10 wears = €1.00 (not under), 11 wears = €0.91.
        let ten = f.item(price: 1_000, prior: 9, wornDaysAgo: [0])
        let eleven = f.item(price: 1_000, prior: 10, wornDaysAgo: [0])
        let notToday = f.item(price: 1_000, prior: 10, wornDaysAgo: [1])
        #expect(PaidOffTodayRule().evaluate(f.context([ten])) == nil)
        #expect(PaidOffTodayRule().evaluate(f.context([eleven]))?.relatedItemId == eleven.id)
        #expect(PaidOffTodayRule().evaluate(f.context([notToday])) == nil)
    }

    @Test func closeToTargetIsTenWearsOrFewer() {
        // €20: under €1.00 from wear 21.
        let ten = f.item(price: 2_000, prior: 11)
        let eleven = f.item(price: 2_000, prior: 10)
        let candidate = CloseToTargetRule().evaluate(f.context([ten]))
        #expect(candidate?.title.hasPrefix("10 more wears") == true)
        #expect(candidate?.mentionsMoney == true)
        #expect(CloseToTargetRule().evaluate(f.context([eleven])) == nil)
    }

    @Test func roundWearCountsReachedToday() {
        #expect(RoundWearsRule().evaluate(f.context([f.item(prior: 99, wornDaysAgo: [0])])) != nil)
        #expect(RoundWearsRule().evaluate(f.context([f.item(prior: 100, wornDaysAgo: [0])])) == nil)
        #expect(RoundWearsRule().evaluate(f.context([f.item(prior: 99, wornDaysAgo: [1])])) == nil)
        #expect(RoundWearsRule.isRound(1_000) && RoundWearsRule.isRound(2_500) && !RoundWearsRule.isRound(1_200))
    }

    @Test func anniversaryWithinThreeDays() {
        let years = { (offset: Int) in f.calendar.date(byAdding: .year, value: -6, to: f.date(daysAgo: -offset))! }
        let today = AnniversaryRule().evaluate(f.context([f.item("Iron Ranger", bought: years(0))]))
        #expect(today?.title == "The Iron Ranger is six years old today.")
        #expect(today?.isTimely == true)
        #expect(AnniversaryRule().evaluate(f.context([f.item(bought: years(3))]))?.isTimely == false)
        #expect(AnniversaryRule().evaluate(f.context([f.item(bought: years(4))])) == nil)
        #expect(AnniversaryRule().evaluate(f.context([f.item(bought: years(-3))]))?.title.contains("turned") == true)
    }

    @Test func cheapestPerWearNeedsThirtyWears() {
        let items = [f.item(price: 1_000, prior: 30), f.item(price: 3_000, prior: 30), f.item(price: 500, prior: 29),
                     f.item(price: 2_000, prior: 40)]
        #expect(CheapestPerWearRule().evaluate(f.context(items))?.relatedItemId == items[0].id)
    }

    // MARK: Habits

    @Test func workhorseNeedsFortyPercentOfThisYearsDays() {
        // 50 logged days this year; the jeans on 20 (40%) or 19 (38%).
        let filler = Array(0..<50)
        let yes = f.item("Jeans", wornDaysAgo: Array(0..<20))
        let no = f.item("Jeans", wornDaysAgo: Array(0..<19))
        #expect(WorkhorseRule().evaluate(f.context([yes], extraDays: filler))?.title == "The Jeans on 40% of days this year.")
        #expect(WorkhorseRule().evaluate(f.context([no], extraDays: filler)) == nil)
    }

    @Test func workhorseLeavesOutDailyDrivers() {
        let wallet = f.item("Wallet", wornDaysAgo: Array(0..<50)) { $0.isDailyDriver = true }
        #expect(WorkhorseRule().evaluate(f.context([wallet])) == nil)
    }

    @Test func streakOfFiveDays() {
        #expect(StreakRule().evaluate(f.context([f.item(wornDaysAgo: Array(0..<5))]))?.title == "The Tee, 5 days in a row.")
        #expect(StreakRule().evaluate(f.context([f.item(wornDaysAgo: Array(1..<6))])) != nil) // up to yesterday
        #expect(StreakRule().evaluate(f.context([f.item(wornDaysAgo: Array(0..<4))])) == nil)
        #expect(StreakRule().evaluate(f.context([f.item(wornDaysAgo: Array(2..<8))])) == nil) // broken yesterday
    }

    @Test func combinationOfThreeTenTimes() {
        let days = Array(0..<10)
        let trio = ["Boots", "Jeans", "Sweater"].map { f.item($0, wornDaysAgo: days) }
        #expect(CombinationRule().evaluate(f.context(trio))?.detail == "Your most-worn combination.")
        let nine = ["Boots", "Jeans", "Sweater"].map { f.item($0, wornDaysAgo: Array(0..<9)) }
        #expect(CombinationRule().evaluate(f.context(nine)) == nil)
    }

    @Test func weekdayPatternNeedsEightOfThatWeekday() {
        // Thursdays: today and every 7 days back.
        let thursdays = (0..<8).map { $0 * 7 }
        let item = f.item("Blazer", wornDaysAgo: Array(thursdays.prefix(5)))   // 5 of 8 = 63%
        let other = f.item("Other", wornDaysAgo: Array(thursdays.suffix(3)))
        #expect(WeekdayPatternRule().evaluate(f.context([item, other]))?.relatedItemId == item.id)
        let onlySeven = f.context([f.item("Blazer", wornDaysAgo: Array(thursdays.prefix(7)))])
        #expect(onlySeven.days.count == 7)
        #expect(WeekdayPatternRule().evaluate(onlySeven) == nil)
    }

    @Test func forgottenFavoriteWhenTheWeatherFits() {
        let coat = f.item("Coat", wornDaysAgo: [45]) { $0.isFavorite = true; $0.minTempC = -10; $0.maxTempC = 10 }
        let forecast = InsightForecast(lowC: 0, highC: 4, conditions: .cloudy)
        #expect(ForgottenFavoriteRule().evaluate(f.context([coat], tomorrow: forecast))?.isTimely == true)
        let recent = f.item("Coat", wornDaysAgo: [44]) { $0.isFavorite = true; $0.minTempC = -10; $0.maxTempC = 10 }
        #expect(ForgottenFavoriteRule().evaluate(f.context([recent], tomorrow: forecast)) == nil)
        let warm = InsightForecast(lowC: 18, highC: 24, conditions: .sun)
        #expect(ForgottenFavoriteRule().evaluate(f.context([coat], tomorrow: warm)) == nil)
    }

    // MARK: Weather

    @Test func coldBandNeedsTwentyDaysAndEightyPercent() {
        let cold = Dictionary(uniqueKeysWithValues: (0..<20).map { ($0, -5.0) })
        let boots = f.item("Boots", wornDaysAgo: Array(0..<20))
        let candidate = WeatherBandRule().evaluate(f.context([boots], weather: cold))
        #expect(candidate?.title == "Below \(Temperature.format(celsius: 0)) you always wore the Boots.")
        #expect(candidate?.isTimely == false)
        let tomorrow = InsightForecast(lowC: -4, highC: -2, conditions: .snow)
        #expect(WeatherBandRule().evaluate(f.context([boots], weather: cold, tomorrow: tomorrow))?.isTimely == true)

        let fewer = Dictionary(uniqueKeysWithValues: (0..<19).map { ($0, -5.0) })
        #expect(WeatherBandRule().evaluate(f.context([f.item(wornDaysAgo: Array(0..<19))], weather: fewer)) == nil)
        let sometimes = f.item("Boots", wornDaysAgo: Array(0..<15))   // 15 of 20 = 75%
        #expect(WeatherBandRule().evaluate(f.context([sometimes], extraDays: Array(15..<20), weather: cold)) == nil)
    }

    @Test func lastTimeThisColdNeedsAColderTomorrow() {
        let temps = Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, Double(-$0)) }) // down to -9
        let parka = f.item("Parka", wornDaysAgo: Array(0..<10))
        let colder = InsightForecast(lowC: -12, highC: -8, conditions: .snow)   // -10
        let candidate = LastTimeThisColdRule().evaluate(f.context([parka], weather: temps, tomorrow: colder))
        #expect(candidate?.detail == "Last time it was this cold you wore the Parka.")
        let same = InsightForecast(lowC: -11, highC: -7, conditions: .snow)     // -9
        #expect(LastTimeThisColdRule().evaluate(f.context([parka], weather: temps, tomorrow: same)) == nil)
    }

    // MARK: Brands, care, buy less

    @Test func brandRulesNeedFiveBrandedItems() {
        let four = (0..<4).map { _ in f.item(prior: 50) { $0.brand = "Northfield" } } + [f.item(prior: 50)]
        #expect(!MostWornBrandRule().minimumData.isMet(by: f.context(four)))
        let five = (0..<5).map { _ in f.item(prior: 50) { $0.brand = "Northfield" } }
        #expect(MostWornBrandRule().minimumData.isMet(by: f.context(five)))
        #expect(MostWornBrandRule().evaluate(f.context(five))?.title == "Northfield makes up 100% of your wears.")
        #expect(MostOwnedBrandRule().evaluate(f.context(five))?.isSlow == true)
    }

    @Test func originMismatchCountsAwayFromHome() {
        let away = (0..<3).map { _ in f.item { $0.brand = "Levi’s"; $0.brandCountry = "US"; $0.madeIn = "JP" } }
        let home = f.item { $0.brand = "Lee"; $0.brandCountry = "US"; $0.madeIn = "US" }
        #expect(OriginMismatchRule().evaluate(f.context(away + [home]))?.key == "mismatch:3")
        #expect(OriginMismatchRule().evaluate(f.context(Array(away.prefix(2)) + [home])) == nil)
    }

    @Test func repairPaybackAfterTenWears() {
        let repaired = { (wears: Int) in
            f.item("Boots", wornDaysAgo: Array(0..<wears)) {
                $0.repairs = [.init(name: "Resole", date: f.date(daysAgo: 30), cents: 12_000)]
            }
        }
        let candidate = RepairPaybackRule().evaluate(f.context([repaired(10)]))
        #expect(candidate?.title == "10 wears since the Boots’s resole.")
        #expect(candidate?.mentionsMoney == true)
        #expect(RepairPaybackRule().evaluate(f.context([repaired(9)])) == nil)
    }

    @Test func buyLessStreakMilestones() {
        let stats = { (days: Int) in
            BuyLessStats(purchases: [], enabledDate: f.date(daysAgo: days), now: f.now)
        }
        let on = InsightBuyLess(stats: stats(30), monthlyLimitCents: 5_000, yearlyBudgetCents: 30_000)
        #expect(BuyLessStreakRule().evaluate(f.context([], buyLess: on))?.title == "30 days without buying anything new.")
        let off = InsightBuyLess(stats: stats(31), monthlyLimitCents: 5_000, yearlyBudgetCents: 30_000)
        #expect(BuyLessStreakRule().evaluate(f.context([], buyLess: off)) == nil)
        #expect(!BuyLessStreakRule().minimumData.isMet(by: f.context([])))
    }

    @Test func everyRuleHasAUniqueID() {
        let ids = InsightRules.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func noTitleShouts() {
        // Copy rule: no exclamation marks, short titles.
        let items = [f.item(price: 1_000, prior: 10, wornDaysAgo: [0]), f.item(price: 2_000, prior: 11)]
        for rule in InsightRules.all {
            guard let candidate = rule.evaluate(f.context(items)) else { continue }
            #expect(!candidate.title.contains("!"))
            #expect(candidate.title.count <= 90)
        }
    }
}

struct InsightEngineTests {
    private let f = Fixture()

    private struct Fixed: InsightRule {
        var id: String
        var category: InsightCategory
        var minimumData = DataRequirement.none
        var candidate: InsightCandidate

        func evaluate(_ context: InsightContext) -> InsightCandidate? { candidate }
    }

    private func rule(_ id: String, _ category: InsightCategory = .habits, money: Bool = false, slow: Bool = false,
                      timely: Bool = false, score: Double = 20) -> Fixed {
        Fixed(id: id, category: category, candidate: InsightCandidate(
            ruleId: id, category: category, key: "\(id):fact", title: id, score: score, isTimely: timely,
            mentionsMoney: money, isSlow: slow))
    }

    private func shown(_ id: String, _ category: InsightCategory, daysAgo: Int) -> DailyInsight {
        DailyInsight(date: f.key(daysAgo: daysAgo), candidate: InsightCandidate(
            ruleId: id, category: category, key: "\(id):fact", title: id, score: 0))
    }

    private func keys(_ rules: [Fixed], filter: InsightFilter = InsightFilter(buyLessEnabled: true),
                      history: [DailyInsight] = []) -> Set<String> {
        Set(InsightEngine.candidates(rules: rules, context: f.context([]), filter: filter, history: history).map(\.ruleId))
    }

    @Test func filtersFollowSettings() {
        let rules = [rule("money", .value, money: true), rule("habit"), rule("buy", .buyLess), rule("brand", .brands)]
        #expect(keys(rules) == ["money", "habit", "buy", "brand"])
        #expect(keys(rules, filter: InsightFilter(feelGood: true, buyLessEnabled: true)) == ["habit", "buy", "brand"])
        #expect(keys(rules, filter: InsightFilter(buyLessEnabled: false)) == ["money", "habit", "brand"])
        #expect(keys(rules, filter: InsightFilter(disabledCategories: [.brands], buyLessEnabled: true)) == ["money", "habit", "buy"])
    }

    @Test func recentFactsAreSuppressed() {
        let rules = [rule("habit"), rule("slow", .brands, slow: true), rule("other", .care)]
        #expect(keys(rules, history: [shown("habit", .value, daysAgo: 7)]) == ["slow", "other"])
        #expect(keys(rules, history: [shown("habit", .value, daysAgo: 8)]).contains("habit"))
        #expect(!keys(rules, history: [shown("slow", .value, daysAgo: 30)]).contains("slow"))
        #expect(keys(rules, history: [shown("slow", .value, daysAgo: 31)]).contains("slow"))
    }

    @Test func notYesterdaysCategoryUnlessNothingElse() {
        let rules = [rule("a", .habits), rule("b", .weather)]
        let yesterday = [shown("x", .habits, daysAgo: 1)]
        #expect(keys(rules, history: yesterday) == ["b"])
        #expect(keys([rule("a", .habits)], history: yesterday) == ["a"])
    }

    @Test func scoreAddsBonuses() {
        let timely = rule("t", timely: true, score: 20)
        let fresh = InsightEngine.candidates(rules: [timely], context: f.context([]), filter: InsightFilter(), history: [])
        #expect(fresh.first?.score == Double(20 + 50 + 10))
        let seen = InsightEngine.candidates(rules: [rule("t", score: 20)], context: f.context([]), filter: InsightFilter(),
                                            history: [shown("t", .weather, daysAgo: 10)].map { var pick = $0; pick.key = "old"; return pick })
        #expect(seen.first?.score == 20.0)
    }

    @Test func pickIsStableForASeedAndVariesAcrossDays() {
        let candidates = (0..<12).map { rule("r\($0)").candidate }
        let seed = InsightEngine.seed(dayKey: "2026-11-05", installID: "install")
        let first = InsightEngine.pick(from: candidates, seed: seed)
        #expect(InsightEngine.pick(from: candidates.reversed(), seed: seed) == first)
        let picks = Set((1...20).compactMap { day in
            InsightEngine.pick(from: candidates, seed: InsightEngine.seed(dayKey: "2026-11-\(day)", installID: "install"))?.ruleId
        })
        #expect(picks.count > 3)
        #expect(InsightEngine.pick(from: [], seed: seed) == nil)
    }

    @Test func timelyUsuallyWins() {
        let candidates = InsightEngine.candidates(
            rules: [rule("timely", timely: true, score: 45)] + (0..<4).map { rule("r\($0)", score: 20) },
            context: f.context([]), filter: InsightFilter(), history: [])
        let wins = (1...200).count { day in
            InsightEngine.pick(from: candidates, seed: InsightEngine.seed(dayKey: "d\(day)", installID: "x"))?.ruleId == "timely"
        }
        #expect(wins > 100)
    }
}

@MainActor
struct DailyInsightStoreTests {
    private let f = Fixture()

    private func defaults() -> UserDefaults {
        let name = "insights-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func rules(_ entries: [(String, InsightCategory, Bool)]) -> [any InsightRule] {
        entries.map { id, category, money in
            AnyRule(id: id, category: category, candidate: InsightCandidate(
                ruleId: id, category: category, key: "\(id):k", title: "Title \(id)", score: 20, mentionsMoney: money))
        }
    }

    private struct AnyRule: InsightRule {
        var id: String
        var category: InsightCategory
        var minimumData = DataRequirement.none
        var candidate: InsightCandidate
        func evaluate(_ context: InsightContext) -> InsightCandidate? { candidate }
    }

    private let pool: [(String, InsightCategory, Bool)] = [
        ("a", .habits, false), ("b", .weather, false), ("c", .value, true), ("d", .brands, false), ("e", .care, false),
    ]

    @Test func sameDayShowsTheStoredPickWithoutRecomputing() {
        let storage = defaults()
        let store = DailyInsightStore(defaults: storage, installID: "seed")
        store.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        let first = store.today

        // A "relaunch": a new store on the same storage, and a context that would fail if asked for.
        let relaunched = DailyInsightStore(defaults: storage, installID: "seed")
        var asked = false
        relaunched.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) {
            asked = true
            return f.context([])
        }
        #expect(relaunched.today == first)
        #expect(!asked)
    }

    @Test func wipedStoreAndSameSeedGiveTheSamePick() {
        let a = DailyInsightStore(defaults: defaults(), installID: "seed")
        let b = DailyInsightStore(defaults: defaults(), installID: "seed")
        a.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        b.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        #expect(a.today?.key == b.today?.key)
    }

    @Test func aNewDayGetsANewPick() {
        let store = DailyInsightStore(defaults: defaults(), installID: "seed")
        store.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        let tomorrow = f.calendar.date(byAdding: .day, value: 1, to: f.now)!
        store.refresh(now: tomorrow, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        #expect(store.today?.date == DayKey.make(for: tomorrow))
        #expect(store.history.count == 2)
    }

    @Test func disablingThePicksCategoryReplacesItOnceThenStaysStable() throws {
        let storage = defaults()
        let store = DailyInsightStore(defaults: storage, installID: "seed")
        store.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        let first = try #require(store.today?.category)

        let filter = InsightFilter(disabledCategories: [first])
        store.refresh(now: f.now, filter: filter, rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        let replacement = store.today
        #expect(replacement?.category != first)
        #expect(replacement?.isEmpty == false)

        // Turning the category back on doesn't bring the first one back today.
        store.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        #expect(store.today == replacement)
    }

    @Test func feelGoodReplacesAMoneyPick() {
        let store = DailyInsightStore(defaults: defaults(), installID: "seed")
        store.refresh(now: f.now, filter: InsightFilter(), rules: rules([("c", .value, true), ("a", .habits, false)]),
                      itemExists: { _ in true }) { f.context([]) }
        store.refresh(now: f.now, filter: InsightFilter(feelGood: true), rules: rules([("c", .value, true), ("a", .habits, false)]),
                      itemExists: { _ in true }) { f.context([]) }
        #expect(store.today?.mentionsMoney == false)
        #expect(store.today?.ruleId == "a")
    }

    @Test func deletedItemReplacesThePick() {
        let id = UUID()
        let itemRule = AnyRule(id: "item", category: .value, candidate: InsightCandidate(
            ruleId: "item", category: .value, key: "item:k", title: "About an item", score: 20, relatedItemId: id))
        let store = DailyInsightStore(defaults: defaults(), installID: "seed")
        store.refresh(now: f.now, filter: InsightFilter(), rules: [itemRule], itemExists: { _ in true }) { f.context([]) }
        #expect(store.today?.relatedItemId == id)
        store.refresh(now: f.now, filter: InsightFilter(), rules: [itemRule], itemExists: { _ in false }) { f.context([]) }
        #expect(store.today?.isEmpty == true)
    }

    @Test func anEmptyDayIsStoredAndNotRecomputed() {
        let store = DailyInsightStore(defaults: defaults(), installID: "seed")
        store.refresh(now: f.now, filter: InsightFilter(), rules: [], itemExists: { _ in true }) { f.context([]) }
        #expect(store.today?.isEmpty == true)
        var asked = false
        store.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) {
            asked = true
            return f.context([])
        }
        #expect(!asked)
        #expect(store.today?.isEmpty == true)
    }

    @Test func turningInsightsBackOnPicksAgain() {
        let store = DailyInsightStore(defaults: defaults(), installID: "seed")
        store.refresh(now: f.now, filter: InsightFilter(), rules: [], itemExists: { _ in true }) { f.context([]) }
        store.resetToday(now: f.now)
        store.refresh(now: f.now, filter: InsightFilter(), rules: rules(pool), itemExists: { _ in true }) { f.context([]) }
        #expect(store.today?.isEmpty == false)
    }

    @Test func hideForTodayIsPerDate() {
        let store = DailyInsightStore(defaults: defaults(), installID: "seed")
        store.hideOnToday(now: f.now)
        #expect(store.isHiddenOnToday(now: f.now))
        #expect(!store.isHiddenOnToday(now: f.calendar.date(byAdding: .day, value: 1, to: f.now)!))
    }
}
