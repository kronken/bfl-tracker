import SwiftData
import SwiftUI

/// Settings › Categories and types: reorder, add, open one to edit.
struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [ClothingCategory]
    @State private var showNew = false

    private var ordered: [ClothingCategory] { ClothingCategory.sorted(categories) }

    var body: some View {
        List {
            Section {
                ForEach(ordered) { category in
                    NavigationLink {
                        CategoryDetailView(category: category)
                    } label: {
                        row(category)
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("Tap Edit, then drag to reorder. Today shows the groups in this order. Basics is built in: items from a deleted category move there.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .padding(.top, 4)
            }
            .listRowBackground(Color.surface)
            .listRowSeparatorTint(.stroke)

            Section {
                DashedAddButton(title: "New category") { showNew = true }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New category", systemImage: "plus") { showNew = true }
                    .tint(.textPrimary)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                EditButton().tint(.textPrimary)
            }
        }
        .sheet(isPresented: $showNew) { CategorySheet() }
        .onAppear { ClothingCategory.ensureSetup(in: modelContext) }
    }

    private func row(_ category: ClothingCategory) -> some View {
        let types = category.sortedTypes.map(\.name)
        let count = category.ownedItems.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(category.name)
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                    if category.isBuiltInBasics { BuiltInTag() }
                }
                Text(types.isEmpty ? "No types yet" : types.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(types.isEmpty ? .textTertiary : .textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(count == 1 ? "1 item" : "\(count) items")
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = ordered
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() where category.sortIndex != index {
            category.sortIndex = index
        }
        try? modelContext.save()
    }
}

/// One category: its name, its types, delete.
struct CategoryDetailView: View {
    let category: ClothingCategory

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [ClothingCategory]

    @State private var name = ""
    @State private var editingType: ItemType?
    @State private var showNewType = false
    @State private var confirmDelete = false

    private var existing: [(id: UUID, name: String)] { categories.map { ($0.id, $0.name) } }
    private var isTaken: Bool { CategoryRules.isTaken(name, among: existing, excluding: category.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    FormRow(label: "Name") {
                        TextField("Name", text: $name, prompt: Text(category.name).foregroundStyle(.textTertiary))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(rename)
                    }
                    .foregroundStyle(.textPrimary)
                    .card(padding: nil)
                    if isTaken {
                        TakenNote()
                    } else if name.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("A category needs a name.")
                            .font(.footnote)
                            .foregroundStyle(.warning)
                            .padding(.horizontal, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Types")
                    let types = category.sortedTypes
                    if !types.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(types.enumerated()), id: \.element.id) { index, type in
                                if index > 0 { RowDivider() }
                                Button { editingType = type } label: { typeRow(type) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .card(padding: nil)
                        Text("Counts are owned items. Sold items keep their type for history.")
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                            .padding(.horizontal, 4)
                    }
                    DashedAddButton(title: "New type") { showNewType = true }
                        .padding(.top, 4)
                }

                if !category.isBuiltInBasics {
                    let count = (category.items ?? []).count
                    Button(count == 0 ? "Delete category"
                           : "Delete category · \(count == 1 ? "1 item moves" : "\(count) items move") to Basics",
                           role: .destructive) { confirmDelete = true }
                        .font(.body)
                        .foregroundStyle(.destructive)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(.appBackground)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .onAppear { name = category.name }
        .onDisappear(perform: rename)
        .sheet(item: $editingType) { type in TypeSheet(mode: .edit(type)) }
        .sheet(isPresented: $showNewType) { TypeSheet(mode: .new(category)) }
        .confirmationDialog("Delete \(category.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete category", role: .destructive) {
                ClothingCategory.delete(category, in: modelContext)
                dismiss()
            }
        } message: {
            Text("Its items move to Basics without a type, and its types are deleted.")
        }
    }

    private func typeRow(_ type: ItemType) -> some View {
        let names = type.ownedItems.map(\.name)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(type.name)
                    .font(.body)
                    .foregroundStyle(.textPrimary)
                Text(names.isEmpty ? "No items yet" : names.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(names.isEmpty ? .textTertiary : .textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(names.count)")
                .font(.number(.subheadline, weight: .regular))
                .foregroundStyle(.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(.rect)
    }

    /// Saves the name when it's valid; otherwise keeps the old one.
    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isTaken, trimmed != category.name else { return }
        category.name = trimmed
        try? modelContext.save()
    }
}
