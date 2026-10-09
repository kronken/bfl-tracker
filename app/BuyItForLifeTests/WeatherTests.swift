import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import BuyItForLife

struct CitiesTests {
    static let large = ["US", "CA", "GB", "DE", "FR", "IT", "ES", "PL", "AU"]
    static let small = ["FI", "SE", "NO", "DK", "IS", "NL", "BE", "LU", "AT", "CH", "IE", "PT", "CZ", "EE", "LV", "LT", "NZ"]

    @Test func coversTheAgreedCountries() {
        #expect(Set(Cities.byCountry.keys) == Set(Self.large + Self.small))
    }

    @Test(arguments: large)
    func largeCountriesListTen(code: String) {
        #expect(Cities.byCountry[code]?.count == 10)
    }

    @Test(arguments: small)
    func smallCountriesListFive(code: String) {
        #expect(Cities.byCountry[code]?.count == 5)
    }

    @Test func idsAreUniqueAndMatchTheirCountry() {
        let all = Cities.byCountry.flatMap { code, cities in cities.map { (code, $0) } }
        #expect(Set(all.map(\.1.id)).count == all.count)
        for (code, city) in all {
            #expect(city.countryCode == code, "\(city.id)")
            #expect(city.id.hasPrefix(code.lowercased() + "."), "\(city.id)")
            #expect((-90...90).contains(city.latitude) && (-180...180).contains(city.longitude), "\(city.id)")
        }
    }

    @Test func finlandIsTheFiveLargest() {
        #expect(Cities.suggestions(forRegion: "FI").map(\.name) == ["Helsinki", "Espoo", "Tampere", "Vantaa", "Oulu"])
    }

    @Test func uncoveredCountriesGetTheSixGlobalCities() {
        let global = Cities.suggestions(forRegion: "JP").map(\.name)
        #expect(global == ["Los Angeles", "New York", "London", "Paris", "Berlin", "Helsinki"])
        #expect(Cities.suggestions(forRegion: nil).count == 6)
        #expect(!Cities.isCovered(regionCode: "JP"))
        #expect(Cities.isCovered(regionCode: "fi"))
    }

    @Test func nearestCityNamesCurrentLocation() {
        let kallio = CLLocation(latitude: 60.18, longitude: 24.95)
        #expect(WeatherStore.placeName(near: kallio) == "Helsinki")
        let middleOfAtlantic = CLLocation(latitude: 40, longitude: -40)
        #expect(WeatherStore.placeName(near: middleOfAtlantic) == nil)
    }
}

struct WeatherBucketTests {
    @Test(arguments: [
        ("clear", WeatherConditions.sun),
        ("mostlyCloudy", .cloudy),
        ("foggy", .cloudy),
        ("drizzle", .rain),
        ("thunderstorms", .rain),
        ("sleet", .snow),
        ("blizzard", .snow),
        ("windy", .wind),
        ("somethingNew", .cloudy),
    ])
    func mapsWeatherKitConditions(raw: String, bucket: WeatherConditions) {
        #expect(WeatherBuckets.bucket(forRaw: raw) == bucket)
    }
}

@MainActor
struct TodayRulesTests {
    private let context: ModelContext
    private let calendar = Calendar.current

    init() throws {
        let schema = Schema([Item.self, DayLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    @Test func ownedFromPurchaseUntilSaleDay() {
        let item = Item(name: "Boots", category: .footwear, purchaseDate: day(2026, 3, 10), purchasePriceCents: 100)
        context.insert(item)
        #expect(!item.wasOwned(on: day(2026, 3, 9)))
        #expect(item.wasOwned(on: day(2026, 3, 10)))
        item.soldDate = day(2026, 6, 1)
        #expect(item.wasOwned(on: day(2026, 6, 1)))
        #expect(!item.wasOwned(on: day(2026, 6, 2)))
    }

    @Test func explainsWhyAnItemDoesNotSuit() {
        let linen = Item(name: "Linen shirt", category: .tops, purchaseDate: .now, purchasePriceCents: 100,
                         minTempC: 20, maxTempC: 35, conditions: [.sun, .cloudy])
        context.insert(linen)
        #expect(linen.unsuitedReason(temperatureC: 3, conditions: .rain).hasPrefix("Best above 20"))
        #expect(linen.unsuitedReason(temperatureC: 38, conditions: .sun).hasPrefix("Best below 35"))
        #expect(linen.unsuitedReason(temperatureC: 25, conditions: .rain) == "Not for rain")
    }

    @Test func dayLogStoresAndReadsWeather() throws {
        let log = try DayLog.fetchOrCreate(dayKey: "2026-10-09", in: context)
        #expect(log.weather == nil)
        let snapshot = WeatherSnapshot(temperatureC: 3, feelsLikeC: -1, conditionRaw: "drizzle",
                                       symbolName: "cloud.drizzle", placeName: "Helsinki")
        log.store(snapshot)
        #expect(log.weather == snapshot)
        #expect(snapshot.conditions == .rain)
    }
}
