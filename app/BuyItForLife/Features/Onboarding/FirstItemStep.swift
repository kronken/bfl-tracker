import SwiftData
import SwiftUI

/// Onboarding's lighter item form: weather is picked as broad temperature
/// bands instead of exact degrees.
struct FirstItemStep: View {
    var onAdded: (Item) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var draft = ItemDraft()
    @State private var bands: Set<TemperatureBand> = []
    @State private var isProcessingPhoto = false
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your first item")
                        .font(.screenTitle)
                        .foregroundStyle(.textPrimary)
                    Text("Start with something you wear a lot: your boots, a jacket, your jeans.")
                        .font(.body)
                        .foregroundStyle(.textSecondary)
                }
                .padding(.horizontal, 4)

                PhotoSection(photo: $draft.photo, isProcessing: $isProcessingPhoto,
                             name: draft.name, category: draft.category)

                VStack(spacing: 0) {
                    FormRow(label: "Name") {
                        TextField("Name", text: $draft.name, prompt: Text("Brand and model").foregroundStyle(.textTertiary))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .focused($focused)
                    }
                    RowDivider()
                    FormRow(label: "Price") {
                        TextField("Price", text: $draft.priceText,
                                  prompt: Text(Money.format(cents: 0)).foregroundStyle(.textTertiary))
                            .font(.number(.body, weight: .regular))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focused)
                    }
                    RowDivider()
                    FormRow(label: "Bought") {
                        DatePicker("Bought", selection: $draft.purchaseDate, in: ...Date.now, displayedComponents: .date)
                            .labelsHidden()
                    }
                    RowDivider()
                    FormRow(label: "Worn so far", detail: "A rough guess is fine") {
                        HStack(spacing: 4) {
                            step("minus", enabled: draft.priorWearCount > 0) {
                                draft.priorWearCount = max(0, draft.priorWearCount - 10)
                            }
                            TextField("Wears", text: $draft.priorWearCount.emptyWhenZero,
                                      prompt: Text("0").foregroundStyle(.textTertiary))
                                .font(.number(.body))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 56)
                                .focused($focused)
                            step("plus", enabled: true) { draft.priorWearCount += 10 }
                        }
                    }
                }
                .foregroundStyle(.textPrimary)
                .card(padding: nil)

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

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Weather it’s for")
                    VStack(alignment: .leading, spacing: 14) {
                        FlowLayout(spacing: 8) {
                            ForEach(TemperatureBand.allCases) { band in
                                Chip(title: band.title, isOn: bands.contains(band)) {
                                    if bands.contains(band) { bands.remove(band) } else { bands.insert(band) }
                                }
                            }
                        }
                        if let range = TemperatureBand.range(of: bands) {
                            TemperatureRangeBar(min: range.lowerBound, max: range.upperBound)
                            Text("Suggested on Today from \(Temperature.format(celsius: range.lowerBound)) to \(Temperature.format(celsius: range.upperBound)).")
                                .font(.rowDetail)
                                .foregroundStyle(.textSecondary)
                        } else {
                            Text("Pick at least one.")
                                .font(.rowDetail)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // A safe-area bar fades the content out under the button instead of a
        // solid strip. It's hidden while typing: riding above the keyboard it
        // covered the field being edited, and it can't be used mid-typing anyway.
        .safeAreaBar(edge: .bottom) {
            if !focused {
                Button("Add to wardrobe") { Task { await add() } }
                    .buttonStyle(.primary)
                    .disabled(!canAdd)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private var canAdd: Bool {
        draft.isValid && !bands.isEmpty && !isProcessingPhoto && !isSaving
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .textPrimary : .textTertiary)
        .disabled(!enabled)
    }

    private func add() async {
        guard canAdd, let range = TemperatureBand.range(of: bands) else { return }
        isSaving = true
        var draft = draft
        draft.minTempC = range.lowerBound
        draft.maxTempC = range.upperBound
        let item = Item(name: draft.trimmedName, category: draft.category ?? .other,
                        purchaseDate: draft.purchaseDate, purchasePriceCents: draft.priceCents ?? 0)
        modelContext.insert(item)
        await draft.apply(to: item)
        try? modelContext.save()
        isSaving = false
        onAdded(item)
    }
}

/// The onboarding's broad temperature choices.
enum TemperatureBand: Int, CaseIterable, Identifiable, Hashable {
    case freezing, cold, mild, warm

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .freezing: "Freezing"
        case .cold: "Cold"
        case .mild: "Mild"
        case .warm: "Warm"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .freezing: -30...0
        case .cold: 0...10
        case .mild: 10...18
        case .warm: 18...35
        }
    }

    /// From the coldest picked band's low to the warmest's high.
    static func range(of bands: Set<TemperatureBand>) -> ClosedRange<Int>? {
        guard let low = bands.min(by: { $0.rawValue < $1.rawValue }),
              let high = bands.max(by: { $0.rawValue < $1.rawValue })
        else { return nil }
        return low.range.lowerBound...high.range.upperBound
    }
}
