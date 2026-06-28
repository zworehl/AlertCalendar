import Foundation

struct FootballNotificationMessage: Equatable {
    let title: String
    let body: String
}

extension CalendarMonitor {
    func prepareFootballNotificationAuthorizationIfNeeded(settings: AppSettings) {
        guard settings.enableFootballGoalNotifications
            || settings.enableFootballFinalNotifications
            || settings.enableFootballAutoAddNotifications else { return }

        Task {
            await AlertCalendarUserNotifier.requestAuthorizationIfNeeded()
        }
    }

    nonisolated static func footballGoalNotificationMessage(
        for match: FootballFixtureMatch,
        scoringSide: FootballScoreSide,
        scorer: FootballMatchGoalScorer?,
        includeScorerName: Bool
    ) -> FootballNotificationMessage {
        let scoreLine = footballNotificationScoreLine(for: match)
        let scoringTeam = footballNotificationTeamName(for: match, side: scoringSide)

        let bodyLead: String
        if includeScorerName, let scorer {
            if let minute = scorer.minute {
                bodyLead = "\(scorer.name) scored at \(minute)."
            } else {
                bodyLead = "\(scorer.name) scored."
            }
        } else {
            bodyLead = "\(scoringTeam) scored."
        }

        return FootballNotificationMessage(
            title: "\(scoringTeam) goal",
            body: "\(bodyLead) \(scoreLine)."
        )
    }

    nonisolated static func footballFinalNotificationMessage(
        for match: FootballFixtureMatch
    ) -> FootballNotificationMessage {
        FootballNotificationMessage(
            title: "Match finished",
            body: "\(footballNotificationScoreLine(for: match))."
        )
    }

    nonisolated static func footballAutoAddNotificationMessage(
        for match: FootballFixtureMatch,
        now: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> FootballNotificationMessage {
        let matchup = "\(match.homeTeam.name) vs \(match.awayTeam.name)"
        let competition = FootballFixtureFormatter.competitionDetailText(for: match)
        let schedule = footballScheduleText(for: match, now: now)

        return FootballNotificationMessage(
            title: "Match added to Calendar",
            body: "\(competition): \(matchup), \(schedule)."
        )
    }

    nonisolated static func footballNotificationScoreLine(
        for match: FootballFixtureMatch
    ) -> String {
        "\(match.homeTeam.name) \(match.homeScore)-\(match.awayScore) \(match.awayTeam.name)"
    }

    nonisolated static func footballNotificationTeamName(
        for match: FootballFixtureMatch,
        side: FootballScoreSide
    ) -> String {
        switch side {
        case .home:
            return match.homeTeam.name
        case .away:
            return match.awayTeam.name
        }
    }

    nonisolated static func footballGoalNotificationKey(
        for match: FootballFixtureMatch,
        scoringSide: FootballScoreSide
    ) -> String {
        let goalNumber = footballGoalCount(for: match, side: scoringSide)
        return "football.goal.\(match.id).\(scoringSide.rawValue).\(goalNumber).\(match.homeScore)-\(match.awayScore)"
    }

    nonisolated static func footballFinalNotificationKey(
        for match: FootballFixtureMatch
    ) -> String {
        "football.final.\(match.id)"
    }

    nonisolated static func footballAutoAddNotificationKey(
        for match: FootballFixtureMatch
    ) -> String {
        "football.autoAdd.\(match.id)"
    }

    nonisolated static func footballFinishedTransition(
        from previousMatch: FootballFixtureMatch,
        to currentMatch: FootballFixtureMatch
    ) -> Bool {
        currentMatch.statusReliability == .reported
            && previousMatch.statusState != .finished
            && currentMatch.statusState == .finished
    }

    nonisolated static func footballGoalCount(
        for match: FootballFixtureMatch,
        side: FootballScoreSide
    ) -> Int {
        switch side {
        case .home:
            return match.homeGoals
        case .away:
            return match.awayGoals
        }
    }

    nonisolated static func footballGoalScorer(
        from scorers: FootballMatchGoalScorers?,
        side: FootballScoreSide,
        goalNumber: Int
    ) -> FootballMatchGoalScorer? {
        let scorerList: [FootballMatchGoalScorer]
        switch side {
        case .home:
            scorerList = scorers?.home ?? []
        case .away:
            scorerList = scorers?.away ?? []
        }

        let sortedScorers = scorerList.sorted { lhs, rhs in
            footballGoalScorerEventIndex(lhs) < footballGoalScorerEventIndex(rhs)
        }
        guard goalNumber > 0 else { return sortedScorers.last }
        guard sortedScorers.indices.contains(goalNumber - 1) else { return sortedScorers.last }
        return sortedScorers[goalNumber - 1]
    }

    nonisolated static func footballGoalScorerEventIndex(
        _ scorer: FootballMatchGoalScorer
    ) -> Int {
        guard let token = scorer.id.split(separator: "-").last,
              let index = Int(token) else {
            return .max
        }
        return index
    }

    func queueFootballGoalNotification(
        for match: FootballFixtureMatch,
        highlight: FootballGoalHighlight,
        settings: AppSettings
    ) {
        guard settings.enableFootballGoalNotifications else { return }
        guard isManagedFootballMatch(match) else { return }

        let notificationKey = Self.footballGoalNotificationKey(
            for: match,
            scoringSide: highlight.scoringSide
        )
        guard deliveredFootballNotificationKeys.insert(notificationKey).inserted else { return }

        let footballClient = footballClient
        let includeScorerName = settings.includeFootballGoalScorerInNotifications
        Task {
            let scorers = includeScorerName ? (try? await footballClient.fetchGoalScorers(for: match)) : nil
            let scorer = Self.footballGoalScorer(
                from: scorers,
                side: highlight.scoringSide,
                goalNumber: Self.footballGoalCount(for: match, side: highlight.scoringSide)
            )
            let message = Self.footballGoalNotificationMessage(
                for: match,
                scoringSide: highlight.scoringSide,
                scorer: scorer,
                includeScorerName: includeScorerName
            )
            await AlertCalendarUserNotifier.deliver(
                identifier: notificationKey,
                title: message.title,
                body: message.body
            )
        }
    }

    func queueFootballFinalNotificationIfNeeded(
        from previousMatch: FootballFixtureMatch,
        to currentMatch: FootballFixtureMatch,
        settings: AppSettings
    ) {
        guard settings.enableFootballFinalNotifications else { return }
        guard Self.footballFinishedTransition(from: previousMatch, to: currentMatch) else { return }
        guard isManagedFootballMatch(currentMatch) else { return }

        let notificationKey = Self.footballFinalNotificationKey(for: currentMatch)
        guard deliveredFootballNotificationKeys.insert(notificationKey).inserted else { return }

        let message = Self.footballFinalNotificationMessage(for: currentMatch)
        Task {
            await AlertCalendarUserNotifier.deliver(
                identifier: notificationKey,
                title: message.title,
                body: message.body
            )
        }
    }

    func queueFootballAutoAddNotification(for match: FootballFixtureMatch, now: Date) {
        guard snapshotSettings().enableFootballAutoAddNotifications else { return }

        let notificationKey = Self.footballAutoAddNotificationKey(for: match)
        guard deliveredFootballNotificationKeys.insert(notificationKey).inserted else { return }

        let message = Self.footballAutoAddNotificationMessage(for: match, now: now)
        Task {
            await AlertCalendarUserNotifier.deliver(
                identifier: notificationKey,
                title: message.title,
                body: message.body
            )
        }
    }

    func isManagedFootballMatch(_ match: FootballFixtureMatch) -> Bool {
        managedFootballEventRecords.contains { $0.matchID == match.id }
    }
}
