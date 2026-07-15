import XCTest
@testable import AlertCalendar

final class FootballOutcomeProbabilityHeuristicsTests: FootballFixtureFormatterTestCase {
    func testScheduledLeagueMatchUsesRegulationOutcomeScope() throws {
        let match = makeMatch(
            id: "league-scheduled",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionSlug: "eng.1"
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match))

        XCTAssertEqual(probabilities.source, FootballMatchOutcomeProbabilitySource.heuristic)
        XCTAssertEqual(probabilities.scope, FootballMatchOutcomeProbabilityScope.regulationTime)
        XCTAssertGreaterThan(probabilities.draw, 0.20)
        XCTAssertGreaterThan(probabilities.homeWin, probabilities.awayWin)
    }

    func testScheduledSecondLegUsesExtraTimePossibleOutcomeScope() throws {
        let match = makeMatch(
            id: "second-leg-scheduled",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Tied on aggregate"
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match))

        XCTAssertEqual(probabilities.scope, FootballMatchOutcomeProbabilityScope.extraTimePossible)
        XCTAssertGreaterThan(probabilities.draw, 0.25)
    }

    func testLateRegulationLeadStronglyFavorsLeadingTeamInNinetyMinuteMatch() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "late-league-lead",
            startDate: now.addingTimeInterval(-95 * 60),
            statusState: .inProgress,
            statusText: "80'",
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0"
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match, now: now))

        XCTAssertEqual(probabilities.scope, FootballMatchOutcomeProbabilityScope.regulationTime)
        XCTAssertGreaterThan(probabilities.homeWin, 0.75)
        XCTAssertLessThan(probabilities.awayWin, 0.10)
    }

    func testKnockoutStoppageTimeLevelMatchKeepsNinetyMinuteDrawScopeUntilExtraTimeConfirmed() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "stoppage-level-second-leg",
            startDate: now.addingTimeInterval(-107 * 60),
            statusState: .inProgress,
            statusText: "90'+2'",
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Tied on aggregate",
            homeScore: "1",
            awayScore: "1"
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match, now: now))

        XCTAssertEqual(probabilities.scope, FootballMatchOutcomeProbabilityScope.extraTimePossible)
        XCTAssertGreaterThan(probabilities.draw, 0.80)
        XCTAssertGreaterThan(probabilities.homeWin, 0)
        XCTAssertGreaterThan(probabilities.awayWin, 0)
    }

    func testConfirmedExtraTimeUsesDecisiveOutcomeScopeWithoutDrawSegment() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "extra-time-level",
            startDate: now.addingTimeInterval(-120 * 60),
            statusState: .inProgress,
            statusText: "105'",
            statusPeriod: 3,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match, now: now))

        XCTAssertEqual(probabilities.scope, FootballMatchOutcomeProbabilityScope.decisiveResult)
        XCTAssertEqual(probabilities.draw, 0, accuracy: 0.0001)
        XCTAssertEqual(probabilities.homeWin + probabilities.awayWin, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(probabilities.homeWin, 0.35)
        XCTAssertGreaterThan(probabilities.awayWin, 0.35)
    }

    func testExtraTimeIntervalLeavesOnlySecondPeriodAndItsAddedTime() {
        let match = makeMatch(
            id: "extra-time-interval",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .inProgress,
            statusText: "HT",
            statusPeriod: 3,
            competitionSlug: "fifa.world",
            seasonSlug: "semifinals",
            competitionNote: "Semifinal",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(
            CalendarMonitor.footballExpectedExtraTimeMinutesRemaining(
                match: match,
                baseMinute: 105,
                stoppageMinute: 0
            ),
            16.2,
            accuracy: 0.0001
        )
    }

    func testFinishedMatchUsesExactFinalResult() throws {
        let match = makeMatch(
            id: "finished-home",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "FT",
            competitionSlug: "eng.1",
            homeScore: "2",
            awayScore: "1",
            officialWinner: .home
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match))

        XCTAssertEqual(probabilities.source, FootballMatchOutcomeProbabilitySource.finalResult)
        XCTAssertEqual(probabilities.scope, .regulationTime)
        XCTAssertEqual(probabilities.homeWin, 1, accuracy: 0.0001)
        XCTAssertEqual(probabilities.draw, 0, accuracy: 0.0001)
        XCTAssertEqual(probabilities.awayWin, 0, accuracy: 0.0001)
    }

    func testStoppageTimeScoreConditionsLiveMarketOdds() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let england = FootballTestData.nationalTeam(
            id: "eng",
            name: "England",
            abbreviation: "ENG",
            countryName: "England"
        )
        let argentina = FootballTestData.nationalTeam(
            id: "arg",
            name: "Argentina",
            abbreviation: "ARG",
            countryName: "Argentina"
        )
        let market = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.45,
                draw: 0.16,
                awayWin: 0.39,
                source: .liveMarketOdds,
                scope: .regulationTime,
                providerName: "Example Live Odds",
                observedAt: now,
                observedHomeScore: 1,
                observedAwayScore: 2,
                observedStatusPeriod: 2
            )
        )
        let match = makeMatch(
            id: "world-cup-semifinal-stoppage",
            startDate: now.addingTimeInterval(-111 * 60),
            statusState: .inProgress,
            statusText: "90'+6'",
            statusPeriod: 2,
            competitionSlug: "fifa.world",
            seasonSlug: "semifinals",
            competitionNote: "Semifinal",
            homeTeam: england,
            awayTeam: argentina,
            homeScore: "1",
            awayScore: "2",
            outcomeProbabilities: market
        )

        let probabilities = try XCTUnwrap(
            CalendarMonitor.footballOutcomeProbabilities(for: match, now: now)
        )

        XCTAssertGreaterThan(probabilities.awayWin, 0.90)
        XCTAssertLessThan(probabilities.homeWin, probabilities.draw)
        XCTAssertGreaterThan(probabilities.draw, 0)
        XCTAssertEqual(probabilities.source, .heuristic)
        XCTAssertNotEqual(probabilities.homeWin, market.homeWin, accuracy: 0.0001)
        XCTAssertNotEqual(probabilities.awayWin, market.awayWin, accuracy: 0.0001)
    }

    func testPlausibleFreshLiveMarketIsNotConditionedTwice() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let baselineMatch = makeMatch(
            id: "plausible-live-baseline",
            startDate: now.addingTimeInterval(-75 * 60),
            statusState: .inProgress,
            statusText: "60'",
            statusPeriod: 2,
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0"
        )
        let projected = try XCTUnwrap(
            CalendarMonitor.footballOutcomeProbabilities(for: baselineMatch, now: now)
        )
        let live = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: projected.homeWin,
                draw: projected.draw,
                awayWin: projected.awayWin,
                source: .liveMarketOdds,
                scope: .regulationTime,
                providerName: "Coherent Live",
                observedAt: now,
                observedHomeScore: 1,
                observedAwayScore: 0,
                observedStatusPeriod: 2
            )
        )
        let liveMatch = makeMatch(
            id: "plausible-live",
            startDate: baselineMatch.startDate,
            statusState: .inProgress,
            statusText: "60'",
            statusPeriod: 2,
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0",
            outcomeProbabilities: live
        )

        let probabilities = try XCTUnwrap(
            CalendarMonitor.footballOutcomeProbabilities(for: liveMatch, now: now)
        )

        XCTAssertEqual(probabilities.source, .liveMarketOdds)
        XCTAssertEqual(probabilities.homeWin, live.homeWin, accuracy: 0.000_001)
        XCTAssertEqual(probabilities.draw, live.draw, accuracy: 0.000_001)
        XCTAssertEqual(probabilities.awayWin, live.awayWin, accuracy: 0.000_001)
    }

    func testLeaderProbabilityIncreasesAsSecondHalfStoppageTimeElapses() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let early = makeMatch(
            id: "stoppage-early",
            startDate: now.addingTimeInterval(-106 * 60),
            statusState: .inProgress,
            statusText: "90'+1'",
            statusPeriod: 2,
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "2"
        )
        let late = makeMatch(
            id: "stoppage-late",
            startDate: now.addingTimeInterval(-111 * 60),
            statusState: .inProgress,
            statusText: "90'+6'",
            statusPeriod: 2,
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "2"
        )

        let earlyProbabilities = try XCTUnwrap(
            CalendarMonitor.footballOutcomeProbabilities(for: early, now: now)
        )
        let lateProbabilities = try XCTUnwrap(
            CalendarMonitor.footballOutcomeProbabilities(for: late, now: now)
        )

        XCTAssertGreaterThan(lateProbabilities.awayWin, earlyProbabilities.awayWin)
        XCTAssertLessThan(lateProbabilities.draw, earlyProbabilities.draw)
        XCTAssertLessThan(lateProbabilities.homeWin, earlyProbabilities.homeWin)
    }

    func testInterruptedMatchDoesNotInventLiveProbabilities() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "suspended",
            startDate: now.addingTimeInterval(-70 * 60),
            statusState: .inProgress,
            statusText: "Suspended",
            statusDetailText: "63'",
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertNil(CalendarMonitor.footballOutcomeProbabilities(for: match, now: now))
    }

    func testTiedFinishedShootoutDoesNotBecomeCertainDraw() {
        let match = makeMatch(
            id: "finished-shootout",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "FT-Pens",
            statusPeriod: 5,
            competitionSlug: "fifa.world",
            seasonSlug: "final",
            competitionNote: "Argentina win on penalties",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertNil(CalendarMonitor.footballOutcomeProbabilities(for: match))
    }

    func testActiveShootoutHidesEstimateWithoutKickOrder() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "active-shootout",
            startDate: now.addingTimeInterval(-145 * 60),
            statusState: .inProgress,
            statusText: "PEN",
            statusPeriod: 5,
            competitionSlug: "fifa.world",
            seasonSlug: "semifinals",
            competitionNote: "Semifinal",
            homeScore: "1",
            awayScore: "1",
            homeShootoutScore: 4,
            awayShootoutScore: 2
        )

        XCTAssertNil(CalendarMonitor.footballOutcomeProbabilities(for: match, now: now))
    }

    func testFinishedResultIgnoresDegradedLiveReliability() throws {
        let match = makeMatch(
            id: "finished-delayed-feed",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "FT",
            statusReliability: .delayedLiveData,
            competitionSlug: "eng.1",
            homeScore: "2",
            awayScore: "1"
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match))

        XCTAssertEqual(probabilities.homeWin, 1, accuracy: 0.0001)
    }

    func testFinishedShootoutUsesOfficialWinnerWhenVisibleScoreIsLevel() throws {
        let match = makeMatch(
            id: "finished-shootout-winner",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "FT-Pens",
            statusPeriod: 5,
            competitionSlug: "fifa.world",
            seasonSlug: "final",
            competitionNote: "Argentina win on penalties",
            homeScore: "1",
            awayScore: "1",
            officialWinner: .away,
            homeShootoutScore: 4,
            awayShootoutScore: 3
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match))

        XCTAssertEqual(probabilities.scope, .decisiveResult)
        XCTAssertEqual(probabilities.homeWin, 0, accuracy: 0.0001)
        XCTAssertEqual(probabilities.draw, 0, accuracy: 0.0001)
        XCTAssertEqual(probabilities.awayWin, 1, accuracy: 0.0001)
    }

    func testFinishedShootoutFallsBackToShootoutScore() throws {
        let match = makeMatch(
            id: "finished-shootout-score",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "FT-Pens",
            statusPeriod: 5,
            competitionSlug: "fifa.world",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "2",
            awayScore: "2",
            homeShootoutScore: 5,
            awayShootoutScore: 4
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match))

        XCTAssertEqual(probabilities.homeWin, 1, accuracy: 0.0001)
        XCTAssertEqual(probabilities.draw, 0, accuracy: 0.0001)
        XCTAssertEqual(probabilities.awayWin, 0, accuracy: 0.0001)
    }

    func testRedCardMovesProbabilityAgainstDismissedTeam() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let baseline = makeMatch(
            id: "level-baseline",
            startDate: now.addingTimeInterval(-75 * 60),
            statusState: .inProgress,
            statusText: "60'",
            statusPeriod: 2,
            competitionSlug: "eng.1",
            homeScore: "0",
            awayScore: "0"
        )
        let dismissedHome = makeMatch(
            id: "level-home-red",
            startDate: now.addingTimeInterval(-75 * 60),
            statusState: .inProgress,
            statusText: "60'",
            statusPeriod: 2,
            competitionSlug: "eng.1",
            homeScore: "0",
            awayScore: "0",
            homeRedCards: 1
        )

        let baselineProbabilities = try XCTUnwrap(
            CalendarMonitor.footballOutcomeProbabilities(for: baseline, now: now)
        )
        let dismissedProbabilities = try XCTUnwrap(
            CalendarMonitor.footballOutcomeProbabilities(for: dismissedHome, now: now)
        )

        XCTAssertLessThan(dismissedProbabilities.homeWin, baselineProbabilities.homeWin)
        XCTAssertGreaterThan(dismissedProbabilities.awayWin, baselineProbabilities.awayWin)
    }

    func testLiveOddsExpireAndAreInvalidatedByScoreChanges() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-odds-fingerprint",
            startDate: now.addingTimeInterval(-75 * 60),
            statusState: .inProgress,
            statusText: "60'",
            statusPeriod: 2,
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0"
        )
        let expired = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.45,
                draw: 0.30,
                awayWin: 0.25,
                source: .liveMarketOdds,
                scope: .regulationTime,
                providerName: "Expired Live",
                observedAt: now.addingTimeInterval(-CalendarMonitor.footballLiveOddsMaximumAge - 1),
                observedHomeScore: 1,
                observedAwayScore: 0,
                observedStatusPeriod: 2
            )
        )
        let beforeGoal = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.45,
                draw: 0.30,
                awayWin: 0.25,
                source: .liveMarketOdds,
                scope: .regulationTime,
                providerName: "Before Goal Live",
                observedAt: now,
                observedHomeScore: 0,
                observedAwayScore: 0,
                observedStatusPeriod: 2
            )
        )
        let matching = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.70,
                draw: 0.20,
                awayWin: 0.10,
                source: .liveMarketOdds,
                scope: .regulationTime,
                providerName: "Current Live",
                observedAt: now,
                observedHomeScore: 1,
                observedAwayScore: 0,
                observedStatusPeriod: 2
            )
        )

        XCTAssertNil(CalendarMonitor.footballUsableOutcomeProbabilities(expired, for: match, now: now))
        XCTAssertNil(CalendarMonitor.footballUsableOutcomeProbabilities(beforeGoal, for: match, now: now))
        XCTAssertEqual(
            CalendarMonitor.footballUsableOutcomeProbabilities(matching, for: match, now: now)?.providerName,
            "Current Live"
        )
    }
}
