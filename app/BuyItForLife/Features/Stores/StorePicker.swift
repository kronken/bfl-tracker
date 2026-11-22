import SwiftData
import SwiftUI

/// Choose where an item was bought: search, "New store", "No store", or one
/// of the list. Choosing applies it and closes the sheet.
struct StorePicker: View {
    var selectedID: UUID?
    /// The item being edited, shown when a new store is created from here.
    var item: ItemImageContent?
    var onSelect: (Store?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var stores: [Store]

    @State private var query = ""
    @State private var showNew = false
    /// Set when a store was created; this sheet closes once that one has.
    @State private var created = false

    private var matches: [Store] {
        let sorted = Store.sorted(stores)
        guard !trimmedQuery.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedStandardContains(trimmedQuery) }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    SearchField(prompt: "Search stores", text: $query)
                    VStack(spacing: 0) {
                        Button { showNew = true } label: {
                            Label(trimmedQuery.isEmpty ? "New store" : "New store “\(trimmedQuery)”", systemImage: "plus")
                                .font(.body)
                                .foregroundStyle(.dataBlue)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        RowDivider()
                        row(title: "No store", subtitle: nil, isOn: selectedID == nil, muted: true) { choose(nil) }
                    }
                    .card(padding: nil)

                    if !matches.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, store in
                                if index > 0 { RowDivider() }
                                let count = store.itemCount
                                row(title: store.name, subtitle: count == 1 ? "1 item" : "\(count) items",
                                    isOn: store.id == selectedID, muted: false) { choose(store) }
                            }
                        }
                        .card(padding: nil)
                    } else if !stores.isEmpty {
                        Text("No store matches “\(trimmedQuery)”.")
                            .font(.rowDetail)
                            .foregroundStyle(.textSecondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(.appBackground)
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.textPrimary)
                }
            }
        }
        .presentationBackground(.appBackground)
        .sheet(isPresented: $showNew, onDismiss: { if created { dismiss() } }) {
            StoreSheet(mode: .new(name: trimmedQuery, fromItem: item)) { store in
                onSelect(store)
                created = true
            }
        }
    }

    private func choose(_ store: Store?) {
        onSelect(store)
        dismiss()
    }

    private func row(title: String, subtitle: String?, isOn: Bool, muted: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(muted ? .textSecondary : .textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
