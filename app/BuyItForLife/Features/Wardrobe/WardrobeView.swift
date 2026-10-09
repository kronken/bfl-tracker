import SwiftData
import SwiftUI

struct WardrobeView: View {
    private enum Shelf: Hashable { case owned, sold }

    @Query(sort: \Item.purchaseDate, order: .reverse) private var items: [Item]

    @State private var shelf: Shelf = .owned
    @State private var category: ItemCategory?
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
                        options: [(Shelf.owned, "Owned · \(owned.count)"), (Shelf.sold, "Sold · \(sold.count)")],
                        selection: $shelf
                    )
                    categoryChips
                    grid
                }
            }
            .navigationTitle("Wardrobe")
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
        }
        .onChange(of: shelf) { category = nil }
        #if DEBUG
        // `-openItemForm new|edit` or `-openItemDetail YES` on launch, for screenshots.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "openItemForm") {
            case "new": showNewItem = true
            case "edit": editing = items.first
            default: break
            }
            if UserDefaults.standard.bool(forKey: "openItemDetail"), let first = items.max(by: { $0.stats.wearCount < $1.stats.wearCount }) {
                path = [first]
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
    private var onShelf: [Item] { shelf == .owned ? owned : sold }

    private var visible: [Item] {
        onShelf.filter { item in
            (category == nil || item.category == category) && matchesSearch(item)
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
        case .owned:
            "\(Money.format(cents: owned.reduce(0) { $0 + $1.purchasePriceCents })) in what you own"
        case .sold:
            "\(Money.format(cents: sold.reduce(0) { $0 + ($1.soldPriceCents ?? 0) })) back from sales"
        }
    }

    // MARK: Pieces

    /// "All" plus only the categories that have items on this shelf.
    private var categoryChips: some View {
        let present = ItemCategory.allCases.compactMap { category -> (ItemCategory, Int)? in
            let count = onShelf.count { $0.category == category }
            return count > 0 ? (category, count) : nil
        }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Chip(title: "All \(onShelf.count)", isOn: category == nil, height: 36) { category = nil }
                ForEach(present, id: \.0) { category, count in
                    Chip(title: "\(category.title) \(count)", isOn: self.category == category, height: 36) {
                        self.category = category
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
                }
            }
            .padding(.top, 4)
        }
    }

    private var emptyMessage: String {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty { return "No items match “\(search)”." }
        return shelf == .sold ? "Items you sell show up here." : "Nothing owned in this category."
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
                    if item.isSold { soldBadge.padding(8) }
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

    private var soldBadge: some View {
        Text("SOLD")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: .capsule)
            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
    }

    private func meta(_ stats: ItemStats) -> String {
        if let soldDate = item.soldDate {
            let price = Money.format(cents: item.soldPriceCents ?? 0)
            return "Sold \(price) · \(soldDate.formatted(.dateTime.month(.abbreviated).year()))"
        }
        let wears = stats.wearCount == 1 ? "1 wear" : "\(stats.wearCount) wears"
        return "\(wears) · \(Money.format(cents: item.purchasePriceCents))"
    }
}

#Preview {
    WardrobeView()
        .environment(AppSettings())
        .modelContainer(for: [Item.self, DayLog.self], inMemory: true)
        .preferredColorScheme(.dark)
}
