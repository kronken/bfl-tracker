import SwiftData
import SwiftUI

/// The New item / Edit item sheet.
struct ItemFormView: View {
    enum Mode {
        case new
        case edit(Item)
    }

    let mode: Mode
    /// Opens the form scrolled to the Care section ("Choose actions").
    var scrollToCare = false
    /// Called with the saved item after Add or Save.
    var onSave: (Item) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var occasions: [Occasion]
    @Query private var brands: [Brand]
    @Query private var stores: [Store]
    @Query private var allItems: [Item]
    @Query private var categoryRecords: [ClothingCategory]
    @Query private var careActions: [CareAction]

    @State private var draft: ItemDraft
    @State private var isProcessingPhoto = false
    @State private var isSaving = false
    @State private var showNewOccasion = false
    @State private var showBrandPicker = false
    @State private var showMadeIn = false
    @State private var showStorePicker = false
    @State private var showNewCategory = false
    @State private var showNewType = false
    @State private var showNewCareAction = false
    /// Bumped when the last occasion is tapped: it shakes instead.
    @State private var occasionRefusals = 0
    @FocusState private var focusedField: Field?

    private enum Field { case name, size, price, wears, notes, soldPrice }

    @State private var initialDraft: ItemDraft

    init(mode: Mode, scrollToCare: Bool = false, onSave: @escaping (Item) -> Void = { _ in }) {
        self.mode = mode
        self.scrollToCare = scrollToCare
        self.onSave = onSave
        let draft: ItemDraft = switch mode {
        case .new: ItemDraft()
        case .edit(let item): ItemDraft(item: item)
        }
        _draft = State(initialValue: draft)
        _initialDraft = State(initialValue: draft)
    }

    private var isNew: Bool {
        if case .new = mode { true } else { false }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PhotoSection(
                        photo: $draft.photo,
                        isProcessing: $isProcessingPhoto,
                        name: draft.name,
                        iconName: selectedCategory?.iconName ?? ClothingCategory.genericIcon
                    )
                    itemSection
                    categorySection
                    if selectedCategory != nil { typeSection }
                    occasionsSection
                    weatherSection
                    careSection.id("care")
                    notesSection
                    if draft.isSold { soldSection }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .onAppear {
                if scrollToCare { proxy.scrollTo("care", anchor: .top) }
            }
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
        .onAppear(perform: fillInOccasions)
        .sheet(isPresented: $showNewCategory) {
            CategorySheet { created in pickCategory(created.id) }
        }
        .sheet(isPresented: $showNewType) {
            if let category = selectedCategory {
                TypeSheet(mode: .new(category)) { created in draft.typeID = created.id }
            }
        }
        .sheet(isPresented: $showNewCareAction) {
            CareActionSheet(mode: .new) { created in draft.careActionIDs.insert(created.id) }
        }
        .sheet(isPresented: $showBrandPicker) {
            BrandPicker(selectedID: draft.brandID, item: draftImageContent) { draft.brandID = $0?.id }
        }
        .sheet(isPresented: $showStorePicker) {
            StorePicker(selectedID: draft.storeID, item: draftImageContent) { draft.storeID = $0?.id }
        }
        .sheet(isPresented: $showMadeIn) {
            CountryPicker(title: "Made in", selection: draft.madeInCountryCode,
                          suggested: Countries.suggestions(used: allItems.map(\.madeInCountryCode)
                                                               + brands.map(\.countryCode))) {
                draft.madeInCountryCode = $0
            }
        }
        .sheet(isPresented: $showNewOccasion) {
            OccasionSheet(mode: .new(item: draftImageContent)) { created in
                draft.occasionIDs.insert(created.id)
            }
        }
    }

    // MARK: Brand and origin

    private var selectedBrand: Brand? {
        draft.brandID.flatMap { id in brands.first { $0.id == id } }
    }

    private var selectedStore: Store? {
        draft.storeID.flatMap { id in stores.first { $0.id == id } }
    }

    /// A form row that opens a picker: label, value, chevron.
    private func pickerRow<Value: View>(_ label: String, action: @escaping () -> Void,
                                        @ViewBuilder value: () -> Value) -> some View {
        Button(action: action) {
            FormRow(label: label) {
                HStack(spacing: 8) {
                    value()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textTertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Occasions

    private var occasionInfos: [OccasionInfo] { occasions.map(\.info) }

    /// Items without occasions are in Everyday; a new item starts in the
    /// default occasion.
    private func fillInOccasions() {
        guard draft.occasionIDs.isEmpty else { return }
        let everyday = Occasion.ensureBuiltIn(in: modelContext)
        let all = occasions.map(\.info)
        let start = isNew ? (OccasionRules.defaultOccasion(all)?.id ?? everyday.id) : everyday.id
        draft.occasionIDs = [start]
        initialDraft.occasionIDs = [start]
    }

    private var draftImageContent: ItemImageContent {
        ItemImageContent(imageData: draft.photo?.chosenThumbnail ?? draft.photo?.chosen,
                         isCutout: draft.photo?.usesCutout ?? false, tintHex: draft.photo?.chosenTint,
                         name: draft.trimmedName,
                         iconName: selectedCategory?.iconName ?? ClothingCategory.genericIcon)
    }

    private var occasionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Occasions")
            let visible = OccasionRules.visible(occasionInfos)
            FlowLayout(spacing: 8) {
                ForEach(visible) { occasion in
                    OccasionChip(title: occasion.name, isOn: draft.occasionIDs.contains(occasion.id)) {
                        toggleOccasion(occasion.id, visible: visible)
                    }
                }
                DashedAddChip(title: "New occasion") { showNewOccasion = true }
            }
            .keyframeAnimator(initialValue: 0.0, trigger: occasionRefusals) { content, offset in
                content.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    for offset in [-8.0, 7, -5, 3, 0] {
                        CubicKeyframe(offset, duration: 0.06)
                    }
                }
            }
            .sensoryFeedback(.error, trigger: occasionRefusals)
            Text("Shown on Today when that occasion is picked. Pick any number.")
                .font(.footnote)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    /// At least one shown occasion has to stay picked.
    private func toggleOccasion(_ id: UUID, visible: [OccasionInfo]) {
        if draft.occasionIDs.contains(id) {
            let remaining = draft.occasionIDs.subtracting([id])
            guard visible.contains(where: { remaining.contains($0.id) }) else {
                occasionRefusals += 1
                return
            }
            draft.occasionIDs = remaining
        } else {
            draft.occasionIDs.insert(id)
        }
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
                pickerRow("Brand", action: { showBrandPicker = true }) {
                    if let brand = selectedBrand {
                        HStack(spacing: 0) {
                            Text(brand.name).foregroundStyle(.textPrimary)
                            if let code = brand.countryCode {
                                Text(" · \(Countries.name(for: code))").foregroundStyle(.textSecondary)
                            }
                        }
                        .lineLimit(1)
                    } else {
                        Text("Optional").foregroundStyle(.textTertiary)
                    }
                }
                RowDivider()
                pickerRow("Made in", action: { showMadeIn = true }) {
                    Text(draft.madeInCountryCode.map { Countries.name(for: $0) } ?? "Optional")
                        .foregroundStyle(draft.madeInCountryCode == nil ? .textTertiary : .textPrimary)
                        .lineLimit(1)
                }
                RowDivider()
                FormRow(label: "Size") {
                    TextField("Size", text: $draft.sizeText, prompt: Text("M, 48, W32 L34").foregroundStyle(.textTertiary))
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .size)
                }
                if draft.hasPieceLog {
                    RowDivider()
                    FormRow(label: "Price and date", detail: "Kept in the item’s log: Add more and Retire") {
                        EmptyView()
                    }
                } else {
                    RowDivider()
                    FormRow(label: draft.isGift ? (draft.isMultiPiece ? "Value of all" : "Value")
                                                : (draft.isMultiPiece ? "Price for all" : "Price")) {
                        priceField($draft.priceText, field: .price)
                    }
                    RowDivider()
                    FormRow(label: draft.isGift ? "Received" : "Bought") {
                        DatePicker("Bought", selection: $draft.purchaseDate, in: ...Date.now, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                // Gifts weren't bought anywhere.
                if !draft.isGift {
                    RowDivider()
                    pickerRow("Store", action: { showStorePicker = true }) {
                        Text(selectedStore?.name ?? "Optional")
                            .foregroundStyle(selectedStore == nil ? .textTertiary : .textPrimary)
                            .lineLimit(1)
                    }
                }
                RowDivider()
                ToggleRow(label: "Received as a gift",
                          detail: "Not counted as spending. Value still sets cost per wear",
                          isOn: $draft.isGift)
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
                RowDivider()
                ToggleRow(label: "Identical pieces",
                          detail: draft.pieceLogLocked
                              ? "Can’t be turned off once pieces have been added or retired"
                              : "Socks, boxers, basic tees. Log the set, not the piece",
                          isOn: $draft.isMultiPiece)
                    .disabled(draft.pieceLogLocked)
                if draft.isMultiPiece && !draft.hasPieceLog {
                    RowDivider()
                    FormRow(label: "How many") {
                        CountStepper(value: $draft.pieceCount, range: 2...99, label: "How many")
                    }
                }
            }
            .card(padding: nil)
        }
    }

    // MARK: Category, type, care

    private var orderedCategories: [ClothingCategory] { ClothingCategory.sorted(categoryRecords) }

    private var selectedCategory: ClothingCategory? {
        draft.categoryID.flatMap { id in categoryRecords.first { $0.id == id } }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Category")
            FlowLayout(spacing: 8) {
                ForEach(orderedCategories) { category in
                    Chip(title: category.name, isOn: draft.categoryID == category.id) { pickCategory(category.id) }
                }
                DashedAddChip(title: "New category") { showNewCategory = true }
            }
        }
    }

    /// Changing the category clears the type.
    private func pickCategory(_ id: UUID) {
        guard draft.categoryID != id else { return }
        draft.categoryID = id
        draft.typeID = nil
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Type · \(selectedCategory?.name ?? "")")
            FlowLayout(spacing: 8) {
                ForEach(selectedCategory?.sortedTypes ?? []) { type in
                    OccasionChip(title: type.name, isOn: draft.typeID == type.id) {
                        // Optional: tapping the picked type again clears it.
                        draft.typeID = draft.typeID == type.id ? nil : type.id
                    }
                }
                DashedAddChip(title: "New type") { showNewType = true }
            }
            Text("Optional. Lets you see how many of one kind you own.")
                .font(.footnote)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var careSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Care")
            FlowLayout(spacing: 8) {
                ForEach(CareAction.sorted(careActions)) { action in
                    OccasionChip(title: action.name, isOn: draft.careActionIDs.contains(action.id)) {
                        draft.careActionIDs.formSymmetricDifference([action.id])
                    }
                }
                DashedAddChip(title: "New action") { showNewCareAction = true }
            }
            Text("Turn on the care you want to log for this item. None are on until you pick them.")
                .font(.footnote)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 4)
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
            TextField("Notes", text: $draft.notes, prompt: Text("Fit, anything else").foregroundStyle(.textTertiary),
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
            item = Item(name: draft.trimmedName, purchaseDate: draft.purchaseDate,
                        purchasePriceCents: draft.priceCents ?? 0)
            modelContext.insert(item)
        case .edit(let existing):
            item = existing
        }
        await draft.apply(to: item)
        item.brand = selectedBrand
        item.store = draft.isGift ? nil : selectedStore
        item.setCategory(selectedCategory)
        item.itemType = draft.typeID.flatMap { id in selectedCategory?.types?.first { $0.id == id } }
        item.enabledCareActions = careActions.filter { draft.careActionIDs.contains($0.id) }
        let tagged = occasions.filter { draft.occasionIDs.contains($0.id) }
        if !tagged.isEmpty { item.occasions = tagged }
        updatePieceLog(of: item)
        try? modelContext.save()
        isSaving = false
        onSave(item)
        dismiss()
    }

    /// Identical pieces: turning the switch on starts the log with one
    /// purchase (how many, price, date); turning it off (only possible with a
    /// single entry) goes back to a normal item.
    private func updatePieceLog(of item: Item) {
        let events = item.pieceEvents ?? []
        if item.isMultiPiece && events.isEmpty {
            let first = PieceEvent(kind: .bought, quantity: draft.pieceCount, date: item.purchaseDate,
                                   priceCents: item.purchasePriceCents)
            first.isGift = item.isGift
            modelContext.insert(first)
            first.item = item
        } else if !item.isMultiPiece && events.count == 1 {
            modelContext.delete(events[0])
        }
        // The first purchase of a set follows the item's gift switch; later
        // Add mores keep their own setting.
        if item.isMultiPiece, let first = (item.pieceEvents ?? []).filter({ $0.kind == .bought }).min(by: { $0.date < $1.date }) {
            first.isGift = item.isGift
        }
        item.syncFromPieceEvents()
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

/// An occasion in the item form: checkmark and fill when picked.
struct OccasionChip: View {
    var title: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.rowDetail.weight(.medium))
            }
            .foregroundStyle(isOn ? .textPrimary : .textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(isOn ? AnyShapeStyle(.fillSelected) : AnyShapeStyle(.clear), in: .capsule)
            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
