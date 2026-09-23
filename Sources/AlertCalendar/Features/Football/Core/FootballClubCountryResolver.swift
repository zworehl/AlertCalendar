import Foundation

enum FootballClubCountryResolver {
    // ESPN can omit the domestic league or expose a touring venue for these clubs.
    // Countries are verified against UEFA; see docs/football-presentation.md.
    // Match both the ESPN ID and name so similarly named clubs stay distinct.
    private static let verifiedClubs: [String: (names: Set<String>, country: String)] = [
        "493": (["shakhtar", "shakhtar donetsk"], "Ukraine"),
        "494": (["slavia prague", "slavia praha", "sk slavia praha"], "Czech Republic"),
        "521": (["s bratislava", "slovan bratislava", "sk slovan bratislava"], "Slovakia"),
        "21922": (["sabah", "sabah fk", "sabah fc"], "Azerbaijan"),
    ]

    static func countryName(teamID: String?, name: String?) -> String? {
        guard let teamID,
              let club = verifiedClubs[teamID],
              club.names.contains(FootballDataAPIClient.normalizedLookupKey(name)) else {
            return nil
        }
        return club.country
    }
}
