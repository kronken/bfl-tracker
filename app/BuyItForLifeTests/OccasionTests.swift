import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

struct OccasionRulesTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2
        return c
    }()

    /// 9 Oct 2026 is a Friday, 10 Oct a Saturday.
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private let everyday = OccasionInfo(id: UUID(), name: "Everyday", isBuiltIn: true, isHidden: false, isDefault: true,
                                        weekdays: [], sortOrder: 0)
    private let office = OccasionInfo(id: UUID(), name: "Office", isBuiltIn: false, isHidden: false, isDefault: false,
                                      weekdays: .workweek, sortOrder: 1)
    private let gym = OccasionInfo(id: UUID(), name: "Gym", isBuiltIn: false, isHidden: false, isDefault: false,
                                   weekdays: [], sortOrder: 2)
    private var all: [OccasionInfo] { [gym, office, everyday] }

    @Test func dayRulePicksOnMatchingWeekday() {
        #expect(OccasionRules.automatic(on: date(9), all, calendar: calendar)?.id == office.id)
    }

    @Test func defaultIsUsedWhenNoRuleMatches() {
        #expect(OccasionRules.automatic(on: date(10), all, calendar: calendar)?.id == everyday.id)
    }

    @Test func firstInOrderWinsWhenRulesShareADay() {
        var gymFridays = gym
        gymFridays.weekdays = .day(6)
        gymFridays.sortOrder = 0
        var everydayLast = everyday
        everydayLast.sortOrder = 5
        let picked = OccasionRules.automatic(on: date(9), [gymFridays, office, everydayLast], calendar: calendar)
        #expect(picked?.id == gym.id)
    }

    @Test func hiddenDefaultFallsBackToFirstVisible() {
        var hidden = everyday
        hidden.isHidden = true
        #expect(OccasionRules.defaultOccasion([hidden, office, gym])?.id == office.id)
        #expect(OccasionRules.visible([hidden, office, gym]).map(\.id) == [office.id, gym.id])
    }

    @Test func overrideWinsForItsDay() {
        #expect(OccasionRules.occasion(on: date(9), override: gym.id, all, calendar: calendar)?.id == gym.id)
        #expect(OccasionRules.occasion(on: date(9), override: nil, all, calendar: calendar)?.id == office.id)
    }

    @Test func overrideToHiddenOrDeletedOccasionIsIgnored() {
        var hidden = everyday
        hidden.isHidden = true
        hidden.isDefault = false
        let picked = OccasionRules.occasion(on: date(10), override: everyday.id, [hidden, office, gym], calendar: calendar)
        #expect(picked?.id == office.id)
        #expect(OccasionRules.occasion(on: date(9), override: UUID(), all, calendar: calendar)?.id == office.id)
    }

    @Test func itemsWithoutOccasionsAreInTheBuiltInOne() {
        #expect(OccasionRules.occasionIDs(tagged: [], builtInID: everyday.id) == [everyday.id])
        #expect(OccasionRules.occasionIDs(tagged: [office.id], builtInID: everyday.id) == [office.id])
    }

    @Test func notes() {
        #expect(OccasionRules.note(showing: office, automatic: office, on: date(9), calendar: calendar)
                == "Office on weekdays. Change rules in Settings.")
        #expect(OccasionRules.note(showing: everyday, automatic: everyday, on: date(10), calendar: calendar)
                == "Everyday is your default.")
        #expect(OccasionRules.note(showing: gym, automatic: office, on: date(9), calendar: calendar)
                == "Just for this day. Office is the usual pick.")
        // A default with a rule, picked on a day outside the rule.
        var officeDefault = office
        officeDefault.isDefault = true
        #expect(OccasionRules.note(showing: officeDefault, automatic: officeDefault, on: date(10), calendar: calendar)
                == "Office is your default.")
    }

    @Test func weekdayWording() {
        #expect(Weekdays.workweek.shortSummary(calendar: calendar) == "Weekdays")
        #expect(Weekdays([.day(3), .day(5)]).shortSummary(calendar: calendar) == "Tue, Thu")
        #expect(Weekdays([.day(3), .day(5)]).phrase(calendar: calendar) == "on Tuesdays and Thursdays")
        #expect(Weekdays.ordered(calendar: calendar) == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test func ruleHelper() {
        #expect(OccasionRules.ruleHelper(name: "Gym", weekdays: []) == "No days picked. Choose Gym on Today when you need it.")
        #expect(OccasionRules.ruleHelper(name: "Office", weekdays: .workweek) == "Today opens on Office Monday to Friday.")
        #expect(OccasionRules.ruleHelper(name: "Gym", weekdays: .day(3)) == "Today opens on Gym on the days picked.")
    }

    @Test func namesAreUniqueIgnoringCase() {
        #expect(!OccasionRules.isNameAvailable(" office ", excluding: nil, in: all))
        #expect(OccasionRules.isNameAvailable("Office", excluding: office.id, in: all))
        #expect(OccasionRules.isNameAvailable("Formal", excluding: nil, in: all))
        #expect(!OccasionRules.isNameAvailable("  ", excluding: nil, in: all))
    }
}

@MainActor
struct OccasionModelTests {
    private let context: ModelContext

    init() throws {
        let schema = Schema([Item.self, DayLog.self, Repair.self, PieceEvent.self, Occasion.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func item(_ name: String) -> Item {
        let item = Item(name: name, category: .tops, purchaseDate: .now, purchasePriceCents: 1_000)
        context.insert(item)
        return item
    }

    private var occasions: [Occasion] { (try? context.fetch(FetchDescriptor<Occasion>())) ?? [] }

    @Test func builtInIsCreatedOnceAsDefault() {
        let first = Occasion.ensureBuiltIn(in: context)
        let second = Occasion.ensureBuiltIn(in: context)
        #expect(first.id == second.id)
        #expect(first.isDefault && first.isBuiltIn && first.name == "Everyday")
        #expect(occasions.count == 1)
    }

    @Test func syncedDuplicateBuiltInsAreMerged() {
        let older = Occasion(name: "Everyday", isBuiltIn: true, isDefault: true)
        older.createdAt = .distantPast
        let newer = Occasion(name: "Everyday", isBuiltIn: true, isDefault: true)
        context.insert(older)
        context.insert(newer)
        let tee = item("Tee")
        tee.occasions = [newer]
        let log = DayLog(dayKey: "2026-10-09")
        log.occasionID = newer.id.uuidString
        context.insert(log)

        let kept = Occasion.ensureBuiltIn(in: context)
        #expect(kept.id == older.id)
        #expect(occasions.count == 1)
        #expect(tee.occasions?.map(\.id) == [older.id])
        #expect(log.occasionID == older.id.uuidString)
    }

    @Test func makingADefaultClearsTheOldOne() {
        let everyday = Occasion.ensureBuiltIn(in: context)
        let office = Occasion.create(name: "Office", weekdays: .workweek, isDefault: true, in: context)
        #expect(office.isDefault && !everyday.isDefault)
        #expect(office.sortOrder == 1)
    }

    @Test func deletingMovesOrphansToEverydayAndClearsOverrides() {
        let everyday = Occasion.ensureBuiltIn(in: context)
        let gym = Occasion.create(name: "Gym", weekdays: [], isDefault: true, in: context)
        let shorts = item("Shorts")
        shorts.occasions = [gym]
        let tee = item("Tee")
        tee.occasions = [everyday, gym]
        let log = DayLog(dayKey: "2026-10-09")
        log.occasionID = gym.id.uuidString
        context.insert(log)

        Occasion.delete(gym, in: context)

        #expect(occasions.map(\.id) == [everyday.id])
        #expect(everyday.isDefault)
        #expect(shorts.occasions?.map(\.id) == [everyday.id])
        #expect(tee.occasions?.map(\.id) == [everyday.id])
        #expect(log.occasionID == nil)
    }

    @Test func orphansGoToTheDefaultWhileEverydayIsHidden() {
        let everyday = Occasion.ensureBuiltIn(in: context)
        let office = Occasion.create(name: "Office", weekdays: .workweek, isDefault: true, in: context)
        let gym = Occasion.create(name: "Gym", weekdays: [], isDefault: false, in: context)
        everyday.isHidden = true
        let shorts = item("Shorts")
        shorts.occasions = [gym]

        Occasion.delete(gym, in: context)

        #expect(everyday.isHidden)
        #expect(shorts.occasions?.map(\.id) == [office.id])
    }

    @Test func builtInCannotBeDeleted() {
        let everyday = Occasion.ensureBuiltIn(in: context)
        Occasion.delete(everyday, in: context)
        #expect(occasions.count == 1)
    }

    @Test func itemsOnlyInEverydayAreCounted() {
        let everyday = Occasion.ensureBuiltIn(in: context)
        let office = Occasion.create(name: "Office", weekdays: .workweek, isDefault: false, in: context)
        _ = item("Untagged")                       // no occasions: Everyday
        item("Tagged").occasions = [everyday]
        item("Both").occasions = [everyday, office]
        item("Office only").occasions = [office]
        let sold = item("Sold")
        sold.soldDate = .now
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        #expect(Set(Occasion.itemsOnlyInBuiltIn(all, builtInID: everyday.id).map(\.name)) == ["Untagged", "Tagged"])
    }
}
