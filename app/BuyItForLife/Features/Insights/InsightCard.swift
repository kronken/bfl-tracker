import SwiftUI

/// The day's insight at the top of Insights: category, title, detail.
struct InsightCard: View {
    var insight: DailyInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                Text((insight.category?.title ?? "Insight").uppercased())
                    .tracking(0.3)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.accentGold)
            Text(insight.title ?? "")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = insight.detail {
                Text(detail)
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["Insight, \(insight.category?.title ?? "")", insight.title, insight.detail]
            .compactMap { $0 }.joined(separator: ". "))
    }
}

/// The day's insight as one line on Today, under the weather card.
struct TodayInsightLine: View {
    var insight: DailyInsight
    var onOpen: () -> Void
    var onHide: () -> Void

    /// Title and detail together when they're short enough for two lines.
    private var text: String {
        let title = insight.title ?? ""
        guard let detail = insight.detail, title.count + detail.count <= 90 else { return title }
        return "\(title) \(detail)"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.accentGold)
                Text(text)
                    .font(.rowDetail)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentGold.opacity(0.08), in: .rect(cornerRadius: Radius.tile))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Color.accentGold.opacity(0.22), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: Radius.tile))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Hide for today", systemImage: "eye.slash", action: onHide)
        }
        .accessibilityLabel("Insight. \(text)")
        .accessibilityHint("Opens Insights")
    }
}
