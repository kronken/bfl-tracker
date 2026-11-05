import SwiftUI

/// First control in Wardrobe's filter row: "Brand ⌄" when no brand is picked,
/// otherwise the brand name with a × to clear it.
struct BrandFilterControl: View {
    var brandName: String?
    var height: CGFloat = 36
    var onOpen: () -> Void
    var onClear: () -> Void

    var body: some View {
        if let brandName {
            HStack(spacing: 0) {
                Button(action: onOpen) {
                    Text(brandName)
                        .font(.rowDetail.weight(.semibold))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                        .padding(.leading, 14)
                        .frame(minHeight: height)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Brand filter: \(brandName)")
                .accessibilityHint("Shows the brand list")
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // A 44pt target that doesn't make the capsule taller than the chips.
                .padding(.vertical, (height - 44) / 2)
                .padding(.leading, -4)
                .accessibilityLabel("Clear brand filter")
            }
            .background(.fillSelected, in: .capsule)
            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
        } else {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text("Brand")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.rowDetail.weight(.medium))
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: height)
                .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter by brand")
        }
    }
}

/// "Filter by brand": brands with items in the current Wardrobe tab. Picking
/// one applies it and closes the sheet.
struct BrandFilterSheet: View {
    /// Items in the current tab, before any filter.
    var items: [Item]
    var brands: [Brand]
    var selectedID: UUID?
    var onSelect: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [(brand: Brand, count: Int)] {
        var counts: [UUID: Int] = [:]
        for item in items {
            if let id = item.brand?.id { counts[id, default: 0] += 1 }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return Brand.sorted(brands)
            .compactMap { brand in counts[brand.id].map { (brand, $0) } }
            .filter { trimmed.isEmpty || $0.brand.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SearchField(prompt: "Search brands", text: $query)
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVStack(spacing: 0) {
                            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                                row(title: "All brands", subtitle: nil, count: items.count, isOn: selectedID == nil) {
                                    choose(nil)
                                }
                            }
                            ForEach(Array(rows.enumerated()), id: \.element.brand.id) { index, row in
                                if index > 0 || query.trimmingCharacters(in: .whitespaces).isEmpty { RowDivider() }
                                self.row(title: row.brand.name, subtitle: row.brand.countryCode.map { Countries.name(for: $0) },
                                         count: row.count, isOn: row.brand.id == selectedID) { choose(row.brand.id) }
                            }
                        }
                        .card(padding: nil)
                        if rows.isEmpty && !query.isEmpty {
                            Text("No brand matches “\(query)”.")
                                .font(.rowDetail)
                                .foregroundStyle(.textSecondary)
                                .padding(.horizontal, 4)
                        }
                        Text("Counts are items in the current tab. Brands with no items there are hidden.")
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(.appBackground)
            .navigationTitle("Filter by brand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(.textPrimary)
                }
            }
        }
        .presentationBackground(.appBackground)
    }

    private func choose(_ id: UUID?) {
        onSelect(id)
        dismiss()
    }

    private func row(title: String, subtitle: String?, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer()
                Text(count.formatted())
                    .font(.number(.subheadline, weight: .regular))
                    .foregroundStyle(.textSecondary)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.textPrimary)
                    .opacity(isOn ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
