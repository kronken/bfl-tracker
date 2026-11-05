import Foundation
import SwiftData

/// A clothing brand and where it's based. Every property is optional or
/// defaulted, as required for CloudKit sync.
@Model
final class Brand {
    var id: UUID = UUID()
    /// Unique, ignoring case; see `BrandRules.isNameAvailable`.
    var name: String = ""
    /// ISO 3166-1 alpha-2, e.g. "US". Display it with `Countries.name(for:)`.
    var countryCode: String?
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Item.brand) var items: [Item]? = []

    init(name: String, countryCode: String? = nil) {
        self.name = name
        self.countryCode = countryCode
    }
}

extension Brand {
    /// Brands sorted by name, the way people read them ("A.P.C." before "Barbour").
    static func sorted(_ brands: [Brand]) -> [Brand] {
        brands.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Owned and sold items with this brand.
    var itemCount: Int { (items ?? []).count }
}

nonisolated enum BrandRules {
    /// Whether `name` is free: not empty and not used by another brand,
    /// ignoring case, accents and surrounding spaces.
    static func isNameAvailable(_ name: String, excluding id: UUID?, in brands: [(id: UUID, name: String)]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !brands.contains { $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// Free text such as a size: trimmed, nil when empty.
    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Countries

/// Countries by ISO code, named in the user's language. Only codes are stored.
nonisolated enum Countries {
    /// Two-letter codes that aren't countries.
    private static let excluded: Set<String> = ["EU", "EZ", "UN", "QO", "XA", "XB", "ZZ"]

    /// Every country, sorted by its localized name.
    static func all(locale: Locale = .current) -> [String] {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) && !excluded.contains($0) }
            .filter { locale.localizedString(forRegionCode: $0) != nil }
            .sorted { name(for: $0, locale: locale).localizedStandardCompare(name(for: $1, locale: locale)) == .orderedAscending }
    }

    /// "United States" for "US"; the code itself if the system has no name.
    static func name(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    /// The device's region first, then countries already used, most used first.
    static func suggestions(used: [String?], locale: Locale = .current) -> [String] {
        var counts: [String: Int] = [:]
        for code in used.compactMap({ $0 }) { counts[code, default: 0] += 1 }
        let byUse = counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
        let device = deviceRegion(locale: locale).map { [$0] } ?? []
        return Array((device + byUse.filter { !device.contains($0) }).prefix(6))
    }

    /// The device's own region, if it is a country.
    static func deviceRegion(locale: Locale = .current) -> String? {
        guard let code = locale.region?.identifier, code.count == 2, !excluded.contains(code) else { return nil }
        return code
    }
}

// MARK: - Where it comes from

/// What Insights groups owned items by.
nonisolated enum OriginDimension: String, CaseIterable, Sendable {
    case brand, brandCountry, madeIn

    var title: String {
        switch self {
        case .brand: "Brand"
        case .brandCountry: "Brand country"
        case .madeIn: "Made in"
        }
    }

    /// For the footnote: "8 brand countries across 14 items".
    func countLabel(_ count: Int) -> String {
        switch self {
        case .brand: count == 1 ? "1 brand" : "\(count) brands"
        case .brandCountry: count == 1 ? "1 brand country" : "\(count) brand countries"
        case .madeIn: count == 1 ? "1 country of manufacture" : "\(count) countries of manufacture"
        }
    }
}

nonisolated enum OriginMetric: String, CaseIterable, Sendable {
    case items, value
}

/// One owned item as the origin chart sees it.
nonisolated struct OriginEntry: Equatable, Sendable {
    var brandName: String?
    var brandCountry: String?
    var madeIn: String?
    /// Value plus repairs; gifts count at their value.
    var valueCents: Int
}

nonisolated struct OriginSlice: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case named, notSet, other }

    var id: String
    var name: String
    var amount: Double
    var kind: Kind
    /// Share of the whole, 0…1.
    var share: Double
}

nonisolated struct OriginBreakdown: Equatable, Sendable {
    var slices: [OriginSlice]
    var total: Double
    /// Distinct named groups (not "Not set"/"No brand").
    var groupCount: Int
    var itemCount: Int

    static let maxSlices = 5

    init(entries: [OriginEntry], dimension: OriginDimension, metric: OriginMetric,
         countryName: (String) -> String = { Countries.name(for: $0) }) {
        var groups: [String: (name: String, amount: Double)] = [:]
        var unset = 0.0
        var hasUnset = false
        for entry in entries {
            let amount = metric == .items ? 1 : Double(entry.valueCents)
            let key: String?
            let name: String?
            switch dimension {
            case .brand:
                let trimmed = entry.brandName?.trimmingCharacters(in: .whitespacesAndNewlines)
                key = (trimmed?.isEmpty ?? true) ? nil : trimmed!.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                name = trimmed
            case .brandCountry:
                key = entry.brandName == nil ? nil : entry.brandCountry
                name = key.map(countryName)
            case .madeIn:
                key = entry.madeIn
                name = key.map(countryName)
            }
            if let key, let name {
                groups[key, default: (name, 0)].amount += amount
            } else {
                unset += amount
                hasUnset = true
            }
        }

        var all = groups.map { OriginSlice(id: $0.key, name: $0.value.name, amount: $0.value.amount, kind: .named, share: 0) }
        if hasUnset {
            all.append(OriginSlice(id: "notSet", name: dimension == .brand ? "No brand" : "Not set",
                                   amount: unset, kind: .notSet, share: 0))
        }
        // Biggest first; on a tie, named groups before "Not set", then by name.
        all.sort {
            if $0.amount != $1.amount { return $0.amount > $1.amount }
            if $0.kind != $1.kind { return $0.kind == .named }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        var shown = Array(all.prefix(Self.maxSlices))
        let rest = all.dropFirst(Self.maxSlices)
        if !rest.isEmpty {
            shown.append(OriginSlice(id: "other", name: "Other (\(rest.count))",
                                     amount: rest.reduce(0) { $0 + $1.amount }, kind: .other, share: 0))
        }
        let total = all.reduce(0) { $0 + $1.amount }
        slices = shown.map { slice in
            var slice = slice
            slice.share = total > 0 ? slice.amount / total : 0
            return slice
        }
        self.total = total
        groupCount = groups.count
        itemCount = entries.count
    }
}

extension Item {
    /// What the origin chart needs. Identical pieces count as one item.
    var originEntry: OriginEntry {
        OriginEntry(brandName: brand?.name, brandCountry: brand?.countryCode, madeIn: madeInCountryCode,
                    valueCents: stats.totalCostCents)
    }
}
