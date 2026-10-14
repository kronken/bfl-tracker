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
    @State private var repairSheet: RepairSheetTarget?
    @State private var pieceSheet: PieceSheetTarget?

    /// Which repair sheet is open: a new repair or an existing one.
    private enum RepairSheetTarget: Identifiable {
        case new
        case edit(Repair)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let repair): repair.id.uuidString
            }
        }
    }

    /// Which pieces sheet is open.
    private enum PieceSheetTarget: Identifiable {
        case add, retire
        case edit(PieceEvent)

        var id: String {
            switch self {
            case .add: "add"
            case .retire: "retire"
            case .edit(let event): event.id.uuidString
            }
        }
    }

    var body: some View {
        let stats = item.stats
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                titleBlock
                costCard(stats)
                statTiles(stats)
                priceCard(stats)
                if item.isMultiPiece { pieceLog }
                if !(item.repairs ?? []).isEmpty { repairsSection(stats) }
                WearsPerMonthCard(months: stats.wearsPerMonth())
                weatherCard
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
        .sheet(item: $repairSheet) { target in
            switch target {
            case .new: RepairSheet(item: item)
            case .edit(let repair): RepairSheet(item: item, repair: repair)
            }
        }
        .sheet(item: $pieceSheet) { target in
            switch target {
            case .add: PieceEventSheet(item: item, mode: .add)
            case .retire: PieceEventSheet(item: item, mode: .retire)
            case .edit(let event): PieceEventSheet(item: item, mode: .edit(event))
            }
        }
        #if DEBUG
        // `-openItemSheet repair|editRepair|add|retire` on launch, for screenshots.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "openItemSheet") {
            case "repair": repairSheet = .new
            case "editRepair": if let repair = item.sortedRepairs.first { repairSheet = .edit(repair) }
            case "add": pieceSheet = .add
            case "retire": pieceSheet = .retire
            default: break
            }
        }
        #endif
        .confirmationDialog("Delete \(item.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete item", role: .destructive, action: delete)
        } message: {
            Text("The item, its repairs and its wear history are removed from all your devices. This can’t be undone.")
        }
    }

    // MARK: Header

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
        .overlay(alignment: .bottomLeading) {
            if item.isMultiPiece { PieceCountBadge(count: item.piecesInUse, large: true).padding(12) }
        }
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
            let labels = itemLabels
            if !labels.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(labels, id: \.title) { label in
                        ItemLabel(title: label.title, systemImage: label.symbol)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 4)
    }

    private var itemLabels: [(title: String, symbol: String)] {
        guard !item.isSold else { return [] }
        var labels: [(String, String)] = []
        if item.isGift { labels.append(("Gift", "gift")) }
        if item.isFavorite { labels.append(("Favorite", "star.fill")) }
        if item.isDailyDriver { labels.append(("Daily driver", "arrow.triangle.2.circlepath")) }
        if item.isMultiPiece { labels.append(("Identical pieces", "square.on.square")) }
        if item.isInactive { labels.append(("Inactive", "eye.slash")) }
        return labels
    }

    private var metaLine: String {
        let date = item.purchaseDate.formatted(date: .abbreviated, time: .omitted)
        var parts = [
            item.category.title,
            item.isGift ? (item.isMultiPiece ? "Gift, first received \(date)" : "Gift, received \(date)")
                : item.isMultiPiece ? "First bought \(date)" : "Bought \(item.boughtSecondHand ? "second-hand" : "new"), \(date)",
        ]
        if let soldDate = item.soldDate {
            parts.append("Sold \(Money.format(cents: item.soldPriceCents ?? 0)) on \(soldDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Cost

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
        if item.isMultiPiece {
            let pieces = item.piecesBought == 1 ? "1 piece" : "\(item.piecesBought) pieces"
            let days = stats.wearCount == 1 ? "1 day" : "\(stats.wearCount.formatted()) days"
            return "\(Money.format(cents: stats.totalCostCents)) for \(pieces) over \(days) worn. You log the set, not which piece."
        }
        let repairs = stats.repairsCents > 0 ? "Includes \(Money.format(cents: stats.repairsCents)) of repairs. " : ""
        let targetText = Money.format(fractionalCents: Double(target))
        if stats.wearCount == 0 {
            return repairs + "Not worn yet. Each wear brings the cost down."
        }
        if item.isSold {
            return repairs + "\(Money.format(cents: stats.netCostCents)) net over \(wears(stats.wearCount))."
        }
        if paidOff, let wear = stats.paidOffAtWear(targetCents: target) {
            return repairs + (wear <= stats.priorWearCount
                ? "Under your \(targetText) target."
                : "Under your \(targetText) target since wear \(wear).")
        }
        let remaining = stats.wearsUntilPaidOff(targetCents: target) ?? 0
        return repairs + "\(remaining) more \(remaining == 1 ? "wear" : "wears") to reach your \(targetText) target."
    }

    private func statTiles(_ stats: ItemStats) -> some View {
        HStack(spacing: 12) {
            if item.isMultiPiece {
                StatTile(value: item.piecesInUse.formatted(), label: "In use")
                StatTile(value: stats.wearCount.formatted(), label: "Wears")
            } else {
                StatTile(value: stats.wearCount.formatted(), label: "Wears")
                StatTile(value: stats.daysOwned().formatted(), label: "Days owned")
            }
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

    /// Original / repairs / total, or for identical pieces bought / retired / total.
    private func priceCard(_ stats: ItemStats) -> some View {
        let repairCount = (item.repairs ?? []).count
        let figures: [(String, String, Bool)] = item.isMultiPiece
            ? [("\(item.piecesBought)", "BOUGHT", false), ("\(item.piecesRetired)", "RETIRED", false),
               (Money.format(cents: stats.totalCostCents), "TOTAL COST", true)]
            : [(Money.format(cents: stats.purchasePriceCents), item.isGift ? "GIFT VALUE" : "ORIGINAL", false),
               (repairCount == 0 ? "—" : "+\(Money.format(cents: stats.repairsCents))",
                repairCount == 0 ? "REPAIRS" : "REPAIRS (\(repairCount))", false),
               (Money.format(cents: stats.totalCostCents), "TOTAL COST", true)]
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(figures, id: \.1) { value, label, emphasised in
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.number(.title3))
                        .foregroundStyle(emphasised ? .textPrimary : .textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(label)
                        .font(.label)
                        .foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(padding: nil)
        .accessibilityElement(children: .combine)
    }

    // MARK: Repairs and pieces

    private func repairsSection(_ stats: ItemStats) -> some View {
        let repairs = item.sortedRepairs
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Repairs")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(repairs.count) · \(Money.format(cents: stats.repairsCents))")
                    .font(.rowDetail)
                    .monospacedDigit()
                    .foregroundStyle(.textSecondary)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(repairs.enumerated()), id: \.element.id) { index, repair in
                    if index > 0 { RowDivider() }
                    Button { repairSheet = .edit(repair) } label: { RepairRow(repair: repair) }
                        .buttonStyle(.plain)
                }
            }
            .card(padding: nil)
        }
    }

    private var pieceLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Log")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("Newest first")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                let events = item.sortedPieceEvents
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { RowDivider() }
                    Button { pieceSheet = .edit(event) } label: { PieceEventRow(event: event) }
                        .buttonStyle(.plain)
                }
            }
            .card(padding: nil)
        }
    }

    // MARK: Weather and notes

    @ViewBuilder
    private var weatherCard: some View {
        if item.isDailyDriver {
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Text("Any weather. As a daily driver it’s pre-selected on Today every day, whatever the forecast.")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            .card()
        } else {
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
                Text(item.isMultiPiece
                     ? "Listed under Basics on Today when the forecast is in range."
                     : "Shown first on Today when the forecast is in range.")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            .card()
        }
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

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 8) {
            if !item.isSold {
                if item.isMultiPiece {
                    HStack(spacing: 8) {
                        Button { pieceSheet = .add } label: { Label("Add more", systemImage: "plus") }
                            .buttonStyle(.secondary)
                        Button { pieceSheet = .retire } label: { Label("Retire", systemImage: "minus") }
                            .buttonStyle(.secondary)
                            .disabled(item.piecesInUse == 0)
                    }
                }
                Button { repairSheet = .new } label: { Label("Repair", systemImage: "wrench.and.screwdriver") }
                    .buttonStyle(.secondary)
                if !item.isMultiPiece {
                    Button { showMarkSold = true } label: { Label("Mark as sold", systemImage: "tag") }
                        .buttonStyle(.secondary)
                }
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

/// A capsule on the item screen: "★ Favorite", "Daily driver", "Identical pieces".
struct ItemLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.textPrimary)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(.fillSelected, in: .capsule)
        .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
    }
}

/// "× 6" over a photo: how many identical pieces are in use.
struct PieceCountBadge: View {
    var count: Int
    var large = false

    var body: some View {
        Text(count == 0 ? "All retired" : "× \(count)")
            .font(count == 0 ? .caption.weight(.semibold) : .number(large ? .body : .footnote, weight: .bold))
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, large ? 12 : 8)
            .padding(.vertical, large ? 4 : 2)
            .background(.black.opacity(0.55), in: .capsule)
            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
            .accessibilityLabel(count == 0 ? "All pieces retired" : "\(count) pieces in use")
    }
}

/// One repair: wrench, name, "date · description", price, chevron.
struct RepairRow: View {
    let repair: Repair

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.textPrimary)
                .frame(width: 36, height: 36)
                .background(.surfaceRaised, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(repair.name)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text([repair.date.formatted(date: .abbreviated, time: .omitted), repair.details]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.format(cents: repair.priceCents))
                .font(.number(.body))
                .foregroundStyle(.textPrimary)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// One entry in an identical-pieces log: "+2 Bought 2" or "−1 Retired 1".
struct PieceEventRow: View {
    let event: PieceEvent

    var body: some View {
        let bought = event.kind == .bought
        HStack(spacing: 12) {
            Text(bought ? "+\(event.quantity)" : "−\(event.quantity)")
                .font(.number(.subheadline, weight: .bold))
                .foregroundStyle(bought ? .textPrimary : .textSecondary)
                .frame(width: 36, height: 36)
                .background(.surfaceRaised, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(bought ? "Bought \(event.quantity)" : "Retired \(event.quantity)")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Text(meta)
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if bought, let price = event.priceCents {
                Text(Money.format(cents: price))
                    .font(.number(.body))
                    .foregroundStyle(.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        let date = event.date.formatted(date: .abbreviated, time: .omitted)
        if event.kind == .retired { return [date, event.reason ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }
        guard let price = event.priceCents, event.quantity > 0 else { return date }
        return "\(date) · \(Money.format(fractionalCents: Double(price) / Double(event.quantity))) each"
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
