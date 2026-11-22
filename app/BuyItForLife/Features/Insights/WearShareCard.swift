import SwiftData
import SwiftUI

/// "What you wore": per month, each item's share of a category's wears as a
/// full-height stacked bar. Footwear, Bottoms and Outerwear, where you mostly
/// wear one item a day. Tap a month to see its split.
struct WearShareCard: View {
    var items: [Item]

    @Query private var categories: [ClothingCategory]
    @AppStorage("wearShareCategory") private var selectedKey = StarterCategory.footwear.rawValue
    @State private var selectedMonth: Int?

    static let categoryKeys: [StarterCategory] = [.footwear, .bottoms, .outerwear]

    private let plotHeight: CGFloat = 140
    private let axisWidth: CGFloat = 34
    private let gap: CGFloat = 1.5

    /// The three categories that still exist, in the order above; a renamed
    /// one keeps its new name.
    private var shownCategories: [ClothingCategory] {
        Self.categoryKeys.compactMap { key in categories.first { $0.seedKey == key.rawValue } }
    }

    var body: some View {
        let choices = shownCategories
        let category = choices.first { $0.seedKey == selectedKey } ?? choices.first
        let share = category.map { Self.share(of: $0, items: items) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("What you wore")
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("Last 12 months")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            HStack(spacing: 8) {
                ForEach(choices) { choice in
                    Chip(title: choice.name, isOn: choice.id == category?.id, height: 36) {
                        selectedKey = choice.seedKey ?? ""
                        selectedMonth = nil
                    }
                }
            }
            if let share, !share.isEmpty {
                chart(share)
                breakdown(share)
                Text(selectedMonth == nil ? "Each month is its share of wears. Tap a month to see it."
                                          : "Tap the month again to see the whole year.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
            } else {
                Text("No \(category?.name.lowercased() ?? "items") logged in the last 12 months.")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
        }
        .card()
    }

    static func share(of category: ClothingCategory, items: [Item]) -> WearShare {
        let entries = items.filter { $0.category?.id == category.id }
            .map { WearShareEntry(id: $0.id, name: $0.name, dayKeys: $0.loggedDayKeys) }
        return WearShare(entries: entries)
    }

    // MARK: Chart

    private func chart(_ share: WearShare) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                gridline("100%", at: 0)
                gridline("50%", at: plotHeight / 2)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(share.months.enumerated()), id: \.offset) { month, _ in
                        bar(share, month: month)
                    }
                }
                .frame(height: plotHeight)
                .padding(.trailing, axisWidth + 6)
            }
            .frame(height: plotHeight)
            HStack(spacing: 6) {
                ForEach(Array(share.months.enumerated()), id: \.offset) { month, start in
                    Text(start.formatted(.dateTime.month(.narrow)))
                        .font(.label)
                        .foregroundStyle(selectedMonth == month ? .textPrimary : .textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, axisWidth + 6)
        }
        .padding(.top, 6)
    }

    private func gridline(_ label: String, at y: CGFloat) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(.clear)
                .frame(height: 1)
                .overlay {
                    Line().stroke(.stroke, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            Text(label)
                .font(.number(.caption2, weight: .regular))
                .foregroundStyle(.textSecondary)
                .frame(width: axisWidth, alignment: .leading)
        }
        .frame(height: 12)
        .offset(y: y - 6)
        .accessibilityHidden(true)
    }

    private func bar(_ share: WearShare, month: Int) -> some View {
        let parts = share.series.filter { $0.counts[month] > 0 }
        let usable = plotHeight - gap * CGFloat(max(0, parts.count - 1))
        let isSelected = selectedMonth == month
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedMonth = isSelected ? nil : month }
        } label: {
            VStack(spacing: gap) {
                // Most worn at the bottom.
                ForEach(parts.reversed()) { series in
                    Rectangle()
                        .fill(color(series))
                        .frame(height: usable * share.share(series, month: month))
                }
            }
            .frame(maxWidth: .infinity, minHeight: plotHeight, maxHeight: plotHeight, alignment: .bottom)
            .background(.surfaceRaised)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.5), lineWidth: 1.5).padding(-3)
                }
            }
            .opacity(selectedMonth == nil || isSelected ? 1 : 0.35)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(share.months[month].formatted(.dateTime.month(.wide).year()))
        .accessibilityValue(parts.isEmpty ? "Nothing logged"
            : parts.map { "\($0.name) \(percent(share.share($0, month: month)))" }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Breakdown

    private func breakdown(_ share: WearShare) -> some View {
        let rows: [(series: WearShare.Series, days: Int, share: Double)]
        let title: String
        let total: Int
        if let month = selectedMonth {
            total = share.total(month: month)
            rows = share.series.filter { $0.counts[month] > 0 }
                .map { ($0, $0.counts[month], share.share($0, month: month)) }
            title = share.months[month].formatted(.dateTime.month(.wide).year())
        } else {
            total = share.total
            rows = share.series.map { ($0, $0.total, total > 0 ? Double($0.total) / Double(total) : 0) }
            title = "Last 12 months"
        }
        return VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title, trailing: "\(Self.days(total)) logged")
                .padding(.horizontal, -4)
            if rows.isEmpty {
                Text("Nothing logged this month.")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
            ForEach(rows, id: \.series.id) { row in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(row.series))
                        .frame(width: 10, height: 10)
                    Text(row.series.name)
                        .font(.rowDetail)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.days(row.days))
                        .font(.number(.subheadline, weight: .regular))
                        .foregroundStyle(.textSecondary)
                    Text(percent(row.share))
                        .font(.number(.subheadline, weight: .regular))
                        .foregroundStyle(.textPrimary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Helpers

    private func color(_ series: WearShare.Series) -> Color {
        series.colorIndex.map { OriginCard.palette[$0 % OriginCard.palette.count] } ?? OriginCard.grey
    }

    private func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    static func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}
