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

    func testCanceledFixtureDoesNotExposePlaceholderScore() {
        let match = makeMatch(
            id: "match-canceled",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .finished,
            statusText: "Canceled",
            homeScore: "0",
            awayScore: "0"
        )

        let display = FootballFixtureFormatter.menuBarDisplay(
            for: match,
            competitionLocalLogoURL: nil,
            homeLocalLogoURL: nil,
            awayLocalLogoURL: nil
        )

        XCTAssertTrue(match.hasInterruptedStatus)
        XCTAssertFalse(match.hasVisibleScore)
        XCTAssertEqual(FootballFixtureFormatter.calendarTitle(for: match), "BAR 🇪🇸 - 🇩🇪 BAY")
        XCTAssertFalse(display.showsScore)
    }

    func testScoreHighlightRangeFindsHomeAndAwayScoresInCalendarTitle() {
        let title = "BAR 🇪🇸 2 - 1 🇩🇪 BAY"

        let homeRange = FootballFixtureFormatter.scoreHighlightRange(in: title, side: .home)
        let awayRange = FootballFixtureFormatter.scoreHighlightRange(in: title, side: .away)

        XCTAssertEqual(homeRange.map { (title as NSString).substring(with: $0) }, "2")
        XCTAssertEqual(awayRange.map { (title as NSString).substring(with: $0) }, "1")
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
        XCTAssertTrue(display.showsScore)
        XCTAssertEqual(display.homeScore, "2")
        XCTAssertEqual(display.awayScore, "1")
        XCTAssertEqual(display.competitionLocalLogoPath, "/tmp/competition.png")
        XCTAssertEqual(display.homeLocalLogoPath, "/tmp/home.png")
        XCTAssertEqual(display.awayLocalLogoPath, "/tmp/away.png")
    }

    func testCompetitionDetailTextCollapsesRedundantYearPrefixedStage() {
        XCTAssertEqual(
            FootballFixtureFormatter.competitionDetailText(
                competitionName: "International Friendly",
                competitionStage: "2026 International Friendly"
            ),
            "International Friendly"
        )
    }

    func testCompetitionDetailTextPreservesMeaningfulStage() {
        XCTAssertEqual(
            FootballFixtureFormatter.competitionDetailText(
                competitionName: "UEFA Champions League",
                competitionStage: "Quarterfinals"
            ),
            "UEFA Champions League • Quarterfinals"
        )
    }

    func testSharedCompetitionTitleUsesSharedCompetitionDetailWhenMatchesFullyAlign() {
        let matches = [
            FootballFixtureMatch(
                id: "shared-1",
                competitionSlug: "fifa.friendly",
                competitionName: "International Friendly",
                competitionStage: nil,
                competitionLogoURL: nil,
                locationText: nil,
                startDate: Date(timeIntervalSince1970: 1_720_000_000),
                statusState: .inProgress,
                statusText: "12'",
                homeTeam: FootballTeamSummary(
                    id: "usa",
                    name: "United States",
                    abbreviation: "USA",
                    logoURL: nil,
                    countryName: "United States",
                    isNational: true
                ),
                awayTeam: FootballTeamSummary(
                    id: "por",
                    name: "Portugal",
                    abbreviation: "POR",
                    logoURL: nil,
                    countryName: "Portugal",
                    isNational: true
                ),
                homeScore: "0",
                awayScore: "1"
            ),
            FootballFixtureMatch(
                id: "shared-2",
                competitionSlug: "fifa.friendly",
                competitionName: "International Friendly",
                competitionStage: nil,
                competitionLogoURL: nil,
                locationText: nil,
                startDate: Date(timeIntervalSince1970: 1_720_003_600),
                statusState: .inProgress,
                statusText: "23'",
                homeTeam: FootballTeamSummary(
                    id: "arg",
                    name: "Argentina",
                    abbreviation: "ARG",
                    logoURL: nil,
                    countryName: "Argentina",
                    isNational: true
                ),
                awayTeam: FootballTeamSummary(
                    id: "zam",
                    name: "Zambia",
                    abbreviation: "ZAM",
                    logoURL: nil,
                    countryName: "Zambia",
                    isNational: true
                ),
                homeScore: "1",
                awayScore: "0"
            ),
        ]

        XCTAssertEqual(
            FootballFixtureFormatter.sharedCompetitionTitle(for: matches),
            "International Friendly"
        )
    }

    func testSharedCompetitionTitleFallsBackToCompetitionNameWhenStagesDiffer() {
        let quarterfinal = FootballFixtureMatch(
            id: "knockout-1",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: "Quarterfinals",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "7:00 PM",
            homeTeam: FootballTeamSummary(
                id: "bar",
                name: "Barcelona",
                abbreviation: "BAR",
                logoURL: nil,
                countryName: "Spain",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "bay",
                name: "Bayern Munich",
                abbreviation: "BAY",
                logoURL: nil,
                countryName: "Germany",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )
        let semifinal = FootballFixtureMatch(
            id: "knockout-2",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: "Semifinals",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_003_600),
            statusState: .scheduled,
            statusText: "9:00 PM",
            homeTeam: FootballTeamSummary(
                id: "psg",
                name: "PSG",
                abbreviation: "PSG",
                logoURL: nil,
                countryName: "France",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "int",
                name: "Internazionale",
                abbreviation: "INT",
                logoURL: nil,
                countryName: "Italy",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertEqual(
            FootballFixtureFormatter.sharedCompetitionTitle(for: [quarterfinal, semifinal]),
            "UEFA Champions League"
        )
    }

    func testSharedCompetitionTitleReturnsNilWhenCompetitionsDiffer() {
        let championsMatch = makeMatch(
            id: "mixed-1",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionSlug: "uefa.champions"
        )
        let leagueMatch = FootballFixtureMatch(
            id: "mixed-2",
            competitionSlug: "eng.1",
            competitionName: "Premier League",
            competitionStage: nil,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_003_600),
            statusState: .scheduled,
            statusText: "8:00 PM",
            homeTeam: FootballTeamSummary(
                id: "ars",
                name: "Arsenal",
                abbreviation: "ARS",
                logoURL: nil,
                countryName: "England",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "liv",
                name: "Liverpool",
                abbreviation: "LIV",
                logoURL: nil,
                countryName: "England",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertNil(FootballFixtureFormatter.sharedCompetitionTitle(for: [championsMatch, leagueMatch]))
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

    func testCalendarTitleUsesBlackFlagAndTBDForCompactWorldCupSlotCodes() {
        let match = FootballFixtureMatch(
            id: "match-compact-slots",
            competitionSlug: "fifa.world",
            competitionName: "FIFA World Cup",
            competitionStage: "Round of 16",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "TBD",
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
            ),
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertEqual(FootballFixtureFormatter.calendarTitle(for: match), "TBD 🏴 - 🏴 TBD")
        XCTAssertTrue(FootballFixtureFormatter.hasUnknownParticipants(in: match))
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

    func testFlagEmojiSupportsNationalTeamAliasesFromFeeds() {
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Bonaire"), "🇧🇶")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Bosnia and Herzegovina"), "🇧🇦")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "China"), "🇨🇳")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Ivory Coast"), "🇨🇮")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "IR Iran"), "🇮🇷")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Kyrgyz Republic"), "🇰🇬")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Korea Republic"), "🇰🇷")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Korea DPR"), "🇰🇵")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Macau"), "🇲🇴")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "DR Congo"), "🇨🇩")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "China PR"), "🇨🇳")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Palestine"), "🇵🇸")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Trinidad and Tobago"), "🇹🇹")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "US Virgin Islands"), "🇻🇮")
    }

    func testFlagEmojiNormalizesPunctuationAndDiacritics() {
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Cote d'Ivoire"), "🇨🇮")
        XCTAssertEqual(FootballFixtureFormatter.flagEmoji(for: "Curacao"), "🇨🇼")
    }

    func testNationalTeamFlagPrefersTeamNameWhenStoredCountryNameIsWrong() {
        let team = FootballTeamSummary(
            id: "469",
            name: "IR Iran",
            abbreviation: "IRN",
            logoURL: nil,
            countryName: "Türkiye",
            isNational: true
        )

        XCTAssertEqual(FootballFixtureFormatter.teamFlag(for: team), "🇮🇷")
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

    func testCompetitionPresetsCoverSupportedLeaguesAndUseConfiguredSuggestionWindow() {
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
            "mex.1",
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
        XCTAssertTrue(
            FootballCompetitionPreset.menuPresets.allSatisfy {
                $0.lookbackDays == FootballCompetitionPreset.suggestionWindowLookbackDays
                    && $0.lookaheadDays == FootballCompetitionPreset.suggestionWindowLookaheadDays
            }
        )
    }

    func testManagedFootballSuggestionWindowUsesFortyFiveDayLookbackAndNinetyDayLookahead() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let insidePast = calendar.date(byAdding: .day, value: -45, to: now)!
        let insideFuture = calendar.date(byAdding: .day, value: 90, to: now)!
        let outsidePast = calendar.date(byAdding: .day, value: -46, to: now)!
        let outsideFuture = calendar.date(byAdding: .day, value: 91, to: now)!

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
    }

    private func makeMatch(
        id: String,
        startDate: Date,
        actualStartDate: Date? = nil,
        statusState: FootballFixtureStatusState,
        statusText: String? = nil,
        statusDetailText: String? = nil,
        statusReliability: FootballFixtureStatusReliability = .reported,
        competitionSlug: String = "uefa.champions",
        seasonSlug: String? = nil,
        competitionNote: String? = nil,
        homeTeam: FootballTeamSummary? = nil,
        awayTeam: FootballTeamSummary? = nil,
        homeScore: String = "0",
        awayScore: String = "0"
    ) -> FootballFixtureMatch {
        FootballTestData.match(
            id: id,
            competitionSlug: competitionSlug,
            competitionName: "UEFA Champions League",
            competitionStage: nil,
            seasonSlug: seasonSlug,
            competitionNote: competitionNote,
            locationText: nil,
            startDate: startDate,
            actualStartDate: actualStartDate,
            statusState: statusState,
            statusText: statusText ?? (statusState == .inProgress ? "55'" : "7:00 PM"),
            statusDetailText: statusDetailText,
            statusReliability: statusReliability,
            homeTeam: homeTeam ?? FootballTestData.defaultClubHomeTeam,
            awayTeam: awayTeam ?? FootballTestData.defaultClubAwayTeam,
            homeScore: homeScore,
            awayScore: awayScore
        )
    }
}
