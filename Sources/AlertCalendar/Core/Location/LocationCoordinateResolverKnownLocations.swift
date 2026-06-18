import Foundation

extension LocationCoordinateResolver {
    private struct KnownLocation: Sendable {
        let aliases: [String]
        let coordinate: ResolvedLocationCoordinate
        let timeZoneIdentifier: String?

        var resolvedLocation: ResolvedLocation {
            ResolvedLocation(
                coordinate: coordinate,
                timeZoneIdentifier: timeZoneIdentifier
            )
        }
    }

    private static func knownLocation(
        aliases: [String],
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String
    ) -> KnownLocation {
        KnownLocation(
            aliases: aliases,
            coordinate: ResolvedLocationCoordinate(
                latitude: latitude,
                longitude: longitude
            ),
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private static let knownLocations: [String: ResolvedLocation] = {
        let locations = [
            knownLocation(
                aliases: [
                    "Estadio Banorte, Mexico City, Mexico",
                    "Estadio Banorte, Ciudad de México, Mexico",
                    "Estadio Banorte, Ciudad de México, México",
                    "Estadio Azteca, Mexico City, Mexico",
                    "Estadio Azteca, Ciudad de México, Mexico",
                    "Estadio Azteca, Ciudad de México, México",
                ],
                latitude: 19.302911,
                longitude: -99.150442,
                timeZoneIdentifier: "America/Mexico_City"
            ),
            knownLocation(
                aliases: [
                    "Estadio Akron, Guadalajara, Mexico",
                    "Estadio Akron, Guadalajara, México",
                    "Estadio Akron, Zapopan, Mexico",
                    "Estadio Akron, Zapopan, México",
                    "Estadio Chivas, Guadalajara, Mexico",
                    "Estadio Chivas, Zapopan, Mexico",
                ],
                latitude: 20.681853,
                longitude: -103.462322,
                timeZoneIdentifier: "America/Mexico_City"
            ),
            knownLocation(
                aliases: [
                    "Estadio BBVA, Guadalupe, Mexico",
                    "Estadio BBVA, Guadalupe, México",
                    "Estadio BBVA, Guadalupe, Nuevo Leon, Mexico",
                    "Estadio BBVA, Guadalupe, Nuevo León, Mexico",
                    "Estadio BBVA, Monterrey, Mexico",
                    "Estadio BBVA, Nuevo Leon, Mexico",
                    "Estadio BBVA, Nuevo León, Mexico",
                    "Estadio BBVA Bancomer, Monterrey, Mexico",
                    "Monterrey Stadium, Monterrey, Mexico",
                ],
                latitude: 25.668565,
                longitude: -100.244545,
                timeZoneIdentifier: "America/Monterrey"
            ),
            knownLocation(
                aliases: [
                    "Toyota Stadium, Frisco, Texas, USA",
                    "Toyota Stadium, Frisco, Texas, United States",
                    "Toyota Stadium, Toyota Stadium, USA",
                    "Toyota Stadium, USA",
                    "Pizza Hut Park, Frisco, Texas, USA",
                    "FC Dallas Stadium, Frisco, Texas, USA",
                ],
                latitude: 33.154444,
                longitude: -96.835278,
                timeZoneIdentifier: "America/Chicago"
            ),
            knownLocation(
                aliases: [
                    "BMO Field, Toronto, Canada",
                ],
                latitude: 43.633223,
                longitude: -79.418562,
                timeZoneIdentifier: "America/Toronto"
            ),
            knownLocation(
                aliases: [
                    "SoFi Stadium, Inglewood, California, USA",
                    "SoFi Stadium, Inglewood, California, United States",
                ],
                latitude: 33.953536,
                longitude: -118.339027,
                timeZoneIdentifier: "America/Los_Angeles"
            ),
            knownLocation(
                aliases: [
                    "Levi's Stadium, Santa Clara, California, USA",
                    "Levi's Stadium, Santa Clara, California, United States",
                    "Levis Stadium, Santa Clara, California, USA",
                ],
                latitude: 37.403277,
                longitude: -121.969548,
                timeZoneIdentifier: "America/Los_Angeles"
            ),
            knownLocation(
                aliases: [
                    "MetLife Stadium, East Rutherford, New Jersey, USA",
                    "MetLife Stadium, East Rutherford, New Jersey, United States",
                ],
                latitude: 40.813528,
                longitude: -74.074361,
                timeZoneIdentifier: "America/New_York"
            ),
            knownLocation(
                aliases: [
                    "Gillette Stadium, Foxborough, Massachusetts, USA",
                    "Gillette Stadium, Foxborough, Massachusetts, United States",
                    "Gillette Stadium, Foxboro, Massachusetts, USA",
                ],
                latitude: 42.090944,
                longitude: -71.264344,
                timeZoneIdentifier: "America/New_York"
            ),
            knownLocation(
                aliases: [
                    "Nu Stadium, Miami, Florida, USA",
                    "Nu Stadium, Miami, Florida, United States",
                    "Miami Freedom Park, Miami, Florida, USA",
                ],
                latitude: 25.7931,
                longitude: -80.2590,
                timeZoneIdentifier: "America/New_York"
            ),
            knownLocation(
                aliases: [
                    "BC Place, Vancouver, Canada",
                ],
                latitude: 49.276750,
                longitude: -123.111999,
                timeZoneIdentifier: "America/Vancouver"
            ),
            knownLocation(
                aliases: [
                    "NRG Stadium, Houston, Texas, USA",
                    "NRG Stadium, Houston, Texas, United States",
                ],
                latitude: 29.684722,
                longitude: -95.410707,
                timeZoneIdentifier: "America/Chicago"
            ),
            knownLocation(
                aliases: [
                    "AT&T Stadium, Arlington, Texas, USA",
                    "AT&T Stadium, Arlington, Texas, United States",
                    "ATT Stadium, Arlington, Texas, USA",
                ],
                latitude: 32.747284,
                longitude: -97.094494,
                timeZoneIdentifier: "America/Chicago"
            ),
            knownLocation(
                aliases: [
                    "Lincoln Financial Field, Philadelphia, Pennsylvania, USA",
                    "Lincoln Financial Field, Philadelphia, Pennsylvania, United States",
                ],
                latitude: 39.900771,
                longitude: -75.167469,
                timeZoneIdentifier: "America/New_York"
            ),
            knownLocation(
                aliases: [
                    "Mercedes-Benz Stadium, Atlanta, Georgia, USA",
                    "Mercedes-Benz Stadium, Atlanta, Georgia, United States",
                    "Mercedes Benz Stadium, Atlanta, Georgia, USA",
                ],
                latitude: 33.755489,
                longitude: -84.401993,
                timeZoneIdentifier: "America/New_York"
            ),
            knownLocation(
                aliases: [
                    "Lumen Field, Seattle, Washington, USA",
                    "Lumen Field, Seattle, Washington, United States",
                    "CenturyLink Field, Seattle, Washington, USA",
                ],
                latitude: 47.595153,
                longitude: -122.331625,
                timeZoneIdentifier: "America/Los_Angeles"
            ),
            knownLocation(
                aliases: [
                    "ScottsMiracle-Gro Field, Columbus, Ohio, USA",
                    "ScottsMiracle-Gro Field, Columbus, Ohio, United States",
                    "Lower.com Field, Columbus, Ohio, USA",
                    "Lowercom Field, Columbus, Ohio, USA",
                ],
                latitude: 39.968461,
                longitude: -83.017089,
                timeZoneIdentifier: "America/New_York"
            ),
            knownLocation(
                aliases: [
                    "Hard Rock Stadium, Miami Gardens, Florida, USA",
                    "Hard Rock Stadium, Miami Gardens, Florida, United States",
                ],
                latitude: 25.958056,
                longitude: -80.238889,
                timeZoneIdentifier: "America/New_York"
            ),
            knownLocation(
                aliases: [
                    "GEHA Field at Arrowhead Stadium, Kansas City, Missouri, USA",
                    "GEHA Field at Arrowhead Stadium, Kansas City, Missouri, United States",
                    "Arrowhead Stadium, Kansas City, Missouri, USA",
                ],
                latitude: 39.049002,
                longitude: -94.483864,
                timeZoneIdentifier: "America/Chicago"
            ),
            knownLocation(
                aliases: [
                    "Hill Dickinson Stadium, Liverpool, England",
                    "Hill Dickinson Stadium, Liverpool, United Kingdom",
                    "Everton Stadium, Liverpool, England",
                    "Bramley-Moore Dock Stadium, Liverpool, England",
                ],
                latitude: 53.4251,
                longitude: -3.0028,
                timeZoneIdentifier: "Europe/London"
            ),
        ]

        var indexed: [String: ResolvedLocation] = [:]
        for location in locations {
            for alias in location.aliases {
                indexed[normalizedKnownLocationKey(alias)] = location.resolvedLocation
            }
        }
        return indexed
    }()

    static func knownLocation(for rawText: String) -> ResolvedLocation? {
        knownLocations[normalizedKnownLocationKey(rawText)]
    }

    private static func normalizedKnownLocationKey(_ value: String) -> String {
        normalizedSearchText(value)
            .replacingOccurrences(of: #"\s*,\s*"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
