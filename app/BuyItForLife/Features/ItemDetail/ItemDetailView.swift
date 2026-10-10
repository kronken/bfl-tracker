import SwiftData
import SwiftUI

struct ItemDetailView: View {
    let item: Item

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showMarkSold = false
    @State private var confirmDelete = false

    var body: some View {
        let stats = item.stats
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                titleBlock
                costCard(stats)
                statTiles(stats)
                WearsPerMonthCard(months: stats.wearsPerMonth())
                if !item.isSold { dailyDriverCard }
                weatherCard
                    .opacity(item.isDailyDriver ? 0.45 : 1)
                if !item.notes.isEmpty { notesCard }
                actions
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(.appBackground)
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !item.isSold {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.snappy) { item.isFavorite.toggle() }
                        try? modelContext.save()
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                    }
                    .tint(.textPrimary)
                    .accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites")
                    .sensoryFeedback(.selection, trigger: item.isFavorite)
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
                    .tint(.textPrimary)
            }
        }
        .sheet(isPresented: $showEdit) {
            ItemFormView(mode: .edit(item))
        }
        .sheet(isPresented: $showMarkSold) {
            MarkSoldView(item: item)
        }
        .confirmationDialog("Delete \(item.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete item", role: .destructive, action: delete)
        } message: {
            Text("The item and its wear history are removed from all your devices. This can’t be undone.")
        }
    }

    // MARK: Sections

    private var hero: some View {
        ItemImageView(
            content: ItemImageContent(
                imageData: item.usesCutout ? item.photoCutout : item.photoOriginal,
                isCutout: item.usesCutout,
                tintHex: item.tintHex,
                name: item.name,
                category: item.category
            ),
            cornerRadius: Radius.card,
            iconSize: 56
        )
        .frame(height: 280)
        .overlay(alignment: .bottomTrailing) {
            GlassIconButton(systemImage: "camera", accessibilityLabel: "Change photo") { showEdit = true }
                .padding(12)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary)
            Text(metaLine)
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
            if item.isInactive && !item.isSold {
                Text("Inactive · not suggested on Today")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            if item.isFavorite && !item.isSold {
                Text(item.isDailyDriver ? "Favorite" : "Favorite · listed first on Today when the weather fits")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var metaLine: String {
        var parts = [
            item.category.title,
            "Bought \(item.boughtSecondHand ? "second-hand" : "new"), \(item.purchaseDate.formatted(date: .abbreviated, time: .omitted))",
            Money.format(cents: item.purchasePriceCents),
        ]
        if let soldDate = item.soldDate {
            parts.append("Sold \(Money.format(cents: item.soldPriceCents ?? 0)) on \(soldDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private func costCard(_ stats: ItemStats) -> some View {
        let target = settings.paidOffTargetCents
        let paidOff = stats.isPaidOff(targetCents: target)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((item.isSold ? "Final cost per wear" : "Cost per wear").uppercased())
                    .font(.label)
                    .tracking(0.3)
                    .foregroundStyle(.textSecondary)
                Spacer()
                if paidOff { PaidOffBadge() }
            }
            Text(stats.costPerWearCents.map { Money.format(fractionalCents: $0) } ?? Money.format(cents: stats.netCostCents))
                .font(.heroNumber)
                .foregroundStyle(.accentGold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(costExplanation(stats, target: target, paidOff: paidOff))
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
        }
        .card()
    }

    private func costExplanation(_ stats: ItemStats, target: Int, paidOff: Bool) -> String {
        let targetText = Money.format(fractionalCents: Double(target))
        if stats.wearCount == 0 {
            return "Not worn yet. Each wear brings the cost down."
        }
        if item.isSold {
            return "\(Money.format(cents: stats.netCostCents)) net over \(wears(stats.wearCount))."
        }
        if paidOff, let wear = stats.paidOffAtWear(targetCents: target) {
            return wear <= stats.priorWearCount
                ? "Under your \(targetText) target."
                : "Under your \(targetText) target since wear \(wear)."
        }
        let remaining = stats.wearsUntilPaidOff(targetCents: target) ?? 0
        return "\(remaining) more \(remaining == 1 ? "wear" : "wears") to reach your \(targetText) target."
    }

    private func statTiles(_ stats: ItemStats) -> some View {
        HStack(spacing: 12) {
            StatTile(value: stats.wearCount.formatted(), label: "Wears")
            StatTile(value: stats.daysOwned().formatted(), label: "Days owned")
            StatTile(value: lastWornText(stats), label: "Last worn")
        }
    }

    private func lastWornText(_ stats: ItemStats) -> String {
        switch stats.daysSinceLastWorn() {
        case nil: "–"
        case 0: "Today"
        case 1: "1 day"
        case let days?: "\(days) days"
        }
    }

    private var dailyDriverCard: some View {
        ToggleRow(
            label: "Daily driver",
            detail: item.isDailyDriver
                ? "Pre-selected every day. Weather is ignored."
                : "For things you wear every day: watch, belt, wallet.",
            isOn: Binding(
                get: { item.isDailyDriver },
                set: { newValue in
                    withAnimation(.snappy) { item.isDailyDriver = newValue }
                    try? modelContext.save()
                }
            )
        )
        .padding(.horizontal, -4)
        .card(padding: nil)
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weather")
                .font(.rowTitle)
                .foregroundStyle(.textPrimary)
            VStack(spacing: 6) {
                TemperatureRangeBar(min: item.minTempC, max: item.maxTempC)
                HStack {
                    Text(Temperature.format(celsius: ItemDraft.tempLowest))
                    Spacer()
                    Text("\(Temperature.format(celsius: item.minTempC)) to \(Temperature.format(celsius: item.maxTempC))")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text(Temperature.format(celsius: ItemDraft.tempHighest))
                }
                .font(.label)
                .monospacedDigit()
                .foregroundStyle(.textSecondary)
            }
            let chosen = WeatherConditions.options.filter { item.conditions.contains($0.condition) }
            if !chosen.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(chosen, id: \.condition.rawValue) { option in
                        Text(option.title)
                            .font(.rowDetail)
                            .foregroundStyle(.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(.fillSelected, in: .capsule)
                            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
                    }
                }
            }
            Text("Shown first on Today when the forecast is in range.")
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
        }
        .card()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(.label)
                .tracking(0.3)
                .foregroundStyle(.textSecondary)
            Text(item.notes)
                .font(.body)
                .foregroundStyle(.textPrimary)
        }
        .card()
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if !item.isSold {
                Button {
                    showMarkSold = true
                } label: {
                    Label("Mark as sold", systemImage: "tag")
                }
                .buttonStyle(.secondary)
            }
            Button("Delete item", role: .destructive) { confirmDelete = true }
                .font(.body)
                .foregroundStyle(.destructive)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .padding(.top, 8)
    }

    private func wears(_ count: Int) -> String {
        count == 1 ? "1 wear" : "\(count.formatted()) wears"
    }

    private func delete() {
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Pieces

struct PaidOffBadge: View {
    var body: some View {
        Label("Paid off", systemImage: "checkmark")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.positive)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(.positive.opacity(0.14), in: .capsule)
    }
}

/// A small card with a number and an uppercase label, e.g. "412 WEARS".
struct StatTile: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.number(.title2))
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.label)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.stroke, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Bars for logged wears in each of the last 12 months.
struct WearsPerMonthCard: View {
    var months: [MonthCount]

    private let barAreaHeight: CGFloat = 96

    var body: some View {
        let peak = months.map(\.count).max() ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Wears per month")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("Last 12 months")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(months, id: \.monthStart) { month in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(month.count > 0 ? AnyShapeStyle(.dataBlue) : AnyShapeStyle(.surfaceRaised))
                        .frame(height: peak > 0 ? max(3, barAreaHeight * CGFloat(month.count) / CGFloat(peak)) : 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: barAreaHeight, alignment: .bottom)
            HStack(spacing: 6) {
                ForEach(months, id: \.monthStart) { month in
                    Text(month.monthStart.formatted(.dateTime.month(.narrow)))
                        .font(.label)
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            Text(caption(peak: peak))
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wears per month, last 12 months")
        .accessibilityValue(months.map { "\($0.monthStart.formatted(.dateTime.month(.wide))): \($0.count)" }.joined(separator: ", "))
    }

    private func caption(peak: Int) -> String {
        guard peak > 0, let best = months.last(where: { $0.count == peak }) else {
            return "Log what you wear on Today to see it here."
        }
        let month = best.monthStart.formatted(.dateTime.month(.wide))
        return "Most worn in \(month): \(peak) \(peak == 1 ? "wear" : "wears")."
    }
}
