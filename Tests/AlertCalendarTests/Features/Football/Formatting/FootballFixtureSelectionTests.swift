import XCTest
@testable import AlertCalendar

final class FootballFixtureSelectionTests: FootballFixtureFormatterTestCase {
    func testLiveAndNextDayMatchesOnlyIncludeLiveAndUpcomingWindow() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let live = makeMatch(
            id: "live",
            startDate: calendar.date(byAdding: .hour, value: -1, to: now)!,
            statusState: .inProgress
        )
        let soon = makeMatch(
            id: "soon",
            startDate: calendar.date(byAdding: .hour, value: 6, to: now)!,
            statusState: .scheduled
        )
        let later = makeMatch(
            id: "later",
            startDate: calendar.date(byAdding: .hour, value: 60, to: now)!,
            statusState: .scheduled
        )
        let finished = makeMatch(
            id: "finished",
            startDate: calendar.date(byAdding: .hour, value: -2, to: now)!,
            statusState: .finished
        )

        XCTAssertEqual(
            CalendarMonitor.liveAndNextDayMatches(from: [later, finished, soon, live], now: now, calendar: calendar).map(\.id),
            ["live", "soon"]
        )
    }
    func testLiveAndNextDayMatchesKeepFixturesAwaitingDelayedLiveData() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let delayed = makeMatch(
            id: "delayed",
            startDate: calendar.date(byAdding: .minute, value: -20, to: now)!,
            statusState: .scheduled,
            statusText: "Starting soon",
            statusReliability: .delayedLiveData
        )
        let upcoming = makeMatch(
            id: "upcoming",
            startDate: calendar.date(byAdding: .hour, value: 6, to: now)!,
            statusState: .scheduled
        )

        XCTAssertEqual(
            CalendarMonitor.liveAndNextDayMatches(from: [upcoming, delayed], now: now, calendar: calendar).map(\.id),
            ["delayed", "upcoming"]
        )
        XCTAssertEqual(CalendarMonitor.footballStatusWarningSummary(for: delayed), "Live data fetch delayed")
    }
    func testLiveAndNextDayMatchesDeduplicateRepeatedMatchIDs() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let duplicateLive = makeMatch(
            id: "duplicate-live",
            startDate: calendar.date(byAdding: .minute, value: -30, to: now)!,
            statusState: .inProgress
        )
        let upcoming = makeMatch(
            id: "upcoming",
            startDate: calendar.date(byAdding: .hour, value: 4, to: now)!,
            statusState: .scheduled
        )

        XCTAssertEqual(
            CalendarMonitor.liveAndNextDayMatches(
                from: [duplicateLive, upcoming, duplicateLive],
                now: now,
                calendar: calendar
            ).map(\.id),
            ["duplicate-live", "upcoming"]
        )
    }
    func testLiveAndNextDayMatchesExcludeFixturesBeyondTwentyFourHours() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let insideWindow = makeMatch(
            id: "inside",
            startDate: calendar.date(byAdding: .hour, value: 23, to: now)!,
            statusState: .scheduled
        )
        let outsideWindow = makeMatch(
            id: "outside",
            startDate: calendar.date(byAdding: .hour, value: 25, to: now)!,
            statusState: .scheduled
        )

        XCTAssertEqual(
            CalendarMonitor.liveAndNextDayMatches(
                from: [outsideWindow, insideWindow],
                now: now,
                calendar: calendar
            ).map(\.id),
            ["inside"]
        )
    }
    func testLiveAndNextDayMatchesExcludeFixturesWithUnknownParticipants() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let known = makeMatch(
            id: "known",
            startDate: calendar.date(byAdding: .hour, value: 4, to: now)!,
            statusState: .scheduled
        )
        let unknown = makeMatch(
            id: "unknown",
            startDate: calendar.date(byAdding: .hour, value: 3, to: now)!,
            statusState: .scheduled,
            homeTeam: FootballTeamSummary(
                id: "17631",
                name: "Quarterfinal 1 Winner",
                abbreviation: "QFW1",
                logoURL: nil,
                countryName: nil,
                isNational: false
            )
        )

        XCTAssertEqual(
            CalendarMonitor.liveAndNextDayMatches(
                from: [unknown, known],
                now: now,
                calendar: calendar
            ).map(\.id),
            ["known"]
        )
    }
    func testLiveAndNextDayMatchesExcludeFixturesWithCompactPlaceholderSlotParticipants() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let known = makeMatch(
            id: "known",
            startDate: calendar.date(byAdding: .hour, value: 4, to: now)!,
            statusState: .scheduled
        )
        let placeholder = makeMatch(
            id: "placeholder",
            startDate: calendar.date(byAdding: .hour, value: 2, to: now)!,
            statusState: .scheduled,
            competitionSlug: "fifa.world",
            homeTeam: FootballTeamSummary(
                id: "ga2",
                name: "GA2",
                abbreviation: "GA2",
                logoURL: nil,
                countryName: nil,
                isNational: true
            ),
            awayTeam: FootballTeamSummary(
                id: "rd3",
                name: "RD3",
                abbreviation: "RD3",
                logoURL: nil,
                countryName: nil,
                isNational: true
            )
        )

        XCTAssertEqual(
            CalendarMonitor.liveAndNextDayMatches(
                from: [placeholder, known],
                now: now,
                calendar: calendar
            ).map(\.id),
            ["known"]
        )
    }
    func testLiveAndNextDayMatchesIncludeResolvedWorldCupKnockoutFixtureWithoutCachedCountryDetails() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let match = makeMatch(
            id: "canada-south-africa",
            startDate: calendar.date(byAdding: .hour, value: 4, to: now)!,
            statusState: .scheduled,
            competitionSlug: "fifa.world",
            homeTeam: FootballTeamSummary(
                id: "467",
                name: "South Africa",
                abbreviation: "RSA",
                logoURL: nil,
                countryName: nil,
                isNational: true
            ),
            awayTeam: FootballTeamSummary(
                id: "206",
                name: "Canada",
                abbreviation: "CAN",
                logoURL: nil,
                countryName: nil,
                isNational: true
            )
        )

        XCTAssertEqual(
            CalendarMonitor.liveAndNextDayMatches(
                from: [match],
                now: now,
                calendar: calendar
            ).map(\.id),
            ["canada-south-africa"]
        )
    }
    func testUpcomingManagedFootballMatchesIncludeLiveAndFutureButExcludeFinished() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let live = makeMatch(
            id: "live",
            startDate: calendar.date(byAdding: .hour, value: -1, to: now)!,
            statusState: .inProgress
        )
        let upcoming = makeMatch(
            id: "upcoming",
            startDate: calendar.date(byAdding: .hour, value: 8, to: now)!,
            statusState: .scheduled
        )
        let later = makeMatch(
            id: "later",
            startDate: calendar.date(byAdding: .day, value: 3, to: now)!,
            statusState: .scheduled
        )
        let delayed = makeMatch(
            id: "delayed",
            startDate: calendar.date(byAdding: .minute, value: -20, to: now)!,
            statusState: .scheduled,
            statusText: "Starting soon",
            statusReliability: .delayedLiveData
        )
        let finished = makeMatch(
            id: "finished",
            startDate: calendar.date(byAdding: .hour, value: -2, to: now)!,
            statusState: .finished
        )

        XCTAssertEqual(
            CalendarMonitor.upcomingManagedFootballMatches(from: [finished, live, later, upcoming, delayed], now: now).map(\.id),
            ["live", "delayed", "upcoming", "later"]
        )
    }
    func testUpcomingManagedFootballMatchesDeduplicateRepeatedMatchIDs() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let duplicateLive = makeMatch(
            id: "duplicate-live",
            startDate: calendar.date(byAdding: .minute, value: -30, to: now)!,
            statusState: .inProgress
        )
        let upcoming = makeMatch(
            id: "upcoming",
            startDate: calendar.date(byAdding: .hour, value: 4, to: now)!,
            statusState: .scheduled
        )

        XCTAssertEqual(
            CalendarMonitor.upcomingManagedFootballMatches(
                from: [upcoming, duplicateLive, duplicateLive],
                now: now
            ).map(\.id),
            ["duplicate-live", "upcoming"]
        )
    }
    func testUpcomingManagedFootballMatchesExcludeFixturesWithUnknownParticipants() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let known = makeMatch(
            id: "known",
            startDate: calendar.date(byAdding: .hour, value: 6, to: now)!,
            statusState: .scheduled
        )
        let unknown = makeMatch(
            id: "unknown",
            startDate: calendar.date(byAdding: .hour, value: 5, to: now)!,
            statusState: .scheduled,
            awayTeam: FootballTeamSummary(
                id: "17629",
                name: "Quarterfinal 2 Winner",
                abbreviation: "QFW2",
                logoURL: nil,
                countryName: nil,
                isNational: false
            )
        )

        XCTAssertEqual(
            CalendarMonitor.upcomingManagedFootballMatches(
                from: [unknown, known],
                now: now
            ).map(\.id),
            ["known"]
        )
    }

    func testFootballMatchesEligibleForAutoAddOnlyIncludeNewPlayableEnabledMatches() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let enabledSlug = FootballCompetitionPreset.championsLeague.slug

        let live = makeMatch(
            id: "live",
            startDate: calendar.date(byAdding: .minute, value: -30, to: now)!,
            statusState: .inProgress,
            competitionSlug: enabledSlug
        )
        let upcoming = makeMatch(
            id: "upcoming",
            startDate: calendar.date(byAdding: .hour, value: 5, to: now)!,
            statusState: .scheduled,
            competitionSlug: enabledSlug
        )
        let managed = makeMatch(
            id: "managed",
            startDate: calendar.date(byAdding: .hour, value: 6, to: now)!,
            statusState: .scheduled,
            competitionSlug: enabledSlug
        )
        let finished = makeMatch(
            id: "finished",
            startDate: calendar.date(byAdding: .hour, value: -2, to: now)!,
            statusState: .finished,
            competitionSlug: enabledSlug
        )
        let disabledCompetition = makeMatch(
            id: "disabled",
            startDate: calendar.date(byAdding: .hour, value: 7, to: now)!,
            statusState: .scheduled,
            competitionSlug: FootballCompetitionPreset.majorLeagueSoccer.slug
        )
        let unknownParticipant = makeMatch(
            id: "unknown",
            startDate: calendar.date(byAdding: .hour, value: 8, to: now)!,
            statusState: .scheduled,
            competitionSlug: enabledSlug,
            awayTeam: FootballTeamSummary(
                id: "17629",
                name: "Quarterfinal 2 Winner",
                abbreviation: "QFW2",
                logoURL: nil,
                countryName: nil,
                isNational: false
            )
        )

        XCTAssertEqual(
            CalendarMonitor.footballMatchesEligibleForAutoAdd(
                [upcoming, finished, disabledCompetition, live, unknownParticipant, managed],
                enabledCompetitionSlugs: [enabledSlug],
                managedMatchIDs: ["managed"],
                now: now
            ).map(\.id),
            ["live", "upcoming"]
        )
    }

    func testNormalizedFootballAutoAddCompetitionSlugsKeepKnownMenuOrder() {
        XCTAssertEqual(
            CalendarMonitor.normalizedFootballAutoAddCompetitionSlugs([
                "not-real",
                FootballCompetitionPreset.championsLeague.slug,
                " ",
                FootballCompetitionPreset.majorLeagueSoccer.slug,
                FootballCompetitionPreset.championsLeague.slug,
            ]),
            [
                FootballCompetitionPreset.majorLeagueSoccer.slug,
                FootballCompetitionPreset.championsLeague.slug,
            ]
        )
    }
}
