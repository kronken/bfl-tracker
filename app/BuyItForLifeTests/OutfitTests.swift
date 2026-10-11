import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

struct OutfitRulesTests {
    let jeansA = UUID(), jeansB = UUID(), shirt = UUID(), sweater = UUID(), watch = UUID()

    @Test func tappingSelectsAndDeselectsOnlyThatItem() {
        var selection: Set<UUID> = [jeansA, shirt]
        selection = OutfitRules.toggle(jeansB, in: selection)
        #expect(selection == [jeansA, jeansB, shirt]) // two pairs of jeans is fine
        selection = OutfitRules.toggle(jeansA, in: selection)
        #expect(selection == [jeansB, shirt])
    }

    @Test func dailyDriversArePreselectedOnlyOnUnsavedDays() {
        #expect(OutfitRules.effectiveSelection(saved: [], isSaved: false, dailyDrivers: [watch]) == [watch])
        // A saved day keeps exactly what was saved, even without the watch.
        #expect(OutfitRules.effectiveSelection(saved: [shirt], isSaved: true, dailyDrivers: [watch]) == [shirt])
    }

    @Test func favoritesFirstThenMostWorn() {
        #expect(OutfitRules.isOrderedBefore(favoriteA: true, wearsA: 1, favoriteB: false, wearsB: 300))
        #expect(OutfitRules.isOrderedBefore(favoriteA: false, wearsA: 300, favoriteB: false, wearsB: 20))
        #expect(!OutfitRules.isOrderedBefore(favoriteA: false, wearsA: 20, favoriteB: false, wearsB: 300))
    }

    @Test func categoriesMapToGroups() {
        #expect(OutfitGroup(category: .knitwear) == .tops)
        #expect(OutfitGroup(category: .bottoms) == .bottoms)
        #expect(OutfitGroup(category: .accessories) == .more)
    }
}

struct ReminderPlannerTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return c
    }()

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func todayWhenNothingLoggedAndTimeAhead() {
        #expect(ReminderPlanner.nextFireDate(now: at(14), minutes: 20 * 60, loggedToday: false, calendar: calendar) == at(20))
    }

    @Test func tomorrowOnceLogged() {
        #expect(ReminderPlanner.nextFireDate(now: at(14), minutes: 20 * 60, loggedToday: true, calendar: calendar) == at(20, day: 11))
    }

    @Test func tomorrowWhenTimeHasPassed() {
        #expect(ReminderPlanner.nextFireDate(now: at(21), minutes: 20 * 60, loggedToday: false, calendar: calendar) == at(20, day: 11))
        #expect(ReminderPlanner.nextFireDate(now: at(20), minutes: 20 * 60, loggedToday: false, calendar: calendar) == at(20, day: 11))
    }

    @Test func halfHourTimes() {
        #expect(ReminderPlanner.nextFireDate(now: at(8), minutes: 7 * 60 + 30, loggedToday: false, calendar: calendar) == at(7, 30, day: 11))
    }
}

@MainActor
struct SellSuggestionTests {
    private let context: ModelContext
    private let calendar = Calendar.current

    init() throws {
        let schema = Schema([Item.self, DayLog.self, Repair.self, PieceEvent.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func monthsAgo(_ months: Int, from now: Date) -> Date {
        calendar.date(byAdding: .month, value: -months, to: now)!
    }

    private func item(bought: Date, added: Date, dailyDriver: Bool = false) -> Item {
        let item = Item(name: "Chinos", category: .bottoms, purchaseDate: bought, purchasePriceCents: 10_000)
        item.createdAt = added
        item.isDailyDriver = dailyDriver
        context.insert(item)
        return item
    }

    @Test func neverLoggedCountsFromWhenItWasAdded() {
        let now = Date.now
        // Bought years ago but only just added: not a suggestion yet.
        let fresh = item(bought: monthsAgo(60, from: now), added: monthsAgo(1, from: now))
        #expect(!fresh.isSellSuggestion(months: 12, now: now))
        let forgotten = item(bought: monthsAgo(60, from: now), added: monthsAgo(13, from: now))
        #expect(forgotten.isSellSuggestion(months: 12, now: now))
    }

    @Test func lastLoggedWearCounts() throws {
        let now = Date.now
        let chinos = item(bought: monthsAgo(30, from: now), added: monthsAgo(30, from: now))
        let log = DayLog(dayKey: DayKey.make(for: monthsAgo(4, from: now)))
        context.insert(log)
        log.items = [chinos]
        #expect(chinos.monthsUnworn(now: now) == 4)
        #expect(!chinos.isSellSuggestion(months: 12, now: now))
        #expect(chinos.isSellSuggestion(months: 3, now: now))
    }

    @Test func dailyDriversAndSoldItemsAreNeverSuggested() {
        let now = Date.now
        let watch = item(bought: monthsAgo(40, from: now), added: monthsAgo(40, from: now), dailyDriver: true)
        #expect(!watch.isSellSuggestion(months: 3, now: now))
        let sold = item(bought: monthsAgo(40, from: now), added: monthsAgo(40, from: now))
        sold.soldDate = now
        #expect(!sold.isSellSuggestion(months: 3, now: now))
    }

    @Test func inactiveItemsAreLeftOffTodayButCanBeSold() {
        let now = Date.now
        let jeans = item(bought: monthsAgo(20, from: now), added: monthsAgo(20, from: now))
        #expect(jeans.isOfferedOnToday(on: now))
        jeans.isInactive = true
        #expect(!jeans.isOfferedOnToday(on: now))
        #expect(jeans.isSellSuggestion(months: 12, now: now))
    }

    @Test func remindersCountOnlyNonDailyDriverPicks() throws {
        let watch = item(bought: .now, added: .now, dailyDriver: true)
        let log = try DayLog.fetchOrCreate(dayKey: DayKey.make(for: .now), in: context)
        log.items = [watch]
        log.userEdited = true
        #expect(!Reminders.isLoggedToday(context: context))
        let jeans = item(bought: .now, added: .now)
        log.items = [watch, jeans]
        #expect(Reminders.isLoggedToday(context: context))
    }
}

struct ReviewPromptTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return c
    }()

    private func keys(_ days: ClosedRange<Int>) -> Set<String> {
        Set(days.map { String(format: "2026-10-%02d", $0) })
    }

    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 9))! }

    @Test func countsConsecutiveDaysEndingToday() {
        #expect(ReviewPrompt.streak(loggedDayKeys: keys(5...11), today: today, calendar: calendar) == 7)
        var gap = keys(5...11)
        gap.remove("2026-10-08")
        #expect(ReviewPrompt.streak(loggedDayKeys: gap, today: today, calendar: calendar) == 3)
        #expect(ReviewPrompt.streak(loggedDayKeys: keys(1...10), today: today, calendar: calendar) == 0)
    }

    @Test func asksAfterAWeekOncePerVersion() {
        #expect(!ReviewPrompt.shouldAsk(streak: 6, askedVersion: nil, currentVersion: "1.4"))
        #expect(ReviewPrompt.shouldAsk(streak: 7, askedVersion: nil, currentVersion: "1.4"))
        #expect(!ReviewPrompt.shouldAsk(streak: 30, askedVersion: "1.4", currentVersion: "1.4"))
        #expect(ReviewPrompt.shouldAsk(streak: 7, askedVersion: "1.3", currentVersion: "1.4"))
    }
}
