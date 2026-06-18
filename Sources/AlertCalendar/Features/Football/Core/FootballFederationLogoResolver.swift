import Foundation

enum FootballFederationLogoResolver {
    private static let associationLogoBaseURL = "https://api.fifa.com/api/v3/picture/associations-sq-2"
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
    private static let unsupportedFIFAAssociationCodes: Set<String> = [
        "BOE",
        "GDL",
        "MTQ",
        "SMA",
        "SMN",
    ]

    static func resolvedLogoURL(
        existingLogoURL: URL?,
        teamID: String? = nil,
        name: String?,
        abbreviation: String?,
        countryName: String?,
        isNational: Bool
    ) -> URL? {
        federationLogoURL(
            teamID: teamID,
            name: name,
            abbreviation: abbreviation,
            countryName: countryName,
            isNational: isNational
        ) ?? existingLogoURL
    }

    static func federationLogoURL(
        teamID: String? = nil,
        name: String?,
        abbreviation: String?,
        countryName: String?,
        isNational: Bool
    ) -> URL? {
        guard isNational,
              let code = associationCode(
                teamID: teamID,
                name: name,
                abbreviation: abbreviation,
                countryName: countryName
              ) else {
            return nil
        }

        return URL(string: "\(associationLogoBaseURL)/\(code)")
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
              !unsupportedFIFAAssociationCodes.contains(code) else {
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
