import Foundation

extension CalendarMonitor {
    nonisolated static let footballLiveOddsMaximumAge: TimeInterval = 75

    nonisolated static func footballOutcomeProbabilities(
        for match: FootballFixtureMatch,
        now: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> FootballMatchOutcomeProbabilities? {
        guard !FootballFixtureFormatter.hasUnknownParticipants(in: match) else {
            return nil
        }

        guard !match.hasInterruptedStatus else {
            return nil
        }

        if match.statusState == .finished {
            return footballFinishedOutcomeProbabilities(for: match)
        }

        if footballEffectiveStartDate(for: match) <= now,
           match.statusReliability != .reported {
            return nil
        }

        let scope = footballOutcomeProbabilityScope(for: match, now: now)
        let suppliedProbabilities = footballUsableOutcomeProbabilities(
            match.outcomeProbabilities,
            for: match,
            now: now
        )
        let pregamePrior = match.pregameOutcomeProbabilities?.source == .marketOdds
            ? match.pregameOutcomeProbabilities
            : nil
        let displayBase = (suppliedProbabilities
            ?? pregamePrior
            ?? footballPregameHeuristicOutcomeProbabilities(for: match))
            .replacing(scope: scope)

        let isLiveState = match.statusState == .inProgress
            || (match.statusState == .unknown && footballEffectiveStartDate(for: match) <= now)
        guard isLiveState else {
            return displayBase.source == .liveMarketOdds
                ? footballPregameHeuristicOutcomeProbabilities(for: match).replacing(scope: scope)
                : displayBase
        }

        guard footballParsedGoalValue(match.homeScore) != nil,
              footballParsedGoalValue(match.awayScore) != nil else {
            return nil
        }
        let modelBase = suppliedProbabilities?.source == .liveMarketOdds
            ? (pregamePrior ?? footballPregameHeuristicOutcomeProbabilities(for: match)).replacing(scope: scope)
            : displayBase

        if footballStatusConfirmsPenaltyShootout(match) {
            return footballPenaltyShootoutOutcomeProbabilities(
                base: modelBase,
                match: match
            )
        }

        if footballStatusConfirmsExtraTime(match) {
            return footballExtraTimeOutcomeProbabilities(
                base: modelBase,
                match: match,
                now: now
            )
        }

        let projected = footballRegulationOutcomeProbabilities(
            base: modelBase,
            match: match,
            now: now
        )
        guard let liveProbabilities = suppliedProbabilities,
              liveProbabilities.source == .liveMarketOdds else {
            return projected
        }
        return footballReconciledLiveRegulationProbabilities(
            live: liveProbabilities.replacing(scope: scope),
            projected: projected,
            match: match,
            now: now
        )
    }

    nonisolated static func footballUsableOutcomeProbabilities(
        _ probabilities: FootballMatchOutcomeProbabilities?,
        for match: FootballFixtureMatch,
        now: Date
    ) -> FootballMatchOutcomeProbabilities? {
        guard let probabilities else { return nil }
        guard probabilities.source == .liveMarketOdds else { return probabilities }

        guard let observedAt = probabilities.observedAt else { return nil }
        let age = now.timeIntervalSince(observedAt)
        guard age >= -5, age <= footballLiveOddsMaximumAge else { return nil }

        guard let observedHomeScore = probabilities.observedHomeScore,
              let observedAwayScore = probabilities.observedAwayScore,
              observedHomeScore == footballParsedGoalValue(match.homeScore),
              observedAwayScore == footballParsedGoalValue(match.awayScore) else {
            return nil
        }

        if let observedStatusPeriod = probabilities.observedStatusPeriod,
           let currentStatusPeriod = match.statusPeriod,
           observedStatusPeriod != currentStatusPeriod {
            return nil
        }

        return probabilities
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

    nonisolated static func footballReconciledLiveRegulationProbabilities(
        live: FootballMatchOutcomeProbabilities,
        projected: FootballMatchOutcomeProbabilities,
        match: FootballFixtureMatch,
        now: Date
    ) -> FootballMatchOutcomeProbabilities {
        let minute = footballProbabilityClock(for: match, now: now, fallbackBaseMinute: 0).baseMinute
        let maximumTotalVariation: Double
        switch minute {
        case 90...:
            maximumTotalVariation = 0.20
        case 75...:
            maximumTotalVariation = 0.30
        case 45...:
            maximumTotalVariation = 0.38
        default:
            maximumTotalVariation = 0.48
        }
        let totalVariation = 0.5 * (
            abs(live.homeWin - projected.homeWin)
                + abs(live.draw - projected.draw)
                + abs(live.awayWin - projected.awayWin)
        )
        return totalVariation <= maximumTotalVariation ? live : projected
    }

    nonisolated static func footballFinishedOutcomeProbabilities(
        for match: FootballFixtureMatch
    ) -> FootballMatchOutcomeProbabilities? {
        let scope: FootballMatchOutcomeProbabilityScope = footballStatusConfirmsPenaltyShootout(match)
            || footballStatusConfirmsExtraTime(match)
            ? .decisiveResult
            : .regulationTime

        if let officialWinner = match.officialWinner {
            return footballCertainFinalOutcome(winner: officialWinner, scope: scope)
        }

        if footballStatusConfirmsPenaltyShootout(match),
           let homeShootoutScore = match.homeShootoutScore,
           let awayShootoutScore = match.awayShootoutScore,
           homeShootoutScore != awayShootoutScore {
            return footballCertainFinalOutcome(
                winner: homeShootoutScore > awayShootoutScore ? .home : .away,
                scope: .decisiveResult
            )
        }

        guard let homeScore = footballParsedGoalValue(match.homeScore),
              let awayScore = footballParsedGoalValue(match.awayScore) else {
            return nil
        }

        if homeScore > awayScore {
            return footballCertainFinalOutcome(winner: .home, scope: scope)
        }

        if awayScore > homeScore {
            return footballCertainFinalOutcome(winner: .away, scope: scope)
        }

        // A level visible score does not identify a decisive winner. Until the
        // provider reports one, failing closed is safer than claiming a draw.
        if scope == .decisiveResult {
            return nil
        }

        return FootballMatchOutcomeProbabilities(
            homeWin: 0,
            draw: 1,
            awayWin: 0,
            source: .finalResult,
            scope: .regulationTime
        )
    }

    nonisolated static func footballCertainFinalOutcome(
        winner: FootballScoreSide,
        scope: FootballMatchOutcomeProbabilityScope
    ) -> FootballMatchOutcomeProbabilities? {
        FootballMatchOutcomeProbabilities(
            homeWin: winner == .home ? 1 : 0,
            draw: 0,
            awayWin: winner == .away ? 1 : 0,
            source: .finalResult,
            scope: scope
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
            homeAdvantage = 0
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
        let clock = footballProbabilityClock(for: match, now: now, fallbackBaseMinute: 0)
        let minute = min(max(clock.baseMinute, 0), 90)
        let scoreDifference = footballGoalValue(match.homeScore) - footballGoalValue(match.awayScore)
        let totalExpectedGoals = footballExpectedRegulationGoalsRemaining(
            match: match,
            baseMinute: minute,
            stoppageMinute: clock.stoppageMinute,
            scoreDifference: scoreDifference
        )
        let homeShare = footballExpectedHomeGoalShare(
            base: base,
            scoreDifference: scoreDifference,
            minute: minute,
            phaseUpperBoundMinute: 90
        )

        let expectedGoals = footballExpectedGoalsAdjustedForRedCards(
            home: totalExpectedGoals * homeShare,
            away: totalExpectedGoals * (1 - homeShare),
            match: match
        )

        return footballProjectedOutcomeProbabilities(
            base: base,
            match: match,
            scoreDifference: scoreDifference,
            homeExpectedGoals: expectedGoals.home,
            awayExpectedGoals: expectedGoals.away,
            tiedOutcome: .draw
        )
    }

    nonisolated static func footballExtraTimeOutcomeProbabilities(
        base: FootballMatchOutcomeProbabilities,
        match: FootballFixtureMatch,
        now: Date
    ) -> FootballMatchOutcomeProbabilities {
        let clock = footballProbabilityClock(for: match, now: now, fallbackBaseMinute: 91)
        let minute = min(max(clock.baseMinute, 91), 120)
        let relevantScores = footballRelevantScores(for: match)
        let scoreDifference = relevantScores.home - relevantScores.away
        let remainingMinutes = footballExpectedExtraTimeMinutesRemaining(
            match: match,
            baseMinute: minute,
            stoppageMinute: clock.stoppageMinute
        )
        let totalExpectedGoals = max(0.001, 0.75 * remainingMinutes / 30)
        let homeShare = footballExpectedHomeGoalShare(
            base: base,
            scoreDifference: scoreDifference,
            minute: minute,
            phaseUpperBoundMinute: 120
        )

        let expectedGoals = footballExpectedGoalsAdjustedForRedCards(
            home: totalExpectedGoals * homeShare,
            away: totalExpectedGoals * (1 - homeShare),
            match: match
        )

        return footballProjectedOutcomeProbabilities(
            base: base.replacing(scope: .decisiveResult),
            match: match,
            scoreDifference: scoreDifference,
            homeExpectedGoals: expectedGoals.home,
            awayExpectedGoals: expectedGoals.away,
            tiedOutcome: .penalties
        )
    }

    nonisolated static func footballPenaltyShootoutOutcomeProbabilities(
        base _: FootballMatchOutcomeProbabilities,
        match _: FootballFixtureMatch
    ) -> FootballMatchOutcomeProbabilities? {
        // A shootout score alone does not reveal attempts taken or whose kick is
        // next. Hide the estimate until the provider supplies that state.
        nil
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
