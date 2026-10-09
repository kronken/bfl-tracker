import Foundation

/// Clothing category. The raw value is what gets stored and synced, so never
/// rename a case's raw value; change `title` instead.
nonisolated enum ItemCategory: String, CaseIterable, Identifiable, Sendable {
    case footwear
    case bottoms
    case tops
    case knitwear
    case outerwear
    case headwear
    case underwear
    case accessories
    case other

    var id: String { rawValue }

    /// Unknown raw values (e.g. synced from a newer app version) fall back to `.other`.
    init(storedValue: String) {
        self = ItemCategory(rawValue: storedValue) ?? .other
    }

    var title: String {
        switch self {
        case .footwear: "Footwear"
        case .bottoms: "Bottoms"
        case .tops: "Tops"
        case .knitwear: "Knitwear"
        case .outerwear: "Outerwear"
        case .headwear: "Headwear"
        case .underwear: "Underwear & socks"
        case .accessories: "Accessories"
        case .other: "Other"
        }
    }
}
