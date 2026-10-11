import Foundation
import SwiftData

/// For an item made of identical pieces (socks, boxers): pieces bought or
/// retired. The item's pieces in use, original price and first purchase date
/// all follow from these.
@Model
final class PieceEvent {
    enum Kind: String, CaseIterable, Sendable { case bought, retired }

    /// Why pieces were retired. Stored as the title.
    static let retireReasons = ["Worn out", "Broken", "Lost", "Gave away", "Other"]

    var id: UUID = UUID()
    var kindRaw: String = Kind.bought.rawValue
    var quantity: Int = 1
    var date: Date = Date.now
    /// Bought only: the price for all pieces in this purchase.
    var priceCents: Int?
    /// Retired only: one of `retireReasons`.
    var reason: String?
    var item: Item?

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .bought }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: Kind, quantity: Int, date: Date, priceCents: Int? = nil, reason: String? = nil) {
        self.kindRaw = kind.rawValue
        self.quantity = quantity
        self.date = date
        self.priceCents = priceCents
        self.reason = reason
    }
}
