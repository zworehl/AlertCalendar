import XCTest
@testable import AlertCalendar

final class FootballFixtureFormatterTests: XCTestCase {
    func testCalendarTitleUsesFlagsForScheduledFixtures() {
        let match = FootballFixtureMatch(
            id: "match-1",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: nil,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "7:00 PM",
            homeTeam: FootballTeamSummary(
                id: "83",
                name: "Barcelona",
                abbreviation: "BAR",
                logoURL: nil,
                countryName: "Spain",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "361",
                name: "Newcastle United",
                abbreviation: "NEW",
                logoURL: nil,
                countryName: "England",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )

        let title = FootballFixtureFormatter.calendarTitle(for: match)

        XCTAssertTrue(title.hasPrefix("BAR 🇪🇸"))
        XCTAssertTrue(title.contains(" - "))
        XCTAssertTrue(title.contains(FootballFixtureFormatter.flagEmoji(for: "England")))
        XCTAssertTrue(title.hasSuffix("NEW"))
    }

    func testCalendarTitleUsesScoresWhenFixtureIsLive() {
        let match = FootballFixtureMatch(
            id: "match-2",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: nil,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .inProgress,
            statusText: "55'",
            homeTeam: FootballTeamSummary(
                id: "83",
                name: "Barcelona",
                abbreviation: "BAR",
                logoURL: nil,
                countryName: "Spain",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "132",
                name: "Bayern Munich",
                abbreviation: "BAY",
                logoURL: nil,
                countryName: "Germany",
                isNational: false
            ),
            homeScore: "2",
            awayScore: "1"
        )

        XCTAssertEqual(FootballFixtureFormatter.calendarTitle(for: match), "BAR 🇪🇸 2 - 1 🇩🇪 BAY")
    }

    func testMenuBarDisplayKeepsFixtureMetadata() {
        let match = FootballFixtureMatch(
            id: "match-badge",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: nil,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .inProgress,
            statusText: "55'",
            homeTeam: FootballTeamSummary(
                id: "83",
                name: "Barcelona",
                abbreviation: "BAR",
                logoURL: nil,
                countryName: "Spain",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "132",
                name: "Bayern Munich",
                abbreviation: "BAY",
                logoURL: nil,
                countryName: "Germany",
                isNational: false
            ),
            homeScore: "2",
            awayScore: "1"
        )

        let display = FootballFixtureFormatter.menuBarDisplay(
            for: match,
            competitionLocalLogoURL: URL(fileURLWithPath: "/tmp/competition.png"),
            homeLocalLogoURL: URL(fileURLWithPath: "/tmp/home.png"),
            awayLocalLogoURL: URL(fileURLWithPath: "/tmp/away.png")
        )

        XCTAssertEqual(display.homeAbbreviation, "BAR")
        XCTAssertEqual(display.awayAbbreviation, "BAY")
        XCTAssertEqual(display.competitionLocalLogoPath, "/tmp/competition.png")
        XCTAssertEqual(display.homeLocalLogoPath, "/tmp/home.png")
        XCTAssertEqual(display.awayLocalLogoPath, "/tmp/away.png")
    }

    func testManagedFixtureReferenceRoundTripsThroughURL() {
        let reference = ManagedFootballFixtureReference(
            matchID: "12345",
            competitionSlug: "uefa.champions"
        )

        let parsed = ManagedFootballFixtureReference.parse(from: reference.url)

        XCTAssertEqual(parsed, reference)
    }

    func testCalendarTitleUsesBlackFlagAndTBDForUnknownKnockoutSlots() {
        let match = FootballFixtureMatch(
            id: "match-3",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: "Semifinals",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "TBD",
            homeTeam: FootballTeamSummary(
                id: "17631",
                name: "Quarterfinal 1 Winner",
                abbreviation: "QFW1",
                logoURL: nil,
                countryName: nil,
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "17629",
                name: "Quarterfinal 2 Winner",
                abbreviation: "QFW2",
                logoURL: nil,
                countryName: nil,
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertEqual(FootballFixtureFormatter.calendarTitle(for: match), "TBD 🏴 - 🏴 TBD")
    }

    func testClubIdentifiersAreTrimmedToThreeLetters() {
        let team = FootballTeamSummary(
            id: "1",
            name: "Palmeiras",
            abbreviation: "PALM",
            logoURL: nil,
            countryName: "Brazil",
            isNational: false
        )

        XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: team), "PAL")
    }

    func testNationalTeamIdentifiersUseFIFACode() {
        let team = FootballTeamSummary(
            id: "439",
            name: "Costa Rica",
            abbreviation: "CRC",
            logoURL: nil,
            countryName: "Costa Rica",
            isNational: true
        )

        XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: team), "CRC")
    }

    func testCalendarIdentityKeyIgnoresFlagsAndLiveScore() {
        XCTAssertEqual(
            FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: "CAP 🇧🇷 1 - 0 🇧🇷 BOT"),
            "CAP|BOT"
        )
        XCTAssertEqual(
            FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: "DOM 🇩🇴 - 🇨🇺 CUB"),
            "DOM|CUB"
        )
    }

    func testCalendarIdentityKeyForMatchUsesDisplayedTeamIdentifiers() {
        let match = FootballFixtureMatch(
            id: "match-identity",
            competitionSlug: "fifa.friendly",
            competitionName: "International Friendly",
            competitionStage: nil,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "7:00 PM",
            homeTeam: FootballTeamSummary(
                id: "439",
                name: "Costa Rica",
                abbreviation: "CRC",
                logoURL: nil,
                countryName: "Costa Rica",
                isNational: true
            ),
            awayTeam: FootballTeamSummary(
                id: "1",
                name: "Palmeiras",
                abbreviation: "PALM",
                logoURL: nil,
                countryName: "Brazil",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertEqual(FootballFixtureFormatter.calendarIdentityKey(for: match), "CRC|PAL")
    }

    func testCompetitionPresetsCoverSupportedLeaguesAndUseThirtyDayWindow() {
        let expectedSlugs: Set<String> = [
            "eng.1",
            "esp.1",
            "bra.1",
            "ita.1",
            "ger.1",
            "fra.1",
            "por.1",
            "arg.1",
            "ned.1",
            "col.1",
            "usa.1",
            "fifa.world",
            "fifa.friendly",
            "uefa.champions",
            "uefa.europa",
            "uefa.super_cup",
            "uefa.euro",
            "conmebol.america",
            "conmebol.libertadores",
            "fifa.cwc",
            "concacaf.gold",
            "caf.nations",
            "afc.asian.cup",
        ]

        XCTAssertEqual(Set(FootballCompetitionPreset.menuPresets.map(\.slug)), expectedSlugs)
        XCTAssertTrue(FootballCompetitionPreset.menuPresets.allSatisfy { $0.lookbackDays == 30 && $0.lookaheadDays == 30 })
    }

    func testManagedFootballSuggestionWindowStaysWithinThirtyDays() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let insidePast = calendar.date(byAdding: .day, value: -29, to: now)!
        let insideFuture = calendar.date(byAdding: .day, value: 29, to: now)!
        let outsidePast = calendar.date(byAdding: .day, value: -31, to: now)!
        let outsideFuture = calendar.date(byAdding: .day, value: 31, to: now)!

        XCTAssertTrue(CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: insidePast, now: now, calendar: calendar))
        XCTAssertTrue(CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: insideFuture, now: now, calendar: calendar))
        XCTAssertFalse(CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: outsidePast, now: now, calendar: calendar))
        XCTAssertFalse(CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: outsideFuture, now: now, calendar: calendar))
    }

    func testKickoffStatusTextUsesWeekdayWhenFixtureIsWithinAWeek() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .day, value: 3, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballKickoffStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            formatter.string(from: startDate)
        )
    }

    func testKickoffStatusTextUsesTodayWhenFixtureIsLaterTheSameDay() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .hour, value: 5, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballKickoffStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Today \(formatter.string(from: startDate))"
        )
    }

    func testKickoffStatusTextUsesTomorrowWhenFixtureIsNextDay() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .day, value: 1, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballKickoffStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Tomorrow \(formatter.string(from: startDate))"
        )
    }

    func testKickoffStatusTextUsesDateWhenFixtureIsMoreThanAWeekAway() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .day, value: 10, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballKickoffStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            formatter.string(from: startDate)
        )
    }

    func testStartedStatusTextUsesStartedPrefixForFinishedFixtures() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .hour, value: -3, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballStartedStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Started \(formatter.string(from: startDate))"
        )
    }

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

    func testScheduledSecondLegKeepsExtraTimeBuffer() {
        let match = makeMatch(
            id: "second-leg",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionSlug: "uefa.champions",
            seasonSlug: "quarterfinals",
            competitionNote: "2nd Leg - Tied on aggregate"
        )

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match), 150 * 60)
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

        XCTAssertEqual(CalendarMonitor.approximateFootballMatchDuration(for: match, now: now), 120 * 60)
    }

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

    private func makeMatch(
        id: String,
        startDate: Date,
        statusState: FootballFixtureStatusState,
        statusText: String? = nil,
        statusReliability: FootballFixtureStatusReliability = .reported,
        competitionSlug: String = "uefa.champions",
        seasonSlug: String? = nil,
        competitionNote: String? = nil,
        homeScore: String = "0",
        awayScore: String = "0"
    ) -> FootballFixtureMatch {
        FootballFixtureMatch(
            id: id,
            competitionSlug: competitionSlug,
            competitionName: "UEFA Champions League",
            competitionStage: nil,
            seasonSlug: seasonSlug,
            competitionNote: competitionNote,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: startDate,
            statusState: statusState,
            statusText: statusText ?? (statusState == .inProgress ? "55'" : "7:00 PM"),
            statusReliability: statusReliability,
            homeTeam: FootballTeamSummary(
                id: "83",
                name: "Barcelona",
                abbreviation: "BAR",
                logoURL: nil,
                countryName: "Spain",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "132",
                name: "Bayern Munich",
                abbreviation: "BAY",
                logoURL: nil,
                countryName: "Germany",
                isNational: false
            ),
            homeScore: homeScore,
            awayScore: awayScore
        )
    }
}
