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
            guard let city = FootballVenueCanonicalizer.stringValue(address?["city"]) else { return false }
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
        Rule(
            venueIDs: ["6351", "7540"],
            names: [
                normalized("Estadio BBVA"),
                normalized("Estadio BBVA Bancomer"),
            ],
            cities: [
                normalized("Guadalupe"),
                normalized("Monterrey"),
            ],
            countries: [
                normalizedCountry("Mexico"),
                normalizedCountry("México"),
            ],
            locationText: "Estadio BBVA, Monterrey, Mexico"
        ),
    ]

    static func locationText(
        from venue: [String: Any]?,
        fallbackLocationText: String
    ) -> String {
        guard let venue else { return fallbackLocationText }
        return rules.first(where: { $0.matches(venue: venue) })?.locationText ?? fallbackLocationText
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
}
