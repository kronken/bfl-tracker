import Foundation
import SwiftData

/// A shop, website or market where items are bought. Every property is
/// optional or defaulted, as required for CloudKit sync.
@Model
final class Store {
    var id: UUID = UUID()
    /// Unique, ignoring case; see `BrandRules.isNameAvailable`.
    var name: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Item.store) var items: [Item]? = []

    init(name: String) {
        self.name = name
    }
}

extension Store {
    /// Stores sorted by name.
    static func sorted(_ stores: [Store]) -> [Store] {
        stores.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Owned and sold items bought here.
    var itemCount: Int { (items ?? []).count }

    /// What was paid here: purchases only, no repairs, no gifts.
    var spentCents: Int {
        (items ?? []).reduce(0) { total, item in total + item.purchases.reduce(0) { $0 + $1.cents } }
    }
}
