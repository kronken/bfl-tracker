import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Item.purchaseDate) private var items: [Item]

    @State private var cumulativeSpend = false
    @State private var bestFirst = true

    /// Items without a logged wear for this long get the "Unworn" tag.
    static let neglectedAfterDays = 90

    var body: some View {
        NavigationStack {
            TabScreen {
                ScreenHeader(subtitle: items.isEmpty ? nil : subtitle, title: "Insights")
                if items.isEmpty {
                    PlaceholderCard(text: "Add items in Wardrobe to see what your clothes cost per day and per wear.")
                } else {
                    let wardrobe = WardrobeStats(items: items.map(\.stats))
                    CostPerDayCard(wardrobe: wardrobe)
                    totals(wardrobe)
                    SpendPerYearCard(points: wardrobe.spendPerYear(), cumulative: $cumulativeSpend)
                    ranking
                }
            }
            .navigationTitle("Insights")
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
        }
    }

    private var subtitle: String {
        let owned = items.count { !$0.isSold }
        let sold = items.count - owned
        var parts = ["\(owned) owned"]
        if sold > 0 { parts.append("\(sold) sold") }
        if let first = items.first?.purchaseDate {
            parts.append("since \(first.formatted(.dateTime.month(.abbreviated).year()))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Totals

    private func totals(_ wardrobe: WardrobeStats) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            TotalTile(label: "Total spent", value: Money.format(cents: wardrobe.totalSpentCents),
                      detail: wardrobe.repairsCents > 0 ? "incl. \(Money.format(cents: wardrobe.repairsCents)) repairs" : nil)
            TotalTile(label: "Back from sales", value: Money.format(cents: wardrobe.backFromSalesCents))
            TotalTile(label: "Total wears", value: wardrobe.wearCount.formatted())
            TotalTile(label: "Avg cost / wear",
                      value: wardrobe.averageCostPerWearCents.map { Money.format(fractionalCents: $0) } ?? "–")
        }
    }

    // MARK: Ranking

    private var ranked: [Item] {
        // Each item's cost per wear is worked out once, not on every comparison.
        // Never-worn items have no cost per wear; they rank as worst value.
        let keyed = items.filter { !$0.isSold }.map { ($0, $0.stats.costPerWearCents ?? .infinity) }
        return keyed.sorted { bestFirst ? $0.1 < $1.1 : $0.1 > $1.1 }.map(\.0)
    }

    private var ranking: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cost per wear")
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Button {
                    withAnimation(.snappy) { bestFirst.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(bestFirst ? "Best value first" : "Worst value first")
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.rowDetail)
                    .foregroundStyle(.dataBlue)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if ranked.isEmpty {
                PlaceholderCard(text: "Everything you owned has been sold.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: item) {
                            RankingRow(item: item, targetCents: settings.paidOffTargetCents)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: nil)
            }

            Text("Paid off = under \(Money.format(fractionalCents: Double(settings.paidOffTargetCents))) per wear. Change the target in Settings.")
                .font(.caption)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 4)
        }
        .padding(.top, 8)
    }
}

// MARK: - Cards

/// The headline figure with its year-by-year line.
private struct CostPerDayCard: View {
    var wardrobe: WardrobeStats

    var body: some View {
        let now = wardrobe.costPerDayCents() ?? 0
        let history = wardrobe.costPerDayHistory()
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WARDROBE COST PER DAY")
                    .font(.label)
                    .tracking(0.3)
                    .foregroundStyle(.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Money.format(fractionalCents: now))
                        .font(.heroNumber)
                        .foregroundStyle(.accentGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("/ day")
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                }
                Text(summary(now: now))
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            if history.count >= 2 {
                CostLineChart(points: history)
                    .frame(height: 150)
                    .padding(.top, 4)
            }
        }
        .card()
    }

    private func summary(now: Double) -> String {
        let days = wardrobe.daysTracked()
        var text = "\(Money.format(cents: wardrobe.netCostCents)) net over \(days.formatted()) \(days == 1 ? "day" : "days")"
        guard let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now),
              let then = wardrobe.costPerDayCents(asOf: yearAgo)
        else { return text }
        let change = now - then
        if abs(change) >= 0.5 {
            text += " · \(change < 0 ? "down" : "up") \(Money.format(fractionalCents: abs(change))) on last year"
        }
        return text
    }
}

/// Cost per day at the end of each year, ending with now.
private struct CostLineChart: View {
    var points: [YearPoint]

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let size = geometry.size
                let values = points.map(\.cents)
                let low = values.min() ?? 0
                let high = values.max() ?? 1
                let span = max(high - low, 1)
                let inset: CGFloat = 8
                let position = { (index: Int) -> CGPoint in
                    let x = inset + (size.width - inset * 2) * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let y = 16 + (size.height - 32) * CGFloat(1 - (values[index] - low) / span)
                    return CGPoint(x: x, y: y)
                }
                ZStack(alignment: .topLeading) {
                    ForEach(0..<3, id: \.self) { line in
                        Path { path in
                            let y = 16 + (size.height - 32) * CGFloat(line) / 2
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        .stroke(.stroke, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }
                    Path { path in
                        path.move(to: position(0))
                        for index in points.indices.dropFirst() { path.addLine(to: position(index)) }
                    }
                    .stroke(.dataBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    Circle().fill(.dataBlue).frame(width: 8, height: 8).position(position(0))
                    Circle()
                        .fill(.dataBlue)
                        .frame(width: 10, height: 10)
                        .overlay { Circle().stroke(.surface, lineWidth: 2) }
                        .position(position(points.count - 1))
                    valueLabel(values[0], color: .textSecondary)
                        .position(x: position(0).x + 26, y: position(0).y + 16)
                    valueLabel(values[values.count - 1], color: .textPrimary)
                        .position(x: position(points.count - 1).x - 26, y: position(points.count - 1).y - 16)
                }
            }
            HStack {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Text(yearLabel(point, isFirst: index == 0))
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.label)
            .monospacedDigit()
            .foregroundStyle(.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cost per day by year")
        .accessibilityValue(points.map { "\(yearLabel($0, isFirst: true)): \(Money.format(fractionalCents: $0.cents))" }
            .joined(separator: ", "))
    }

    private func valueLabel(_ cents: Double, color: Color) -> some View {
        Text(Money.format(fractionalCents: cents))
            .font(.number(.caption))
            .foregroundStyle(color)
            .fixedSize()
    }
}

/// "2020" for the first year, "’21" for later ones, "Now" for the current point.
private func yearLabel(_ point: YearPoint, isFirst: Bool) -> String {
    if point.isNow { return "Now" }
    return isFirst ? String(point.year) : "’" + String(point.year % 100).leftPadded(to: 2)
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}

private struct TotalTile: View {
    var label: String
    var value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.label)
                .tracking(0.3)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.number(.title2))
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.stroke, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Purchases per year, or the running total.
struct SpendPerYearCard: View {
    var points: [YearPoint]
    @Binding var cumulative: Bool

    private let barAreaHeight: CGFloat = 110

    var body: some View {
        let values = shownValues
        let peak = values.max() ?? 0
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Spent per year")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                SegmentedControl(options: [(false, "Yearly"), (true, "Total")], selection: $cumulative)
                    .frame(width: 150)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    VStack(spacing: 4) {
                        Text(Self.compact(value))
                            .font(.number(.caption))
                            .foregroundStyle(.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.dataBlue)
                            .frame(height: peak > 0 ? max(4, barAreaHeight * CGFloat(value / peak)) : 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: barAreaHeight + 24, alignment: .bottom)
            HStack(spacing: 8) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Text(index == 0 ? String(point.year) : "’" + String(point.year % 100).leftPadded(to: 2))
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.label)
            .foregroundStyle(.textSecondary)
            .padding(.top, -8)
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    private var shownValues: [Double] {
        guard cumulative else { return points.map(\.cents) }
        var running = 0.0
        return points.map { running += $0.cents; return running }
    }

    /// "€629" / "629 €", and "$1.3K" / "1,3K €": the number is shortened but
    /// the currency symbol stays where the locale puts it.
    static func compact(_ cents: Double, locale: Locale = .current) -> String {
        let euros = cents / 100
        guard euros >= 1000 else { return Money.format(cents: Int(cents.rounded()), locale: locale) }
        let number = euros.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
        return Money.format(cents: 0, locale: locale).replacingOccurrences(of: "0", with: number)
    }
}

/// One owned item in the cost-per-wear ranking.
private struct RankingRow: View {
    let item: Item
    var targetCents: Int

    var body: some View {
        let stats = item.stats
        HStack(spacing: 12) {
            ItemImageView(content: item.thumbnailContent, cornerRadius: Radius.thumb, iconSize: 20)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text("\(stats.wearCount == 1 ? "1 wear" : "\(stats.wearCount) wears") · \(Money.format(cents: stats.totalCostCents))")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(stats.costPerWearCents.map { Money.format(fractionalCents: $0) } ?? "–")
                    .font(.number(.body))
                    .foregroundStyle(.textPrimary)
                if let unworn = item.daysUnworn(), unworn >= InsightsView.neglectedAfterDays {
                    Text("Unworn \(unworn) d")
                        .font(.label)
                        .foregroundStyle(.warning)
                } else if stats.isPaidOff(targetCents: targetCents) {
                    Text("Paid off")
                        .font(.label)
                        .foregroundStyle(.positive)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    InsightsView()
        .environment(AppSettings())
        .modelContainer(for: [Item.self, DayLog.self], inMemory: true)
        .preferredColorScheme(.dark)
}
