import Foundation

enum FootballNationalLogoResolver {
    private static let countryFlagLogoBaseURL = "https://a.espncdn.com/i/teamlogos/countries/500"
    private static let localFlagResourcePrefix = "football-flag-"
    private static let localFlagResourceSubdirectories = [
        "FootballNationalFlags",
        "Resources/Images/FootballNationalFlags",
    ]
    private static let placeholderCodes: Set<String> = [
        "TBA",
        "TBC",
        "TBD",
    ]
    private static let codeAliases: [String: String] = [
        "BKA": "BFA",
        "BVI": "VGB",
        "CHE": "SUI",
        "MGL": "MNG",
        "PSE": "PLE",
        "SWITZERLAND": "SUI",
        "USVI": "VIR",
    ]

    static func resolvedLogoURL(
        existingLogoURL: URL?,
        teamID: String? = nil,
        name: String?,
        abbreviation: String?,
        countryName: String?,
        isNational: Bool
    ) -> URL? {
        guard isNational else { return existingLogoURL }

        if let existingLogoURL,
           !isFIFAAssociationLogo(existingLogoURL) {
            return existingLogoURL
        }

        return nationalFlagLogoURL(
            teamID: teamID,
            name: name,
            abbreviation: abbreviation,
            countryName: countryName
        ) ?? existingLogoURL
    }

    static func nationalFlagLogoURL(
        teamID: String? = nil,
        name: String?,
        abbreviation: String?,
        countryName: String?
    ) -> URL? {
        guard let code = associationCode(
            teamID: teamID,
            name: name,
            abbreviation: abbreviation,
            countryName: countryName
        ) else {
            return nil
        }

        return URL(string: "\(countryFlagLogoBaseURL)/\(code.lowercased()).png")
    }

    static func localFlagImageURL(
        teamID: String? = nil,
        name: String?,
        abbreviation: String?,
        countryName: String?
    ) -> URL? {
        guard let code = associationCode(
            teamID: teamID,
            name: name,
            abbreviation: abbreviation,
            countryName: countryName
        ) else {
            return nil
        }

        return localFlagImageURL(forAssociationCode: code)
    }

    static func localFlagImageURL(forAssociationCode code: String) -> URL? {
        guard let normalizedCode = normalizedAssociationCode(from: code) else {
            return nil
        }

        let resourceName = "\(localFlagResourcePrefix)\(normalizedCode.lowercased())"
        for subdirectory in localFlagResourceSubdirectories {
            if let url = Bundle.module.url(
                forResource: resourceName,
                withExtension: "png",
                subdirectory: subdirectory
            ) {
                return url
            }
        }

        return Bundle.module.url(forResource: resourceName, withExtension: "png")
    }

    static func isFIFAAssociationLogo(_ url: URL) -> Bool {
        url.host?.caseInsensitiveCompare("api.fifa.com") == .orderedSame
            && url.path.contains("/api/v3/picture/associations-sq-2/")
    }

    static func associationCode(
        teamID: String? = nil,
        name: String?,
        abbreviation: String?,
        countryName: String?
    ) -> String? {
        let candidates = [
            abbreviation,
            countryName,
            name,
            teamID.flatMap(associationCodeFromKnownTeamID),
        ]

        for candidate in candidates {
            if let code = normalizedAssociationCode(from: candidate) {
                return code
            }
        }

        return nil
    }

    static func normalizedAssociationCode(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let compact = rawValue
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard !compact.isEmpty,
              !compact.contains(where: \.isNumber),
              !placeholderCodes.contains(compact) else {
            return nil
        }

        let code = codeAliases[compact] ?? compact
        guard code.count == 3,
              !placeholderCodes.contains(code) else {
            return nil
        }

        return code
    }

    private static func associationCodeFromKnownTeamID(_ teamID: String) -> String? {
        knownAssociationCodesByESPNTeamID[teamID.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    private static let knownAssociationCodesByESPNTeamID: [String: String] = [
        "2642": "USA",
        "2650": "ESP",
        "2677": "CRC",
        "2751": "CPV",
    ]
}
