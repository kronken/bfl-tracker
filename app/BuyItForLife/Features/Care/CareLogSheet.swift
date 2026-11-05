import SwiftData
import SwiftUI

/// Log care / Edit care for one item.
struct CareLogSheet: View {
    enum Mode {
        case new(preselected: CareAction?)
        case edit(CareLogEntry)
    }

    let item: Item
    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var actionID: UUID?
    @State private var date = Date.now
    @State private var note = ""

    private var editing: CareLogEntry? {
        if case .edit(let entry) = mode { entry } else { nil }
    }

    /// The item's actions, plus an entry's own action if it was turned off since.
    private var choices: [CareAction] {
        var actions = item.enabledActions
        if let own = editing?.action, !actions.contains(where: { $0.id == own.id }) { actions.append(own) }
        return actions
    }

    /// "Oiling 5 times · Waxing 3 times".
    private var summary: String {
        let parts = item.enabledActions.map { action in
            let count = item.careSummary(for: action).count
            return "\(action.name) \(count == 1 ? "1 time" : "\(count) times")"
        }
        return parts.isEmpty ? "No care actions turned on" : parts.joined(separator: " · ")
    }

    var body: some View {
        EditSheet(title: editing == nil ? "Log care" : "Edit care", canSave: actionID != nil, onSave: save) {
            SheetContextRow(item: item, summary: summary)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Action")
                FlowLayout(spacing: 8) {
                    ForEach(choices) { action in
                        OccasionChip(title: action.name, isOn: actionID == action.id) { actionID = action.id }
                    }
                }
                Text("Only actions turned on for this item.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 4)
            }

            FormRow(label: "Date") {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden()
            }
            .foregroundStyle(.textPrimary)
            .card(padding: nil)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Note · optional")
                TextField("Note", text: $note, prompt: Text("Product used, how it went").foregroundStyle(.textTertiary),
                          axis: .vertical)
                    .lineLimit(3...8)
                    .foregroundStyle(.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .card(padding: nil)
            }

            if editing != nil {
                Button("Delete entry", role: .destructive, action: delete)
                    .font(.body)
                    .foregroundStyle(.destructive)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.top, 16)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        switch mode {
        case .new(let preselected):
            actionID = preselected?.id ?? choices.first?.id
        case .edit(let entry):
            actionID = entry.action?.id
            date = entry.date
            note = entry.note ?? ""
        }
    }

    private func save() {
        guard let action = choices.first(where: { $0.id == actionID }) else { return }
        let day = Calendar.current.startOfDay(for: date)
        let cleaned = BrandRules.cleaned(note)
        if let editing {
            editing.action = action
            editing.date = day
            editing.note = cleaned
        } else {
            let entry = CareLogEntry(date: day, note: cleaned)
            modelContext.insert(entry)
            entry.item = item
            entry.action = action
        }
        try? modelContext.save()
    }

    private func delete() {
        guard let editing else { return }
        modelContext.delete(editing)
        try? modelContext.save()
        dismiss()
    }
}

/// The item screen's Care section: each turned-on action with a Log button,
/// then the most recent log entries.
struct CareSection: View {
    let item: Item
    var onChooseActions: () -> Void

    @State private var sheet: SheetTarget?

    private enum SheetTarget: Identifiable {
        case log(CareAction)
        case edit(CareLogEntry)

        var id: String {
            switch self {
            case .log(let action): "log-\(action.id)"
            case .edit(let entry): "edit-\(entry.id)"
            }
        }
    }

    static let shownEntries = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Care")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Button("Choose actions", action: onChooseActions)
                    .font(.rowDetail)
                    .foregroundStyle(.dataBlue)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 4)

            let actions = item.enabledActions
            if !actions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        if index > 0 { RowDivider() }
                        actionRow(action)
                    }
                }
                .card(padding: nil)
            }

            let log = item.sortedCareLog
            if !log.isEmpty {
                SectionLabel("Care log")
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(Array(log.prefix(Self.shownEntries).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider() }
                        Button { sheet = .edit(entry) } label: { CareLogRow(entry: entry) }
                            .buttonStyle(.plain)
                    }
                    if log.count > Self.shownEntries {
                        RowDivider()
                        NavigationLink {
                            CareLogListView(item: item)
                        } label: {
                            Text("Show all \(log.count)")
                                .font(.rowDetail.weight(.medium))
                                .foregroundStyle(.dataBlue)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: nil)
            }
        }
        .sheet(item: $sheet) { target in
            switch target {
            case .log(let action): CareLogSheet(item: item, mode: .new(preselected: action))
            case .edit(let entry): CareLogSheet(item: item, mode: .edit(entry))
            }
        }
    }

    private func actionRow(_ action: CareAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.textPrimary)
                .frame(width: 32, height: 32)
                .background(.surfaceRaised, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.name)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Text(item.careSummary(for: action).subtitle())
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { sheet = .log(action) } label: {
                Label("Log", systemImage: "plus")
                    .font(.rowDetail.weight(.semibold))
                    .foregroundStyle(.onAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(.accentGold, in: .capsule)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log \(action.name.lowercased())")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
    }
}

/// One log entry: action, then date and note.
struct CareLogRow: View {
    let entry: CareLogEntry

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.textTertiary)
                .frame(width: 6, height: 6)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.action?.name ?? "Care")
                    .font(.body)
                    .foregroundStyle(.textPrimary)
                Text([entry.date.formatted(date: .abbreviated, time: .omitted), entry.note].compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(.rect)
    }
}

/// Every log entry for an item.
struct CareLogListView: View {
    let item: Item
    @State private var editing: CareLogEntry?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                let log = item.sortedCareLog
                ForEach(Array(log.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowDivider() }
                    Button { editing = entry } label: { CareLogRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
            .card(padding: nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.appBackground)
        .navigationTitle("Care log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .sheet(item: $editing) { entry in CareLogSheet(item: item, mode: .edit(entry)) }
    }
}
