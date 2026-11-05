import SwiftData
import SwiftUI

/// New category. Opened from Settings › Categories or the item form, where
/// the new category is picked for the item.
struct CategorySheet: View {
    var onCreate: (ClothingCategory) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [ClothingCategory]
    @State private var name = ""

    private var existing: [(id: UUID, name: String)] { categories.map { ($0.id, $0.name) } }

    var body: some View {
        EditSheet(title: "New category",
                  canSave: CategoryRules.isNameAvailable(name, among: existing, excluding: nil), onSave: save) {
            NameField(name: $name, placeholder: "Bags, Workwear",
                      isTaken: CategoryRules.isTaken(name, among: existing, excluding: nil))
            let suggestions = CategoryRules.suggestions(CategoryRules.categorySuggestions, excluding: categories.map(\.name))
            if !suggestions.isEmpty {
                SuggestionChips(suggestions: suggestions) { name = $0 }
            }
        }
    }

    private func save() {
        let created = ClothingCategory.create(name: name, in: modelContext)
        try? modelContext.save()
        onCreate(created)
    }
}

/// New type / Edit type.
struct TypeSheet: View {
    enum Mode {
        case new(ClothingCategory)
        case edit(ItemType)
    }

    let mode: Mode
    var onCreate: (ItemType) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmDelete = false

    private var category: ClothingCategory? {
        switch mode {
        case .new(let category): category
        case .edit(let type): type.category
        }
    }

    private var editing: ItemType? {
        if case .edit(let type) = mode { type } else { nil }
    }

    private var existing: [(id: UUID, name: String)] { (category?.types ?? []).map { ($0.id, $0.name) } }

    var body: some View {
        EditSheet(title: editing == nil ? "New type" : "Edit type",
                  canSave: CategoryRules.isNameAvailable(name, among: existing, excluding: editing?.id), onSave: save) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    FormRow(label: "Category") {
                        Text(category?.name ?? "")
                            .foregroundStyle(.textSecondary)
                    }
                    RowDivider()
                    FormRow(label: "Name") {
                        TextField("Name", text: $name, prompt: Text("Denim jackets").foregroundStyle(.textTertiary))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                    }
                }
                .foregroundStyle(.textPrimary)
                .card(padding: nil)
                if CategoryRules.isTaken(name, among: existing, excluding: editing?.id) {
                    TakenNote()
                }
                Text(editing == nil ? "Plural reads best in lists: Denim jackets, Leather boots."
                                    : "Deleting keeps the items; they just lose this type.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 4)
            }

            if editing == nil, let category {
                let suggestions = CategoryRules.suggestions(CategoryRules.typeSuggestions(forCategoryNamed: category.name),
                                                            excluding: (category.types ?? []).map(\.name))
                if !suggestions.isEmpty {
                    SuggestionChips(suggestions: suggestions) { name = $0 }
                }
            }

            if let editing {
                let names = editing.ownedItems.map(\.name)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ITEMS OF THIS TYPE")
                        .font(.label)
                        .tracking(0.3)
                        .foregroundStyle(.textSecondary)
                    Text(names.isEmpty ? "None yet" : names.joined(separator: ", "))
                        .font(.body)
                        .foregroundStyle(names.isEmpty ? .textTertiary : .textPrimary)
                }
                .card()

                Button("Delete type", role: .destructive) { confirmDelete = true }
                    .font(.body)
                    .foregroundStyle(.destructive)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.top, 24)
            }
        }
        .onAppear { if let editing { name = editing.name } }
        .confirmationDialog("Delete \(editing?.name ?? "this type")?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete type", role: .destructive) {
                guard let editing else { return }
                ItemType.delete(editing, in: modelContext)
                dismiss()
            }
        } message: {
            Text("The items stay; they just lose this type.")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing {
            editing.name = trimmed
        } else if let category {
            onCreate(ItemType.create(name: trimmed, in: category, context: modelContext))
        }
        try? modelContext.save()
    }
}

// MARK: - Shared pieces

/// A Name row in its own card, with the "Already exists" note.
struct NameField: View {
    @Binding var name: String
    var placeholder: String
    var isTaken: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormRow(label: "Name") {
                TextField("Name", text: $name, prompt: Text(placeholder).foregroundStyle(.textTertiary))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }
            .foregroundStyle(.textPrimary)
            .card(padding: nil)
            if isTaken { TakenNote() }
        }
    }
}

struct TakenNote: View {
    var body: some View {
        Text("Already exists")
            .font(.footnote)
            .foregroundStyle(.warning)
            .padding(.horizontal, 4)
    }
}

/// "SUGGESTIONS" chips that fill in a name.
struct SuggestionChips: View {
    var suggestions: [String]
    var onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Suggestions")
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Chip(title: suggestion, isOn: false) { onPick(suggestion) }
                }
            }
        }
    }
}

/// "BUILT IN" capsule next to a name.
struct BuiltInTag: View {
    var body: some View {
        Text("BUILT IN")
            .font(.caption2.weight(.bold))
            .tracking(0.3)
            .foregroundStyle(.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
    }
}
