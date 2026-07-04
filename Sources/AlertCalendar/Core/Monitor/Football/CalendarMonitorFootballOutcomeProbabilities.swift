import Foundation

extension CalendarMonitor {
    nonisolated static func footballOutcomeProbabilities(
        for match: FootballFixtureMatch,
        now: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> FootballMatchOutcomeProbabilities? {
        guard !FootballFixtureFormatter.hasUnknownParticipants(in: match) else {
            return nil
        }

        if match.statusState == .finished {
            return footballFinishedOutcomeProbabilities(for: match)
        }

        let scope = footballOutcomeProbabilityScope(for: match, now: now)
        let base = (match.outcomeProbabilities ?? footballPregameHeuristicOutcomeProbabilities(for: match))
            .replacing(scope: scope)

        guard match.statusState == .inProgress
            || (match.statusState == .unknown && footballEffectiveStartDate(for: match) <= now) else {
            return base
        }

        if base.source == .liveMarketOdds,
           scope != .decisiveResult {
            return base
        }

        if footballStatusConfirmsPenaltyShootout(match) {
            return footballPenaltyShootoutOutcomeProbabilities(
                base: base,
                match: match
            )
        }

        if footballStatusConfirmsExtraTime(match) {
            return footballExtraTimeOutcomeProbabilities(
                base: base,
                match: match,
                now: now
            )
        }

        return footballRegulationOutcomeProbabilities(
            base: base,
            match: match,
            now: now
        )
    }

    nonisolated static func footballOutcomeProbabilityScope(
        for match: FootballFixtureMatch,
        now _: Date
    ) -> FootballMatchOutcomeProbabilityScope {
        if footballStatusConfirmsPenaltyShootout(match) || footballStatusConfirmsExtraTime(match) {
            return .decisiveResult
        }

        if footballCanReachExtraTime(match) {
            return .extraTimePossible
        }

        return .regulationTime
    }

    nonisolated static func footballFinishedOutcomeProbabilities(
        for match: FootballFixtureMatch
    ) -> FootballMatchOutcomeProbabilities? {
        let homeScore = footballGoalValue(match.homeScore)
        let awayScore = footballGoalValue(match.awayScore)
        let scope: FootballMatchOutcomeProbabilityScope = footballStatusConfirmsPenaltyShootout(match)
            || footballStatusConfirmsExtraTime(match)
            ? .decisiveResult
            : .regulationTime

        if homeScore > awayScore {
            return FootballMatchOutcomeProbabilities(
                homeWin: 1,
                draw: 0,
                awayWin: 0,
                source: .finalResult,
                scope: scope
            )
        }

        if awayScore > homeScore {
            return FootballMatchOutcomeProbabilities(
                homeWin: 0,
                draw: 0,
                awayWin: 1,
                source: .finalResult,
                scope: scope
            )
        }

        return FootballMatchOutcomeProbabilities(
            homeWin: 0,
            draw: 1,
            awayWin: 0,
            source: .finalResult,
            scope: .regulationTime
        )
    }

    nonisolated static func footballPregameHeuristicOutcomeProbabilities(
        for match: FootballFixtureMatch
    ) -> FootballMatchOutcomeProbabilities {
        let canReachExtraTime = footballCanReachExtraTime(match)
        let neutralContext = footballLikelyNeutralContext(match)
        let nationalFixture = match.homeTeam.isNational || match.awayTeam.isNational

        var draw = canReachExtraTime ? 0.31 : 0.28
        if neutralContext {
            draw += 0.01
        }
        if nationalFixture {
            draw += 0.01
        }

        let homeAdvantage: Double
        if neutralContext {
            homeAdvantage = nationalFixture ? 0.015 : 0.025
        } else if nationalFixture {
            homeAdvantage = 0.055
        } else {
            homeAdvantage = 0.075
        }

        let nonDraw = max(0.10, 1 - draw)
        let homeWin = nonDraw * (0.5 + homeAdvantage)
        let awayWin = nonDraw - homeWin

        return FootballMatchOutcomeProbabilities(
            homeWin: homeWin,
            draw: draw,
            awayWin: awayWin,
            source: .heuristic,
            scope: canReachExtraTime ? .extraTimePossible : .regulationTime
        ) ?? FootballMatchOutcomeProbabilities(
            homeWin: 0.43,
            draw: 0.28,
            awayWin: 0.29,
            source: .heuristic,
            scope: .regulationTime
        )!
    }

    nonisolated static func footballLikelyNeutralContext(_ match: FootballFixtureMatch) -> Bool {
        if footballIsFinalContext(match) || match.competitionSlug == "uefa.super_cup" {
            return true
        }

        switch match.competitionSlug {
        case "fifa.world", "uefa.euro", "conmebol.america", "concacaf.gold", "caf.nations", "afc.asian.cup":
            return footballIsSingleMatchKnockoutContext(match)
        default:
            return false
        }
    }

    nonisolated static func footballRegulationOutcomeProbabilities(
        base: FootballMatchOutcomeProbabilities,
        match: FootballFixtureMatch,
        now: Date
    ) -> FootballMatchOutcomeProbabilities {
        let minute = min(max(footballLiveMinute(for: match, now: now) ?? 0, 0), 90)
        let scoreDifference = footballGoalValue(match.homeScore) - footballGoalValue(match.awayScore)
        let totalExpectedGoals = footballExpectedRegulationGoalsRemaining(
            match: match,
            minute: minute,
            scoreDifference: scoreDifference
        )
        let homeShare = footballExpectedHomeGoalShare(
            base: base,
            scoreDifference: scoreDifference,
            minute: minute,
            phaseUpperBoundMinute: 90
        )

        return footballProjectedOutcomeProbabilities(
            base: base,
            match: match,
            scoreDifference: scoreDifference,
            homeExpectedGoals: totalExpectedGoals * homeShare,
            awayExpectedGoals: totalExpectedGoals * (1 - homeShare),
            tiedOutcome: .draw
        )
    }

    nonisolated static func footballExtraTimeOutcomeProbabilities(
        base: FootballMatchOutcomeProbabilities,
        match: FootballFixtureMatch,
        now: Date
    ) -> FootballMatchOutcomeProbabilities {
        let minute = min(max(footballLiveMinute(for: match, now: now) ?? 91, 91), 120)
        let scoreDifference = footballGoalValue(match.homeScore) - footballGoalValue(match.awayScore)
        let remainingMinutes = max(0, 120 - minute)
        let totalExpectedGoals = max(0.04, 0.75 * Double(remainingMinutes) / 30)
        let homeShare = footballExpectedHomeGoalShare(
            base: base,
            scoreDifference: scoreDifference,
            minute: minute,
            phaseUpperBoundMinute: 120
        )

        return footballProjectedOutcomeProbabilities(
            base: base.replacing(scope: .decisiveResult),
            match: match,
            scoreDifference: scoreDifference,
            homeExpectedGoals: totalExpectedGoals * homeShare,
            awayExpectedGoals: totalExpectedGoals * (1 - homeShare),
            tiedOutcome: .penalties
        )
    }

    nonisolated static func footballPenaltyShootoutOutcomeProbabilities(
        base: FootballMatchOutcomeProbabilities,
        match _: FootballFixtureMatch
    ) -> FootballMatchOutcomeProbabilities {
        let homePenaltyWin = footballPenaltyHomeWinProbability(base: base)
        return FootballMatchOutcomeProbabilities(
            homeWin: homePenaltyWin,
            draw: 0,
            awayWin: 1 - homePenaltyWin,
            source: .heuristic,
            scope: .decisiveResult,
            providerName: base.providerName
        ) ?? base.replacing(source: .heuristic, scope: .decisiveResult)
    }

    private enum FootballTiedProjectionOutcome {
        case draw
        case penalties
    }

    nonisolated private static func footballProjectedOutcomeProbabilities(
        base: FootballMatchOutcomeProbabilities,
        match _: FootballFixtureMatch,
        scoreDifference: Int,
        homeExpectedGoals: Double,
        awayExpectedGoals: Double,
        tiedOutcome: FootballTiedProjectionOutcome
    ) -> FootballMatchOutcomeProbabilities {
        let homeGoalProbabilities = footballPoissonGoalProbabilities(mean: homeExpectedGoals)
        let awayGoalProbabilities = footballPoissonGoalProbabilities(mean: awayExpectedGoals)
        let penaltyHomeWin = footballPenaltyHomeWinProbability(base: base)

        var homeWin = 0.0
        var draw = 0.0
        var awayWin = 0.0

        for (homeGoals, homeProbability) in homeGoalProbabilities.enumerated() {
            for (awayGoals, awayProbability) in awayGoalProbabilities.enumerated() {
                let probability = homeProbability * awayProbability
                let projectedDifference = scoreDifference + homeGoals - awayGoals

                if projectedDifference > 0 {
                    homeWin += probability
                } else if projectedDifference < 0 {
                    awayWin += probability
                } else {
                    switch tiedOutcome {
                    case .draw:
                        draw += probability
                    case .penalties:
                        homeWin += probability * penaltyHomeWin
                        awayWin += probability * (1 - penaltyHomeWin)
                    }
                }
            }
        }

        return FootballMatchOutcomeProbabilities(
            homeWin: homeWin,
            draw: draw,
            awayWin: awayWin,
            source: .heuristic,
            scope: base.scope,
            providerName: base.providerName
        ) ?? base
    }

    nonisolated static func footballExpectedRegulationGoalsRemaining(
        match: FootballFixtureMatch,
        minute: Int,
        scoreDifference: Int
    ) -> Double {
        let boundedMinute = min(max(minute, 0), 90)
        let remainingMinutes = max(0, 90 - boundedMinute)
        let baseGoalsPerMatch: Double = match.competitionCategory == .nationalTeams ? 2.45 : 2.65
        let stoppageReserve: Double
        if boundedMinute >= 88 {
            stoppageReserve = 0.10
        } else if boundedMinute >= 80 {
            stoppageReserve = 0.16
        } else {
            stoppageReserve = 0.22
        }

        let urgencyMultiplier: Double
        if scoreDifference == 0 {
            urgencyMultiplier = footballCanReachExtraTime(match) && boundedMinute >= 75 ? 0.88 : 1.0
        } else {
            urgencyMultiplier = 1.08
        }

        return max(0.02, ((baseGoalsPerMatch * Double(remainingMinutes) / 90) + stoppageReserve) * urgencyMultiplier)
    }

    nonisolated static func footballExpectedHomeGoalShare(
        base: FootballMatchOutcomeProbabilities,
        scoreDifference: Int,
        minute: Int,
        phaseUpperBoundMinute: Int
    ) -> Double {
        let baseNonDraw = max(0.01, base.homeWin + base.awayWin)
        var homeShare = base.homeWin / baseNonDraw
        let progress = min(max(Double(minute) / Double(max(1, phaseUpperBoundMinute)), 0), 1)
        let chaseAdjustment = min(0.20, 0.08 + (0.16 * progress))

        if scoreDifference > 0 {
            homeShare -= chaseAdjustment
        } else if scoreDifference < 0 {
            homeShare += chaseAdjustment
        }

        return min(max(homeShare, 0.18), 0.82)
    }

    nonisolated static func footballPenaltyHomeWinProbability(
        base: FootballMatchOutcomeProbabilities
    ) -> Double {
        let nonDraw = max(0.01, base.homeWin + base.awayWin)
        let homeStrengthShare = base.homeWin / nonDraw
        return min(max(0.50 + ((homeStrengthShare - 0.50) * 0.45), 0.36), 0.64)
    }

    nonisolated static func footballPoissonGoalProbabilities(
        mean: Double,
        maxGoals: Int = 7
    ) -> [Double] {
        let boundedMean = min(max(mean, 0), 8)
        guard maxGoals > 0 else { return [1] }

        var probabilities = Array(repeating: 0.0, count: maxGoals + 1)
        probabilities[0] = exp(-boundedMean)
        if maxGoals > 1 {
            for goals in 1..<maxGoals {
                probabilities[goals] = probabilities[goals - 1] * boundedMean / Double(goals)
            }
        }

        let assignedProbability = probabilities.dropLast().reduce(0, +)
        probabilities[maxGoals] = max(0, 1 - assignedProbability)
        return probabilities
    }
}
