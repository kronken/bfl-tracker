import Foundation
import Observation
import SwiftData

/// Picks the day's insight once and keeps it: stored on this device as soon
/// as it's picked, shown again on every open that day, never recomputed
/// unless it can no longer be shown.
@MainActor
@Observable
final class DailyInsightStore {
    /// Today's pick; nil until worked out, `isEmpty` when there's nothing to say.
    private(set) var today: DailyInsight?
    /// Days whose Today one-liner was hidden with "Hide for today".
    private(set) var hiddenOnToday: Set<String>

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore
    @ObservationIgnored private let fixedInstallID: String?
    @ObservationIgnored private(set) var history: [DailyInsight]

    private enum Key {
        static let history = "dailyInsightHistory"
        static let hidden = "dailyInsightHiddenOnToday"
        static let installID = "insightInstallID"
    }

    /// Picks older than this are dropped; suppression looks back 30 days.
    static let historyDays = 60

    /// `installID` fixes the seed, for tests.
    init(defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore = .default, installID: String? = nil) {
        self.defaults = defaults
        self.cloud = cloud
        fixedInstallID = installID
        history = (defaults.data(forKey: Key.history))
            .flatMap { try? JSONDecoder().decode([DailyInsight].self, from: $0) } ?? []
        hiddenOnToday = Set(defaults.stringArray(forKey: Key.hidden) ?? [])
    }

    /// A random ID made once and kept in iCloud, so a reinstall or a new
    /// device picks the same insight for the same day and data.
    var installID: String {
        if let fixedInstallID { return fixedInstallID }
        if let id = cloud.string(forKey: Key.installID) ?? defaults.string(forKey: Key.installID) { return id }
        let id = UUID().uuidString
        cloud.set(id, forKey: Key.installID)
        defaults.set(id, forKey: Key.installID)
        return id
    }

    /// Shows today's stored pick, or picks one on the first open of the day.
    /// Re-picks (same seed, without the old one) only if the stored pick can
    /// no longer be shown.
    func refresh(now: Date = .now, filter: InsightFilter, rules: [any InsightRule] = InsightRules.all,
                 itemExists: (UUID) -> Bool, makeContext: () -> InsightContext) {
        let dayKey = DayKey.make(for: now)
        if let stored = history.first(where: { $0.date == dayKey }) {
            let stillValid = stored.isEmpty
                || (filter.allows(stored) && stored.relatedItemId.map(itemExists) ?? true)
            if stillValid {
                today = stored
                return
            }
            let excluded = stored.excludedKeys + [stored.key].compactMap { $0 }
            store(pick(dayKey: dayKey, filter: filter, rules: rules, excluding: excluded, context: makeContext()), now: now)
            return
        }
        store(pick(dayKey: dayKey, filter: filter, rules: rules, excluding: [], context: makeContext()), now: now)
    }

    /// Forgets today's pick, e.g. after insights were turned off and on.
    func resetToday(now: Date = .now) {
        let dayKey = DayKey.make(for: now)
        history.removeAll { $0.date == dayKey }
        today = nil
        save()
    }

    func hideOnToday(now: Date = .now) {
        hiddenOnToday.insert(DayKey.make(for: now))
        // Only recent days matter.
        let cutoff = DayKey.make(for: Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now)
        hiddenOnToday = hiddenOnToday.filter { $0 >= cutoff }
        defaults.set(Array(hiddenOnToday), forKey: Key.hidden)
    }

    func isHiddenOnToday(now: Date = .now) -> Bool { hiddenOnToday.contains(DayKey.make(for: now)) }

    #if DEBUG
    /// `-debugInsight <ruleId>`: shows that rule's insight for this run, for
    /// screenshots. Nothing is stored.
    func showForDebugging(ruleId: String, context: InsightContext) {
        guard let rule = InsightRules.all.first(where: { $0.id == ruleId }),
              let candidate = rule.evaluate(context) else { return }
        today = DailyInsight(date: DayKey.make(for: context.now), candidate: candidate)
    }
    #endif

    // MARK: Picking

    private func pick(dayKey: String, filter: InsightFilter, rules: [any InsightRule], excluding: [String],
                      context: InsightContext) -> DailyInsight {
        let candidates = InsightEngine.candidates(rules: rules, context: context, filter: filter,
                                                  history: history, excluding: Set(excluding))
        let chosen = InsightEngine.pick(from: candidates, seed: InsightEngine.seed(dayKey: dayKey, installID: installID))
        return DailyInsight(date: dayKey, candidate: chosen, excludedKeys: excluding)
    }

    private func store(_ pick: DailyInsight, now: Date) {
        history.removeAll { $0.date == pick.date }
        history.append(pick)
        let cutoff = DayKey.make(for: Calendar.current.date(byAdding: .day, value: -Self.historyDays, to: now) ?? now)
        history = history.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
        today = pick
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(history), forKey: Key.history)
    }
}

// MARK: - Context from the store

extension InsightContext {
    /// Everything the rules need, read from SwiftData and the app's state.
    @MainActor
    static func make(context: ModelContext, settings: AppSettings, weather: WeatherStore, now: Date = .now) -> InsightContext {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        let calendar = Calendar.current

        // One entry per day, merging sync duplicates.
        var days: [String: InsightDay] = [:]
        for log in logs {
            let ids = Set((log.items ?? []).map(\.id))
            guard !ids.isEmpty, let date = DayKey.date(from: log.dayKey, calendar: calendar) else { continue }
            var day = days[log.dayKey] ?? InsightDay(dayKey: log.dayKey, date: date, itemIDs: [])
            day.itemIDs.formUnion(ids)
            if day.temperatureC == nil, let snapshot = log.weather {
                day.temperatureC = snapshot.temperatureC
                day.conditions = snapshot.conditions
            }
            days[log.dayKey] = day
        }

        var current: Double?
        if case .loaded(let snapshot) = weather.today { current = snapshot.temperatureC }

        return InsightContext(
            items: items.map(\.insightItem),
            days: days.values.sorted { $0.dayKey < $1.dayKey },
            now: now,
            calendar: calendar,
            currentTempC: current,
            tomorrow: weather.tomorrow,
            paidOffTargetCents: settings.paidOffTargetCents,
            sellSuggestionMonths: settings.sellSuggestionMonths,
            buyLess: settings.buyLessEnabled
                ? InsightBuyLess(stats: BuyLessStats(purchases: items.flatMap(\.purchases),
                                                     enabledDate: settings.buyLessEnabledDate ?? now, now: now),
                                 monthlyLimitCents: settings.monthlyLimitCents,
                                 yearlyBudgetCents: settings.yearlyBudgetCents)
                : nil
        )
    }
}

extension Item {
    var insightItem: InsightItem {
        InsightItem(
            id: id, name: listName, categoryID: category?.id, categoryName: categoryName, typeID: itemType?.id,
            typeName: itemType?.name, isFavorite: isFavorite, isDailyDriver: isDailyDriver,
            isGift: isGift, isSecondHand: boughtSecondHand, isInactive: isInactive, createdAt: createdAt,
            stats: stats, brand: brand?.name, brandCountry: brand?.countryCode, madeIn: madeInCountryCode,
            minTempC: minTempC, maxTempC: maxTempC, conditions: conditions,
            repairs: (repairs ?? []).map { InsightItem.Repair(name: $0.name, date: $0.date, cents: $0.priceCents) },
            careLog: (careLog ?? []).compactMap { entry in
                entry.action.map { InsightItem.CareEntry(actionID: $0.id, actionName: $0.name,
                                                         isWashing: $0.isBuiltInWashing, date: entry.date) }
            }
        )
    }
}
