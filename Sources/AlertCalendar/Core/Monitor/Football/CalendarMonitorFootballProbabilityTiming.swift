import Foundation

extension CalendarMonitor {
    nonisolated static func footballExpectedRegulationGoalsRemaining(
        match: FootballFixtureMatch,
        baseMinute: Int,
        stoppageMinute: Int,
        scoreDifference: Int
    ) -> Double {
        let boundedMinute = min(max(baseMinute, 0), 90)
        let remainingMinutes = footballExpectedRegulationMinutesRemaining(
            match: match,
            baseMinute: boundedMinute,
            stoppageMinute: stoppageMinute
        )
        let baseGoalsPerMatch: Double = match.competitionCategory == .nationalTeams ? 2.45 : 2.65

        let urgencyMultiplier: Double
        if scoreDifference == 0 {
            urgencyMultiplier = footballCanReachExtraTime(match) && boundedMinute >= 75 ? 0.88 : 1.0
        } else {
            urgencyMultiplier = 1.08
        }

        return max(0.001, (baseGoalsPerMatch * remainingMinutes / 90) * urgencyMultiplier)
    }

    nonisolated static func footballExpectedRegulationMinutesRemaining(
        match: FootballFixtureMatch,
        baseMinute: Int,
        stoppageMinute: Int
    ) -> Double {
        let minute = min(max(baseMinute, 0), 90)
        let stoppage = max(0, stoppageMinute)
        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        let expectedFirstHalfStoppage = 2.5
        let expectedSecondHalfStoppage = 4.8

        if minute < 45 {
            return Double(90 - minute) + expectedFirstHalfStoppage + expectedSecondHalfStoppage
        }

        if minute == 45 {
            if normalizedStatus == "HT" || normalizedStatus.contains("HALF") {
                return 45 + expectedSecondHalfStoppage
            }

            if match.statusPeriod == 1 || stoppage > 0 {
                return 45
                    + footballExpectedStoppageMinutesRemaining(
                        elapsed: stoppage,
                        initialExpectation: expectedFirstHalfStoppage,
                        decay: 0.30
                    )
                    + expectedSecondHalfStoppage
            }

            return 45 + expectedSecondHalfStoppage
        }

        if minute < 90 {
            return Double(90 - minute) + expectedSecondHalfStoppage
        }

        return footballExpectedStoppageMinutesRemaining(
            elapsed: stoppage,
            initialExpectation: expectedSecondHalfStoppage,
            decay: 0.28
        )
    }

    nonisolated static func footballExpectedExtraTimeMinutesRemaining(
        match: FootballFixtureMatch,
        baseMinute: Int,
        stoppageMinute: Int
    ) -> Double {
        let minute = min(max(baseMinute, 91), 120)
        let stoppage = max(0, stoppageMinute)
        let expectedPeriodStoppage = 1.2
        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        let isExtraTimeInterval = normalizedStatus == "HT" || normalizedStatus.contains("HALF")

        if match.statusPeriod == 3 {
            if minute < 105 {
                return Double(105 - minute) + expectedPeriodStoppage + 15 + expectedPeriodStoppage
            }
            let firstPeriodRemainder = isExtraTimeInterval ? 0 : footballExpectedStoppageMinutesRemaining(
                elapsed: stoppage,
                initialExpectation: expectedPeriodStoppage,
                decay: 0.36
            )
            return 15 + firstPeriodRemainder + expectedPeriodStoppage
        }

        if match.statusPeriod == 4 {
            if minute < 120 {
                return Double(120 - minute) + expectedPeriodStoppage
            }
            return footballExpectedStoppageMinutesRemaining(
                elapsed: stoppage,
                initialExpectation: expectedPeriodStoppage,
                decay: 0.36
            )
        }

        if minute < 105 {
            return Double(120 - minute) + (expectedPeriodStoppage * 2)
        }
        if minute < 120 {
            return Double(120 - minute) + expectedPeriodStoppage
        }
        return footballExpectedStoppageMinutesRemaining(
            elapsed: stoppage,
            initialExpectation: expectedPeriodStoppage,
            decay: 0.36
        )
    }

    nonisolated static func footballExpectedStoppageMinutesRemaining(
        elapsed: Int,
        initialExpectation: Double,
        decay: Double
    ) -> Double {
        max(0.05, initialExpectation * exp(-decay * Double(max(0, elapsed))))
    }

    nonisolated static func footballExpectedGoalsAdjustedForRedCards(
        home: Double,
        away: Double,
        match: FootballFixtureMatch
    ) -> (home: Double, away: Double) {
        let homeMultiplier = pow(0.72, Double(max(0, match.homeRedCards)))
            * pow(1.22, Double(max(0, match.awayRedCards)))
        let awayMultiplier = pow(0.72, Double(max(0, match.awayRedCards)))
            * pow(1.22, Double(max(0, match.homeRedCards)))
        return (
            max(0, home * min(max(homeMultiplier, 0.30), 2.25)),
            max(0, away * min(max(awayMultiplier, 0.30), 2.25))
        )
    }

    nonisolated static func footballProbabilityClock(
        for match: FootballFixtureMatch,
        now: Date,
        fallbackBaseMinute: Int
    ) -> FootballStatusMinuteComponents {
        if let components = footballLiveMinuteComponents(for: match, now: now) {
            return components
        }

        return FootballStatusMinuteComponents(
            baseMinute: footballLiveMinute(for: match, now: now) ?? fallbackBaseMinute,
            stoppageMinute: 0
        )
    }

    nonisolated static func footballParsedGoalValue(_ rawScore: String) -> Int? {
        let trimmed = rawScore.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }
}
