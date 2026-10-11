import SwiftUI

// MARK: - Chip

/// A capsule toggle, e.g. a category filter or a weather condition.
struct Chip: View {
    var title: String
    var isOn: Bool
    /// The Wardrobe filter row uses 36pt chips, the forms 40pt.
    var height: CGFloat = 40
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.rowDetail.weight(.medium))
                .foregroundStyle(isOn ? .textPrimary : .textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: height)
                .background(isOn ? AnyShapeStyle(.fillSelected) : AnyShapeStyle(.clear), in: .capsule)
                .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Segmented control

/// The design's two- or three-way switch: a dark track with a lighter
/// selected segment.
struct SegmentedControl<Value: Hashable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.rowDetail.weight(.semibold))
                        .foregroundStyle(.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(isOn ? AnyShapeStyle(.segmentSelected) : AnyShapeStyle(.clear),
                                    in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.surfaceRaised, in: .rect(cornerRadius: Radius.thumb))
    }
}

// MARK: - Search field

struct SearchField: View {
    var prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.textSecondary)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(.textSecondary))
                .foregroundStyle(.textPrimary)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.surfaceRaised, in: .rect(cornerRadius: Radius.thumb))
    }
}

// MARK: - Flow layout

/// Lays out children left to right, wrapping onto new lines. Used for chip
/// groups.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Form rows

/// A row inside a form card: label on the left, control on the right, 52pt tall.
struct FormRow<Control: View>: View {
    var label: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body)
                    .foregroundStyle(.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.textSecondary)
                }
            }
            .frame(minWidth: 96, alignment: .leading)
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
    }
}

/// A row with a label, a short explanation and an iOS switch, 64pt tall.
struct ToggleRow: View {
    var label: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body)
                    .foregroundStyle(.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
            }
        }
        .tint(.positive)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
    }
}

/// A hairline between rows in a card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(.stroke).frame(height: 1)
    }
}

// MARK: - Number input

extension Binding where Value == Int {
    /// Text for a number field where 0 shows as empty, so a "0" placeholder
    /// can be typed over without deleting it first. Non-digits are ignored.
    var emptyWhenZero: Binding<String> {
        Binding<String>(
            get: { wrappedValue == 0 ? "" : String(wrappedValue) },
            set: { wrappedValue = Int(String($0.filter(\.isNumber).prefix(6))) ?? 0 }
        )
    }
}

// MARK: - Sheets

/// −  value  + with bounds, e.g. "How many".
struct CountStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var label: String

    var body: some View {
        HStack(spacing: 4) {
            step("minus", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)")
                .font(.number(.title3))
                .foregroundStyle(.textPrimary)
                .contentTransition(.numericText())
                .frame(minWidth: 36)
            step("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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
    }
}

/// The item a sheet is about: thumbnail, name and a short summary.
struct SheetContextRow: View {
    let item: Item
    var summary: String

    var body: some View {
        HStack(spacing: 12) {
            ItemImageView(content: item.thumbnailContent, cornerRadius: Radius.thumb, iconSize: 22)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text(summary)
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// "AFTER THIS": two or three figures that update as the user types.
struct AfterThisCard: View {
    var title: String
    var figures: [(value: String, label: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.label)
                .tracking(0.3)
                .foregroundStyle(.textSecondary)
            HStack(alignment: .top, spacing: 8) {
                ForEach(figures.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(figures[index].value)
                            .font(.number(.title3))
                            .foregroundStyle(.textPrimary)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(figures[index].label)
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Cancel / title / Save sheet scaffold used by the repair and pieces sheets.
struct EditSheet<Content: View>: View {
    var title: String
    var canSave: Bool
    var onSave: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.appBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
                }
            }
        }
        .presentationBackground(.appBackground)
    }
}
