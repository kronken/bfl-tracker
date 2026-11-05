import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

@MainActor
struct CategoryMigrationTests {
    private let context: ModelContext

    init() throws {
        let schema = Schema(AppSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "categories-\(UUID().uuidString)")! }

    private func item(_ name: String, _ starter: StarterCategory) -> Item {
        let item = Item(name: name, starter: starter, purchaseDate: .now, purchasePriceCents: 1_000)
        context.insert(item)
        return item
    }

    private var categories: [ClothingCategory] {
        ClothingCategory.sorted((try? context.fetch(FetchDescriptor<ClothingCategory>())) ?? [])
    }

    @Test func upgradingKeepsEveryItemInItsOldCategory() {
        let boots = item("Boots", .footwear)
        let sweater = item("Sweater", .knitwear)
        let socks = item("Socks", .underwear)
        let defaults = freshDefaults()
        ClothingCategory.ensureSetup(in: context, defaults: defaults)

        #expect(categories.map(\.name) == StarterCategory.upgradeSet.map(\.title))
        #expect(boots.category?.name == "Footwear")
        #expect(sweater.category?.name == "Knitwear")
        #expect(socks.category?.isBuiltInBasics == true)
        #expect(boots.category?.iconName == "Categories/footwear")
        #expect(((try? context.fetch(FetchDescriptor<CareAction>())) ?? []).map(\.name) == ["Washing"])

        // Running again changes nothing.
        ClothingCategory.ensureSetup(in: context, defaults: defaults)
        #expect(categories.count == StarterCategory.upgradeSet.count)
        #expect(((try? context.fetch(FetchDescriptor<CareAction>())) ?? []).count == 1)
    }

    @Test func newUsersGetTheStarterSet() {
        ClothingCategory.ensureSetup(in: context, defaults: freshDefaults())
        #expect(categories.map(\.name) == ["Footwear", "Outerwear", "Tops", "Bottoms", "Accessories", "Basics"])
        #expect(categories.count { $0.isBuiltInBasics } == 1)
        #expect(((try? context.fetch(FetchDescriptor<ItemType>())) ?? []).isEmpty)
    }

    @Test func itemsFromAnOlderVersionAreFiledLater() {
        let defaults = freshDefaults()
        ClothingCategory.ensureSetup(in: context, defaults: defaults)
        let hat = item("Hat", .headwear)          // no Headwear among the starters
        ClothingCategory.ensureSetup(in: context, defaults: defaults)
        #expect(hat.category?.name == "Headwear")
        #expect(categories.last?.name == "Headwear")
    }

    @Test func copiesFromTwoDevicesAreMerged() {
        let older = ClothingCategory(name: "Footwear", sortIndex: 0, seedKey: "footwear")
        older.createdAt = .distantPast
        let newer = ClothingCategory(name: "Footwear", sortIndex: 0, seedKey: "footwear")
        context.insert(older)
        context.insert(newer)
        let boots = item("Boots", .footwear)
        boots.category = newer
        let type = ItemType(name: "Leather boots", sortIndex: 0)
        context.insert(type)
        type.category = newer

        ClothingCategory.ensureSetup(in: context, defaults: freshDefaults())

        #expect(categories.count { $0.seedKey == "footwear" } == 1)
        #expect(boots.category?.id == older.id)
        #expect(type.category?.id == older.id)
    }

    @Test func deletingACategoryMovesItsItemsToBasics() {
        ClothingCategory.ensureSetup(in: context, defaults: freshDefaults())
        let outerwear = categories.first { $0.name == "Outerwear" }!
        let denim = ItemType.create(name: "Denim jackets", in: outerwear, context: context)
        let jacket = item("Jacket", .outerwear)
        jacket.setCategory(outerwear)
        jacket.itemType = denim
        let sold = item("Old jacket", .outerwear)
        sold.setCategory(outerwear)
        sold.soldDate = .now

        ClothingCategory.delete(outerwear, in: context)

        #expect(jacket.category?.isBuiltInBasics == true)
        #expect(jacket.itemType == nil)
        #expect(sold.category?.isBuiltInBasics == true)
        #expect(!categories.contains { $0.name == "Outerwear" })
        #expect(((try? context.fetch(FetchDescriptor<ItemType>())) ?? []).isEmpty)
    }

    @Test func basicsCannotBeDeleted() {
        let basics = ClothingCategory.ensureSetup(in: context, defaults: freshDefaults())
        ClothingCategory.delete(basics, in: context)
        #expect(categories.contains { $0.isBuiltInBasics })
    }

    @Test func changingCategoryClearsTheType() {
        ClothingCategory.ensureSetup(in: context, defaults: freshDefaults())
        let footwear = categories.first { $0.name == "Footwear" }!
        let tops = categories.first { $0.name == "Tops" }!
        let boots = ItemType.create(name: "Leather boots", in: footwear, context: context)
        let item = item("Boots", .footwear)
        item.setCategory(footwear)
        item.itemType = boots
        item.setCategory(footwear)
        #expect(item.itemType?.id == boots.id)
        item.setCategory(tops)
        #expect(item.itemType == nil)
        #expect(item.categoryRaw == "tops")
    }

    @Test func deletingATypeKeepsItsItems() {
        ClothingCategory.ensureSetup(in: context, defaults: freshDefaults())
        let bottoms = categories.first { $0.name == "Bottoms" }!
        let jeans = ItemType.create(name: "Jeans", in: bottoms, context: context)
        let pair = item("501", .bottoms)
        pair.setCategory(bottoms)
        pair.itemType = jeans
        ItemType.delete(jeans, in: context)
        #expect(pair.itemType == nil)
        #expect(pair.category?.id == bottoms.id)
    }
}

struct CategoryRulesTests {
    @Test func namesAreUniqueIgnoringCase() {
        let existing: [(id: UUID, name: String)] = [(UUID(), "Footwear"), (UUID(), "Denim jackets")]
        #expect(!CategoryRules.isNameAvailable(" footwear ", among: existing, excluding: nil))
        #expect(CategoryRules.isNameAvailable("Footwear", among: existing, excluding: existing[0].id))
        #expect(!CategoryRules.isNameAvailable("", among: existing, excluding: nil))
        #expect(CategoryRules.isTaken("FOOTWEAR", among: existing, excluding: nil))
    }

    @Test func suggestionsHideWhatExists() {
        #expect(CategoryRules.typeSuggestions(forCategoryNamed: "Bottoms") == ["Jeans", "Chinos", "Work pants", "Shorts"])
        #expect(CategoryRules.typeSuggestions(forCategoryNamed: "Workwear").isEmpty)
        #expect(CategoryRules.suggestions(["Jeans", "Chinos"], excluding: ["jeans"]) == ["Chinos"])
    }

    @Test func typeNamesInsideSentences() {
        #expect(InsightCopy.midSentence("Denim jackets") == "denim jackets")
        #expect(InsightCopy.midSentence("T-shirts") == "T-shirts")
        #expect(InsightCopy.midSentence("APC jeans") == "APC jeans")
    }
}

@MainActor
struct CareTests {
    private let context: ModelContext

    init() throws {
        let schema = Schema(AppSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func log(_ item: Item, _ action: CareAction, daysAgo: Int) {
        let entry = CareLogEntry(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!)
        context.insert(entry)
        entry.item = item
        entry.action = action
    }

    @Test func washingIsMadeOnceAndMerged() {
        let a = CareAction.ensureWashing(in: context)
        #expect(CareAction.ensureWashing(in: context).id == a.id)
        let copy = CareAction(name: "Washing", isBuiltInWashing: true)
        copy.createdAt = .distantFuture
        context.insert(copy)
        CareAction.ensureWashing(in: context)
        #expect(((try? context.fetch(FetchDescriptor<CareAction>())) ?? []).count == 1)
    }

    @Test func deletingAnActionDeletesItsLogsButNotItems() {
        let waxing = CareAction.create(name: "Waxing", in: context)
        let jacket = Item(name: "Jacket", purchaseDate: .now, purchasePriceCents: 1_000)
        context.insert(jacket)
        jacket.enabledCareActions = [waxing]
        log(jacket, waxing, daysAgo: 3)
        try? context.save()

        CareAction.delete(waxing, in: context)

        #expect((jacket.enabledCareActions ?? []).isEmpty)
        #expect(((try? context.fetch(FetchDescriptor<CareLogEntry>())) ?? []).isEmpty)
        #expect(((try? context.fetch(FetchDescriptor<Item>())) ?? []).count == 1)
    }

    @Test func washingCannotBeDeleted() {
        let washing = CareAction.ensureWashing(in: context)
        CareAction.delete(washing, in: context)
        #expect(((try? context.fetch(FetchDescriptor<CareAction>())) ?? []).count == 1)
    }

    @Test func deletingAnItemDeletesItsCareLog() {
        let washing = CareAction.ensureWashing(in: context)
        let shirt = Item(name: "Shirt", purchaseDate: .now, purchasePriceCents: 1_000)
        context.insert(shirt)
        log(shirt, washing, daysAgo: 1)
        try? context.save()
        context.delete(shirt)
        try? context.save()
        #expect(((try? context.fetch(FetchDescriptor<CareLogEntry>())) ?? []).isEmpty)
    }

    @Test func turningAnActionOffKeepsItsHistory() {
        let oiling = CareAction.create(name: "Oiling", in: context)
        let boots = Item(name: "Boots", purchaseDate: .now, purchasePriceCents: 1_000)
        context.insert(boots)
        boots.enabledCareActions = [oiling]
        log(boots, oiling, daysAgo: 5)
        boots.enabledCareActions = []
        #expect(boots.sortedCareLog.count == 1)
        #expect(boots.hasCare)
    }

    @Test func summaryCountsWearsStrictlyAfterTheLastLog() {
        let calendar = Calendar.current
        let day = { (ago: Int) in calendar.date(byAdding: .day, value: -ago, to: calendar.startOfDay(for: .now))! }
        let keys = Set([0, 1, 4, 5, 9].map { DayKey.make(for: day($0)) })
        let summary = CareSummary(logDates: [day(9), day(5)], wornDayKeys: keys)
        #expect(summary.count == 2)
        #expect(summary.wearsSince == 3)  // days 4, 1 and 0; not day 5 itself
        #expect(CareSummary(logDates: [], wornDayKeys: keys).subtitle() == "Never logged")
        #expect(CareSummary(logDates: [day(5)], wornDayKeys: keys).subtitle().contains("1 time · 3 wears since"))
    }
}

/// The new insight rules about types and care.
struct KindAndCareRuleTests {
    private let calendar = Calendar.current
    private let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!

    private func date(_ ago: Int) -> Date { calendar.date(byAdding: .day, value: -ago, to: calendar.startOfDay(for: now))! }

    private func item(_ name: String, type: (UUID, String)? = nil, prior: Int = 0, worn: [Int] = [], price: Int = 10_000,
                      bought: Int = 400, care: [(UUID, String, Int)] = []) -> InsightItem {
        InsightItem(
            id: UUID(), name: name, typeID: type?.0, typeName: type?.1, createdAt: date(bought),
            stats: ItemStats(purchaseDate: date(bought), purchasePriceCents: price, priorWearCount: prior,
                             loggedDayKeys: Set(worn.map { DayKey.make(for: date($0)) }), soldDate: nil, soldPriceCents: nil),
            careLog: care.map { .init(actionID: $0.0, actionName: $0.1, isWashing: false, date: date($0.2)) })
    }

    private func context(_ items: [InsightItem], buyLess: Bool = false, tomorrow: InsightForecast? = nil) -> InsightContext {
        var days: [String: InsightDay] = [:]
        for item in items {
            for key in item.stats.loggedDayKeys {
                days[key, default: InsightDay(dayKey: key, date: DayKey.date(from: key)!, itemIDs: [])].itemIDs.insert(item.id)
            }
        }
        return InsightContext(
            items: items, days: days.values.sorted { $0.dayKey < $1.dayKey }, now: now, tomorrow: tomorrow,
            buyLess: buyLess ? InsightBuyLess(stats: BuyLessStats(purchases: [], enabledDate: date(10), now: now),
                                              monthlyLimitCents: 5_000, yearlyBudgetCents: 30_000) : nil)
    }

    private let jeans = (UUID(), "Jeans")
    private let tees = (UUID(), "T-shirts")

    @Test func typeRulesWaitForFiveTypedItems() {
        let four = (0..<4).map { item("Pair \($0)", type: jeans) } + [item("Other")]
        #expect(!MostOwnedKindRule().minimumData.isMet(by: context(four)))
        let five = (0..<5).map { item("Pair \($0)", type: jeans) }
        #expect(MostOwnedKindRule().minimumData.isMet(by: context(five)))
    }

    @Test func mostOwnedKindNeedsAClearLead() {
        let three = (0..<3).map { item("Pair \($0)", type: jeans, prior: 10) } + (0..<2).map { item("Tee \($0)", type: tees) }
        #expect(MostOwnedKindRule().evaluate(context(three))?.title == "Jeans are your biggest group: 3 pieces.")
        let tied = (0..<3).map { item("Pair \($0)", type: jeans) } + (0..<3).map { item("Tee \($0)", type: tees) }
        #expect(MostOwnedKindRule().evaluate(context(tied)) == nil)
    }

    @Test func favouriteOfTheBunchNeedsSixtyPercent() {
        let favourite = item("Levi’s", type: jeans, worn: Array(0..<21))
        let others = [item("Lee", type: jeans, worn: Array(30..<35)), item("APC", type: jeans, worn: Array(40..<44))]
        let filler = (0..<2).map { item("Tee \($0)", type: tees) }
        let candidate = FavouriteOfTheBunchRule().evaluate(context([favourite] + others + filler))
        #expect(candidate?.title == "Of your 3 jeans, the Levi’s gets 7 of every 10 wears.")
        let even = [item("A", type: jeans, worn: Array(0..<10)), item("B", type: jeans, worn: Array(10..<20)),
                    item("C", type: jeans, worn: Array(20..<30))] + filler
        #expect(FavouriteOfTheBunchRule().evaluate(context(even)) == nil)
    }

    @Test func spendShareMentionsMoney() {
        let boots = (UUID(), "Boots")
        let items = [item("Iron Ranger", type: boots, price: 40_000)] + (0..<4).map { item("Tee \($0)", type: tees, price: 2_000) }
        let candidate = KindSpendShareRule().evaluate(context(items))
        #expect(candidate?.mentionsMoney == true)
        #expect(candidate?.isSlow == true)
    }

    @Test func numberNOnlyWithBuyLessGoals() {
        let newPair = item("New pair", type: jeans, bought: 1)
        let items = [newPair] + (0..<3).map { item("Pair \($0)", type: jeans, prior: 70, bought: 730) } + [item("Tee", type: tees)]
        #expect(NumberNRule().evaluate(context(items)) == nil)
        let candidate = NumberNRule().evaluate(context(items, buyLess: true))
        #expect(candidate?.title == "That makes 4 jeans.")
        #expect(candidate?.detail == "The other three average 35 wears a year.")
    }

    @Test func kindMilestoneCrossedToday() {
        let items = [item("A", type: jeans, prior: 249, worn: [0]), item("B", type: jeans)] + (0..<3).map { item("T\($0)", type: tees) }
        #expect(KindMilestoneRule().evaluate(context(items))?.title == "Your jeans just passed 250 wears together.")
        let notToday = [item("A", type: jeans, prior: 249, worn: [1]), item("B", type: jeans)] + (0..<3).map { item("T\($0)", type: tees) }
        #expect(KindMilestoneRule().evaluate(context(notToday)) == nil)
    }

    @Test func dueByHabitAfterOneAndAHalfTimesTheUsualGap() {
        let oiling = UUID()
        // Logs 60, 40 and 20 days ago with 9 wears between each (1.5 × 9 = 13.5); then 15 wears since.
        let worn = Array(stride(from: 59, to: 41, by: -2)) + Array(stride(from: 39, to: 21, by: -2)) + Array(0..<15)
        let boots = item("Boots", worn: worn, care: [(oiling, "Oiling", 60), (oiling, "Oiling", 40), (oiling, "Oiling", 20)])
        let dry = InsightForecast(lowC: 2, highC: 6, conditions: .sun)
        let candidate = CareDueByHabitRule().evaluate(context([boots], tomorrow: dry))
        #expect(candidate?.title == "15 wears since the Boots’s last oiling.")
        #expect(candidate?.isTimely == true)
        let fewer = item("Boots", worn: Array(stride(from: 59, to: 41, by: -2)) + Array(stride(from: 39, to: 21, by: -2)) + Array(0..<13),
                         care: [(oiling, "Oiling", 60), (oiling, "Oiling", 40), (oiling, "Oiling", 20)])
        #expect(CareDueByHabitRule().evaluate(context([fewer])) == nil)
    }

    @Test func careMilestoneOnTheTenthLogToday() {
        let waxing = UUID()
        let tenth = item("Jacket", care: (0..<10).map { (waxing, "Waxing", $0 * 30) })
        #expect(CareMilestoneRule().evaluate(context([tenth]))?.title == "Tenth waxing for the Jacket.")
        let ninth = item("Jacket", care: (0..<9).map { (waxing, "Waxing", $0 * 30) })
        #expect(CareMilestoneRule().evaluate(context([ninth])) == nil)
    }

    @Test func careAnniversaryNotIfDoneRecently() {
        let waxing = UUID()
        #expect(CareAnniversaryRule().evaluate(context([item("Jacket", care: [(waxing, "Waxing", 366)])])) != nil)
        #expect(CareAnniversaryRule().evaluate(context([item("Jacket", care: [(waxing, "Waxing", 366), (waxing, "Waxing", 10)])])) == nil)
    }

    @Test func newRulesHaveUniqueIDsAndTheirOwnTopics() {
        let ids = InsightRules.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(InsightRules.kindsAndCare.allSatisfy { $0.category == .types || $0.category == .careLog })
    }
}
