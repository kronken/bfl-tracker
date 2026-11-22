import Foundation

/// One item as the "What you wore" chart sees it.
nonisolated struct WearShareEntry: Sendable {
    var id: UUID
    var name: String
    /// "yyyy-MM-dd" of every day it was logged.
    var dayKeys: Set<String>
}

/// Each item's share of a category's wears per month, for a 100% stacked bar
/// chart: every month with wears is a full bar split by item. The five most
/// worn items over the period keep their own colour; the rest are "Other".
nonisolated struct WearShare: Equatable, Sendable {
    nonisolated struct Series: Identifiable, Equatable, Sendable {
        /// The item id, or "other".
        var id: String
        var name: String
        /// Index into the chart palette; nil for "Other" (grey).
        var colorIndex: Int?
        /// Wear days per month, aligned with `months`.
        var counts: [Int]
        var total: Int { counts.reduce(0, +) }
    }

    static let maxNamed = 5

    /// First day of each month, oldest first, ending with this month.
    var months: [Date]
    /// Most worn first; only series with wears in the period.
    var series: [Series]

    init(entries: [WearShareEntry], months count: Int = 12, now: Date = .now, calendar: Calendar = .current) {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        months = (0..<count).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        let monthKeys = months.map { String(DayKey.make(for: $0, calendar: calendar).prefix(7)) }
        let index = Dictionary(uniqueKeysWithValues: monthKeys.enumerated().map { ($1, $0) })

        let all: [Series] = entries.compactMap { entry in
            var counts = Array(repeating: 0, count: monthKeys.count)
            for key in entry.dayKeys {
                if let month = index[String(key.prefix(7))] { counts[month] += 1 }
            }
            let series = Series(id: entry.id.uuidString, name: entry.name, colorIndex: nil, counts: counts)
            return series.total > 0 ? series : nil
        }
        .sorted { $0.total != $1.total ? $0.total > $1.total
                  : $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var shown = all.prefix(Self.maxNamed).enumerated().map { offset, series in
            var series = series
            series.colorIndex = offset
            return series
        }
        let rest = all.dropFirst(Self.maxNamed)
        if !rest.isEmpty {
            let counts = (0..<monthKeys.count).map { month in rest.reduce(0) { $0 + $1.counts[month] } }
            shown.append(Series(id: "other", name: "Other (\(rest.count))", colorIndex: nil, counts: counts))
        }
        series = shown
    }

    var isEmpty: Bool { series.isEmpty }

    /// All wear days in `month` (an index into `months`).
    func total(month: Int) -> Int { series.reduce(0) { $0 + $1.counts[month] } }

    /// All wear days in the period.
    var total: Int { series.reduce(0) { $0 + $1.total } }

    /// A series' share of a month, 0…1; 0 for an empty month.
    func share(_ series: Series, month: Int) -> Double {
        let sum = total(month: month)
        return sum > 0 ? Double(series.counts[month]) / Double(sum) : 0
    }
}
