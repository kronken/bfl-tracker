import Foundation

/// The weather conditions an item is suited for. Stored as a bitmask, so never
/// change an existing option's bit.
nonisolated struct WeatherConditions: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let sun = WeatherConditions(rawValue: 1 << 0)
    static let cloudy = WeatherConditions(rawValue: 1 << 1)
    static let rain = WeatherConditions(rawValue: 1 << 2)
    static let snow = WeatherConditions(rawValue: 1 << 3)
    static let wind = WeatherConditions(rawValue: 1 << 4)

    static let all: WeatherConditions = [.sun, .cloudy, .rain, .snow, .wind]

    /// Individual options in display order, with their labels.
    static let options: [(condition: WeatherConditions, title: String)] = [
        (.sun, "Sun"),
        (.cloudy, "Cloudy"),
        (.rain, "Rain"),
        (.snow, "Snow"),
        (.wind, "Wind"),
    ]
}
