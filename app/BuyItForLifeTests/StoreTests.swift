import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

struct StoreBreakdownTests {
    private func entry(_ store: String?, gift: Bool = false, cents: Int = 100) -> OriginEntry {
        OriginEntry(brandName: nil, brandCountry: nil, madeIn: nil, valueCents: cents, storeName: store, isGift: gift)
    }

    @Test func groupsByStoreIgnoringCaseWithNoStoreBucket() {
        let b = OriginBreakdown(entries: [entry("Northside"), entry("northside "), entry("Kallio"), entry(nil)],
                                dimension: .store, metric: .items)
        #expect(b.slices.map(\.name) == ["Northside", "Kallio", "No store"])
        #expect(b.slices.map(\.amount) == [2, 1, 1])
        #expect(b.slices.last?.kind == .notSet)
        #expect(b.groupCount == 2)
        #expect(!b.hasGifts)
    }

    @Test func giftsGetTheirOwnSliceEvenWithAStore() {
        let b = OriginBreakdown(entries: [entry("Northside"), entry("Northside", gift: true), entry(nil, gift: true)],
                                dimension: .store, metric: .items)
        #expect(b.slices.map(\.name) == ["Gifts", "Northside"])
        #expect(b.slices.first?.kind == .gifts)
        #expect(b.hasGifts)
        #expect(b.groupCount == 1)
        #expect(b.itemCount == 3)
    }

    @Test func giftsOnlyMatterWhenGroupingByStore() {
        let b = OriginBreakdown(entries: [entry(nil, gift: true)], dimension: .brand, metric: .items)
        #expect(b.slices.map(\.name) == ["No brand"])
        #expect(!b.hasGifts)
    }

    @Test func giftsAreLighterGrey() {
        let b = OriginBreakdown(entries: [entry("A"), entry(nil), entry(nil, gift: true)], dimension: .store, metric: .items)
        let colors = OriginCard.colors(for: b.slices)
        #expect(colors["gifts"] == OriginCard.giftGrey)
        #expect(colors["notSet"] == OriginCard.grey)
        #expect(colors[b.slices.first { $0.kind == .named }!.id] == OriginCard.palette[0])
    }
}

@MainActor
struct StoreModelTests {
    private let context: ModelContext

    init() throws {
        let schema = Schema(AppSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func deletingAStoreKeepsItsItems() {
        let store = Store(name: "Northside Supply")
        context.insert(store)
        let boots = Item(name: "Boots", starter: .footwear, purchaseDate: .now, purchasePriceCents: 34_900)
        context.insert(boots)
        boots.store = store
        #expect(store.itemCount == 1)

        Store.delete(store, in: context)

        #expect(boots.store == nil)
        #expect(((try? context.fetch(FetchDescriptor<Item>())) ?? []).count == 1)
        #expect(((try? context.fetch(FetchDescriptor<Store>())) ?? []).isEmpty)
    }

    @Test func spentCountsPurchasesOnlyNotRepairsOrGifts() {
        let store = Store(name: "Northside Supply")
        context.insert(store)
        let boots = Item(name: "Boots", starter: .footwear, purchaseDate: .now, purchasePriceCents: 34_900)
        let scarf = Item(name: "Scarf", starter: .accessories, purchaseDate: .now, purchasePriceCents: 8_000)
        scarf.isGift = true
        context.insert(boots)
        context.insert(scarf)
        boots.store = store
        scarf.store = store
        let resole = Repair(name: "Resole", date: .now, priceCents: 12_000)
        context.insert(resole)
        resole.item = boots
        #expect(store.spentCents == 34_900)
    }

    @Test func originEntryCarriesTheStore() {
        let store = Store(name: "Kallio Vintage")
        context.insert(store)
        let coat = Item(name: "Coat", starter: .outerwear, purchaseDate: .now, purchasePriceCents: 20_000)
        context.insert(coat)
        coat.store = store
        #expect(coat.originEntry.storeName == "Kallio Vintage")
        #expect(!coat.originEntry.isGift)
    }
}
