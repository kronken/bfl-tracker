import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

struct OriginBreakdownTests {
    private let names = ["US": "United States", "GB": "United Kingdom", "JP": "Japan", "IT": "Italy",
                         "FR": "France", "CH": "Switzerland", "IE": "Ireland"]

    private func breakdown(_ entries: [OriginEntry], _ dimension: OriginDimension, _ metric: OriginMetric) -> OriginBreakdown {
        OriginBreakdown(entries: entries, dimension: dimension, metric: metric) { names[$0] ?? $0 }
    }

    private func entry(_ brand: String?, _ country: String? = nil, madeIn: String? = nil, cents: Int = 100) -> OriginEntry {
        OriginEntry(brandName: brand, brandCountry: country, madeIn: madeIn, valueCents: cents)
    }

    @Test func groupsByBrandIgnoringCaseWithNoBrandBucket() {
        let b = breakdown([entry("Red Wing"), entry("red wing"), entry("Filson"), entry(nil)], .brand, .items)
        #expect(b.slices.map(\.name) == ["Red Wing", "Filson", "No brand"])
        #expect(b.slices.map(\.amount) == [2, 1, 1])
        #expect(b.slices.last?.kind == .notSet)
        #expect(b.groupCount == 2)
        #expect(b.itemCount == 4)
    }

    @Test func brandCountryNeedsABrandWithACountry() {
        let b = breakdown([entry("Red Wing", "US"), entry("Lee", "US"), entry("Nameless"), entry(nil, "US")],
                          .brandCountry, .items)
        #expect(b.slices.map(\.name) == ["United States", "Not set"])
        #expect(b.slices.map(\.amount) == [2, 2])
    }

    @Test func madeInUsesTheItemsOwnCountry() {
        let b = breakdown([entry("Levi’s", "US", madeIn: "JP"), entry(nil, madeIn: "JP"), entry("Lee", "US")],
                          .madeIn, .items)
        #expect(b.slices.map(\.name) == ["Japan", "Not set"])
    }

    @Test func valueSumsTotalCostAndSharesAddUp() {
        let b = breakdown([entry("A", "US", cents: 30_000), entry("B", "GB", cents: 10_000)], .brandCountry, .value)
        #expect(b.total == 40_000)
        #expect(b.slices.map(\.share) == [0.75, 0.25])
    }

    @Test func topFiveThenOtherLast() {
        let codes = ["US", "US", "US", "GB", "GB", "JP", "IT", "FR", "CH", "IE"]
        let b = breakdown(codes.enumerated().map { entry("Brand \($0.offset)", $0.element) }, .brandCountry, .items)
        #expect(b.slices.count == 6)
        #expect(b.slices.prefix(2).map(\.name) == ["United States", "United Kingdom"])
        #expect(b.slices.last?.name == "Other (2)")
        #expect(b.slices.last?.kind == .other)
        #expect(b.slices.last?.amount == 2)
        #expect(b.groupCount == 7)
    }

    @Test func coloursSkipGreySlices() {
        let b = breakdown([entry(nil), entry(nil), entry("A"), entry("B")], .brand, .items)
        let colors = OriginCard.colors(for: b.slices)
        #expect(colors["notSet"] == OriginCard.grey)
        #expect(colors[b.slices[1].id] == OriginCard.palette[0])
        #expect(colors[b.slices[2].id] == OriginCard.palette[1])
    }
}

struct BrandRulesTests {
    private let brands: [(id: UUID, name: String)] = [(UUID(), "A.P.C."), (UUID(), "Inis Meáin")]

    @Test func namesAreUniqueIgnoringCaseAndAccents() {
        #expect(!BrandRules.isNameAvailable(" a.p.c. ", excluding: nil, in: brands))
        #expect(!BrandRules.isNameAvailable("Inis Meain", excluding: nil, in: brands))
        #expect(BrandRules.isNameAvailable("A.P.C.", excluding: brands[0].id, in: brands))
        #expect(BrandRules.isNameAvailable("Filson", excluding: nil, in: brands))
        #expect(!BrandRules.isNameAvailable("   ", excluding: nil, in: brands))
    }

    @Test func emptySizeIsStoredAsNil() {
        #expect(BrandRules.cleaned("  ") == nil)
        #expect(BrandRules.cleaned(" W32 L34 ") == "W32 L34")
    }

    @Test func countryListHasCountriesOnly() {
        let all = Countries.all(locale: Locale(identifier: "en_US"))
        #expect(all.contains("FI") && all.contains("US"))
        #expect(!all.contains("EU") && !all.contains("001"))
        #expect(Countries.name(for: "GB", locale: Locale(identifier: "en_US")) == "United Kingdom")
    }

    @Test func suggestionsStartWithTheDeviceRegion() {
        let locale = Locale(identifier: "fi_FI")
        #expect(Countries.suggestions(used: ["US", "JP", "US", nil, "FI"], locale: locale) == ["FI", "US", "JP"])
    }
}

@MainActor
struct BrandModelTests {
    private let context: ModelContext

    init() throws {
        let schema = Schema(AppSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func deletingABrandKeepsItsItems() {
        let brand = Brand(name: "Red Wing", countryCode: "US")
        context.insert(brand)
        let boots = Item(name: "Boots", starter: .footwear, purchaseDate: .now, purchasePriceCents: 34_900)
        context.insert(boots)
        boots.brand = brand
        #expect(brand.itemCount == 1)

        Brand.delete(brand, in: context)

        #expect(boots.brand == nil)
        #expect(((try? context.fetch(FetchDescriptor<Item>())) ?? []).count == 1)
        #expect(((try? context.fetch(FetchDescriptor<Brand>())) ?? []).isEmpty)
    }

    @Test func originEntryUsesTotalCostAndGiftValue() {
        let brand = Brand(name: "Hamilton", countryCode: "CH")
        context.insert(brand)
        let watch = Item(name: "Watch", starter: .accessories, purchaseDate: .now, purchasePriceCents: 49_500)
        watch.isGift = true
        context.insert(watch)
        watch.brand = brand
        let service = Repair(name: "Service", date: .now, priceCents: 10_000)
        context.insert(service)
        service.item = watch
        #expect(watch.originEntry == OriginEntry(brandName: "Hamilton", brandCountry: "CH", madeIn: nil, valueCents: 59_500,
                                                storeName: nil, isGift: true))
    }
}

struct ItemTextTests {
    @Test func taglineJoinsWhatIsSet() {
        #expect(ItemText.tagline(brand: "Sunspel", size: "M") == "Sunspel · M")
        #expect(ItemText.tagline(brand: "Hamilton", size: nil) == "Hamilton")
        #expect(ItemText.tagline(brand: nil, size: "W32 L34") == "W32 L34")
        #expect(ItemText.tagline(brand: nil, size: nil) == nil)
        #expect(ItemText.tagline(brand: " ", size: "") == nil)
    }

    @Test func spokenTaglineNamesTheSize() {
        #expect(ItemText.spokenTagline(brand: "Red Wing", size: "9.5 D") == "Red Wing, size 9.5 D")
        #expect(ItemText.spokenTagline(brand: nil, size: nil) == nil)
    }

    @Test func listNameDropsALeadingBrand() {
        #expect(ItemText.listName("Red Wing Iron Ranger 8111", brand: "Red Wing") == "Iron Ranger 8111")
        #expect(ItemText.listName("levi’s 501 shrink-to-fit", brand: "Levi’s") == "501 shrink-to-fit")
        #expect(ItemText.listName("sunspel linen shirt", brand: "Sunspel") == "Linen shirt")
        // Not a prefix followed by a space, or nothing left: unchanged.
        #expect(ItemText.listName("Leeds scarf", brand: "Lee") == "Leeds scarf")
        #expect(ItemText.listName("Hamilton", brand: "Hamilton") == "Hamilton")
        #expect(ItemText.listName("Iron Ranger", brand: nil) == "Iron Ranger")
    }
}
