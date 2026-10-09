import CoreLocation
import Foundation
import Observation
import WeatherKit

/// Fetches weather from WeatherKit for the location chosen in settings.
@MainActor
@Observable
final class WeatherStore {
    enum TodayState: Equatable {
        /// No weather location chosen yet.
        case needsLocation
        /// "Current location" is chosen but permission is off.
        case locationDenied
        case loading
        case loaded(WeatherSnapshot)
        case failed
    }

    struct Attribution: Equatable {
        var markURL: URL
        var legalURL: URL
    }

    private(set) var today: TodayState = .needsLocation
    private(set) var attribution: Attribution?

    let location = LocationProvider()

    @ObservationIgnored private let service = WeatherService.shared
    @ObservationIgnored private var lastRefresh: (location: String, date: Date)?
    @ObservationIgnored private var historyCache: [String: WeatherSnapshot] = [:]

    /// Reloads today's weather. Skipped if it was loaded in the last 15
    /// minutes for the same location, unless `force` is set.
    func refreshToday(locationSetting: String?, force: Bool = false) async {
        guard let locationSetting else {
            today = .needsLocation
            return
        }
        if !force, let last = lastRefresh, last.location == locationSetting,
           -last.date.timeIntervalSinceNow < 15 * 60, case .loaded = today {
            return
        }
        #if DEBUG
        // `-debugWeather 3,drizzle` fakes today's weather, for screenshots.
        if let fake = UserDefaults.standard.string(forKey: "debugWeather")?.split(separator: ","), fake.count == 2,
           let temperature = Double(fake[0]) {
            let name = Cities.city(id: locationSetting)?.name
            today = .loaded(WeatherSnapshot(temperatureC: temperature, feelsLikeC: temperature - 4,
                                            conditionRaw: String(fake[1]), symbolName: "cloud.drizzle", placeName: name))
            return
        }
        #endif
        if case .loaded = today {} else { today = .loading }

        do {
            let (place, name) = try await resolve(locationSetting)
            let current = try await service.weather(for: place, including: .current)
            today = .loaded(WeatherSnapshot(
                temperatureC: current.temperature.converted(to: .celsius).value,
                feelsLikeC: current.apparentTemperature.converted(to: .celsius).value,
                conditionRaw: current.condition.rawValue,
                symbolName: current.symbolName,
                placeName: name
            ))
            lastRefresh = (locationSetting, .now)
            await loadAttribution()
        } catch LocationProvider.LocationError.denied {
            today = .locationDenied
        } catch {
            if case .loaded = today { return } // keep showing the last good reading
            today = .failed
        }
    }

    /// A past day's weather: the noon reading where the user is now.
    func history(for dayKey: String, locationSetting: String?) async -> WeatherSnapshot? {
        guard let locationSetting else { return nil }
        let cacheKey = "\(locationSetting)|\(dayKey)"
        if let cached = historyCache[cacheKey] { return cached }
        guard let day = DayKey.date(from: dayKey),
              let noon = Calendar.current.date(byAdding: .hour, value: 12, to: day),
              let end = Calendar.current.date(byAdding: .hour, value: 1, to: noon)
        else { return nil }
        do {
            let (place, name) = try await resolve(locationSetting)
            let hours = try await service.weather(for: place, including: .hourly(startDate: noon, endDate: end))
            guard let hour = hours.first else { return nil }
            let snapshot = WeatherSnapshot(
                temperatureC: hour.temperature.converted(to: .celsius).value,
                feelsLikeC: hour.apparentTemperature.converted(to: .celsius).value,
                conditionRaw: hour.condition.rawValue,
                symbolName: hour.symbolName,
                placeName: name
            )
            historyCache[cacheKey] = snapshot
            return snapshot
        } catch {
            return nil
        }
    }

    /// The coordinates and display name for a location setting.
    func resolve(_ locationSetting: String) async throws -> (CLLocation, String?) {
        if locationSetting == AppSettings.currentLocation {
            let here: CLLocation
            do {
                here = try await location.currentLocation()
            } catch LocationProvider.LocationError.unavailable {
                guard let cached = LocationCache.load() else { throw LocationProvider.LocationError.unavailable }
                here = cached
            }
            return (here, Self.placeName(near: here))
        }
        guard let city = Cities.city(id: locationSetting) else { throw LocationProvider.LocationError.unavailable }
        return (city.location, city.name)
    }

    /// The nearest known city within 40 km, so "current location" can still
    /// show a place name without a geocoding request.
    nonisolated static func placeName(near location: CLLocation) -> String? {
        let nearest = Cities.all.values.min {
            $0.location.distance(from: location) < $1.location.distance(from: location)
        }
        guard let nearest, nearest.location.distance(from: location) < 40_000 else { return nil }
        return nearest.name
    }

    private func loadAttribution() async {
        guard attribution == nil, let value = try? await service.attribution else { return }
        attribution = Attribution(markURL: value.combinedMarkDarkURL, legalURL: value.legalPageURL)
    }
}
