import SwiftData
import SwiftUI

/// Choose an item's brand: search, "New brand", "No brand", or one of the
/// list. Choosing applies it and closes the sheet.
struct BrandPicker: View {
    var selectedID: UUID?
    /// The item being edited, shown when a new brand is created from here.
    var item: ItemImageContent?
    var onSelect: (Brand?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var brands: [Brand]

    @State private var query = ""
    @State private var showNew = false
    /// Set when a brand was created; this sheet closes once that one has.
    @State private var created = false

    private var matches: [Brand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let sorted = Brand.sorted(brands)
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedStandardContains(trimmed) }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    SearchField(prompt: "Search brands", text: $query)
                    VStack(spacing: 0) {
                        Button { showNew = true } label: {
                            Label(trimmedQuery.isEmpty ? "New brand" : "New brand “\(trimmedQuery)”", systemImage: "plus")
                                .font(.body)
                                .foregroundStyle(.dataBlue)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        RowDivider()
                        row(title: "No brand", subtitle: nil, isOn: selectedID == nil, muted: true) { choose(nil) }
                    }
                    .card(padding: nil)

                    if !matches.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, brand in
                                if index > 0 { RowDivider() }
                                row(title: brand.name, subtitle: brand.countryCode.map { Countries.name(for: $0) },
                                    isOn: brand.id == selectedID, muted: false) { choose(brand) }
                            }
                        }
                        .card(padding: nil)
                    } else if !brands.isEmpty {
                        Text("No brand matches “\(trimmedQuery)”.")
                            .font(.rowDetail)
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
            .navigationTitle("Brand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.textPrimary)
                }
            }
        }
        .presentationBackground(.appBackground)
        .sheet(isPresented: $showNew, onDismiss: { if created { dismiss() } }) {
            BrandSheet(mode: .new(name: trimmedQuery, fromItem: item)) { brand in
                onSelect(brand)
                created = true
            }
        }
    }

    private func choose(_ brand: Brand?) {
        onSelect(brand)
        dismiss()
    }

    private func row(title: String, subtitle: String?, isOn: Bool, muted: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(muted ? .textSecondary : .textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
