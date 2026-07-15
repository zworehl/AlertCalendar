import Foundation

extension FootballDataAPIClient {
    struct ParsedOutcomeProbabilityCandidate {
        let probabilities: FootballMatchOutcomeProbabilities
        let priority: Int
    }

    struct OutcomeProbabilityObservationContext {
        let observedAt: Date
        let homeScore: Int?
        let awayScore: Int?
        let statusPeriod: Int?
        let statusState: FootballFixtureStatusState
    }

    static func matchOutcomeProbabilities(
        from root: [String: Any],
        competition: [String: Any]? = nil,
        observedAt: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> FootballMatchOutcomeProbabilities? {
        bestOutcomeProbability(
            from: parsedOutcomeProbabilityCandidates(
                from: root,
                competition: competition,
                observedAt: observedAt
            )
        )
    }

    static func pregameOutcomeProbabilities(
        from root: [String: Any],
        competition: [String: Any]? = nil,
        observedAt: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> FootballMatchOutcomeProbabilities? {
        bestOutcomeProbability(
            from: parsedOutcomeProbabilityCandidates(
                from: root,
                competition: competition,
                observedAt: observedAt
            ).filter { $0.probabilities.source == .marketOdds }
        )
    }

    static func parsedOutcomeProbabilityCandidates(
        from root: [String: Any],
        competition: [String: Any]?,
        observedAt: Date
    ) -> [ParsedOutcomeProbabilityCandidate] {
        var oddsEntries: [[String: Any]] = []
        let headerCompetition = ((root["header"] as? [String: Any])?["competitions"] as? [[String: Any]])?.first
        let rootCompetition = (root["competitions"] as? [[String: Any]])?.first
        let observedCompetition = competition ?? headerCompetition ?? rootCompetition
        let observationContext = outcomeProbabilityObservationContext(
            from: observedCompetition,
            observedAt: oddsObservationDate(from: root, fallback: observedAt) ?? observedAt
        )
        if let competitionOdds = competition?["odds"] as? [[String: Any]] {
            oddsEntries.append(contentsOf: competitionOdds)
        }
        if let rootOdds = root["odds"] as? [[String: Any]] {
            oddsEntries.append(contentsOf: rootOdds)
        }
        if let headerCompetition,
           let headerOdds = headerCompetition["odds"] as? [[String: Any]] {
            oddsEntries.append(contentsOf: headerOdds)
        }
        return oddsEntries.compactMap {
            matchOutcomeProbabilityCandidate(from: $0, observationContext: observationContext)
        }
    }

    static func bestOutcomeProbability(
        from candidates: [ParsedOutcomeProbabilityCandidate]
    ) -> FootballMatchOutcomeProbabilities? {
        candidates.sorted { lhs, rhs in
            let lhsIsLive = lhs.probabilities.source == .liveMarketOdds
            let rhsIsLive = rhs.probabilities.source == .liveMarketOdds
            if lhsIsLive != rhsIsLive {
                return lhsIsLive
            }
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return (lhs.probabilities.providerName ?? "") < (rhs.probabilities.providerName ?? "")
        }
        .first?
        .probabilities
    }

    static func matchOutcomeProbabilityCandidate(
        from oddsEntry: [String: Any],
        observationContext: OutcomeProbabilityObservationContext? = nil
    ) -> ParsedOutcomeProbabilityCandidate? {
        let provider = oddsEntry["provider"] as? [String: Any]
        let providerName = stringValue(provider?["displayName"])
            ?? stringValue(provider?["name"])
        let isLiveOdds = isLiveOddsEntry(
            oddsEntry,
            providerName: providerName,
            matchStatusState: observationContext?.statusState ?? .unknown
        )
        guard !isLiveOdds || !liveOddsEntryIsUnavailable(oddsEntry) else {
            return nil
        }
        let observedAt = oddsObservationDate(
            from: oddsEntry,
            fallback: observationContext?.observedAt
        )

        guard let home = impliedHomeWinProbability(from: oddsEntry),
              let draw = impliedDrawProbability(from: oddsEntry),
              let away = impliedAwayWinProbability(from: oddsEntry),
              let probabilities = FootballMatchOutcomeProbabilities(
                homeWin: home,
                draw: draw,
                awayWin: away,
                source: isLiveOdds ? .liveMarketOdds : .marketOdds,
                scope: .regulationTime,
                providerName: providerName,
                observedAt: observedAt,
                observedHomeScore: observationContext?.homeScore,
                observedAwayScore: observationContext?.awayScore,
                observedStatusPeriod: observationContext?.statusPeriod
              ) else {
            return nil
        }

        let providerPriority = intValue(provider?["priority"]) ?? 50
        return ParsedOutcomeProbabilityCandidate(
            probabilities: probabilities,
            priority: providerPriority
        )
    }

    static func outcomeProbabilityObservationContext(
        from competition: [String: Any]?,
        observedAt: Date
    ) -> OutcomeProbabilityObservationContext {
        let status = competition?["status"] as? [String: Any]
        let statusType = status?["type"] as? [String: Any]
        let competitors = competition?["competitors"] as? [[String: Any]] ?? []
        let home = competitors.first {
            stringValue($0["homeAway"])?.lowercased() == "home"
        }
        let away = competitors.first {
            stringValue($0["homeAway"])?.lowercased() == "away"
        }

        return OutcomeProbabilityObservationContext(
            observedAt: observedAt,
            homeScore: observedScore(from: home),
            awayScore: observedScore(from: away),
            statusPeriod: intValue(statusType?["period"]) ?? intValue(status?["period"]),
            statusState: matchStatusState(from: stringValue(statusType?["state"]))
        )
    }

    static func observedScore(from competitor: [String: Any]?) -> Int? {
        if let score = intValue(competitor?["score"]) {
            return max(0, score)
        }

        guard let score = competitor?["score"] as? [String: Any] else { return nil }
        return (intValue(score["value"]) ?? intValue(score["displayValue"])).map { max(0, $0) }
    }

    static func oddsObservationDate(
        from oddsEntry: [String: Any],
        fallback: Date?
    ) -> Date? {
        let bettingOdds = oddsEntry["bettingOdds"] as? [String: Any]
        let candidates: [Any?] = [
            oddsEntry["lastUpdated"], oddsEntry["lastUpdatedAt"], oddsEntry["updatedAt"],
            bettingOdds?["lastUpdated"], bettingOdds?["lastUpdatedAt"], bettingOdds?["updatedAt"],
        ]

        for candidate in candidates {
            if let text = stringValue(candidate), let date = parseEventDate(text) {
                return date
            }
            if let rawValue = candidate as? NSNumber {
                let value = rawValue.doubleValue
                if value > 1_000_000_000 {
                    return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
                }
            }
        }
        return fallback
    }

    static func isLiveOddsEntry(
        _ oddsEntry: [String: Any],
        providerName: String?,
        matchStatusState: FootballFixtureStatusState
    ) -> Bool {
        if matchStatusState == .scheduled {
            return false
        }

        if let structuredValue = structuredLiveOddsValue(from: oddsEntry) {
            return structuredValue
        }

        // ESPN's in-play feed exposes a bettingOdds object even when the provider
        // name itself does not include "live" (for example, Bet 365).
        if oddsEntry["bettingOdds"] is [String: Any] {
            return matchStatusState != .scheduled
        }

        return normalizedOddsText(providerName).contains("live")
    }

    static func structuredLiveOddsValue(from oddsEntry: [String: Any]) -> Bool? {
        let booleanKeys = [
            "isLive",
            "live",
            "isInPlay",
            "inPlay",
            "isInplay",
            "inplay",
        ]

        for key in booleanKeys where oddsEntry.keys.contains(key) {
            if let value = oddsBooleanValue(oddsEntry[key]) {
                return value
            }
        }

        for containerKey in ["status", "market", "marketStatus", "type"] {
            guard let container = oddsEntry[containerKey] as? [String: Any] else { continue }
            for key in booleanKeys where container.keys.contains(key) {
                if let value = oddsBooleanValue(container[key]) {
                    return value
                }
            }

            for key in ["name", "type", "state", "slug"] {
                let value = normalizedOddsText(stringValue(container[key]))
                if ["live", "inplay", "in-play", "in_play"].contains(value) {
                    return true
                }
                if ["pregame", "pre-game", "pre_game"].contains(value) {
                    return false
                }
            }
        }

        return nil
    }

    static func liveOddsEntryIsUnavailable(_ oddsEntry: [String: Any]) -> Bool {
        let unavailableTokens: Set<String> = [
            "closed", "inactive", "off", "suspended", "unavailable",
        ]
        var candidates: [Any?] = [
            oddsEntry["state"],
            oddsEntry["status"],
            oddsEntry["marketStatus"],
        ]

        for key in ["status", "market", "marketStatus"] {
            guard let container = oddsEntry[key] as? [String: Any] else { continue }
            candidates.append(contentsOf: [
                container["state"],
                container["status"],
                container["name"],
                container["type"],
            ])
        }

        for candidate in candidates {
            let token = normalizedOddsText(stringValue(candidate))
            if unavailableTokens.contains(token) {
                return true
            }
        }

        return false
    }

    static func oddsBooleanValue(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool {
            return value
        }
        if let value = raw as? NSNumber {
            return value.boolValue
        }
        switch normalizedOddsText(stringValue(raw)) {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    static func normalizedOddsText(_ raw: String?) -> String {
        (raw ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func impliedHomeWinProbability(from oddsEntry: [String: Any]) -> Double? {
        let moneyline = oddsEntry["moneyline"] as? [String: Any]
        if let probability = impliedCurrentProbability(fromMoneylineSide: moneyline?["home"])
            ?? impliedCurrentProbability(fromTeamOdds: oddsEntry["homeTeamOdds"]) {
            return probability
        }

        return impliedProbability(fromMoneylineSide: moneyline?["home"])
            ?? impliedProbability(fromTeamOdds: oddsEntry["homeTeamOdds"])
    }

    static func impliedAwayWinProbability(from oddsEntry: [String: Any]) -> Double? {
        let moneyline = oddsEntry["moneyline"] as? [String: Any]
        if let probability = impliedCurrentProbability(fromMoneylineSide: moneyline?["away"])
            ?? impliedCurrentProbability(fromTeamOdds: oddsEntry["awayTeamOdds"]) {
            return probability
        }

        return impliedProbability(fromMoneylineSide: moneyline?["away"])
            ?? impliedProbability(fromTeamOdds: oddsEntry["awayTeamOdds"])
    }

    static func impliedDrawProbability(from oddsEntry: [String: Any]) -> Double? {
        let moneyline = oddsEntry["moneyline"] as? [String: Any]
        if let probability = impliedCurrentProbability(fromMoneylineSide: moneyline?["draw"]) {
            return probability
        }

        if let current = oddsEntry["current"] as? [String: Any],
           let draw = current["draw"] as? [String: Any],
           let probability = impliedProbability(fromCurrentOddsQuote: draw) {
            return probability
        }

        if let probability = impliedCurrentProbability(fromTeamOdds: oddsEntry["drawOdds"]) {
            return probability
        }

        if let probability = impliedProbability(fromMoneylineSide: moneyline?["draw"]) {
            return probability
        }

        if let drawOdds = oddsEntry["drawOdds"] as? [String: Any] {
            return impliedProbability(fromDecimalOdds: drawOdds["decimal"])
                ?? impliedProbability(fromDecimalOdds: drawOdds["value"])
                ?? impliedProbability(fromAmericanOdds: drawOdds["moneyLine"])
                ?? impliedProbability(fromFractionalOdds: drawOdds["summary"])
        }

        return nil
    }

    static func impliedProbability(fromMoneylineSide rawSide: Any?) -> Double? {
        guard let side = rawSide as? [String: Any] else { return nil }

        if let probability = impliedCurrentProbability(fromMoneylineSide: side) {
            return probability
        }

        if let close = side["close"] as? [String: Any],
           let probability = impliedProbability(fromAmericanOdds: close["odds"])
            ?? impliedProbability(fromAmericanOdds: close["american"])
            ?? impliedProbability(fromAmericanOdds: close["alternateDisplayValue"]) {
            return probability
        }

        if let open = side["open"] as? [String: Any],
           let probability = impliedProbability(fromAmericanOdds: open["odds"])
            ?? impliedProbability(fromAmericanOdds: open["american"])
            ?? impliedProbability(fromAmericanOdds: open["alternateDisplayValue"]) {
            return probability
        }

        return impliedProbability(fromAmericanOdds: side["odds"])
            ?? impliedProbability(fromAmericanOdds: side["moneyLine"])
    }

    static func impliedCurrentProbability(fromMoneylineSide rawSide: Any?) -> Double? {
        guard let side = rawSide as? [String: Any],
              let current = side["current"] as? [String: Any] else {
            return nil
        }

        if let moneyline = current["moneyLine"] as? [String: Any],
           let probability = impliedProbability(fromCurrentOddsQuote: moneyline) {
            return probability
        }

        return impliedProbability(fromCurrentOddsQuote: current)
    }

    static func impliedProbability(fromCurrentOddsQuote quote: [String: Any]) -> Double? {
        impliedProbability(fromDecimalOdds: quote["decimal"])
            ?? impliedProbability(fromDecimalOdds: quote["value"])
            ?? impliedProbability(fromAmericanOdds: quote["odds"])
            ?? impliedProbability(fromAmericanOdds: quote["alternateDisplayValue"])
            ?? impliedProbability(fromAmericanOdds: quote["american"])
    }

    static func impliedProbability(fromTeamOdds rawTeamOdds: Any?) -> Double? {
        guard let teamOdds = rawTeamOdds as? [String: Any] else { return nil }

        if let probability = impliedCurrentProbability(fromTeamOdds: teamOdds) {
            return probability
        }

        if let odds = teamOdds["odds"] as? [String: Any],
           let probability = impliedProbability(fromDecimalOdds: odds["decimal"])
            ?? impliedProbability(fromDecimalOdds: odds["value"])
            ?? impliedProbability(fromAmericanOdds: odds["alternateDisplayValue"])
            ?? impliedProbability(fromAmericanOdds: odds["american"])
            ?? impliedProbability(fromFractionalOdds: odds["summary"]) {
            return probability
        }

        if let open = teamOdds["open"] as? [String: Any],
           let moneyline = open["moneyLine"] as? [String: Any],
           let probability = impliedProbability(fromDecimalOdds: moneyline["decimal"])
            ?? impliedProbability(fromDecimalOdds: moneyline["value"])
            ?? impliedProbability(fromAmericanOdds: moneyline["alternateDisplayValue"])
            ?? impliedProbability(fromAmericanOdds: moneyline["american"]) {
            return probability
        }

        return impliedProbability(fromAmericanOdds: teamOdds["moneyLine"])
    }

    static func impliedCurrentProbability(fromTeamOdds rawTeamOdds: Any?) -> Double? {
        guard let teamOdds = rawTeamOdds as? [String: Any],
              let current = teamOdds["current"] as? [String: Any] else {
            return nil
        }

        if let moneyline = current["moneyLine"] as? [String: Any],
           let probability = impliedProbability(fromCurrentOddsQuote: moneyline) {
            return probability
        }

        return impliedProbability(fromCurrentOddsQuote: current)
    }

    static func impliedProbability(fromAmericanOdds raw: Any?) -> Double? {
        guard let value = doubleValue(raw), value != 0 else { return nil }

        if value < 0 {
            let absoluteValue = abs(value)
            return absoluteValue / (absoluteValue + 100)
        }

        return 100 / (value + 100)
    }

    static func impliedProbability(fromDecimalOdds raw: Any?) -> Double? {
        guard let value = doubleValue(raw), value > 1 else { return nil }
        return 1 / value
    }

    static func impliedProbability(fromFractionalOdds raw: Any?) -> Double? {
        guard let value = stringValue(raw) else { return nil }
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[0] >= 0, parts[1] > 0 else { return nil }
        return parts[1] / (parts[0] + parts[1])
    }

    static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double {
            return value
        }
        if let value = raw as? Float {
            return Double(value)
        }
        if let value = raw as? Int {
            return Double(value)
        }
        if let value = raw as? NSNumber {
            return value.doubleValue
        }
        if let value = stringValue(raw) {
            let normalized = value
                .replacingOccurrences(of: "+", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(normalized)
        }
        return nil
    }
}
