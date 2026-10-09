import Foundation
import WeatherKit

/// The weather for one day as the app uses it: today's current conditions,
/// or a past day's noon reading. Stored on `DayLog`.
nonisolated struct WeatherSnapshot: Equatable, Sendable {
    var temperatureC: Double
    var feelsLikeC: Double?
    /// WeatherKit `WeatherCondition.rawValue`, e.g. "drizzle".
    var conditionRaw: String
    var symbolName: String
    var placeName: String?

    /// The bucket items are matched against.
    var conditions: WeatherConditions { WeatherBuckets.bucket(forRaw: conditionRaw) }

    /// Localized description, e.g. "Drizzle".
    var conditionText: String {
        WeatherCondition(rawValue: conditionRaw)?.description ?? conditionRaw.capitalized
    }

    /// "7°C · Cloudy"
    var shortText: String {
        "\(Temperature.format(celsius: temperatureC)) · \(conditionText)"
    }
}

/// Maps WeatherKit's ~30 conditions onto the five an item can be marked for.
nonisolated enum WeatherBuckets {
    static func bucket(forRaw raw: String) -> WeatherConditions {
        switch raw {
        case "clear", "mostlyClear", "hot", "frigid":
            .sun
        case "partlyCloudy", "mostlyCloudy", "cloudy", "foggy", "haze", "smoky":
            .cloudy
        case "drizzle", "rain", "heavyRain", "sunShowers", "freezingDrizzle", "freezingRain",
             "isolatedThunderstorms", "scatteredThunderstorms", "thunderstorms", "strongStorms",
             "tropicalStorm", "hurricane":
            .rain
        case "flurries", "sunFlurries", "snow", "heavySnow", "blizzard", "blowingSnow",
             "sleet", "wintryMix", "hail":
            .snow
        case "breezy", "windy", "blowingDust":
            .wind
        default:
            .cloudy
        }
    }
}

extension DayLog {
    var weather: WeatherSnapshot? {
        guard let temperatureC, let conditionRaw else { return nil }
        return WeatherSnapshot(
            temperatureC: temperatureC,
            feelsLikeC: feelsLikeC,
            conditionRaw: conditionRaw,
            symbolName: symbolName ?? "cloud",
            placeName: placeName
        )
    }

    func store(_ snapshot: WeatherSnapshot) {
        temperatureC = snapshot.temperatureC
        feelsLikeC = snapshot.feelsLikeC
        conditionRaw = snapshot.conditionRaw
        symbolName = snapshot.symbolName
        placeName = snapshot.placeName
    }
}
