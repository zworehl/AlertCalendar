import XCTest
@testable import AlertCalendar

final class FootballFixtureDurationAndContextTests: FootballFixtureFormatterTestCase {
    func testScheduledSecondLegKeepsExtraTimeBuffer() {
        let match = makeMatch(
            id: "second-leg",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Tied on aggregate"
        )

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match), 140 * 60)
    }
    func testApproximateFootballMatchEndDateAddsFiveMinuteMargin() {
        let startDate = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "scheduled-margin",
            startDate: startDate,
            statusState: .scheduled
        )

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: startDate),
            startDate.addingTimeInterval((110 + 5) * 60)
        )
    }
    func testApproximateFootballMatchEndDateUsesActualKickoffWithFiveMinuteMargin() {
        let scheduledStart = Date(timeIntervalSince1970: 1_720_000_000)
        let actualKickoff = scheduledStart.addingTimeInterval(7 * 60)
        let match = makeMatch(
            id: "actual-kickoff-margin",
            startDate: scheduledStart,
            actualStartDate: actualKickoff,
            statusState: .finished
        )

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: scheduledStart),
            actualKickoff.addingTimeInterval((110 + 5) * 60)
        )
    }
    func testLiveSecondHalfEndDateUsesReportedMinute() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-second-half-end",
            startDate: now.addingTimeInterval(-95 * 60),
            statusState: .inProgress,
            statusText: "80'",
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: now),
            roundedLiveEndDate(now.addingTimeInterval((10 + 5) * 60))
        )
    }
    func testLiveStoppageTimeEndDateKeepsOnlyShortTail() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-stoppage-end",
            startDate: now.addingTimeInterval(-110 * 60),
            statusState: .inProgress,
            statusText: "90'+4'",
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: now),
            roundedLiveEndDate(now.addingTimeInterval(5 * 60))
        )
    }
    func testLiveHalfTimeEndDateUsesRemainingBreak() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-half-time-end",
            startDate: now.addingTimeInterval(-50 * 60),
            statusState: .inProgress,
            statusText: "HT",
            competitionSlug: "eng.1"
        )

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: now),
            roundedLiveEndDate(now.addingTimeInterval((10 + 45 + 5) * 60))
        )
    }
    func testLiveKnockoutAtLevelKeepsExtraTimeEndReserve() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-extra-time-reserve-end",
            startDate: now.addingTimeInterval(-95 * 60),
            statusState: .inProgress,
            statusText: "80'",
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Tied on aggregate",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: now),
            roundedLiveEndDate(now.addingTimeInterval((10 + 5 + 35) * 60))
        )
    }
    func testLivePenaltyShootoutEndDateUsesShortRollingEstimate() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-penalty-end",
            startDate: now.addingTimeInterval(-130 * 60),
            statusState: .inProgress,
            statusText: "PEN",
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: now),
            roundedLiveEndDate(now.addingTimeInterval(15 * 60))
        )
    }
    func testLiveConfirmedExtraTimeAt120KeepsPenaltyReserve() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-extra-time-edge-end",
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

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: now),
            roundedLiveEndDate(now.addingTimeInterval((5 + 15) * 60))
        )
    }
    func testLiveEndDateUsesInferredMinuteWhenReportedMinuteIsStale() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-stale-minute-end",
            startDate: now.addingTimeInterval(-100 * 60),
            statusState: .inProgress,
            statusText: "11'",
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: match, now: now),
            roundedLiveEndDate(now.addingTimeInterval((5 + 5) * 60))
        )
    }
    func testLiveEndDateRoundingAvoidsHeartbeatChurn() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "live-rounded-end",
            startDate: now.addingTimeInterval(-95 * 60),
            statusState: .inProgress,
            statusText: "80'",
            competitionSlug: "eng.1",
            homeScore: "1",
            awayScore: "0"
        )

        let initialEndDate = CalendarMonitor.approximateFootballMatchEndDate(for: match, now: now)
        let heartbeatEndDate = CalendarMonitor.approximateFootballMatchEndDate(
            for: match,
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(initialEndDate, heartbeatEndDate)
    }
    func testFinishedMatchVisibilityUsesEstimatedEndLookbackWindow() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "finished-lookback",
            startDate: now.addingTimeInterval(-3 * 24 * 60 * 60),
            statusState: .finished,
            statusText: "FT"
        )

        XCTAssertTrue(
            CalendarMonitor.shouldDisplayFinishedFootballMatch(
                match,
                now: now,
                lookbackDays: 4
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldDisplayFinishedFootballMatch(
                match,
                now: now,
                lookbackDays: 2
            )
        )
    }
    func testFinishedMatchVisibilityUsesActualKickoffWhenAvailable() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let scheduledStart = now.addingTimeInterval(-4 * 60 * 60)
        let actualKickoff = scheduledStart.addingTimeInterval(30 * 60)
        let match = makeMatch(
            id: "finished-actual-lookback",
            startDate: scheduledStart,
            actualStartDate: actualKickoff,
            statusState: .finished,
            statusText: "FT"
        )

        XCTAssertTrue(
            CalendarMonitor.shouldDisplayFinishedFootballMatch(
                match,
                now: now,
                lookbackDays: 1
            )
        )
    }
    func testFinishedMatchPreservingKnownTimingContextKeepsActualKickoffAndLongerStatusPeriod() {
        let scheduledStart = Date(timeIntervalSince1970: 1_720_000_000)
        let actualKickoff = scheduledStart.addingTimeInterval(7 * 60)
        let previousMatch = makeMatch(
            id: "finished-preserve",
            startDate: scheduledStart,
            actualStartDate: actualKickoff,
            statusState: .inProgress,
            statusText: "118'",
            statusPeriod: 4,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "1",
            awayScore: "1"
        )
        let finishedMatch = makeMatch(
            id: "finished-preserve",
            startDate: scheduledStart,
            statusState: .finished,
            statusText: "FT",
            statusPeriod: 2,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "2",
            awayScore: "1"
        )

        let resolvedMatch = CalendarMonitor.footballMatchPreservingKnownTimingContext(
            finishedMatch,
            previousMatch: previousMatch
        )

        XCTAssertEqual(resolvedMatch.actualStartDate, actualKickoff)
        XCTAssertEqual(resolvedMatch.statusPeriod, 4)
        XCTAssertEqual(
            CalendarMonitor.approximateFootballMatchEndDate(for: resolvedMatch, now: scheduledStart),
            actualKickoff.addingTimeInterval((140 + 5) * 60)
        )
    }
    func testLateOneGoalLeadFallsBackToRegulationBuffer() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "late-lead",
            startDate: now.addingTimeInterval(-80 * 60),
            statusState: .inProgress,
            statusText: "80'",
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Tied on aggregate",
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match, now: now), 110 * 60)
    }
    func testLateSecondLegKeepsExtraTimeBufferWhenAggregateIsStillLevel() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "late-aggregate-level",
            startDate: now.addingTimeInterval(-80 * 60),
            statusState: .inProgress,
            statusText: "80'",
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Atlético Madrid lead 2-0 on aggregate",
            seriesSummary: FootballFixtureSeriesSummary(
                legNumber: 2,
                legLabel: "2nd Leg",
                seriesTitle: "Quarterfinals",
                totalLegs: 2,
                homeAggregateScore: 2,
                awayAggregateScore: 2
            ),
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match, now: now), 140 * 60)
    }
    func testFootballStatusBadgeKeepsStoppageMinuteUntilExtraTimeIsConfirmed() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeMatch(
            id: "aggregate-level-et",
            startDate: now.addingTimeInterval(-92 * 60),
            statusState: .inProgress,
            statusText: "90'+2'",
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Atlético Madrid lead 2-0 on aggregate",
            seriesSummary: FootballFixtureSeriesSummary(
                legNumber: 2,
                legLabel: "2nd Leg",
                seriesTitle: "Quarterfinals",
                totalLegs: 2,
                homeAggregateScore: 2,
                awayAggregateScore: 2
            ),
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertEqual(CalendarMonitor.footballStatusBadgeText(for: match, now: now), "90'+2'")
    }
    func testFixtureContextTextPrefersStructuredSeriesSummary() {
        let match = makeMatch(
            id: "fixture-context",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionNote: "2nd Leg - Atlético Madrid lead 2-0 on aggregate",
            seriesSummary: FootballFixtureSeriesSummary(
                legNumber: 2,
                legLabel: "2nd Leg",
                seriesTitle: "Quarterfinals",
                totalLegs: 2,
                homeAggregateScore: 2,
                awayAggregateScore: 0
            )
        )

        XCTAssertEqual(FootballFixtureFormatter.fixtureContextText(for: match), "2nd Leg • Agg 2-0")
    }
    func testMenuBarAggregateTextUsesParenthesizedAggregateScore() {
        let match = makeMatch(
            id: "fixture-context-compact",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionNote: "2nd Leg - Atlético Madrid lead 2-0 on aggregate",
            seriesSummary: FootballFixtureSeriesSummary(
                legNumber: 2,
                legLabel: "2nd Leg",
                seriesTitle: "Quarterfinals",
                totalLegs: 2,
                homeAggregateScore: 2,
                awayAggregateScore: 0
            )
        )

        XCTAssertEqual(FootballFixtureFormatter.menuBarAggregateText(for: match), "(2 - 0)")
    }
    func testMenuBarAggregateTextParsesNumericAggregateFromCompetitionNote() {
        let match = makeMatch(
            id: "fixture-context-compact-level",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionNote: "2nd Leg - Atlético Madrid lead 3-1 on aggregate"
        )

        XCTAssertEqual(FootballFixtureFormatter.menuBarAggregateText(for: match), "(3 - 1)")
    }
    func testFinishedExtraTimeMatchUsesStatusPeriodForCalendarDuration() {
        let match = makeMatch(
            id: "finished-extra-time",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "FT",
            statusPeriod: 4,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "2",
            awayScore: "1"
        )

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match), 140 * 60)
    }
    func testFinishedPenaltyMatchUsesStatusPeriodForCalendarDuration() {
        let match = makeMatch(
            id: "finished-penalties",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "FT",
            statusPeriod: 5,
            competitionSlug: "uefa.super_cup",
            seasonSlug: "final",
            competitionNote: "Final",
            homeScore: "5",
            awayScore: "4"
        )

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match), 150 * 60)
    }
    func testFootballRefreshIntervalTracksMatchUrgency() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let live = makeMatch(
            id: "live-refresh",
            startDate: now.addingTimeInterval(-20 * 60),
            statusState: .inProgress
        )
        let nearKickoff = makeMatch(
            id: "near-refresh",
            startDate: now.addingTimeInterval(10 * 60),
            statusState: .scheduled
        )
        let upcoming = makeMatch(
            id: "upcoming-refresh",
            startDate: now.addingTimeInterval(3 * 60 * 60),
            statusState: .scheduled
        )
        let distant = makeMatch(
            id: "distant-refresh",
            startDate: now.addingTimeInterval(3 * 24 * 60 * 60),
            statusState: .scheduled
        )

        XCTAssertEqual(
            CalendarMonitor.footballRefreshInterval(for: [live], now: now),
            CalendarMonitor.footballActiveRefreshInterval
        )
        XCTAssertEqual(
            CalendarMonitor.footballRefreshInterval(for: [nearKickoff], now: now),
            CalendarMonitor.footballManagedSyncInterval
        )
        XCTAssertEqual(
            CalendarMonitor.footballRefreshInterval(for: [upcoming], now: now),
            CalendarMonitor.footballUpcomingRefreshInterval
        )
        XCTAssertEqual(
            CalendarMonitor.footballRefreshInterval(for: [distant], now: now),
            CalendarMonitor.footballIdleRefreshInterval
        )
    }
    func testFootballMatchPreservingKnownTimingContextKeepsResolvedTeamDetails() {
        let startDate = Date(timeIntervalSince1970: 1_720_000_000)
        let previousMatch = FootballTestData.match(
            id: "preserve-team-details",
            competitionSlug: "usa.1",
            competitionName: "MLS",
            locationText: "BMO Field, Toronto, Canada",
            startDate: startDate,
            statusState: .scheduled,
            homeTeam: FootballTestData.clubTeam(
                id: "1845",
                name: "Toronto FC",
                abbreviation: "TOR",
                countryName: "Canada"
            ).withResolvedDetails(
                countryName: "Canada",
                isNational: false,
                logoURL: URL(string: "https://example.com/toronto.png")
            ),
            awayTeam: FootballTestData.clubTeam(
                id: "1850",
                name: "Inter Miami CF",
                abbreviation: "MIA",
                countryName: "United States"
            ).withResolvedDetails(
                countryName: "United States",
                isNational: false,
                logoURL: URL(string: "https://example.com/miami.png")
            )
        )
        let lightweightMatch = FootballTestData.match(
            id: "preserve-team-details",
            competitionSlug: "usa.1",
            competitionName: "MLS",
            locationText: nil,
            startDate: startDate,
            statusState: .scheduled,
            homeTeam: FootballTeamSummary(
                id: "1845",
                name: "Toronto FC",
                abbreviation: "TOR",
                logoURL: nil,
                countryName: nil,
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "1850",
                name: "Inter Miami CF",
                abbreviation: "MIA",
                logoURL: nil,
                countryName: nil,
                isNational: false
            )
        )

        let resolvedMatch = CalendarMonitor.footballMatchPreservingKnownTimingContext(
            lightweightMatch,
            previousMatch: previousMatch
        )

        XCTAssertEqual(resolvedMatch.locationText, "BMO Field, Toronto, Canada")
        XCTAssertEqual(resolvedMatch.homeTeam.countryName, "Canada")
        XCTAssertEqual(resolvedMatch.awayTeam.countryName, "United States")
        XCTAssertEqual(resolvedMatch.homeTeam.logoURL, URL(string: "https://example.com/toronto.png"))
        XCTAssertEqual(resolvedMatch.awayTeam.logoURL, URL(string: "https://example.com/miami.png"))
    }

    private func roundedLiveEndDate(_ date: Date) -> Date {
        let interval = CalendarMonitor.footballLiveEndDateRoundingInterval
        let roundedTime = ceil(date.timeIntervalSince1970 / interval) * interval
        return Date(timeIntervalSince1970: roundedTime)
    }
}
