import Foundation

extension FootballFixtureFormatter {
    private static let englandFlag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
    private static let scotlandFlag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
    private static let walesFlag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"

    private static let specialRegionFlags: [String: String] = [
        "england": englandFlag,
        "scotland": scotlandFlag,
        "wales": walesFlag,
        "united states": "🇺🇸",
        "usa": "🇺🇸",
        "south korea": "🇰🇷",
        "north korea": "🇰🇵",
        "czech republic": "🇨🇿",
        "czechia": "🇨🇿",
        "turkey": "🇹🇷",
        "turkiye": "🇹🇷",
    ]

    private static let regionCodeAliases: [String: String] = [
        "bonaire": "BQ",
        "bosnia and herzegovina": "BA",
        "china": "CN",
        "ivory coast": "CI",
        "ir iran": "IR",
        "kyrgyz republic": "KG",
        "korea republic": "KR",
        "republic of korea": "KR",
        "korea dpr": "KP",
        "dpr korea": "KP",
        "macau": "MO",
        "dr congo": "CD",
        "congo dr": "CD",
        "congo kinshasa": "CD",
        "china pr": "CN",
        "pr china": "CN",
        "palestine": "PS",
        "trinidad and tobago": "TT",
        "uae": "AE",
        "us virgin islands": "VI",
        "hong kong china": "HK",
        "cape verde islands": "CV",
        "cabo verde": "CV",
        "st kitts and nevis": "KN",
        "saint kitts and nevis": "KN",
        "st lucia": "LC",
        "saint lucia": "LC",
        "st vincent and the grenadines": "VC",
        "saint vincent and the grenadines": "VC",
        "st vincent grenadines": "VC",
    ]

    private static let regionNameLookup: [String: String] = {
        let locale = Locale(identifier: "en_US_POSIX")
        var values: [String: String] = [:]
        for regionCode in Locale.Region.isoRegions.map(\.identifier) {
            guard let name = locale.localizedString(forRegionCode: regionCode) else { continue }
            values[FootballDataAPIClient.normalizedLookupKey(name)] = regionCode
        }
        return values
    }()

    static func flagEmoji(for countryName: String?) -> String {
        guard let countryName else { return "🏳️" }
        let normalized = FootballDataAPIClient.normalizedLookupKey(countryName)
        if let special = specialRegionFlags[normalized] {
            return special
        }
        if let aliasedRegionCode = regionCodeAliases[normalized] {
            return flagEmoji(forRegionCode: aliasedRegionCode)
        }
        guard let regionCode = regionNameLookup[normalized] else {
            return "🏳️"
        }
        return flagEmoji(forRegionCode: regionCode)
    }

    static func normalizedAbbreviation(_ raw: String, fallbackName: String) -> String {
        let compactRaw = compactIdentifier(raw)
        if !compactRaw.isEmpty {
            return compactRaw
        }

        let name = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "TBD" : name
    }

    static func teamDisplayIdentifier(for team: FootballTeamSummary) -> String {
        if isUnknownTeam(team) {
            return "TBD"
        }
        return normalizedAbbreviation(team.abbreviation, fallbackName: team.name)
    }

    static func teamFlag(for team: FootballTeamSummary) -> String {
        if isUnknownTeam(team) {
            return "🏴"
        }
        if team.isNational {
            for candidate in nationalTeamCountryCandidates(for: team) {
                let flag = flagEmoji(for: candidate)
                if flag != "🏳️" {
                    return flag
                }
            }
        }
        let clubCountry = team.isNational ? nil : FootballClubCountryResolver.countryName(
            teamID: team.id,
            name: team.name
        )
        return flagEmoji(for: clubCountry ?? team.countryName)
    }

    static func isUnknownTeam(_ team: FootballTeamSummary) -> Bool {
        let abbreviation = team.abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedName = FootballDataAPIClient.normalizedLookupKey(team.name)
        let normalizedCountryName = FootballDataAPIClient.normalizedLookupKey(team.countryName)
        let compactName = compactIdentifier(team.name)
        let missingCountryName = team.countryName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true

        if abbreviation == "TBD" || abbreviation == "TBC" {
            return true
        }

        if team.isNational,
           isRecognizedNationalTeamName(team.name) {
            return false
        }

        if isPlaceholderSlotDescription(normalizedName)
            || isPlaceholderSlotDescription(normalizedCountryName) {
            return true
        }

        if missingCountryName,
           normalizedName.contains("group") || abbreviation == "GRO" || compactName == "GRO" {
            return true
        }

        if isPlaceholderSlotIdentifier(abbreviation) || isPlaceholderSlotIdentifier(compactName) {
            return true
        }

        if abbreviation.range(of: #"^[A-Z]{1,4}(?:W|RU)\d+$"#, options: .regularExpression) != nil {
            return true
        }

        if abbreviation.range(of: #"^(QF|SF|RO|PO|GW)[A-Z0-9-]*$"#, options: .regularExpression) != nil,
           team.countryName == nil {
            return true
        }

        return false
    }

    static func scoreText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0" : trimmed
    }

    static func nationalTeamCountryCandidates(for team: FootballTeamSummary) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        for raw in [team.name, team.countryName] {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = FootballDataAPIClient.normalizedLookupKey(trimmed)
            guard seen.insert(normalized).inserted else { continue }
            candidates.append(trimmed)
        }

        return candidates
    }

    static func compactIdentifier(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    static func isPlaceholderSlotIdentifier(_ raw: String) -> Bool {
        let compact = compactIdentifier(raw)
        guard !compact.isEmpty else { return false }

        return compact.range(of: #"^G[A-Z]\d+$"#, options: .regularExpression) != nil
            || compact.range(of: #"^RD\d+[A-Z0-9]*$"#, options: .regularExpression) != nil
            || compact.range(of: #"^[123][A-L]$"#, options: .regularExpression) != nil
            || compact.range(of: #"^3RD[A-Z0-9]*$"#, options: .regularExpression) != nil
    }

    static func isPlaceholderSlotDescription(_ normalized: String) -> Bool {
        guard !normalized.isEmpty else { return false }

        if normalized.contains("winner")
            || normalized.contains("runner up")
            || normalized.contains("to be determined")
            || normalized.contains("quarterfinal")
            || normalized.contains("semifinal") {
            return true
        }

        return normalized.contains("group") && normalized.contains("place")
    }

    static func isRecognizedNationalTeamName(_ raw: String) -> Bool {
        flagEmoji(for: raw) != "🏳️"
    }

    static func flagEmoji(forRegionCode regionCode: String) -> String {
        let baseValue: UInt32 = 127397
        let scalars = regionCode.uppercased().unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard let scalarValue = UnicodeScalar(baseValue + scalar.value) else { return nil }
            return scalarValue
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func containsFlagEmoji(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x1F1E6 ... 0x1F1FF).contains(value) || value == 0x1F3F3 || value == 0x1F3F4
        }
    }
}
