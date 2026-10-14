import SwiftData
import SwiftUI

/// Add more pieces, retire some, or edit an entry in an identical-pieces log.
struct PieceEventSheet: View {
    enum Mode {
        case add, retire
        case edit(PieceEvent)
    }

    let item: Item
    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var quantity = 1
    @State private var date = Date.now
    @State private var priceText = ""
    @State private var reason = PieceEvent.retireReasons[0]
    @State private var isGift = false
    @State private var confirmDelete = false

    private var editing: PieceEvent? {
        if case .edit(let event) = mode { event } else { nil }
    }

    private var kind: PieceEvent.Kind {
        switch mode {
        case .add: .bought
        case .retire: .retired
        case .edit(let event): event.kind
        }
    }

    private var title: String {
        switch mode {
        case .add: "Add more"
        case .retire: "Retire"
        case .edit(let event): event.kind == .bought ? "Edit purchase" : "Edit retirement"
        }
    }

    /// Pieces that could be retired by this entry.
    private var retireLimit: Int {
        item.piecesInUse + (editing?.kind == .retired ? editing?.quantity ?? 0 : 0)
    }

    private var priceCents: Int? { Money.parseCents(priceText) }

    private var canSave: Bool {
        switch kind {
        case .bought: quantity >= 1 && priceCents != nil
        case .retired: quantity >= 1 && quantity <= retireLimit
        }
    }

    /// The only purchase can't be deleted: the set would have no pieces.
    private var canDelete: Bool {
        guard let editing else { return false }
        return editing.kind == .retired
            || (item.pieceEvents ?? []).filter { $0.kind == .bought }.count > 1
    }

    var body: some View {
        EditSheet(title: title, canSave: canSave, onSave: save) {
            SheetContextRow(item: item, summary:
                "\(item.piecesInUse) in use · \(Money.format(cents: item.stats.totalCostCents)) paid so far")

            VStack(spacing: 0) {
                FormRow(label: "How many") {
                    CountStepper(value: $quantity,
                                 range: kind == .retired ? 1...max(1, retireLimit) : 1...99,
                                 label: "How many")
                }
                RowDivider()
                FormRow(label: "Date") {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                }
                if kind == .bought {
                    RowDivider()
                    ToggleRow(label: "Gift", detail: "Received, not bought: not counted as spending", isOn: $isGift)
                    RowDivider()
                    FormRow(label: isGift ? "Value of all" : "Price for all", detail: eachText) {
                        TextField("Price for all", text: $priceText,
                                  prompt: Text(Money.format(cents: 0)).foregroundStyle(.textTertiary))
                            .font(.number(.body, weight: .regular))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .foregroundStyle(.textPrimary)
            .card(padding: nil)

            if kind == .retired {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Why")
                    FlowLayout(spacing: 8) {
                        ForEach(PieceEvent.retireReasons, id: \.self) { option in
                            Chip(title: option, isOn: reason == option) { reason = option }
                        }
                    }
                }
            }

            AfterThisCard(title: "After this", figures: afterFigures)

            Text(kind == .bought
                 ? "New pieces join the set. What you paid is added to the total cost."
                 : "Retired pieces still count towards what you paid. Past wears are kept.")
                .font(.footnote)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 4)

            if editing != nil {
                Button(kind == .bought ? "Delete purchase" : "Delete retirement", role: .destructive) {
                    confirmDelete = true
                }
                .font(.body)
                .foregroundStyle(canDelete ? .destructive : .textTertiary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .disabled(!canDelete)
                if !canDelete {
                    Text("The first purchase can’t be deleted while it’s the only one.")
                        .font(.footnote)
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var eachText: String? {
        guard let priceCents, priceCents > 0, quantity > 0 else { return nil }
        return "\(Money.format(fractionalCents: Double(priceCents) / Double(quantity))) each"
    }

    private var afterFigures: [(value: String, label: String)] {
        var stats = item.stats
        var inUse = item.piecesInUse
        let old = editing
        switch kind {
        case .bought:
            stats.purchasePriceCents += (priceCents ?? 0) - (old?.priceCents ?? 0)
            inUse += quantity - (old?.quantity ?? 0)
        case .retired:
            inUse -= quantity - (old?.quantity ?? 0)
        }
        let perWear = stats.costPerWearCents.map { Money.format(fractionalCents: $0) } ?? "–"
        return [("\(max(0, inUse))", "In use"), (Money.format(cents: stats.totalCostCents), "Total cost"),
                (perWear, "Per wear")]
    }

    // MARK: Saving

    private func load() {
        switch mode {
        case .add: quantity = 2
        case .retire: quantity = 1
        case .edit(let event):
            quantity = event.quantity
            date = event.date
            priceText = event.priceCents.map { Money.inputText(cents: $0) } ?? ""
            reason = event.reason ?? PieceEvent.retireReasons[0]
            isGift = event.isGift
        }
    }

    private func save() {
        let event = editing ?? {
            let new = PieceEvent(kind: kind, quantity: quantity, date: date)
            modelContext.insert(new)
            new.item = item
            return new
        }()
        event.quantity = quantity
        event.date = date
        event.priceCents = kind == .bought ? priceCents ?? 0 : nil
        event.isGift = kind == .bought && isGift
        event.reason = kind == .retired ? reason : nil
        item.syncFromPieceEvents()
        try? modelContext.save()
    }

    private func delete() {
        guard let editing, canDelete else { return }
        modelContext.delete(editing)
        item.syncFromPieceEvents()
        try? modelContext.save()
        dismiss()
    }
}
