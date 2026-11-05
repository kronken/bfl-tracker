import SwiftData
import SwiftUI

/// Settings › Brands: every brand with its country and item count.
struct BrandsView: View {
    @Query private var brands: [Brand]

    @State private var editing: Brand?
    @State private var showNew = false
    @State private var deleting: Brand?

    var body: some View {
        List {
            Section {
                Text("Name and home country of each brand you own.")
                    .font(.body)
                    .foregroundStyle(.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            Section {
                Button { showNew = true } label: {
                    Label("Add brand", systemImage: "plus")
                        .font(.body)
                        .foregroundStyle(.dataBlue)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.surface)

            if brands.isEmpty {
                Section {
                    Text("No brands yet. Add one here or when editing an item.")
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
            } else {
                Section {
                    ForEach(Brand.sorted(brands)) { brand in
                        Button { editing = brand } label: { row(brand) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { deleting = brand }
                            }
                    }
                }
                .listRowBackground(Color.surface)
                .listRowSeparatorTint(.stroke)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Brands")
        .navigationBarTitleDisplayMode(.large)
        .toolbarVisibility(.visible, for: .navigationBar)
        .sheet(item: $editing) { brand in
            BrandSheet(mode: .edit(brand))
        }
        .sheet(isPresented: $showNew) {
            BrandSheet(mode: .new())
        }
        .brandDeleteConfirmation(deleting, isPresented: Binding(get: { deleting != nil },
                                                               set: { if !$0 { deleting = nil } }))
        #if DEBUG
        // `-openBrands new|<name>` on launch opens that sheet, for screenshots.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "openBrands") {
            case "new": showNew = true
            case let name?: editing = brands.first { $0.name == name }
            case nil: break
            }
        }
        #endif
    }

    private func row(_ brand: Brand) -> some View {
        let count = brand.itemCount
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(brand.name)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text("\(brand.countryCode.map { Countries.name(for: $0) } ?? "No country") · \(count == 1 ? "1 item" : "\(count) items")")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.textTertiary)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}
