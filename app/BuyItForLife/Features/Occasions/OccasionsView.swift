import SwiftData
import SwiftUI

/// Settings › Occasions: the list, in rule-priority order. Reorder with Edit.
struct OccasionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var occasions: [Occasion]
    @Query private var items: [Item]

    @State private var editing: Occasion?
    @State private var showNew = false

    private var sorted: [Occasion] {
        let order = OccasionRules.sorted(occasions.map(\.info)).map(\.id)
        return order.compactMap { id in occasions.first { $0.id == id } }
    }

    var body: some View {
        List {
            Section {
                Text("Group clothes by where you wear them. Today shows one occasion at a time.")
                    .font(.body)
                    .foregroundStyle(.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            Section {
                ForEach(sorted) { occasion in
                    Button { editing = occasion } label: { row(occasion) }
                        .buttonStyle(.plain)
                }
                .onMove(perform: move)
                Button { showNew = true } label: {
                    Label("Add occasion", systemImage: "plus")
                        .font(.body)
                        .foregroundStyle(.dataBlue)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .moveDisabled(true)
            } footer: {
                explainer
            }
            .listRowBackground(Color.surface)
            .listRowSeparatorTint(.stroke)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Occasions")
        .navigationBarTitleDisplayMode(.large)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
            if occasions.count > 1 {
                EditButton().tint(.textPrimary)
            }
        }
        .sheet(item: $editing) { occasion in
            OccasionSheet(mode: .edit(occasion))
        }
        .sheet(isPresented: $showNew) {
            OccasionSheet(mode: .new(item: nil))
        }
        .onAppear {
            Occasion.ensureBuiltIn(in: modelContext)
            #if DEBUG
            // `-openOccasions new|<name>` on launch opens that sheet, for screenshots.
            switch UserDefaults.standard.string(forKey: "openOccasions") {
            case "new": showNew = true
            case let name?: editing = occasions.first { $0.name == name }
            case nil: break
            }
            #endif
        }
    }

    private func row(_ occasion: Occasion) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(occasion.name)
                        .font(.rowTitle)
                        .foregroundStyle(occasion.isHidden ? .textSecondary : .textPrimary)
                        .lineLimit(1)
                    if isDefault(occasion) {
                        Text("DEFAULT")
                            .font(.caption2.weight(.bold))
                            .tracking(0.3)
                            .foregroundStyle(.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.surfaceRaised, in: .capsule)
                    }
                }
                Text(subtitle(occasion))
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.textTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    /// The one shown as default: sync could leave two flagged.
    private func isDefault(_ occasion: Occasion) -> Bool {
        OccasionRules.defaultOccasion(occasions.map(\.info))?.id == occasion.id
    }

    /// e.g. "Weekdays · 9 items" or "Built in · 12 items · used when no rule applies".
    private func subtitle(_ occasion: Occasion) -> String {
        let builtInID = OccasionRules.builtIn(occasions.map(\.info))?.id
        let count = items.count { !$0.isSold && $0.occasionIDs(builtInID: builtInID).contains(occasion.id) }
        var parts: [String] = []
        if occasion.isBuiltIn { parts.append("Built in") }
        if occasion.isHidden {
            parts.append("Hidden from Today")
        } else if !occasion.isBuiltIn || !occasion.weekdays.isEmpty {
            parts.append(occasion.weekdays.shortSummary())
        }
        parts.append(count == 1 ? "1 item" : "\(count) items")
        if isDefault(occasion) { parts.append("used when no rule applies") }
        return parts.joined(separator: " · ")
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW TODAY PICKS ONE")
                .font(.label)
                .tracking(0.3)
            Text("1. An occasion whose day rule matches today, e.g. Office on weekdays.")
            Text("2. Otherwise your default occasion.")
            Text("You can always switch on Today. That choice lasts for the day.")
        }
        .font(.footnote)
        .foregroundStyle(.textSecondary)
        .padding(.top, 12)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = sorted
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, occasion) in reordered.enumerated() where occasion.sortOrder != index {
            occasion.sortOrder = index
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack { OccasionsView() }
        .modelContainer(for: [Item.self, DayLog.self, Occasion.self], inMemory: true)
        .preferredColorScheme(.dark)
}
