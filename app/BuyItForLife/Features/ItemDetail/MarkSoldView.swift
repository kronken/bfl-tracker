import SwiftData
import SwiftUI

/// Half-height sheet for recording a sale. Wear history is kept.
struct MarkSoldView: View {
    let item: Item

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var priceText = ""
    @State private var soldDate = Date.now
    @FocusState private var priceFocused: Bool

    private var priceCents: Int { Money.parseCents(priceText) ?? 0 }

    /// The item's figures as they would be after the sale.
    private var afterSale: ItemStats {
        var stats = item.stats
        stats.soldDate = soldDate
        stats.soldPriceCents = priceCents
        return stats
    }

    var body: some View {
        let current = item.stats
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Mark as sold")
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
            }

            HStack(spacing: 12) {
                ItemImageView(content: item.thumbnailContent, cornerRadius: Radius.thumb, iconSize: 22)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                    Text("Cost \(Money.format(cents: current.totalCostCents)) · \(current.wearCount.formatted()) wears")
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                }
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Sold for").font(.body)
                    Spacer()
                    stepButton("minus", label: "Lower price by 10") {
                        priceText = Money.inputText(cents: max(0, priceCents - 1000))
                    }
                    .disabled(priceCents == 0)
                    TextField("Price", text: $priceText, prompt: Text(Money.format(cents: 0)).foregroundStyle(.textTertiary))
                        .font(.number(.title2))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 72, maxWidth: 120)
                        .fixedSize()
                        .focused($priceFocused)
                    stepButton("plus", label: "Raise price by 10") {
                        priceText = Money.inputText(cents: priceCents + 1000)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(minHeight: 64)
                RowDivider()
                HStack {
                    Text("Date sold").font(.body)
                    Spacer()
                    DatePicker("Date sold", selection: $soldDate, in: item.purchaseDate...Date.now, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
            .foregroundStyle(.textPrimary)
            .background(.surfaceRaised, in: .rect(cornerRadius: Radius.tile))

            VStack(alignment: .leading, spacing: 4) {
                Text("FINAL COST PER WEAR")
                    .font(.label)
                    .tracking(0.3)
                    .foregroundStyle(.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(costPerWear(afterSale))
                        .font(.heroNumber)
                        .foregroundStyle(.textPrimary)
                        .contentTransition(.numericText())
                    if current.wearCount > 0 {
                        Text(costPerWear(current))
                            .font(.rowDetail)
                            .strikethrough()
                            .foregroundStyle(.textSecondary)
                    }
                }
                Text("\(Money.format(cents: afterSale.netCostCents)) net over \(current.wearCount.formatted()) wears. Wear history is kept.")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)

            Button("Mark as sold", action: markSold)
                .buttonStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .presentationDetents([.height(640), .large])
        .presentationBackground(.surface)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { priceFocused = false }
            }
        }
        .onAppear {
            if soldDate < item.purchaseDate { soldDate = item.purchaseDate }
        }
    }

    private func costPerWear(_ stats: ItemStats) -> String {
        stats.costPerWearCents.map { Money.format(fractionalCents: $0) } ?? Money.format(cents: stats.netCostCents)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func markSold() {
        item.soldDate = soldDate
        item.soldPriceCents = priceCents
        try? modelContext.save()
        dismiss()
    }
}
