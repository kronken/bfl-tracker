import SwiftData
import SwiftUI

/// New repair, or editing one (with Delete). Its price adds to the item's
/// total cost; the summary shows the effect as you type.
struct RepairSheet: View {
    let item: Item
    /// nil for a new repair.
    var repair: Repair?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var details = ""
    @State private var date = Date.now
    @State private var priceText = ""
    @State private var confirmDelete = false

    private var priceCents: Int? { Money.parseCents(priceText) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && priceCents != nil
    }

    var body: some View {
        EditSheet(title: repair == nil ? "New repair" : "Edit repair", canSave: canSave, onSave: save) {
            SheetContextRow(item: item, summary: contextSummary)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Repair")
                VStack(spacing: 0) {
                    FormRow(label: "Name") {
                        TextField("Name", text: $name,
                                  prompt: Text("Resole, new zip, reweave").foregroundStyle(.textTertiary))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.sentences)
                    }
                    RowDivider()
                    FormRow(label: "Date") {
                        DatePicker("Date", selection: $date, in: item.purchaseDate...Date.now, displayedComponents: .date)
                            .labelsHidden()
                    }
                    RowDivider()
                    FormRow(label: "Price") {
                        TextField("Price", text: $priceText,
                                  prompt: Text(Money.format(cents: 0)).foregroundStyle(.textTertiary))
                            .font(.number(.body, weight: .regular))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .foregroundStyle(.textPrimary)
                .card(padding: nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Description")
                TextField("Description", text: $details,
                          prompt: Text("What was done, and by whom").foregroundStyle(.textTertiary), axis: .vertical)
                    .lineLimit(3...8)
                    .foregroundStyle(.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .card(padding: nil)
            }

            AfterThisCard(title: "After this repair", figures: afterFigures)

            if repair != nil {
                Button("Delete repair", role: .destructive) { confirmDelete = true }
                    .font(.body)
                    .foregroundStyle(.destructive)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Delete this repair?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete repair", role: .destructive, action: delete)
        } message: {
            Text("Its price is taken off the item’s total cost.")
        }
    }

    // MARK: Figures

    private var contextSummary: String {
        let paid = "Paid \(Money.format(cents: item.purchasePriceCents))"
        let repairs = item.repairs ?? []
        guard !repairs.isEmpty else { return "\(paid) · no repairs yet" }
        let count = repairs.count == 1 ? "1 repair" : "\(repairs.count) repairs"
        if repair != nil { return "\(paid) · \(count)" }
        return "\(paid) · \(count) so far, \(Money.format(cents: item.stats.repairsCents))"
    }

    private var afterFigures: [(value: String, label: String)] {
        var stats = item.stats
        stats.repairsCents += (priceCents ?? 0) - (repair?.priceCents ?? 0)
        let perWear = stats.costPerWearCents.map { Money.format(fractionalCents: $0) } ?? "–"
        return [(Money.format(cents: stats.totalCostCents), "Total cost"), (perWear, "Cost per wear")]
    }

    // MARK: Saving

    private func load() {
        guard let repair else { return }
        name = repair.name
        details = repair.details
        date = repair.date
        priceText = Money.inputText(cents: repair.priceCents)
    }

    private func save() {
        guard let priceCents else { return }
        let target = repair ?? {
            let new = Repair(name: "", date: date, priceCents: 0)
            modelContext.insert(new)
            new.item = item
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        target.date = date
        target.priceCents = priceCents
        try? modelContext.save()
    }

    private func delete() {
        guard let repair else { return }
        modelContext.delete(repair)
        try? modelContext.save()
        dismiss()
    }
}
