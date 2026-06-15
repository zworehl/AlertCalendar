import Foundation

extension FootballDataAPIClient {
    static func matchGoalScorers(from root: [String: Any], match: FootballFixtureMatch) -> FootballMatchGoalScorers? {
        guard match.totalGoals > 0 else { return nil }
        guard match.statusState != .scheduled else { return nil }

        let competitors = ((root["header"] as? [String: Any])?["competitions"] as? [[String: Any]])?
            .first?["competitors"] as? [[String: Any]] ?? []

        let homeCompetitor = competitors.first(where: { Self.stringValue($0["homeAway"])?.lowercased() == "home" })
        let awayCompetitor = competitors.first(where: { Self.stringValue($0["homeAway"])?.lowercased() == "away" })

        let homeTeam = homeCompetitor?["team"] as? [String: Any] ?? [:]
        let awayTeam = awayCompetitor?["team"] as? [String: Any] ?? [:]
        let homeTeamID = stringValue(homeTeam["id"]) ?? stringValue(homeCompetitor?["id"]) ?? match.homeTeam.id
        let awayTeamID = stringValue(awayTeam["id"]) ?? stringValue(awayCompetitor?["id"]) ?? match.awayTeam.id
        let homeTeamName = stringValue(homeTeam["displayName"])
            ?? stringValue(homeTeam["shortDisplayName"])
            ?? match.homeTeam.name
        let awayTeamName = stringValue(awayTeam["displayName"])
            ?? stringValue(awayTeam["shortDisplayName"])
            ?? match.awayTeam.name

        let keyEvents = ((root["keyEvents"] as? [[String: Any]]) ?? [])
            + ((root["scoringPlays"] as? [[String: Any]]) ?? [])
        var homeScorers: [FootballMatchGoalScorer] = []
        var awayScorers: [FootballMatchGoalScorer] = []
        var seenEventSignatures = Set<String>()

        for (index, event) in keyEvents.enumerated() {
            guard isGoalScoringEvent(event) else { continue }
            guard let scorerName = goalScorerName(from: event), !scorerName.isEmpty else { continue }

            let minute = goalEventMinute(from: event)
            let teamID = stringValue((event["team"] as? [String: Any])?["id"])
            let signature = "\(teamID ?? "unknown")|\(minute ?? "n/a")|\(stringValue(event["text"]) ?? scorerName)"
            guard seenEventSignatures.insert(signature).inserted else { continue }
            let scorer = FootballMatchGoalScorer(
                id: "\(teamID ?? "unknown")-\(minute ?? "n/a")-\(index)",
                name: scorerName,
                minute: minute
            )

            if let teamID, teamID == homeTeamID {
                homeScorers.append(scorer)
                continue
            }
            if let teamID, teamID == awayTeamID {
                awayScorers.append(scorer)
                continue
            }

            let text = stringValue(event["text"]) ?? ""
            if text.localizedCaseInsensitiveContains("(\(homeTeamName))") {
                homeScorers.append(scorer)
            } else if text.localizedCaseInsensitiveContains("(\(awayTeamName))") {
                awayScorers.append(scorer)
            }
        }

        guard !homeScorers.isEmpty || !awayScorers.isEmpty else { return nil }
        return FootballMatchGoalScorers(home: homeScorers, away: awayScorers)
    }

    static func matchStatistics(from root: [String: Any]) -> [FootballMatchStatistic] {
        guard let teams = (root["boxscore"] as? [String: Any])?["teams"] as? [[String: Any]], !teams.isEmpty else {
            return []
        }

        guard let home = teams.first(where: { Self.stringValue($0["homeAway"])?.lowercased() == "home" }),
              let away = teams.first(where: { Self.stringValue($0["homeAway"])?.lowercased() == "away" }) else {
            return []
        }

        let homeStats = Self.teamStatisticsMap(from: home)
        let awayStats = Self.teamStatisticsMap(from: away)
        let homeTeamID = teamIdentifier(from: home)
        let awayTeamID = teamIdentifier(from: away)
        let substitutions = substitutionCountsByTeam(from: root["keyEvents"] as? [[String: Any]] ?? [])
        let homeSubstitutions = homeTeamID.flatMap { substitutions[$0] } ?? 0
        let awaySubstitutions = awayTeamID.flatMap { substitutions[$0] } ?? 0

        if homeStats.isEmpty && awayStats.isEmpty && homeSubstitutions == 0 && awaySubstitutions == 0 {
            return []
        }

        return Self.mergeStatistics(
            home: homeStats,
            away: awayStats,
            homeSubstitutions: homeSubstitutions,
            awaySubstitutions: awaySubstitutions
        )
    }

    static func actualKickoffDate(from root: [String: Any], fallbackStartDate: Date) -> Date? {
        let keyEvents = root["keyEvents"] as? [[String: Any]] ?? []
        let kickoffDates = keyEvents.compactMap { event -> Date? in
            let typeText = stringValue((event["type"] as? [String: Any])?["text"])?.lowercased()
            let typeValue = stringValue((event["type"] as? [String: Any])?["type"])?.lowercased()
            guard typeText == "kickoff" || typeValue == "kickoff" else { return nil }
            guard let wallclock = stringValue(event["wallclock"]) else { return nil }
            return parseEventDate(wallclock)
        }

        guard let actualKickoff = kickoffDates.min() else { return nil }

        let earliestAllowed = fallbackStartDate.addingTimeInterval(-15 * 60)
        let latestAllowed = fallbackStartDate.addingTimeInterval(2 * 60 * 60)
        guard actualKickoff >= earliestAllowed, actualKickoff <= latestAllowed else {
            return nil
        }

        return actualKickoff
    }

    static func actualEndDate(
        from root: [String: Any],
        fallbackStartDate: Date,
        actualStartDate: Date?,
        statusPeriod: Int?
    ) -> Date? {
        let keyEvents = root["keyEvents"] as? [[String: Any]] ?? []
        let matchStartDate = actualStartDate ?? fallbackStartDate
        let terminalEndDates = keyEvents.compactMap { event -> (date: Date, kind: MatchTerminalEndKind)? in
            guard let kind = matchTerminalEndKind(from: event),
                  let wallclock = stringValue(event["wallclock"]),
                  let date = parseEventDate(wallclock),
                  isReasonableMatchEndDate(date, startDate: matchStartDate) else {
                return nil
            }
            return (date, kind)
        }

        guard !terminalEndDates.isEmpty else { return nil }

        if let statusPeriod {
            if statusPeriod >= 5 {
                return terminalEndDates.filter({ $0.kind == .penalties }).map(\.date).max()
            }

            if statusPeriod >= 3 {
                return terminalEndDates.filter({ $0.kind == .extraTime }).map(\.date).max()
            }

            return terminalEndDates.filter({ $0.kind == .regularTime }).map(\.date).max()
        }

        return terminalEndDates
            .filter { $0.kind == .penalties || $0.kind == .extraTime || $0.kind == .regularTime }
            .map(\.date)
            .max()
    }

    private enum MatchTerminalEndKind {
        case regularTime
        case extraTime
        case penalties
    }

    private static func matchTerminalEndKind(from event: [String: Any]) -> MatchTerminalEndKind? {
        let type = event["type"] as? [String: Any]
        let typeText = normalizedEventTypeToken(stringValue(type?["text"]) ?? "")
        let typeValue = normalizedEventTypeToken(stringValue(type?["type"]) ?? "")

        if typeValue == "END REGULAR TIME" || typeText == "END REGULAR TIME" {
            return .regularTime
        }

        if typeValue == "END EXTRA TIME"
            || typeText == "END EXTRA TIME"
            || typeValue == "END ET"
            || typeText == "END ET" {
            return .extraTime
        }

        if typeValue.contains("PENAL")
            && (typeValue.contains("END") || typeValue.contains("SHOOTOUT")) {
            return .penalties
        }

        if typeText.contains("PENAL")
            && (typeText.contains("END") || typeText.contains("SHOOTOUT")) {
            return .penalties
        }

        if typeText == "FULL TIME" || typeValue == "FULL TIME" {
            return .regularTime
        }

        return nil
    }

    private static func normalizedEventTypeToken(_ text: String) -> String {
        normalizedStatusToken(text)
            .replacingOccurrences(of: #"[^A-Z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isReasonableMatchEndDate(_ endDate: Date, startDate: Date) -> Bool {
        let elapsed = endDate.timeIntervalSince(startDate)
        return elapsed > 0 && elapsed <= 4 * 60 * 60
    }

    static func isGoalScoringEvent(_ event: [String: Any]) -> Bool {
        if (event["scoringPlay"] as? Bool) == true { return true }
        guard let typeText = stringValue((event["type"] as? [String: Any])?["text"])?.lowercased() else {
            return false
        }
        return typeText.contains("goal")
            || typeText.contains("penalty - scored")
            || typeText.contains("penalty scored")
    }

    static func goalEventMinute(from event: [String: Any]) -> String? {
        let clock = (event["clock"] as? [String: Any])?["displayValue"]
        guard let minute = stringValue(clock)?.trimmingCharacters(in: .whitespacesAndNewlines), !minute.isEmpty else {
            return nil
        }
        return minute
    }

    static func goalScorerName(from event: [String: Any]) -> String? {
        if let text = stringValue(event["text"]),
           let ownGoalScorer = ownGoalScorerName(from: text) {
            return "\(ownGoalScorer) (OG)"
        }

        if let athletes = event["athletesInvolved"] as? [[String: Any]],
           let athlete = athletes.first,
           let displayName = stringValue(athlete["displayName"]),
           !displayName.isEmpty {
            return displayName
        }

        guard let text = stringValue(event["text"]), !text.isEmpty else { return nil }
        let components = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }

        let detail = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty { return nil }

        let ownGoalPrefix = "own goal by "
        if detail.lowercased().hasPrefix(ownGoalPrefix) {
            let remainder = String(detail.dropFirst(ownGoalPrefix.count))
            let untilParen = remainder.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true).first
            let name = untilParen?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name?.isEmpty == false) ? name : nil
        }

        if let range = detail.range(of: " (") {
            let candidate = detail[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate.isEmpty ? nil : candidate
        }

        return nil
    }

    static func ownGoalScorerName(from text: String) -> String? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return nil }

        let lowercasedText = normalizedText.lowercased()
        guard let ownGoalRange = lowercasedText.range(of: "own goal by ") else { return nil }

        let originalStart = normalizedText.index(
            normalizedText.startIndex,
            offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: ownGoalRange.upperBound)
        )
        let remainder = String(normalizedText[originalStart...])

        let firstSentence = remainder
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? remainder

        let candidate = firstSentence
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let candidate, !candidate.isEmpty else { return nil }
        return candidate
    }

    static func liveMatch(
        from event: [String: Any],
        competitionSlug: String,
        competitionName: String,
        competitionStage: String?,
        competitionLogoURL: URL?
    ) -> FootballFixtureMatch? {
        guard let startDate = parsedEventDate(from: event),
              let competition = (event["competitions"] as? [[String: Any]])?.first else {
            return nil
        }

        let status = competition["status"] as? [String: Any]
        let statusType = status?["type"] as? [String: Any]
        let rawState = matchStatusState(from: stringValue(statusType?["state"]))
        let statusText = preferredStatusText(
            shortDetail: stringValue(statusType?["shortDetail"]),
            detail: stringValue(statusType?["detail"]),
            displayClock: stringValue(status?["displayClock"])
        )
        let statusDetailText = supplementalStatusText(
            preferredStatusText: statusText,
            detail: stringValue(statusType?["detail"]),
            displayClock: stringValue(status?["displayClock"])
        )
        let statusPeriod = intValue(statusType?["period"]) ?? intValue(status?["period"])
        let inferred = inferredKickoffStatusIfNeeded(
            from: rawState,
            statusText: statusText,
            startDate: startDate
        )

        guard let competitors = competition["competitors"] as? [[String: Any]],
              let home = competitors.first(where: { stringValue($0["homeAway"])?.lowercased() == "home" }),
              let away = competitors.first(where: { stringValue($0["homeAway"])?.lowercased() == "away" })
        else {
            return nil
        }

        let homeTeam = home["team"] as? [String: Any] ?? [:]
        let awayTeam = away["team"] as? [String: Any] ?? [:]
        let homeSummary = FootballTeamSummary(
            id: stringValue(homeTeam["id"]) ?? stringValue(home["id"]) ?? UUID().uuidString,
            name: teamName(from: homeTeam),
            abbreviation: teamAbbreviation(from: homeTeam, fallbackName: teamName(from: homeTeam)),
            logoURL: teamLogoURL(from: homeTeam),
            countryName: nil,
            isNational: false
        )
        let awaySummary = FootballTeamSummary(
            id: stringValue(awayTeam["id"]) ?? stringValue(away["id"]) ?? UUID().uuidString,
            name: teamName(from: awayTeam),
            abbreviation: teamAbbreviation(from: awayTeam, fallbackName: teamName(from: awayTeam)),
            logoURL: teamLogoURL(from: awayTeam),
            countryName: nil,
            isNational: false
        )

        let eventID = stringValue(event["id"]) ?? stringValue(competition["id"]) ?? UUID().uuidString
        let locationText = venueLocationText(from: competition)
        let seasonSlug = stringValue((event["season"] as? [String: Any])?["slug"])
            ?? stringValue((competition["season"] as? [String: Any])?["slug"])
        let competitionNote = competitionNoteText(from: competition)
        let seriesSummary = seriesSummary(
            from: competition,
            homeCompetitor: home,
            awayCompetitor: away
        )

        return FootballFixtureMatch(
            id: eventID,
            competitionSlug: competitionSlug,
            competitionName: competitionName,
            competitionStage: competitionStage,
            seasonSlug: seasonSlug,
            competitionNote: competitionNote,
            seriesSummary: seriesSummary,
            competitionLogoURL: competitionLogoURL,
            locationText: locationText,
            startDate: startDate,
            statusState: inferred.state,
            statusText: inferred.statusText,
            statusDetailText: statusDetailText,
            statusPeriod: statusPeriod,
            statusReliability: inferred.statusReliability,
            homeTeam: homeSummary,
            awayTeam: awaySummary,
            homeScore: (inferred.inferred && inferred.state == .inProgress) ? "0" : (stringValue(home["score"]) ?? "0"),
            awayScore: (inferred.inferred && inferred.state == .inProgress) ? "0" : (stringValue(away["score"]) ?? "0"),
            homeYellowCards: 0,
            awayYellowCards: 0,
            homeRedCards: 0,
            awayRedCards: 0
        )
    }

    static func cardCounts(from root: [String: Any]) -> (homeYellowCards: Int, awayYellowCards: Int, homeRedCards: Int, awayRedCards: Int) {
        let teams = ((root["boxscore"] as? [String: Any])?["teams"] as? [[String: Any]]) ?? []
        let home = teams.first(where: { stringValue($0["homeAway"])?.lowercased() == "home" })
        let away = teams.first(where: { stringValue($0["homeAway"])?.lowercased() == "away" })

        return (
            homeYellowCards: statisticValue(named: "yellowCards", from: home),
            awayYellowCards: statisticValue(named: "yellowCards", from: away),
            homeRedCards: statisticValue(named: "redCards", from: home),
            awayRedCards: statisticValue(named: "redCards", from: away)
        )
    }

    static func statisticValue(named name: String, from teamBoxscore: [String: Any]?) -> Int {
        let statistics = teamBoxscore?["statistics"] as? [[String: Any]] ?? []
        guard let entry = statistics.first(where: { stringValue($0["name"])?.caseInsensitiveCompare(name) == .orderedSame }) else {
            return 0
        }

        if let numericValue = intValue(entry["value"]) {
            return numericValue
        }

        return intValue(entry["displayValue"]) ?? 0
    }

    static func teamStatisticsMap(from entry: [String: Any]) -> [String: (label: String, value: String)] {
        let raw = entry["statistics"] as? [[String: Any]] ?? []
        var mapped: [String: (label: String, value: String)] = [:]
        for stat in raw {
            guard let name = stringValue(stat["name"])?.lowercased() else { continue }
            guard let value = stringValue(stat["displayValue"]) else { continue }
            let label = stringValue(stat["label"]) ?? name
            mapped[name] = (label: label, value: value)
        }
        return mapped
    }

    static func mergeStatistics(
        home: [String: (label: String, value: String)],
        away: [String: (label: String, value: String)],
        homeSubstitutions: Int,
        awaySubstitutions: Int
    ) -> [FootballMatchStatistic] {
        let preferred: [(name: String, label: String)] = [
            ("possessionpct", "Possession"),
            ("totalshots", "Shots"),
            ("shotsontarget", "Shots On Target"),
            ("woncorners", "Corner Kicks"),
            ("offsides", "Offsides"),
            ("foulscommitted", "Fouls"),
            ("yellowcards", "Yellow Cards"),
            ("redcards", "Red Cards"),
            ("saves", "Saves"),
        ]

        var merged: [FootballMatchStatistic] = []
        for item in preferred {
            let homeValue = formatStatisticValue(name: item.name, rawValue: home[item.name]?.value ?? "--")
            let awayValue = formatStatisticValue(name: item.name, rawValue: away[item.name]?.value ?? "--")
            merged.append(
                FootballMatchStatistic(
                    id: item.name,
                    label: item.label,
                    homeValue: homeValue,
                    awayValue: awayValue
                )
            )
        }

        merged.append(
            FootballMatchStatistic(
                id: "substitutions",
                label: "Substitutions",
                homeValue: "\(homeSubstitutions)",
                awayValue: "\(awaySubstitutions)"
            )
        )
        return merged
    }

    static func teamIdentifier(from entry: [String: Any]) -> String? {
        let team = entry["team"] as? [String: Any] ?? [:]
        return stringValue(team["id"])
    }

    static func substitutionCountsByTeam(from keyEvents: [[String: Any]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in keyEvents {
            let type = ((event["type"] as? [String: Any])?["type"] as? String)?.lowercased() ?? ""
            guard type.contains("substitution") else { continue }
            guard let teamID = stringValue((event["team"] as? [String: Any])?["id"]) else { continue }
            counts[teamID, default: 0] += 1
        }
        return counts
    }

    static func formatStatisticValue(name: String, rawValue: String) -> String {
        if rawValue == "--" {
            return rawValue
        }
        if name == "possessionpct" {
            return rawValue.contains("%") ? rawValue : "\(rawValue)%"
        }
        return rawValue
    }


}
