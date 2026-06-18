import Foundation

enum FootballVenueCanonicalizer {
    private struct Rule {
        let venueIDs: Set<String>
        let names: Set<String>
        let cities: Set<String>
        let countries: Set<String>
        let locationText: String

        func matches(venue: [String: Any]) -> Bool {
            if let venueID = Self.venueID(from: venue),
               venueIDs.contains(FootballVenueCanonicalizer.normalized(venueID)) {
                return true
            }

            let address = venue["address"] as? [String: Any]
            guard let name = FootballVenueCanonicalizer.stringValue(venue["fullName"]),
                  names.contains(FootballVenueCanonicalizer.normalized(name)),
                  let country = FootballVenueCanonicalizer.stringValue(address?["country"]),
                  countries.contains(FootballVenueCanonicalizer.normalizedCountry(country)) else {
                return false
            }

            guard !cities.isEmpty else { return true }
            guard let city = FootballVenueCanonicalizer.stringValue(address?["city"]) else { return true }
            guard !FootballVenueCanonicalizer.isPlaceholderLocationText(city) else { return true }
            return cities.contains(FootballVenueCanonicalizer.normalized(city))
        }

        private static func venueID(from venue: [String: Any]) -> String? {
            if let id = FootballVenueCanonicalizer.stringValue(venue["id"]) {
                return id
            }

            guard let rawReference = FootballVenueCanonicalizer.stringValue(venue["$ref"]),
                  let url = URL(string: rawReference.replacingOccurrences(of: "http://", with: "https://")) else {
                return nil
            }

            let pathComponents = url.pathComponents
            guard let venuesIndex = pathComponents.firstIndex(of: "venues"),
                  venuesIndex + 1 < pathComponents.count else {
                return nil
            }

            return pathComponents[venuesIndex + 1]
        }
    }

    private static let rules: [Rule] = [
        rule(
            venueIDs: ["1672"],
            names: ["Estadio Banorte", "Estadio Azteca"],
            cities: ["Mexico City", "Ciudad de México"],
            countries: ["Mexico", "México"],
            locationText: "Estadio Banorte, Mexico City, Mexico"
        ),
        rule(
            venueIDs: ["5009"],
            names: ["Estadio Akron", "Estadio Chivas"],
            cities: ["Guadalajara", "Zapopan"],
            countries: ["Mexico", "México"],
            locationText: "Estadio Akron, Guadalajara, Mexico"
        ),
        rule(
            venueIDs: ["6351", "7540"],
            names: ["Estadio BBVA", "Estadio BBVA Bancomer"],
            cities: ["Guadalupe", "Monterrey"],
            countries: ["Mexico", "México"],
            locationText: "Estadio BBVA, Monterrey, Mexico"
        ),
        rule(
            venueIDs: ["7474"],
            names: ["Toyota Stadium"],
            cities: ["Toyota Stadium", "Frisco", "Frisco, Texas"],
            countries: ["USA", "United States"],
            locationText: "Toyota Stadium, Frisco, Texas, USA"
        ),
        rule(
            venueIDs: ["10143"],
            names: ["BMO Field"],
            cities: ["Toronto"],
            countries: ["Canada"],
            locationText: "BMO Field, Toronto, Canada"
        ),
        rule(
            venueIDs: ["9115"],
            names: ["SoFi Stadium"],
            cities: ["Inglewood", "Inglewood, California"],
            countries: ["USA", "United States"],
            locationText: "SoFi Stadium, Inglewood, California, USA"
        ),
        rule(
            venueIDs: ["5960"],
            names: ["Levi's Stadium", "Levis Stadium"],
            cities: ["Santa Clara", "Santa Clara, California"],
            countries: ["USA", "United States"],
            locationText: "Levi's Stadium, Santa Clara, California, USA"
        ),
        rule(
            venueIDs: ["4727"],
            names: ["MetLife Stadium"],
            cities: ["East Rutherford", "East Rutherford, New Jersey"],
            countries: ["USA", "United States"],
            locationText: "MetLife Stadium, East Rutherford, New Jersey, USA"
        ),
        rule(
            venueIDs: ["10660"],
            names: ["Gillette Stadium"],
            cities: ["Foxborough", "Foxborough, Massachusetts"],
            countries: ["USA", "United States"],
            locationText: "Gillette Stadium, Foxborough, Massachusetts, USA"
        ),
        rule(
            venueIDs: ["10661"],
            names: ["Nu Stadium", "Miami Freedom Park"],
            cities: ["Miami", "Miami, Florida"],
            countries: ["USA", "United States"],
            locationText: "Nu Stadium, Miami, Florida, USA"
        ),
        rule(
            venueIDs: ["4370"],
            names: ["BC Place"],
            cities: ["Vancouver"],
            countries: ["Canada"],
            locationText: "BC Place, Vancouver, Canada"
        ),
        rule(
            venueIDs: ["6262"],
            names: ["NRG Stadium"],
            cities: ["Houston", "Houston, Texas"],
            countries: ["USA", "United States"],
            locationText: "NRG Stadium, Houston, Texas, USA"
        ),
        rule(
            venueIDs: ["3871"],
            names: ["AT&T Stadium", "ATT Stadium"],
            cities: ["Arlington", "Arlington, Texas"],
            countries: ["USA", "United States"],
            locationText: "AT&T Stadium, Arlington, Texas, USA"
        ),
        rule(
            venueIDs: ["1421"],
            names: ["Lincoln Financial Field"],
            cities: ["Philadelphia", "Philadelphia, Pennsylvania"],
            countries: ["USA", "United States"],
            locationText: "Lincoln Financial Field, Philadelphia, Pennsylvania, USA"
        ),
        rule(
            venueIDs: ["7485"],
            names: ["Mercedes-Benz Stadium", "Mercedes Benz Stadium"],
            cities: ["Atlanta", "Atlanta, Georgia"],
            countries: ["USA", "United States"],
            locationText: "Mercedes-Benz Stadium, Atlanta, Georgia, USA"
        ),
        rule(
            venueIDs: ["4485"],
            names: ["Lumen Field", "CenturyLink Field"],
            cities: ["Seattle", "Seattle, Washington"],
            countries: ["USA", "United States"],
            locationText: "Lumen Field, Seattle, Washington, USA"
        ),
        rule(
            venueIDs: ["8689"],
            names: ["ScottsMiracle-Gro Field", "Lower.com Field", "Lowercom Field"],
            cities: ["Columbus", "Columbus, Ohio"],
            countries: ["USA", "United States"],
            locationText: "ScottsMiracle-Gro Field, Columbus, Ohio, USA"
        ),
        rule(
            venueIDs: ["4643"],
            names: ["Hard Rock Stadium"],
            cities: ["Miami Gardens", "Miami Gardens, Florida"],
            countries: ["USA", "United States"],
            locationText: "Hard Rock Stadium, Miami Gardens, Florida, USA"
        ),
        rule(
            venueIDs: ["10897"],
            names: ["GEHA Field at Arrowhead Stadium", "Arrowhead Stadium"],
            cities: ["Kansas City", "Kansas City, Missouri"],
            countries: ["USA", "United States"],
            locationText: "GEHA Field at Arrowhead Stadium, Kansas City, Missouri, USA"
        ),
        rule(
            venueIDs: ["10318"],
            names: ["Hill Dickinson Stadium", "Everton Stadium", "Bramley-Moore Dock Stadium"],
            cities: ["Liverpool"],
            countries: ["England", "United Kingdom", "UK"],
            locationText: "Hill Dickinson Stadium, Liverpool, England"
        ),
    ]

    static func locationText(
        from venue: [String: Any]?,
        fallbackLocationText: String
    ) -> String? {
        guard let venue else { return fallbackLocationText }
        if let canonicalLocationText = rules.first(where: { $0.matches(venue: venue) })?.locationText {
            return canonicalLocationText
        }
        return shouldSuppressAmbiguousFallback(for: venue) ? nil : fallbackLocationText
    }

    private static func rule(
        venueIDs: Set<String>,
        names: Set<String>,
        cities: Set<String>,
        countries: Set<String>,
        locationText: String
    ) -> Rule {
        Rule(
            venueIDs: Set(venueIDs.map(normalized)),
            names: Set(names.map(normalized)),
            cities: Set(cities.map(normalized)),
            countries: Set(countries.map(normalizedCountry)),
            locationText: locationText
        )
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = raw as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func normalizedCountry(_ value: String) -> String {
        let normalized = normalized(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: " ")

        switch normalized {
        case "mexico":
            return "mexico"
        default:
            return normalized
        }
    }

    private static func shouldSuppressAmbiguousFallback(for venue: [String: Any]) -> Bool {
        guard let rawVenueName = stringValue(venue["fullName"]) else { return false }
        guard looksLikeVenueName(rawVenueName) else { return false }
        let address = venue["address"] as? [String: Any]
        let city = stringValue(address?["city"])
        let state = stringValue(address?["state"])

        let normalizedName = normalized(rawVenueName)
        let hasSpecificCity = city.map { candidate in
            !isPlaceholderLocationText(candidate) && normalized(candidate) != normalizedName
        } ?? false
        let hasSpecificState = state.map { candidate in
            !isPlaceholderLocationText(candidate) && normalized(candidate) != normalizedName
        } ?? false

        return !hasSpecificCity && !hasSpecificState
    }

    private static func looksLikeVenueName(_ value: String) -> Bool {
        let tokens = Set(
            normalized(value)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        let venueTokens: Set<String> = [
            "arena",
            "ballpark",
            "centre",
            "center",
            "coliseum",
            "dome",
            "estadio",
            "field",
            "ground",
            "park",
            "stadium",
            "stade",
            "stadio",
        ]
        return tokens.contains { venueTokens.contains($0) }
    }

    private static func isPlaceholderLocationText(_ value: String) -> Bool {
        let normalizedValue = normalized(value)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders = [
            "tbc",
            "tbd",
            "to be announced",
            "to be confirmed",
            "venue tbc",
            "venue tbd",
        ]
        return placeholders.contains(normalizedValue)
    }
}
