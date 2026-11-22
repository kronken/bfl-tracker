import SwiftData
import SwiftUI

/// New store / Edit store. Opened from Settings › Stores or from the store
/// picker, where a new store is given to the item being edited.
struct StoreSheet: View {
    enum Mode {
        /// `name` pre-fills the field (what was typed in the search);
        /// `fromItem` shows the "The item gets this store" note.
        case new(name: String = "", fromItem: ItemImageContent? = nil)
        case edit(Store)
    }

    let mode: Mode
    /// Called with a newly created store after Save.
    var onCreate: (Store) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var stores: [Store]

    @State private var name = ""
    @State private var confirmDelete = false

    private var editing: Store? {
        if case .edit(let store) = mode { store } else { nil }
    }

    private var existing: [(id: UUID, name: String)] { stores.map { ($0.id, $0.name) } }

    private var nameIsTaken: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !BrandRules.isNameAvailable(name, excluding: editing?.id, in: existing)
    }

    var body: some View {
        EditSheet(title: editing == nil ? "New store" : "Edit store",
                  canSave: BrandRules.isNameAvailable(name, excluding: editing?.id, in: existing),
                  onSave: save) {
            if case .new(_, let item?) = mode {
                HStack(spacing: 12) {
                    ItemImageView(content: item, cornerRadius: Radius.thumb, iconSize: 18)
                        .frame(width: 40, height: 40)
                    Text("The item gets this store when you save.")
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .card(padding: nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                FormRow(label: "Name") {
                    TextField("Name", text: $name, prompt: Text("Store name").foregroundStyle(.textTertiary))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }
                .foregroundStyle(.textPrimary)
                .card(padding: nil)
                if nameIsTaken {
                    Text("You already have a store with this name.")
                        .font(.footnote)
                        .foregroundStyle(.warning)
                        .padding(.horizontal, 4)
                }
                Text("A shop, website or market. Anywhere you buy clothes.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 4)
            }

            if let editing {
                let count = editing.itemCount
                VStack(spacing: 4) {
                    Button("Delete store", role: .destructive) { confirmDelete = true }
                        .font(.body)
                        .foregroundStyle(.destructive)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    if count > 0 {
                        Text(Self.deleteNote(count))
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 24)
            }
        }
        .onAppear(perform: load)
        .storeDeleteConfirmation(editing, isPresented: $confirmDelete) { dismiss() }
    }

    static func deleteNote(_ count: Int) -> String {
        count == 1 ? "Its 1 item stays in your wardrobe without a store."
            : "Its \(count) items stay in your wardrobe without a store."
    }

    private func load() {
        switch mode {
        case .new(let prefill, _): name = prefill
        case .edit(let store): name = store.name
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing {
            editing.name = trimmed
        } else {
            let store = Store(name: trimmed)
            modelContext.insert(store)
            onCreate(store)
        }
        try? modelContext.save()
    }
}

extension Store {
    /// Deletes the store. Its items stay, without a store.
    static func delete(_ store: Store, in context: ModelContext) {
        for item in store.items ?? [] { item.store = nil }
        context.delete(store)
        try? context.save()
    }
}

extension View {
    /// "Delete <store>?" with the note about its items. Used by the store
    /// sheet and by swipe-to-delete in the list.
    func storeDeleteConfirmation(_ store: Store?, isPresented: Binding<Bool>, onDelete: @escaping () -> Void = {}) -> some View {
        modifier(StoreDeleteConfirmation(store: store, isPresented: isPresented, onDelete: onDelete))
    }
}

private struct StoreDeleteConfirmation: ViewModifier {
    var store: Store?
    @Binding var isPresented: Bool
    var onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete \(store?.name ?? "this store")?", isPresented: $isPresented,
                                   titleVisibility: .visible) {
            Button("Delete store", role: .destructive) {
                guard let store else { return }
                Store.delete(store, in: modelContext)
                onDelete()
            }
        } message: {
            if let count = store?.itemCount, count > 0 {
                Text(StoreSheet.deleteNote(count))
            }
        }
    }
}
