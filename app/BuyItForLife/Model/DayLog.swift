import Foundation
import SwiftData

/// One calendar day: what was worn, plus a snapshot of that day's weather.
@Model
final class DayLog {
    /// "yyyy-MM-dd", see `DayKey`.
    var dayKey: String = ""
    var items: [Item]? = []

    // Weather snapshot
    var temperatureC: Double?
    var feelsLikeC: Double?
    /// WeatherKit condition raw value, e.g. "drizzle".
    var conditionRaw: String?
    var symbolName: String?
    var placeName: String?

    init(dayKey: String) {
        self.dayKey = dayKey
    }
}

extension DayLog {
    /// Returns the log for `dayKey`, creating it if needed. CloudKit can't
    /// enforce uniqueness, so if sync produced duplicates they are merged into
    /// one here.
    static func fetchOrCreate(dayKey: String, in context: ModelContext) throws -> DayLog {
        let descriptor = FetchDescriptor<DayLog>(predicate: #Predicate { $0.dayKey == dayKey })
        let matches = try context.fetch(descriptor)
        guard let keeper = matches.first else {
            let log = DayLog(dayKey: dayKey)
            context.insert(log)
            return log
        }
        for duplicate in matches.dropFirst() {
            keeper.absorb(duplicate)
            context.delete(duplicate)
        }
        return keeper
    }

    /// Moves another log's items into this one and fills in missing weather.
    func absorb(_ other: DayLog) {
        var current = items ?? []
        let currentIDs = Set(current.map(\.id))
        current.append(contentsOf: (other.items ?? []).filter { !currentIDs.contains($0.id) })
        items = current

        if temperatureC == nil {
            temperatureC = other.temperatureC
            feelsLikeC = other.feelsLikeC
            conditionRaw = other.conditionRaw
            symbolName = other.symbolName
            placeName = other.placeName
        }
    }

    func isWorn(_ item: Item) -> Bool {
        (items ?? []).contains { $0.id == item.id }
    }

    func toggle(_ item: Item) {
        var current = items ?? []
        if let index = current.firstIndex(where: { $0.id == item.id }) {
            current.remove(at: index)
        } else {
            current.append(item)
        }
        items = current
    }
}
