import Foundation

extension FootballFixtureFormatter {
    static func normalizedSeriesLegLabel(for seriesSummary: FootballFixtureSeriesSummary?) -> String? {
        guard let rawLabel = seriesSummary?.legLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawLabel.isEmpty else {
            return nil
        }
        return rawLabel
    }

    static func parsedLegLabel(from competitionNote: String?) -> String? {
        guard let competitionNote else { return nil }
        let normalizedNote = competitionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNote.isEmpty else { return nil }

        if normalizedNote.range(of: #"(?i)\b2nd\s+leg\b"#, options: .regularExpression) != nil
            || normalizedNote.range(of: #"(?i)\bsecond\s+leg\b"#, options: .regularExpression) != nil {
            return "2nd Leg"
        }

        if normalizedNote.range(of: #"(?i)\b1st\s+leg\b"#, options: .regularExpression) != nil
            || normalizedNote.range(of: #"(?i)\bfirst\s+leg\b"#, options: .regularExpression) != nil {
            return "1st Leg"
        }

        return nil
    }

    static func parsedAggregateSummaryText(from competitionNote: String?) -> String? {
        guard let competitionNote else { return nil }
        let normalizedNote = competitionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNote.isEmpty else { return nil }

        if normalizedNote.range(of: #"(?i)\btied on aggregate\b"#, options: .regularExpression) != nil {
            return "Agg level"
        }

        guard let aggregateScores = parsedAggregateScores(from: competitionNote) else {
            return nil
        }

        return "Agg \(aggregateScores.home)-\(aggregateScores.away)"
    }

    static func parsedAggregateScores(from competitionNote: String?) -> (home: String, away: String)? {
        guard let competitionNote else { return nil }
        let normalizedNote = competitionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNote.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(pattern: #"(?i)\b(\d+)\s*-\s*(\d+)\s+on aggregate\b"#),
              let match = regex.firstMatch(
                  in: normalizedNote,
                  range: NSRange(normalizedNote.startIndex..., in: normalizedNote)
              ),
              let homeRange = Range(match.range(at: 1), in: normalizedNote),
              let awayRange = Range(match.range(at: 2), in: normalizedNote) else {
            return nil
        }

        return (
            home: String(normalizedNote[homeRange]),
            away: String(normalizedNote[awayRange])
        )
    }

    static func normalizedCompetitionComparisonKey(_ raw: String) -> String {
        raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.allSatisfy(\.isNumber) }
            .joined(separator: " ")
    }
}
