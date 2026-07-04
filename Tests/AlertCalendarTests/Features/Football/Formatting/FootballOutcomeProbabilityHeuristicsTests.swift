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

    func testFinishedMatchUsesExactFinalResult() throws {
        let match = makeMatch(
            id: "finished-home",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "FT",
            competitionSlug: "eng.1",
            homeScore: "2",
            awayScore: "1"
        )

        let probabilities = try XCTUnwrap(CalendarMonitor.footballOutcomeProbabilities(for: match))

        XCTAssertEqual(probabilities.source, FootballMatchOutcomeProbabilitySource.finalResult)
        XCTAssertEqual(probabilities.homeWin, 1, accuracy: 0.0001)
        XCTAssertEqual(probabilities.draw, 0, accuracy: 0.0001)
        XCTAssertEqual(probabilities.awayWin, 0, accuracy: 0.0001)
    }
}
