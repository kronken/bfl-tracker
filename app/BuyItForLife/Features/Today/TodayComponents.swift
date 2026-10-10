import SwiftUI

/// The seven days of the selected day's week. Future days are disabled; a
/// blue dot marks days with something logged.
struct WeekStrip: View {
    @Binding var selectedDay: Date
    var loggedDayKeys: Set<String>

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
                let isFuture = day > calendar.startOfDay(for: .now)
                let isLogged = !isFuture && loggedDayKeys.contains(DayKey.make(for: day))
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
                } label: {
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.label)
                            .foregroundStyle(isFuture ? .textTertiary : .textSecondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.number(.title3))
                            .foregroundStyle(isFuture ? .textTertiary : .textPrimary)
                        Circle()
                            .fill(isLogged ? AnyShapeStyle(.dataBlue) : AnyShapeStyle(.clear))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(isSelected ? AnyShapeStyle(.fillSelected) : AnyShapeStyle(.clear),
                                in: .rect(cornerRadius: Radius.tile))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(.stroke, lineWidth: 1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (isLogged ? ", logged" : ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var days: [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }
}

/// Temperature, condition and place, with the Apple Weather attribution.
struct WeatherCard: View {
    var snapshot: WeatherSnapshot
    var isToday: Bool
    var attribution: WeatherStore.Attribution?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: snapshot.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20))
                .foregroundStyle(.textPrimary)
                .frame(width: 44, height: 44)
                .background(.surfaceRaised, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Temperature.format(celsius: snapshot.temperatureC))
                        .font(.number(.title2))
                        .foregroundStyle(.textPrimary)
                    Text(snapshot.conditionText)
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                }
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            attributionMark
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(padding: nil)
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        var parts: [String] = []
        if isToday, let feels = snapshot.feelsLikeC {
            parts.append("Feels like \(Temperature.format(celsius: feels))")
        } else if !isToday {
            parts.append("At noon")
        }
        if let place = snapshot.placeName { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    /// Apple requires the Apple Weather mark and a link to its data sources.
    @ViewBuilder
    private var attributionMark: some View {
        if let attribution {
            Link(destination: attribution.legalURL) {
                AsyncImage(url: attribution.markURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    fallbackMark
                }
                .frame(width: 56, height: 14)
            }
            .accessibilityLabel("Apple Weather data sources")
        } else {
            fallbackMark
        }
    }

    private var fallbackMark: some View {
        Text("Apple\nWeather")
            .font(.label)
            .foregroundStyle(.textSecondary)
            .multilineTextAlignment(.trailing)
    }

    /// Shown while the forecast loads.
    static var placeholder: some View {
        HStack(spacing: 12) {
            Circle().fill(.surfaceRaised).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(.surfaceRaised).frame(width: 140, height: 18)
                Capsule().fill(.surfaceRaised).frame(width: 180, height: 14)
            }
            Spacer()
            ProgressView().tint(.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(padding: nil)
        .accessibilityLabel("Loading weather")
    }
}

/// A card asking for something before the weather can be shown.
struct WeatherPromptCard: View {
    var title: String
    var message: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 20))
                    .foregroundStyle(.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.surfaceRaised, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                    Text(message)
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                }
            }
            Button(actionTitle, action: action)
                .buttonStyle(.secondary)
        }
        .card()
    }
}

/// One item on Today: tap to mark it worn.
struct OutfitRow: View {
    let item: Item
    var detail: String
    var isWorn: Bool
    var dimmed: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                ItemImageView(content: item.thumbnailContent, cornerRadius: Radius.thumb, iconSize: 22)
                    .frame(width: 44, height: 44)
                    .opacity(dimmed ? 0.7 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.rowTitle)
                            .foregroundStyle(dimmed ? .textSecondary : .textPrimary)
                            .lineLimit(1)
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(dimmed ? .textSecondary : .textPrimary)
                                .accessibilityLabel("Favorite")
                        }
                    }
                    Text(detail)
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ZStack {
                    if isWorn {
                        Circle().fill(.textPrimary)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.appBackground)
                    } else {
                        Circle().strokeBorder(.textTertiary, lineWidth: 1.5)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isWorn ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isWorn ? "Marked as worn. Tap to unmark." : "Tap to mark as worn.")
    }
}

/// A daily driver on Today: round thumbnail, name, checkmark when selected.
struct DailyDriverChip: View {
    let item: Item
    var isOn: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                ItemImageView(content: item.thumbnailContent, cornerRadius: 15, iconSize: 14)
                    .frame(width: 30, height: 30)
                    .opacity(isOn ? 1 : 0.5)
                Text(item.name)
                    .font(.rowDetail.weight(.medium))
                    .foregroundStyle(isOn ? .textPrimary : .textSecondary)
                    .lineLimit(1)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.textPrimary)
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(minHeight: 40)
            .background(isOn ? AnyShapeStyle(.fillSelected) : AnyShapeStyle(.clear), in: .capsule)
            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isOn ? "Worn today. Tap to unmark." : "Tap to mark as worn.")
    }
}
