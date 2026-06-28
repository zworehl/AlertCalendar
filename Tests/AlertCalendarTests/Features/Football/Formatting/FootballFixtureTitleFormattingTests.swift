import XCTest
@testable import AlertCalendar

final class FootballFixtureTitleFormattingTests: FootballFixtureFormatterTestCase {
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
    func testDelayedLiveFixtureKeepsCurrentScoreVisible() {
        let match = makeMatch(
            id: "match-delayed-live",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .inProgress,
            statusText: "Delay",
            statusDetailText: "45'+3'",
            homeScore: "1",
            awayScore: "0"
        )

        let display = FootballFixtureFormatter.menuBarDisplay(
            for: match,
            competitionLocalLogoURL: nil,
            homeLocalLogoURL: nil,
            awayLocalLogoURL: nil
        )

        XCTAssertTrue(match.hasInterruptedStatus)
        XCTAssertTrue(match.hasVisibleScore)
        XCTAssertEqual(FootballFixtureFormatter.calendarTitle(for: match), "BAR 🇪🇸 1 - 0 🇩🇪 BAY")
        XCTAssertTrue(display.showsScore)
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
        XCTAssertFalse(display.homeLogoUsesCircularOutline)
        XCTAssertFalse(display.awayLogoUsesCircularOutline)
    }
    func testMenuBarDisplayMarksNationalTeamLogosAsCircular() {
        let match = FootballTestData.friendlyMatch(
            id: "national-badges",
            statusState: .scheduled
        )

        let display = FootballFixtureFormatter.menuBarDisplay(
            for: match,
            competitionLocalLogoURL: nil,
            homeLocalLogoURL: URL(fileURLWithPath: "/tmp/home-flag.png"),
            awayLocalLogoURL: URL(fileURLWithPath: "/tmp/away-flag.png")
        )

        XCTAssertEqual(display.homeLocalLogoPath, "/tmp/home-flag.png")
        XCTAssertEqual(display.awayLocalLogoPath, "/tmp/away-flag.png")
        XCTAssertTrue(display.homeLogoUsesCircularOutline)
        XCTAssertTrue(display.awayLogoUsesCircularOutline)
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
    func testWorldCupKnockoutSlotCodesAreUnknownParticipants() {
        for code in ["GRO", "3RD", "1I", "1L", "2J", "2K", "2L", "RD1", "RD16W5"] {
            let team = FootballTeamSummary(
                id: code.lowercased(),
                name: code,
                abbreviation: code,
                logoURL: nil,
                countryName: nil,
                isNational: true
            )

            XCTAssertTrue(FootballFixtureFormatter.isUnknownTeam(team), "\(code) should be treated as a pending knockout slot")
            XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: team), "TBD")
        }
    }
    func testWorldCupKnockoutSlotDescriptionsFromTeamCacheAreUnknownParticipants() {
        for (code, countryName) in [
            ("GRO", "Group A Winner"),
            ("SFL", "Semifinal 1 Loser"),
            ("SFW", "Semifinal 2 Winner"),
        ] {
            let team = FootballTeamSummary(
                id: code.lowercased(),
                name: code,
                abbreviation: code,
                logoURL: nil,
                countryName: countryName,
                isNational: true
            )

            XCTAssertTrue(FootballFixtureFormatter.isUnknownTeam(team), "\(countryName) should be treated as a pending knockout slot")
            XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: team), "TBD")
        }
    }
    func testResolvedNationalTeamsAreNotMistakenForKnockoutSlotsWithoutCachedCountry() {
        for (name, abbreviation, expectedIdentifier) in [
            ("Canada", "CAN", "CAN"),
            ("South Africa", "RSA", "RSA"),
            ("Portugal", "POR", "POR"),
            ("Romania", "ROU", "ROU"),
            ("Poland", "POL", "POL"),
        ] {
            let team = FootballTeamSummary(
                id: abbreviation.lowercased(),
                name: name,
                abbreviation: abbreviation,
                logoURL: nil,
                countryName: nil,
                isNational: true
            )

            XCTAssertFalse(FootballFixtureFormatter.isUnknownTeam(team), "\(name) should be treated as a resolved national team")
            XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: team), expectedIdentifier)
        }
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
    }}
