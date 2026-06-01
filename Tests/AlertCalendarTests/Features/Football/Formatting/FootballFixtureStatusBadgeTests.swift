import AppKit
import XCTest
@testable import AlertCalendar

final class FootballFixtureStatusBadgeTests: FootballFixtureFormatterTestCase {
    func testFootballStatusBadgeSupportsExtraTimeAndPenalties() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let extraTimeMatch = makeMatch(
            id: "extra-time",
            startDate: now.addingTimeInterval(-92 * 60),
            statusState: .inProgress,
            statusText: "ET",
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )
        let penaltiesMatch = makeMatch(
            id: "penalties",
            startDate: now.addingTimeInterval(-121 * 60),
            statusState: .inProgress,
            statusText: "PEN",
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )
        let fullTimeMatch = makeMatch(
            id: "full-time",
            startDate: now.addingTimeInterval(-125 * 60),
            statusState: .finished,
            statusText: "FT",
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "2",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: extraTimeMatch, now: now), "ET")
        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: penaltiesMatch, now: now), "PEN")
        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: fullTimeMatch, now: now), "FT")
    }
    func testFootballStatusBadgeShowsConfirmedExtraTimeMinute() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "extra-time-minute",
            startDate: now.addingTimeInterval(-120 * 60),
            statusState: .inProgress,
            statusText: "105'",
            statusPeriod: 4,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "ET 105'")
    }
    func testFootballStatusBadgeUsesSupplementalMinuteForExtraTimeStatus() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "extra-time-detail-minute",
            startDate: now.addingTimeInterval(-120 * 60),
            statusState: .inProgress,
            statusText: "ET",
            statusDetailText: "105'",
            statusPeriod: 4,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "ET 105'")
    }
    func testFootballStatusBadgeDoesNotInferPenaltiesAtConfirmedExtraTimeEdge() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "extra-time-edge",
            startDate: now.addingTimeInterval(-135 * 60),
            statusState: .inProgress,
            statusText: "120'",
            statusPeriod: 4,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "ET 120'")
    }
    func testFootballStatusBadgeKeepsExtraTimeStoppageBeforePenaltiesAreConfirmed() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "extra-time-stoppage",
            startDate: now.addingTimeInterval(-137 * 60),
            statusState: .inProgress,
            statusText: "120'+2'",
            statusPeriod: 4,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "ET 120'+2'")
    }
    func testFootballStatusBadgeUsesExplicitPenaltyPeriodOverExtraTimeText() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "penalty-period",
            startDate: now.addingTimeInterval(-142 * 60),
            statusState: .inProgress,
            statusText: "ET",
            statusPeriod: 5,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "PEN")
    }
    func testFootballStatusBadgeKeepsInferredExtraTimeAtPenaltyBoundary() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "inferred-extra-time-boundary",
            startDate: now.addingTimeInterval(-136 * 60),
            statusState: .inProgress,
            statusText: "",
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "ET")
    }
    func testFootballStatusBadgeInfersPenaltiesOnlyAfterConservativeBuffer() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "inferred-penalties-buffer",
            startDate: now.addingTimeInterval(-139 * 60),
            statusState: .inProgress,
            statusText: "",
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "PEN")
    }
    func testFootballStatusBadgeKeepsExtraTimeTintForMinuteBadge() {
        XCTAssertTrue(
            CalendarMonitor.footballStatusTintColor(for: "ET 105'").isEqual(NSColor.systemIndigo)
        )
    }
    func testFootballStatusBadgePrefersInterruptedStateOverReportedMinute() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let delayedMatch = makeMatch(
            id: "delay-minute",
            startDate: now.addingTimeInterval(-100 * 60),
            statusState: .inProgress,
            statusText: "Delay",
            statusDetailText: "11'",
            statusReliability: .reported
        )
        let abandonedMatch = makeMatch(
            id: "abandoned-minute",
            startDate: now.addingTimeInterval(-100 * 60),
            statusState: .finished,
            statusText: "Abandoned",
            statusDetailText: "11'",
            statusReliability: .reported
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: delayedMatch, now: now), "DELAY")
        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: abandonedMatch, now: now), "ABN")
    }
    func testInterruptedAbandonedMatchUsesReportedMinuteForCalendarDuration() {
        let match = makeMatch(
            id: "abandoned-duration",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "Abandoned",
            statusDetailText: "11'"
        )

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match), 15 * 60)
    }
    func testInterruptedDelayedMatchKeepsRegulationDurationForCalendarDuration() {
        let match = makeMatch(
            id: "delayed-duration",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .inProgress,
            statusText: "Delay",
            statusDetailText: "11'",
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Tied on aggregate",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match), 110 * 60)
    }
    func testFootballStatusBadgeUsesSoonWhenAwaitingLiveData() {
        let match = makeMatch(
            id: "awaiting-live-data",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "Starting soon",
            statusReliability: .awaitingLiveData
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match), "Soon")
        XCTAssertNil(CalendarMonitor.footballStatusWarningText(for: match))
    }
    func testFootballStatusBadgeFallsBackToInferredMinuteForReportedLiveMatch() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "reported-live-no-minute",
            startDate: now.addingTimeInterval(-40 * 60),
            statusState: .inProgress,
            statusText: "",
            statusReliability: .reported
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "40'")
    }
    func testFootballStatusBadgeUsesActualKickoffDateWhenAvailable() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "reported-live-actual-kickoff",
            startDate: now.addingTimeInterval(-40 * 60),
            actualStartDate: now.addingTimeInterval(-25 * 60),
            statusState: .inProgress,
            statusText: "",
            statusReliability: .reported
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "25'")
    }
    func testFootballStatusBadgeOverridesClearlyStaleReportedMinute() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "reported-live-stale-minute",
            startDate: now.addingTimeInterval(-100 * 60),
            statusState: .inProgress,
            statusText: "11'",
            statusReliability: .reported
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "85'")
    }
    func testFootballStatusWarningAppearsWhenLiveDataLooksDelayed() {
        let match = makeMatch(
            id: "delayed-live-data",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "Starting soon",
            statusReliability: .delayedLiveData
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match), "Soon")
        XCTAssertEqual(
            CalendarMonitor.footballStatusWarningText(for: match),
            "Kickoff time has passed, but ESPN still has not confirmed live match data for this fixture."
        )
    }
    func testGoalHighlightDetectsHomeSideScoreChange() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let previous = makeMatch(
            id: "goal-home",
            startDate: now.addingTimeInterval(-900),
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "1"
        )
        let current = makeMatch(
            id: "goal-home",
            startDate: now.addingTimeInterval(-900),
            statusState: .inProgress,
            homeScore: "2",
            awayScore: "1"
        )

        let highlight = CalendarMonitor.goalHighlight(from: previous, to: current, now: now)

        XCTAssertEqual(highlight?.matchID, "goal-home")
        XCTAssertEqual(highlight?.scoringSide, .home)
        XCTAssertEqual(highlight?.hasBeenShownInMenuBar, false)
    }
    func testGoalHighlightIgnoresMultiSideScoreCorrections() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let previous = makeMatch(
            id: "goal-correction",
            startDate: now.addingTimeInterval(-900),
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "0"
        )
        let current = makeMatch(
            id: "goal-correction",
            startDate: now.addingTimeInterval(-900),
            statusState: .inProgress,
            homeScore: "2",
            awayScore: "1"
        )

        XCTAssertNil(CalendarMonitor.goalHighlight(from: previous, to: current, now: now))
    }}
