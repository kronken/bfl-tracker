import SwiftUI

/// Pick a country: search, suggestions, and an optional "None". Picking one
/// applies it and closes the sheet.
struct CountryPicker: View {
    var title: String
    var selection: String?
    /// Countries to list first: the device region and ones already used.
    var suggested: [String] = []
    /// Shows a "None" row that clears the field.
    var allowsNone = true
    var onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private static let countries = Countries.all()

    private var matches: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Self.countries }
        return Self.countries.filter {
            Countries.name(for: $0).localizedStandardContains(trimmed) || $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private var suggestions: [String] {
        var seen = Set<String>()
        return suggested.filter { Self.countries.contains($0) && seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    SearchField(prompt: "Search countries", text: $query)
                    if query.isEmpty {
                        if allowsNone {
                            row(nil, title: "None", isOn: selection == nil, muted: true)
                                .card(padding: nil)
                        }
                        if !suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel("Suggested")
                                list(suggestions)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("All countries")
                            list(matches)
                        }
                    } else if matches.isEmpty {
                        Text("No country matches “\(query)”.")
                            .font(.rowDetail)
                            .foregroundStyle(.textSecondary)
                            .padding(.horizontal, 4)
                    } else {
                        list(matches)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(.appBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.textPrimary)
                }
            }
        }
        .presentationBackground(.appBackground)
    }

    private func list(_ codes: [String]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(codes.enumerated()), id: \.element) { index, code in
                if index > 0 { RowDivider() }
                row(code, title: Countries.name(for: code), isOn: code == selection, muted: false)
            }
        }
        .card(padding: nil)
    }

    private func row(_ code: String?, title: String, isOn: Bool, muted: Bool) -> some View {
        Button {
            onSelect(code)
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(muted ? .textSecondary : .textPrimary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
