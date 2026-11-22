import Charts
import SwiftUI

/// "Where it comes from": owned items by brand, brand country, country of
/// manufacture or store, as a donut with a legend.
struct OriginCard: View {
    var entries: [OriginEntry]
    /// Feel-good mode: always count items, never show money.
    var hidesTotals: Bool

    @AppStorage("originDimension") private var dimension: OriginDimension = .brandCountry
    @AppStorage("originMetric") private var storedMetric: OriginMetric = .value

    /// Slice colours in order; "Other" and "Not set" are grey, "Gifts" a lighter grey.
    static let palette: [Color] = [Color(hex: 0xD6AD66), Color(hex: 0x7D9CF0), Color(hex: 0x5FBFA8),
                                   Color(hex: 0xC38FDC), Color(hex: 0xE07A5F)]
    static let grey = Color(hex: 0x6E6E73)
    static let giftGrey = Color(hex: 0xA1A1A6)

    private var metric: OriginMetric { hidesTotals ? .items : storedMetric }

    var body: some View {
        let breakdown = OriginBreakdown(entries: entries, dimension: dimension, metric: metric)
        let colors = Self.colors(for: breakdown.slices)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Where it comes from")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                if !hidesTotals {
                    SegmentedControl(options: [(OriginMetric.items, "Items"), (OriginMetric.value, "Value")],
                                     selection: $storedMetric)
                        .frame(width: 124)
                }
            }
            SegmentedControl(options: OriginDimension.allCases.map { ($0, $0.title) }, selection: $dimension)

            HStack(spacing: 16) {
                donut(breakdown, colors: colors)
                legend(breakdown, colors: colors)
            }

            Text(footnote(breakdown))
                .font(.footnote)
                .foregroundStyle(.textSecondary)
        }
        .card()
    }

    // MARK: Chart

    private func donut(_ breakdown: OriginBreakdown, colors: [String: Color]) -> some View {
        Chart(breakdown.slices) { slice in
            SectorMark(angle: .value("Amount", slice.amount), innerRadius: .ratio(0.64), angularInset: 1.5)
                .cornerRadius(2)
                .foregroundStyle(colors[slice.id] ?? Self.grey)
        }
        .chartLegend(.hidden)
        .frame(width: 132, height: 132)
        .overlay {
            VStack(spacing: 0) {
                Text(centerValue(breakdown))
                    .font(.number(.headline, weight: .bold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(metric == .items ? "items" : "value")
                    .font(.label)
                    .foregroundStyle(.textSecondary)
            }
            .frame(width: 80)
        }
        .animation(.snappy, value: breakdown)
        // The legend reads out every slice; the picture adds nothing for VoiceOver.
        .accessibilityHidden(true)
    }

    private func legend(_ breakdown: OriginBreakdown, colors: [String: Color]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(breakdown.slices) { slice in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colors[slice.id] ?? Self.grey)
                        .frame(width: 10, height: 10)
                    Text(slice.name)
                        .font(.rowDetail)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(percent(slice.share))
                        .font(.number(.subheadline, weight: .regular))
                        .foregroundStyle(.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(slice.name)
                .accessibilityValue("\(amountText(slice.amount)), \(percent(slice.share))")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Text

    private func centerValue(_ breakdown: OriginBreakdown) -> String {
        metric == .items ? Int(breakdown.total).formatted() : Money.format(cents: Int((breakdown.total / 100).rounded()) * 100)
    }

    private func amountText(_ amount: Double) -> String {
        if metric == .items {
            let count = Int(amount)
            return count == 1 ? "1 item" : "\(count) items"
        }
        return Money.format(cents: Int((amount / 100).rounded()) * 100)
    }

    private func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    private func footnote(_ breakdown: OriginBreakdown) -> String {
        let items = breakdown.itemCount == 1 ? "1 item" : "\(breakdown.itemCount) items"
        var text = "\(dimension.countLabel(breakdown.groupCount).capitalizedFirst) across \(items)."
        if dimension == .store && breakdown.hasGifts { text += " Gifts are shown on their own." }
        if metric == .value { text += " Value includes repairs; gifts count at their value." }
        return text
    }

    /// Palette colours go to named slices in order; the rest are grey.
    static func colors(for slices: [OriginSlice]) -> [String: Color] {
        var colors: [String: Color] = [:]
        var next = 0
        for slice in slices {
            if slice.kind == .named, next < palette.count {
                colors[slice.id] = palette[next]
                next += 1
            } else if slice.kind == .gifts {
                colors[slice.id] = giftGrey
            } else {
                colors[slice.id] = grey
            }
        }
        return colors
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
