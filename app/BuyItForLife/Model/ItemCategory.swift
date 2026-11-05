import Foundation

/// The categories the app used to have built in. Now only a seed table: it
/// names, orders and gives icons to the `ClothingCategory` records made for
/// new users and when upgrading, and maps the old stored `Item.categoryRaw`
/// onto them. The raw value is stored, so never rename one.
nonisolated enum StarterCategory: String, CaseIterable, Identifiable, Sendable {
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
        self = StarterCategory(rawValue: storedValue) ?? .other
    }

    var title: String {
        switch self {
        case .footwear: "Footwear"
        case .bottoms: "Bottoms"
        case .tops: "Tops"
        case .knitwear: "Knitwear"
        case .outerwear: "Outerwear"
        case .headwear: "Headwear"
        case .underwear: "Basics"
        case .accessories: "Accessories"
        case .other: "Other"
        }
    }

    /// The category artwork in the asset catalog.
    var iconName: String { "Categories/\(rawValue)" }

    /// A new user's categories, in order.
    static let newUserSet: [StarterCategory] = [.footwear, .outerwear, .tops, .bottoms, .accessories, .underwear]

    /// Everything, in the order the app showed it before categories became
    /// editable. Upgrading users get these.
    static let upgradeSet: [StarterCategory] = allCases
}
