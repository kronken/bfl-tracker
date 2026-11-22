import SwiftData
import SwiftUI

/// Settings › Stores: every store with its item count and what was spent there.
struct StoresView: View {
    @Environment(AppSettings.self) private var settings
    @Query private var stores: [Store]

    @State private var editing: Store?
    @State private var showNew = false
    @State private var deleting: Store?

    var body: some View {
        List {
            Section {
                Text("Where you buy your clothes.")
                    .font(.body)
                    .foregroundStyle(.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            Section {
                Button { showNew = true } label: {
                    Label("Add store", systemImage: "plus")
                        .font(.body)
                        .foregroundStyle(.dataBlue)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.surface)

            if stores.isEmpty {
                Section {
                    Text("No stores yet. Add one here or when editing an item.")
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
            } else {
                Section {
                    ForEach(Store.sorted(stores)) { store in
                        Button { editing = store } label: { row(store) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { deleting = store }
                            }
                    }
                }
                .listRowBackground(Color.surface)
                .listRowSeparatorTint(.stroke)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Stores")
        .navigationBarTitleDisplayMode(.large)
        .toolbarVisibility(.visible, for: .navigationBar)
        .sheet(item: $editing) { store in
            StoreSheet(mode: .edit(store))
        }
        .sheet(isPresented: $showNew) {
            StoreSheet(mode: .new())
        }
        .storeDeleteConfirmation(deleting, isPresented: Binding(get: { deleting != nil },
                                                               set: { if !$0 { deleting = nil } }))
        #if DEBUG
        // `-openStores new|<name>` on launch opens that sheet, for screenshots.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "openStores") {
            case "new": showNew = true
            case let name?: editing = stores.first { $0.name == name }
            case nil: break
            }
        }
        #endif
    }

    private func row(_ store: Store) -> some View {
        let count = store.itemCount
        var detail = count == 1 ? "1 item" : "\(count) items"
        // Feel-good mode never shows money.
        if !settings.hidesTotals, store.spentCents > 0 {
            detail += " · \(Money.format(cents: store.spentCents)) spent"
        }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.name)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.textTertiary)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}
