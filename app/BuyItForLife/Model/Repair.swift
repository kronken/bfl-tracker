import Foundation
import SwiftData

/// A repair done to an item: a resole, a new zip. Its price adds to the
/// item's total cost.
@Model
final class Repair {
    var id: UUID = UUID()
    /// "Resole", "New zip".
    var name: String = ""
    /// What was done, and by whom.
    var details: String = ""
    var date: Date = Date.now
    var priceCents: Int = 0
    var item: Item?

    init(name: String, details: String = "", date: Date, priceCents: Int) {
        self.name = name
        self.details = details
        self.date = date
        self.priceCents = priceCents
    }
}
