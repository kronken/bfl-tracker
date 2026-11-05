import Foundation
import SwiftData

/// A clothing category: Footwear, Outerwear… The user can add, rename,
/// reorder and delete them, except Basics. Every property is optional or
/// defaulted, as required for CloudKit sync.
@Model
final class ClothingCategory {
    var id: UUID = UUID()
    /// Unique, ignoring case.
    var name: String = ""
    /// Order on Today, in Wardrobe and in the item form.
    var sortIndex: Int = 0
    /// Basics: exactly one, can't be deleted. Items of a deleted category move there.
    var isBuiltInBasics: Bool = false
    /// An asset ("Categories/footwear") or an SF Symbol ("hanger").
    var iconName: String = ClothingCategory.genericIcon
    /// The `StarterCategory` it was made from, so two devices that both
    /// seeded categories before syncing can be merged. nil for the user's own.
    var seedKey: String?
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ItemType.category) var types: [ItemType]? = []
    @Relationship(deleteRule: .nullify, inverse: \Item.category) var items: [Item]? = []

    init(name: String, sortIndex: Int, iconName: String = ClothingCategory.genericIcon, seedKey: String? = nil,
         isBuiltInBasics: Bool = false) {
        self.name = name
        self.sortIndex = sortIndex
        self.iconName = iconName
        self.seedKey = seedKey
        self.isBuiltInBasics = isBuiltInBasics
    }

    static let genericIcon = "hanger"
}

/// A kind of item inside a category, named in the plural: "Denim jackets".
@Model
final class ItemType {
    var id: UUID = UUID()
    /// Plural; unique within its category, ignoring case.
    var name: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var category: ClothingCategory?

    @Relationship(deleteRule: .nullify, inverse: \Item.itemType) var items: [Item]? = []

    init(name: String, sortIndex: Int) {
        self.name = name
        self.sortIndex = sortIndex
    }
}

// MARK: - Reading

extension ClothingCategory {
    /// Types in order.
    var sortedTypes: [ItemType] { (types ?? []).sorted(by: ItemType.isOrderedBefore) }

    var ownedItems: [Item] { (items ?? []).filter { !$0.isSold } }

    static func isOrderedBefore(_ a: ClothingCategory, _ b: ClothingCategory) -> Bool {
        if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
        return a.createdAt < b.createdAt
    }

    static func sorted(_ categories: [ClothingCategory]) -> [ClothingCategory] {
        categories.sorted(by: isOrderedBefore)
    }
}

extension ItemType {
    var ownedItems: [Item] { (items ?? []).filter { !$0.isSold } }

    static func isOrderedBefore(_ a: ItemType, _ b: ItemType) -> Bool {
        if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}

/// Name rules and suggestions for categories and types.
nonisolated enum CategoryRules {
    /// Whether `name` is free among `existing`: not empty, not used, ignoring
    /// case and surrounding spaces.
    static func isNameAvailable(_ name: String, among existing: [(id: UUID, name: String)], excluding id: UUID?) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !existing.contains { $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    static func isTaken(_ name: String, among existing: [(id: UUID, name: String)], excluding id: UUID?) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isNameAvailable(name, among: existing, excluding: id)
    }

    static let categorySuggestions = ["Knitwear", "Bags", "Workwear", "Sleepwear", "Swimwear", "Hats"]

    /// Type suggestions for the starter categories, by name.
    static let typeSuggestions: [String: [String]] = [
        "footwear": ["Leather boots", "Sneakers", "Sandals", "Loafers", "Dress shoes"],
        "outerwear": ["Denim jackets", "Waxed jackets", "Wool jackets", "Shell jackets", "Parkas", "Overshirts",
                      "Chore coats", "Fleeces"],
        "tops": ["T-shirts", "Shirts", "Knitwear", "Sweatshirts", "Polos"],
        "bottoms": ["Jeans", "Chinos", "Work pants", "Shorts"],
        "accessories": ["Watches", "Belts", "Wallets", "Bags", "Hats", "Scarves"],
        "basics": ["Underwear", "Socks", "Undershirts"],
    ]

    /// Suggestions not already taken.
    static func suggestions(_ all: [String], excluding existing: [String]) -> [String] {
        all.filter { suggestion in
            !existing.contains { $0.compare(suggestion, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
    }

    static func typeSuggestions(forCategoryNamed name: String) -> [String] {
        typeSuggestions[name.trimmingCharacters(in: .whitespaces).lowercased()] ?? []
    }
}

// MARK: - Setup and migration

extension ClothingCategory {
    private static let setupKey = "categoriesSetUp"

    /// Makes sure categories, Basics and Washing exist, merges copies that two
    /// devices made before syncing, and gives every item without a category
    /// the one matching its old stored category. Safe to run on every launch.
    @discardableResult
    static func ensureSetup(in context: ModelContext, defaults: UserDefaults = .standard) -> ClothingCategory {
        var categories = (try? context.fetch(FetchDescriptor<ClothingCategory>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []

        if categories.isEmpty && !defaults.bool(forKey: setupKey) {
            // First run: an upgrading user keeps every old category, a new
            // user gets the starter set.
            let seeds = items.isEmpty ? StarterCategory.newUserSet : StarterCategory.upgradeSet
            for (index, seed) in seeds.enumerated() {
                context.insert(make(seed, sortIndex: index))
            }
            categories = (try? context.fetch(FetchDescriptor<ClothingCategory>())) ?? []
        }

        categories = mergeDuplicates(categories, in: context)
        let basics = categories.first(where: \.isBuiltInBasics) ?? {
            let made = make(.underwear, sortIndex: (categories.map(\.sortIndex).max() ?? -1) + 1)
            context.insert(made)
            categories.append(made)
            return made
        }()

        // Items from before categories were records, or synced from an older version.
        for item in items where item.category == nil {
            let seed = StarterCategory(storedValue: item.categoryRaw)
            let match = categories.first { $0.seedKey == seed.rawValue } ?? {
                let made = make(seed, sortIndex: (categories.map(\.sortIndex).max() ?? -1) + 1)
                context.insert(made)
                categories.append(made)
                return made
            }()
            item.category = match
        }
        // A type always belongs to the item's category.
        for item in items where item.itemType != nil && item.itemType?.category?.id != item.category?.id {
            item.itemType = nil
        }

        CareAction.ensureWashing(in: context)
        try? context.save()
        defaults.set(true, forKey: setupKey)
        return basics
    }

    private static func make(_ seed: StarterCategory, sortIndex: Int) -> ClothingCategory {
        ClothingCategory(name: seed.title, sortIndex: sortIndex, iconName: seed.iconName, seedKey: seed.rawValue,
                         isBuiltInBasics: seed == .underwear)
    }

    /// Seeded categories that exist twice (same seed), and more than one
    /// Basics, are merged into the oldest.
    private static func mergeDuplicates(_ categories: [ClothingCategory], in context: ModelContext) -> [ClothingCategory] {
        var kept = categories
        let groups = Dictionary(grouping: categories.filter { $0.seedKey != nil || $0.isBuiltInBasics }) {
            $0.isBuiltInBasics ? "basics" : $0.seedKey!
        }
        for (_, group) in groups where group.count > 1 {
            let ordered = group.sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString }
            let keeper = ordered[0]
            for duplicate in ordered.dropFirst() {
                for item in duplicate.items ?? [] { item.category = keeper }
                for type in duplicate.types ?? [] { type.category = keeper }
                duplicate.types = []
                context.delete(duplicate)
                kept.removeAll { $0.id == duplicate.id }
            }
        }
        return kept
    }

    // MARK: Changes

    /// A new category at the end of the list, with the generic icon.
    static func create(name: String, in context: ModelContext) -> ClothingCategory {
        let all = (try? context.fetch(FetchDescriptor<ClothingCategory>())) ?? []
        let category = ClothingCategory(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                        sortIndex: (all.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(category)
        return category
    }

    /// Deletes a category: its items (owned and sold) move to Basics without
    /// a type, and its types go with it. Basics can't be deleted.
    static func delete(_ category: ClothingCategory, in context: ModelContext) {
        guard !category.isBuiltInBasics else { return }
        let basics = ensureSetup(in: context)
        for item in category.items ?? [] {
            item.itemType = nil
            item.category = basics
        }
        context.delete(category)
        try? context.save()
    }
}

extension ItemType {
    static func create(name: String, in category: ClothingCategory, context: ModelContext) -> ItemType {
        let type = ItemType(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            sortIndex: ((category.types ?? []).map(\.sortIndex).max() ?? -1) + 1)
        context.insert(type)
        type.category = category
        return type
    }

    /// Deletes a type; its items keep everything else.
    static func delete(_ type: ItemType, in context: ModelContext) {
        for item in type.items ?? [] { item.itemType = nil }
        context.delete(type)
        try? context.save()
    }
}
