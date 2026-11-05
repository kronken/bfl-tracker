import SwiftData
import SwiftUI

/// Settings › Care actions.
struct CareActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var actions: [CareAction]
    @State private var editing: CareAction?
    @State private var showNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    let sorted = CareAction.sorted(actions)
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, action in
                        if index > 0 { RowDivider() }
                        Button { editing = action } label: { row(action) }
                            .buttonStyle(.plain)
                    }
                }
                .card(padding: nil)
                Text("Nothing is logged until you turn an action on for an item, in that item’s edit screen. Washing is built in and can’t be deleted.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 4)
                DashedAddButton(title: "New action") { showNew = true }
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(.appBackground)
        .navigationTitle("Care actions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New action", systemImage: "plus") { showNew = true }
                    .tint(.textPrimary)
            }
        }
        .sheet(item: $editing) { action in CareActionSheet(mode: .edit(action)) }
        .sheet(isPresented: $showNew) { CareActionSheet(mode: .new) }
        .onAppear { CareAction.ensureWashing(in: modelContext) }
    }

    private func row(_ action: CareAction) -> some View {
        let items = (action.items ?? []).count { !$0.isSold }
        let logs = (action.entries ?? []).count
        return HStack(spacing: 12) {
            Image(systemName: action.iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.textPrimary)
                .frame(width: 32, height: 32)
                .background(.surfaceRaised, in: .rect(cornerRadius: Radius.thumb))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(action.name)
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                    if action.isBuiltInWashing { BuiltInTag() }
                }
                Text("On \(items == 1 ? "1 item" : "\(items) items") · \(logs == 1 ? "1 log" : "\(logs) logs")")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .contentShape(.rect)
    }
}

/// New care action / Edit care action.
struct CareActionSheet: View {
    enum Mode {
        case new
        case edit(CareAction)
    }

    let mode: Mode
    var onCreate: (CareAction) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var actions: [CareAction]
    @State private var name = ""
    @State private var confirmDelete = false

    private var editing: CareAction? {
        if case .edit(let action) = mode { action } else { nil }
    }

    private var existing: [(id: UUID, name: String)] { actions.map { ($0.id, $0.name) } }

    private var title: String {
        guard let editing else { return "New care action" }
        return editing.isBuiltInWashing ? editing.name : "Edit care action"
    }

    var body: some View {
        EditSheet(title: title, canSave: CategoryRules.isNameAvailable(name, among: existing, excluding: editing?.id),
                  onSave: save) {
            VStack(alignment: .leading, spacing: 8) {
                NameField(name: $name, placeholder: "Waxing, oiling, re-proofing",
                          isTaken: CategoryRules.isTaken(name, among: existing, excluding: editing?.id))
                Text(editing == nil ? "Then turn it on for the items it applies to."
                     : editing!.isBuiltInWashing ? "Built in. You can rename it, but not delete it."
                     : "Renaming keeps every log.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 4)
            }

            if let editing {
                let names = (editing.items ?? []).filter { !$0.isSold }.map(\.name)
                VStack(alignment: .leading, spacing: 6) {
                    Text("TURNED ON FOR")
                        .font(.label)
                        .tracking(0.3)
                        .foregroundStyle(.textSecondary)
                    Text(names.isEmpty ? "No items yet" : names.joined(separator: ", "))
                        .font(.body)
                        .foregroundStyle(names.isEmpty ? .textTertiary : .textPrimary)
                }
                .card()

                if !editing.isBuiltInWashing {
                    let logs = (editing.entries ?? []).count
                    Button(logs == 0 ? "Delete action" : "Delete action and its \(logs == 1 ? "1 log" : "\(logs) logs")",
                           role: .destructive) { confirmDelete = true }
                        .font(.body)
                        .foregroundStyle(.destructive)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .padding(.top, 24)
                }
            }
        }
        .onAppear { if let editing { name = editing.name } }
        .confirmationDialog("Delete \(editing?.name ?? "this action")?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete action", role: .destructive) {
                guard let editing else { return }
                CareAction.delete(editing, in: modelContext)
                dismiss()
            }
        } message: {
            Text("Its logs are deleted too. The items stay.")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing {
            editing.name = trimmed
        } else {
            onCreate(CareAction.create(name: trimmed, in: modelContext))
        }
        try? modelContext.save()
    }
}
