import Foundation

enum FootballFixtureFormatter {
    static let footballLocationSymbolName = "sportscourt.circle"

    static func calendarTitle(for match: FootballFixtureMatch) -> String {
        let homeFlag = teamFlag(for: match.homeTeam)
        let awayFlag = teamFlag(for: match.awayTeam)
        let homeName = teamDisplayIdentifier(for: match.homeTeam)
        let awayName = teamDisplayIdentifier(for: match.awayTeam)

        if match.hasVisibleScore {
            return "\(homeName) \(homeFlag) \(scoreText(match.homeScore)) - \(scoreText(match.awayScore)) \(awayFlag) \(awayName)"
        }

        return "\(homeName) \(homeFlag) - \(awayFlag) \(awayName)"
    }

    static func menuBarDisplay(
        for match: FootballFixtureMatch,
        competitionLocalLogoURL: URL?,
        homeLocalLogoURL: URL?,
        awayLocalLogoURL: URL?
    ) -> FootballMenuBarDisplay {
        let homeCode = teamDisplayIdentifier(for: match.homeTeam)
        let awayCode = teamDisplayIdentifier(for: match.awayTeam)
        let resolvedHomeLocalLogoURL = resolvedMenuBarTeamLogoURL(
            providedURL: homeLocalLogoURL,
            team: match.homeTeam
        )
        let resolvedAwayLocalLogoURL = resolvedMenuBarTeamLogoURL(
            providedURL: awayLocalLogoURL,
            team: match.awayTeam
        )

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
            homeLocalLogoPath: isUnknownTeam(match.homeTeam) ? nil : resolvedHomeLocalLogoURL?.path,
            awayLocalLogoPath: isUnknownTeam(match.awayTeam) ? nil : resolvedAwayLocalLogoURL?.path,
            homeLogoUsesCircularOutline: match.homeTeam.isNational,
            awayLogoUsesCircularOutline: match.awayTeam.isNational
        )
    }

    static func resolvedMenuBarTeamLogoURL(
        providedURL: URL?,
        team: FootballTeamSummary
    ) -> URL? {
        if let providedURL {
            return providedURL
        }

        guard team.isNational else { return nil }
        return FootballNationalLogoResolver.localFlagImageURL(
            teamID: team.id,
            name: team.name,
            abbreviation: team.abbreviation,
            countryName: team.countryName
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

    static func fixtureContextText(for match: FootballFixtureMatch) -> String? {
        var components: [String] = []

        if let legLabel = normalizedSeriesLegLabel(for: match.seriesSummary) ?? parsedLegLabel(from: match.competitionNote) {
            components.append(legLabel)
        }

        if let aggregateText = match.seriesSummary?.aggregateScoreText ?? parsedAggregateSummaryText(from: match.competitionNote) {
            if !components.contains(aggregateText) {
                components.append(aggregateText)
            }
        }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: " • ")
    }

    static func menuBarAggregateText(for match: FootballFixtureMatch) -> String? {
        if let homeAggregateScore = match.seriesSummary?.homeAggregateScore,
           let awayAggregateScore = match.seriesSummary?.awayAggregateScore {
            return "(\(homeAggregateScore) - \(awayAggregateScore))"
        }

        guard let aggregateScores = parsedAggregateScores(from: match.competitionNote) else {
            return nil
        }

        return "(\(aggregateScores.home) - \(aggregateScores.away))"
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

    static func looksLikeFootballCalendarTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sides = trimmed.components(separatedBy: " - ")
        guard sides.count == 2 else { return false }
        return sides.allSatisfy { side in
            containsFlagEmoji(in: side) && side.rangeOfCharacter(from: .letters) != nil
        }
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
        // Flags delimit the names from the score, preserving numbers in names
        // such as Schalke 04 and 1860 Munich even before kickoff.
        let sides = title.components(separatedBy: " - ")
        if sides.count == 2,
           let homeFlagIndex = sides[0].firstIndex(where: { containsFlagEmoji(in: String($0)) }),
           let awayFlagIndex = sides[1].lastIndex(where: { containsFlagEmoji(in: String($0)) }) {
            let homeName = String(sides[0][..<homeFlagIndex])
            let awayName = String(sides[1][sides[1].index(after: awayFlagIndex)...])
            let identifiers = [homeName, awayName].map(compactIdentifier)
            guard identifiers.allSatisfy({ !$0.isEmpty }) else { return nil }
            return identifiers.joined(separator: "|")
        }

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

}
