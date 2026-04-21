import AppKit
import CoreLocation
import EventKit
import Foundation

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
        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        let minute = footballLiveMinute(for: match, now: now)

        if normalizedStatus.contains("AET") {
            return true
        }

        if normalizedStatus == "ET" || normalizedStatus.contains("EXTRA TIME") {
            return true
        }

        if footballStatusPeriodIndicatesExtraTime(match.statusPeriod) {
            return true
        }

        guard footballCanReachExtraTime(match) else { return false }
        guard footballScoresAreLevel(match) else { return false }

        if let minute, minute >= 90 {
            return true
        }

        return false
    }

    nonisolated static func footballStatusIndicatesPenaltyShootout(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Bool {
        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        let normalizedNote = footballNormalizedStatusText(match.competitionNote ?? "")
        let minute = footballLiveMinute(for: match, now: now)

        if normalizedStatus.contains("PEN") || normalizedStatus == "PK" || normalizedStatus.contains("PENALTY") {
            return true
        }

        if footballStatusPeriodIndicatesPenaltyShootout(match.statusPeriod) {
            return true
        }

        if normalizedNote.contains("PENALTY") || normalizedNote.contains("PENALTIES") {
            return true
        }

        guard footballCanReachExtraTime(match) else { return false }
        guard footballScoresAreLevel(match) else { return false }

        if let minute, minute >= 120 {
            return true
        }

        return false
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

    nonisolated static func footballLiveMinute(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Int? {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return nil
        }

        let normalizedStatus = footballNormalizedStatusText(match.statusText)

        if footballInterruptedStatusBadgeText(from: normalizedStatus) != nil {
            return nil
        }

        if normalizedStatus == "HT" || normalizedStatus.contains("HALF") {
            return 45
        }

        if normalizedStatus.contains("PEN") || normalizedStatus == "PK" {
            return 121
        }

        if normalizedStatus == "ET" || normalizedStatus.contains("EXTRA TIME") {
            return 91
        }

        if let parsed = footballParsedMinute(from: match.statusText) {
            return parsed
        }

        guard match.statusState == .inProgress
            || (match.statusState == .unknown && footballEffectiveStartDate(for: match) <= now) else {
            return nil
        }

        return footballInferredMinuteFromKickoff(for: match, now: now)
    }

    nonisolated static func footballInterruptedMatchDuration(
        for match: FootballFixtureMatch,
        badgeText: String
    ) -> TimeInterval {
        switch badgeText {
        case "ABN", "CANC.":
            if let minute = footballReportedStatusMinute(for: match) {
                return footballDuration(forReportedMinute: minute)
            }
            return footballRegulationMatchDuration
        case "SUSP.", "POSTP.", "DELAY":
            return footballRegulationMatchDuration
        default:
            return footballRegulationMatchDuration
        }
    }

    nonisolated static func footballInferredMinuteFromKickoff(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Int? {
        let elapsedSeconds = max(0, now.timeIntervalSince(footballEffectiveStartDate(for: match)))
        let rawMinutes = Int(elapsedSeconds / 60)
        if rawMinutes <= 45 {
            return rawMinutes
        }
        if rawMinutes <= 60 {
            return 45
        }
        return max(46, rawMinutes - 15)
    }

    nonisolated static func shouldPreferInferredLiveMinute(
        reportedMinute: Int,
        inferredMinute: Int,
        match: FootballFixtureMatch
    ) -> Bool {
        guard match.statusState == .inProgress,
              match.statusReliability == .reported else {
            return false
        }

        guard inferredMinute >= 60 else { return false }
        return inferredMinute - reportedMinute >= 35
    }

    nonisolated static func footballReportedStatusMinute(for match: FootballFixtureMatch) -> Int? {
        if let parsed = footballParsedMinute(from: match.statusText) {
            return parsed
        }

        guard let statusDetailText = match.statusDetailText else { return nil }
        return footballParsedMinute(from: statusDetailText)
    }

    nonisolated static func footballDuration(forReportedMinute minute: Int) -> TimeInterval {
        let elapsedMinutes: Int
        if minute <= 45 {
            elapsedMinutes = minute
        } else if minute <= 90 {
            elapsedMinutes = minute + 15
        } else {
            elapsedMinutes = minute + 20
        }

        return TimeInterval(max(15, elapsedMinutes) * 60)
    }

    nonisolated static func footballParsedMinute(from rawStatusText: String) -> Int? {
        let trimmed = rawStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"(\d{1,3})(?:\+(\d{1,2}))?\s*'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: trimmed,
                  range: NSRange(trimmed.startIndex..., in: trimmed)
              ) else {
            return nil
        }

        let baseMinute = footballRegexInt(match, in: trimmed, at: 1) ?? 0
        let extraMinute = footballRegexInt(match, in: trimmed, at: 2) ?? 0
        let combinedMinute = baseMinute + extraMinute
        return combinedMinute > 0 ? combinedMinute : nil
    }

    nonisolated static func footballInterruptedStatusBadgeText(from normalizedStatus: String) -> String? {
        FootballStatusText.interruptedBadge(for: normalizedStatus)
    }

    nonisolated static func footballRegexInt(_ result: NSTextCheckingResult, in text: String, at index: Int) -> Int? {
        guard index < result.numberOfRanges else { return nil }
        let range = result.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: text) else {
            return nil
        }
        return Int(text[swiftRange])
    }

    nonisolated static func footballLooksLikeMinuteStatus(_ rawStatusText: String) -> Bool {
        footballParsedMinute(from: rawStatusText) != nil
    }

    nonisolated static func footballNormalizedStatusText(_ rawStatusText: String) -> String {
        FootballStatusText.normalized(rawStatusText)
    }

    nonisolated static func footballLocalizedDateFormatter(
        template: String,
        locale: Locale,
        timeZone: TimeZone
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

}
