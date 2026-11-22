import Foundation
import Testing
@testable import BuyItForLife

struct WearShareTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 22))! }

    private func entry(_ name: String, _ days: [String]) -> WearShareEntry {
        WearShareEntry(id: UUID(), name: name, dayKeys: Set(days))
    }

    private func september(_ count: Int, from start: Int = 1) -> [String] {
        (start..<(start + count)).map { String(format: "2026-09-%02d", $0) }
    }

    @Test func splitsAMonthByWearDays() {
        let share = WearShare(entries: [entry("Red Wing", september(10)), entry("Nike", september(20, from: 11))],
                              now: now, calendar: calendar)
        #expect(share.months.count == 12)
        let sep = 9 // Dec 2025 … Nov 2026
        #expect(share.series.map(\.name) == ["Nike", "Red Wing"])
        #expect(share.total(month: sep) == 30)
        #expect(abs(share.share(share.series[1], month: sep) - 1.0 / 3) < 0.0001)
        #expect(abs(share.share(share.series[0], month: sep) - 2.0 / 3) < 0.0001)
        #expect(share.total(month: 0) == 0)
        #expect(share.share(share.series[0], month: 0) == 0)
    }

    @Test func ignoresWearsOutsideThePeriodAndUnwornItems() {
        let share = WearShare(entries: [entry("Old", ["2025-11-30"]), entry("Never", []), entry("Now", ["2026-11-01"])],
                              now: now, calendar: calendar)
        #expect(share.series.map(\.name) == ["Now"])
        #expect(share.total == 1)
    }

    @Test func topFiveKeepColoursRestIsOther() {
        let entries = (0..<7).map { entry("Item \($0)", september(7 - $0)) }
        let share = WearShare(entries: entries, now: now, calendar: calendar)
        #expect(share.series.count == 6)
        #expect(share.series.prefix(5).map(\.colorIndex) == [0, 1, 2, 3, 4])
        #expect(share.series.last?.name == "Other (2)")
        #expect(share.series.last?.colorIndex == nil)
        #expect(share.series.last?.total == 3)
        #expect(share.total == 28)
    }

    @Test func emptyWhenNothingWorn() {
        #expect(WearShare(entries: [entry("A", [])], now: now, calendar: calendar).isEmpty)
    }
}
