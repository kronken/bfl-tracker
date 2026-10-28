import SwiftData
import SwiftUI

/// New occasion / Edit occasion. Opened from Settings or from the item form,
/// where a new occasion is added to the item being edited.
struct OccasionSheet: View {
    enum Mode {
        /// `item` is the item being added or edited, shown as context.
        case new(item: ItemImageContent?)
        case edit(Occasion)
    }

    let mode: Mode
    /// Called with a newly created occasion after Save.
    var onCreate: (Occasion) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var occasions: [Occasion]
    @Query private var items: [Item]

    @State private var name = ""
    @State private var weekdays: Weekdays = []
    @State private var isDefault = false
    @State private var showOnToday = true
    @State private var confirmDelete = false
    @State private var defaultFirst = false
    @State private var hideWarning: Int?

    private let calendar = Calendar.current

    private var editing: Occasion? {
        if case .edit(let occasion) = mode { occasion } else { nil }
    }

    private var isBuiltIn: Bool { editing?.isBuiltIn ?? false }

    private var title: String {
        guard let editing else { return "New occasion" }
        return editing.isBuiltIn ? editing.name : "Edit occasion"
    }

    private var nameIsTaken: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !OccasionRules.isNameAvailable(name, excluding: editing?.id, in: occasions.map(\.info))
    }

    private var canSave: Bool {
        OccasionRules.isNameAvailable(name, excluding: editing?.id, in: occasions.map(\.info))
    }

    /// The current default can't be switched off, only replaced.
    private var isCurrentDefault: Bool { editing?.isDefault ?? false }

    /// Everyday can only be hidden when there is something else to show.
    private var canHide: Bool { occasions.contains { !$0.isBuiltIn } }

    var body: some View {
        EditSheet(title: title, canSave: canSave, onSave: save) {
            if case .new(let item?) = mode {
                itemContext(item)
            }
            if isBuiltIn {
                Text("The built-in occasion. It can be renamed or hidden, but not deleted.")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                FormRow(label: "Name") {
                    TextField("Name", text: $name,
                              prompt: Text("Office, Gym, Formal").foregroundStyle(.textTertiary))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }
                .foregroundStyle(.textPrimary)
                .card(padding: nil)
                if nameIsTaken {
                    Text("You already have an occasion with this name.")
                        .font(.footnote)
                        .foregroundStyle(.warning)
                        .padding(.horizontal, 4)
                }
            }

            weekdayPicker

            VStack(spacing: 0) {
                ToggleRow(label: "Default occasion", detail: "Used when no day rule matches", isOn: defaultBinding)
                    .disabled(isCurrentDefault)
                if isBuiltIn {
                    RowDivider()
                    ToggleRow(label: "Show on Today", detail: "Hide it if every item has another occasion",
                              isOn: showBinding)
                        .disabled(!canHide && showOnToday)
                }
            }
            .card(padding: nil)
            if isCurrentDefault {
                Text("To change the default, make another occasion the default.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 4)
            }

            if let editing, !editing.isBuiltIn {
                VStack(spacing: 4) {
                    Button("Delete occasion", role: .destructive) { confirmDelete = true }
                        .font(.body)
                        .foregroundStyle(.destructive)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    Text("Clothes stay in your wardrobe. They just lose this tag.")
                        .font(.footnote)
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 24)
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Delete \(editing?.name ?? "this occasion")?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete occasion", role: .destructive, action: delete)
        } message: {
            Text("Clothes stay in your wardrobe. They just lose this tag.")
        }
        .alert("Choose another default first", isPresented: $defaultFirst) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(editing?.name ?? Occasion.builtInName) is your default occasion. Make another occasion the default, then hide this one.")
        }
        .alert("Hide \(name)?", isPresented: Binding(get: { hideWarning != nil }, set: { if !$0 { hideWarning = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Hide anyway", role: .destructive) { showOnToday = false }
        } message: {
            let count = hideWarning ?? 0
            Text("\(count) \(count == 1 ? "item is" : "items are") only in \(name) and won’t appear on Today.")
        }
    }

    // MARK: Parts

    private func itemContext(_ item: ItemImageContent) -> some View {
        HStack(spacing: 12) {
            ItemImageView(content: item, cornerRadius: Radius.thumb, iconSize: 18)
                .frame(width: 40, height: 40)
            Text("\(item.name.trimmingCharacters(in: .whitespaces).isEmpty ? "This item" : item.name) joins this occasion when you save.")
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .card(padding: nil)
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Pick automatically on")
            HStack(spacing: 6) {
                ForEach(Weekdays.ordered(calendar: calendar), id: \.self) { weekday in
                    let isOn = weekdays.contains(weekday: weekday)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { weekdays.formSymmetricDifference(.day(weekday)) }
                    } label: {
                        Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                            .font(.rowDetail.weight(.semibold))
                            .foregroundStyle(isOn ? .textPrimary : .textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(isOn ? AnyShapeStyle(.fillSelected) : AnyShapeStyle(.clear), in: .circle)
                            .overlay { Circle().strokeBorder(.stroke, lineWidth: 1) }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Text(OccasionRules.ruleHelper(name: name, weekdays: weekdays))
                .font(.footnote)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 4)
                .contentTransition(.opacity)
        }
    }

    private var defaultBinding: Binding<Bool> {
        Binding(get: { isDefault }, set: { newValue in
            withAnimation(.snappy(duration: 0.2)) {
                isDefault = newValue
                // The default has to be on Today.
                if newValue { showOnToday = true }
            }
        })
    }

    private var showBinding: Binding<Bool> {
        Binding(get: { showOnToday }, set: { newValue in
            guard !newValue else { showOnToday = true; return }
            if isDefault {
                defaultFirst = true
                return
            }
            guard let editing else { return }
            let stranded = Occasion.itemsOnlyInBuiltIn(items, builtInID: editing.id).count
            if stranded > 0 {
                hideWarning = stranded
            } else {
                showOnToday = false
            }
        })
    }

    // MARK: Saving

    private func load() {
        guard let editing else { return }
        name = editing.name
        weekdays = editing.weekdays
        isDefault = editing.isDefault
        showOnToday = !editing.isHidden
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing {
            editing.name = trimmed
            editing.weekdays = weekdays
            if isBuiltIn { editing.isHidden = !showOnToday }
            if isDefault && !editing.isDefault { editing.makeDefault(in: modelContext) }
        } else {
            let created = Occasion.create(name: trimmed, weekdays: weekdays, isDefault: isDefault, in: modelContext)
            onCreate(created)
        }
        try? modelContext.save()
    }

    private func delete() {
        guard let editing else { return }
        Occasion.delete(editing, in: modelContext)
        dismiss()
    }
}
