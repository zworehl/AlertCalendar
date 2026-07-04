import Foundation

extension FootballDataAPIClient {
    struct ParsedOutcomeProbabilityCandidate {
        let probabilities: FootballMatchOutcomeProbabilities
        let priority: Int
    }

    static func matchOutcomeProbabilities(
        from root: [String: Any],
        competition: [String: Any]? = nil
    ) -> FootballMatchOutcomeProbabilities? {
        var oddsEntries: [[String: Any]] = []

        if let competitionOdds = competition?["odds"] as? [[String: Any]] {
            oddsEntries.append(contentsOf: competitionOdds)
        }

        if let rootOdds = root["odds"] as? [[String: Any]] {
            oddsEntries.append(contentsOf: rootOdds)
        }

        if let headerCompetition = ((root["header"] as? [String: Any])?["competitions"] as? [[String: Any]])?.first,
           let headerOdds = headerCompetition["odds"] as? [[String: Any]] {
            oddsEntries.append(contentsOf: headerOdds)
        }

        let parsed = oddsEntries.compactMap(matchOutcomeProbabilityCandidate)
        return parsed.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return (lhs.probabilities.providerName ?? "") < (rhs.probabilities.providerName ?? "")
        }
        .first?
        .probabilities
    }

    static func matchOutcomeProbabilityCandidate(
        from oddsEntry: [String: Any]
    ) -> ParsedOutcomeProbabilityCandidate? {
        let provider = oddsEntry["provider"] as? [String: Any]
        let providerName = stringValue(provider?["displayName"])
            ?? stringValue(provider?["name"])
        let isLiveOdds = providerName?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .contains("live") == true

        guard let home = impliedHomeWinProbability(from: oddsEntry),
              let draw = impliedDrawProbability(from: oddsEntry),
              let away = impliedAwayWinProbability(from: oddsEntry),
              let probabilities = FootballMatchOutcomeProbabilities(
                homeWin: home,
                draw: draw,
                awayWin: away,
                source: isLiveOdds ? .liveMarketOdds : .marketOdds,
                scope: .regulationTime,
                providerName: providerName
              ) else {
            return nil
        }

        let providerPriority = intValue(provider?["priority"]) ?? 50
        let priority = (isLiveOdds ? 0 : 20) + providerPriority
        return ParsedOutcomeProbabilityCandidate(
            probabilities: probabilities,
            priority: priority
        )
    }

    static func impliedHomeWinProbability(from oddsEntry: [String: Any]) -> Double? {
        if let moneyline = oddsEntry["moneyline"] as? [String: Any],
           let probability = impliedProbability(fromMoneylineSide: moneyline["home"]) {
            return probability
        }

        return impliedProbability(fromTeamOdds: oddsEntry["homeTeamOdds"])
    }

    static func impliedAwayWinProbability(from oddsEntry: [String: Any]) -> Double? {
        if let moneyline = oddsEntry["moneyline"] as? [String: Any],
           let probability = impliedProbability(fromMoneylineSide: moneyline["away"]) {
            return probability
        }

        return impliedProbability(fromTeamOdds: oddsEntry["awayTeamOdds"])
    }

    static func impliedDrawProbability(from oddsEntry: [String: Any]) -> Double? {
        if let moneyline = oddsEntry["moneyline"] as? [String: Any],
           let probability = impliedProbability(fromMoneylineSide: moneyline["draw"]) {
            return probability
        }

        if let current = oddsEntry["current"] as? [String: Any],
           let draw = current["draw"] as? [String: Any],
           let probability = impliedProbability(fromDecimalOdds: draw["decimal"])
            ?? impliedProbability(fromDecimalOdds: draw["value"])
            ?? impliedProbability(fromAmericanOdds: draw["alternateDisplayValue"])
            ?? impliedProbability(fromAmericanOdds: draw["american"]) {
            return probability
        }

        if let drawOdds = oddsEntry["drawOdds"] as? [String: Any] {
            return impliedProbability(fromAmericanOdds: drawOdds["moneyLine"])
                ?? impliedProbability(fromDecimalOdds: drawOdds["decimal"])
                ?? impliedProbability(fromDecimalOdds: drawOdds["value"])
                ?? impliedProbability(fromFractionalOdds: drawOdds["summary"])
        }

        return nil
    }

    static func impliedProbability(fromMoneylineSide rawSide: Any?) -> Double? {
        guard let side = rawSide as? [String: Any] else { return nil }

        if let close = side["close"] as? [String: Any],
           let probability = impliedProbability(fromAmericanOdds: close["odds"])
            ?? impliedProbability(fromAmericanOdds: close["american"])
            ?? impliedProbability(fromAmericanOdds: close["alternateDisplayValue"]) {
            return probability
        }

        if let current = side["current"] as? [String: Any],
           let moneyline = current["moneyLine"] as? [String: Any],
           let probability = impliedProbability(fromDecimalOdds: moneyline["decimal"])
            ?? impliedProbability(fromDecimalOdds: moneyline["value"])
            ?? impliedProbability(fromAmericanOdds: moneyline["alternateDisplayValue"])
            ?? impliedProbability(fromAmericanOdds: moneyline["american"]) {
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

    static func impliedProbability(fromTeamOdds rawTeamOdds: Any?) -> Double? {
        guard let teamOdds = rawTeamOdds as? [String: Any] else { return nil }

        if let current = teamOdds["current"] as? [String: Any],
           let moneyline = current["moneyLine"] as? [String: Any],
           let probability = impliedProbability(fromDecimalOdds: moneyline["decimal"])
            ?? impliedProbability(fromDecimalOdds: moneyline["value"])
            ?? impliedProbability(fromAmericanOdds: moneyline["alternateDisplayValue"])
            ?? impliedProbability(fromAmericanOdds: moneyline["american"]) {
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
