import SwiftData
import SwiftUI

/// New brand / Edit brand. Opened from Settings › Brands or from the brand
/// picker, where a new brand is given to the item being edited.
struct BrandSheet: View {
    enum Mode {
        /// `name` pre-fills the field (what was typed in the search);
        /// `fromItem` shows the "The item gets this brand" note.
        case new(name: String = "", fromItem: ItemImageContent? = nil)
        case edit(Brand)
    }

    let mode: Mode
    /// Called with a newly created brand after Save.
    var onCreate: (Brand) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var brands: [Brand]
    @Query private var items: [Item]

    @State private var name = ""
    @State private var countryCode: String?
    @State private var showCountries = false
    @State private var confirmDelete = false

    private var editing: Brand? {
        if case .edit(let brand) = mode { brand } else { nil }
    }

    private var existing: [(id: UUID, name: String)] { brands.map { ($0.id, $0.name) } }

    private var nameIsTaken: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !BrandRules.isNameAvailable(name, excluding: editing?.id, in: existing)
    }

    var body: some View {
        EditSheet(title: editing == nil ? "New brand" : "Edit brand",
                  canSave: BrandRules.isNameAvailable(name, excluding: editing?.id, in: existing),
                  onSave: save) {
            if case .new(_, let item?) = mode {
                HStack(spacing: 12) {
                    ItemImageView(content: item, cornerRadius: Radius.thumb, iconSize: 18)
                        .frame(width: 40, height: 40)
                    Text("The item gets this brand when you save.")
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .card(padding: nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    FormRow(label: "Name") {
                        TextField("Name", text: $name, prompt: Text("Brand name").foregroundStyle(.textTertiary))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }
                    RowDivider()
                    Button { showCountries = true } label: {
                        FormRow(label: "Country") {
                            HStack(spacing: 8) {
                                Text(countryCode.map { Countries.name(for: $0) } ?? "Choose")
                                    .foregroundStyle(countryCode == nil ? .textTertiary : .textPrimary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.textTertiary)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.textPrimary)
                .card(padding: nil)
                if nameIsTaken {
                    Text("You already have a brand with this name.")
                        .font(.footnote)
                        .foregroundStyle(.warning)
                        .padding(.horizontal, 4)
                }
                Text("Where the brand is based. Set where each item was made on the item itself.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 4)
            }

            if let editing {
                let count = editing.itemCount
                VStack(spacing: 4) {
                    Button("Delete brand", role: .destructive) { confirmDelete = true }
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
        .sheet(isPresented: $showCountries) {
            CountryPicker(title: "Country", selection: countryCode,
                          suggested: Countries.suggestions(used: brands.map(\.countryCode))) { countryCode = $0 }
        }
        .brandDeleteConfirmation(editing, isPresented: $confirmDelete) { dismiss() }
    }

    static func deleteNote(_ count: Int) -> String {
        count == 1 ? "Its 1 item stays in your wardrobe without a brand."
            : "Its \(count) items stay in your wardrobe without a brand."
    }

    private func load() {
        switch mode {
        case .new(let prefill, _): name = prefill
        case .edit(let brand):
            name = brand.name
            countryCode = brand.countryCode
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing {
            editing.name = trimmed
            editing.countryCode = countryCode
        } else {
            let brand = Brand(name: trimmed, countryCode: countryCode)
            modelContext.insert(brand)
            onCreate(brand)
        }
        try? modelContext.save()
    }
}

extension Brand {
    /// Deletes the brand. Its items stay, without a brand.
    static func delete(_ brand: Brand, in context: ModelContext) {
        for item in brand.items ?? [] { item.brand = nil }
        context.delete(brand)
        try? context.save()
    }
}

extension View {
    /// "Delete <brand>?" with the note about its items. Used by the brand
    /// sheet and by swipe-to-delete in the list.
    func brandDeleteConfirmation(_ brand: Brand?, isPresented: Binding<Bool>, onDelete: @escaping () -> Void = {}) -> some View {
        modifier(BrandDeleteConfirmation(brand: brand, isPresented: isPresented, onDelete: onDelete))
    }
}

private struct BrandDeleteConfirmation: ViewModifier {
    var brand: Brand?
    @Binding var isPresented: Bool
    var onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete \(brand?.name ?? "this brand")?", isPresented: $isPresented,
                                   titleVisibility: .visible) {
            Button("Delete brand", role: .destructive) {
                guard let brand else { return }
                Brand.delete(brand, in: modelContext)
                onDelete()
            }
        } message: {
            if let count = brand?.itemCount, count > 0 {
                Text(BrandSheet.deleteNote(count))
            }
        }
    }
}
