import SwiftData
import SwiftUI

/// Month calendar for opening a past day. Days with something logged get a dot.
struct PickDaySheet: View {
    @Binding var selectedDay: Date

    @Environment(\.dismiss) private var dismiss
    @Query private var logs: [DayLog]

    @State private var month: Date = .now
    @State private var day: Date = .now

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Pick a day")
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }

            monthHeader
            grid
            summary

            Spacer(minLength: 0)

            Button(ctaTitle) {
                selectedDay = calendar.startOfDay(for: day)
                dismiss()
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .presentationDetents([.large])
        .presentationBackground(.surface)
        .presentationDragIndicator(.visible)
        .onAppear {
            day = selectedDay
            month = startOfMonth(selectedDay)
        }
    }

    // MARK: Month

    private var monthHeader: some View {
        HStack {
            monthButton("chevron.left", label: "Previous month", offset: -1, enabled: true)
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.rowTitle)
                .foregroundStyle(.textPrimary)
            Spacer()
            monthButton("chevron.right", label: "Next month", offset: 1, enabled: month < startOfMonth(.now))
        }
    }

    private func monthButton(_ symbol: String, label: String, offset: Int, enabled: Bool) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: offset, to: month) { month = next }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .textPrimary : .textTertiary)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let logged = Set(logs.filter { !($0.items ?? []).isEmpty }.map(\.dayKey))
        return VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.label)
                        .foregroundStyle(.textSecondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells.indices, id: \.self) { index in
                    if let date = cells[index] {
                        dayCell(date, logged: logged.contains(DayKey.make(for: date)))
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date, logged: Bool) -> some View {
        let isFuture = date > calendar.startOfDay(for: .now)
        let isSelected = calendar.isDate(date, inSameDayAs: day)
        let isToday = calendar.isDateInToday(date)
        return Button {
            day = date
        } label: {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.day()))
                    .font(.number(.body, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isFuture ? .textTertiary : .textPrimary)
                Circle()
                    .fill(logged && !isFuture ? AnyShapeStyle(.dataBlue) : AnyShapeStyle(.clear))
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isSelected ? AnyShapeStyle(.fillSelected) : AnyShapeStyle(.clear), in: .capsule)
            .overlay { if isSelected { Capsule().strokeBorder(.stroke, lineWidth: 1) } }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (logged ? ", logged" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Weekday initials starting from the locale's first day of the week.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's days, padded with nils so the 1st falls on its weekday.
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + days
    }

    // MARK: Selected day

    private var dayLogs: [DayLog] { logs.filter { $0.dayKey == DayKey.make(for: day) } }

    private var wornItems: [Item] {
        var seen = Set<UUID>()
        return dayLogs.flatMap { $0.items ?? [] }.filter { seen.insert($0.id).inserted }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayLabel)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Spacer()
                if let weather = dayLogs.lazy.compactMap(\.weather).first {
                    Text(weather.shortText)
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                        .monospacedDigit()
                }
            }
            if wornItems.isEmpty {
                Text("Nothing logged.")
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            } else {
                ForEach(wornItems) { item in
                    HStack(spacing: 12) {
                        ItemImageView(content: item.thumbnailContent, cornerRadius: Radius.thumb, iconSize: 16)
                            .frame(width: 32, height: 32)
                        Text(item.name)
                            .font(.rowDetail)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surfaceRaised, in: .rect(cornerRadius: Radius.tile))
    }

    private var dayLabel: String {
        let text = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return calendar.isDateInToday(day) ? "Today, \(text)" : text
    }

    private var ctaTitle: String {
        if calendar.isDateInToday(day) { return "Back to today" }
        return wornItems.isEmpty ? "Log this day" : "Edit this day"
    }
}
