import CoreLocation
import Foundation

/// A city the user can pick as their weather location.
nonisolated struct City: Identifiable, Hashable, Sendable {
    /// Stable ID stored in settings, e.g. "fi.helsinki". Never change one.
    let id: String
    let name: String
    let region: String
    /// ISO 3166-1 alpha-2, e.g. "FI".
    let countryCode: String
    let latitude: Double
    let longitude: Double

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Hard-coded city suggestions: the largest cities of the countries most
/// users are in, so picking a weather location needs no search or network.
/// Countries over ~25 million people list 10 cities, the rest 5.
nonisolated enum Cities {
    /// Cities for the device's region, or `global` when it isn't covered.
    static func suggestions(forRegion regionCode: String?) -> [City] {
        guard let code = regionCode?.uppercased(), let list = byCountry[code] else { return global }
        return list
    }

    static func isCovered(regionCode: String?) -> Bool {
        regionCode.map { byCountry[$0.uppercased()] != nil } ?? false
    }

    static func city(id: String) -> City? { all[id] }

    /// Shown when the device's country isn't in the list.
    static let globalIDs = ["us.los-angeles", "us.new-york", "gb.london", "fr.paris", "de.berlin", "fi.helsinki"]
    static var global: [City] { globalIDs.compactMap { all[$0] } }

    static let all: [String: City] = Dictionary(
        uniqueKeysWithValues: byCountry.values.flatMap { $0 }.map { ($0.id, $0) }
    )

    private static func c(_ id: String, _ name: String, _ region: String, _ lat: Double, _ lon: Double) -> City {
        City(id: id, name: name, region: region, countryCode: String(id.prefix(2)).uppercased(), latitude: lat, longitude: lon)
    }

    static let byCountry: [String: [City]] = [
        // MARK: 10 cities
        "US": [
            c("us.new-york", "New York", "New York", 40.71, -74.01),
            c("us.los-angeles", "Los Angeles", "California", 34.05, -118.24),
            c("us.chicago", "Chicago", "Illinois", 41.88, -87.63),
            c("us.houston", "Houston", "Texas", 29.76, -95.37),
            c("us.phoenix", "Phoenix", "Arizona", 33.45, -112.07),
            c("us.philadelphia", "Philadelphia", "Pennsylvania", 39.95, -75.17),
            c("us.san-antonio", "San Antonio", "Texas", 29.42, -98.49),
            c("us.san-diego", "San Diego", "California", 32.72, -117.16),
            c("us.dallas", "Dallas", "Texas", 32.78, -96.80),
            c("us.jacksonville", "Jacksonville", "Florida", 30.33, -81.66),
        ],
        "CA": [
            c("ca.toronto", "Toronto", "Ontario", 43.65, -79.38),
            c("ca.montreal", "Montreal", "Quebec", 45.50, -73.57),
            c("ca.calgary", "Calgary", "Alberta", 51.05, -114.07),
            c("ca.ottawa", "Ottawa", "Ontario", 45.42, -75.70),
            c("ca.edmonton", "Edmonton", "Alberta", 53.55, -113.49),
            c("ca.winnipeg", "Winnipeg", "Manitoba", 49.90, -97.14),
            c("ca.mississauga", "Mississauga", "Ontario", 43.59, -79.64),
            c("ca.vancouver", "Vancouver", "British Columbia", 49.28, -123.12),
            c("ca.brampton", "Brampton", "Ontario", 43.73, -79.76),
            c("ca.hamilton", "Hamilton", "Ontario", 43.26, -79.87),
        ],
        "GB": [
            c("gb.london", "London", "England", 51.51, -0.13),
            c("gb.birmingham", "Birmingham", "England", 52.49, -1.89),
            c("gb.glasgow", "Glasgow", "Scotland", 55.86, -4.25),
            c("gb.liverpool", "Liverpool", "England", 53.41, -2.98),
            c("gb.bristol", "Bristol", "England", 51.45, -2.59),
            c("gb.manchester", "Manchester", "England", 53.48, -2.24),
            c("gb.sheffield", "Sheffield", "England", 53.38, -1.47),
            c("gb.leeds", "Leeds", "England", 53.80, -1.55),
            c("gb.edinburgh", "Edinburgh", "Scotland", 55.95, -3.19),
            c("gb.leicester", "Leicester", "England", 52.64, -1.13),
        ],
        "DE": [
            c("de.berlin", "Berlin", "Berlin", 52.52, 13.40),
            c("de.hamburg", "Hamburg", "Hamburg", 53.55, 9.99),
            c("de.munich", "Munich", "Bavaria", 48.14, 11.58),
            c("de.cologne", "Cologne", "North Rhine-Westphalia", 50.94, 6.96),
            c("de.frankfurt", "Frankfurt", "Hesse", 50.11, 8.68),
            c("de.stuttgart", "Stuttgart", "Baden-Württemberg", 48.78, 9.18),
            c("de.dusseldorf", "Düsseldorf", "North Rhine-Westphalia", 51.23, 6.77),
            c("de.leipzig", "Leipzig", "Saxony", 51.34, 12.37),
            c("de.dortmund", "Dortmund", "North Rhine-Westphalia", 51.51, 7.47),
            c("de.essen", "Essen", "North Rhine-Westphalia", 51.46, 7.01),
        ],
        "FR": [
            c("fr.paris", "Paris", "Île-de-France", 48.86, 2.35),
            c("fr.marseille", "Marseille", "Provence-Alpes-Côte d’Azur", 43.30, 5.37),
            c("fr.lyon", "Lyon", "Auvergne-Rhône-Alpes", 45.76, 4.84),
            c("fr.toulouse", "Toulouse", "Occitanie", 43.60, 1.44),
            c("fr.nice", "Nice", "Provence-Alpes-Côte d’Azur", 43.70, 7.27),
            c("fr.nantes", "Nantes", "Pays de la Loire", 47.22, -1.55),
            c("fr.montpellier", "Montpellier", "Occitanie", 43.61, 3.88),
            c("fr.strasbourg", "Strasbourg", "Grand Est", 48.57, 7.75),
            c("fr.bordeaux", "Bordeaux", "Nouvelle-Aquitaine", 44.84, -0.58),
            c("fr.lille", "Lille", "Hauts-de-France", 50.63, 3.06),
        ],
        "IT": [
            c("it.rome", "Rome", "Lazio", 41.90, 12.50),
            c("it.milan", "Milan", "Lombardy", 45.46, 9.19),
            c("it.naples", "Naples", "Campania", 40.85, 14.27),
            c("it.turin", "Turin", "Piedmont", 45.07, 7.69),
            c("it.palermo", "Palermo", "Sicily", 38.12, 13.36),
            c("it.genoa", "Genoa", "Liguria", 44.41, 8.93),
            c("it.bologna", "Bologna", "Emilia-Romagna", 44.49, 11.34),
            c("it.florence", "Florence", "Tuscany", 43.77, 11.26),
            c("it.bari", "Bari", "Apulia", 41.12, 16.87),
            c("it.catania", "Catania", "Sicily", 37.50, 15.09),
        ],
        "ES": [
            c("es.madrid", "Madrid", "Community of Madrid", 40.42, -3.70),
            c("es.barcelona", "Barcelona", "Catalonia", 41.39, 2.17),
            c("es.valencia", "Valencia", "Valencian Community", 39.47, -0.38),
            c("es.seville", "Seville", "Andalusia", 37.39, -5.98),
            c("es.zaragoza", "Zaragoza", "Aragon", 41.65, -0.89),
            c("es.malaga", "Málaga", "Andalusia", 36.72, -4.42),
            c("es.murcia", "Murcia", "Region of Murcia", 37.98, -1.13),
            c("es.palma", "Palma", "Balearic Islands", 39.57, 2.65),
            c("es.las-palmas", "Las Palmas", "Canary Islands", 28.12, -15.44),
            c("es.bilbao", "Bilbao", "Basque Country", 43.26, -2.93),
        ],
        "PL": [
            c("pl.warsaw", "Warsaw", "Masovia", 52.23, 21.01),
            c("pl.krakow", "Kraków", "Lesser Poland", 50.06, 19.94),
            c("pl.wroclaw", "Wrocław", "Lower Silesia", 51.11, 17.04),
            c("pl.lodz", "Łódź", "Łódź", 51.76, 19.46),
            c("pl.poznan", "Poznań", "Greater Poland", 52.41, 16.93),
            c("pl.gdansk", "Gdańsk", "Pomerania", 54.35, 18.65),
            c("pl.szczecin", "Szczecin", "West Pomerania", 53.43, 14.55),
            c("pl.bydgoszcz", "Bydgoszcz", "Kuyavia-Pomerania", 53.12, 18.01),
            c("pl.lublin", "Lublin", "Lublin", 51.25, 22.57),
            c("pl.bialystok", "Białystok", "Podlaskie", 53.13, 23.16),
        ],
        "AU": [
            c("au.sydney", "Sydney", "New South Wales", -33.87, 151.21),
            c("au.melbourne", "Melbourne", "Victoria", -37.81, 144.96),
            c("au.brisbane", "Brisbane", "Queensland", -27.47, 153.03),
            c("au.perth", "Perth", "Western Australia", -31.95, 115.86),
            c("au.adelaide", "Adelaide", "South Australia", -34.93, 138.60),
            c("au.gold-coast", "Gold Coast", "Queensland", -28.02, 153.40),
            c("au.newcastle", "Newcastle", "New South Wales", -32.93, 151.78),
            c("au.canberra", "Canberra", "Australian Capital Territory", -35.28, 149.13),
            c("au.sunshine-coast", "Sunshine Coast", "Queensland", -26.65, 153.07),
            c("au.wollongong", "Wollongong", "New South Wales", -34.42, 150.89),
        ],

        // MARK: 5 cities
        "FI": [
            c("fi.helsinki", "Helsinki", "Uusimaa", 60.17, 24.94),
            c("fi.espoo", "Espoo", "Uusimaa", 60.21, 24.66),
            c("fi.tampere", "Tampere", "Pirkanmaa", 61.50, 23.76),
            c("fi.vantaa", "Vantaa", "Uusimaa", 60.29, 25.04),
            c("fi.oulu", "Oulu", "North Ostrobothnia", 65.01, 25.47),
        ],
        "SE": [
            c("se.stockholm", "Stockholm", "Stockholm County", 59.33, 18.07),
            c("se.gothenburg", "Gothenburg", "Västra Götaland", 57.71, 11.97),
            c("se.malmo", "Malmö", "Skåne", 55.60, 13.00),
            c("se.uppsala", "Uppsala", "Uppsala County", 59.86, 17.64),
            c("se.vasteras", "Västerås", "Västmanland", 59.61, 16.55),
        ],
        "NO": [
            c("no.oslo", "Oslo", "Oslo", 59.91, 10.75),
            c("no.bergen", "Bergen", "Vestland", 60.39, 5.32),
            c("no.trondheim", "Trondheim", "Trøndelag", 63.43, 10.40),
            c("no.stavanger", "Stavanger", "Rogaland", 58.97, 5.73),
            c("no.kristiansand", "Kristiansand", "Agder", 58.15, 7.99),
        ],
        "DK": [
            c("dk.copenhagen", "Copenhagen", "Capital Region", 55.68, 12.57),
            c("dk.aarhus", "Aarhus", "Central Denmark", 56.16, 10.20),
            c("dk.odense", "Odense", "Southern Denmark", 55.40, 10.39),
            c("dk.aalborg", "Aalborg", "North Denmark", 57.05, 9.92),
            c("dk.esbjerg", "Esbjerg", "Southern Denmark", 55.48, 8.45),
        ],
        "IS": [
            c("is.reykjavik", "Reykjavík", "Capital Region", 64.15, -21.94),
            c("is.kopavogur", "Kópavogur", "Capital Region", 64.11, -21.91),
            c("is.hafnarfjordur", "Hafnarfjörður", "Capital Region", 64.07, -21.95),
            c("is.reykjanesbaer", "Reykjanesbær", "Southern Peninsula", 63.99, -22.56),
            c("is.akureyri", "Akureyri", "Northeast", 65.68, -18.09),
        ],
        "NL": [
            c("nl.amsterdam", "Amsterdam", "North Holland", 52.37, 4.90),
            c("nl.rotterdam", "Rotterdam", "South Holland", 51.92, 4.48),
            c("nl.the-hague", "The Hague", "South Holland", 52.08, 4.30),
            c("nl.utrecht", "Utrecht", "Utrecht", 52.09, 5.12),
            c("nl.eindhoven", "Eindhoven", "North Brabant", 51.44, 5.47),
        ],
        "BE": [
            c("be.antwerp", "Antwerp", "Flanders", 51.22, 4.40),
            c("be.ghent", "Ghent", "Flanders", 51.05, 3.72),
            c("be.charleroi", "Charleroi", "Wallonia", 50.41, 4.44),
            c("be.liege", "Liège", "Wallonia", 50.63, 5.57),
            c("be.brussels", "Brussels", "Brussels-Capital", 50.85, 4.35),
        ],
        "LU": [
            c("lu.luxembourg", "Luxembourg", "Luxembourg", 49.61, 6.13),
            c("lu.esch-sur-alzette", "Esch-sur-Alzette", "Esch-sur-Alzette", 49.50, 5.98),
            c("lu.differdange", "Differdange", "Esch-sur-Alzette", 49.52, 5.89),
            c("lu.dudelange", "Dudelange", "Esch-sur-Alzette", 49.48, 6.09),
            c("lu.ettelbruck", "Ettelbruck", "Diekirch", 49.85, 6.10),
        ],
        "AT": [
            c("at.vienna", "Vienna", "Vienna", 48.21, 16.37),
            c("at.graz", "Graz", "Styria", 47.07, 15.44),
            c("at.linz", "Linz", "Upper Austria", 48.31, 14.29),
            c("at.salzburg", "Salzburg", "Salzburg", 47.80, 13.04),
            c("at.innsbruck", "Innsbruck", "Tyrol", 47.27, 11.40),
        ],
        "CH": [
            c("ch.zurich", "Zurich", "Zurich", 47.38, 8.54),
            c("ch.geneva", "Geneva", "Geneva", 46.20, 6.14),
            c("ch.basel", "Basel", "Basel-Stadt", 47.56, 7.59),
            c("ch.lausanne", "Lausanne", "Vaud", 46.52, 6.63),
            c("ch.bern", "Bern", "Bern", 46.95, 7.45),
        ],
        "IE": [
            c("ie.dublin", "Dublin", "Leinster", 53.35, -6.26),
            c("ie.cork", "Cork", "Munster", 51.90, -8.47),
            c("ie.limerick", "Limerick", "Munster", 52.66, -8.63),
            c("ie.galway", "Galway", "Connacht", 53.27, -9.05),
            c("ie.waterford", "Waterford", "Munster", 52.26, -7.11),
        ],
        "PT": [
            c("pt.lisbon", "Lisbon", "Lisbon", 38.72, -9.14),
            c("pt.porto", "Porto", "Porto", 41.15, -8.61),
            c("pt.vila-nova-de-gaia", "Vila Nova de Gaia", "Porto", 41.13, -8.61),
            c("pt.amadora", "Amadora", "Lisbon", 38.75, -9.23),
            c("pt.braga", "Braga", "Braga", 41.55, -8.42),
        ],
        "CZ": [
            c("cz.prague", "Prague", "Prague", 50.08, 14.44),
            c("cz.brno", "Brno", "South Moravia", 49.20, 16.61),
            c("cz.ostrava", "Ostrava", "Moravia-Silesia", 49.82, 18.26),
            c("cz.plzen", "Plzeň", "Plzeň", 49.75, 13.38),
            c("cz.liberec", "Liberec", "Liberec", 50.77, 15.06),
        ],
        "EE": [
            c("ee.tallinn", "Tallinn", "Harju County", 59.44, 24.75),
            c("ee.tartu", "Tartu", "Tartu County", 58.38, 26.72),
            c("ee.narva", "Narva", "Ida-Viru County", 59.38, 28.19),
            c("ee.parnu", "Pärnu", "Pärnu County", 58.39, 24.50),
            c("ee.kohtla-jarve", "Kohtla-Järve", "Ida-Viru County", 59.40, 27.27),
        ],
        "LV": [
            c("lv.riga", "Riga", "Riga", 56.95, 24.11),
            c("lv.daugavpils", "Daugavpils", "Latgale", 55.87, 26.54),
            c("lv.liepaja", "Liepāja", "Kurzeme", 56.51, 21.01),
            c("lv.jelgava", "Jelgava", "Zemgale", 56.65, 23.72),
            c("lv.jurmala", "Jūrmala", "Riga region", 56.97, 23.77),
        ],
        "LT": [
            c("lt.vilnius", "Vilnius", "Vilnius County", 54.69, 25.28),
            c("lt.kaunas", "Kaunas", "Kaunas County", 54.90, 23.90),
            c("lt.klaipeda", "Klaipėda", "Klaipėda County", 55.70, 21.14),
            c("lt.siauliai", "Šiauliai", "Šiauliai County", 55.93, 23.31),
            c("lt.panevezys", "Panevėžys", "Panevėžys County", 55.73, 24.36),
        ],
        "NZ": [
            c("nz.auckland", "Auckland", "Auckland", -36.85, 174.76),
            c("nz.christchurch", "Christchurch", "Canterbury", -43.53, 172.64),
            c("nz.wellington", "Wellington", "Wellington", -41.29, 174.78),
            c("nz.hamilton", "Hamilton", "Waikato", -37.79, 175.28),
            c("nz.tauranga", "Tauranga", "Bay of Plenty", -37.69, 176.17),
        ],
    ]
}
