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

    private static let knownLocations: [String: ResolvedLocation] = {
        let locations = [
            KnownLocation(
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
                coordinate: ResolvedLocationCoordinate(
                    latitude: 25.668565,
                    longitude: -100.244545
                ),
                timeZoneIdentifier: "America/Monterrey"
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
