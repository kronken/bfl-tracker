import SwiftData
import SwiftUI

struct WardrobeView: View {
    private enum Shelf: Hashable { case owned, toSell, sold }

    /// The chip row: everything, favorites, or one category.
    private enum Filter: Hashable {
        case all, favorites
        case category(ItemCategory)
    }

    @Environment(AppSettings.self) private var settings
    @Query(sort: \Item.purchaseDate, order: .reverse) private var items: [Item]

    @State private var shelf: Shelf = .owned
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var showNewItem = false
    @State private var editing: Item?
    @State private var path: [Item] = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            TabScreen {
                ScreenHeader(subtitle: items.isEmpty ? nil : summary, title: "Wardrobe") {
                    GlassIconButton(systemImage: "plus", accessibilityLabel: "Add item") { showNewItem = true }
                }

                if items.isEmpty {
                    emptyWardrobe
                } else {
                    SearchField(prompt: "Brand, model or category", text: $search)
                    SegmentedControl(
                        options: [
                            (Shelf.owned, "Owned · \(owned.count)"),
                            (Shelf.toSell, "To sell · \(toSell.count)"),
                            (Shelf.sold, "Sold · \(sold.count)"),
                        ],
                        selection: $shelf
                    )
                    if shelf == .toSell {
                        sellList
                    } else {
                        categoryChips
                        grid
                    }
                }
            }
            .navigationTitle("Wardrobe")
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
        }
        .onChange(of: shelf) { filter = .all }
        #if DEBUG
        // `-openItemForm new|edit` or `-openItemDetail` on launch, for screenshots.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "openItemForm") {
            case "new": showNewItem = true
            case "edit": editing = items.first
            default: break
            }
            // `-wardrobeShelf toSell|sold` opens another segment.
            switch UserDefaults.standard.string(forKey: "wardrobeShelf") {
            case "toSell": shelf = .toSell
            case "sold": shelf = .sold
            default: break
            }
            // `-openItemDetail YES` opens the most worn item; any other value
            // opens the first item whose name starts with it.
            if let wanted = UserDefaults.standard.string(forKey: "openItemDetail") {
                let match = wanted == "YES"
                    ? items.max(by: { $0.stats.wearCount < $1.stats.wearCount })
                    : items.first(where: { $0.name.hasPrefix(wanted) })
                if let match { path = [match] }
            }
        }
        #endif
        .sheet(isPresented: $showNewItem) {
            ItemFormView(mode: .new) { item in path = [item] }
        }
        .sheet(item: $editing) { item in
            ItemFormView(mode: .edit(item))
        }
    }

    // MARK: Data

    private var owned: [Item] { items.filter { !$0.isSold } }
    private var sold: [Item] { items.filter(\.isSold) }
    private var onShelf: [Item] { shelf == .sold ? sold : owned }

    /// Owned items unworn for the limit set in Settings, longest unworn first.
    private var toSell: [Item] {
        owned.filter { $0.isSellSuggestion(months: settings.sellSuggestionMonths) }
            .map { ($0, $0.monthsUnworn()) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var visible: [Item] {
        onShelf.filter { matches($0, filter) && matchesSearch($0) }
    }

    private func matches(_ item: Item, _ filter: Filter) -> Bool {
        switch filter {
        case .all: true
        case .favorites: item.isFavorite
        case .category(let category): item.category == category
        }
    }

    private func matchesSearch(_ item: Item) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return item.name.range(of: query, options: options) != nil
            || item.category.title.range(of: query, options: options) != nil
    }

    private var summary: String {
        switch shelf {
        case .owned where settings.hidesTotals:
            WardrobeCopy.ownedLine(items: owned.count, wears: owned.reduce(0) { $0 + $1.stats.wearCount })
        case .sold where settings.hidesTotals:
            sold.count == 1 ? "1 item sold" : "\(sold.count) items sold"
        case .owned:
            "\(Money.format(cents: owned.reduce(0) { $0 + $1.stats.totalCostCents })) in what you own"
        case .toSell:
            settings.sellSuggestionMonths == 12
                ? "Unworn for a year or more"
                : "Unworn for \(settings.sellSuggestionMonths) months or more"
        case .sold:
            "\(Money.format(cents: sold.reduce(0) { $0 + ($1.soldPriceCents ?? 0) })) back from sales"
        }
    }

    // MARK: Pieces

    /// "All", "Favorites" (owned only), then the categories that have items on
    /// this shelf.
    private var categoryChips: some View {
        let present = ItemCategory.allCases.compactMap { category -> (ItemCategory, Int)? in
            let count = onShelf.count { $0.category == category }
            return count > 0 ? (category, count) : nil
        }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Chip(title: "All \(onShelf.count)", isOn: filter == .all, height: 36) { filter = .all }
                if shelf == .owned {
                    Chip(title: "Favorites \(owned.count(where: \.isFavorite))", isOn: filter == .favorites,
                         height: 36) { filter = .favorites }
                }
                ForEach(present, id: \.0) { category, count in
                    Chip(title: "\(category.title) \(count)", isOn: filter == .category(category), height: 36) {
                        filter = .category(category)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }

    @ViewBuilder
    private var grid: some View {
        if visible.isEmpty {
            Text(emptyMessage)
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visible) { item in
                    NavigationLink(value: item) { WardrobeCard(item: item) }
                        .buttonStyle(.plain)
                        // Outside the link, so tapping the star doesn't open the item.
                        .overlay(alignment: .topTrailing) {
                            if !item.isSold { FavoriteStarButton(item: item).padding(8) }
                        }
                }
            }
            .padding(.top, 4)
        }
    }

    private var emptyMessage: String {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty { return "No items match “\(search)”." }
        if shelf == .sold { return "Items you sell show up here." }
        return filter == .favorites
            ? "No favorites yet. Tap the star on an item to add it."
            : "Nothing owned in this category."
    }

    // MARK: To sell

    private var sellList: some View {
        let list = toSell.filter(matchesSearch)
        let limit = settings.sellSuggestionMonths
        return VStack(alignment: .leading, spacing: 12) {
            Text("Not worn in \(limit == 12 ? "12 months" : "\(limit) months") or more. Change the limit in Settings.")
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 4)
            if list.isEmpty {
                Text(toSell.isEmpty ? "Nothing to sell. Everything has been worn recently." : "No items match “\(search)”.")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .card(padding: nil)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: item) { SellSuggestionRow(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .card(padding: nil)
            }
        }
        .padding(.top, 4)
    }

    private var emptyWardrobe: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your wardrobe is empty")
                .font(.rowTitle)
                .foregroundStyle(.textPrimary)
            Text("Add the things you wear most, like your boots, a jacket or your jeans.")
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
            Button("Add your first item") { showNewItem = true }
                .buttonStyle(.primary)
        }
        .card()
    }
}

/// One item in the Wardrobe grid.
struct WardrobeCard: View {
    let item: Item

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let stats = item.stats
        VStack(alignment: .leading, spacing: 10) {
            ItemImageView(content: item.thumbnailContent, cornerRadius: 18, iconSize: 32)
                .frame(height: 140)
                .overlay(alignment: .topLeading) {
                    if item.isSold {
                        PhotoTag(text: "SOLD").padding(8)
                    } else if item.boughtSecondHand {
                        PhotoTag(text: "SECOND-HAND").padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if item.isMultiPiece && !item.isSold { PieceCountBadge(count: item.piecesInUse).padding(8) }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.rowDetail.weight(.semibold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(stats.costPerWearCents.map { Money.format(fractionalCents: $0) } ?? "–")
                        .font(.number(.body))
                        .foregroundStyle(.textPrimary)
                    Text("/ wear")
                        .font(.footnote)
                        .foregroundStyle(.textSecondary)
                    if !item.isSold, stats.isPaidOff(targetCents: settings.paidOffTargetCents) {
                        Spacer(minLength: 4)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.positive)
                            .accessibilityLabel("Paid off")
                    }
                }
                .padding(.top, 4)
                Text(meta(stats))
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .padding(8)
        .card(padding: nil)
        .accessibilityElement(children: .combine)
    }

    private func meta(_ stats: ItemStats) -> String {
        if let soldDate = item.soldDate {
            let price = Money.format(cents: item.soldPriceCents ?? 0)
            return "Sold \(price) · \(soldDate.formatted(.dateTime.month(.abbreviated).year()))"
        }
        let wears = stats.wearCount == 1 ? "1 wear" : "\(stats.wearCount.formatted()) wears"
        if item.isMultiPiece {
            return item.piecesInUse == 0 ? "All retired · \(wears)" : "\(item.piecesInUse) in use · \(wears)"
        }
        if item.isInactive { return "Inactive · \(wears)" }
        if item.isDailyDriver { return "Daily driver · \(wears)" }
        return "\(wears) · \(Money.format(cents: stats.totalCostCents))"
    }
}

/// Feel-good wording for the Wardrobe heading.
nonisolated enum WardrobeCopy {
    /// "14 items, worn 7,400 times".
    static func ownedLine(items: Int, wears: Int) -> String {
        let itemText = items == 1 ? "1 item" : "\(items.formatted()) items"
        let wearText = wears == 1 ? "worn once" : "worn \(wears.formatted()) times"
        return "\(itemText), \(wearText)"
    }
}

/// A small dark capsule over a photo's corner: "SOLD", "SECOND-HAND".
struct PhotoTag: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: .capsule)
            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
    }
}

/// The star in a Wardrobe card's corner: toggles the favorite without opening
/// the item. 44pt to tap, 32pt to see.
struct FavoriteStarButton: View {
    let item: Item

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            withAnimation(.snappy) { item.isFavorite.toggle() }
            try? modelContext.save()
        } label: {
            Image(systemName: item.isFavorite ? "star.fill" : "star")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.isFavorite ? .textPrimary : .textSecondary)
                .frame(width: 32, height: 32)
                .background(.black.opacity(item.isFavorite ? 0.55 : 0.35), in: .circle)
                .overlay { Circle().strokeBorder(.stroke, lineWidth: 1) }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.isFavorite)
        .accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites")
    }
}

/// One row under To sell.
struct SellSuggestionRow: View {
    let item: Item

    var body: some View {
        let stats = item.stats
        let months = item.monthsUnworn()
        HStack(spacing: 12) {
            ItemImageView(content: item.thumbnailContent, cornerRadius: Radius.tile, iconSize: 24)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text(stats.lastWornDayKey == nil
                     ? "Not worn in \(months) months"
                     : "Last worn \(months) months ago")
                    .font(.rowDetail)
                    .foregroundStyle(.warning)
                Text(meta(stats))
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func meta(_ stats: ItemStats) -> String {
        var parts = [stats.wearCount == 1 ? "1 wear" : "\(stats.wearCount) wears"]
        if let cpw = stats.costPerWearCents { parts.append("\(Money.format(fractionalCents: cpw)) / wear") }
        parts.append("paid \(Money.format(cents: stats.totalCostCents))")
        return parts.joined(separator: " · ")
    }
}

#Preview {
    WardrobeView()
        .environment(AppSettings())
        .modelContainer(for: [Item.self, DayLog.self], inMemory: true)
        .preferredColorScheme(.dark)
}
