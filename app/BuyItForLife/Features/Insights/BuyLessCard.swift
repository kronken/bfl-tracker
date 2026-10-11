import SwiftUI

/// Days without buying, this month's and year's budget, and things bought
/// per year. Shown on Insights when buy-less goals are on.
struct BuyLessCard: View {
    var stats: BuyLessStats
    var goalDays: Int
    var monthlyLimitCents: Int
    var yearlyBudgetCents: Int
    var hidesTotals: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            streakHeader
            Rectangle().fill(.stroke).frame(height: 1)
            VStack(spacing: 10) {
                budgetRow(title: Date.now.formatted(.dateTime.month(.wide)),
                          spent: stats.spentThisMonthCents, limit: monthlyLimitCents,
                          bought: stats.boughtThisMonth, isYear: false)
                budgetRow(title: Date.now.formatted(.dateTime.year()),
                          spent: stats.spentThisYearCents, limit: yearlyBudgetCents,
                          bought: stats.boughtThisYear, isYear: true)
            }
            if stats.hasPurchases {
                Rectangle().fill(.stroke).frame(height: 1)
                perMonthChart
            }
        }
        .card()
    }

    // MARK: Streak

    private var reached: Bool { stats.isGoalReached(goalDays: goalDays) }

    private var streakHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.surfaceRaised, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, Double(stats.currentStreakDays) / Double(max(goalDays, 1))))
                    .stroke(reached ? AnyShapeStyle(.positive) : AnyShapeStyle(.dataBlue),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(stats.currentStreakDays.formatted())
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("DAYS")
                        .font(.label)
                        .foregroundStyle(.textSecondary)
                }
                .padding(12)
            }
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("WITHOUT BUYING")
                    .font(.label)
                    .tracking(0.3)
                    .foregroundStyle(.textSecondary)
                Text(BuyLessCopy.cheer(streak: stats.currentStreakDays, goalDays: goalDays))
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Text(BuyLessCopy.status(streak: stats.currentStreakDays, longest: stats.longestStreakDays,
                                        goalDays: goalDays))
                    .font(.rowDetail)
                    .foregroundStyle(reached ? .positive : .textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(stats.currentStreakDays) days without buying")
        }
    }

    // MARK: Budget

    private func budgetRow(title: String, spent: Int, limit: Int, bought: Int, isYear: Bool) -> some View {
        let progress = limit > 0 ? Double(spent) / Double(limit) : (spent > 0 ? 1 : 0)
        let caution = progress >= 0.8
        return VStack(spacing: 6) {
            HStack {
                Text(title)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text(budgetText(spent: spent, limit: limit, bought: bought, isYear: isYear, progress: progress))
                    .foregroundStyle(.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.rowDetail)
            GeometryReader { geometry in
                Capsule()
                    .fill(.surfaceRaised)
                    .overlay(alignment: .leading) {
                        Capsule()
                            // Over budget stays orange, never red.
                            .fill(caution ? AnyShapeStyle(.warning) : AnyShapeStyle(.dataBlue))
                            .frame(width: geometry.size.width * min(1, progress))
                    }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private func budgetText(spent: Int, limit: Int, bought: Int, isYear: Bool, progress: Double) -> String {
        if hidesTotals {
            let things = bought == 0 ? "Nothing bought" : bought == 1 ? "1 thing bought" : "\(bought) things bought"
            guard isYear else { return things }
            if progress > 1 { return "Over budget" }
            return bought == 0 || progress < 0.5 ? "\(things) · well under budget" : "On track"
        }
        if limit == 0 {
            return spent == 0 ? (isYear ? "No-buy year" : "No-buy month") : "\(Money.format(cents: spent)) over"
        }
        if spent > limit { return "\(Money.format(cents: spent - limit)) over" }
        let base = "\(Money.format(cents: spent)) of \(Money.format(cents: limit))"
        return isYear ? "\(base) · \(Money.format(cents: limit - spent)) left" : base
    }

    // MARK: Per month

    private var perMonthChart: some View {
        let months = stats.purchasesPerMonth
        let peak = months.map(\.count).max() ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("THINGS BOUGHT PER MONTH")
                .font(.label)
                .tracking(0.3)
                .foregroundStyle(.textSecondary)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(months.enumerated()), id: \.offset) { index, entry in
                    // This month in green while nothing has been bought in it.
                    let goodMonth = index == months.count - 1 && entry.count == 0
                    VStack(spacing: 4) {
                        Text(entry.count == 0 ? " " : "\(entry.count)")
                            .font(.number(.caption))
                            .foregroundStyle(.textSecondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(goodMonth ? AnyShapeStyle(.positive)
                                  : entry.count > 0 ? AnyShapeStyle(.dataBlue) : AnyShapeStyle(.surfaceRaised))
                            .frame(height: peak > 0 && entry.count > 0 ? max(3, 54 * CGFloat(entry.count) / CGFloat(peak)) : 3)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76, alignment: .bottom)
            HStack(spacing: 4) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, entry in
                    Text(entry.monthStart.formatted(.dateTime.month(.narrow)))
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.label)
            .foregroundStyle(.textSecondary)
            Text(BuyLessCopy.monthSummary(stats))
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
