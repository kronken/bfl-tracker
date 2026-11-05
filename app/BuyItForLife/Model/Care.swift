import Foundation
import SwiftData

/// Something done to look after clothes: washing (built in), waxing, oiling…
/// Turned on per item before it can be logged.
@Model
final class CareAction {
    var id: UUID = UUID()
    /// Unique, ignoring case.
    var name: String = ""
    /// Washing: exactly one, can't be deleted.
    var isBuiltInWashing: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    /// Items this action is turned on for.
    @Relationship(inverse: \Item.enabledCareActions) var items: [Item]? = []
    @Relationship(deleteRule: .cascade, inverse: \CareLogEntry.action) var entries: [CareLogEntry]? = []

    init(name: String, isBuiltInWashing: Bool = false, sortIndex: Int = 0) {
        self.name = name
        self.isBuiltInWashing = isBuiltInWashing
        self.sortIndex = sortIndex
    }

    static let washingName = "Washing"
}

/// One time an item was cared for.
@Model
final class CareLogEntry {
    var id: UUID = UUID()
    /// Day precision, local calendar.
    var date: Date = Date.now
    /// nil when empty.
    var note: String?
    var createdAt: Date = Date.now
    var item: Item?
    var action: CareAction?

    init(date: Date, note: String? = nil) {
        self.date = date
        self.note = note
    }
}

extension CareAction {
    /// SF Symbol: a drop for washing, sparkles for everything else.
    var iconName: String { isBuiltInWashing ? "drop" : "sparkles" }

    static func sorted(_ actions: [CareAction]) -> [CareAction] {
        actions.sorted { a, b in
            if a.isBuiltInWashing != b.isBuiltInWashing { return a.isBuiltInWashing }
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt < b.createdAt
        }
    }

    /// Makes sure there is exactly one Washing; copies made on two devices
    /// before syncing are merged into the oldest.
    @discardableResult
    static func ensureWashing(in context: ModelContext) -> CareAction {
        let all = (try? context.fetch(FetchDescriptor<CareAction>(predicate: #Predicate { $0.isBuiltInWashing }))) ?? []
        let ordered = all.sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString }
        guard let keeper = ordered.first else {
            let washing = CareAction(name: washingName, isBuiltInWashing: true, sortIndex: 0)
            context.insert(washing)
            return washing
        }
        for duplicate in ordered.dropFirst() {
            for entry in duplicate.entries ?? [] { entry.action = keeper }
            duplicate.entries = []
            for item in duplicate.items ?? [] where !(item.enabledCareActions ?? []).contains(where: { $0.id == keeper.id }) {
                item.enabledCareActions = (item.enabledCareActions ?? []) + [keeper]
            }
            context.delete(duplicate)
        }
        return keeper
    }

    static func create(name: String, in context: ModelContext) -> CareAction {
        let all = (try? context.fetch(FetchDescriptor<CareAction>())) ?? []
        let action = CareAction(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                sortIndex: (all.map(\.sortIndex).max() ?? 0) + 1)
        context.insert(action)
        return action
    }

    /// Deletes a custom action with its log entries; items just lose it.
    static func delete(_ action: CareAction, in context: ModelContext) {
        guard !action.isBuiltInWashing else { return }
        for item in action.items ?? [] {
            item.enabledCareActions = (item.enabledCareActions ?? []).filter { $0.id != action.id }
        }
        context.delete(action)
        try? context.save()
    }
}

// MARK: - Per item

/// How one action has gone for one item, as values for testing.
nonisolated struct CareSummary: Equatable, Sendable {
    var count: Int
    var lastDate: Date?
    /// Days worn strictly after the last log.
    var wearsSince: Int

    init(logDates: [Date], wornDayKeys: Set<String>, calendar: Calendar = .current) {
        count = logDates.count
        lastDate = logDates.max()
        if let lastDate {
            let lastKey = DayKey.make(for: lastDate, calendar: calendar)
            wearsSince = wornDayKeys.count { $0 > lastKey }
        } else {
            wearsSince = 0
        }
    }

    /// "12 Oct · 5 times · 6 wears since", or "Never logged".
    func subtitle(now: Date = .now, calendar: Calendar = .current) -> String {
        guard let lastDate else { return "Never logged" }
        let sameYear = calendar.component(.year, from: lastDate) == calendar.component(.year, from: now)
        let date = sameYear ? lastDate.formatted(.dateTime.day().month(.abbreviated))
                            : lastDate.formatted(.dateTime.day().month(.abbreviated).year())
        let times = count == 1 ? "1 time" : "\(count) times"
        let wears = wearsSince == 1 ? "1 wear since" : "\(wearsSince) wears since"
        return "\(date) · \(times) · \(wears)"
    }
}

extension Item {
    var enabledActions: [CareAction] { CareAction.sorted(enabledCareActions ?? []) }

    /// Newest first; same day by when it was logged.
    var sortedCareLog: [CareLogEntry] {
        (careLog ?? []).sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
    }

    func careSummary(for action: CareAction) -> CareSummary {
        CareSummary(logDates: (careLog ?? []).filter { $0.action?.id == action.id }.map(\.date), wornDayKeys: loggedDayKeys)
    }

    /// Actions with something to show: turned on, or logged before.
    var hasCare: Bool { !(enabledCareActions ?? []).isEmpty || !(careLog ?? []).isEmpty }
}
