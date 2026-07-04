import Foundation

enum FootballLiveMatchPhase: Equatable, Sendable {
    case firstHalf
    case halfTime
    case secondHalf
    case extraTime
    case penalties
    case unknown
}

struct FootballStatusMinuteComponents: Equatable, Sendable {
    let baseMinute: Int
    let stoppageMinute: Int

    var combinedMinute: Int {
        baseMinute + stoppageMinute
    }
}

extension CalendarMonitor {
    nonisolated static func footballStatusWarningText(for match: FootballFixtureMatch) -> String? {
        switch match.statusReliability {
        case .reported, .awaitingLiveData:
            return nil
        case .delayedLiveData:
            return "Kickoff time has passed, but ESPN still has not confirmed live match data for this fixture."
        }
    }

    nonisolated static func footballStatusWarningSummary(for match: FootballFixtureMatch) -> String? {
        switch match.statusReliability {
        case .reported, .awaitingLiveData:
            return nil
        case .delayedLiveData:
            return "Live data fetch delayed"
        }
    }

    nonisolated static func footballExtraTimeStillLooksLikely(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Bool {
        if footballScoresAreLevel(match) {
            return true
        }

        let relevantScores = footballRelevantScores(for: match)
        let goalMargin = abs(relevantScores.home - relevantScores.away)
        let minute = footballLiveMinute(for: match, now: now) ?? 0

        if goalMargin >= 2 {
            return minute < 35
        }

        return minute < 72
    }

    nonisolated static func footballStatusIndicatesExtraTime(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Bool {
        let minute = footballLiveMinute(for: match, now: now)

        if footballStatusConfirmsExtraTime(match) {
            return true
        }

        guard footballCanReachExtraTime(match) else { return false }
        guard footballScoresAreLevel(match) else { return false }

        if let minute, minute >= 90 {
            return true
        }

        return false
    }

    nonisolated static func footballStatusConfirmsExtraTime(_ match: FootballFixtureMatch) -> Bool {
        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        let normalizedDetail = footballNormalizedStatusText(match.statusDetailText ?? "")

        if normalizedStatus.contains("AET") || normalizedDetail.contains("AET") {
            return true
        }

        if normalizedStatus == "ET"
            || normalizedStatus.contains("EXTRA TIME")
            || normalizedDetail == "ET"
            || normalizedDetail.contains("EXTRA TIME") {
            return true
        }

        if (footballParsedMinuteComponents(from: match.statusText)?.baseMinute ?? 0) > 90 {
            return true
        }

        if let statusDetailText = match.statusDetailText,
           (footballParsedMinuteComponents(from: statusDetailText)?.baseMinute ?? 0) > 90 {
            return true
        }

        return footballStatusPeriodIndicatesExtraTime(match.statusPeriod)
    }

    nonisolated static func footballStatusIndicatesPenaltyShootout(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Bool {
        let minute = footballLiveMinute(for: match, now: now)

        if footballStatusConfirmsPenaltyShootout(match) {
            return true
        }

        if footballStatusConfirmsExtraTime(match) {
            return false
        }

        guard footballCanReachExtraTime(match) else { return false }
        guard footballScoresAreLevel(match) else { return false }

        if let minute, minute >= footballPenaltyShootoutInferenceMinute {
            return true
        }

        return false
    }

    nonisolated static func footballStatusConfirmsPenaltyShootout(_ match: FootballFixtureMatch) -> Bool {
        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        let normalizedDetail = footballNormalizedStatusText(match.statusDetailText ?? "")
        let normalizedNote = footballNormalizedStatusText(match.competitionNote ?? "")

        if FootballStatusText.indicatesPenaltyShootout(normalizedStatus) {
            return true
        }

        if FootballStatusText.indicatesPenaltyShootout(normalizedDetail) {
            return true
        }

        if footballStatusPeriodIndicatesPenaltyShootout(match.statusPeriod) {
            return true
        }

        return FootballStatusText.indicatesPenaltyShootout(normalizedNote)
    }

    nonisolated static func footballCanReachExtraTime(_ match: FootballFixtureMatch) -> Bool {
        switch match.competitionSlug {
        case "eng.1", "esp.1", "bra.1", "ita.1", "ger.1", "fra.1", "por.1", "arg.1", "ned.1", "col.1", "mex.1", "usa.1", "fifa.friendly":
            return false
        case "uefa.super_cup":
            return true
        case "fifa.world", "uefa.euro", "conmebol.america", "fifa.cwc", "concacaf.gold", "caf.nations", "afc.asian.cup":
            return footballIsSingleMatchKnockoutContext(match)
        case "uefa.champions", "uefa.europa":
            return footballIsFinalContext(match) || footballIsSecondLegContext(match)
        case "conmebol.libertadores":
            return footballIsFinalContext(match) || footballIsSecondLegContext(match)
        default:
            return false
        }
    }

    nonisolated static func footballStatusPeriodIndicatesExtraTime(_ statusPeriod: Int?) -> Bool {
        guard let statusPeriod else { return false }
        return statusPeriod >= 4
    }

    nonisolated static func footballStatusPeriodIndicatesPenaltyShootout(_ statusPeriod: Int?) -> Bool {
        guard let statusPeriod else { return false }
        return statusPeriod >= 5
    }

    nonisolated static func footballIsSingleMatchKnockoutContext(_ match: FootballFixtureMatch) -> Bool {
        guard !footballContainsAnyContextToken(match, tokens: ["group", "regular", "league", "season", "matchday"]) else {
            return false
        }

        return footballContainsAnyContextToken(
            match,
            tokens: ["round", "quarterfinal", "quarterfinals", "quarter", "semifinal", "semifinals", "semi", "final", "finals", "knockout"]
        )
    }

    nonisolated static func footballIsSecondLegContext(_ match: FootballFixtureMatch) -> Bool {
        if match.seriesSummary?.isSecondLeg == true {
            return true
        }

        let normalizedNote = footballNormalizedStatusText(match.competitionNote ?? "")
        return normalizedNote.contains("2ND LEG")
            || normalizedNote.contains("SECOND LEG")
            || normalizedNote.contains("TIED ON AGGREGATE")
    }

    nonisolated static func footballIsFinalContext(_ match: FootballFixtureMatch) -> Bool {
        let words = footballContextWords(for: match)
        return words.contains("final") || words.contains("finals")
    }

    nonisolated static func footballContainsAnyContextToken(
        _ match: FootballFixtureMatch,
        tokens: Set<String>
    ) -> Bool {
        !footballContextWords(for: match).isDisjoint(with: tokens)
    }

    nonisolated static func footballContextWords(for match: FootballFixtureMatch) -> Set<String> {
        let rawValues = [
            match.competitionStage,
            match.seasonSlug,
            match.competitionNote,
        ]

        return rawValues.reduce(into: Set<String>()) { partialResult, value in
            guard let value else { return }
            let normalized = value
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
            let tokens = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            partialResult.formUnion(tokens)
        }
    }

    nonisolated static func footballGoalValue(_ rawScore: String) -> Int {
        let trimmed = rawScore.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed) ?? 0
    }

    nonisolated static func footballEffectiveStartDate(for match: FootballFixtureMatch) -> Date {
        match.actualStartDate ?? match.startDate
    }

    nonisolated static func footballPreferredStatusDetailText(
        current: String?,
        fallback: String?
    ) -> String? {
        if let current, !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return current
        }
        return fallback
    }

    nonisolated static func footballPreferredStatusPeriod(
        for match: FootballFixtureMatch,
        previousMatch: FootballFixtureMatch
    ) -> Int? {
        guard let previousStatusPeriod = previousMatch.statusPeriod else {
            return match.statusPeriod
        }

        guard let currentStatusPeriod = match.statusPeriod else {
            return previousStatusPeriod
        }

        guard match.statusState == .finished else {
            return currentStatusPeriod
        }

        return max(currentStatusPeriod, previousStatusPeriod)
    }

    nonisolated static func footballScoresAreLevel(_ match: FootballFixtureMatch) -> Bool {
        let relevantScores = footballRelevantScores(for: match)
        return relevantScores.home == relevantScores.away
    }

    nonisolated static func footballRelevantScores(
        for match: FootballFixtureMatch
    ) -> (home: Int, away: Int) {
        if footballIsSecondLegContext(match),
           let homeAggregateScore = match.seriesSummary?.homeAggregateScore,
           let awayAggregateScore = match.seriesSummary?.awayAggregateScore {
            return (homeAggregateScore, awayAggregateScore)
        }

        return (
            footballGoalValue(match.homeScore),
            footballGoalValue(match.awayScore)
        )
    }

}
