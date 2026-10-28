import Foundation
import SwiftData

/// Where clothes are worn: Everyday (built in), Office, Gym… Today shows one
/// occasion at a time and can pick one automatically by weekday. Every
/// property is optional or defaulted, as required for CloudKit sync.
@Model
final class Occasion {
    var id: UUID = UUID()
    var name: String = ""
    /// Only Everyday. It can be renamed or hidden, never deleted.
    var isBuiltIn: Bool = false
    /// Hidden from Today. Only the built-in occasion can be hidden.
    var isHidden: Bool = false
    /// Used when no day rule matches. One visible occasion should be default;
    /// if sync ever produces two, `OccasionRules` picks the first.
    var isDefault: Bool = false
    /// Days Today opens on this occasion, see `Weekdays`. 0 = no rule.
    var weekdaysRaw: Int = 0
    /// Position in the list, and rule priority when two share a weekday.
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    /// Items tagged with this occasion. Items with no occasions at all count
    /// as Everyday, so existing items need no migration.
    @Relationship(inverse: \Item.occasions) var items: [Item]? = []

    init(name: String, isBuiltIn: Bool = false, isDefault: Bool = false, weekdays: Weekdays = [], sortOrder: Int = 0) {
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isDefault = isDefault
        self.weekdaysRaw = weekdays.rawValue
        self.sortOrder = sortOrder
    }
}

extension Occasion {
    var weekdays: Weekdays {
        get { Weekdays(rawValue: weekdaysRaw) }
        set { weekdaysRaw = newValue.rawValue }
    }

    var info: OccasionInfo {
        OccasionInfo(id: id, name: name, isBuiltIn: isBuiltIn, isHidden: isBuiltIn && isHidden,
                     isDefault: isDefault, weekdays: weekdays, sortOrder: sortOrder, createdAt: createdAt)
    }

    static let builtInName = "Everyday"

    /// Makes sure there is exactly one built-in occasion and returns it. Two
    /// devices can each create one before syncing; the older one is kept and
    /// the other merged into it.
    @discardableResult
    static func ensureBuiltIn(in context: ModelContext) -> Occasion {
        let descriptor = FetchDescriptor<Occasion>(predicate: #Predicate { $0.isBuiltIn })
        let builtIns = ((try? context.fetch(descriptor)) ?? []).sorted(by: OccasionRules.isOlder)
        guard let keeper = builtIns.first else {
            let hasDefault = ((try? context.fetchCount(FetchDescriptor<Occasion>(predicate: #Predicate { $0.isDefault }))) ?? 0) > 0
            let everyday = Occasion(name: builtInName, isBuiltIn: true, isDefault: !hasDefault, sortOrder: 0)
            context.insert(everyday)
            try? context.save()
            return everyday
        }
        guard builtIns.count > 1 else { return keeper }
        for duplicate in builtIns.dropFirst() {
            keeper.isDefault = keeper.isDefault || duplicate.isDefault
            var tagged = keeper.items ?? []
            let ids = Set(tagged.map(\.id))
            tagged.append(contentsOf: (duplicate.items ?? []).filter { !ids.contains($0.id) })
            keeper.items = tagged
            DayLog.replaceOverrides(of: duplicate.id, with: keeper.id, in: context)
            context.delete(duplicate)
        }
        try? context.save()
        return keeper
    }
}

// MARK: - Changes

extension Occasion {
    /// A new occasion at the end of the list.
    static func create(name: String, weekdays: Weekdays, isDefault: Bool, in context: ModelContext) -> Occasion {
        let all = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        let occasion = Occasion(name: name.trimmingCharacters(in: .whitespacesAndNewlines), weekdays: weekdays,
                                sortOrder: (all.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(occasion)
        if isDefault { occasion.makeDefault(in: context) }
        return occasion
    }

    /// Makes this the one default occasion. A hidden Everyday is shown again,
    /// as the default has to be on Today.
    func makeDefault(in context: ModelContext) {
        for other in (try? context.fetch(FetchDescriptor<Occasion>())) ?? [] where other.id != id {
            other.isDefault = false
        }
        isDefault = true
        isHidden = false
    }

    /// Deletes a custom occasion. Its clothes stay; any left without an
    /// occasion go to Everyday (or to the default while Everyday is hidden),
    /// days that had switched to it go back to automatic, and if it was the
    /// default, Everyday takes over.
    static func delete(_ occasion: Occasion, in context: ModelContext) {
        guard !occasion.isBuiltIn else { return }
        let everyday = ensureBuiltIn(in: context)
        let orphans = (occasion.items ?? []).filter { item in
            (item.occasions ?? []).allSatisfy { $0.id == occasion.id }
        }
        let wasDefault = occasion.isDefault
        DayLog.replaceOverrides(of: occasion.id, with: nil, in: context)
        context.delete(occasion)
        if wasDefault { everyday.makeDefault(in: context) }

        let remaining = ((try? context.fetch(FetchDescriptor<Occasion>())) ?? []).filter { $0.id != occasion.id }
        let home = everyday.isHidden
            ? OccasionRules.defaultOccasion(remaining.map(\.info)).flatMap { info in remaining.first { $0.id == info.id } }
            : everyday
        for item in orphans {
            item.occasions = [home ?? everyday]
        }
        try? context.save()
    }

    /// Owned items that would vanish from Today if Everyday were hidden:
    /// those in no other occasion.
    static func itemsOnlyInBuiltIn(_ items: [Item], builtInID: UUID) -> [Item] {
        items.filter { !$0.isSold && $0.occasionIDs(builtInID: builtInID) == [builtInID] }
    }
}

extension Item {
    /// The item's occasions; an item with none is in the built-in one.
    func occasionIDs(builtInID: UUID?) -> Set<UUID> {
        OccasionRules.occasionIDs(tagged: (occasions ?? []).map(\.id), builtInID: builtInID)
    }
}

// MARK: - Weekdays

/// A set of weekdays, one bit per `Calendar` weekday (1 = Sunday … 7 = Saturday).
nonisolated struct Weekdays: OptionSet, Hashable, Sendable {
    let rawValue: Int

    /// The day for a `Calendar` weekday number, 1 = Sunday.
    static func day(_ weekday: Int) -> Weekdays { Weekdays(rawValue: 1 << (weekday - 1)) }

    static let workweek: Weekdays = [.day(2), .day(3), .day(4), .day(5), .day(6)]
    static let weekend: Weekdays = [.day(1), .day(7)]
    static let all: Weekdays = workweek.union(weekend)

    /// Calendar weekday numbers, starting from the calendar's first weekday.
    static func ordered(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    func contains(weekday: Int) -> Bool { contains(.day(weekday)) }

    /// "Weekdays", "Weekends", "Every day" or e.g. "Tue, Thu".
    func shortSummary(calendar: Calendar = .current) -> String {
        switch self {
        case []: "No day rule"
        case .all: "Every day"
        case .workweek: "Weekdays"
        case .weekend: "Weekends"
        default:
            Weekdays.ordered(calendar: calendar).filter { contains(weekday: $0) }
                .map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// "on weekdays", "at weekends", "every day" or e.g. "on Tuesdays and Thursdays".
    func phrase(calendar: Calendar = .current) -> String {
        switch self {
        case .all: return "every day"
        case .workweek: return "on weekdays"
        case .weekend: return "at weekends"
        default:
            let names = Weekdays.ordered(calendar: calendar).filter { contains(weekday: $0) }
                .map { calendar.standaloneWeekdaySymbols[$0 - 1] + "s" }
            return "on " + (names.formatted(.list(type: .and)))
        }
    }
}

// MARK: - Rules

/// An occasion as plain values, so the rules can be tested without SwiftData.
nonisolated struct OccasionInfo: Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isBuiltIn: Bool
    /// Only ever true for the built-in occasion.
    var isHidden: Bool
    var isDefault: Bool
    var weekdays: Weekdays
    var sortOrder: Int
    var createdAt: Date = .distantPast
}

/// Which occasion Today shows, and the words around it.
nonisolated enum OccasionRules {
    /// List order: `sortOrder`, then the built-in one, then oldest.
    static func isOrderedBefore(_ a: OccasionInfo, _ b: OccasionInfo) -> Bool {
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    static func isOlder(_ a: Occasion, _ b: Occasion) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
    }

    static func sorted(_ all: [OccasionInfo]) -> [OccasionInfo] { all.sorted(by: isOrderedBefore) }

    /// Occasions shown on Today, in order.
    static func visible(_ all: [OccasionInfo]) -> [OccasionInfo] { sorted(all).filter { !$0.isHidden } }

    /// The built-in occasion; the oldest if sync made two.
    static func builtIn(_ all: [OccasionInfo]) -> OccasionInfo? {
        all.filter(\.isBuiltIn).min { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString }
    }

    /// The default occasion: the first visible one marked default, or the
    /// first visible one if the default is hidden or missing.
    static func defaultOccasion(_ all: [OccasionInfo]) -> OccasionInfo? {
        let shown = visible(all)
        return shown.first(where: \.isDefault) ?? shown.first
    }

    /// The occasion picked without the user: the first visible one whose day
    /// rule matches `date`, otherwise the default.
    static func automatic(on date: Date, _ all: [OccasionInfo], calendar: Calendar = .current) -> OccasionInfo? {
        let weekday = calendar.component(.weekday, from: date)
        return visible(all).first { $0.weekdays.contains(weekday: weekday) } ?? defaultOccasion(all)
    }

    /// The occasion Today opens on for `date`: the day's override if it's
    /// still visible, otherwise the automatic one.
    static func occasion(on date: Date, override: UUID?, _ all: [OccasionInfo], calendar: Calendar = .current) -> OccasionInfo? {
        if let override, let chosen = visible(all).first(where: { $0.id == override }) { return chosen }
        return automatic(on: date, all, calendar: calendar)
    }

    /// An item's occasions; none means the built-in one.
    static func occasionIDs(tagged: [UUID], builtInID: UUID?) -> Set<UUID> {
        if !tagged.isEmpty { return Set(tagged) }
        return builtInID.map { [$0] } ?? []
    }

    /// The muted line under Today's switcher.
    static func note(showing: OccasionInfo, automatic: OccasionInfo, on date: Date, calendar: Calendar = .current) -> String {
        if showing.id != automatic.id {
            return "Just for this day. \(automatic.name) is the usual pick."
        }
        guard automatic.weekdays.contains(weekday: calendar.component(.weekday, from: date)) else {
            return "\(automatic.name) is your default."
        }
        return "\(automatic.name) \(automatic.weekdays.phrase(calendar: calendar)). Change rules in Settings."
    }

    /// Helper text under the weekday picker in the occasion sheet.
    static func ruleHelper(name: String, weekdays: Weekdays) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch weekdays {
        case []:
            return "No days picked. Choose \(trimmed.isEmpty ? "this occasion" : trimmed) on Today when you need it."
        case .workweek:
            return "Today opens on \(trimmed.isEmpty ? "this occasion" : trimmed) Monday to Friday."
        default:
            return "Today opens on \(trimmed.isEmpty ? "this occasion" : trimmed) on the days picked."
        }
    }

    /// Whether `name` is free: not empty and not used by another occasion,
    /// ignoring case.
    static func isNameAvailable(_ name: String, excluding id: UUID?, in all: [OccasionInfo]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !all.contains { $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
}
