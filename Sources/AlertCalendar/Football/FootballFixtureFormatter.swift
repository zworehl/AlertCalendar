import Foundation

enum FootballFixtureFormatter {
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
            values[normalizedCountryKey(name)] = regionCode
        }
        return values
    }()

    static func calendarTitle(for match: FootballFixtureMatch) -> String {
        let homeFlag = teamFlag(for: match.homeTeam)
        let awayFlag = teamFlag(for: match.awayTeam)
        let homeCode = teamDisplayIdentifier(for: match.homeTeam)
        let awayCode = teamDisplayIdentifier(for: match.awayTeam)

        if match.hasVisibleScore {
            return "\(homeCode) \(homeFlag) \(scoreText(match.homeScore)) - \(scoreText(match.awayScore)) \(awayFlag) \(awayCode)"
        }

        return "\(homeCode) \(homeFlag) - \(awayFlag) \(awayCode)"
    }

    static func menuBarDisplay(
        for match: FootballFixtureMatch,
        competitionLocalLogoURL: URL?,
        homeLocalLogoURL: URL?,
        awayLocalLogoURL: URL?
    ) -> FootballMenuBarDisplay {
        let homeCode = teamDisplayIdentifier(for: match.homeTeam)
        let awayCode = teamDisplayIdentifier(for: match.awayTeam)

        return FootballMenuBarDisplay(
            accessibilityText: calendarTitle(for: match),
            competitionName: match.competitionName,
            competitionStage: match.competitionStage,
            homeAbbreviation: homeCode,
            awayAbbreviation: awayCode,
            showsScore: match.hasVisibleScore,
            homeScore: scoreText(match.homeScore),
            awayScore: scoreText(match.awayScore),
            competitionLocalLogoPath: competitionLocalLogoURL?.path,
            homeLocalLogoPath: isUnknownTeam(match.homeTeam) ? nil : homeLocalLogoURL?.path,
            awayLocalLogoPath: isUnknownTeam(match.awayTeam) ? nil : awayLocalLogoURL?.path
        )
    }

    static func competitionDetailText(for match: FootballFixtureMatch, display: FootballMenuBarDisplay? = nil) -> String {
        competitionDetailText(
            competitionName: display?.competitionName ?? match.competitionName,
            competitionStage: display?.competitionStage ?? match.competitionStage
        )
    }

    static func competitionDetailText(
        competitionName: String,
        competitionStage: String?
    ) -> String {
        let trimmedCompetitionName = competitionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let competitionStage else { return trimmedCompetitionName }

        let trimmedCompetitionStage = competitionStage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCompetitionStage.isEmpty else { return trimmedCompetitionName }

        if normalizedCompetitionComparisonKey(trimmedCompetitionStage) == normalizedCompetitionComparisonKey(trimmedCompetitionName) {
            return trimmedCompetitionName
        }

        return "\(trimmedCompetitionName) • \(trimmedCompetitionStage)"
    }

    static func sharedCompetitionTitle(for matches: [FootballFixtureMatch]) -> String? {
        guard matches.count > 1, let firstMatch = matches.first else { return nil }

        let sharedCompetitionSlug = firstMatch.competitionSlug
        guard matches.allSatisfy({ $0.competitionSlug == sharedCompetitionSlug }) else {
            return nil
        }

        let sharedCompetitionDetails = Set(matches.map {
            competitionDetailText(
                competitionName: $0.competitionName,
                competitionStage: $0.competitionStage
            )
        })

        if sharedCompetitionDetails.count == 1 {
            return sharedCompetitionDetails.first
        }

        return firstMatch.competitionName
    }

    static func flagEmoji(for countryName: String?) -> String {
        guard let countryName else { return "🏳️" }
        let normalized = normalizedCountryKey(countryName)
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
            return String(compactRaw.prefix(3))
        }

        let compactFallback = compactIdentifier(fallbackName)
        guard !compactFallback.isEmpty else { return "TBD" }
        return String(compactFallback.prefix(3))
    }

    static func teamDisplayIdentifier(for team: FootballTeamSummary) -> String {
        if isUnknownTeam(team) {
            return "TBD"
        }
        if team.isNational {
            return fifaCode(for: team)
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
        return flagEmoji(for: team.countryName)
    }

    static func looksLikeFootballCalendarTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(" - ") else { return false }
        let uppercaseLetters = trimmed.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        guard uppercaseLetters >= 4 else { return false }
        return containsFlagEmoji(in: trimmed)
    }

    static func hasUnknownParticipants(in match: FootballFixtureMatch) -> Bool {
        isUnknownTeam(match.homeTeam) || isUnknownTeam(match.awayTeam)
    }

    static func calendarIdentityKey(for match: FootballFixtureMatch) -> String {
        [
            teamDisplayIdentifier(for: match.homeTeam),
            teamDisplayIdentifier(for: match.awayTeam),
        ]
        .joined(separator: "|")
    }

    static func calendarIdentityKey(fromCalendarTitle title: String) -> String? {
        let strippedFlags = title.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !(0x1F1E6 ... 0x1F1FF).contains(value)
                && value != 0x1F3F4
                && !(0xE0020 ... 0xE007F).contains(value)
        }

        let normalized = String(String.UnicodeScalarView(strippedFlags))
            .replacingOccurrences(
                of: #"\s+\d+\s*-\s*\d+\s+"#,
                with: " | ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+-\s+"#,
                with: " | ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = normalized
            .split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard parts.count == 2 else { return nil }

        let identifiers = parts.compactMap { side -> String? in
            let cleaned = side
                .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
                .uppercased()
            return cleaned.isEmpty ? nil : cleaned
        }

        guard identifiers.count == 2 else { return nil }
        return identifiers.joined(separator: "|")
    }

    static func scoreHighlightRange(in title: String, side: FootballScoreSide) -> NSRange? {
        let fullRange = NSRange(title.startIndex..., in: title)
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d+)\s-\s(\d+)\b"#) else {
            return nil
        }
        guard let match = regex.firstMatch(in: title, options: [], range: fullRange) else {
            return nil
        }

        switch side {
        case .home:
            return match.range(at: 1)
        case .away:
            return match.range(at: 2)
        }
    }

    static func isUnknownTeam(_ team: FootballTeamSummary) -> Bool {
        let abbreviation = team.abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedName = normalizedCountryKey(team.name)
        let compactName = compactIdentifier(team.name)

        if abbreviation == "TBD" || abbreviation == "TBC" {
            return true
        }

        if normalizedName.contains("winner")
            || normalizedName.contains("runner up")
            || normalizedName.contains("runner-up")
            || normalizedName.contains("to be determined")
            || normalizedName.contains("quarterfinal")
            || normalizedName.contains("semifinal") {
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

    private static func nationalTeamCountryCandidates(for team: FootballTeamSummary) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        for raw in [team.name, team.countryName] {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = normalizedCountryKey(trimmed)
            guard seen.insert(normalized).inserted else { continue }
            candidates.append(trimmed)
        }

        return candidates
    }

    private static func fifaCode(for team: FootballTeamSummary) -> String {
        let compactRaw = compactIdentifier(team.abbreviation)
        if compactRaw.count >= 3 {
            return String(compactRaw.prefix(3))
        }

        let compactFallback = compactIdentifier(team.countryName ?? team.name)
        guard !compactFallback.isEmpty else { return "TBD" }
        return String(compactFallback.prefix(3))
    }

    private static func compactIdentifier(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func isPlaceholderSlotIdentifier(_ raw: String) -> Bool {
        let compact = compactIdentifier(raw)
        guard !compact.isEmpty else { return false }

        return compact.range(of: #"^G[A-Z]\d+$"#, options: .regularExpression) != nil
            || compact.range(of: #"^RD\d+$"#, options: .regularExpression) != nil
    }

    private static func normalizedCountryKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }

    private static func normalizedCompetitionComparisonKey(_ raw: String) -> String {
        raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.allSatisfy(\.isNumber) }
            .joined(separator: " ")
    }

    private static func flagEmoji(forRegionCode regionCode: String) -> String {
        let baseValue: UInt32 = 127397
        let scalars = regionCode.uppercased().unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard let scalarValue = UnicodeScalar(baseValue + scalar.value) else { return nil }
            return scalarValue
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func containsFlagEmoji(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x1F1E6 ... 0x1F1FF).contains(value) || value == 0x1F3F4
        }
    }
}
