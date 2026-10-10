import SwiftData
import SwiftUI

/// The New item / Edit item sheet.
struct ItemFormView: View {
    enum Mode {
        case new
        case edit(Item)
    }

    let mode: Mode
    /// Called with the saved item after Add or Save.
    var onSave: (Item) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draft: ItemDraft
    @State private var isProcessingPhoto = false
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, price, wears, notes, soldPrice }

    private let initialDraft: ItemDraft

    init(mode: Mode, onSave: @escaping (Item) -> Void = { _ in }) {
        self.mode = mode
        self.onSave = onSave
        let draft: ItemDraft = switch mode {
        case .new: ItemDraft()
        case .edit(let item): ItemDraft(item: item)
        }
        _draft = State(initialValue: draft)
        initialDraft = draft
    }

    private var isNew: Bool {
        if case .new = mode { true } else { false }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PhotoSection(
                        photo: $draft.photo,
                        isProcessing: $isProcessingPhoto,
                        name: draft.name,
                        category: draft.category
                    )
                    itemSection
                    categorySection
                    weatherSection
                    notesSection
                    if draft.isSold { soldSection }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.appBackground)
            .navigationTitle(isNew ? "New item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { Task { await save() } }
                        .buttonStyle(.glassProminent)
                        .disabled(!draft.isValid || isProcessingPhoto || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .presentationBackground(.appBackground)
        .interactiveDismissDisabled(draft != initialDraft)
    }

    // MARK: Sections

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Item")
            VStack(spacing: 0) {
                FormRow(label: "Name") {
                    TextField("Name", text: $draft.name, prompt: Text("Brand and model").foregroundStyle(.textTertiary))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                }
                RowDivider()
                FormRow(label: "Price") {
                    priceField($draft.priceText, field: .price)
                }
                RowDivider()
                FormRow(label: "Bought") {
                    DatePicker("Bought", selection: $draft.purchaseDate, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                }
                RowDivider()
                ToggleRow(label: "Bought second-hand", detail: "Pre-owned, vintage or swapped",
                          isOn: $draft.boughtSecondHand)
                RowDivider()
                FormRow(label: "Worn so far", detail: "A rough guess is fine") {
                    wearCounter
                }
                RowDivider()
                ToggleRow(label: "Favorite", detail: "Listed first on Today among similar items",
                          isOn: $draft.isFavorite)
                RowDivider()
                ToggleRow(label: "Daily driver", detail: "Pre-selected every day, any weather",
                          isOn: $draft.isDailyDriver)
                RowDivider()
                ToggleRow(label: "Inactive", detail: "Not suggested on Today. Still in Wardrobe and Insights.",
                          isOn: $draft.isInactive)
            }
            .card(padding: nil)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Category")
            FlowLayout(spacing: 8) {
                ForEach(ItemCategory.allCases) { category in
                    Chip(title: category.title, isOn: draft.category == category) {
                        draft.category = category
                    }
                }
            }
        }
    }

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Weather it’s for")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    temperatureBox(
                        "From", value: draft.minTempC,
                        lower: draft.canLowerMin ? { draft.lowerMin() } : nil,
                        raise: draft.canRaiseMin ? { draft.raiseMin() } : nil
                    )
                    temperatureBox(
                        "To", value: draft.maxTempC,
                        lower: draft.canLowerMax ? { draft.lowerMax() } : nil,
                        raise: draft.canRaiseMax ? { draft.raiseMax() } : nil
                    )
                }
                TemperatureRangeBar(min: draft.minTempC, max: draft.maxTempC)
                FlowLayout(spacing: 8) {
                    ForEach(WeatherConditions.options, id: \.condition.rawValue) { option in
                        Chip(title: option.title, isOn: draft.conditions.contains(option.condition)) {
                            if draft.conditions.contains(option.condition) {
                                draft.conditions.remove(option.condition)
                            } else {
                                draft.conditions.insert(option.condition)
                            }
                        }
                    }
                }
                Text(draft.conditions.isEmpty
                     ? "Pick at least one condition, or it will never be shown first on Today."
                     : "Shown first on Today when the forecast fits.")
                    .font(.rowDetail)
                    .foregroundStyle(draft.conditions.isEmpty ? .warning : .textSecondary)
            }
            .card()
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Notes")
            TextField("Notes", text: $draft.notes, prompt: Text("Size, fit, care, repairs").foregroundStyle(.textTertiary),
                      axis: .vertical)
                .lineLimit(3...10)
                .focused($focusedField, equals: .notes)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .card(padding: nil)
        }
    }

    private var soldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Sold")
            VStack(spacing: 0) {
                FormRow(label: "Sold for") {
                    priceField($draft.soldPriceText, field: .soldPrice)
                }
                RowDivider()
                FormRow(label: "Date sold") {
                    DatePicker("Date sold", selection: $draft.soldDate, in: draft.purchaseDate...Date.now,
                               displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .card(padding: nil)
            Button("Mark as not sold") {
                draft.isSold = false
                draft.soldPriceText = ""
            }
            .font(.rowDetail)
            .foregroundStyle(.dataBlue)
            .padding(.horizontal, 4)
        }
    }

    // MARK: Controls

    private func priceField(_ text: Binding<String>, field: Field) -> some View {
        TextField("Price", text: text, prompt: Text(Money.format(cents: 0)).foregroundStyle(.textTertiary))
            .font(.number(.body, weight: .regular))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: field)
    }

    private var wearCounter: some View {
        HStack(spacing: 4) {
            stepButton("minus", label: "10 fewer wears", enabled: draft.priorWearCount > 0) {
                draft.priorWearCount = max(0, draft.priorWearCount - 10)
            }
            TextField("Wears", text: $draft.priorWearCount.emptyWhenZero,
                      prompt: Text("0").foregroundStyle(.textTertiary))
                .font(.number(.body))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 56)
                .focused($focusedField, equals: .wears)
            stepButton("plus", label: "10 more wears", enabled: true) {
                draft.priorWearCount += 10
            }
        }
    }

    private func temperatureBox(_ title: String, value: Int, lower: (() -> Void)?, raise: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.label)
                .foregroundStyle(.textSecondary)
            HStack {
                stepButton("minus", label: "Lower \(title.lowercased()) temperature", enabled: lower != nil) { lower?() }
                Spacer(minLength: 0)
                Text(Temperature.format(celsius: value))
                    .font(.number(.title2))
                    .foregroundStyle(.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                stepButton("plus", label: "Raise \(title.lowercased()) temperature", enabled: raise != nil) { raise?() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.surfaceRaised, in: .rect(cornerRadius: Radius.tile))
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .textPrimary : .textTertiary)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Save

    private func save() async {
        guard draft.isValid else { return }
        isSaving = true
        let item: Item
        switch mode {
        case .new:
            item = Item(name: draft.trimmedName, category: draft.category ?? .other,
                        purchaseDate: draft.purchaseDate, purchasePriceCents: draft.priceCents ?? 0)
            modelContext.insert(item)
        case .edit(let existing):
            item = existing
        }
        await draft.apply(to: item)
        try? modelContext.save()
        isSaving = false
        onSave(item)
        dismiss()
    }
}

/// The blue bar showing an item's temperature range on a −30° to 35°C scale.
struct TemperatureRangeBar: View {
    var min: Int
    var max: Int

    var body: some View {
        GeometryReader { geometry in
            let span = Double(ItemDraft.tempHighest - ItemDraft.tempLowest)
            let start = Double(min - ItemDraft.tempLowest) / span
            let width = Double(max - min) / span
            Capsule()
                .fill(.surfaceRaised)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.dataBlue)
                        .frame(width: geometry.size.width * width)
                        .offset(x: geometry.size.width * start)
                }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Suited from \(Temperature.format(celsius: min)) to \(Temperature.format(celsius: max))")
    }
}

#Preview("New") {
    ItemFormView(mode: .new)
        .modelContainer(for: [Item.self, DayLog.self], inMemory: true)
        .preferredColorScheme(.dark)
}
