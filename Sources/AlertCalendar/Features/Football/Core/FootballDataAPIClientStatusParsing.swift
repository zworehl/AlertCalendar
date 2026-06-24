import Foundation

extension FootballDataAPIClient {
    static func matchStatusState(from raw: String?) -> FootballFixtureStatusState {
        switch raw?.lowercased() {
        case "pre":
            return .scheduled
        case "in":
            return .inProgress
        case "post":
            return .finished
        default:
            return .unknown
        }
    }

    static func preferredStatusText(
        shortDetail: String?,
        detail: String?,
        displayClock: String?
    ) -> String {
        let resolvedShortDetail = shortDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayClock = displayClock?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let resolvedShortDetail, !resolvedShortDetail.isEmpty {
            if let resolvedDetail,
               statusTextShouldPreferDetail(shortDetail: resolvedShortDetail, detail: resolvedDetail) {
                return resolvedDetail
            }

            return resolvedShortDetail
        }

        if let resolvedDetail, !resolvedDetail.isEmpty {
            return resolvedDetail
        }

        if let resolvedDisplayClock, !resolvedDisplayClock.isEmpty {
            return resolvedDisplayClock
        }

        return "LIVE"
    }

    static func supplementalStatusText(
        preferredStatusText: String,
        detail: String?,
        displayClock: String?
    ) -> String? {
        let normalizedPreferred = normalizedStatusToken(preferredStatusText)
        let resolvedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayClock = displayClock?.trimmingCharacters(in: .whitespacesAndNewlines)

        if FootballStatusText.indicatesInterruptedPlay(normalizedPreferred) {
            if let resolvedDetail,
               !resolvedDetail.isEmpty,
               normalizedStatusToken(resolvedDetail) != normalizedPreferred,
               statusTextLooksLikeMinute(resolvedDetail) {
                return resolvedDetail
            }

            if let resolvedDisplayClock,
               !resolvedDisplayClock.isEmpty,
               normalizedStatusToken(resolvedDisplayClock) != normalizedPreferred,
               statusTextLooksLikeMinute(resolvedDisplayClock) {
                return resolvedDisplayClock
            }
        }

        let candidates = [
            resolvedDetail,
            resolvedDisplayClock,
        ]

        for candidate in candidates {
            guard let candidate, !candidate.isEmpty else { continue }
            if normalizedStatusToken(candidate) != normalizedPreferred {
                return candidate
            }
        }

        return nil
    }

    static func inferredKickoffStatusIfNeeded(
        from state: FootballFixtureStatusState,
        statusText: String,
        startDate: Date,
        now: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> (
        state: FootballFixtureStatusState,
        statusText: String,
        statusReliability: FootballFixtureStatusReliability,
        inferred: Bool
    ) {
        let secondsFromKickoff = now.timeIntervalSince(startDate)
        guard secondsFromKickoff >= 0 else {
            return (state, statusText, .reported, false)
        }

        guard state == .scheduled else {
            return (state, statusText, .reported, false)
        }

        if statusTextShouldRemainAsReported(statusText) {
            return (state, statusText, .reported, false)
        }

        let reliability: FootballFixtureStatusReliability
        if secondsFromKickoff >= delayedLiveDataWarningAfterKickoff {
            reliability = .delayedLiveData
        } else {
            reliability = .awaitingLiveData
        }

        return (.scheduled, "Starting soon", reliability, true)
    }

    static func statusTextShouldRemainAsReported(_ statusText: String) -> Bool {
        FootballStatusText.indicatesInterruptedPlay(normalizedStatusToken(statusText))
    }

    static func statusTextShouldPreferDetail(shortDetail: String, detail: String) -> Bool {
        let normalizedShort = normalizedStatusToken(shortDetail)
        let normalizedDetail = normalizedStatusToken(detail)

        if normalizedDetail.isEmpty || normalizedShort == normalizedDetail {
            return false
        }

        if FootballStatusText.indicatesInterruptedPlay(normalizedShort) {
            return false
        }

        if FootballStatusText.indicatesInterruptedPlay(normalizedDetail)
            && !FootballStatusText.indicatesInterruptedPlay(normalizedShort) {
            return true
        }

        if statusTextLooksLikeMinute(detail) && !statusTextLooksLikeMinute(shortDetail) {
            return true
        }

        let preciseTokens = ["FT", "HT", "ET", "AET", "PEN", "PK", "PENALTY", "EXTRA TIME"]
        let detailIsPrecise = preciseTokens.contains { normalizedDetail.contains($0) }
        let shortIsPrecise = preciseTokens.contains { normalizedShort.contains($0) }

        return detailIsPrecise && !shortIsPrecise
    }

    static func statusTextLooksLikeMinute(_ text: String) -> Bool {
        let pattern = #"\d{1,3}\s*['’]?(?:\s*\+\s*\d{1,2})?\s*['’]"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func normalizedStatusToken(_ text: String) -> String {
        FootballStatusText.normalized(text)
    }

    static func parseEventDate(_ rawDate: String) -> Date? {
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatterWithFraction.date(from: rawDate) {
            return value
        }

        let formatterWithSeconds = gregorianPOSIXDateFormatter("yyyy-MM-dd'T'HH:mm:ssX")
        if let value = formatterWithSeconds.date(from: rawDate) {
            return value
        }

        let formatterWithoutSeconds = gregorianPOSIXDateFormatter("yyyy-MM-dd'T'HH:mmX")
        return formatterWithoutSeconds.date(from: rawDate)
    }

    static func gregorianPOSIXDateFormatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        return formatter
    }

    static func parsedEventDate(from event: [String: Any]) -> Date? {
        guard let rawDate = stringValue(event["date"]) else { return nil }
        return parseEventDate(rawDate)
    }

    static func displayLeagueName(from rawSlug: String) -> String {
        rawSlug
            .replacingOccurrences(
                of: #"^\d{4}-\d{2}-"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    static func competitionDisplayName(from league: [String: Any]?) -> String? {
        stringValue(league?["name"])
    }

    static func leagueStageName(from league: [String: Any]?) -> String? {
        let season = league?["season"] as? [String: Any]
        let type = season?["type"] as? [String: Any]
        return stringValue(type?["name"])
            ?? stringValue(type?["abbreviation"])
            ?? stringValue(season?["displayName"])
    }

    static func leagueLogoURL(from league: [String: Any]?) -> URL? {
        let logos = league?["logos"] as? [[String: Any]] ?? []
        if let preferred = logos.first(where: { (($0["rel"] as? [String]) ?? []).contains("default") }),
           let href = safeURL(from: stringValue(preferred["href"])) {
            return href
        }
        return logos.first.flatMap { safeURL(from: stringValue($0["href"])) }
    }

    static func teamName(from team: [String: Any]) -> String {
        stringValue(team["shortDisplayName"])
            ?? stringValue(team["displayName"])
            ?? stringValue(team["name"])
            ?? "Unknown"
    }

    static func competitionNoteText(from competition: [String: Any]) -> String? {
        let notes = competition["notes"] as? [[String: Any]] ?? []
        for note in notes {
            if let value = stringValue(note["headline"])
                ?? stringValue(note["shortText"])
                ?? stringValue(note["text"])
                ?? stringValue(note["detail"]) {
                return value
            }
        }
        return nil
    }

    static func seriesSummary(
        from competition: [String: Any],
        homeCompetitor: [String: Any]?,
        awayCompetitor: [String: Any]?
    ) -> FootballFixtureSeriesSummary? {
        let leg = competition["leg"] as? [String: Any]
        let legNumber = intValue(leg?["value"])
        let legLabel = stringValue(leg?["displayValue"])
            ?? stringValue(leg?["label"])
            ?? stringValue(leg?["description"])

        let series = competition["series"] as? [String: Any]
        let seriesTitle = stringValue(series?["title"])
        let totalLegs = intValue(series?["totalCompetitions"])
        let seriesCompetitors = series?["competitors"] as? [[String: Any]] ?? []

        let homeAggregateScore = aggregateScore(
            for: homeCompetitor,
            fallbackSeriesCompetitors: seriesCompetitors
        )
        let awayAggregateScore = aggregateScore(
            for: awayCompetitor,
            fallbackSeriesCompetitors: seriesCompetitors
        )

        guard legNumber != nil
            || legLabel != nil
            || seriesTitle != nil
            || totalLegs != nil
            || homeAggregateScore != nil
            || awayAggregateScore != nil else {
            return nil
        }

        return FootballFixtureSeriesSummary(
            legNumber: legNumber,
            legLabel: legLabel,
            seriesTitle: seriesTitle,
            totalLegs: totalLegs,
            homeAggregateScore: homeAggregateScore,
            awayAggregateScore: awayAggregateScore
        )
    }

    static func aggregateScore(
        for competitor: [String: Any]?,
        fallbackSeriesCompetitors: [[String: Any]]
    ) -> Int? {
        if let directAggregate = intValue(competitor?["aggregateScore"]) {
            return directAggregate
        }

        let competitorID = stringValue(competitor?["id"])
            ?? stringValue((competitor?["team"] as? [String: Any])?["id"])

        if let competitorID,
           let seriesCompetitor = fallbackSeriesCompetitors.first(where: { seriesCompetitor in
               let seriesCompetitorID = stringValue(seriesCompetitor["id"])
                   ?? stringValue((seriesCompetitor["team"] as? [String: Any])?["id"])
               return seriesCompetitorID == competitorID
           }) {
            return intValue(seriesCompetitor["aggregateScore"])
        }

        return nil
    }


}
