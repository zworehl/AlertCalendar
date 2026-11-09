import Foundation

extension FootballFixtureFormatter {
    static func calendarNotes(
        for match: FootballFixtureMatch,
        goalScorers: FootballMatchGoalScorers?
    ) -> String? {
        guard match.totalGoals > 0, let goalScorers else { return nil }

        let homeRows = sortedGoalScorers(goalScorers.home).map {
            goalScorerNotesLine(for: $0, scoringSide: .home, match: match)
        }
        let awayRows = sortedGoalScorers(goalScorers.away).map {
            goalScorerNotesLine(for: $0, scoringSide: .away, match: match)
        }
        guard !homeRows.isEmpty || !awayRows.isEmpty else { return nil }

        return [
            "Goals",
            "",
            goalScorerNotesTeamHeading(for: match.homeTeam),
            homeRows.isEmpty ? "No goals" : homeRows.joined(separator: "\n"),
            "",
            goalScorerNotesTeamHeading(for: match.awayTeam),
            awayRows.isEmpty ? "No goals" : awayRows.joined(separator: "\n"),
        ]
        .joined(separator: "\n")
    }

    static func goalScorerNotesTeamHeading(for team: FootballTeamSummary) -> String {
        "\(teamFlag(for: team)) \(team.name)"
    }

    static func goalScorerNotesLine(
        for scorer: FootballMatchGoalScorer,
        scoringSide: FootballScoreSide,
        match: FootballFixtureMatch
    ) -> String {
        let minute = scorer.minute ?? "--"
        let flag = goalScorerFlag(for: scorer, scoringSide: scoringSide, match: match)
        let name = goalScorerNotesName(scorer.name)
        let modifiers = goalScorerNotesModifiers(for: scorer)
        let modifierText = modifiers.isEmpty ? "" : " (\(modifiers.joined(separator: ", ")))"

        return "\(flag) \(minute) \(name)\(modifierText)"
    }

    static func goalScorerNotesModifiers(for scorer: FootballMatchGoalScorer) -> [String] {
        var modifiers: [String] = []
        if scorer.isOwnGoal {
            modifiers.append("own goal")
        }
        if scorer.isPenalty {
            modifiers.append("penalty")
        }
        return modifiers
    }

    static func goalScorerFlag(
        for scorer: FootballMatchGoalScorer,
        scoringSide: FootballScoreSide,
        match: FootballFixtureMatch
    ) -> String {
        let explicitFlag = flagEmoji(for: scorer.countryName)
        if explicitFlag != "🏳️" {
            return explicitFlag
        }

        guard shouldFallbackToTeamCountry(for: match) else {
            return explicitFlag
        }

        let fallbackTeam: FootballTeamSummary
        switch (scoringSide, scorer.isOwnGoal) {
        case (.home, false), (.away, true):
            fallbackTeam = match.homeTeam
        case (.away, false), (.home, true):
            fallbackTeam = match.awayTeam
        }

        let fallbackFlag = teamFlag(for: fallbackTeam)
        return fallbackFlag == "🏴" ? explicitFlag : fallbackFlag
    }

    static func shouldFallbackToTeamCountry(for match: FootballFixtureMatch) -> Bool {
        match.competitionCategory == .nationalTeams
            || match.homeTeam.isNational
            || match.awayTeam.isNational
    }

    static func goalScorerNotesName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" (OG)", " (O.G.)", " (Own Goal)", " (own goal)", " (autogol)"] {
            if trimmed.hasSuffix(suffix) {
                return String(trimmed.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return trimmed
    }

    static func sortedGoalScorers(_ scorers: [FootballMatchGoalScorer]) -> [FootballMatchGoalScorer] {
        scorers.sorted { lhs, rhs in
            goalScorerEventIndex(lhs.id) < goalScorerEventIndex(rhs.id)
        }
    }

    static func goalScorerEventIndex(_ scorerID: String) -> Int {
        guard let token = scorerID.split(separator: "-").last,
              let index = Int(token) else {
            return .max
        }
        return index
    }
}
